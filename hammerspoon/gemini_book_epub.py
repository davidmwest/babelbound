#!/usr/bin/env python3
"""Export a saved BT translation.html as an offline, reflowable EPUB 3.

The saved HTML is the authoritative translation. No page is retranslated and
no network resources are loaded. All local artwork is packaged in the EPUB;
reviewed positioned layouts become composed artwork with a visible transcript.
Capture boundaries stay navigable without becoming artificial chapter breaks.
"""
from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
from typing import Iterator
from urllib.parse import unquote, urlsplit
import uuid
import xml.etree.ElementTree as ET
import zipfile

from PIL import Image, ImageColor, ImageDraw, ImageFont, ImageOps
from gemini_book_portable import asset, MAX_EDGE, JPEG_QUALITY

XHTML = 'http://www.w3.org/1999/xhtml'
EPUB = 'http://www.idpf.org/2007/ops'
OPF = 'http://www.idpf.org/2007/opf'
DC = 'http://purl.org/dc/elements/1.1/'
ET.register_namespace('', XHTML)
ET.register_namespace('epub', EPUB)


def tag(namespace: str, name: str) -> str:
    return '{' + namespace + '}' + name


@dataclass
class Node:
    name: str
    attrs: dict[str, str] = field(default_factory=dict)
    children: list = field(default_factory=list)

    def text(self) -> str:
        return ''.join(child if isinstance(child, str) else child.text() for child in self.children)

    def has(self, class_name: str) -> bool:
        return class_name in self.attrs.get('class', '').split()

    def walk(self, name: str | None = None) -> Iterator[Node]:
        if name is None or self.name == name:
            yield self
        for child in self.children:
            if isinstance(child, Node):
                yield from child.walk(name)


class Reader(HTMLParser):
    VOID = {'img', 'meta', 'link', 'br', 'hr', 'input', 'source', 'wbr', 'area', 'base', 'embed', 'param', 'col', 'track'}

    def __init__(self, text: str):
        super().__init__(convert_charrefs=True)
        self.root = Node('document')
        self.stack = [self.root]
        self.feed(text)
        self.close()

    def handle_starttag(self, name, attrs):
        if len({k for k, _ in attrs}) != len(attrs):
            raise ValueError('Ambiguous duplicate HTML attributes')
        node = Node(name, {k: v or '' for k, v in attrs})
        self.stack[-1].children.append(node)
        if name not in self.VOID:
            self.stack.append(node)

    def handle_startendtag(self, name, attrs):
        self.handle_starttag(name, attrs)
        if name not in self.VOID:
            self.handle_endtag(name)

    def handle_endtag(self, name):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].name == name:
                self.stack = self.stack[:i]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


# These are export scaffolding, not book prose. Other bracketed notes survive.
CONTINUES = re.compile(r"\[continues\]", re.IGNORECASE)
EMPTY_CAPTURE_TEXT = {"NO TEXT", "NO_TEXT", "[No readable text on this page.]"}


def clean_continuations(text: str) -> str:
    """Remove the exact model marker without gluing adjacent words together."""
    text = text.replace('\r\n', '\n').replace('\r', '\n')
    pattern = re.compile(r"[ \t]*\[continues\][ \t]*", re.IGNORECASE)
    def replacement(match):
        left = text[match.start() - 1] if match.start() else ''
        right = text[match.end()] if match.end() < len(text) else ''
        # Existing line/paragraph boundaries remain intact. At an inline
        # marker, replace spacing only when the neighboring text needs it.
        if not left or not right or left.isspace() or right.isspace():
            return ''
        if left in '([{<“‘' or right in ',.;:!?)]}>”’':
            return ''
        return ' '
    return pattern.sub(replacement, text)


def prose_text(node: Node) -> str:
    """Recover explicit line breaks, including any already-authored <br>."""
    return ''.join(child if isinstance(child, str) else '\n' if child.name == 'br'
                   else prose_text(child) for child in node.children)


def prose_paragraphs(node: Node) -> list[list[str]]:
    text = clean_continuations(prose_text(node)).strip()
    if not text or text in EMPTY_CAPTURE_TEXT:
        return []
    return [[line.strip() for line in paragraph.strip().split('\n')]
            for paragraph in re.split(r'\n[ \t]*\n+', text) if paragraph.strip()]


