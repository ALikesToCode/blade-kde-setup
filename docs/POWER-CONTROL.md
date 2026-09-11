# Brightness and charger controls

Run the following inside the logged-in Plasma session:

```sh
./install.sh --dry-run --power
./install.sh --power
```

The power-only installer adds KDE's native Brightness widget and Blade Power
to each existing application panel. It preserves other widgets, backs up the
panel configuration, and starts `blade-power.service` as the current user.
No sudo is required when the prerequisites are already installed.

The package manifest includes Python, Qt's `qdbus6`, PowerDevil,
plasma5support, and power-profiles-daemon. On an existing Arch installation
missing those packages, run:

```sh
sudo pacman -S --needed python qt6-tools powerdevil plasma5support power-profiles-daemon
```

## Power policy

| Source | Built-in screen | CPU power profile |
|---|---:|---|
| 400 W main charger, explicitly selected | 100% | performance |
| USB-C reported by Linux or explicitly selected | 40% | power-saver |
| External power with unknown charger type | 40% | power-saver |
| Battery | 17% | power-saver |
| Battery at or below 15% | 12% | power-saver |

The service checks for a power-source change every two seconds and applies its
policy after six stable seconds, allowing PowerDevil to finish its own source
transition. Later manual brightness adjustments remain in effect until the
source or configured brightness changes. External monitor brightness, suspend
timers, charging thresholds, firmware, CPU wattage limits, and GPU controls are
not modified. A missing internal-display interface or failed operation appears
as an error in the widget and service log.

Edit `~/.config/blade-power.conf` to adjust brightness percentages. Existing
configuration is preserved during reinstallation. `~/.config/powerdevilrc`
is not replaced or rewritten.

## Charger identification

Linux power-supply telemetry does not always distinguish barrel AC from USB-C.
For example, the MSI Titan 18 HX AI A2XWJG can expose only `ADP1`, type `Mains`,
with `online=1`, and no USB power-delivery device. That reading establishes
external power, but does not prove that a 400 W adapter is powering the laptop.

Blade Power therefore displays `AC ?` for ambiguous external power and uses the
USB saving settings. Click it to select the connected charger. `400 W*` and
`USB-C*` denote a manual choice, not measured adapter wattage. Battery detection
continues automatically and clears the manual choice when the service observes
a disconnect. Choices are session-local and reset at logout. A swap that keeps
AC continuously online, or occurs entirely between polls, requires a new manual
selection. If both chargers are connected, Linux may not report which physical
power path the firmware chose; the selector does not control power routing.

The widget reports the battery's actual charging/discharging status and net
battery power. Positive watts mean charging; negative watts mean discharge.
This is not input wattage at the charger. Lower brightness and the CPU
power-saving profile can reduce demand, but cannot guarantee net charging from
100 W during heavy CPU/GPU work. Check the displayed battery flow after switching
to USB-C and reduce the workload if it remains negative.

The [Linux power-supply documentation](https://www.kernel.org/doc/html/latest/power/power_supply_class.html)
describes the underlying telemetry. MSI's
[Titan 18 HX AI specification](https://storage-asset.msi.com/specSheet/th/nb/Titan%2018%20HX%20AI%20A2XWJG-1019THCP.pdf)
lists a 400 W adapter and up to 270 W combined CPU/GPU power; saving settings
cannot turn a 100 W supply into the full-power adapter.

## Commands and verification

```sh
blade-power status
blade-power status --json
blade-power mode main      # select the connected 400 W adapter
blade-power mode usb       # select the connected 100 W USB-C adapter
blade-power mode auto      # clear the manual selection
blade-power apply          # reapply current brightness/profile once
systemctl --user status blade-power.service
journalctl --user -u blade-power.service -n 30
```

To pause automation, run `systemctl --user stop blade-power.service`; this leaves
the last brightness and CPU profile in place. To disable it at future logins,
run `systemctl --user disable --now blade-power.service`. KDE's native Brightness
widget continues to work independently.

Tests use synthetic sysfs records, a mocked desktop bus, and a simulated panel
to cover ambiguous AC, USB detection, peripheral exclusion, battery discharge,
low-battery transitions, manual-selection reset, error reporting, idempotence,
and preservation of external displays and existing widgets:

```sh
python3 -B tests/power-control.py
node tests/power-panel.cjs
shellcheck scripts/install-power-control.sh
```

Physical charger swaps still need testing on the target hardware. A passing
fixture test does not establish that its firmware distinguishes the adapters.
