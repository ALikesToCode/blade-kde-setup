#!/usr/bin/env python3
"""Tile and focus normal top-level windows on the private Xephyr display."""

from __future__ import annotations

import argparse
import ctypes
import os
import select
import signal
import sys
from pathlib import Path


Display = ctypes.c_void_p
Window = ctypes.c_ulong
Bool = ctypes.c_int

MAP_REQUEST = 20
CONFIGURE_NOTIFY = 22
CONFIGURE_REQUEST = 23

STRUCTURE_NOTIFY_MASK = 1 << 17
SUBSTRUCTURE_NOTIFY_MASK = 1 << 19
SUBSTRUCTURE_REDIRECT_MASK = 1 << 20

INPUT_OUTPUT = 1
IS_UNMAPPED = 0
REVERT_TO_POINTER_ROOT = 1
CURRENT_TIME = 0


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("border_width", ctypes.c_int),
        ("depth", ctypes.c_int),
        ("visual", ctypes.c_void_p),
        ("root", Window),
        ("window_class", ctypes.c_int),
        ("bit_gravity", ctypes.c_int),
        ("win_gravity", ctypes.c_int),
        ("backing_store", ctypes.c_int),
        ("backing_planes", ctypes.c_ulong),
        ("backing_pixel", ctypes.c_ulong),
        ("save_under", Bool),
        ("colormap", ctypes.c_ulong),
        ("map_installed", Bool),
        ("map_state", ctypes.c_int),
        ("all_event_masks", ctypes.c_long),
        ("your_event_mask", ctypes.c_long),
        ("do_not_propagate_mask", ctypes.c_long),
        ("override_redirect", Bool),
        ("screen", ctypes.c_void_p),
    ]


class XAnyEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", Bool),
        ("display", Display),
        ("window", Window),
    ]


class XMapRequestEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", Bool),
        ("display", Display),
        ("parent", Window),
        ("window", Window),
    ]


class XConfigureEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", Bool),
        ("display", Display),
        ("event", Window),
        ("window", Window),
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("border_width", ctypes.c_int),
        ("above", Window),
        ("override_redirect", Bool),
    ]


class XConfigureRequestEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("serial", ctypes.c_ulong),
        ("send_event", Bool),
        ("display", Display),
        ("parent", Window),
        ("window", Window),
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("border_width", ctypes.c_int),
        ("above", Window),
        ("detail", ctypes.c_int),
        ("value_mask", ctypes.c_ulong),
    ]


class XErrorEvent(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int),
        ("display", Display),
        ("resource_id", Window),
        ("serial", ctypes.c_ulong),
        ("error_code", ctypes.c_ubyte),
        ("request_code", ctypes.c_ubyte),
        ("minor_code", ctypes.c_ubyte),
    ]


class XEvent(ctypes.Union):
    _fields_ = [
        ("type", ctypes.c_int),
        ("xany", XAnyEvent),
        ("xmaprequest", XMapRequestEvent),
        ("xconfigure", XConfigureEvent),
        ("xconfigurerequest", XConfigureRequestEvent),
        ("pad", ctypes.c_long * 24),
    ]


ErrorHandler = ctypes.CFUNCTYPE(ctypes.c_int, Display, ctypes.POINTER(XErrorEvent))


