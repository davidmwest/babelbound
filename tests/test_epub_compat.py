#!/usr/bin/env python3
import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from PIL import Image
from support import SOURCE
from gemini_book_epub import export, Reader, XHTML, OPF, DC, EPUB, text_plan, Node, wrap_text, font_for

NS = {'x': XHTML, 'opf': OPF, 'dc': DC, 'epub': EPUB}
HTML = '''<!doctype html><html><title>Book translation</title><style>bad remote CSS is ignored</style>
<section id="screen-1" data-model="flash-lite" data-models="flash-lite"><h2>Screen 0001<span class="model-badge">Model: Flash-Lite</span></h2>
<figure class="book-figure cover" id="art1"><div class="original-page" style="aspect-ratio:.7/1">
<img class="page-art" src="illustrations/cover.png" alt="Cover" style="width:140%;height:100%;left:-20%;top:0%">
<span class="text-mask" style="left:10%;top:20%;width:80%;height:30%;background:#fff"></span>
<div class="translated-block title" style="left:10%;top:20%;width:80%;height:30%;font-size:5cqw;line-height:1.2;text-align:center;background:#fff">Test Book\nA&amp;B “volume”</div>
</div><figcaption>Screen 1 · Illustration 1</figcaption></figure>
<details class="transcript"><summary>Plain text translation (reviewed)</summary><div class="prose">1\n\nA&amp;B “quoted”\nExact — punctuation!\n\nReviewed text.</div></details></section>
<section id="screen-7" data-model="flash" data-models="flash,pro"><h2>Screen 0007<span class="model-badge">Model: Flash (selection uncertain)</span></h2><div class="prose">Second screen\n\nTwo paragraphs.</div><figure class="book-figure"><img src="illustrations/second.png" alt="Second image" loading="lazy"><figcaption>Second</figcaption></figure><figure><img src="illustrations/second.png" alt="Repeated illustration"></figure><script>alert('never export')</script></section></html>'''


class EPUBTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        (self.folder/'illustrations').mkdir()
        Image.new('RGB', (400, 500), '#f9cadb').save(self.folder/'illustrations/cover.png')
        Image.new('RGB', (3400, 3000), '#d2eef8').save(self.folder/'illustrations/second.png')
        self.source = self.folder/'translation.html'
        self.source.write_text(HTML)
        self.out = self.folder/'translation.epub'
        (self.folder/'checkpoint.json').write_text(json.dumps({'bookTitle': 'Test Book - Vol. 01', 'author': 'Known Author', 'tag': 'fixture-stable-id'}))

    def tearDown(self):
        self.tmp.cleanup()

    def build(self):
        return export(self.source)

    def test_complete_container_order_spine_and_metadata(self):
        result = self.build()
        self.assertTrue(result['ok']); self.assertEqual(result['screens'], 2)
        self.assertEqual(result['images'], 3); self.assertEqual(result['illustratedLayouts'], 1)
        with zipfile.ZipFile(self.out) as z:
            first = z.infolist()[0]
            self.assertEqual(first.filename, 'mimetype'); self.assertEqual(first.compress_type, zipfile.ZIP_STORED)
            self.assertEqual(first.extra, b''); self.assertEqual(z.read(first), b'application/epub+zip')
            ET.fromstring(z.read('META-INF/container.xml'))
            opf = ET.fromstring(z.read('EPUB/package.opf'))
            self.assertEqual(opf.find('opf:metadata/dc:title', NS).text, 'Test Book - Vol. 01')
            self.assertEqual(opf.find('opf:metadata/dc:creator', NS).text, 'Known Author')
            self.assertEqual(opf.find('opf:metadata/dc:language', NS).text, 'en')
            self.assertEqual([n.get('idref') for n in opf.findall('opf:spine/opf:itemref', NS)], ['reading'])
            self.assertEqual(len(opf.findall("opf:metadata/opf:meta[@property='dcterms:modified']", NS)), 1)
            manifest = opf.findall('opf:manifest/opf:item', NS)
            self.assertEqual(len([n for n in manifest if n.get('properties') == 'nav']), 1)
            self.assertEqual(len([n for n in manifest if n.get('properties') == 'cover-image']), 1)
            for node in manifest:
                self.assertIn('EPUB/' + node.get('href'), z.namelist())
            toc = ET.fromstring(z.read('EPUB/nav.xhtml'))
            self.assertEqual([n.get('href') for n in toc.findall(".//x:nav[@epub:type='toc']//x:a", NS)], ['text/reading.xhtml#screen-1', 'text/reading.xhtml#screen-7'])
            self.assertLess(result['bytes'], 150000)

    def test_exact_prose_model_and_safe_reading_markup(self):
        self.build()
        source = Reader(HTML).root
        expected = [n.text() for n in source.walk() if n.has('prose')]
        actual = []
        with zipfile.ZipFile(self.out) as z:
            for path in ['EPUB/text/reading.xhtml']:
                data = z.read(path); root = ET.fromstring(data)
                actual.extend('\n\n'.join((p.text or '') + ''.join(('\n' if child.tag == '{'+XHTML+'}br' else '') + ''.join(child.itertext()) + (child.tail or '') for child in p) for p in n.findall('x:p',NS)) for n in root.findall(".//x:div[@class='prose']", NS))
                self.assertNotIn(b'<script', data); self.assertNotIn(b'<details', data)
                self.assertNotIn(b'loading=', data); self.assertNotIn(b'cqw', data)
                self.assertNotIn(b'http://example', data)
            self.assertEqual(actual, expected)
            root = ET.fromstring(z.read('EPUB/text/reading.xhtml'))
            self.assertEqual(root.find("x:body/x:section[@id='screen-7']", NS).get('data-model'), 'flash')
            self.assertEqual(root.find("x:body/x:section[@id='screen-7']", NS).get('data-models'), 'flash,pro')
            self.assertNotIn('Model: Flash (selection uncertain)', ''.join(root.itertext()))
            models = json.loads(z.read('META-INF/bt-export.json'))
            self.assertEqual(models['screens'][1]['screen'], 7)
            self.assertEqual(models['sourceSHA256'], hashlib.sha256(self.source.read_bytes()).hexdigest())

    def test_images_packaged_reused_and_bounded(self):
        self.build()
        with zipfile.ZipFile(self.out) as z:
            images = [p for p in z.namelist() if p.startswith('EPUB/images/')]
            self.assertEqual(len(images), 2)  # Composed cover + reused ordinary image.
            for path in images:
                with Image.open(io.BytesIO(z.read(path))) as image:
                    self.assertEqual(image.mode, 'RGB'); self.assertEqual(image.format, 'JPEG')
                    self.assertLessEqual(max(image.size), 2200)
                    self.assertLessEqual(image.width*image.height, 5600000)
            opf = ET.fromstring(z.read('EPUB/package.opf'))
            cover = opf.find("opf:manifest/opf:item[@properties='cover-image']", NS).get('href')
            self.assertIn('composed-', cover)
            with Image.open(io.BytesIO(z.read('EPUB/' + cover))) as image:
                # The translated title adds dark text to an otherwise pink/white image.
                self.assertLess(image.convert('L').getextrema()[0], 80)

    def test_source_and_originals_never_changed(self):
        paths = [self.source, self.folder/'checkpoint.json', *self.folder.glob('illustrations/*.png')]
        original = {p: p.read_bytes() for p in paths}
        self.build()
        for p, data in original.items():
            self.assertEqual(p.read_bytes(), data)

    def test_atomic_failure_keeps_previous_export(self):
        self.build(); previous = self.out.read_bytes()
        self.source.write_text(HTML.replace('illustrations/second.png', 'illustrations/missing.png'))
        with self.assertRaises(OSError): self.build()
        self.assertEqual(self.out.read_bytes(), previous)
        self.assertEqual(list(self.folder.glob('.translation.epub.*.tmp')), [])

    def test_reject_escaping_and_remote_resources(self):
        for src in ('../secret.png', '/tmp/file.png', 'https://example.com/art.png', 'file:///tmp/art.png', 'illustrations/%2e%2e/secret.png', 'illustrations/cover.png?other=1', 'illustrations\\cover.png', 'data:image/svg+xml;base64,AAAA'):
            with self.subTest(src=src):
                self.source.write_text(HTML.replace('illustrations/cover.png', src))
                with self.assertRaises(ValueError): self.build()

    def test_reject_symlink_outside_illustrations(self):
        outside = self.folder/'outside.png'; Image.new('RGB', (10, 10)).save(outside)
        (self.folder/'illustrations/cover.png').unlink()
        (self.folder/'illustrations/cover.png').symlink_to(outside)
        with self.assertRaises(ValueError): self.build()

    def test_reject_empty_or_duplicate_screens(self):
        for markup in ('<html>No screens</html>', HTML.replace('screen-7', 'screen-1')):
            self.source.write_text(markup)
            with self.assertRaises(ValueError): self.build()

    def test_output_cannot_overwrite_source(self):
        with self.assertRaises(ValueError): export(self.source, self.source)
        self.assertEqual(self.source.read_text(), HTML)

    def test_data_uri_supported_and_no_external_dependency(self):
        encoded = base64.b64encode((self.folder/'illustrations/cover.png').read_bytes()).decode()
        self.source.write_text(HTML.replace('illustrations/cover.png', 'data:image/png;base64,' + encoded))
        self.build()
        with zipfile.ZipFile(self.out) as z:
            self.assertNotIn(b'data:', z.read('EPUB/text/reading.xhtml'))

    def test_identity_stable_across_pages_and_renames(self):
        self.build()
        with zipfile.ZipFile(self.out) as z:
            before = ET.fromstring(z.read('EPUB/package.opf')).find('opf:metadata/dc:identifier', NS).text
        self.source.write_text(HTML.replace('Second screen', 'Reviewed second screen'))
        export(self.source, title='Renamed Title')
        with zipfile.ZipFile(self.out) as z:
            after = ET.fromstring(z.read('EPUB/package.opf')).find('opf:metadata/dc:identifier', NS).text
        self.assertEqual(before, after)

    def test_inferred_title_uses_translated_cover_and_volume(self):
        (self.folder/'checkpoint.json').unlink()
        self.assertEqual(self.build()['title'], 'Test Book A&B “volume” — Vol. 01')

    def test_wrap_preserves_all_words_in_tiny_box_and_vertical(self):
        value = 'Supercalifragilisticexpialidocious word\nNext line'
        font = font_for(20)
        lines = wrap_text(value, font, 50)
        self.assertEqual(''.join(lines).replace(' ', ''), value.replace(' ', '').replace('\n', ''))
        node = Node('div', {'class': 'translated-block title', 'style': 'width:4%;height:65%;writing-mode:vertical-rl;font-size:3cqw'}, [value])
        plan = text_plan(node, 1000, 1400)
        self.assertTrue(plan['vertical'])
        self.assertLessEqual(len(plan['lines'])*plan['advance'], plan['ih'])


if __name__ == '__main__': unittest.main(verbosity=2)
