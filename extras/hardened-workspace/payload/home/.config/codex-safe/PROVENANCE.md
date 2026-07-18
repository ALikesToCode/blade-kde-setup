# codex-safe provenance receipt

Verified during installation on 2026-07-18:

- Official source: `https://github.com/CloakHQ/CloakBrowser`
- CloakBrowser source tag: `v0.4.11`
- Resolved source commit: `86d1d76b8139e586ec0248d4e12b3a4618007682`
- GitHub API tag signature verification: valid (verified 2026-07-16)
- Official patched Chromium version: `146.0.7680.177.5`
- Official release asset: `cloakbrowser-linux-x64.tar.gz`
- Release asset SHA-256 from the official release: `4a12bcde95fa1bb1beef2b41ab5e5c27c36be78e3be3d0dac8c64d705216670e`
- Independently downloaded asset SHA-256: exact match
- GitHub artifact attestation (`gh attestation verify`): PASS for `CloakHQ/CloakBrowser`
- Installed `bin/cloakserve` SHA-256: `a334ec5aaf2221e8a463a7c64cfa9b290e62348582da7e03e24f927b285df1fa`
- Installed patched `chrome` executable SHA-256: `715722e8605ae3ce81523c1218aba1ec89425786ab33ceaf99f8a6cb5e70e6e8`
- ShellCheck release: official `koalaman/shellcheck` `v0.11.0` Linux x86-64 archive
- ShellCheck archive SHA-256 from GitHub release metadata and independently matched: `b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6`
- Installed standalone `shellcheck` SHA-256: `4da528ddb3a4d1b7b24a59d4e16eb2f5fd960f4bd9a3708a15baddbdf1d5a55b`

The CloakBrowser installed-file hashes are enforced at every `codex-safe` launch.
The standalone ShellCheck hash is enforced by the installer and doctor. The
release archive was verified before extraction; auto-update is disabled during
sandbox sessions so a session cannot replace the pinned browser.
