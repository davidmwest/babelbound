# Contributing

Babelbound is a desktop tool with a portable export layer. You can work on its parsing, persistence, or EPUB behavior without opening Chrome. Changes to the live reader workflow need a separate macOS check.

## Set up a development environment

Use Python 3.10+ and Lua 5.4. From the repository root:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
python -m unittest discover -s tests -p 'test_*.py' -v
for file in tests/test_*.lua; do lua "$file" || exit; done
```

Use `lua5.4` if that is the executable name on your system. These tests use synthetic data and memory-only Hammerspoon stand-ins; they do not send model requests or control the desktop. The [test guide](tests/README.md) describes coverage. The [offline demo](scripts/demo.py) exercises the real export path with invented content.

## Keep changes reviewable

Start with the concrete failure or behavior you want to change. Include a small synthetic reproduction when practical. Link the relevant [design decision](docs/design-notes.md) or [module](docs/architecture.md) rather than copying the entire architecture into a pull request.

For a fix, explain the trigger, what previously happened, and what now happens. Record the checks you ran and their limits. UI changes need the Chrome, macOS, and Hammerspoon versions used for the manual check. An offline pass does not establish that the current Gemini sidebar still exposes the same controls.

Save each completed repository update as a new commit with a descriptive message. Keep published commits intact; do not amend or rewrite them unless the repository owner explicitly requests it. Tag a new version for a new packaged release rather than replacing a published release's contents.

## Protect the recovery guarantees

- Persist a pending request before sending it. Collect a sent request before considering a resend.
- Commit an accepted response before advancing. Keep ambiguous turns recoverable rather than clicking again automatically.
- Preserve original captures and responses when changing derived HTML or EPUB output.
- Keep background writers serialized and reject stale callbacks after cancellation.
- Keep image paths confined to the intended job assets. Avoid network resources in EPUB export.

Persistence and request-flow changes need failure-path regressions. Cosmetic documentation edits do not need new implementation tests. Avoid broad formatting or unrelated refactors in a behavior fix.

## Use shareable examples

Use invented text and generated fixtures for tests and examples. Do not commit real job folders, session tokens, private browser captures, account details, or full book archives. Review diagnostics before attaching them to an issue; they can contain source text and local paths.

Original contributions use this project's [MIT license](LICENSE). Preserve third-party notices and respect the [screenshot exceptions](NOTICE.md). Explain any added runtime dependency and why the existing standard library or Pillow cannot reasonably do the job.