def generated_heading(node: Node, parent: ET.Element) -> bool:
    if node.name != 'h2' or parent.tag != tag(XHTML, 'section'):
        return False
    if not re.fullmatch(r'screen-\d+', parent.get('id', '')):
        return False
    content = ''.join(child if isinstance(child, str) else '' if child.has('model-badge')
                      else child.text() for child in node.children).strip()
    return re.fullmatch(r'Screen\s+\d+', content) is not None


def css(value: str) -> dict[str, str]:
    return {k.strip(): v.strip() for part in value.split(';') if ':' in part for k, v in [part.split(':', 1)]}


def number(value: str, default=0.0) -> float:
    match = re.fullmatch(r'(-?(?:\d+(?:\.\d*)?|\.\d+))(?:%|cqw|px)?', value.strip())
    result = float(match.group(1)) if match else default
    if not math.isfinite(result):
        raise ValueError('Non-finite layout coordinate')
    return result


def geometry(style: dict, width: float, height: float) -> tuple[float, float, float, float]:
    return (number(style.get('left', '0')) * width / 100,
            number(style.get('top', '0')) * height / 100,
            number(style.get('width', '100')) * width / 100,
            number(style.get('height', '100')) * height / 100)


def font_for(size: float, family='Georgia,serif', weight='400', italic=False):
    serif = 'sans' not in family and 'system-ui' not in family
    bold = number(weight, 400) >= 600
    variant = (' Bold' if bold else '') + (' Italic' if italic else '')
    candidates = [
        Path('/System/Library/Fonts/Supplemental') / (('Georgia' if serif else 'Arial') + variant + '.ttf'),
        Path('/System/Library/Fonts/Supplemental') / (('Times New Roman' if serif else 'Arial') + variant + '.ttf'),
        Path('/usr/share/fonts/truetype/dejavu') / (('DejaVuSerif' if serif else 'DejaVuSans') + ('-Bold' if bold else '') + '.ttf'),
    ]
    for path in candidates:
        if path.is_file():
            return ImageFont.truetype(str(path), max(1, round(size)))
    return ImageFont.load_default(size=max(1, round(size)))


def wrap_text(text: str, font, maximum: float) -> list[str]:
    result = []
    for paragraph in text.split('\n'):
        if not paragraph.strip():
            result.append('')
            continue
        line = ''
        for word in paragraph.split():
            candidate = (line + ' ' + word).strip()
            if line and font.getlength(candidate) > maximum:
                result.append(line)
                line = word
            else:
                line = candidate
            # Keep every character even if an unbroken token is too wide.
            while font.getlength(line) > maximum and len(line) > 1:
                cut = len(line) - 1
                while cut > 1 and font.getlength(line[:cut]) > maximum:
                    cut -= 1
                result.append(line[:cut])
                line = line[cut:]
        result.append(line)
    return result


def text_plan(node: Node, width: float, height: float) -> dict:
    style = css(node.attrs.get('style', ''))
    x, y, w, h = geometry(style, width, height)
    if w <= 0 or h <= 0:
        raise ValueError('Translated text has an empty layout box')
    vertical = style.get('writing-mode', '').startswith('vertical')
    inner_w, inner_h = (h, w) if vertical else (w, h)
    padding = .0045 * width
    size = max(1, number(style.get('font-size', '2cqw')) * width / 100)
    line_height = number(style.get('line-height', '1.3'), 1.3)
    family = style.get('font-family', 'Georgia,serif')
    weight = style.get('font-weight', '400')
    italic = node.has('quote')
    # Every composed page uses the original geometry and measured text wrapping.
    for _ in range(80):
        font = font_for(size, family, weight, italic)
        lines = wrap_text(clean_continuations(node.text()).strip(), font, max(1, inner_w - 2 * padding))
        if len(lines) * size * line_height <= inner_h - 2 * padding or size <= 1.5:
            break
        size *= .96
    advance = size * line_height
    align = style.get('text-align', 'left')
    start_y = padding if node.has('profile') else max(padding, (inner_h - len(lines) * advance) / 2)
    # Baseline uses the original font ascender and descender metrics.
    ascent, descent = font.getmetrics()
    baseline = start_y + (advance - ascent - descent) / 2 + ascent
    return dict(x=x, y=y, w=w, h=h, iw=inner_w, ih=inner_h, vertical=vertical,
                padding=padding, size=size, advance=advance, baseline=baseline,
                lines=lines, family=family, weight=weight, italic=italic,
                align=align, color=style.get('color', '#211c25'),
                background=style.get('background', 'transparent'))


