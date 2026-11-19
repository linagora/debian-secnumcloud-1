# Build CCBDos : sur le serveur 'ccbd' de TELECOM, ou en local via Docker.
# 'just' (sans argument) liste les commandes.
#
# Reglages propres a chacun : variables d'environnement, ou fichier .env local (ignore par git)
#   CCBD_REMOTE=ccbd                  alias SSH du serveur de build
#   CCBD_SSH_KEY=~/.ssh/id_ed25519    cle SSH injectee dans la VM (la .pub doit exister)

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load

# libvirt (raccourci de commandes classiques)
virsh_c  := "--connect=qemu:///system"
vm_name  := "os-ccbdos"
vm_dir   := home_dir() / ".vm"
vm_ram   := "4096"
vm_cpus  := "4"
vm_disk  := "16G"

# Réponses à systemd-firstboot en mode no-firstboot (credentials systemd passés à la VM)
# Permet de passer la partie setup du firstboot
fb_hostname := "ccbdos"
fb_locale   := "C.UTF-8"
fb_keymap   := "fr"
fb_timezone := "Europe/Paris"

# SSH : la clé publique est injectée dans la VM à sa création (credential systemd), pas dans l'image
ssh_key  := env("CCBD_SSH_KEY", home_dir() / ".ssh/id_ed25519")
# VM recréée à chaque fois : on n'enregistre pas sa clé d'hôte
ssh_opt  := "-i " + ssh_key + " -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR"

# Serveur -- variables
remote := env("CCBD_REMOTE", "ccbd")   # alias SSH défini dans ~/.ssh/config
rdir   := "ccbdos"                      # dossier de travail dans le home du serveur

# Docker
image  := "ccbdos-build"
docker := "docker run --rm --privileged -v \"$PWD\":/work"

out    := "mkosi.output"
stamp  := `date +%F_%H-%M-%S`

# Profile mkosi par defaut : une cible (cloudimg | baremetal), plus ",dev" pour le debug
profile := env("CCBD_PROFILE", "cloudimg")

[private]
default:
    @just --list

# Build de l'image : where = docker (défaut) ou srv (serveur ccbd a TELECOM)
[group('build')]
build profiles=profile where="docker":
    just build-{{where}} {{profiles}}

# --- Serveur ---------------------------------------------------------------

# Envoie le dossier de travail sur le serveur (sans .git ni fichiers ignorés par git)
[group('build')]
sync:
    rsync -az --delete --exclude .git --filter=':- .gitignore' ./ {{remote}}:{{rdir}}/

# Build sur le serveur (images précédentes supprimées), log horodaté en local
[private]
build-srv profiles: sync
    mkdir -p logs
    ssh {{remote}} 'cd {{rdir}} && rm -rf {{out}} && mkdir {{out}} && mkosi --profile={{profiles}} -B -f build' 2>&1 | tee "logs/{{stamp}}_build-srv.log"

