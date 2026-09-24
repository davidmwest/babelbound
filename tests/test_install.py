"""Offline installer regressions; all files live in temporary directories."""

import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from support import ROOT

spec = importlib.util.spec_from_file_location("bt_install", ROOT / "scripts" / "install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def snapshot(folder):
    return {str(path.relative_to(folder)): path.read_bytes()
            for path in folder.rglob("*") if path.is_file() and not path.is_symlink()}


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="bt install fixture ")
        self.folder = Path(self.temp.name)
        self.package = self.folder / "package with spaces"
        self.source = self.package / "hammerspoon"
        self.source.mkdir(parents=True)
        for name in installer.FILES:
            (self.source / name).write_bytes(("synthetic packaged content: " + name + "\n").encode())
        (self.package / "requirements.txt").write_text("Pillow>=10.1,<13\n")
        self.config = self.folder / "config with spaces"

    def tearDown(self):
        self.temp.cleanup()

    def invoke(self, *arguments, **mocks):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(installer, "ROOT", self.package))
            stack.enter_context(contextlib.redirect_stdout(stdout))
            stack.enter_context(contextlib.redirect_stderr(stderr))
            for key, value in mocks.items():
                stack.enter_context(patch.object(installer, key, value))
            result = installer.main(["--config-dir", str(self.config), *arguments])
        return result, stdout.getvalue(), stderr.getvalue()

    def test_fresh_plan_is_read_only_then_installs_into_path_with_spaces(self):
        before = snapshot(self.folder)
        plan = installer.plan_install(self.config, self.source)
        self.assertEqual(len(plan), len(installer.FILES) + 1)
        self.assertEqual(snapshot(self.folder), before)
        self.assertFalse(self.config.exists())
        backup = installer.apply_plan(self.config, plan)
        self.assertIsNone(backup)
        for name in installer.FILES:
            self.assertEqual((self.config / name).read_bytes(), (self.source / name).read_bytes())
        self.assertIn(installer.LOAD_LINE, (self.config / "init.lua").read_text())

    def test_dry_run_makes_no_files_and_never_runs_dependency_commands(self):
        before = snapshot(self.folder)
        with patch.object(installer.subprocess, "run", side_effect=AssertionError("No processes in dry run")):
            result, stdout, stderr = self.invoke("--dry-run")
        self.assertEqual(result, 0, stderr)
        self.assertIn("Dry run complete", stdout)
        self.assertEqual(snapshot(self.folder), before)
        self.assertFalse(self.config.exists())

    def test_existing_custom_prompt_init_and_unrelated_config_are_preserved(self):
        self.config.mkdir()
        customized = b"My own translation style instructions.\n"
        old_distribution = b"Prior distributed instructions.\n"
        old_module = b"-- older translator module\n"
        old_init = b"-- personal shortcuts\nhs.hotkey.bind({}, 'F1', function() end)"
        (self.config / "gemini_book_prompt.txt").write_bytes(customized)
        (self.config / "gemini_book_prompt.txt.dist").write_bytes(old_distribution)
        (self.config / "gemini_book.lua").write_bytes(old_module)
        (self.config / "init.lua").write_bytes(old_init)
        (self.config / "unrelated.lua").write_bytes(b"return 'keep me'\n")
        backup = installer.apply_plan(self.config, installer.plan_install(self.config, self.source))
        self.assertIsNotNone(backup)
        self.assertEqual((self.config / "gemini_book_prompt.txt").read_bytes(), customized)
        self.assertEqual((self.config / "gemini_book_prompt.txt.dist").read_bytes(), (self.source / "gemini_book_prompt.txt").read_bytes())
        self.assertEqual((self.config / "unrelated.lua").read_bytes(), b"return 'keep me'\n")
        new_init = (self.config / "init.lua").read_bytes()
        self.assertTrue(new_init.startswith(old_init + b"\n"))
        self.assertEqual(new_init.count(installer.LOAD_LINE.encode()), 1)
        self.assertEqual((backup / "init.lua").read_bytes(), old_init)
        self.assertEqual((backup / "gemini_book.lua").read_bytes(), old_module)
        self.assertEqual((backup / "gemini_book_prompt.txt.dist").read_bytes(), old_distribution)
        self.assertFalse((backup / "gemini_book_prompt.txt").exists())
        self.assertFalse((backup / "unrelated.lua").exists())

    def test_repeated_install_is_idempotent_including_custom_prompt(self):
        self.config.mkdir()
        (self.config / "gemini_book_prompt.txt").write_text("Customized prompt\n")
        installer.apply_plan(self.config, installer.plan_install(self.config, self.source))
        before = snapshot(self.config)
        plan = installer.plan_install(self.config, self.source)
        self.assertEqual(plan, [])
        self.assertIsNone(installer.apply_plan(self.config, plan))
        self.assertEqual(snapshot(self.config), before)

    def test_no_init_leaves_existing_bytes_or_absence_untouched(self):
        for existing in (None, b"-- non-UTF8 user content: \xff\n"):
            with self.subTest(existing=existing):
                config = self.config / str(existing is not None)
                config.mkdir(parents=True)
                if existing is not None:
                    (config / "init.lua").write_bytes(existing)
                plan = installer.plan_install(config, self.source, update_init=False)
                self.assertFalse(any(path.name == "init.lua" for path, _ in plan))
                installer.apply_plan(config, plan)
                self.assertEqual((config / "init.lua").read_bytes() if (config / "init.lua").exists() else None, existing)

    def test_main_no_init_option_preserves_existing_loader_configuration(self):
        self.config.mkdir()
        original = b"return require('personal_config')\n"
        (self.config / "init.lua").write_bytes(original)
        with patch.object(installer.sys, "platform", "darwin"), \
             patch.object(installer, "check_environment", return_value=None):
            result, stdout, stderr = self.invoke("--skip-deps", "--no-init")
        self.assertEqual(result, 0, stderr)
        self.assertEqual((self.config / "init.lua").read_bytes(), original)
        self.assertEqual((self.config / "gemini_book.lua").read_bytes(), (self.source / "gemini_book.lua").read_bytes())
        self.assertIn("Add this to init.lua when ready", stdout)

    def test_active_load_statement_is_not_duplicated(self):
        self.config.mkdir()
        for statement in ("GeminiBook = require('gemini_book')\n", 'require "gemini_book"\n',
                          'local translator = require ( "gemini_book" )\n'):
            with self.subTest(statement=statement):
                (self.config / "init.lua").write_text(statement)
                plan = installer.plan_install(self.config, self.source)
                self.assertFalse(any(path.name == "init.lua" for path, _ in plan))

    def test_commented_load_statement_does_not_suppress_install(self):
        self.config.mkdir()
        for comment in ("-- require('gemini_book')\n", '--[[ require("gemini_book") ]]\n',
                        '--[=[\nGeminiBook = require "gemini_book"\n]=]\n'):
            with self.subTest(comment=comment):
                (self.config / "init.lua").write_text(comment)
                plan = dict(installer.plan_install(self.config, self.source))
                self.assertTrue(plan[self.config / "init.lua"].startswith(comment.encode()))
                self.assertTrue(plan[self.config / "init.lua"].endswith((installer.LOAD_LINE + "\n").encode()))

    def test_load_detection_ignores_string_literals_and_understands_real_comments(self):
        for inactive in ('''local example = 'require("gemini_book")' ''',
                         '''local example = "require('gemini_book')" ''',
                         '''local help = [=[ require("gemini_book") ]=]'''):
            with self.subTest(inactive=inactive):
                self.assertFalse(installer.has_load_line(inactive))
        for active in ('''local note = "--"; GeminiBook = require('gemini_book')''',
                       '''local note = '--[['; GeminiBook = require('gemini_book')''',
                       '''-- ignored require('other')\nGeminiBook = require -- comment\n('gemini_book')'''):
            with self.subTest(active=active):
                self.assertTrue(installer.has_load_line(active))

    def test_top_level_return_is_rejected_before_writes_and_no_init_remains_available(self):
        self.config.mkdir()
        original = b"-- use another configuration module\nreturn require('my_config')\n"
        (self.config / "init.lua").write_bytes(original)
        before = snapshot(self.folder)
        with self.assertRaisesRegex(ValueError, "top-level return.*--no-init"):
            installer.plan_install(self.config, self.source)
        self.assertEqual(snapshot(self.folder), before)
        plan = installer.plan_install(self.config, self.source, update_init=False)
        installer.apply_plan(self.config, plan)
        self.assertEqual((self.config / "init.lua").read_bytes(), original)

    def test_returns_in_nested_blocks_strings_and_comments_allow_append(self):
        self.config.mkdir()
        for original in ("local function getConfig() return {} end\n",
                         "local getConfig = function() return {} end\n",
                         "if false then return end\n", "do return end\n",
                         "for i = 1, 2 do if i == 3 then return end end\n",
                         "repeat if false then return end until true\n",
                         "local help = 'return require(\"my_config\")'\n",
                         "-- return require('my_config')\n"):
            with self.subTest(original=original):
                (self.config / "init.lua").write_text(original)
                plan = dict(installer.plan_install(self.config, self.source))
                updated = plan[self.config / "init.lua"]
                self.assertTrue(updated.startswith(original.encode()))
                self.assertTrue(updated.endswith((installer.LOAD_LINE + "\n").encode()))

    def test_top_level_return_after_closed_nested_block_still_rejected(self):
        self.config.mkdir()
        for prefix in ("local function helper() return 1 end\n",
                       "if false then return end\n", "do local x = 1 end\n"):
            with self.subTest(prefix=prefix):
                (self.config / "init.lua").write_text(prefix + "return require('my_config')\n")
                with self.assertRaisesRegex(ValueError, "top-level return"):
                    installer.plan_install(self.config, self.source)

    def test_unsafe_destination_symlinks_and_nonfiles_fail_before_writes(self):
        self.config.mkdir()
        outside = self.folder / "outside.txt"
        outside.write_bytes(b"untouched")
        for name in ("gemini_book.lua", "init.lua", "gemini_book_prompt.txt"):
            for kind in ("symlink", "directory"):
                path = self.config / name
                with self.subTest(name=name, kind=kind):
                    if kind == "symlink":
                        path.symlink_to(outside)
                    else:
                        path.mkdir()
                    before = snapshot(self.folder)
                    with self.assertRaises(ValueError):
                        installer.plan_install(self.config, self.source)
                    self.assertEqual(snapshot(self.folder), before)
                    self.assertEqual(outside.read_bytes(), b"untouched")
                    if kind == "symlink":path.unlink()
                    else:path.rmdir()

    def test_custom_prompt_distribution_symlink_is_rejected(self):
        self.config.mkdir()
        (self.config / "gemini_book_prompt.txt").write_text("Custom prompt")
        outside = self.folder / "outside.txt"
        outside.write_bytes(b"untouched")
        (self.config / "gemini_book_prompt.txt.dist").symlink_to(outside)
        with self.assertRaises(ValueError):
            installer.plan_install(self.config, self.source)
        self.assertEqual(outside.read_bytes(), b"untouched")

    def test_missing_or_symlinked_packaged_file_prevents_any_application_writes(self):
        last = self.source / installer.FILES[-1]
        original = last.read_bytes()
        last.unlink()
        before = snapshot(self.folder)
        with self.assertRaises(ValueError):
            installer.plan_install(self.config, self.source)
        self.assertEqual(snapshot(self.folder), before)
        self.assertFalse(self.config.exists())
        other = self.folder / "outside-module.lua"
        other.write_bytes(original)
        last.symlink_to(other)
        with self.assertRaises(ValueError):
            installer.plan_install(self.config, self.source)
        self.assertFalse(self.config.exists())

    def test_backup_symlink_prevents_replacement(self):
        self.config.mkdir()
        (self.config / "gemini_book.lua").write_bytes(b"old module")
        target = self.folder / "other backups"
        target.mkdir()
        (self.config / "bt-backups").symlink_to(target)
        before = snapshot(self.folder)
        with self.assertRaises(ValueError):
            installer.apply_plan(self.config, installer.plan_install(self.config, self.source))
        self.assertEqual(snapshot(self.folder), before)

    def test_atomic_replacement_preserves_existing_mode(self):
        self.config.mkdir()
        module = self.config / "gemini_book.lua"
        module.write_bytes(b"old module")
        module.chmod(0o640)
        installer.apply_plan(self.config, installer.plan_install(self.config, self.source))
        self.assertEqual(module.stat().st_mode & 0o777, 0o640)

    def test_main_refuses_dependency_failure_before_copying_application_files(self):
        self.config.mkdir()
        module = self.config / "gemini_book.lua"
        module.write_bytes(b"old module")
        before = snapshot(self.folder)
        with patch.object(installer.sys, "platform", "darwin"), patch.object(
            installer, "check_environment", side_effect=ValueError("fixture missing Pillow")):
            result, stdout, stderr = self.invoke("--skip-deps")
        self.assertEqual(result, 1)
        self.assertIn("fixture missing Pillow", stderr)
        self.assertEqual(snapshot(self.folder), before)

    def test_main_refuses_failed_python_without_copying_application_files(self):
        before = snapshot(self.folder)
        with patch.object(installer.sys, "platform", "darwin"), \
             patch.object(installer, "check_python", side_effect=ValueError("fixture unsupported Python")), \
             patch.object(installer.subprocess, "run", side_effect=AssertionError("No subprocess after invalid Python")):
            result, _stdout, stderr = self.invoke("--python", "/fixture/python with spaces")
        self.assertEqual(result, 1)
        self.assertIn("fixture unsupported Python", stderr)
        self.assertEqual(snapshot(self.folder), before)
        self.assertFalse(self.config.exists())

    def test_main_refuses_pip_failure_without_replacing_existing_application_files(self):
        python = self.config / ".bt-venv" / "bin" / "python3"
        python.parent.mkdir(parents=True)
        python.write_bytes(b"synthetic executable placeholder")
        (self.config / "gemini_book.lua").write_bytes(b"old working module")
        before = snapshot(self.folder)
        with patch.object(installer.sys, "platform", "darwin"), \
             patch.object(installer, "check_python", return_value=None), \
             patch.object(installer.subprocess, "run", side_effect=subprocess.CalledProcessError(1, [str(python)])) as run:
            result, _stdout, stderr = self.invoke()
        self.assertEqual(result, 1)
        self.assertIn("Installation stopped", stderr)
        self.assertEqual(run.call_args.args[0][:4], [str(python), "-m", "pip", "install"])
        self.assertEqual(snapshot(self.folder), before)

    def test_main_missing_requirements_is_rejected_before_any_dependency_setup(self):
        (self.package / "requirements.txt").unlink()
        with patch.object(installer.subprocess, "run", side_effect=AssertionError("No dependency writes")):
            result, _stdout, stderr = self.invoke()
        self.assertEqual(result, 1)
        self.assertIn("missing requirements.txt", stderr)
        self.assertFalse(self.config.exists())

    def test_main_prevalidates_missing_package_before_dependency_setup(self):
        (self.source / installer.FILES[-1]).unlink()
        with patch.object(installer.subprocess, "run", side_effect=AssertionError("No dependency writes")):
            result, _stdout, stderr = self.invoke()
        self.assertEqual(result, 1)
        self.assertIn("Missing or invalid packaged source", stderr)
        self.assertFalse(self.config.exists())

    def test_main_rejects_helper_environment_symlink(self):
        self.config.mkdir()
        elsewhere = self.folder / "other environment"
        elsewhere.mkdir()
        (self.config / ".bt-venv").symlink_to(elsewhere)
        with patch.object(installer.subprocess, "run", side_effect=AssertionError("No dependency writes")):
            result, _stdout, stderr = self.invoke("--dry-run")
        self.assertEqual(result, 1)
        self.assertIn("symlink helper environment", stderr)
        self.assertEqual(list(elsewhere.iterdir()), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
