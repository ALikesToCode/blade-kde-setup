# Configuration inventory

This is the durable map of the Blade KDE work. It separates reproducible
configuration from private or machine-generated state, so a public clone can be
reviewed before it changes a system.

| Requested area | Repository coverage | Apply path |
|---|---|---|
| Dark Artix Rounded desktop | Global look-and-feel, Artix KDE color scheme, stable Breeze Dark Plasma surfaces, and rounded widget styling below `kde/` | `--user --apply` |
| Blue/green accents | Near-black palette with blue selection/link/focus colors and green healthy-state telemetry | `--apply` |
| Candy icons | Complete icon theme below `assets/icons/candy-icons/` | `--user` |
| Personal **A** launcher | 1024 px master, six hicolor sizes, prompt, and checksums below `assets/branding/launcher/` | `--user --apply` |
| Rounded window controls | Klassy preset, right-side compact controls, and pastel yellow/green/coral hover states | `--user --apply` |
| Solid Konsole chrome | Matching profile and colors, native clickable tabs, hidden normal close glyphs, and disabled process-wide stylesheet | `--user --apply` |
| Dark multi-monitor panels | One application panel per display, primary visible and additional panels auto-hidden | `--apply` |
| Desktop widgets | SDDM-inspired desktop clock plus native media, Wi-Fi, Bluetooth, audio, battery, notifications, workspaces, live download/upload speed, and CPU/RAM/GPU donuts | `--user --apply` |
| Event Calendar | Pinned Plasma 6 calendar/agenda source, reviewed checksums, dark Material card overlay, blue/green panel clock, event badges, optional weather/Google sync, and recurring iCalendar dependencies | `--user --apply` |
| Login and lock flow | Qylock-compatible Artix Material You files, blue/green power/session/reboot/sleep icons, runtime QML regression test, and SDDM selection | `--user`, then `--system` |
| Coordinated wallpapers | Separate native 16:10 4K and 3440×1440 ultrawide login/desktop images with checksums | `--user --apply`, plus `--system` for SDDM |
| Shell and prompt | Bash PATH/history/completion, green/blue Nerd Font prompt, pnpm-first aliases, and `vi`/`vim` to Neovim | `--user` |
| Editor and terminal tools | Neovim, tmux, and Readline configurations | `--user` |
| Media and downloads | MPV, yt-dlp, a persistent authenticated aria2 queue in `~/storage/anime`, checksum-pinned local AriaNg, makepkg, Yay concurrency, and Pacman parallel downloads | `--user` or `--downloads`, plus `--system` |
| Fast mirrors | Rate-sorted India/Asia Reflector policy and enabled weekly timer | `--system` |
| Unified updates | `updateall -y` and the full detected-manager updater, including PipeWire/JACK provider handling | `--user` |
| Node tooling | pnpm aliases, explicit system npm escape hatches, and global Wrangler installation | `--user` |
| Application launch tuning | Native Wayland Zen/Antigravity launchers, corrected integrated Candy controls for borderless Zen, and deterministic Vulkan Zed selection | `--user` |
| Safe publication workflow | Global modularity, verification, independent-commit, existing-identity, and destructive-action rules | `--user` |
| Hardened interactive launcher | Firejail/Landlock policy, terminal-preserving runtime, browser wrappers, checksums, doctor, self-test, and reversible manifest installer | `--hardened` |

## Dynamic values

Some settings must be discovered on the destination machine instead of being
hardcoded:

- Git commits and publications use the effective repository/global author and
  the account already authenticated by the GitHub CLI. The installer never
  replaces identity, signing, SSH, or credential configuration.
- The default GPU sensor is `gpu/gpu1`; `BLADE_GPU_SENSOR_PREFIX` and
  `BLADE_GPU_TITLE` adapt the donut to other hardware.
- Plasma screen count is read from the live session. Existing pinned
  applications and unrelated panels are preserved by default.
- Zen's active profile is discovered from `profiles.ini`; only the integrated
  titlebar preference is merged.

## Intentionally excluded

The repository never stores `.env` files, API keys, GitHub tokens, SSH/GPG
keys, browser profiles, cookies, credential databases, private histories,
generated caches, or sandbox verification workspaces. External browser/runtime
binaries are represented by exact versions and checksums rather than vendored.

Every mutable installer destination is backed up first. Panel deletion exists
only behind the explicit `--replace-existing --yes` command; the regular setup
uses additive, idempotent behavior.
