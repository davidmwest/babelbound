"""Smoke the complete synthetic demo through the production EPUB exporter."""

import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET
import zipfile

from PIL import Image

from support import ROOT

spec = importlib.util.spec_from_file_location("bt_demo", ROOT / "scripts" / "demo.py")
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)
NS = {"x": "http://www.w3.org/1999/xhtml", "o": "http://www.idpf.org/2007/opf",
      "dc": "http://purl.org/dc/elements/1.1/"}


class DemoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.output = self.folder / "preview with spaces"

    def tearDown(self):
        self.temp.cleanup()

    def test_offline_demo_has_embedded_artwork_clean_reading_order_and_truthful_label(self):
        with patch("socket.socket", side_effect=AssertionError("Demo must be offline")), \
             patch("socket.create_connection", side_effect=AssertionError("Demo must be offline")), \
             patch("urllib.request.urlopen", side_effect=AssertionError("Demo must be offline")), \
             patch("subprocess.run", side_effect=AssertionError("Demo must not launch other processes")):
            result = demo.create_demo(self.output)
        html = result["html"].read_text(encoding="utf-8")
        self.assertIn(demo.NOTICE, html)
        self.assertIn('[continues]', html)
        self.assertIn('src="illustrations/harbor.png"', html)
        self.assertTrue(result["illustration"].is_file())
        with zipfile.ZipFile(result["epub"]) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(archive.read("mimetype"), b"application/epub+zip")
            for name in archive.namelist():
                if name.endswith((".xml", ".xhtml", ".opf")):
                    ET.fromstring(archive.read(name))
            package = ET.fromstring(archive.read("EPUB/package.opf"))
            self.assertEqual(package.find("o:metadata/dc:title", NS).text, demo.TITLE)
            reading = ET.fromstring(archive.read("EPUB/text/reading.xhtml"))
            text = " ".join(reading.itertext())
            self.assertIn(demo.NOTICE, text)
            self.assertNotIn("[continues]", text)
            self.assertLess(text.index("At dusk, Mira"), text.index("beside the lighthouse door"))
            self.assertLess(text.index("beside the lighthouse door"), text.index("End of synthetic preview."))
            self.assertEqual([node.get("id") for node in reading.findall("x:body/x:section", NS)],
                             ["screen-1", "screen-2", "screen-3"])
            images = reading.findall(".//x:img", NS)
            self.assertEqual(len(images), 1)
            self.assertEqual(images[0].get("src").split("/")[:2], ["..", "images"])
            image_path = "EPUB/" + images[0].get("src")[3:]
            with Image.open(io.BytesIO(archive.read(image_path))) as image:
                self.assertEqual(image.format, "JPEG")
                self.assertEqual(image.size, (900, 1200))
            self.assertFalse(reading.findall(".//x:script", NS))
        self.assertEqual(sorted(str(path.relative_to(self.output)) for path in self.output.rglob("*") if path.is_file()),
                         ["illustrations/harbor.png", "translation.epub", "translation.html"])

    def test_existing_directory_file_and_symlink_are_never_overwritten(self):
        cases = [(self.folder / "existing-dir", "dir"), (self.folder / "existing-file", "file"),
                 (self.folder / "existing-link", "symlink")]
        for path, kind in cases:
            with self.subTest(kind=kind):
                if kind == "dir":
                    path.mkdir()
                    (path / "personal.txt").write_bytes(b"preserve me")
                elif kind == "file":
                    path.write_bytes(b"preserve me")
                else:
                    path.symlink_to(self.folder / "missing target")
                with patch.object(demo, "export", side_effect=AssertionError("Refuse before exporting")):
                    with self.assertRaises(FileExistsError):
                        demo.create_demo(path)
                if kind == "dir":self.assertEqual((path / "personal.txt").read_bytes(), b"preserve me")
                elif kind == "file":self.assertEqual(path.read_bytes(), b"preserve me")
                else:self.assertTrue(path.is_symlink())

    def test_failed_export_does_not_publish_partial_output(self):
        with patch.object(demo, "export", side_effect=ValueError("fixture export failure")):
            with self.assertRaisesRegex(ValueError, "fixture export failure"):
                demo.create_demo(self.output)
        self.assertFalse(self.output.exists())
        self.assertEqual(list(self.folder.iterdir()), [])

    def test_command_prints_local_outputs_and_rejects_repeat(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            self.assertEqual(demo.main(["--output", str(self.output)]), 0)
            self.assertEqual(demo.main(["--output", str(self.output)]), 1)
        self.assertIn(str(self.output / "translation.epub"), stdout.getvalue())
        self.assertIn("No model translation", stdout.getvalue())
        self.assertIn("Choose a new --output directory", stderr.getvalue())


if __name__ == "__main__":
    unittest.main(verbosity=2)
