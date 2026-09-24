#!/usr/bin/env python3
"""Build self-contained book readers with portable, high-quality JPEG artwork.

Only PNG/JPEG files directly inside the reader's illustrations directory are
eligible. Source artwork is never changed. Cached derivatives retain the
source's content-addressed filename and add a versioned rendering policy.

prepare_assets(job, manifest) populates the cache for ebook export.
asset(job, src) resolves one illustration to a verified cached JPEG.
--job PATH prepares every asset in its illustrations/manifest.json.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import sys
import tempfile
from pathlib import Path, PurePosixPath

from PIL import Image, ImageOps

POLICY = "ipad-v1"
MAX_EDGE = 2200
JPEG_QUALITY = 92
ALLOWED_FORMATS = {"PNG", "JPEG"}


def atomic_write(path: Path, data: bytes) -> None:
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


def portable_path(src: str) -> str:
    """Return the policy-versioned cache path; this rule is shared with Lua."""
    if not isinstance(src, str) or not src or "\\" in src or "\x00" in src:
        raise ValueError("Illustration source must be a safe relative PNG/JPEG path")
    parts = PurePosixPath(src).parts
    if (len(parts) != 2 or parts[0] != "illustrations" or src != "/".join(parts)
            or parts[1] in {".", ".."} or Path(parts[1]).suffix.lower() not in {".png", ".jpg", ".jpeg"}):
        raise ValueError(f"Unsupported illustration source: {src}")
    return f"illustrations/portable/{parts[1]}.{POLICY}.jpg"


def confined(job: Path, relative: str) -> Path:
    path = job / relative
    try:
        illustration_root = (job / "illustrations").resolve()
        illustration_root.relative_to(job)
        path.resolve().relative_to(illustration_root)
    except ValueError:
        raise ValueError(f"Illustration path escapes the book folder: {relative}") from None
    return path


def asset(job: Path, src: str) -> tuple[Path, bool, int, int]:
    """Prepare one derivative, returning path, generated, source/output sizes."""
    job = Path(job).expanduser().resolve()
    target_relative = portable_path(src)
    source = confined(job, src)
    target = confined(job, target_relative)
    metadata = confined(job, target_relative + ".json")
    source_data = source.read_bytes()  # Missing artwork aborts before HTML replacement.
    source_sha = hashlib.sha256(source_data).hexdigest()
    stamp = {"policy": POLICY, "sourceSHA256": source_sha}
    if target.is_file() and metadata.is_file():
        try:
            cached = target.read_bytes()
            expected = dict(stamp, jpegSHA256=hashlib.sha256(cached).hexdigest())
            if json.loads(metadata.read_text(encoding="utf-8")) == expected:
                return target, False, len(source_data), len(cached)
        except (OSError, ValueError):
            pass
    with Image.open(io.BytesIO(source_data)) as original:
        if original.format not in ALLOWED_FORMATS:
            raise ValueError(f"Illustration is not PNG/JPEG: {src}")
        original.load()
        picture = ImageOps.exif_transpose(original)
        if picture.mode in {"RGBA", "LA"} or "transparency" in picture.info:
            rgba = picture.convert("RGBA")
            canvas = Image.new("RGBA", rgba.size, "white")
            canvas.alpha_composite(rgba)
            picture = canvas.convert("RGB")
        else:
            picture = picture.convert("RGB")
        picture.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
        output = io.BytesIO()
        picture.save(output, format="JPEG", quality=JPEG_QUALITY, subsampling=0,
                     optimize=True, progressive=False)
    data = output.getvalue()
    atomic_write(target, data)
    stamp["jpegSHA256"] = hashlib.sha256(data).hexdigest()
    atomic_write(metadata, (json.dumps(stamp, sort_keys=True) + "\n").encode("utf-8"))
    return target, True, len(source_data), len(data)


def prepare_assets(job: Path, manifest: dict) -> dict:
    """Prepare all unique source-page and cropped-art assets in a manifest."""
    job = Path(job).expanduser().resolve()
    sources = set()
    records = manifest.get("records")
    if not isinstance(records, list):
        raise ValueError("Illustration manifest has no records list")
    for record in records:
        if record.get("sourceSrc"):
            sources.add(record["sourceSrc"])
        for illustration in record.get("illustrations", []):
            sources.add(illustration["src"])
    result = {"policy": POLICY, "assetCount": len(sources), "generated": 0,
              "reused": 0, "sourceBytes": 0, "portableBytes": 0}
    # Validate every path before generating any derivative.
    for src in sources:
        portable_path(src)
        confined(job, src)
    for src in sorted(sources):
        _path, generated, source_size, target_size = asset(job, src)
        result["generated" if generated else "reused"] += 1
        result["sourceBytes"] += source_size
        result["portableBytes"] += target_size
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--job", type=Path, required=True)
    args = parser.parse_args()
    try:
        manifest = json.loads((args.job / "illustrations" / "manifest.json").read_text(encoding="utf-8"))
        print(json.dumps(prepare_assets(args.job, manifest), ensure_ascii=False))
        return 0
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
