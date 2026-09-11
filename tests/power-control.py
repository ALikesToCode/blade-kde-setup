#!/usr/bin/env python3
"""Exercise source ambiguity, safe transitions, and internal-screen-only writes."""

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from blade_power import desktop
from blade_power import cli
from blade_power.policy import DEFAULTS, Transition, decide, load_settings
from blade_power.sources import snapshot


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def supply(self, name, **attributes):
        directory = self.root / name
        directory.mkdir(exist_ok=True)
        for key, value in attributes.items():
            (directory / key).write_text(str(value))

    def test_generic_mains_does_not_claim_400_watts(self):
        self.supply("ADP1", type="Mains", online=1)
        self.supply("BAT1", type="Battery", status="Charging", capacity=92,
                    voltage_now=17_000_000, current_now=1_500_000)
        result = snapshot(self.root)
        self.assertEqual(result["detected"], "external")
        self.assertEqual(result["batteries"][0]["net_watts"], 25.5)
        decision = decide(result, "auto", DEFAULTS)
        self.assertEqual(decision["brightness_percent"], 40)
        self.assertEqual(decision["power_profile"], "power-saver")
        self.assertIn("unknown", decision["label"])

    def test_online_usb_is_detected_but_peripheral_supplies_are_ignored(self):
        self.supply("mouse", type="USB", online=1, scope="Device")
        self.supply("BAT1", type="Battery", status="Discharging", capacity=60)
        self.assertEqual(snapshot(self.root)["detected"], "battery")
        self.supply("ucsi", type="USB_PD", online=1, scope="System")
        self.assertEqual(snapshot(self.root)["detected"], "usb")

    def test_discharge_while_plugged_in_is_not_reported_as_charging(self):
        self.supply("ADP1", type="Mains", online=1)
        self.supply("BAT1", type="Battery", status="Discharging", power_now=12_000_000)
        result = snapshot(self.root)
        self.assertEqual(result["batteries"][0]["net_watts"], -12)
        self.assertIn("discharging", decide(result, "usb", DEFAULTS)["warning"])

    def test_missing_telemetry_does_not_activate_performance_or_battery_policy(self):
        decision = decide(snapshot(self.root), "main", DEFAULTS)
        self.assertEqual(decision["source"], "unavailable")
        self.assertIsNone(decision["brightness_percent"])

    def test_manual_main_choice_is_ignored_on_battery(self):
        self.supply("ADP1", type="Mains", online=0)
        self.supply("BAT1", type="Battery", status="Discharging", capacity=40)
        decision = decide(snapshot(self.root), "main", DEFAULTS)
        self.assertEqual(decision["selection"], "auto")
        self.assertEqual(decision["brightness_percent"], 17)
        self.assertEqual(decision["power_profile"], "power-saver")
        self.supply("BAT1", capacity=10)
        self.assertEqual(decide(snapshot(self.root), "main", DEFAULTS)["brightness_percent"], 12)

    def test_main_mode_is_explicitly_labeled_as_selected(self):
        self.supply("ADP1", type="Mains", online=1)
        decision = decide(snapshot(self.root), "main", DEFAULTS)
        self.assertIn("selected", decision["label"])
        self.assertEqual(decision["brightness_percent"], 100)
        self.assertEqual(decision["power_profile"], "performance")

    def test_custom_brightness_is_validated(self):
        path = self.root / "settings.conf"
        path.write_text("[brightness]\nusb_brightness=32\n")
        self.assertEqual(load_settings(path)["usb_brightness"], 32)
        path.write_text("[brightness]\nusb_brightness=0\n")
        with self.assertRaises(ValueError):
            load_settings(path)


class TransitionTests(unittest.TestCase):
    def test_settles_then_applies_only_once_per_source(self):
        transition = Transition()
        self.assertFalse(transition.ready("usb", 0))
        self.assertFalse(transition.ready("usb", 5))
        self.assertTrue(transition.ready("usb", 6))
        transition.complete()
        self.assertFalse(transition.ready("usb", 600))
        self.assertFalse(transition.ready("battery", 601))
        self.assertTrue(transition.ready("battery", 607))

    def test_flapping_power_does_not_change_brightness(self):
        transition = Transition()
        for tick in range(20):
            self.assertFalse(transition.ready("usb" if tick % 2 else "battery", tick))