def xml_bytes(root: ET.Element) -> bytes:
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)


def xhtml_document(title: str) -> tuple[ET.Element, ET.Element, ET.Element]:
    root = ET.Element(tag(XHTML, 'html'), {'lang': 'en', '{http://www.w3.org/XML/1998/namespace}lang': 'en'})
    head = ET.SubElement(root, tag(XHTML, 'head'))
    ET.SubElement(head, tag(XHTML, 'title')).text = title
    ET.SubElement(head, tag(XHTML, 'meta'), {'charset': 'utf-8'})
    ET.SubElement(head, tag(XHTML, 'link'), {'rel': 'stylesheet', 'type': 'text/css', 'href': '../styles/book.css'})
    body = ET.SubElement(root, tag(XHTML, 'body'))
    return root, head, body


CSS = '''html{color-scheme:light dark}body{font-family:Georgia,serif;line-height:1.55;margin:5%;overflow-wrap:break-word}h1,h2,h3,figcaption{font-family:sans-serif}h1{font-size:1.3em}h2{font-size:1em;margin:1em 0}section{margin:0;padding:0;border:0;break-before:auto;break-after:auto;break-inside:auto}p{margin:.75em 0;orphans:2;widows:2}.prose{white-space:normal;overflow-wrap:break-word}.prose p:first-child{margin-top:.75em}.screen-anchor{margin:0;padding:0;font-size:0;line-height:0;height:0}figure{margin:.5em 0;break-inside:auto;page-break-inside:auto}figure img{display:block;width:auto;height:auto;max-width:100%;max-height:85vh;object-fit:contain;margin:0 auto}figcaption{font-size:.7em;text-align:center;margin:.3em 0}.transcript{margin:1em 0}.transcript h3{font-size:.8em;font-weight:normal;color:#666}nav ol{padding-left:1.5em}a{color:inherit}'''


