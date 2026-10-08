-- {"order":1,"file":"","version":0,"desc":"Fetch liked songs and mixes, download what's missing","arguments":[]}
-- Runs as its own systemd unit: myMPD's sandbox (MemoryDenyWriteExecute) would break yt-dlp's JS runtime.
local out = mympd.os_capture("systemctl --user start --no-block blade-music-sync-now.service 2>&1")
if out ~= nil and out ~= "" then
  return "Sync failed to start: " .. out
end
return "YouTube Music sync started; new songs appear in the YTM playlists when it finishes."
