# Testing in a VM

The image is tested in a libvirt VM (`qemu:///system`) with UEFI **Secure Boot** and an emulated **TPM 2.0**, as close as possible to the target hardware.

## Prerequisites

On the host, you need libvirt with QEMU, `virt-install`, `virt-viewer`, the `swtpm` TPM emulator and the OVMF UEFI firmware:

Debian

```sh
sudo apt install libvirt-daemon-system virtinst virt-viewer swtpm swtpm-tools ovmf
sudo adduser "$USER" libvirt   # then log out and back in
```

Ubuntu

```sh
sudo apt install libvirt-daemon-system virtinst virt-viewer swtpm swtpm-tools ovmf
sudo usermod -aG libvirt "$USER"   # then log out and back in
```

Arch Linux

```sh
sudo pacman -S libvirt qemu-full virt-install virt-viewer swtpm edk2-ovmf dnsmasq
sudo systemctl enable --now libvirtd.service
sudo virsh net-autostart default && sudo virsh net-start default
sudo usermod -aG libvirt "$USER"   # then log out and back in
```

`dnsmasq` is needed by the libvirt `default` network (DHCP for `just vm-ssh`).

NixOS
    
In `configuration.nix`, then `sudo nixos-rebuild switch` and log out and back in (NOT SURE OF THIS ONE :33):

```nix
virtualisation.libvirtd = {
    enable = true;
    qemu.swtpm.enable = true;   # TPM 2.0 emulator
};
environment.systemPackages = with pkgs; [ virt-manager virt-viewer ];  # virt-manager provides virt-install
users.users.<your-user>.extraGroups = [ "libvirtd" ];  # the group is "libvirtd" on NixOS
```

The OVMF firmware shipped with QEMU (including the Secure Boot variant) is available by default. On NixOS releases older than 25.11, also set `virtualisation.libvirtd.qemu.ovmf.packages = [ pkgs.OVMFFull.fd ];`.

| Component | Role |
|---|---|
| libvirt + QEMU, `virt-install` | VM management |
| `virt-viewer` | graphical console (`just vm-gui`) |
| `swtpm` | TPM 2.0 emulator |
| OVMF (`ovmf`, `edk2-ovmf`) | UEFI firmware with Secure Boot support |

`just vm-create` asks libvirt (`virsh domcapabilities`) whether the TPM emulator and a Secure Boot firmware are available before creating the VM, so the check works on every distribution.

You also need an image in `mkosi.output/` (see [Building the image](build.md)) and an SSH key pair (`CCBD_SSH_KEY`, default `~/.ssh/id_ed25519`).

## Commands

| Command | Action |
|---|---|
| `just vm-create` | (re)create the VM from the latest image; the first-boot wizard opens in a window |
| `just vm-create no-firstboot` | same, first-boot answers pre-filled (hostname, locale, keymap, timezone) |
| `just vm-console` | serial console, starts the VM if needed (`Ctrl-]` to exit) |
| `just vm-gui` | graphical console in virt-viewer |
| `just vm-ssh` | SSH as `root` |
| `just vm-destroy` | delete the VM, its UEFI variables and its TPM state |

`just vm-create` always starts from a fresh state: it destroys the previous VM and works on a copy of the image in `~/.vm/`, so the build output stays untouched. Your public SSH key is injected as a systemd credential (SMBIOS), not built into the image.

## Secure Boot and TPM2

### Firmware in setup mode

The VM starts with Secure Boot **enabled** but **no keys enrolled** (OVMF "setup mode", no Microsoft keys). On first boot:

1. systemd-boot finds the project keys on the ESP (`/loader/keys/auto/`), placed there by mkosi at build time;
2. it enrolls them (PK, KEK, db) in the UEFI variables;
3. the VM reboots by itself; from then on, only binaries signed with `mkosi.key` are accepted.

### Emulated TPM

The VM has a TPM 2.0 (`tpm-crb` model) emulated by `swtpm` and managed by libvirt. Its state is kept between VM reboots and deleted by `just vm-destroy`, so each new VM starts with an empty TPM.

## Checking the VM

Follow the first boot (key enrollment, then the automatic reboot):

```sh
just vm-create no-firstboot
just vm-console
```

Then, in the VM (`just vm-ssh`):

```sh
bootctl status | grep -i "secure boot"   # Secure Boot: enabled (user)
systemd-analyze has-tpm2                 # yes
ls -l /dev/tpmrm0                        # TPM resource manager
systemd-analyze pcrs                     # PCRs 0-7 and 11 not zero
```

### An unsigned image is refused

Corrupt the UKI on the ESP so that its signature no longer matches, then reboot:

```sh
f=$(ls "$(bootctl -p)"/EFI/Linux/*.efi)
dd if=/dev/urandom of="$f" bs=1 count=16 seek=$((5*1024*1024)) conv=notrunc
systemctl reboot
```

On the serial console, the firmware refuses to load the kernel (*Security Violation* / *Access Denied*). Run `just vm-create` again to get a working VM.

## Troubleshooting

`systemd-analyze has-tpm2` answers `partial`
:   A line starting with `-` shows what is missing. `-libtss2-…`: a TPM2 library is missing from the image (`mkosi.images/core/mkosi.conf.d/04-tpm2.conf`). `-firmware` or `-driver`: the VM has no TPM, check the `--tpm` option of `virt-install`.

`bootctl status` shows `Secure Boot: setup`
:   The keys were not enrolled: check that the build signed the image (signing steps in the log in `logs/`) and that `mkosi.key` / `mkosi.crt` existed on the build machine.

`just vm-create` fails with `TPM émulé indisponible` or `Firmware UEFI secure boot indisponible`
:   libvirt finds no TPM emulator or no Secure Boot firmware: install the host prerequisites listed above, then restart libvirt (`sudo systemctl restart libvirtd`) so that it detects them.