class Exporter:
    def __init__(self, html_path: Path, title: str | None = None):
        self.html_path = html_path.expanduser().resolve()
        self.folder = self.html_path.parent
        self.source = self.html_path.read_bytes()
        self.root = Reader(self.source.decode('utf-8')).root
        self.sections = [n for n in self.root.walk('section') if re.fullmatch(r'screen-\d+', n.attrs.get('id', ''))]
        if not self.sections:
            raise ValueError('No saved screen sections found in translation HTML')
        ids = [s.attrs['id'] for s in self.sections]
        if len(set(ids)) != len(ids):
            raise ValueError('Duplicate screen IDs in translation HTML')
        self.metadata = {}
        checkpoint = self.folder / 'checkpoint.json'
        if checkpoint.is_file():
            try:
                self.metadata = json.loads(checkpoint.read_text(encoding='utf-8'))
            except (OSError, ValueError):
                pass
        self.title = title or self.metadata.get('bookTitle') or self.infer_title()
        self.inferred_cover = self.infer_cover()
        self.resources: dict[str, bytes] = {}
        self.assets: dict[str, tuple[str, bytes]] = {}
        self.cover: str | None = None
        self.image_count = 0
        self.layout_count = 0
        self.used_images = set()
        self.chapter_models = []
        self.removed_markers = sum(len(CONTINUES.findall(n.text())) for n in self.root.walk() if n.has('prose') or n.has('translated-block'))

    def infer_cover(self) -> Node | None:
        """Recognize plain front-cover captures without choosing interior art.

        Reviewed cover layouts take precedence. An unreviewed capture must be
        the first screen, have a short title-page transcript matching this
        book, and contain exactly one illustration. Do not simply pick the
        first image of a job that may have started midway through the book.
        """
        if any(n.has('cover') for section in self.sections for n in section.walk('figure')):
            return None
        first = self.sections[0]
        if first.attrs['id'] != 'screen-1':
            return None
        prose = [n for n in first.walk() if n.has('prose')]
        figures = list(first.walk('figure'))
        if len(prose) != 1 or len(figures) != 1 or len(list(first.walk('img'))) != 1:
            return None
        transcript = clean_continuations(prose_text(prose[0])).strip()
        if not transcript or len(transcript) > 1500:
            return None
        normalize = lambda value: ''.join(c for c in value.casefold() if c.isalnum())
        title = self.title.strip()
        volume = re.fullmatch(r'(.*?)\s*[-–—:]?\s*\b(?:vol\.?|volume)\s*(\d+)\s*', title, re.IGNORECASE)
        base = normalize(volume.group(1) if volume else title)
        if len(base) < 3 or base in {'booktranslation', 'translation', 'untitled'}:
            return None
        if volume:
            for line in transcript.splitlines():
                separate_volume = re.fullmatch(r'\s*(?:(?:vol\.?|volume)\s*)?(\d{1,3})\s*', line, re.IGNORECASE)
                if separate_volume and int(separate_volume.group(1)) != int(volume.group(2)):
                    return None
        for line in transcript.splitlines():
            candidate = normalize(line)
            if candidate == base:
                return figures[0]
            if volume and candidate.startswith(base):
                suffix = re.fullmatch(r'(?:vol|volume)?(\d+)', candidate[len(base):])
                if suffix and int(suffix.group(1)) == int(volume.group(2)):
                    return figures[0]
        return None

    def infer_title(self) -> str:
        if self.folder.name.startswith('Book-'):
            return self.folder.name[5:]
        titles = [n.text().replace('\n', ' ').strip() for n in self.sections[0].walk() if n.has('translated-block') and n.has('title')]
        if titles:
            title = titles[0]
            prose = next((n.text() for n in self.sections[0].walk() if n.has('prose')), '')
            volume = re.search(r'(?m)^\s*(\d{1,3})\s*$', prose)
            if volume:
                title += ' — Vol. ' + volume.group(1).zfill(2)
            return title
        heading = next((n.text().strip() for n in self.root.walk('h1')), '')
        if heading and heading != 'Book translation':
            return heading
        return 'Book translation'

    def resolve_image(self, src: str) -> tuple[str, bytes]:
        if src in self.assets:
            return self.assets[src]
        if src.startswith(('data:image/jpeg;base64,', 'data:image/png;base64,')):
            if len(src) > 120_000_000:
                raise ValueError('Embedded illustration is unexpectedly large')
            try:
                data = base64.b64decode(src.split(',', 1)[1], validate=True)
            except ValueError:
                raise ValueError('Invalid embedded illustration') from None
            with Image.open(io.BytesIO(data)) as im:
                if im.format not in {'PNG', 'JPEG'}:
                    raise ValueError('Embedded illustration must be PNG/JPEG')
                im = ImageOps.exif_transpose(im).convert('RGBA')
                bg = Image.new('RGBA', im.size, 'white'); bg.alpha_composite(im)
                im = bg.convert('RGB'); im.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
                out = io.BytesIO(); im.save(out, format='JPEG', quality=JPEG_QUALITY, subsampling=0, optimize=True)
                data = out.getvalue()
        else:
            parsed = urlsplit(src)
            if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
                raise ValueError('Only confined local illustrations may be exported')
            src = unquote(src)
            if re.fullmatch(r'illustrations/portable/[^/]+\.ipad-v1\.jpg', src):
                # Resolve back to the original and verify/regenerate its cache.
                original = 'illustrations/' + PurePosixPath(src).name[:-len('.ipad-v1.jpg')]
                jpeg, *_ = asset(self.folder, original)
            else:
                jpeg, *_ = asset(self.folder, src)
            data = jpeg.read_bytes()
        name = 'images/' + hashlib.sha256(data).hexdigest()[:24] + '.jpg'
        self.resources[name] = data
        self.assets[src] = name, data
        return name, data

    def layout(self, original: Node) -> bytes:
        style = css(original.attrs.get('style', ''))
        ratio = style.get('aspect-ratio', '1/1').split('/')
        aspect = number(ratio[0], 1) / (number(ratio[1], 1) if len(ratio) > 1 else 1)
        if aspect <= .05 or aspect >= 20:
            raise ValueError('Unsupported illustrated page aspect ratio')
        width, height = 1000.0, 1000.0 / aspect
        scale = MAX_EDGE / max(width, height)
        canvas = Image.new('RGB', (round(width * scale), round(height * scale)), 'white')
        draw = ImageDraw.Draw(canvas)
        for node in original.children:
            if not isinstance(node, Node):
                continue
            ns = css(node.attrs.get('style', ''))
            x, y, w, h = geometry(ns, width, height)
            if node.name == 'img':
                resource, data = self.resolve_image(node.attrs.get('src', ''))
                with Image.open(io.BytesIO(data)) as pic:
                    pic = pic.convert('RGB').resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.Resampling.LANCZOS)
                    canvas.paste(pic, (round(x * scale), round(y * scale)))
            elif node.has('text-mask'):
                color = ns.get('background', 'white')
                draw.rectangle((x * scale, y * scale, (x + w) * scale, (y + h) * scale), fill=color)
            elif node.has('translated-block'):
                plan = text_plan(node, width, height)
                self.draw_text(canvas, plan, scale)
        out = io.BytesIO(); canvas.save(out, format='JPEG', quality=JPEG_QUALITY, subsampling=0, optimize=True)
        return out.getvalue()

    @staticmethod
    def draw_text(canvas, p, scale):
        x, y, w, h = p['x'], p['y'], p['w'], p['h']
        background = p['background']
        if background != 'transparent':
            ImageDraw.Draw(canvas).rectangle((x * scale, y * scale, (x + w) * scale, (y + h) * scale), fill=background)
        anchor = {'center': 'middle', 'right': 'end'}.get(p['align'], 'start')
        line_x = p['iw'] / 2 if anchor == 'middle' else p['iw'] - p['padding'] if anchor == 'end' else p['padding']
        layer = Image.new('RGBA', (max(1, round(p['iw'] * scale)), max(1, round(p['ih'] * scale))), (0, 0, 0, 0))
        layer_draw = ImageDraw.Draw(layer)
        font = font_for(p['size'] * scale, p['family'], p['weight'], p['italic'])
        pil_anchor = {'middle': 'ms', 'end': 'rs', 'start': 'ls'}[anchor]
        for i, line in enumerate(p['lines']):
            baseline = p['baseline'] + i * p['advance']
            layer_draw.text((line_x * scale, baseline * scale), line, font=font, fill=p['color'], anchor=pil_anchor)
        if p['vertical']:
            layer = layer.transpose(Image.Transpose.ROTATE_270)
        canvas.paste(layer, (round(x * scale), round(y * scale)), layer)

    def render_node(self, node: Node, parent: ET.Element) -> None:
        if node.name in {'script', 'style', 'select', 'button', 'input', 'label'}:
            return
        if node.has('model-badge') or generated_heading(node, parent):
            return
        if node.name == 'figcaption' and re.fullmatch(r'Screen\s+\d+\s*·\s*Illustration\s+\d+', node.text().strip()):
            return
        if node.has('prose'):
            paragraphs = prose_paragraphs(node)
            if not paragraphs:
                return
            element = ET.SubElement(parent, tag(XHTML, 'div'), {'class': 'prose'})
            for lines in paragraphs:
                paragraph = ET.SubElement(element, tag(XHTML, 'p'))
                paragraph.text = lines[0]
                for line in lines[1:]:
                    ET.SubElement(paragraph, tag(XHTML, 'br')).tail = line
            return
        if node.has('transcript') and not any(prose_paragraphs(n) for n in node.walk() if n.has('prose')) and not any(node.walk('img')):
            return
        if node.has('original-page'):
            data = self.layout(node)
            resource = 'images/composed-' + hashlib.sha256(data).hexdigest()[:24] + '.jpg'
            self.resources[resource] = data
            self.used_images.add(resource)
            ET.SubElement(parent, tag(XHTML, 'img'), {'src': '../' + resource, 'alt': 'Illustrated page with translated English text; full transcript follows'})
            self.layout_count += 1
            self.image_count += 1
            if self.cover is None and self._in_cover:
                self.cover = resource
            return
        if node.name == 'img':
            if 'srcset' in node.attrs:
                raise ValueError('Ambiguous image srcset is unsupported')
            resource, data = self.resolve_image(node.attrs.get('src', ''))
            self.used_images.add(resource)
            ET.SubElement(parent, tag(XHTML, 'img'), {'src': '../' + resource, 'alt': node.attrs.get('alt', 'Book illustration')})
            self.image_count += 1
            if self.cover is None and self._in_cover:
                self.cover = resource
            return
        allowed = {'section', 'div', 'h1', 'h2', 'h3', 'p', 'span', 'figure', 'figcaption', 'details', 'summary', 'br', 'em', 'strong', 'i', 'b', 'small', 'blockquote', 'ul', 'ol', 'li', 'a'}
        if node.name not in allowed:
            raise ValueError('Unsupported content element in saved translation: ' + node.name)
        name = {'details': 'div', 'summary': 'h3'}.get(node.name, node.name)
        attrs = {key: value for key, value in node.attrs.items() if key in {'id', 'class', 'lang', 'data-model', 'data-models'}}
        element = ET.SubElement(parent, tag(XHTML, name), attrs)
        was_cover = self._in_cover
        self._in_cover = self._in_cover or (node.name == 'figure' and (node.has('cover') or node is self.inferred_cover))
        for child in node.children:
            if isinstance(child, str):
                if len(element):
                    element[-1].tail = (element[-1].tail or '') + child
                else:
                    element.text = (element.text or '') + child
            else:
                self.render_node(child, element)
        self._in_cover = was_cover
        if node.name == 'section' and not ''.join(element.itertext()).strip() and next(element.iter(tag(XHTML, 'img')), None) is None:
            # A saved blank capture remains a TOC/model anchor with no box.
            element.clear()
            element.attrib.update(attrs)
            element.set('class', (element.get('class', '') + ' screen-anchor').strip())

    def build(self) -> dict[str, bytes]:
        self.resources['styles/book.css'] = CSS.encode('utf-8')
        chapters = []
        reading, head, reading_body = xhtml_document(self.title)
        reading_path = 'text/reading.xhtml'
        for section in self.sections:
            number_id = int(section.attrs['id'].split('-')[1])
            title = f'Screen {number_id:04d}'
            model = section.attrs.get('data-model', '')
            models = section.attrs.get('data-models', model)
            self.chapter_models.append({'screen': number_id, 'model': model, 'models': models})
            self._in_cover = False
            self.render_node(section, reading_body)
            reading_body[-1].tail = '\n'
            chapters.append((f'screen{number_id}', reading_path + '#' + section.attrs['id'], title))
        self.resources[reading_path] = xml_bytes(reading)
        # Cover metadata reuses the existing reading image; no extra cover
        # document or forced page break is added to the continuous spine.
        nav, head, body = xhtml_document(self.title)
        nav.find(tag(XHTML, 'head')).find(tag(XHTML, 'link')).set('href', 'styles/book.css')
        ET.SubElement(body, tag(XHTML, 'h1')).text = self.title
        toc = ET.SubElement(body, tag(XHTML, 'nav'), {tag(EPUB, 'type'): 'toc', 'id': 'toc'})
        ET.SubElement(toc, tag(XHTML, 'h2')).text = 'Contents'
        ol = ET.SubElement(toc, tag(XHTML, 'ol'))
        for _, path, title in chapters:
            ET.SubElement(ET.SubElement(ol, tag(XHTML, 'li')), tag(XHTML, 'a'), {'href': path}).text = title
        landmarks = ET.SubElement(body, tag(XHTML, 'nav'), {tag(EPUB, 'type'): 'landmarks', 'hidden': 'hidden'})
        links = ET.SubElement(landmarks, tag(XHTML, 'ol'))
        ET.SubElement(ET.SubElement(links, tag(XHTML, 'li')), tag(XHTML, 'a'), {tag(EPUB, 'type'): 'bodymatter', 'href': chapters[0][1]}).text = 'Start reading'
        self.resources['nav.xhtml'] = xml_bytes(nav)
        opf = ET.Element(tag(OPF, 'package'), {'version': '3.0', 'unique-identifier': 'book-id', 'prefix': 'rendition: http://www.idpf.org/vocab/rendition/#'})
        metadata = ET.SubElement(opf, tag(OPF, 'metadata'))
        identity = self.metadata.get('tag') or self.metadata.get('jobTag') or self.title
        ET.SubElement(metadata, tag(DC, 'identifier'), {'id': 'book-id'}).text = 'urn:uuid:' + str(uuid.uuid5(uuid.NAMESPACE_URL, 'bt-epub:' + str(identity)))
        ET.SubElement(metadata, tag(DC, 'title')).text = self.title
        ET.SubElement(metadata, tag(DC, 'language')).text = 'en'
        ET.SubElement(metadata, tag(DC, 'description')).text = f'English reading copy exported from {len(self.sections)} saved BT screens. Translation model metadata is retained for each captured screen.'
        # Only explicit author metadata is used; do not infer creator from prose.
        author = self.metadata.get('author') or self.metadata.get('bookAuthor')
        if isinstance(author, str) and author.strip():
            ET.SubElement(metadata, tag(DC, 'creator')).text = author.strip()
        ET.SubElement(metadata, tag(OPF, 'meta'), {'property': 'dcterms:modified'}).text = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        ET.SubElement(metadata, tag(OPF, 'meta'), {'property': 'rendition:layout'}).text = 'reflowable'
        if self.cover:
            ET.SubElement(metadata, tag(OPF, 'meta'), {'name': 'cover', 'content': 'cover-image'})
        manifest = ET.SubElement(opf, tag(OPF, 'manifest'))
        ET.SubElement(manifest, tag(OPF, 'item'), {'id': 'reading', 'href': reading_path, 'media-type': 'application/xhtml+xml'})
        ET.SubElement(manifest, tag(OPF, 'item'), {'id': 'nav', 'href': 'nav.xhtml', 'media-type': 'application/xhtml+xml', 'properties': 'nav'})
        ET.SubElement(manifest, tag(OPF, 'item'), {'id': 'style', 'href': 'styles/book.css', 'media-type': 'text/css'})
        self.resources = {name: data for name, data in self.resources.items() if not name.startswith('images/') or name in self.used_images}
        for i, path in enumerate(sorted(self.used_images), 1):
            attrs = {'id': 'cover-image' if path == self.cover else f'image{i}', 'href': path, 'media-type': 'image/jpeg'}
            if path == self.cover:
                attrs['properties'] = 'cover-image'
            ET.SubElement(manifest, tag(OPF, 'item'), attrs)
        spine = ET.SubElement(opf, tag(OPF, 'spine'), {'page-progression-direction': 'ltr'})
        ET.SubElement(spine, tag(OPF, 'itemref'), {'idref': 'reading'})
        self.resources['package.opf'] = xml_bytes(opf)
        container = b'''<?xml version="1.0" encoding="UTF-8"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'''
        files = {'META-INF/container.xml': container}
        files.update({'EPUB/' + name: data for name, data in self.resources.items()})
        files['META-INF/bt-export.json'] = (json.dumps({'format': 1, 'exportRevision': 'continuous-v1', 'readingLayout': 'continuous', 'coverImage': self.cover, 'coverSelection': ('title-matched-frontmatter' if self.inferred_cover else 'explicit') if self.cover else None, 'continuationMarkersRemoved': self.removed_markers, 'title': self.title, 'sourceSHA256': hashlib.sha256(self.source).hexdigest(), 'screens': self.chapter_models}, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
        return files


def export(html_path: Path, output: Path | None = None, title: str | None = None) -> dict:
    exporter = Exporter(html_path, title)
    output = output.expanduser().absolute() if output else exporter.html_path.with_suffix('.epub')
    if output.resolve() == exporter.html_path:
        raise ValueError('EPUB output must not overwrite source HTML')
    if output.suffix.lower() != '.epub':
        raise ValueError('EPUB output filename must end in .epub')
    files = exporter.build()
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.' + output.name + '.', suffix='.tmp', dir=output.parent)
    try:
        with os.fdopen(fd, 'w+b') as stream:
            with zipfile.ZipFile(stream, 'w') as archive:
                mime = zipfile.ZipInfo('mimetype')
                mime.compress_type = zipfile.ZIP_STORED
                archive.writestr(mime, b'application/epub+zip')
                for path, data in files.items():
                    archive.writestr(path, data, compress_type=zipfile.ZIP_DEFLATED)
            stream.flush(); os.fsync(stream.fileno())
        # The published file is always a complete ZIP; interrupted exports keep
        # the prior successful reading copy intact.
        os.replace(temporary, output)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    return {'ok': True, 'output': str(output), 'title': exporter.title,
            'screens': len(exporter.sections), 'images': exporter.image_count,
            'illustratedLayouts': exporter.layout_count, 'continuationMarkersRemoved': exporter.removed_markers, 'bytes': output.stat().st_size}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--html', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--title')
    args = parser.parse_args()
    try:
        print(json.dumps(export(args.html, args.output, args.title), ensure_ascii=False))
        return 0
    except (OSError, ValueError, TypeError, KeyError, ZeroDivisionError) as exc:
        print(json.dumps({'ok': False, 'error': str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
