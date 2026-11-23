# Security design

This page describes how the image protects itself: what is trusted, what can be modified, and what is not covered yet.

!!! warning "Work in progress"
    This page describes the design introduced by pull requests #9 (profiles), #13 (signed dm-verity root), #15 (`/var` partition) and #17 (read-only `/etc`), which are still open. It does not match `main` until they are merged.

## Goals

The system is an immutable image: every machine runs exactly the operating system that was built and signed, and anything a machine changes is kept apart from it.

| Goal                                      | How                                                                              |
| ----------------------------------------- | -------------------------------------------------------------------------------- |
| Detect any modification of the system     | The root filesystem is checked block by block by dm-verity, with a signed root hash. |
| Prevent changes to the system at runtime  | The root filesystem, including `/usr` and `/etc`, is mounted read-only.          |
| Isolate machine state from the image      | All writable data lives in a separate `/var` partition, created on the machine.  |
| Give each machine its own identity        | No machine ID, SSH host key or local setting is shipped in the image.            |

## Disk layout

| Partition         | Size                  | Content                                                        | Protection                           |
| ----------------- | --------------------- | -------------------------------------------------------------- | ------------------------------------ |
| ESP               | 512 MB                | `systemd-boot` and the unified kernel image (UKI)              | None (`esp=unprotected`)             |
| `root`            | 3 GB                  | The operating system (ext4)                                    | Read-only, verified by dm-verity     |
| `root-verity`     | 128 MB                | dm-verity hash tree of `root`                                  | Used for verification                |
| `root-verity-sig` | Small                 | Signature of the root hash                                     | Signed with the build key            |
| `var`             | Rest of the disk (≥ 1 GB) | Machine state: `/var`, `/home`, `/root`, mutable `/etc` entries | Writable, not encrypted              |

The first four partitions are produced by the build (`mkosi.repart/`). The `var` partition is not shipped: `systemd-repart` creates it on the target disk at first boot (`usr/lib/repart.d/40-var.conf`). The `root` partition size is fixed so that a second slot can be added later for A/B updates.

## Signed, read-only root

The root partition is protected by [dm-verity](https://docs.kernel.org/admin-guide/device-mapper/verity.html):

- at build time, mkosi computes a hash tree of the `root` partition and signs its root hash with the build key (`mkosi.key` / `mkosi.crt`);
- at boot, the kernel command line sets `root=dissect` and an image policy, `systemd.image_policy=esp=unprotected:root=signed:swap=unprotected+absent:=ignore`. systemd only mounts a root partition that has a valid verity signature, and ignores any other partition type;
- every block read from `root` is checked against the hash tree. A modified block causes a read error instead of returning altered data. Corrupting 8 MB of the root partition prevents it from being mounted (tested in #13).

The root filesystem is mounted read-only (`ro`): `/usr` and `/etc` cannot be modified at runtime, even by root.

## Read-only `/etc` and `/var/etc`

`/etc` is part of the verified root, so it is read-only too. A few entries must stay writable for the system to work. These entries are replaced at build time by symbolic links to `/var/etc`:

```text
/etc/hostname  ->  /var/etc/hostname
/etc/hosts     ->  /var/etc/hosts
...
```

- The links themselves are part of the signed root: a machine cannot redirect anything that was not redirected at build time.
- The list of writable entries is `usr/lib/tmpfiles.d/01-var-etc.conf`. Their default content is stored in `/usr/share/factory/var/etc/` and copied to `/var/etc` at boot if missing.
- `/etc/machine-id` points to `/var/lib/dbus/machine-id`, and `/etc/resolv.conf` to the `systemd-resolved` stub in `/run`.
- The build fails (`finalize-tmpfiles-etc`) if a package ships a tmpfiles.d rule that would create something in `/etc` without a redirection. A new writable entry therefore has to be declared on purpose.
- The services that change these settings (`systemd-hostnamed`, `systemd-timedated`, `systemd-localed`, `systemd-firstboot`) write to `/var/etc`, through the `SYSTEMD_ETC_*` variables and `ReadWritePaths=/var/etc`.

Everything else in `/etc` is fixed by the image. As a consequence, tools that write to `/etc/passwd`, `/etc/shadow` or `/etc/group` (`passwd`, `useradd`) do not work.

## `/var`: the only writable area

- `/var` is mounted from the initrd (`systemd.mount-extra=PARTLABEL=CCBDos-var:/var:ext4:x-initrd.mount`), so the links to `/var/etc` work from the very start of the system.
- `/home` and `/root` are bind mounts of `/var/home` and `/var/roothome`: there is no separate home partition.
- The system journal is persistent and limited to 1 GB.
- The partition is declared with `FactoryReset=yes`. A factory reset erases it and recreates it empty at the next boot, which brings the machine back to the state of the image.

## Per-machine identity

The image contains no secret and no identifier specific to a machine:

| Item           | In the image                         | Created at first boot                                                  |
| -------------- | ------------------------------------ | ---------------------------------------------------------------------- |
| Machine ID     | `uninitialized`                      | Generated by systemd and saved in `/var/lib/dbus/machine-id`.          |
| SSH host key   | Removed (`RemoveFiles=`)             | `sshd-keygen.service` generates an Ed25519 key in `/var/etc/ssh/`.     |
| Hostname, timezone | Not set                          | Asked by `systemd-firstboot`, or read from systemd credentials.        |
| Locale, keymap | Defaults `C.UTF-8` and `fr`          | Not asked; change them by editing `/etc/locale.conf` and `/etc/vconsole.conf` (stored in `/var/etc`). |
| SSH access     | No authorised key                    | Provided as a credential (`ssh.authorized_keys.root`), see `just vm-create`. |

Two machines installed from the same image therefore never share keys or identifiers.

## Console access and the `dev` profile

In normal builds, the initrd keeps systemd's default behaviour: the `emergency` and `rescue` targets run `sulogin`, which requires the root password.

The `dev` profile, used together with a target (`--profile=cloudimg,dev`), deliberately weakens this to make debugging possible:

- `emergency.service` and `rescue.service` in the initrd run `bash` directly on the console, without `sulogin`;
- root is logged in automatically on the consoles (`Autologin=yes`).

!!! danger "Never deploy a `dev` image"
    An image built with the `dev` profile gives a root shell to anyone with console access. It must only be used for development and testing.

## Known gaps

The following points are not covered yet:

- **No Secure Boot.** The ESP is not protected and the UKI is not signed. Today, the chain of trust starts at the UKI, not at the firmware.
- **`/var` is neither encrypted nor integrity-protected.** Its content, including the writable `/etc` entries (`hosts`, `crypttab`, `credstore`…) and the SSH host key, can be read or changed by someone with offline access to the disk.
- **Development signing keys.** Each developer generates their own key with `mkosi genkey`. There is no production key or key management process yet (see [Key management](../administration/keys.md)).
- **TPM 2.0 is not used.** `systemd-tpm2-setup-early.service` currently fails at boot.
- **No A/B updates.** The layout leaves room for a second root slot, but updates are not implemented (see [Updates](../administration/updates.md)).
