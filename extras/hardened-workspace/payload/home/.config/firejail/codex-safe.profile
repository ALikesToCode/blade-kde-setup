# codex-safe: mandatory outer security boundary.
#
# Dynamic workspace and Landlock rules are supplied by ~/.local/bin/codex-safe
# after it resolves and validates the real launch directory. CloakBrowser is
# deliberately launched by runtime-inner.sh, so it inherits this exact jail.

quiet
private-tmp
private-dev
ipc-namespace
noroot
nonewprivs
caps.drop all
seccomp
protocol unix,inet,inet6,netlink
dbus-user none
dbus-system none
noautopulse
nosound
nogroups

# First make the host filesystem read-only. The launcher adds one narrower
# read-write bind for the validated workspace after loading this profile.
read-only /
read-only /home
read-only /root
read-only /etc
read-only /usr
read-only /var
read-only /opt
read-only /srv
read-only /boot
read-only /mnt
read-only /media
read-only /run/media

# Codex refuses to build its helper aliases when CODEX_HOME is textually under
# /tmp. This per-jail tmpfs is mounted over an otherwise empty host directory,
# providing ephemeral writable state without exposing a persistent home path.
tmpfs ${HOME}/.cache/codex-safe-runtime

# Credentials unrelated to Codex authentication are not exposed. ~/.codex is
# intentionally readable (the home mount is read-only) so auth, skills, plugins,
# MCP definitions, notifications, and marketplaces can be copied or linked into
# the private per-session CODEX_HOME.
blacklist ${HOME}/.ssh
blacklist ${HOME}/.gnupg
blacklist ${HOME}/.aws
blacklist ${HOME}/.azure
blacklist ${HOME}/.kube
blacklist ${HOME}/.docker
blacklist ${HOME}/.config/gh
blacklist ${HOME}/.config/gcloud
blacklist ${HOME}/.config/rclone
blacklist ${HOME}/.local/share/keyrings
blacklist ${HOME}/.password-store
blacklist ${HOME}/.netrc
blacklist ${HOME}/.npmrc
blacklist ${HOME}/.pypirc
blacklist ${HOME}/.git-credentials
blacklist ${HOME}/.git-credential-cache
blacklist ${HOME}/.config/git/credentials
blacklist ${HOME}/.config/git/credential
blacklist /run/dbus/system_bus_socket
blacklist /run/user/*/bus

# Read-only mounts do not make Unix-domain sockets read-only. Hide host control,
# credential-agent, and desktop-service sockets so a sandboxed process cannot
# ask a more privileged host daemon to mutate files on its behalf.
blacklist /run/docker.sock
blacklist /var/run/docker.sock
blacklist /run/containerd
blacklist /run/podman
blacklist /run/libvirt
blacklist /run/incus
blacklist /run/lxd
blacklist /run/systemd/private
blacklist /run/systemd/io.systemd.*
blacklist /run/udev/control
blacklist /run/cups/cups.sock
blacklist /run/snapd.socket
blacklist /run/user/*

# Fail closed against stock-browser fallback. Only the signed patched binary
# under ~/.cloakbrowser is left visible.
blacklist ${HOME}/.cache/ms-playwright
blacklist ${HOME}/.local/share/ms-playwright
blacklist ${HOME}/.local/share/codex-safe/playwright-cli/node_modules/playwright-core/.local-browsers
blacklist /ms-playwright
blacklist /usr/bin/chromium
blacklist /usr/bin/chromium-browser
blacklist /usr/bin/google-chrome
blacklist /usr/bin/google-chrome-stable
blacklist /usr/bin/google-chrome-beta
blacklist /usr/bin/google-chrome-unstable
blacklist /usr/bin/firefox
blacklist /usr/lib/chromium
blacklist /opt/google/chrome

# Cloakserve changes its bind address when it thinks it is in a container.
# Hiding these markers guarantees its documented bare-metal loopback behavior;
# runtime-inner.sh additionally verifies the listening address before Codex runs.
blacklist /.dockerenv
blacklist /run/.containerenv
