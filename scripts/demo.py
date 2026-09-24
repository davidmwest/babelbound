#!/usr/bin/env python3
"""Create an offline, synthetic HTML and EPUB preview of BT's export pipeline.

No browser, account, Hammerspoon installation, or model request is used. The
English text is invented for this example; Pillow draws a geometric fixture.
An existing output path is always refused, even if it is an empty directory.
"""
from __future__ import annotations

import argparse
from html import escape
from pathlib import Path
import sys
import tempfile

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hammerspoon"))
from gemini_book_epub import export

TITLE = "The Lantern Harbor — Synthetic Preview"
NOTICE = ("Synthetic preview: the English text was invented for this demo. "
          "No model translation or browser automation was used.")
ARTWORK = "illustrations/harbor.png"


def illustration(path: Path) -> None:
    """Draw a small geometric test fixture, with no downloaded image assets."""
    image = Image.new("RGB", (900, 1200), "#e9edf2")
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 650, 900, 1200), fill="#7b9daa")
    draw.ellipse((535, 130, 715, 310), fill="#efc976")
    draw.polygon([(90, 650), (260, 430), (410, 650)], fill="#516877")
    draw.polygon([(370, 650), (600, 480), (820, 650)], fill="#8ca2a6")
    draw.rectangle((385, 365, 480, 865), fill="#f7f1de")
    draw.rectangle((362, 342, 503, 382), fill="#445564")
    draw.polygon([(360, 342), (432, 282), (505, 342)], fill="#445564")
    draw.rectangle((407, 390, 460, 450), fill="#efc976")
    draw.rectangle((428, 495, 437, 820), fill="#b4bab8")
    for y, width in ((920, 235), (978, 150), (1036, 75)):
        draw.rectangle((432 - width, y, 432 + width, y + 8), fill="#cbdcdb")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG")


def reading_html() -> str:
    title, notice = escape(TITLE), escape(NOTICE)
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
body{{max-width:42rem;margin:2rem auto;padding:0 1.2rem;color:#23313d;background:#faf9f5;font:1.1rem/1.65 Georgia,serif}}
h1,h2,header,figcaption{{font-family:system-ui,sans-serif}}h1{{line-height:1.2}}
header{{padding-bottom:1rem;border-bottom:1px solid #c6cdd2}}
section{{margin:2rem 0}}h2{{font-size:.8rem;color:#64717c}}
.prose{{white-space:pre-wrap}}figure{{margin:1.5rem 0}}img{{display:block;max-width:100%;max-height:70vh;width:auto;height:auto;margin:auto}}
figcaption{{font-size:.8rem;text-align:center;color:#64717c}}
</style></head><body>
<header><h1>{title}</h1><p>{notice}</p>
<p>This HTML keeps capture boundaries and continuation markers visible. The EPUB packages the artwork and cleans those reading interruptions.</p></header>
<section id="screen-1" data-model="synthetic-demo" data-models="synthetic-demo">
<h2>Screen 0001<span class="model-badge"> · Synthetic example</span></h2>
<div class="prose">{title}

{notice}</div>
<figure class="book-figure cover" id="screen-1-illustration-1">
<img src="{ARTWORK}" alt="Geometric fixture of a lighthouse, water, and a golden sun">
<figcaption>Original geometric fixture, generated locally for this example.</figcaption></figure>
</section>
<section id="screen-2" data-model="synthetic-demo" data-models="synthetic-demo">
<h2>Screen 0002<span class="model-badge"> · Synthetic example</span></h2>
<div class="prose">At dusk, Mira carried a small lantern down to the harbor. The boats had returned, but one window in the lighthouse remained dark.

She set her lantern on the stone wall and waited. Across the water, a bell sounded once. Then a second light appeared [continues]</div>
</section>
<section id="screen-3" data-model="synthetic-demo" data-models="synthetic-demo">
<h2>Screen 0003<span class="model-badge"> · Synthetic example</span></h2>
<div class="prose">[continues]beside the lighthouse door. Its keeper waved, holding the lamp he had been repairing all afternoon.

Mira waved back. The harbor needed no grand announcement: two steady lights were enough to show everyone the way home.

End of synthetic preview.</div>
</section>
</body></html>
'''


def create_demo(output: Path) -> dict:
    output = Path(output).expanduser().absolute()
    if output.exists() or output.is_symlink():
        raise FileExistsError(f"Output already exists: {output}. Choose a new --output directory.")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Finish the exporter before making the requested output visible. A failed
    # export cannot leave an apparently successful reading copy in that folder.
    with tempfile.TemporaryDirectory(prefix=".bt-demo-", dir=output.parent) as temporary:
        staging = Path(temporary)
        illustration(staging / ARTWORK)
        (staging / "translation.html").write_text(reading_html(), encoding="utf-8")
        export(staging / "translation.html", title=TITLE)
        # mkdir is an exclusive reservation: a path created meanwhile is also
        # refused. Exclusive file creation never replaces an existing file.
        output.mkdir()
        for relative in (ARTWORK, "translation.html", "translation.epub"):
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as stream:
                stream.write((staging / relative).read_bytes())
    return {"html": output / "translation.html", "epub": output / "translation.epub",
            "illustration": output / ARTWORK}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("demo-output"),
                        help="new output directory (default: demo-output)")
    args = parser.parse_args(argv)
    try:
        result = create_demo(args.output)
    except (OSError, ValueError) as error:
        print(f"Demo stopped: {error}", file=sys.stderr)
        return 1
    print(NOTICE)
    print(f"HTML preview: {result['html']}")
    print(f"EPUB for Books or another ebook reader: {result['epub']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