class DesktopTests(unittest.TestCase):
    def test_external_monitor_is_never_a_write_target(self):
        calls = []

        def bus(path, method, *args):
            calls.append((path, method, args))
            if path == desktop.DISPLAY_ROOT:
                return "display0\ndisplay1"
            if method.endswith("GetAll"):
                internal = "true" if path.endswith("display0") else "false"
                return f"IsInternal: {internal}\nMaxBrightness: 10000\nBrightness: 10000"
            return ""

        with patch.object(desktop, "dbus", side_effect=bus), patch.object(desktop, "command") as command:
            desktop.apply_policy({"brightness_percent": 40, "power_profile": "power-saver"})
        writes = [call for call in calls if call[1].endswith("SetBrightness")]
        self.assertEqual(writes, [("/org/kde/ScreenBrightness/display0", "org.kde.ScreenBrightness.Display.SetBrightness", (4000, 0))])
        command.assert_called_once_with("powerprofilesctl", "set", "power-saver")

    def test_missing_internal_display_changes_nothing(self):
        with patch.object(desktop, "internal_displays", return_value=[]), patch.object(desktop, "command") as command:
            with self.assertRaisesRegex(RuntimeError, "internal display"):
                desktop.apply_policy({"brightness_percent": 40, "power_profile": "power-saver"})
        command.assert_not_called()

    def test_profile_failure_is_reported_and_not_marked_successful(self):
        with patch.object(desktop, "internal_displays", return_value=[("display0", 10000)]), \
             patch.object(desktop, "command", side_effect=RuntimeError("Access denied")), \
             patch.object(desktop, "dbus") as bus:
            with self.assertRaisesRegex(RuntimeError, "Access denied"):
                desktop.apply_policy({"brightness_percent": 40, "power_profile": "power-saver"})
        bus.assert_not_called()


class WatcherTests(unittest.TestCase):
    def run_cycles(self, runtime, statuses, apply):
        ticks = iter(range(0, len(statuses) * 2, 2))
        waits = [None] * (len(statuses) - 1) + [InterruptedError("test complete")]
        with patch.object(cli, "current", side_effect=statuses), \
             patch.object(cli, "apply_policy", side_effect=apply), \
             patch.object(cli.time, "monotonic", side_effect=lambda: next(ticks)), \
             patch.object(cli.time, "sleep", side_effect=waits), \
             patch("builtins.print"):
            with self.assertRaises(InterruptedError):
                cli.loop(runtime / "config", runtime)

    def test_disconnect_clears_manual_selection_and_applies_battery_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary)
            desktop.write_json(runtime / "selection.json", {"mode": "main", "changed_at": 1})
            main = {"detected": "external", "source": "main", "key": ["main", 100],
                    "brightness_percent": 100, "power_profile": "performance"}
            battery = {"detected": "battery", "source": "battery", "key": ["battery", 17],
                       "brightness_percent": 17, "power_profile": "power-saver"}
            applied = []
            self.run_cycles(runtime, [main] * 4 + [battery] * 4,
                            lambda status: applied.append(status["source"]) or {})
            self.assertEqual(applied, ["main", "battery"])
            self.assertEqual(desktop.read_json(runtime / "selection.json")["mode"], "auto")

    def test_failure_remains_visible_while_waiting_to_retry(self):
        with tempfile.TemporaryDirectory() as temporary:
            runtime = Path(temporary)
            status = {"detected": "external", "key": ["external", 40]}
            def fail(_):
                raise RuntimeError("PowerDevil unavailable")
            # A failed apply reads monotonic time once more to schedule its retry.
            ticks = iter([0, 2, 4, 6, 6, 8, 10])
            with patch.object(cli, "current", return_value=status), \
                 patch.object(cli, "apply_policy", side_effect=fail), \
                 patch.object(cli.time, "monotonic", side_effect=lambda: next(ticks)), \
                 patch.object(cli.time, "sleep", side_effect=[None] * 5 + [InterruptedError]), \
                 patch("builtins.print"):
                with self.assertRaises(InterruptedError):
                    cli.loop(runtime / "config", runtime)
            self.assertEqual(desktop.read_json(runtime / "status.json")["error"], "PowerDevil unavailable")


if __name__ == "__main__":
    unittest.main()
