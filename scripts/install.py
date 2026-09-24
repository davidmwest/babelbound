#!/usr/bin/env python3
"""Install Babelbound without replacing unrelated Hammerspoon configuration."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FILES = (
    "gemini_book.lua", "gemini_book_ax.lua", "gemini_book_core.lua",
    "gemini_book_epub.lua", "gemini_book_epub.py", "gemini_book_focus.lua",
    "gemini_book_illustrations.py", "gemini_book_jobs.lua", "gemini_book_limits.lua",
    "gemini_book_move.py", "gemini_book_names.lua", "gemini_book_portable.py",
    "gemini_book_prior_reply.lua", "gemini_book_prompt.txt", "gemini_book_rename.lua",
    "gemini_book_resume.lua", "gemini_book_skill.lua", "gemini_book_source.lua",
    "gemini_book_status.lua",
)
LOAD_LINE = 'GeminiBook = require("gemini_book")'
LONG_OPEN = re.compile(r"\[(=*)\[")
TOKEN = re.compile(r"[A-Za-z_][A-Za-z_0-9]*|[^\s]")


def lua_tokens(text: str):
    """Tokenize enough Lua to distinguish executable require calls from examples."""
    pos = 0
    while pos < len(text):
        comment = text.startswith("--", pos)
        start = pos + 2 if comment else pos
        long = LONG_OPEN.match(text, start)
        if long:
            closing = "]" + long.group(1) + "]"
            end = text.find(closing, long.end())
            end = len(text) if end < 0 else end
            if not comment:
                yield ("string", text[long.end():end].lstrip("\n"))
            pos = min(len(text), end + len(closing))
        elif comment:
            end = text.find("\n", start)
            pos = len(text) if end < 0 else end + 1
        elif text[pos] in "\"'":
            quote = text[pos]
            pos += 1
            value = []
            while pos < len(text) and text[pos] != quote:
                if text[pos] == "\\" and pos + 1 < len(text):
                    pos += 1
                value.append(text[pos])
                pos += 1
            pos += 1
            yield ("string", "".join(value))
        else:
            token = TOKEN.match(text, pos)
            if token:
                yield ("code", token.group())
                pos = token.end()
            else:
                pos += 1


def has_load_line(text: str) -> bool:
    tokens = list(lua_tokens(text))
    for index, token in enumerate(tokens):
        if token != ("code", "require"):
            continue
        following = index + 1
        if following < len(tokens) and tokens[following] == ("code", "("):
            following += 1
        if following < len(tokens) and tokens[following] == ("string", "gemini_book"):
            return True
    return False


def has_top_level_return(text: str) -> bool:
    blocks = []
    for kind, token in lua_tokens(text):
        if kind != "code":
            continue
        if token in {"function", "if", "do", "repeat"}:
            blocks.append(token)
        elif token in {"end", "until"}:
            if blocks:
                blocks.pop()
        elif token == "return" and not blocks:
            return True
    return False


def plain_file(path: Path) -> None:
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"Refusing to replace a symlink or non-file: {path}")


def plan_install(config: Path, source: Path, update_init: bool = True) -> list[tuple[Path, bytes]]:
    """Read and validate everything before copying any application files."""
    planned = []
    for name in FILES:
        src = source / name
        if src.is_symlink() or not src.is_file():
            raise ValueError(f"Missing or invalid packaged source: {src}")
        data = src.read_bytes()
        dest = config / name
        plain_file(dest)
        if dest.exists() and dest.read_bytes() == data:
            continue
        if name == "gemini_book_prompt.txt" and dest.exists():
            dest = config / (name + ".dist")
            plain_file(dest)
            if dest.exists() and dest.read_bytes() == data:
                continue
        planned.append((dest, data))
    if update_init:
        init = config / "init.lua"
        plain_file(init)
        original = init.read_bytes() if init.exists() else b""
        text = original.decode("utf-8")
        if not has_load_line(text):
            if has_top_level_return(text):
                raise ValueError("init.lua has a top-level return. Use --no-init, then add the Babelbound load line before that return manually.")
            addition = ("\n" if original and not original.endswith(b"\n") else "")
            addition += "\n-- Babelbound\n" + LOAD_LINE + "\n"
            planned.append((init, original + addition.encode("utf-8")))
    return planned


def atomic_write(path: Path, data: bytes) -> None:
    fd, temporary = tempfile.mkstemp(prefix=".bt-install-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(temporary, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def apply_plan(config: Path, planned: list[tuple[Path, bytes]]) -> Path | None:
    config.mkdir(parents=True, exist_ok=True)
    existing = [path for path, _ in planned if path.exists()]
    backup = None
    if existing:
        parent = config / "bt-backups"
        if parent.is_symlink():
            raise ValueError(f"Refusing symlink backup directory: {parent}")
        parent.mkdir(exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ-")
        backup = Path(tempfile.mkdtemp(prefix=stamp, dir=parent))
        for path in existing:
            shutil.copy2(path, backup / path.name)
    for path, data in planned:
        atomic_write(path, data)
    return backup


def check_python(python: str) -> None:
    subprocess.run([python, "-c", "import sys; assert sys.version_info >= (3,10), 'Python 3.10+ is required'"], check=True)


def check_environment(python: Path) -> None:
    if not python.is_file():
        raise ValueError(f"Helper environment is missing: {python}. Run without --skip-deps first.")
    check_python(str(python))
    subprocess.run([str(python), "-c", (
        "import PIL; from PIL import Image, ImageFont; "
        "v=tuple(map(int,PIL.__version__.split('.')[:2])); "
        "assert (10,1)<=v<(13,0), 'Pillow>=10.1,<13 is required'; "
        "ImageFont.load_default(size=12)"
    )], check=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=Path, default=Path.home() / ".hammerspoon")
    parser.add_argument("--python", default=sys.executable, help="Python 3.10+ used to create the helper environment")
    parser.add_argument("--no-init", action="store_true")
    parser.add_argument("--skip-deps", action="store_true", help="Require an existing working .bt-venv")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    try:
        if sys.version_info < (3, 10):
            raise ValueError("The installer requires Python 3.10 or newer.")
        config = args.config_dir.expanduser().absolute()
        if config.exists() and not config.is_dir():
            raise ValueError(f"Configuration path is not a directory: {config}")
        env = config / ".bt-venv"
        if env.is_symlink():
            raise ValueError(f"Refusing symlink helper environment: {env}")
        python = env / "bin" / "python3"
        planned = plan_install(config, ROOT / "hammerspoon", not args.no_init)
        requirements = ROOT / "requirements.txt"
        if not requirements.is_file():
            raise ValueError("The package is missing requirements.txt")
        print(f"Babelbound installation directory: {config}")
        for path, _ in planned:
            print(f"  {'Update' if path.exists() else 'Create'} {path.name}")
        if args.dry_run:
            print(f"Would {'validate' if args.skip_deps else 'prepare'} {env}")
            print("Dry run complete; no files changed.")
            return 0
        if sys.platform != "darwin":
            raise ValueError("Babelbound requires macOS. Use --dry-run to inspect the install elsewhere.")
        if args.skip_deps:
            check_environment(python)
        else:
            check_python(args.python)
            if not env.exists():
                subprocess.run([args.python, "-m", "venv", str(env)], check=True)
            elif not python.is_file():
                raise ValueError(f"Incomplete helper environment: {env}. Move it aside before retrying.")
            subprocess.run([str(python), "-m", "pip", "install", "-r", str(requirements)], check=True)
            check_environment(python)
        backup = apply_plan(config, planned)
        if backup:
            print(f"Replaced files backed up to: {backup}")
        print("Babelbound installed (BT menu). Grant Hammerspoon Accessibility and Screen Recording access, then choose Reload Config.")
        if args.no_init:
            print(f"Add this to init.lua when ready: {LOAD_LINE}")
        return 0
    except (ValueError, OSError, UnicodeError, subprocess.CalledProcessError) as error:
        print(f"Installation stopped: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
