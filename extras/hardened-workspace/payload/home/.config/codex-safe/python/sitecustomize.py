"""Force Python Playwright launch calls through the session CloakBrowser CDP.

This module is imported automatically through PYTHONPATH inside codex-safe.
It does not run outside that environment. Direct stock browser executables are
also hidden by Firejail, so removing PYTHONPATH cannot create a silent fallback.
"""

from __future__ import annotations

import os


if os.environ.get("CODEX_SAFE_ACTIVE") == "1":
    endpoint = os.environ.get("CLOAK_CDP_ENDPOINT")
    artifacts_dir = os.environ.get("PLAYWRIGHT_MCP_OUTPUT_DIR")

    try:
        from playwright.sync_api import BrowserType as SyncBrowserType
        from playwright.async_api import BrowserType as AsyncBrowserType
    except ImportError:
        SyncBrowserType = None
        AsyncBrowserType = None

    def _browser_name(browser_type: object) -> str:
        return str(getattr(browser_type, "name", "unknown"))

    if SyncBrowserType is not None:
        _sync_connect = SyncBrowserType.connect_over_cdp

        def _sync_secure_connect(self, requested_endpoint=endpoint, **kwargs):
            if not endpoint:
                raise RuntimeError("codex-safe: CLOAK_CDP_ENDPOINT is missing")
            if requested_endpoint != endpoint:
                raise RuntimeError("codex-safe: alternate CDP endpoints are forbidden")
            kwargs.setdefault("timeout", 20_000)
            if artifacts_dir:
                kwargs.setdefault("artifacts_dir", artifacts_dir)
            return _sync_connect(self, endpoint, **kwargs)

        def _sync_launch(self, **_kwargs):
            if _browser_name(self) != "chromium":
                raise RuntimeError("codex-safe: only CloakBrowser-backed Chromium is enabled")
            return _sync_secure_connect(self, endpoint)

        def _sync_launch_persistent(self, _user_data_dir=None, **_kwargs):
            browser = _sync_launch(self)
            contexts = browser.contexts
            if not contexts:
                raise RuntimeError("codex-safe: CloakBrowser did not expose a default context")
            return contexts[0]

        SyncBrowserType.connect_over_cdp = _sync_secure_connect
        SyncBrowserType.launch = _sync_launch
        SyncBrowserType.launch_persistent_context = _sync_launch_persistent

    if AsyncBrowserType is not None:
        _async_connect = AsyncBrowserType.connect_over_cdp

        async def _async_secure_connect(self, requested_endpoint=endpoint, **kwargs):
            if not endpoint:
                raise RuntimeError("codex-safe: CLOAK_CDP_ENDPOINT is missing")
            if requested_endpoint != endpoint:
                raise RuntimeError("codex-safe: alternate CDP endpoints are forbidden")
            kwargs.setdefault("timeout", 20_000)
            if artifacts_dir:
                kwargs.setdefault("artifacts_dir", artifacts_dir)
            return await _async_connect(self, endpoint, **kwargs)

        async def _async_launch(self, **_kwargs):
            if _browser_name(self) != "chromium":
                raise RuntimeError("codex-safe: only CloakBrowser-backed Chromium is enabled")
            return await _async_secure_connect(self, endpoint)

        async def _async_launch_persistent(self, _user_data_dir=None, **_kwargs):
            browser = await _async_launch(self)
            contexts = browser.contexts
            if not contexts:
                raise RuntimeError("codex-safe: CloakBrowser did not expose a default context")
            return contexts[0]

        AsyncBrowserType.connect_over_cdp = _async_secure_connect
        AsyncBrowserType.launch = _async_launch
        AsyncBrowserType.launch_persistent_context = _async_launch_persistent

    os.environ["CODEX_SAFE_PYTHON_PLAYWRIGHT_POLICY_ACTIVE"] = "1"
