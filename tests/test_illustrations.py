#!/usr/bin/env python3
"""Synthetic regressions for committed artwork extraction and publication."""

import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image, ImageDraw

from support import SOURCE  # Adds the actual production helpers to sys.path.
import gemini_book_illustrations as illustrations


class IllustrationExtraction(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.job = Path(self.tmp.name) / "Book-Synthetic"
        self.sources = self.job / "sources"
        self.sources.mkdir(parents=True)
        self.output = self.job / "illustrations"
        self.manifest = self.output / "manifest.json"
        self.args = SimpleNamespace(
            job=self.job, output_dir=None, overrides=None, layouts=None,
            force=False, direction="rtl", asset_prefix="illustrations",
        )

    def page(self, index):
        image = Image.new("RGB", (400, 300), "white")
        draw = ImageDraw.Draw(image)
        # Midtone artwork on a white page exercises the real detector.
        for x in range(90, 310):
            draw.line((x, 55, x, 245), fill=(70 + x // 3, 90, 140))
        path = self.sources / f"{index:05d}.png"
        image.save(path)
        return path

    def checkpoint(self, indices, pending=None):
        value = {"records": [{"index": index, "sourceHash": f"synthetic-{index}"}
                             for index in indices]}
        if pending is not None:
            value["pending"] = {"index": pending, "sent": False}
        (self.job / "checkpoint.json").write_text(json.dumps(value), encoding="utf-8")

    def review(self, filename, value):
        (self.job / filename).write_text(
            json.dumps({"version": 1, "screens": {"1": value}}), encoding="utf-8")

    def snapshot_output(self):
        return {path.name: (path.read_bytes(), path.stat().st_mtime_ns)
                for path in self.output.iterdir() if path.is_file()}

    def test_only_committed_sources_are_read_and_originals_stay_unchanged(self):
        original = self.page(1)
        before = original.read_bytes()
        # Decoding either of these would fail: neither belongs to committed work.
        (self.sources / "00002.png").write_bytes(b"pending capture is not a PNG")
        (self.sources / "00099.png").write_bytes(b"unreferenced capture is not a PNG")
        self.checkpoint([1], pending=2)

        result = illustrations.run(self.args)

        self.assertEqual(result["sourceCount"], 1)
        self.assertEqual(result["illustratedScreens"], 1)
        records = json.loads(self.manifest.read_text())["records"]
        self.assertEqual([record["screenIndex"] for record in records], [1])
        self.assertEqual(records[0]["detection"], "automatic")
        self.assertTrue(records[0]["illustrations"])
        self.assertEqual(original.read_bytes(), before)
        self.assertEqual((self.job / records[0]["sourceSrc"]).read_bytes(), before)

    def test_mismatched_review_hashes_are_rejected_without_replacing_manifest(self):
        self.page(1)
        self.checkpoint([1])
        illustrations.run(self.args)
        before = self.manifest.read_bytes()
        for filename, fields in (
            ("illustration-overrides.json", {"boxes": [[90, 55, 310, 245]]}),
            ("illustration-layouts.json", {"pageBox": [0, 0, 400, 300], "blocks": []}),
        ):
            with self.subTest(review=filename):
                self.review(filename, dict(fields, sourceSHA256="0" * 64))
                with self.assertRaisesRegex(ValueError, "sourceSHA256 does not match"):
                    illustrations.run(self.args)
                self.assertEqual(self.manifest.read_bytes(), before)
                (self.job / filename).unlink()

    def test_unchanged_sources_reuse_assets_and_manifest_without_detection(self):
        self.page(1)
        self.checkpoint([1])
        illustrations.run(self.args)
        before = self.snapshot_output()

        with patch.object(illustrations, "detect_artwork", side_effect=AssertionError("cache miss")):
            result = illustrations.run(self.args)

        self.assertEqual(result["reused"], 1)
        self.assertFalse(result["changed"])
        self.assertEqual(self.snapshot_output(), before)

    def test_failure_after_processing_a_new_screen_keeps_previous_manifest(self):
        self.page(1)
        self.checkpoint([1])
        illustrations.run(self.args)
        before = self.snapshot_output()
        self.page(2)
        self.checkpoint([1, 2, 3])  # Screen 3 is committed, but its capture is missing.

        with self.assertRaisesRegex(ValueError, "Screen 3: committed source PNG is missing"):
            illustrations.run(self.args)

        after = self.snapshot_output()
        for name, previous in before.items():
            self.assertEqual(after[name], previous)
        self.assertTrue(any(name.startswith("00002-") for name in after))
        self.assertEqual(json.loads(self.manifest.read_text())["sourceCount"], 1)
        # New content-addressed crops may remain; the published manifest must not change.

    def test_reviewed_boxes_preserve_order_and_exact_source_pixels(self):
        source = self.page(1)
        self.checkpoint([1])
        boxes = [[90, 55, 150, 120], [230, 150, 310, 245]]
        self.review("illustration-overrides.json", {
            "sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "boxes": boxes,
        })

        result = illustrations.run(self.args)

        self.assertEqual(result["illustrationCount"], 2)
        record = json.loads(self.manifest.read_text())["records"][0]
        self.assertEqual(record["detection"], "reviewed")
        self.assertEqual([item["bbox"] for item in record["illustrations"]], boxes)
        with Image.open(source) as image:
            for box, item in zip(boxes, record["illustrations"]):
                with Image.open(self.job / item["src"]) as crop:
                    expected = image.crop(box)
                    self.assertEqual(crop.size, expected.size)
                    self.assertEqual(crop.tobytes(), expected.tobytes())


if __name__ == "__main__":
    unittest.main()
