# Security

## Secret policy

This repository must never contain `.env` files, API keys, access tokens,
passwords, cookies, SSH/GPG private keys, or credential-helper data. The
installer adds a small safe Git include and intentionally leaves the existing
identity and authentication configuration alone.

Run `./tests/smoke.sh` before every commit. Its secret patterns are a safety net,
not a substitute for reviewing `git diff --cached`.

## Privileged operations

Only `install.sh --packages`, `install.sh --system`, and the installed
`updateall` utility use `sudo`. The setup installer authenticates once, backs up
destinations before replacement, and never restarts SDDM. Read the dry run first:

```bash
./install.sh --dry-run --all
```

Report security issues privately to the repository owner rather than placing
credentials or sensitive host details in a public issue.
