#!/usr/bin/env python3
"""Extract artwork from committed, visible Gemini Book Translator captures.

Needs Python 3.9+ and Pillow. No network, model, OCR, or reader access is used.
The checkpoint is the source of truth: uncommitted screenshots are never read.

Usage: gemini_book_illustrations.py --job /path/to/Book-job
Outputs illustrations/manifest.json plus lossless PNG crops. The manifest is
published atomically only after every committed source has been processed.
Existing crops are content addressed; interrupted scans cannot corrupt a
previous manifest. Repeated runs reuse unchanged sources and render assets.

Reviewed optional JOB/illustration-overrides.json format:
  {"version":1,"screens":{"3":{"sourceSHA256":"...","boxes":[[l,t,r,b]]}}}
An empty boxes array explicitly excludes a page. All boxes are source pixels,
right/bottom exclusive, ordered right-to-left by the detector. Overrides keep
the reviewer's order. Reviewed JOB/illustration-layouts.json has the same
screens map; each entry contains sourceSHA256, pageBox, kind, and blocks.
Layout metadata is passed to the HTML renderer after checksum verification.
This supports precise translated typography without modifying original art.

Detection is conservative: continuous-tone connected regions seed extraction,
then nearby dark/line pixels complete their contours. Text columns and uniform
decorative black panels do not qualify as art. Exceptional line-only artwork
may need a reviewed override; this is not a semantic image recognition model.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import signal
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageFilter, ImageOps
except ImportError:
    sys.stderr.write("Illustration extraction needs Pillow in the configured Python interpreter.\n")
    raise SystemExit(2)

GENERATOR_VERSION = "1.0.0"
MANIFEST_VERSION = 1


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encoded(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def atomic_write(path: Path, data: bytes) -> None:
    """Replace a file only after the complete new contents reach disk."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data)
            out.flush()
            os.fsync(out.fileno())
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def image_write(path: Path, image: Image.Image) -> None:
    if path.is_file():
        return
    out = io.BytesIO()
    image.save(out, format="PNG")
    atomic_write(path, out.getvalue())


def components(mask: Image.Image):
    """Eight-connected components on a small binary image, dependency-free."""
    width, height = mask.size
    pixels = bytearray(mask.tobytes())
    for y in range(height):
        for x in range(width):
            offset = y * width + x
            if not pixels[offset]:
                continue
            pixels[offset] = 0
            pending = [(x, y)]
            points = []
            left = right = x
            top = bottom = y
            while pending:
                px, py = pending.pop()
                points.append((px, py))
                left, right = min(left, px), max(right, px)
                top, bottom = min(top, py), max(bottom, py)
                for yy in range(max(0, py - 1), min(height, py + 2)):
                    for xx in range(max(0, px - 1), min(width, px + 2)):
                        neighbor = yy * width + xx
                        if pixels[neighbor]:
                            pixels[neighbor] = 0
                            pending.append((xx, yy))
            yield points, (left, top, right + 1, bottom + 1)


def order_boxes(boxes: list[list[int]], direction: str) -> list[list[int]]:
    # Columns read right-to-left in a Japanese spread; within one column,
    # upper illustrations precede lower ones. Connected collages stay intact.
    if direction == "rtl":
        return sorted(boxes, key=lambda box: (-(box[0] + box[2]) / 2, box[1]))
    return sorted(boxes, key=lambda box: ((box[0] + box[2]) / 2, box[1]))


