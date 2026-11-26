# Building the image

The image is built with [mkosi](https://github.com/systemd/mkosi) (version 27 or later). All commands go through the `Justfile`: run `just` alone to list them.

Two build locations are supported, producing the same image:

| Location | Command | Where mkosi runs |
|---|---|---|
| Local (default) | `just build` | in a privileged Docker container (`env/Dockerfile`) |
| Remote build server | `just build srv` | directly on the server, over SSH |

## Prerequisites

Local (Docker)

    - [`just`](https://github.com/casey/just)
    - Docker, with permission to run privileged containers

    mkosi itself is not needed on the host: it is installed in the `ccbdos-build` image, rebuilt automatically when `env/Dockerfile` changes.

Remote server

    - `just`, `rsync`, `zstd` on the workstation
    - On the server: mkosi 27 or later, `rsync`, `zstd`
    - An SSH alias for the server in `~/.ssh/config` (default name: `ccbd`)

### Local settings

Per-user settings are read from environment variables, or from a `.env` file at the repository root (ignored by git):

```sh
CCBD_REMOTE=ccbd                  # SSH alias of the build server
CCBD_SSH_KEY=~/.ssh/id_ed25519    # key injected into the VM (the .pub must exist)
```

## Secure Boot signing keys

The UKI and systemd-boot are signed for UEFI Secure Boot (`[Validation] SecureBoot=yes` in `mkosi.conf`). The build needs a key pair at the repository root:

- `mkosi.key`: private key
- `mkosi.crt`: X.509 certificate

These files are **never committed** (see `.gitignore`) and are **not sent** by `just sync`. Generate them once on each machine that builds:

Local (Docker)

```sh
just docker-image
docker run --rm -v "$PWD":/work ccbdos-build genkey
sudo chown "$(id -u):$(id -g)" mkosi.key mkosi.crt
```

Remote server

```sh
just sync
ssh ccbd 'cd ccbdos && ls mkosi.key mkosi.crt 2>/dev/null || mkosi genkey'
```

The keys stay on the server and survive later `just sync` runs (files ignored by git are neither sent nor deleted).

!!! warning "Development keys only"
    These self-signed keys are for development and VM testing. Each build machine has its own keys, so a local image and a server image are not signed by the same key.

## Building

Local (Docker)

```sh
just build
```

Previous images in `mkosi.output/` are deleted, then the build runs in the container. Files created by the container are given back to the current user at the end.

Remote server

```sh
just build srv   # sync + build on the server
just fetch       # download the latest server image
```

`just build srv` sends the working tree with `just sync` (without `.git` or ignored files), then builds in `~/ccbdos` on the server. `just fetch` compresses the image with zstd for the transfer, downloads it into `mkosi.output/` and updates the local `mkosi.version`.

Each build gets a new version (`mkosi.bump`, format `YY.MMDD.HHMMSS`), written to `mkosi.version`. The disk image is:

```text
mkosi.output/CCBDos_<version>_x86-64.raw
```

The full build log is saved with a timestamp in `logs/`.

## Image structure

| Image | Configuration | Content |
|---|---|---|
| `core` | `mkosi.images/core/` | base system shared by the disk image and the extensions (directory tree) |
| main | `mkosi.conf` | bootable disk image: kernel, systemd-boot, signed UKI |

The `core` image is built with `WithRecommends=no`: a dependency that a package only *recommends* must be listed explicitly (e.g. the `libtss2-*` libraries used by systemd for the TPM2, in `04-tpm2.conf`).

## Cleaning up

```sh
just clean
```

Deletes `mkosi.output/`, the package cache and the tools tree. The signing keys are kept.

## Next step

[Test the image in a VM](vm.md).
