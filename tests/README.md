# Offline tests

These tests use generated images, invented book text, temporary directories,
and in-memory Hammerspoon stand-ins. They do not open a browser, send requests,
press keys, turn pages, read installed jobs, or require Hammerspoon.

From the repository root, with Python 3.10+ and Lua 5.4 installed:

```sh
python3 -m pip install "Pillow>=10.1,<13"
python3 -m unittest discover -s tests -p 'test_*.py' -v
for file in tests/test_*.lua; do lua "$file" || exit; done
```

Use `lua5.4` instead of `lua` if that is the interpreter's name on your system.
Every test resolves the production modules in `hammerspoon/` relative to its
own file, so it can also run individually from another working directory.

Python tests cover EPUB packaging and metadata, cover selection, prose cleanup,
artwork layout, missing or unsafe resources, atomic export failure, image
optimization, and cache freshness. Installer tests cover dry runs, customized
prompts, backups, repeat installation, safe Lua loader edits, path validation,
and dependency failures. The offline demo smoke test checks packaged artwork,
reading order, continuation cleanup, network-free operation, and refusal to
replace an existing output path. All image fixtures are created at test time.
Illustration extraction tests check committed-screen selection, stale review
rejection, cache reuse, preservation of the published manifest after a failure,
and exact crop contents and ordering.

To inspect the same synthetic export yourself:

```sh
python3 scripts/demo.py --output demo-output
```

Open `demo-output/translation.html` in a browser or import
`demo-output/translation.epub` into an ebook reader. The invented English text
and geometric illustration do not use a model, browser automation, or an
account. The command requires a new directory; use a different `--output` path
for another run. It refuses an existing directory, file, or symlink.

Lua tests cover status and percentage progress, prepared-draft resume and
duplicate-submit prevention, source review and cancellation, page-turn focus
and write-ahead guards, response markers, job naming and transactional renames,
automatic EPUB export, its asynchronous writer queue, and pre-load configuration.
Main-module tests
load the actual production code into a memory-only environment; no separate
copy of the translator implementation is used.

The GitHub workflow also compiles every Lua file before running the tests on
Ubuntu 24.04 with Python 3.10 and macOS 15 with Python 3.14, using Lua 5.4 on both.
Native Chrome accessibility, screen capture, and the Apple Books interface
still require manual validation on macOS.