def detect_artwork(image: Image.Image, direction: str = "rtl"):
    gray = ImageOps.grayscale(image)
    # Use native-pixel midtone density. Downsampling first would turn small
    # black text into gray and cause text-only pages to masquerade as art.
    width = max(64, min(160, round(image.width / 32)))
    height = max(48, round(width * image.height / image.width))
    density = gray.point(lambda value: 255 if 40 < value < 228 else 0)
    density = density.resize((width, height), Image.Resampling.BOX)
    seeds = []
    for points, box in components(density.point(lambda value: 255 if value > 56 else 0)):
        if (len(points) >= width * height * 0.012
                and box[2] - box[0] >= width * 0.05
                and box[3] - box[1] >= height * 0.10):
            seeds.append(box)
    if not seeds:
        return [], False

    # Refine on a non-white mask so black clothing and fine contours stay
    # attached. Small isolated letters are not selected without an art seed.
    fine_width = max(128, min(768, round(image.width / 8)))
    fine_height = max(96, round(fine_width * image.height / image.width))
    mask = gray.point(lambda value: 255 if value < 245 else 0)
    mask = mask.resize((fine_width, fine_height), Image.Resampling.BOX)
    mask = mask.point(lambda value: 255 if value > 40 else 0).filter(ImageFilter.MaxFilter(3))
    seeds = [(l * fine_width / width, t * fine_height / height,
              r * fine_width / width, b * fine_height / height) for l, t, r, b in seeds]
    boxes = []
    padding = max(4, round(image.width * 0.004))
    for points, box in components(mask):
        if len(points) < fine_width * fine_height * 0.006:
            continue
        left, top, right, bottom = box
        matches = False
        for sl, st, sr, sb in seeds:
            if min(right, sr) <= max(left, sl) or min(bottom, sb) <= max(top, st):
                continue
            hits = sum(sl <= x <= sr and st <= y <= sb for x, y in points)
            if hits > (sr - sl) * (sb - st) * 0.05:
                matches = True
                break
        if matches:
            boxes.append([
                max(0, round(left * image.width / fine_width) - padding),
                max(0, round(top * image.height / fine_height) - padding),
                min(image.width, round(right * image.width / fine_width) + padding),
                min(image.height, round(bottom * image.height / fine_height) + padding),
            ])
    # An uncertain page is explicitly reported instead of represented by a
    # full text screenshot. A reviewed box can resolve such a page later.
    return order_boxes(boxes, direction), not bool(boxes)


def checked_box(value, size, context: str) -> list[int]:
    if not isinstance(value, list) or len(value) != 4:
        raise ValueError(f"{context}: expected [left, top, right, bottom]")
    if not all(isinstance(number, (int, float)) and math.isfinite(number) for number in value):
        raise ValueError(f"{context}: coordinates must be finite numbers")
    box = [round(number) for number in value]
    if not (0 <= box[0] < box[2] <= size[0] and 0 <= box[1] < box[3] <= size[1]):
        raise ValueError(f"{context}: box lies outside source image")
    return box


