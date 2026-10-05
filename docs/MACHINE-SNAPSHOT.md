# Machine snapshot

The Blade installer reproduces the desktop design. The machine snapshot in
`machine/` records the rest of the workstation: explicitly installed packages,
user-level tools, system tuning, enabled services, group memberships, and KDE
settings changed through System Settings.

## Recording changes

After installing a package, enabling a service, or changing a KDE setting, run:

```bash
make capture        # or ./scripts/capture-machine.sh
git diff -- machine
```

The capture is deterministic: lists are sorted, home paths become `__HOME__`,
and window geometry, recent files, session counters, and similar runtime state
are dropped. Commit the reviewed diff like any other change.

## Restoring on another machine

On a fresh Arch install with Yay available:

```bash
./install.sh --all -y      # Blade desktop, packages, tools, and system tuning
./install.sh --machine -y  # this workstation's recorded additions
```

Preview first with `./install.sh --dry-run --machine`. The restore:

1. enables `[multilib]` when `lib32-*` packages are recorded, upgrades the
   system while installing repository packages with `--needed`, and installs AUR
   packages one at a time so a removed package does not block the rest;
2. installs the recorded pnpm, npm (`~/.local` prefix), uv, pipx, and Flatpak
   tools at their recorded versions;
3. installs the files under `machine/etc/` with root ownership after backing up
   each replaced file, then runs `locale-gen`, `sysctl --system`, and a udev
   reload when the matching files changed;
4. enables the recorded system and user units, applies recorded masks, and adds
   the account to recorded groups that exist;
5. merges `machine/home/` into the KDE config files key by key, so settings the
   snapshot does not name stay untouched;
6. reports, without changing, every file in `machine/etc-reference/` that
   differs from the target system.

Backups go to `~/.local/state/blade-kde-backups/`. Log out or reboot afterwards.

## Hardware gates

`machine/hardware-rules.tsv` maps packages, units, and files to the hardware
they need. The restore detects NVIDIA, Intel, and AMD graphics from PCI class
codes, the CPU vendor from `/proc/cpuinfo`, a battery from
`/sys/class/power_supply`, and MSI firmware from DMI, and holds back entries
whose hardware is absent. Entries gated as `manual` (the DisplayLink `evdi`
driver) are never installed automatically. Set `BLADE_MACHINE_GATES` to a
comma-separated list to override detection.

## Review-only files

`machine/etc-reference/` holds the GRUB defaults, mkinitcpio configuration and
preset, NVIDIA and Type-C module loading, `lm_sensors` detection, `pacman.conf`,
and `firejail.users`. Copied to different hardware, the boot files can leave a
machine unbootable, and the Firejail list is an access-control decision, so
apply them by hand after comparing. `pacman.conf` also records the Warp
repository; add it and import its signing key before installing
`warp-terminal`.

## Never recorded

Credentials and host identity stay out of the snapshot: `fstab`, `crypttab`,
`hosts`, account databases, `machine-id`, NVMe host IDs, network connections,
printers, `sudoers`, the mirror list (Reflector regenerates it), SSH and GPG
keys, Git and GitHub identity, cloud CLI configuration, and every application
token or key file. Monitor layouts and Plasma panels are also excluded because
they are bound to specific displays; `apply-panels.sh` generates the panels.

The `update-stevenblack-hosts` cron entry needs `cronie` enabled before it runs.
