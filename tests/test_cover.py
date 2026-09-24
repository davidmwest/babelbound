import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from PIL import Image

from support import SOURCE
from gemini_book_epub import export, XHTML, OPF
NS={'x':XHTML,'o':OPF}
TITLE='The Glass Harbor - Vol. 07'
TRANSCRIPT='●REC\n\nThe Glass Harbor. 7\n\nAvery Quill\nIllustration: Robin Oak\n\nFixture Press'

class CoverTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.folder=Path(self.temp.name)
        (self.folder/'illustrations').mkdir()
        Image.new('RGB',(300,450),'red').save(self.folder/'illustrations/first.png')
        Image.new('RGB',(300,450),'blue').save(self.folder/'illustrations/second.png')
        self.source=self.folder/'translation.html'
        (self.folder/'checkpoint.json').write_text(json.dumps({'bookTitle':TITLE,'tag':'cover-test'}))

    def tearDown(self): self.temp.cleanup()

    def section(self, text=TRANSCRIPT, number=1, image='first', cls='book-figure'):
        return f'<section id="screen-{number}" data-model="flash"><h2>Screen {number:04d}</h2><div class="prose">{text}</div><figure class="{cls}"><img src="illustrations/{image}.png" alt="Book artwork"/></figure></section>'

    def build(self, markup):
        self.source.write_text('<html>'+markup+'</html>');source=self.source.read_bytes()
        export(self.source)
        self.assertEqual(self.source.read_bytes(),source)
        with zipfile.ZipFile(self.source.with_suffix('.epub')) as z:
            package=ET.fromstring(z.read('EPUB/package.opf'))
            reading=ET.fromstring(z.read('EPUB/text/reading.xhtml'))
            cover=package.find("o:manifest/o:item[@properties='cover-image']",NS)
            metadata=json.loads(z.read('META-INF/bt-export.json'))
            self.assertEqual(metadata['sourceSHA256'],hashlib.sha256(source).hexdigest())
            if cover is not None:self.assertIn('EPUB/'+cover.get('href'),z.namelist())
            return package,reading,cover,metadata

    def test_untagged_title_capture_has_books_cover_metadata_without_extra_page(self):
        package,reading,cover,metadata=self.build(self.section())
        self.assertIsNotNone(cover)
        self.assertEqual(cover.get('href'),reading.find('.//x:img',NS).get('src')[3:])
        legacy=package.find("o:metadata/o:meta[@name='cover']",NS)
        self.assertEqual(legacy.get('content'),cover.get('id'))
        self.assertEqual(len(package.findall('o:spine/o:itemref',NS)),1)
        self.assertEqual(len(reading.findall('.//x:img',NS)),1)
        self.assertEqual(metadata['coverSelection'],'title-matched-frontmatter')

    def test_explicit_later_cover_takes_precedence(self):
        _,reading,cover,metadata=self.build(self.section()+self.section('Reviewed cover',2,'second','book-figure cover'))
        images=reading.findall('.//x:img',NS)
        self.assertEqual(cover.get('href'),images[1].get('src')[3:])
        self.assertNotEqual(cover.get('href'),images[0].get('src')[3:])
        self.assertEqual(metadata['coverSelection'],'explicit')

    def test_interior_illustration_is_not_a_cover(self):
        for prose in ['The characters returned home.', 'She read The Glass Harbor. 7 that night.',TRANSCRIPT+'\n'+('long prose '*200)]:
            with self.subTest(prose=prose[:40]):
                self.assertIsNone(self.build(self.section(prose))[2])

    def test_partial_job_is_not_a_cover(self):
        self.assertIsNone(self.build(self.section(number=12))[2])

    def test_ambiguous_images_do_not_get_arbitrary_cover(self):
        markup=self.section().replace('</section>','<figure><img src="illustrations/second.png" alt="Other illustration"/></figure></section>')
        self.assertIsNone(self.build(markup)[2])

    def test_volume_mismatch_is_not_marked(self):
        self.assertIsNone(self.build(self.section(TRANSCRIPT.replace('Harbor. 7','Harbor. 8')))[2])

    def test_separate_volume_line_must_match(self):
        for label in ['8', 'Vol. 8', 'Volume 08']:
            self.assertIsNone(self.build(self.section(TRANSCRIPT.replace('Harbor. 7','Harbor.\n'+label)))[2])
        for label in ['7', 'Vol. 07', 'Volume 7']:
            self.assertIsNotNone(self.build(self.section(TRANSCRIPT.replace('Harbor. 7','Harbor.\n'+label)))[2])

    def test_volume_label_and_punctuation_variations(self):
        for line in ['The Glass Harbor — Volume 07','THE GLASS HARBOR: Vol. 7']:
            with self.subTest(line=line):self.assertIsNotNone(self.build(self.section(line+'\nAuthor'))[2])

    def test_placeholder_title_does_not_claim_artwork(self):
        (self.folder/'checkpoint.json').write_text(json.dumps({'bookTitle':'Book translation'}))
        self.assertIsNone(self.build(self.section('Book translation'))[2])

if __name__=='__main__':unittest.main(verbosity=2)