# Télécharge le dernier build serveur (image compressée en zstd pour le transfert)
[group('build')]
fetch:
    #!/usr/bin/env bash
    set -euo pipefail
    v=$(ssh {{remote}} 'cat {{rdir}}/mkosi.version')
    echo "Version : $v"
    ssh {{remote}} "cd {{rdir}}/{{out}} && for f in *_${v}_*.raw; do zstd -T0 -3 -f -q \"\$f\"; done"
    mkdir -p {{out}}
    rsync -a --info=progress2 --exclude '*.raw' "{{remote}}:{{rdir}}/{{out}}/*_${v}_*" {{out}}/
    for f in {{out}}/*_${v}_*.raw.zst; do zstd -d -f -q --rm "$f"; done
    echo "$v" > mkosi.version
    ls -lsh {{out}}/*_${v}_*

# --- Docker ----------------------------------------------------------------

# Image Docker de build (instantané si env/Dockerfile n'a pas changé)
[private]
docker-image:
    docker build -t {{image}} env/

# Build en local dans Docker (images précédentes supprimées), log horodaté
[private]
build-docker profiles: docker-image
    mkdir -p logs
    docker run --rm -v "$PWD":/work --entrypoint rm {{image}} -rf {{out}}
    mkdir {{out}}
    {{docker}} {{image}} --profile={{profiles}} -B -f build 2>&1 | tee "logs/{{stamp}}_build-docker.log"
    docker run --rm -v "$PWD":/work --entrypoint chown {{image}} -R "$(id -u):$(id -g)" {{out}} mkosi.version .mkosi-private

# Shell dans le conteneur de build, pour déboguer
[group('build')]
shell: docker-image
    {{docker}} -it --entrypoint bash {{image}}

# Supprime sorties, cache et outillage locaux (créés en root par le conteneur)
[group('build')]
clean: docker-image
    docker run --rm -v "$PWD":/work --entrypoint rm {{image}} -rf {{out}} mkosi.cache mkosi.tools mkosi.tools.manifest .mkosi-private

# --- libvirt ---------------------------------------------------------------

# (Re)crée et démarre la VM depuis le dernier build : mode = firstboot (questions, défaut) ou no-firstboot (prérempli)
[group('vm')]
vm-create mode="firstboot":
    #!/usr/bin/env bash
    set -euo pipefail
    [[ "{{mode}}" == firstboot || "{{mode}}" == no-firstboot ]] || { echo "Mode inconnu '{{mode}}' : firstboot ou no-firstboot" >&2; exit 1; }
    img="{{out}}/CCBDos_$(cat mkosi.version 2>/dev/null || true)_x86-64.raw"
    [[ -f "$img" ]] || { echo "Aucune image dans {{out}} : lancer 'just build' ou 'just fetch'" >&2; exit 1; }
    echo "Image : $img"
    just vm-destroy
    # Copie de travail dans ~/.vm : l'image de build reste intacte
    mkdir -p {{vm_dir}}
    cp --sparse=always "$img" {{vm_dir}}/{{vm_name}}.raw
    truncate -s {{vm_disk}} {{vm_dir}}/{{vm_name}}.raw
    # Credentials systemd transmis via SMBIOS : clé SSH toujours, réponses de firstboot en mode no-firstboot
    creds=("ssh.authorized_keys.root=$(cat {{ssh_key}}.pub)")
    if [[ "{{mode}}" == no-firstboot ]]; then
        creds+=("system.hostname={{fb_hostname}}" "firstboot.locale={{fb_locale}}"
                "firstboot.keymap={{fb_keymap}}" "firstboot.timezone={{fb_timezone}}")
    fi
    sysinfo="type=smbios"
    for i in "${!creds[@]}"; do sysinfo+=",oemStrings.entry$i=io.systemd.credential:${creds[$i]}"; done
    virt-install {{virsh_c}} \
        --import \
        --name {{vm_name}} \
        --vcpus {{vm_cpus}} \
        --ram {{vm_ram}} \
        --machine q35 \
        --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
        --disk "path={{vm_dir}}/{{vm_name}}.raw,format=raw,bus=virtio" \
        --os-variant debian13 \
        --network network=default \
        --graphics spice \
        --video virtio \
        --channel spicevmc \
        --channel unix,target.type=virtio,target.name=org.qemu.guest_agent.0 \
        --console pty,target_type=serial \
        --sysinfo "$sysinfo" \
        --noautoconsole
    if [[ "{{mode}}" == firstboot ]]; then
        echo "VM {{vm_name}} démarrée : l'assistant de premier démarrage s'affiche dans la fenêtre"
        just vm-gui
    else
        echo "VM {{vm_name}} démarrée : 'just vm-console' ou 'just vm-ssh' pour s'y connecter"
    fi

# Ouvre l'écran de la VM dans une fenêtre virt-viewer (détachée du terminal)
[group('vm')]
vm-gui:
    #!/usr/bin/env bash
    set -euo pipefail
    virsh {{virsh_c}} dominfo {{vm_name}} &>/dev/null || { echo "Pas de VM {{vm_name}} : lancer 'just vm-create'" >&2; exit 1; }
    if command -v virt-viewer &>/dev/null; then viewer=(virt-viewer)
    else viewer=(nix shell nixpkgs#virt-viewer --command virt-viewer); fi
    setsid -f "${viewer[@]}" {{virsh_c}} --wait {{vm_name}} &>/dev/null

# Ouvre la console série de la VM, en la démarrant si elle est arrêtée (Ctrl-] pour sortir)
[group('vm')]
vm-console:
    #!/usr/bin/env bash
    set -euo pipefail
    virsh {{virsh_c}} dominfo {{vm_name}} &>/dev/null || { echo "Pas de VM {{vm_name}} : lancer 'just vm-create'" >&2; exit 1; }
    [[ $(virsh {{virsh_c}} domstate {{vm_name}}) == running ]] || virsh {{virsh_c}} start {{vm_name}}
    exec virsh {{virsh_c}} console {{vm_name}}

# Se connecte en SSH (root) à la VM, via son adresse sur le réseau libvirt "default"
[group('vm')]
vm-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh --quiet {{virsh_c}} domifaddr {{vm_name}} --source lease | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
    [[ -n "$ip" ]] || { echo "Pas d'adresse IP pour {{vm_name}} : VM démarrée ? (just vm-create)" >&2; exit 1; }
    exec ssh {{ssh_opt}} root@"$ip"

# Arrête et supprime la VM (définition, variables EFI et disque dans ~/.vm)
[group('vm')]
vm-destroy:
    #!/usr/bin/env bash
    set -euo pipefail
    if virsh {{virsh_c}} dominfo {{vm_name}} &>/dev/null; then
        virsh {{virsh_c}} destroy {{vm_name}} &>/dev/null || true
        virsh {{virsh_c}} undefine {{vm_name}} --nvram
    fi
    rm -f {{vm_dir}}/{{vm_name}}.raw
