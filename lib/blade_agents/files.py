"""Back up and atomically replace small configuration files."""

import datetime as dt
import os
from pathlib import Path
import shutil
import tempfile


def state_root():
    return Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))


def backup_root():
    override = os.environ.get("BLADE_BACKUP_ROOT")
    if override:
        return Path(override)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    return state_root() / "blade-kde-backups" / f"agents-{stamp}"


def read_text(path):
    return path.read_text() if path.exists() else ""


def replace(path, text):
    """Write text to path, keeping a backup and the existing permissions."""
    if path.is_symlink():
        raise OSError(f"refusing symlink target: {path}")
    mode = 0o600
    if path.exists():
        mode = path.stat().st_mode & 0o777
        backup = backup_root() / str(path.resolve()).lstrip("/")
        backup.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(text)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        Path(temporary).unlink(missing_ok=True)
        raise
