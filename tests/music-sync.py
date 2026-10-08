#!/usr/bin/env python3
"""Exercise local matching, play counting, playlist paths, and cache-only deletion."""

import datetime as dt
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from blade_music import cache, config, playlists, youtube
from blade_music.library import Track, find_local, norm, tag_key
from blade_music.store import open_db


class TemporaryState(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.db = open_db(self.root / "state")
        self.addCleanup(self.db.close)

    def add_file(self, path, video_id=None, artist=None, title=None, duration=None):
        self.db.execute("INSERT INTO local_files VALUES (?,?,?,?,?,?,?,?,?)",
                        (path, 0, 0, video_id, artist, title, duration,
                         tag_key(artist, title), norm(Path(path).stem)))


class MatchingTests(TemporaryState):
    def test_normalising_handles_full_width_cjk_and_noise(self):
        self.assertEqual(norm("Megalovania ｜ EPIC (Official Video) [b-pFvuqR5ck]"), "megalovania epic")
        self.assertEqual(norm("虚式 「茈」"), "虚式 茈")

    def test_youtube_id_prefers_audio_over_video_container(self):
        self.add_file("Hero [DcERQHg3iy8].webm", "DcERQHg3iy8")
        self.add_file("Hero [DcERQHg3iy8].opus", "DcERQHg3iy8")
        self.assertEqual(find_local(self.db, Track("DcERQHg3iy8", "", "", None), 3),
                         ("Hero [DcERQHg3iy8].opus", "id"))

    def test_tags_match_only_when_lengths_agree(self):
        self.add_file("ost/21. 霹靂.flac", artist="照井順政", title="霹靂", duration=120)
        self.assertEqual(find_local(self.db, Track("x" * 11, "照井順政", "霹靂", 122), 3)[1], "tags")
        self.assertIsNone(find_local(self.db, Track("x" * 11, "照井順政", "霹靂", 200), 3))

    def test_filename_match_needs_untagged_file_and_known_length(self):
        self.add_file("Shadowborn (Pure Instrumental).mp4", duration=195)
        hit = Track("y" * 11, "Hiroyuki SAWANO", "Shadowborn (Pure Instrumental)", 195)
        self.assertEqual(find_local(self.db, hit, 3)[1], "filename")
        self.assertIsNone(find_local(self.db, Track("y" * 11, "", "Shadowborn (Pure Instrumental)", None), 3))


class HistoryTests(unittest.TestCase):
    def test_play_days_count_recent_days_and_backfill_once(self):
        history = [{"videoId": "a", "played": "Today"}, {"videoId": "b", "played": "Yesterday"},
                   {"videoId": "c", "played": "Last week"}, {"played": "Today"}]
        today = dt.date(2026, 10, 8)
        self.assertEqual(youtube.play_days(history, today, first_run=False),
                         [("a", "2026-10-08"), ("b", "2026-10-07")])
        backfill = youtube.play_days(history, today, first_run=True)[-1]
        self.assertEqual(backfill, ("c", "2026-09-08:Last week"))


class FavouriteTests(unittest.TestCase):
    def test_radio_playlist_starts_with_the_favourite_itself(self):
        class Radio:
            def get_watch_playlist(self, videoId, radio, limit):
                items = [{"videoId": "similar0001", "title": "Similar"},
                         {"videoId": videoId, "title": "4eVR", "artists": [{"name": "Hiroyuki SAWANO"}]}]
                return {"tracks": items}
        radios = youtube.favourite_radios(Radio(), ["iqJ5XKrFtco"], 50)
        self.assertEqual(list(radios), ["Like 4eVR"])
        self.assertEqual([t.video_id for t in radios["Like 4eVR"]], ["iqJ5XKrFtco", "similar0001"])


class CacheTests(TemporaryState):
    def settings(self):
        music = self.root / "music"
        return {"music_root": music, "cache_dir": music / "ytm-cache", "keep_days_after_unwanted": 30}

    def test_cleanup_deletes_only_stale_cache_files(self):
        settings = self.settings()
        files = {"album/keep [aaaaaaaaaaa].opus": ("aaaaaaaaaaa", "2026-01-01"),
                 "ytm-cache/old [bbbbbbbbbbb].opus": ("bbbbbbbbbbb", "2026-08-01"),
                 "ytm-cache/fresh [ccccccccccc].opus": ("ccccccccccc", "2026-10-01")}
        for rel, (video_id, wanted) in files.items():
            (settings["music_root"] / rel).parent.mkdir(parents=True, exist_ok=True)
            (settings["music_root"] / rel).touch()
            self.add_file(rel, video_id)
            self.db.execute("INSERT INTO tracks VALUES (?,?,?,?,?)", (video_id, "", "", None, wanted))
        removed = cache.cleanup(self.db, settings, dt.date(2026, 10, 8), dry_run=False)
        self.assertEqual(removed, ["ytm-cache/old [bbbbbbbbbbb].opus"])
        self.assertTrue((settings["music_root"] / "album/keep [aaaaaaaaaaa].opus").exists())
        self.assertTrue((settings["music_root"] / "ytm-cache/fresh [ccccccccccc].opus").exists())

    def test_unclaimed_cache_files_get_the_full_grace_period(self):
        settings = self.settings()
        rel = "ytm-cache/orphan [eeeeeeeeeee].opus"
        (settings["music_root"] / "ytm-cache").mkdir(parents=True)
        (settings["music_root"] / rel).touch()
        self.add_file(rel, "eeeeeeeeeee")
        self.assertEqual(cache.cleanup(self.db, settings, dt.date(2026, 10, 8), dry_run=False), [])
        self.assertEqual(cache.cleanup(self.db, settings, dt.date(2026, 11, 8), dry_run=False), [rel])

    def test_cache_files_seen_only_in_history_still_expire(self):
        settings = self.settings()
        rel = "ytm-cache/heard [fffffffffff].opus"
        (settings["music_root"] / "ytm-cache").mkdir(parents=True)
        (settings["music_root"] / rel).touch()
        self.add_file(rel, "fffffffffff")
        self.db.execute("INSERT INTO tracks VALUES (?,?,?,?,?)", ("fffffffffff", "", "", None, None))
        self.assertEqual(cache.cleanup(self.db, settings, dt.date(2026, 10, 8), dry_run=False), [])
        self.assertEqual(cache.cleanup(self.db, settings, dt.date(2026, 11, 8), dry_run=False), [rel])

    def test_collapsed_wanted_list_blocks_cleanup(self):
        self.assertFalse(cache.cleanup_allowed(336, 8))
        self.assertTrue(cache.cleanup_allowed(336, 300))
        self.assertTrue(cache.cleanup_allowed(0, 0))


class PlaylistTests(TemporaryState):
    def test_portable_and_mpd_playlists_use_their_own_relative_paths(self):
        music = self.root / "music"
        settings = {"playlist_dir": music / "playlists", "mpd_playlist_dir": self.root / "mpd"}
        tracks = [Track("aaaaaaaaaaa", "A", "Keep", 100), Track("ddddddddddd", "D", "Missing", 90)]
        summary = playlists.write_playlists(settings, {"Liked": tracks},
                                            {"aaaaaaaaaaa": "album/keep.opus"}, self.root / "state")
        self.assertEqual(summary, [{"name": "Liked", "playlist": "YTM - Liked", "available": 1, "total": 2}])
        self.assertIn("../album/keep.opus", (music / "playlists/YTM - Liked.m3u8").read_text())
        self.assertIn("\nalbum/keep.opus\n", (self.root / "mpd/YTM - Liked.m3u").read_text())
        saved = json.loads((self.root / "state/playlists.json").read_text())
        self.assertEqual(saved[0]["available"], 1)


class ConfigTests(unittest.TestCase):
    def test_zen_resolves_to_the_most_recently_used_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, stamp in (("old.default", 1000), ("new.default", 2000)):
                (root / name).mkdir()
                (root / name / "cookies.sqlite").touch()
                os.utime(root / name / "cookies.sqlite", (stamp, stamp))
            self.assertEqual(config.newest_zen_profile(root), root / "new.default")

    def test_favourite_links_resolve_to_video_ids(self):
        self.assertEqual(config.video_id_from(
            "https://music.youtube.com/watch?v=JZOGJGcFfD8&si=ONTs0_uWYWr5lKJQ"), "JZOGJGcFfD8")
        self.assertEqual(config.video_id_from("https://youtu.be/iqJ5XKrFtco?si=x"), "iqJ5XKrFtco")
        self.assertEqual(config.video_id_from("iqJ5XKrFtco"), "iqJ5XKrFtco")
        self.assertIsNone(config.video_id_from("https://music.youtube.com/playlist?list=PL123"))

    def test_favourites_file_skips_comments_and_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "favourites.txt"
            path.write_text("# mine\nJZOGJGcFfD8\n")
            self.assertEqual(config.add_favourite("https://music.youtube.com/watch?v=JZOGJGcFfD8&si=a", path),
                             "JZOGJGcFfD8")
            config.add_favourite("https://music.youtube.com/watch?v=iqJ5XKrFtco", path)
            self.assertEqual(config.read_favourites(path), ["JZOGJGcFfD8", "iqJ5XKrFtco"])
            with self.assertRaises(SystemExit):
                config.add_favourite("not a link", path)

    def test_profile_path_after_browser_name_is_expanded(self):
        self.assertEqual(config.resolve_cookie_source("firefox:~/p"), f"firefox:{Path.home()}/p")


if __name__ == "__main__":
    unittest.main(verbosity=1)
