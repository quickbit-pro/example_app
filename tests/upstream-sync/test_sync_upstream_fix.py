"""Integration tests: disposable repositories only, no network or source writes."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/sync-upstream-fix.sh"
SOURCE_URL = "https://github.com/quickbit-pro/hoppa_demo_app.git"
TARGET_URL = "https://github.com/quickbit-pro/sample_mobile_app.git"


class SyncUpstreamFixTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="sample-upstream-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "example-source"
        self.target = self.root / "sample"
        self.env = dict(os.environ)
        # Tests must not use personal hooks, credentials, signing or Git identity.
        self.env.update({
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_EDITOR": "true",
        })
        for variable in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            self.env.pop(variable, None)
        self.run_command(self.root, "git", "init", "-b", "main", str(self.source))
        self.configure_identity(self.source)
        destination = self.source / "scripts/sync-upstream-fix.sh"
        destination.parent.mkdir(parents=True)
        shutil.copy2(SCRIPT, destination)
        self.write(self.source, "backend/logic.txt", "original\n")
        self.write(self.source, "mobile_flutter/lib/features/cards/presentation/card_screen.dart", "original UI\n")
        self.write(self.source, "mobile_flutter/assets/branding/logo.svg", "original logo\n")
        self.base = self.commit(self.source, "Initial shared history")
        self.git(self.source, "remote", "add", "origin", SOURCE_URL)
        self.run_command(self.root, "git", "clone", str(self.source), str(self.target))
        self.configure_identity(self.target)
        self.git(self.target, "remote", "set-url", "origin", TARGET_URL)
        self.git(self.target, "remote", "add", "upstream", SOURCE_URL)
        self.git(self.target, "remote", "set-url", "--push", "upstream", "DISABLED")
        # Keep production remote checks intact; Git rewrites only this fetch URL
        # to a disposable local repository. The script does not get a bypass flag.
        self.git(self.target, "config", f"url.{self.source.as_uri()}.insteadOf", SOURCE_URL)

    def run_command(self, directory, *arguments, check=True):
        result = subprocess.run(
            arguments, cwd=directory, env=self.env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        if check and result.returncode:
            self.fail(f"Command failed: {arguments!r}\n{result.stdout}")
        return result

    def git(self, directory, *arguments):
        return self.run_command(directory, "git", *arguments).stdout.strip()

    def configure_identity(self, directory):
        self.git(directory, "config", "user.name", "Sync test")
        self.git(directory, "config", "user.email", "sync-test@example.invalid")
        self.git(directory, "config", "commit.gpgsign", "false")
        self.git(directory, "config", "core.hooksPath", str(self.root / "no-hooks"))
        self.git(directory, "config", "maintenance.auto", "false")

    @staticmethod
    def write(directory, name, content):
        path = directory / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self, directory, message):
        self.git(directory, "add", "--all")
        self.git(directory, "commit", "-m", message)
        return self.git(directory, "rev-parse", "HEAD")

    def fix(self, path="backend/logic.txt", content="fixed\n"):
        self.write(self.source, path, content)
        return self.commit(self.source, "Fix a functional regression")

    @staticmethod
    def source_snapshot(directory):
        digest = hashlib.sha256()
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                digest.update(str(path.relative_to(directory)).encode())
                digest.update(path.read_bytes())
        return digest.hexdigest()

    def invoke(self, *arguments, directory=None):
        source_before = self.source_snapshot(self.source)
        config_before = (self.target / ".git/config").read_bytes()
        result = self.run_command(
            directory or self.target,
            "bash", str((directory or self.target) / "scripts/sync-upstream-fix.sh"),
            *arguments, check=False,
        )
        self.assertEqual(source_before, self.source_snapshot(self.source), "Source repository was changed")
        self.assertEqual(config_before, (self.target / ".git/config").read_bytes(), "Remote/config settings were changed")
        return result

    def assert_rejected(self, result, text):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(text, result.stdout)
        self.assertEqual(self.git(self.target, "rev-parse", "main"), self.base)

    def test_preview_fetches_without_changing_worktree_or_branches(self):
        sha = self.fix()
        branches_before = self.git(self.target, "for-each-ref", "refs/heads/")
        result = self.invoke(sha[:10])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Preview only", result.stdout)
        self.assertEqual(self.git(self.target, "for-each-ref", "refs/heads/"), branches_before)
        self.assertEqual(self.git(self.target, "status", "--porcelain"), "")
        self.assertEqual((self.target / "backend/logic.txt").read_text(), "original\n")
        self.assertEqual(self.git(self.target, "rev-parse", "upstream/main"), sha)

    def test_apply_creates_attributed_branch_without_changing_main(self):
        sha = self.fix()
        result = self.invoke("--apply", sha)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.git(self.target, "branch", "--show-current"), f"codex/upstream-fix-{sha[:12]}")
        self.assertEqual(self.git(self.target, "rev-parse", "main"), self.base)
        self.assertIn(f"(cherry picked from commit {sha})", self.git(self.target, "log", "-1", "--format=%B"))
        self.assertEqual((self.target / "backend/logic.txt").read_text(), "fixed\n")
        self.assertEqual(self.git(self.target, "status", "--porcelain"), "")

    def test_rejects_untracked_and_tracked_dirty_work(self):
        sha = self.fix()
        for name in ("untracked.txt", "backend/logic.txt"):
            with self.subTest(path=name):
                self.write(self.target, name, "local work\n")
                self.assert_rejected(self.invoke("--apply", sha), "checkout must be clean")
                if name == "untracked.txt":
                    (self.target / name).unlink()

    def test_refuses_to_operate_in_example_source_checkout(self):
        sha = self.fix()
        self.assert_rejected(self.invoke("--apply", sha, directory=self.source), "origin must point only")

    def test_rejects_unexpected_upstream_and_never_rewrites_it(self):
        sha = self.fix()
        self.git(self.target, "remote", "set-url", "upstream", "https://github.com/other/repository.git")
        self.assert_rejected(self.invoke(sha), "upstream must point only")

    def test_rejects_multiple_origin_urls(self):
        sha = self.fix()
        self.git(self.target, "config", "--add", "remote.origin.url", SOURCE_URL)
        self.assert_rejected(self.invoke(sha), "origin must point only")

    def test_rejects_origin_push_url_pointing_to_example(self):
        sha = self.fix()
        self.git(self.target, "remote", "set-url", "--push", "origin", SOURCE_URL)
        self.assert_rejected(self.invoke(sha), "explicit origin push URL must point only")

    def test_requires_disabled_upstream_push(self):
        sha = self.fix()
        self.git(self.target, "config", "--unset", "remote.upstream.pushurl")
        self.assert_rejected(self.invoke(sha), "push URL to DISABLED")

    def test_rejects_commit_outside_upstream_main(self):
        sha = self.fix()
        self.git(self.target, "fetch", "upstream")
        self.git(self.source, "checkout", "-b", "unmerged-fix")
        other_sha = self.fix(content="unmerged fix\n")
        self.git(self.target, "fetch", "upstream", "unmerged-fix")
        self.assert_rejected(self.invoke(other_sha), "reachable from the freshly fetched upstream/main")
        self.assertEqual(self.git(self.target, "rev-parse", "upstream/main"), sha)

    def test_rejects_merge_commit(self):
        self.git(self.source, "checkout", "-b", "fix")
        self.fix()
        self.git(self.source, "checkout", "main")
        self.git(self.source, "merge", "--no-ff", "fix", "-m", "Merge fix")
        sha = self.git(self.source, "rev-parse", "HEAD")
        self.assert_rejected(self.invoke(sha), "Merge and root commits")

    def test_rejects_root_and_empty_commits(self):
        self.assert_rejected(self.invoke(self.base), "Merge and root commits")
        self.git(self.source, "commit", "--allow-empty", "-m", "Empty commit")
        sha = self.git(self.source, "rev-parse", "HEAD")
        self.assert_rejected(self.invoke("--apply", sha), "contains no file changes")

    def test_rejects_protected_paths_even_with_ui_acknowledgment(self):
        paths = (
            "mobile_flutter/config/sample.json",
            "mobile_flutter/assets/branding/logo.svg",
            "mobile_flutter/lib/core/branding/app_branding.dart",
            "mobile_flutter/lib/brands/example/example_mark.dart",
            "mobile_flutter/lib/core/theme/app_theme.dart",
            "mobile_flutter/lib/shared/theme/app_colors.dart",
            "mobile_flutter/lib/shared/widgets/brand_loader.dart",
            "scripts/prepare-mobile-brand.py",
            "scripts/run-mobile-branded.sh",
            "scripts/requirements-branding.txt",
            "scripts/branding/index.template.html",
            "mobile_flutter/android/app/brand.properties",
            "mobile_flutter/android/app/src/main/res/drawable/launch_background.xml",
            "mobile_flutter/ios/Flutter/Brand.xcconfig",
            "mobile_flutter/ios/Flutter/Debug.xcconfig",
            "mobile_flutter/ios/Flutter/Release.xcconfig",
            "mobile_flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json",
            "mobile_flutter/ios/Runner/Info.plist",
            "mobile_flutter/web/branding/logo.png",
            "mobile_flutter/web/flutter_bootstrap.js",
            ".github/workflows/deploy.yml",
        )
        for path in paths:
            with self.subTest(path=path):
                sha = self.fix(path, "changed branding or release setting\n")
                result = self.invoke("--apply", "--reviewed-ui", sha)
                self.assert_rejected(result, "Automatic cherry-pick is blocked")
                self.assertIn(path, result.stdout)
                self.assertEqual(self.git(self.target, "branch", "--show-current"), "main")

    def test_protected_rename_cannot_bypass_guard(self):
        self.git(self.source, "mv", "mobile_flutter/assets/branding/logo.svg", "backend/moved-logo.svg")
        sha = self.commit(self.source, "Move protected logo out of assets")
        self.assert_rejected(self.invoke("--apply", sha), "mobile_flutter/assets/branding/logo.svg")

    def test_ui_preview_is_allowed_but_apply_requires_review(self):
        sha = self.fix("mobile_flutter/lib/features/cards/presentation/card_screen.dart", "functional UI fix\n")
        preview = self.invoke(sha)
        self.assertEqual(preview.returncode, 0, preview.stdout)
        self.assertIn("--reviewed-ui", preview.stdout)
        self.assert_rejected(self.invoke("--apply", sha), "Review the complete UI diff first")
        applied = self.invoke("--apply", "--reviewed-ui", sha)
        self.assertEqual(applied.returncode, 0, applied.stdout)

    def test_equivalent_patch_is_not_applied_twice(self):
        sha = self.fix()
        self.write(self.target, "backend/logic.txt", "fixed\n")
        self.commit(self.target, "Independently fixed the same issue")
        branches_before = self.git(self.target, "for-each-ref", "refs/heads/")
        result = self.invoke("--apply", sha)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("equivalent patch is already", result.stdout)
        self.assertEqual(self.git(self.target, "for-each-ref", "refs/heads/"), branches_before)

    def test_web_shell_changes_require_ui_review(self):
        for path in ("mobile_flutter/web/app_recovery.js", "mobile_flutter/web/app_bridges.js"):
            with self.subTest(path=path):
                sha = self.fix(path, "// Web shell functional change\n")
                self.assert_rejected(self.invoke("--apply", sha), "Review the complete UI diff first")

    def test_exact_commit_already_present_is_not_applied_twice(self):
        sha = self.fix()
        self.git(self.target, "fetch", "upstream")
        self.git(self.target, "merge", "--ff-only", sha)
        result = self.invoke("--apply", sha)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Already present in this branch history", result.stdout)

    def test_apply_requires_main_and_does_not_overwrite_existing_branch(self):
        sha = self.fix()
        self.git(self.target, "switch", "-c", "local-feature")
        self.assert_rejected(self.invoke("--apply", sha), "Switch to local main")
        self.git(self.target, "switch", "main")
        branch = f"codex/upstream-fix-{sha[:12]}"
        self.git(self.target, "branch", branch)
        self.assert_rejected(self.invoke("--apply", sha), "already exists")
        self.assertEqual(self.git(self.target, "rev-parse", branch), self.base)

    def test_conflict_preserves_source_and_allows_abort(self):
        sha = self.fix()
        self.write(self.target, "backend/logic.txt", "conflicting sample change\n")
        main_before = self.commit(self.target, "Sample-specific behavior")
        result = self.invoke("--apply", sha)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("Cherry-pick stopped", result.stdout)
        self.assertEqual(self.git(self.target, "rev-parse", "main"), main_before)
        self.assertEqual(self.git(self.target, "rev-parse", "CHERRY_PICK_HEAD"), sha)
        self.git(self.target, "cherry-pick", "--abort")
        self.git(self.target, "switch", "main")
        self.assertEqual((self.target / "backend/logic.txt").read_text(), "conflicting sample change\n")

    def test_rejects_revision_expressions_and_unknown_options(self):
        for argument in ("HEAD", "main", "--force", "0123456^{commit}"):
            with self.subTest(argument=argument):
                result = self.invoke(argument)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertEqual(self.git(self.target, "rev-parse", "HEAD"), self.base)


if __name__ == "__main__":
    unittest.main()
