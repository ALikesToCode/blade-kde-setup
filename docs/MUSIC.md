# Blade Music

Run the following inside the logged-in Plasma session:

```sh
./install.sh --dry-run --music
./install.sh --music
```

Blade Music keeps an offline copy of the YouTube Music you actually listen to
and plays it, together with the rest of `~/storage/music`, through MPD. It
starts at login: MPD plays, myMPD is the web player, `mpd-mpris` exposes MPD to
Plasma's Media Player widget and media keys, and the Blade Music panel widget
picks playlists and starts a sync. Closing the web player tab never stops the
music. No sudo is required when the prerequisites are installed:

```sh
sudo pacman -S --needed mpd mpc mpd-mpris mympd rmpc python-ytmusicapi python-mutagen yt-dlp yt-dlp-ejs ffmpeg
```

## What is cached

| List | Source |
| --- | --- |
| Liked | Every liked song |
| Like ‹song› | Each favourite and its YouTube Music radio of similar songs |
| Your playlists | Playlists you created in YouTube Music |
| Most played | Songs played on the most distinct days in the last 90 days, from watch history |
| Personal mixes | The top of My Supermix, Replay Mix, Discover Mix, New Release Mix, and Archive Mix |

Lists download in that order, 50 songs per sync. A song already anywhere in
`~/storage/music` is reused: by the YouTube ID in its filename, or by artist and
title tags (or the filename for untagged files) when the length also agrees.
Matches other than by ID are listed in `~/.local/state/blade-music/fuzzy-matches.tsv`.
Missing songs download as Opus at the best quality the account receives into
`~/storage/music/ytm-cache/`.

Add a favourite from any shared link:

```sh
blade-music favourite 'https://music.youtube.com/watch?v=…&si=…'
blade-music sync-now
```

## Safety on a travelling laptop

- `ytm-cache/` is the only folder Blade Music writes audio to or deletes from.
  A cached song is removed only after no list has wanted it for 30 days, and a
  run whose wanted list suddenly halves skips cleanup, since that usually means
  YouTube changed a page rather than your taste.
- The timer checks hourly but syncs at most every six hours, never when
  `~/storage` is unmounted, and downloads nothing on a metered connection.
- MPD and myMPD listen on loopback only (`127.0.0.1:6600` and `127.0.0.1:8080`).
- The YouTube login is read from the browser each run, so no token is stored.
  Set `brand_account` in `~/.config/blade-music.toml` when you listen on a brand
  channel; its page ID is shown by YouTube's account switcher.

## Commands

| Command | Effect |
| --- | --- |
| `blade-music-web` | Open myMPD in the browser |
| `blade-music play ['YTM - Liked']` | Play a stored playlist, or the shuffled library |
| `blade-music sync-now` | Start a sync now (also in the panel widget and myMPD's menu) |
| `blade-music sync --dry-run --force -v` | Show what a sync would download and delete |
| `journalctl --user -u blade-music-sync -u blade-music-sync-now` | Sync logs |
