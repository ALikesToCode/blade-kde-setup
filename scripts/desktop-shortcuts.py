#!/usr/bin/env python3
"""Give every virtual desktop a switch and a move-window shortcut.

Meta+Alt+N switches to desktop N and Meta+Alt+Shift+N sends the active window
there, for desktops 1-5. Existing keys on those KWin actions are kept, so the
stock Ctrl+F1..F4 and Meta+F1..F4 still work. kglobalaccel saves the result.
"""
import sys

import dbus

META, ALT, SHIFT = 0x10000000, 0x08000000, 0x02000000
KEY_1 = 0x31
DESKTOPS = 5


def main():
    bus = dbus.SessionBus()
    accel = dbus.Interface(bus.get_object("org.kde.kglobalaccel", "/kglobalaccel"),
                           "org.kde.KGlobalAccel")
    for desktop in range(1, DESKTOPS + 1):
        digit = KEY_1 + desktop - 1
        for action, modifiers in ((f"Switch to Desktop {desktop}", META | ALT),
                                  (f"Window to Desktop {desktop}", META | ALT | SHIFT)):
            action_id = ["kwin", action, "KWin", action]
            # Each key sequence arrives as a one-field struct holding four ints.
            current = [[int(key) for key in seq[0]] for seq in accel.shortcutKeys(action_id)]
            current = [seq for seq in current if any(seq)]
            wanted = [modifiers | digit, 0, 0, 0]
            if wanted not in current:
                current.append(wanted)
            accel.setForeignShortcutKeys(
                action_id,
                dbus.Array([dbus.Struct([dbus.Array(seq, signature="i")], signature="ai")
                            for seq in current], signature="(ai)"))
            print(f"{action}: Meta+Alt+{'Shift+' if modifiers & SHIFT else ''}{desktop}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
