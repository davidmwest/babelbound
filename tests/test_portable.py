#!/usr/bin/env python3
"""Behavioral regressions for ebook asset safety, cache freshness, and quality."""

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image

from support import SOURCE
MODULE = SOURCE / "gemini_book_portable.py"
spec = importlib.util.spec_from_file_location("portable", MODULE)
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)


class PortableAssets(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.job = Path(self.tmp.name) / "Book-Test"
        self.illustrations = self.job / "illustrations"
        self.illustrations.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def make(self, name="00001-source-abc.png", size=(400, 200), color="red", mode="RGB"):
        path = self.illustrations / name
        Image.new(mode, size, color).save(path)
        return "illustrations/" + name, path

    def test_dimensions_and_original_preservation(self):
        src, original = self.make(size=(5000, 3000))
        before = original.read_bytes()
        path, generated, source_size, target_size = portable.asset(self.job, src)
        self.assertTrue(generated)
        self.assertEqual(source_size, len(before))
        self.assertEqual(target_size, path.stat().st_size)
        self.assertEqual(before, original.read_bytes())
        with Image.open(path) as image:
            self.assertEqual(image.format, "JPEG")
            self.assertEqual(image.mode, "RGB")
            self.assertEqual(image.size, (2200, 1320))

    def test_small_art_not_upscaled(self):
        src, _original = self.make(size=(420, 800))
        path, *_ = portable.asset(self.job, src)
        with Image.open(path) as image:
            self.assertEqual(image.size, (420, 800))

    def test_transparency_composited_white(self):
        src, _original = self.make(mode="RGBA", color=(10, 20, 30, 0))
        path, *_ = portable.asset(self.job, src)
        with Image.open(path) as image:
            self.assertTrue(all(value >= 254 for value in image.getpixel((20, 20))))

    def test_palette_transparency_composited_white(self):
        original = self.illustrations / "palette.png"
        image = Image.new("P", (40, 40), 0)
        image.putpalette([0, 0, 0, 255, 0, 0] + [0] * 762)
        image.save(original, transparency=0)
        path, *_ = portable.asset(self.job, "illustrations/palette.png")
        with Image.open(path) as image:
            self.assertEqual(image.getpixel((20, 20)), (255, 255, 255))

    def test_reuses_cache_without_rewrite(self):
        src, _original = self.make()
        path, *_ = portable.asset(self.job, src)
        before = path.read_bytes(), path.stat().st_mtime_ns
        self.assertFalse(portable.asset(self.job, src)[1])
        self.assertEqual(before, (path.read_bytes(), path.stat().st_mtime_ns))

    def test_stale_source_regenerates_same_deterministic_path(self):
        src, original = self.make()
        path, *_ = portable.asset(self.job, src)
        before = path.read_bytes()
        Image.new("RGB", (400, 200), "blue").save(original)
        target, generated, *_ = portable.asset(self.job, src)
        self.assertEqual(path, target)
        self.assertTrue(generated)
        self.assertNotEqual(before, target.read_bytes())
        metadata = json.loads(Path(str(target) + ".json").read_text())
        self.assertEqual(metadata["sourceSHA256"], hashlib.sha256(original.read_bytes()).hexdigest())

    def test_corrupt_cache_regenerates(self):
        src, _original = self.make()
        path, *_ = portable.asset(self.job, src)
        before = path.read_bytes()
        path.write_bytes(b"corrupt")
        self.assertTrue(portable.asset(self.job, src)[1])
        self.assertEqual(before, path.read_bytes())

    def test_missing_metadata_regenerates(self):
        src, _original = self.make()
        path, *_ = portable.asset(self.job, src)
        Path(str(path) + ".json").unlink()
        self.assertTrue(portable.asset(self.job, src)[1])

    def test_missing_source_not_hidden_by_cache(self):
        src, original = self.make()
        portable.asset(self.job, src)
        original.unlink()
        with self.assertRaises(FileNotFoundError):
            portable.asset(self.job, src)

    def test_supported_names_and_extension_collision(self):
        png, _original = self.make(name="title page 日本語.png")
        jpg, _original = self.make(name="title page 日本語.jpg")
        png_path, *_ = portable.asset(self.job, png)
        jpg_path, *_ = portable.asset(self.job, jpg)
        self.assertNotEqual(png_path, jpg_path)
        self.assertEqual(png_path.name, "title page 日本語.png.ipad-v1.jpg")

    def test_path_rejections(self):
        for src in ("../secret.png", "/etc/secret.png", "illustrations/../secret.png",
                    "illustrations/../../secret.jpg", "illustrations/sub/page.png",
                    "illustrations//page.png", "./illustrations/page.png",
                    "file:///tmp/page.png", "https://example.org/pic.jpg",
                    "illustrations/vector.svg", "illustrations\\page.png", "illustrations/x\x00.png"):
            with self.subTest(src=src), self.assertRaises(ValueError):
                portable.asset(self.job, src)

    def test_source_symlink_cannot_escape_illustrations(self):
        outside = self.job / "outside.png"
        Image.new("RGB", (20, 20), "red").save(outside)
        (self.illustrations / "source.png").symlink_to(outside)
        with self.assertRaises(ValueError):
            portable.asset(self.job, "illustrations/source.png")

    def test_cache_symlink_cannot_write_outside_illustrations(self):
        src, _original = self.make()
        elsewhere = self.job / "elsewhere"
        elsewhere.mkdir()
        (self.illustrations / "portable").symlink_to(elsewhere)
        with self.assertRaises(ValueError):
            portable.asset(self.job, src)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_foreign_format_disguised_as_png_rejected(self):
        path = self.illustrations / "pretend.png"
        Image.new("RGB", (30, 30), "red").save(path, format="GIF")
        with self.assertRaises(ValueError):
            portable.asset(self.job, "illustrations/pretend.png")

    def test_manifest_prepares_sources_and_crops_once(self):
        src, _ = self.make("source.png")
        crop, _ = self.make("crop.png")
        manifest = {"records": [{"sourceSrc": src, "illustrations": [{"src": crop}]},
                                {"sourceSrc": src, "illustrations": [{"src": crop}]},
                                {"illustrations": []}]}
        first = portable.prepare_assets(self.job, manifest)
        self.assertEqual(first["assetCount"], 2)
        self.assertEqual(first["generated"], 2)
        self.assertEqual(first["reused"], 0)
        second = portable.prepare_assets(self.job, manifest)
        self.assertEqual(second["generated"], 0)
        self.assertEqual(second["reused"], 2)
        self.assertEqual(second["sourceBytes"], first["sourceBytes"])
        self.assertEqual(second["portableBytes"], first["portableBytes"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
