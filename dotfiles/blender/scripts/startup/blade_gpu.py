"""Render Cycles on the GPU in every Blender that has this tree on BLENDER_SYSTEM_SCRIPTS.

The agent Blender MCP servers start Blender headless, one with --factory-startup,
so the user's preferences never reach them and Cycles falls back to the CPU.
Set BLADE_BLENDER_DEVICE=CPU to keep a session on the CPU.
"""

import os

import bpy
from bpy.app.handlers import persistent

# OptiX first: on NVIDIA RTX it is faster than CUDA and uses the RT cores.
BACKENDS = ("OPTIX", "CUDA", "HIP", "ONEAPI", "METAL")


def _select_backend():
    addon = bpy.context.preferences.addons.get("cycles")
    if addon is None:
        return None
    preferences = addon.preferences
    for backend in BACKENDS:
        try:
            preferences.compute_device_type = backend
        except TypeError:
            continue
        preferences.get_devices()
        if any(device.type == backend for device in preferences.devices):
            # GPU only: adding CPU threads to an OptiX render usually slows it.
            for device in preferences.devices:
                device.use = device.type == backend
            return backend
    preferences.compute_device_type = "NONE"
    return None


@persistent
def _render_on_gpu(scene, _depsgraph=None):
    if os.environ.get("BLADE_BLENDER_DEVICE", "").upper() == "CPU":
        return
    if scene.render.engine == "CYCLES" and _select_backend():
        scene.cycles.device = "GPU"


def register():
    if _render_on_gpu not in bpy.app.handlers.render_init:
        bpy.app.handlers.render_init.append(_render_on_gpu)


def unregister():
    if _render_on_gpu in bpy.app.handlers.render_init:
        bpy.app.handlers.render_init.remove(_render_on_gpu)
