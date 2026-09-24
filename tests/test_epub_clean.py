#!/usr/bin/env python3
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from PIL import Image
from support import SOURCE
from gemini_book_epub import export, Reader, XHTML, OPF, EPUB, clean_continuations, prose_paragraphs, Node, text_plan
NS = {'x': XHTML, 'opf': OPF, 'epub': EPUB}


def screen(n, prose='', extra='', model='flash'):
    return f'<section id="screen-{n}" data-model="{model}" data-models="{model}"><h2>Screen {n:04d}<span class="model-badge">Model: {model}</span></h2><div class="prose">{prose}</div>{extra}</section>'


class CleanEPUBTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        (self.folder/'illustrations').mkdir()
        Image.new('RGB', (400, 1400), '#cadbfa').save(self.folder/'illustrations/page.png')
        self.source = self.folder/'translation.html'
        self.output = self.folder/'translation.epub'
        self.figure = '<figure class="book-figure" id="screen-19-illustration-1"><img src="illustrations/page.png" alt="Original art"><figcaption>Screen 0019 · Illustration 1</figcaption></figure>'
        self.html = ('<!doctype html><html>' +
            screen(17, '  A traveler reached the station.\n\nThe train was green and white [continues]\n\n\n', model='flash-lite') +
            screen(18, '[CONTINUES]clothes suited her.\nLine after a single break.\n\n[happy] [scab] [Electronic Book Bonus]') +
            screen(19, 'Caption text is real book text.', self.figure) +
            screen(20, '[continues]') +
            screen(21, '[No readable text on this page.]') +
            screen(22, 'NO TEXT') +
            screen(23, '') +
            screen(24, '[No readable text on this page.]', self.figure.replace('screen-19-illustration-1','screen-24-illustration-1')) +
            '</html>')
        self.source.write_text(self.html)
        self.checkpoint = self.folder/'checkpoint.json'
        self.checkpoint.write_text(json.dumps({'bookTitle':'Fixture Vol. 07','tag':'stable-book-tag','records':[{'id':'one','translation':'unchanged'}]}))

    def tearDown(self): self.tmp.cleanup()

    def book(self):
        result = export(self.source)
        self.assertTrue(result['ok'])
        with zipfile.ZipFile(self.output) as z:
            return result, ET.fromstring(z.read('EPUB/text/reading.xhtml')), ET.fromstring(z.read('EPUB/package.opf')), ET.fromstring(z.read('EPUB/nav.xhtml')), json.loads(z.read('META-INF/bt-export.json')), z.read('EPUB/styles/book.css').decode(), {n:z.read(n) for n in z.namelist()}

    def test_one_spine_continuous_reading_and_all_anchor_targets(self):
        result, root, opf, nav, meta, css, files = self.book()
        self.assertEqual(result['screens'], 8)
        self.assertEqual([n.get('idref') for n in opf.findall('opf:spine/opf:itemref', NS)], ['reading'])
        self.assertEqual([n for n in files if n.endswith('.xhtml')], ['EPUB/text/reading.xhtml','EPUB/nav.xhtml'])
        self.assertEqual(opf.find("opf:manifest/opf:item[@id='reading']", NS).get('href'), 'text/reading.xhtml')
        expected_ids = [f'screen-{n}' for n in range(17,25)]
        self.assertEqual([n.get('id') for n in root.findall('x:body/x:section', NS)], expected_ids)
        links = nav.findall(".//x:nav[@epub:type='toc']//x:a", NS)
        self.assertEqual([n.get('href') for n in links], ['text/reading.xhtml#'+n for n in expected_ids])
        self.assertNotRegex(css, r'(?:break-before|break-after|page-break-before|page-break-after):(?:always|left|right|page)')

    def test_exact_marker_cleanup_and_paragraphs(self):
        result, root, *_ = self.book()
        paragraphs = root.findall(".//x:section[@id='screen-17']/x:div/x:p", NS)
        self.assertEqual([''.join(p.itertext()) for p in paragraphs], ['A traveler reached the station.','The train was green and white'])
        paragraphs = root.findall(".//x:section[@id='screen-18']/x:div/x:p", NS)
        self.assertEqual(paragraphs[0].text, 'clothes suited her.')
        self.assertEqual(paragraphs[0].find('x:br',NS).tail, 'Line after a single break.')
        self.assertEqual(paragraphs[1].text, '[happy] [scab] [Electronic Book Bonus]')
        self.assertNotIn('[continues]', ''.join(root.itertext()).lower())
        self.assertEqual(result['continuationMarkersRemoved'], 3)
        # A capture boundary remains a paragraph boundary; it is not rewritten
        # into a guessed reconstruction of a split sentence.
        self.assertNotIn('whiteclothes', ''.join(root.itertext()))

    def test_marker_spacing_inline_and_case_variants(self):
        cases = {
            '[continues]word':'word', 'word[continues]':'word',
            'word[CoNtInUeS]word':'word word',
            'word [continues] word':'word word',
            'word[continues], next':'word, next',
            '( [continues] word)':'(word)',
            '<Preserva[continues]>':'<Preserva>',
            '<[continues]Preserva>':'<Preserva>',
            'word\n[continues]\n\nnext':'word\n\n\nnext',
            '[continued] [continue] [happy]':'[continued] [continue] [happy]',
            '[https://example.com/]':'[https://example.com/]',
        }
        for source, expected in cases.items():
            with self.subTest(source=source): self.assertEqual(clean_continuations(source),expected)

    def test_only_generated_heading_and_caption_removed(self):
        self.source.write_text(self.html.replace('Caption text is real book text.', 'Screen 0019 is meaningful prose.')
            .replace(self.figure, self.figure + '<h2>Actual Chapter Title</h2><figure><figcaption>The original caption stays.</figcaption></figure>'))
        _, root, *_ = self.book()
        self.assertEqual([n.text for n in root.findall('.//x:h2',NS)], ['Actual Chapter Title'])
        self.assertFalse(root.findall(".//x:span[@class='model-badge']",NS))
        captions = [n.text for n in root.findall('.//x:figcaption',NS)]
        self.assertEqual(captions,['The original caption stays.'])
        self.assertIn('Screen 0019 is meaningful prose.', ''.join(root.itertext()))

    def test_empty_capture_zero_box_anchors_and_art_survives(self):
        _, root, _, _, meta, css, _ = self.book()
        for n in (20,21,22,23):
            section = root.find(f"x:body/x:section[@id='screen-{n}']",NS)
            self.assertEqual(section.get('class'),'screen-anchor')
            self.assertEqual(''.join(section.itertext()),'')
            self.assertEqual(len(section),0)
            self.assertEqual(section.get('data-model'),'flash')
        section = root.find("x:body/x:section[@id='screen-24']",NS)
        self.assertEqual(len(section.findall('.//x:img',NS)),1)
        self.assertNotIn('[No readable text on this page.]',''.join(section.itertext()))
        self.assertIn('height:0',css)
        self.assertEqual(len(meta['screens']),8)

    def test_other_bracket_notes_and_embedded_blank_placeholder_preserved(self):
        text = '[No readable text on this page.] This sentence quotes a technical note.\n\n[With E-book Bonus] [scab] [happy] [NO TEXT]'
        self.source.write_text('<html>'+screen(1,text)+'</html>')
        _, root, *_ = self.book()
        actual = '\n\n'.join(''.join(p.itertext()) for p in root.findall('.//x:p',NS))
        self.assertEqual(actual,text)

    def test_models_source_sha_and_saved_source_unchanged(self):
        originals = {p:p.read_bytes() for p in [self.source,self.checkpoint,self.folder/'illustrations/page.png']}
        _, root, _, _, meta, _, _ = self.book()
        self.assertEqual(meta['format'],1)
        self.assertEqual(meta['exportRevision'],'continuous-v1')
        self.assertEqual(meta['readingLayout'],'continuous')
        self.assertEqual(meta['sourceSHA256'],hashlib.sha256(originals[self.source]).hexdigest())
        self.assertEqual(meta['screens'][0],{'screen':17,'model':'flash-lite','models':'flash-lite'})
        self.assertEqual(root.find("x:body/x:section[@id='screen-17']",NS).get('data-model'),'flash-lite')
        for path, data in originals.items(): self.assertEqual(path.read_bytes(),data)

    def test_figure_css_fits_without_forcing_entire_figure_unbreakable(self):
        _, root, _, _, _, css, files = self.book()
        self.assertIn('width:auto;height:auto;max-width:100%;max-height:85vh',css)
        self.assertIn('figure{margin:.5em 0;break-inside:auto;page-break-inside:auto}',css)
        self.assertNotIn('white-space:pre-wrap',css)
        for path, data in files.items():
            if path.endswith('.jpg'):
                with Image.open(io.BytesIO(data)) as image:
                    self.assertEqual(image.width/image.height,400/1400)

    def test_prose_single_explicit_br_and_blankline_handling(self):
        n=Node('div',{'class':'prose'},['\n\n  First & second  ',Node('br'), 'Second line\n\n\nThird.\n\n'])
        self.assertEqual(prose_paragraphs(n),[['First & second','Second line'],['Third.']])

    def test_layout_text_marker_removed_without_mutating_source_node(self):
        original='[continues]English cover text [continues]'
        node=Node('div',{'class':'translated-block title','style':'left:0%;top:0%;width:80%;height:30%;font-size:3cqw'},[original])
        plan=text_plan(node,1000,1400)
        self.assertEqual(' '.join(plan['lines']),'English cover text')
        self.assertEqual(node.text(),original)

    def test_atomic_failure_preserves_successful_epub(self):
        self.book(); previous=self.output.read_bytes()
        self.source.write_text(self.html.replace('illustrations/page.png','illustrations/missing.png'))
        with self.assertRaises(OSError): export(self.source)
        self.assertEqual(self.output.read_bytes(),previous)

    def test_zip_contract_and_no_network_resource_dependency(self):
        self.book()
        with zipfile.ZipFile(self.output) as z:
            first=z.infolist()[0]
            self.assertEqual(first.filename,'mimetype'); self.assertEqual(first.compress_type,zipfile.ZIP_STORED)
            self.assertEqual(z.read(first),b'application/epub+zip')
            reading=ET.fromstring(z.read('EPUB/text/reading.xhtml'))
            for image in reading.findall('.//x:img',NS):
                self.assertIn('EPUB/'+image.get('src')[3:],z.namelist())


if __name__=='__main__': unittest.main(verbosity=2)
