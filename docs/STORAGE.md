# Storage

| Partition | Filesystem | Mounted at | Holds |
| --- | --- | --- | --- |
| `ROOT` | ext4 | `/` | The system |
| `HOME` | ext4 | `/home` | The home directory |
| `storage` | ext4 (was NTFS) | `~/storage` | Code checkouts, media, downloads, caches |
| `Basic data partition` | NTFS | `~/Windows`, on demand | The emergency Windows install and files shared with it |

Windows is only an emergency system, so `~/storage` does not need to be NTFS.
On NTFS every Git, package, and test operation of every agent went through the
FUSE `ntfs-3g` driver, and file modes were faked. Files that Windows should see
go on the Windows partition, which both systems read and write.

## Move ~/storage to ext4

`scripts/migrate-storage.sh` copies the 368 GB to `/storage-staging` on the
root partition, verifies the copy, reformats the partition as ext4, mounts it
by UUID at the same path, copies everything back, and verifies again. Paths do
not change, so repositories, worktrees, Codex trust entries, and the music
library keep working. Verification compares entry counts by type, total file
bytes, and an rsync pass that must find nothing to change; add `--checksum`
to compare contents as well.

Nothing may have files open under `~/storage` during the move: quit Codex,
t3code, Claude sessions, editors, and Dolphin windows there, and `cd ~` in
every terminal. The script stops and later restarts aria2, MPD, myMPD, and the
music sync, and pauses Baloo. Run it from a terminal whose working directory
is outside `~/storage`; it copies itself out before unmounting.

```sh
cd ~
~/storage/github/blade-kde-setup/scripts/migrate-storage.sh check
~/storage/github/blade-kde-setup/scripts/migrate-storage.sh all
# check your files, then
~/storage/github/blade-kde-setup/scripts/migrate-storage.sh finish
```

`all` runs `copy`, `format`, and `restore`; each can also run on its own, and a
failed or interrupted step can be rerun. `format` asks you to type the
partition path before erasing it. The staging copy stays until you run
`migrate-storage.sh finish`, which asks you to type `delete`.

Files copied from NTFS keep the owner-only `0700` modes ntfs-3g reported, so
keep `core.fileMode=false` in existing checkouts.
