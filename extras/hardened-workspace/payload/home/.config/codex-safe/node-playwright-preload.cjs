'use strict';

// NODE_OPTIONS loads this before Node programs inside codex-safe. It converts
// ordinary Playwright launch calls into an attachment to the verified local
// CloakBrowser endpoint and rejects alternate browsers/remotes. If a process
// removes NODE_OPTIONS, Firejail still blacklists stock browser binaries.
if (process.env.CODEX_SAFE_ACTIVE === '1') {
  const Module = require('module');
  const originalLoad = Module._load;
  const endpoint = process.env.CLOAK_CDP_ENDPOINT;
  const artifactsDir = process.env.PLAYWRIGHT_MCP_OUTPUT_DIR;
  const patched = new WeakSet();

  function refusal(message) {
    return async function codexSafeRefusal() {
      throw new Error(`codex-safe: ${message}`);
    };
  }

  function patchBrowserType(browserType, name) {
    if (!browserType || patched.has(browserType)) return;
    patched.add(browserType);

    if (name !== 'chromium') {
      browserType.launch = refusal(`${name} is disabled; use CloakBrowser-backed Chromium`);
      browserType.launchPersistentContext = refusal(`${name} is disabled; use CloakBrowser-backed Chromium`);
      browserType.launchServer = refusal(`${name} browser servers are disabled`);
      browserType.connect = refusal(`${name} remote browser connections are disabled`);
      return;
    }

    if (!endpoint) {
      browserType.launch = refusal('CLOAK_CDP_ENDPOINT is unavailable; stock Chromium fallback is forbidden');
      browserType.launchPersistentContext = browserType.launch;
      browserType.launchServer = browserType.launch;
      return;
    }

    const originalConnectOverCDP = browserType.connectOverCDP.bind(browserType);
    const secureConnect = async (requestedEndpoint = endpoint, options = {}) => {
      if (requestedEndpoint !== endpoint) {
        throw new Error('codex-safe: alternate CDP endpoints are forbidden');
      }
      const connectOptions = { ...options };
      if (artifactsDir && connectOptions.artifactsDir === undefined) connectOptions.artifactsDir = artifactsDir;
      if (connectOptions.timeout === undefined) connectOptions.timeout = 20000;
      return originalConnectOverCDP(endpoint, connectOptions);
    };

    browserType.connectOverCDP = secureConnect;
    browserType.launch = async () => secureConnect(endpoint);
    browserType.launchPersistentContext = async () => {
      const browser = await secureConnect(endpoint);
      const contexts = browser.contexts();
      if (!contexts.length) throw new Error('codex-safe: CloakBrowser did not expose a default context');
      return contexts[0];
    };
    browserType.launchServer = refusal('launchServer is disabled; use the session CloakBrowser CDP endpoint');
    browserType.connect = refusal('Playwright protocol remotes are disabled; use the session CloakBrowser CDP endpoint');
    browserType.executablePath = () => process.env.CLOAKBROWSER_BINARY_PATH || '';
  }

  function hardenPlaywright(exportsObject) {
    if (!exportsObject || (typeof exportsObject !== 'object' && typeof exportsObject !== 'function')) return exportsObject;
    patchBrowserType(exportsObject.chromium, 'chromium');
    patchBrowserType(exportsObject.firefox, 'firefox');
    patchBrowserType(exportsObject.webkit, 'webkit');
    return exportsObject;
  }

  Module._load = function codexSafeModuleLoad(request, parent, isMain) {
    const loaded = originalLoad.call(this, request, parent, isMain);
    if (request === 'playwright' || request === 'playwright-core' || request === '@playwright/test') {
      return hardenPlaywright(loaded);
    }
    return loaded;
  };

  process.env.CODEX_SAFE_PLAYWRIGHT_PRELOAD_ACTIVE = '1';
}
