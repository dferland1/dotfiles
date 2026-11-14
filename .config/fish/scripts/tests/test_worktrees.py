import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1]


class WorktreeScriptsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="worktree-scripts-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "project with spaces"
        self.repo.mkdir()
        self.git("init", "-q")
        (self.repo / "Tiltfile").write_text("# fixture\n")
        self.git("add", "Tiltfile")
        self.commit("initial")
        tools = self.root / "bin"
        tools.mkdir()
        tilt = tools / "tilt"
        tilt.write_text(
            '#!/bin/sh\n'
            'printf "%s\\n" "$PWD" "$@" >> "$TILT_LOG"\n'
            'if [ "${TILT_DIRTY:-0}" = 1 ]; then touch generated; fi\n'
            'exit "${TILT_STATUS:-0}"\n'
        )
        tilt.chmod(0o755)
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith("REX_")
        }
        self.env.update(
            PATH=f"{tools}:{os.environ['PATH']}",
            TILT_LOG=str(self.root / "tilt.log"),
        )

    def git(self, *args, cwd=None):
        result = subprocess.run(
            ["git", *args], cwd=cwd or self.repo,
            text=True, capture_output=True, check=True,
        )
        return result.stdout.strip()

    def commit(self, message, cwd=None):
        self.git(
            "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "commit", "--allow-empty", "-qm", message, cwd=cwd,
        )

    def run_script(self, name, *args, cwd=None, **env):
        return subprocess.run(
            ["fish", "--no-config", str(SCRIPTS / f"worktree-{name}.fish"), *args],
            cwd=cwd or self.repo, env={**self.env, **env},
            text=True, capture_output=True,
        )

    def create(self, branch, cwd=None):
        result = self.run_script("create", branch, cwd=cwd)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        expected = self.root / ".worktrees" / self.repo.name / branch
        self.assertEqual(data["worktree"], str(expected))
        self.assertEqual(data["project"], self.repo.name)
        self.assertEqual(data["branch"], branch)
        self.assertTrue(expected.is_dir())
        return expected

    def test_create_existing_branch_and_from_linked_head(self):
        self.git("branch", "existing")
        first = self.create("existing")
        self.commit("linked HEAD", cwd=first)
        nested = self.create("feature/nested", cwd=first)
        self.assertEqual(
            self.git("rev-parse", "HEAD", cwd=nested),
            self.git("rev-parse", "HEAD", cwd=first),
        )

    def test_branch_name_is_passed_literally(self):
        worktree = self.create('topic/quoted-\'";$HOME')
        self.assertEqual(
            self.git("branch", "--show-current", cwd=worktree),
            'topic/quoted-\'";$HOME',
        )

    def test_create_rejects_invalid_names_and_conflicts(self):
        for branch in ["../escape", "/absolute", "-bad", "bad name", "@{-1}"]:
            with self.subTest(branch=branch):
                self.assertNotEqual(self.run_script("create", branch).returncode, 0)
        self.create("occupied")
        self.assertNotEqual(self.run_script("create", "occupied").returncode, 0)
        current = self.git("branch", "--show-current")
        self.assertNotEqual(self.run_script("create", current).returncode, 0)

    def test_main_checkout_and_dirty_worktree_are_protected(self):
        self.assertNotEqual(self.run_script("close").returncode, 0)
        worktree = self.create("dirty")
        for name in ["untracked", "Tiltfile"]:
            with self.subTest(file=name):
                path = worktree / name
                original = path.read_text() if path.exists() else None
                path.write_text("keep this\n")
                result = self.run_script("close", cwd=worktree)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(worktree.exists())
                self.assertFalse((self.root / "tilt.log").exists())
                if original is None:
                    path.unlink()
                else:
                    path.write_text(original)

    def test_prepare_then_remove_preserves_branch_and_runs_tilt_once(self):
        worktree = self.create("phased")
        prepared = self.run_script("close", "--prepare", str(worktree))
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        data = json.loads(prepared.stdout)
        self.assertEqual(data["main_repo"], str(self.repo))
        self.assertTrue(worktree.exists())
        removed = self.run_script("close", "--remove", data["worktree"])
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertFalse(worktree.exists())
        self.assertTrue(self.git("show-ref", "--verify", "refs/heads/phased"))
        self.assertEqual(
            (self.root / "tilt.log").read_text().splitlines(),
            [str(worktree), "down", "-f", str(worktree / "Tiltfile")],
        )

    def test_tilt_failure_and_generated_files_abort_cleanup(self):
        for branch, env in [
            ("tilt-failure", {"TILT_STATUS": "7"}),
            ("tilt-dirty", {"TILT_DIRTY": "1"}),
        ]:
            with self.subTest(branch=branch):
                worktree = self.create(branch)
                result = self.run_script("close", cwd=worktree, **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(worktree.exists())

    def test_remove_rechecks_changes_after_prepare(self):
        worktree = self.create("changed-after-prepare")
        prepared = self.run_script("close", "--prepare", str(worktree))
        self.assertEqual(prepared.returncode, 0, prepared.stderr)
        (worktree / "untracked").write_text("keep\n")
        self.assertNotEqual(
            self.run_script("close", "--remove", str(worktree)).returncode, 0,
        )
        self.assertTrue(worktree.exists())

    def test_standalone_close_runs_tilt(self):
        worktree = self.create("standalone-tilt")
        result = self.run_script("close", cwd=worktree)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(worktree.exists())
        self.assertTrue((self.root / "tilt.log").exists())
        self.assertTrue(self.git("show-ref", "--verify", "refs/heads/standalone-tilt"))

    def test_standalone_close_without_tiltfile(self):
        worktree = self.create("standalone")
        self.git("rm", "Tiltfile", cwd=worktree)
        self.commit("remove Tiltfile", cwd=worktree)
        subdir = worktree / "subdir"
        subdir.mkdir()
        result = self.run_script("close", cwd=subdir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(worktree.exists())
        self.assertFalse((self.root / "tilt.log").exists())
        self.assertTrue(self.git("show-ref", "--verify", "refs/heads/standalone"))


if __name__ == "__main__":
    unittest.main()