def load_optional(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("version") != 1 or not isinstance(data.get("screens"), dict):
        raise ValueError(f"{path.name}: expected version 1 and a screens object")
    return data["screens"]


def verify_review(review, source_sha: str, context: str):
    if review is None:
        return None
    if not isinstance(review, dict) or review.get("sourceSHA256") != source_sha:
        raise ValueError(f"{context}: reviewed sourceSHA256 does not match the saved PNG")
    return review


def asset_exists(output: Path, entry: dict) -> bool:
    assets = [art["src"] for art in entry.get("illustrations", [])]
    if entry.get("sourceSrc"):
        assets.append(entry["sourceSrc"])
    return all((output / Path(src).name).is_file() for src in assets)


def run(args) -> dict:
    job = args.job.expanduser().resolve()
    output = args.output_dir.expanduser().resolve() if args.output_dir else job / "illustrations"
    checkpoint = json.loads((job / "checkpoint.json").read_text(encoding="utf-8"))
    committed = checkpoint.get("records")
    if not isinstance(committed, list):
        raise ValueError("checkpoint.json has no committed records list")
    indices = [record.get("index") for record in committed]
    if any(type(index) is not int or index < 1 for index in indices) or len(indices) != len(set(indices)):
        raise ValueError("checkpoint.json has invalid or duplicate screen indices")
    overrides = load_optional(args.overrides or job / "illustration-overrides.json")
    layouts = load_optional(args.layouts or job / "illustration-layouts.json")
    old = {}
    manifest_path = output / "manifest.json"
    if manifest_path.exists():
        try:
            previous = json.loads(manifest_path.read_text(encoding="utf-8"))
            if previous.get("generatorVersion") == GENERATOR_VERSION:
                old = {entry["screenIndex"]: entry for entry in previous["records"]}
        except (ValueError, KeyError, TypeError):
            old = {}
    output.mkdir(parents=True, exist_ok=True)
    entries = []
    reused = 0
    for record in sorted(committed, key=lambda item: item["index"]):
        index = record["index"]
        source = job / "sources" / f"{index:05d}.png"
        if not source.is_file():
            raise ValueError(f"Screen {index}: committed source PNG is missing")
        source_bytes = source.read_bytes()
        sha = digest(source_bytes)
        review = verify_review(overrides.get(str(index)), sha, f"Screen {index} artwork override")
        layout = verify_review(layouts.get(str(index)), sha, f"Screen {index} layout")
        signature = digest(encoded({"sourceSHA256": sha, "sourceHash": record.get("sourceHash"),
                                    "override": review, "layout": layout, "direction": args.direction,
                                    "assetPrefix": args.asset_prefix, "generatorVersion": GENERATOR_VERSION}))
        cached = old.get(index)
        if (not args.force and cached and cached.get("signature") == signature
                and asset_exists(output, cached)):
            entries.append(cached)
            reused += 1
            continue
        with Image.open(io.BytesIO(source_bytes)) as native:
            native.load()
            image = native.convert("RGB")
            entry = {"screenIndex": index, "sourceHash": record.get("sourceHash"),
                     "sourceSHA256": sha, "sourceFile": f"sources/{index:05d}.png",
                     "sourceWidth": image.width, "sourceHeight": image.height,
                     "signature": signature, "illustrations": []}
            if review is not None:
                if not isinstance(review.get("boxes"), list):
                    raise ValueError(f"Screen {index}: artwork override needs a boxes list")
                boxes = [checked_box(box, image.size, f"Screen {index} artwork") for box in review["boxes"]]
                uncertain = False
                entry["detection"] = "reviewed"
            else:
                boxes, uncertain = detect_artwork(image, args.direction)
                entry["detection"] = "automatic"
            if layout is not None:
                layout = dict(layout)
                layout["pageBox"] = checked_box(layout.get("pageBox"), image.size, f"Screen {index} layout")
                if not isinstance(layout.get("blocks"), list):
                    raise ValueError(f"Screen {index}: layout needs a blocks list")
                entry["layout"] = layout
                # A reviewed page design (e.g. cover or title page) is also
                # meaningful when it does not satisfy photographic heuristics.
                if not boxes:
                    boxes = [layout["pageBox"]]
                    uncertain = False
            for art_index, box in enumerate(boxes, 1):
                box_sha = digest(encoded(box))[:8]
                name = f"{index:05d}-{art_index:02d}-{sha[:12]}-{box_sha}.png"
                crop = native.crop(tuple(box))
                image_write(output / name, crop)
                entry["illustrations"].append({"index": art_index,
                                              "src": f"{args.asset_prefix}/{name}",
                                              "width": crop.width, "height": crop.height,
                                              "bbox": box})
            entry["status"] = "review-needed" if uncertain else "illustrated" if boxes else "text"
            if boxes:
                name = f"{index:05d}-source-{sha[:12]}.png"
                if not (output / name).exists():
                    atomic_write(output / name, source_bytes)
                entry["sourceSrc"] = f"{args.asset_prefix}/{name}"
            entries.append(entry)

    manifest = {"version": MANIFEST_VERSION, "generatorVersion": GENERATOR_VERSION,
                "sourceCount": len(entries), "illustratedScreens": sum(bool(e["illustrations"]) for e in entries),
                "illustrationCount": sum(len(e["illustrations"]) for e in entries),
                "reviewRequired": [e["screenIndex"] for e in entries if e["status"] == "review-needed"],
                "records": entries}
    data = encoded(manifest)
    changed = not manifest_path.exists() or manifest_path.read_bytes() != data
    if changed:
        atomic_write(manifest_path, data)
    return {"ok": True, "manifest": str(manifest_path), "sourceCount": len(entries),
            "illustratedScreens": manifest["illustratedScreens"],
            "illustrationCount": manifest["illustrationCount"],
            "reviewRequired": manifest["reviewRequired"], "reused": reused, "changed": changed}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--job", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--overrides", type=Path)
    parser.add_argument("--layouts", type=Path)
    parser.add_argument("--asset-prefix", default="illustrations")
    parser.add_argument("--direction", choices=("rtl", "ltr"), default="rtl")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    if (not args.asset_prefix or args.asset_prefix.startswith("/")
            or ".." in Path(args.asset_prefix).parts or ":" in args.asset_prefix):
        parser.error("asset-prefix must be a safe relative folder path")
    signal.signal(signal.SIGTERM, lambda _signum, _frame: sys.exit(130))
    try:
        print(json.dumps(run(args), ensure_ascii=False))
        return 0
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