class FullDisplayWindowManager:
    def __init__(self) -> None:
        self.lib = ctypes.CDLL("libX11.so.6")
        self._configure_xlib()
        self.errors: list[int] = []
        self.record_errors = True
        self.error_handler = ErrorHandler(self._handle_x_error)
        self.lib.XSetErrorHandler(self.error_handler)
        self.display = self.lib.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("cannot connect to the private nested display")
        screen = self.lib.XDefaultScreen(self.display)
        self.root = self.lib.XRootWindow(self.display, screen)
        self.connection = self.lib.XConnectionNumber(self.display)
        self.running = True

    def _configure_xlib(self) -> None:
        self.lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.lib.XOpenDisplay.restype = Display
        self.lib.XDefaultScreen.argtypes = [Display]
        self.lib.XDefaultScreen.restype = ctypes.c_int
        self.lib.XRootWindow.argtypes = [Display, ctypes.c_int]
        self.lib.XRootWindow.restype = Window
        self.lib.XConnectionNumber.argtypes = [Display]
        self.lib.XConnectionNumber.restype = ctypes.c_int
        self.lib.XSelectInput.argtypes = [Display, Window, ctypes.c_long]
        self.lib.XSync.argtypes = [Display, Bool]
        self.lib.XPending.argtypes = [Display]
        self.lib.XPending.restype = ctypes.c_int
        self.lib.XNextEvent.argtypes = [Display, ctypes.POINTER(XEvent)]
        self.lib.XGetWindowAttributes.argtypes = [
            Display,
            Window,
            ctypes.POINTER(XWindowAttributes),
        ]
        self.lib.XGetWindowAttributes.restype = ctypes.c_int
        self.lib.XQueryTree.argtypes = [
            Display,
            Window,
            ctypes.POINTER(Window),
            ctypes.POINTER(Window),
            ctypes.POINTER(ctypes.POINTER(Window)),
            ctypes.POINTER(ctypes.c_uint),
        ]
        self.lib.XQueryTree.restype = ctypes.c_int
        self.lib.XMoveResizeWindow.argtypes = [
            Display,
            Window,
            ctypes.c_int,
            ctypes.c_int,
            ctypes.c_uint,
            ctypes.c_uint,
        ]
        self.lib.XSetWindowBorderWidth.argtypes = [Display, Window, ctypes.c_uint]
        self.lib.XMapWindow.argtypes = [Display, Window]
        self.lib.XSetInputFocus.argtypes = [
            Display,
            Window,
            ctypes.c_int,
            ctypes.c_ulong,
        ]
        self.lib.XSendEvent.argtypes = [
            Display,
            Window,
            Bool,
            ctypes.c_long,
            ctypes.POINTER(XEvent),
        ]
        self.lib.XFlush.argtypes = [Display]
        self.lib.XFree.argtypes = [ctypes.c_void_p]
        self.lib.XCloseDisplay.argtypes = [Display]
        self.lib.XSetErrorHandler.argtypes = [ErrorHandler]
        self.lib.XSetErrorHandler.restype = ctypes.c_void_p

    def _handle_x_error(
        self, _display: Display, event: ctypes.POINTER(XErrorEvent)
    ) -> int:
        if self.record_errors:
            self.errors.append(int(event.contents.error_code))
        return 0

    def claim_display(self) -> None:
        mask = (
            SUBSTRUCTURE_REDIRECT_MASK
            | SUBSTRUCTURE_NOTIFY_MASK
            | STRUCTURE_NOTIFY_MASK
        )
        self.lib.XSelectInput(self.display, self.root, mask)
        self.lib.XSync(self.display, False)
        if self.errors:
            raise RuntimeError(
                "cannot claim the nested display as window manager: "
                f"X11 error {self.errors[0]}"
            )
        self.record_errors = False

    def root_size(self) -> tuple[int, int]:
        attributes = XWindowAttributes()
        if not self.lib.XGetWindowAttributes(
            self.display, self.root, ctypes.byref(attributes)
        ):
            raise RuntimeError("cannot read nested display dimensions")
        return max(1, attributes.width), max(1, attributes.height)

    def tile_window(
        self,
        window: int,
        *,
        map_window: bool,
        notify: bool,
        focus: bool,
    ) -> None:
        if not window or window == self.root:
            return
        attributes = XWindowAttributes()
        if not self.lib.XGetWindowAttributes(
            self.display, window, ctypes.byref(attributes)
        ):
            return
        if attributes.override_redirect or attributes.window_class != INPUT_OUTPUT:
            return
        width, height = self.root_size()
        self.lib.XSetWindowBorderWidth(self.display, window, 0)
        self.lib.XMoveResizeWindow(self.display, window, 0, 0, width, height)
        if map_window:
            self.lib.XMapWindow(self.display, window)
        if focus:
            self.lib.XSetInputFocus(
                self.display,
                window,
                REVERT_TO_POINTER_ROOT,
                CURRENT_TIME,
            )
        if notify:
            event = XEvent()
            event.xconfigure.type = CONFIGURE_NOTIFY
            event.xconfigure.display = self.display
            event.xconfigure.event = window
            event.xconfigure.window = window
            event.xconfigure.x = 0
            event.xconfigure.y = 0
            event.xconfigure.width = width
            event.xconfigure.height = height
            event.xconfigure.border_width = 0
            event.xconfigure.above = 0
            event.xconfigure.override_redirect = False
            self.lib.XSendEvent(
                self.display,
                window,
                False,
                STRUCTURE_NOTIFY_MASK,
                ctypes.byref(event),
            )
        self.lib.XFlush(self.display)

    def tile_existing_windows(self) -> None:
        root_return = Window()
        parent_return = Window()
        children = ctypes.POINTER(Window)()
        count = ctypes.c_uint()
        if not self.lib.XQueryTree(
            self.display,
            self.root,
            ctypes.byref(root_return),
            ctypes.byref(parent_return),
            ctypes.byref(children),
            ctypes.byref(count),
        ):
            return
        try:
            for index in range(count.value):
                window = children[index]
                attributes = XWindowAttributes()
                if self.lib.XGetWindowAttributes(
                    self.display, window, ctypes.byref(attributes)
                ) and attributes.map_state != IS_UNMAPPED:
                    self.tile_window(
                        window,
                        map_window=False,
                        notify=True,
                        focus=True,
                    )
        finally:
            if children:
                self.lib.XFree(children)

    def stop(self, _signum: int, _frame: object) -> None:
        self.running = False

    def run(self) -> None:
        signal.signal(signal.SIGTERM, self.stop)
        signal.signal(signal.SIGINT, self.stop)
        while self.running:
            try:
                readable, _, _ = select.select([self.connection], [], [], 0.25)
            except InterruptedError:
                continue
            if not readable:
                continue
            while self.running and self.lib.XPending(self.display):
                event = XEvent()
                self.lib.XNextEvent(self.display, ctypes.byref(event))
                if event.type == MAP_REQUEST:
                    self.tile_window(
                        event.xmaprequest.window,
                        map_window=True,
                        notify=False,
                        focus=True,
                    )
                elif event.type == CONFIGURE_REQUEST:
                    self.tile_window(
                        event.xconfigurerequest.window,
                        map_window=False,
                        notify=True,
                        focus=False,
                    )
                elif (
                    event.type == CONFIGURE_NOTIFY
                    and event.xconfigure.window == self.root
                ):
                    self.tile_existing_windows()

    def close(self) -> None:
        if self.display:
            self.lib.XCloseDisplay(self.display)
            self.display = None


def write_ready_file(path: Path) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    with os.fdopen(descriptor, "w", encoding="ascii") as handle:
        handle.write("ready\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ready-file", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.ready_file.is_absolute():
        parser.error("--ready-file must be absolute")

    manager: FullDisplayWindowManager | None = None
    try:
        manager = FullDisplayWindowManager()
        manager.claim_display()
        manager.tile_existing_windows()
        write_ready_file(arguments.ready_file)
        manager.run()
    except (OSError, RuntimeError) as error:
        print(f"nested-window-manager: ERROR: {error}", file=sys.stderr)
        return 1
    finally:
        if manager:
            manager.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
