import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import packaging


LOCK_COMPETITOR_CODE = r"""
import os
import sys
import time
from pathlib import Path

code_root = Path(sys.argv[1])
project_root = Path(sys.argv[2])
gate = Path(sys.argv[3])
ready_directory = Path(sys.argv[4])
events = Path(sys.argv[5])
sys.path.insert(0, str(code_root))
from scripts import packaging

(ready_directory / f"{os.getpid()}.ready").write_text("ready", encoding="ascii")
while not gate.exists():
    time.sleep(0.01)
try:
    token = packaging.ensure_no_active_build(project_root)
except packaging.PackagingError:
    sys.exit(23)
try:
    with events.open("a", encoding="ascii") as stream:
        stream.write(f"enter {os.getpid()}\n")
    time.sleep(0.75)
    with events.open("a", encoding="ascii") as stream:
        stream.write(f"exit {os.getpid()}\n")
finally:
    packaging.release_build_lock(project_root, owner_token=token)
"""

STALE_LOCK_OWNER_CODE = r"""
import os
import sys
from pathlib import Path

code_root = Path(sys.argv[1])
project_root = Path(sys.argv[2])
sys.path.insert(0, str(code_root))
from scripts import packaging

token = packaging.ensure_no_active_build(project_root)
print(token, flush=True)
os._exit(0)
"""


class PackagingTestCase(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        self.root = Path(self.temporary_directory.name)

    def write_pubspec(self, contents):
        (self.root / "pubspec.yaml").write_text(contents, encoding="utf-8")

    def make_source(self, contents=b"artifact"):
        source = self.root / "artifact.bin"
        source.write_bytes(contents)
        return source

    def make_build_path(self, platform, name):
        path = self.root / "build" / platform / name
        path.mkdir(parents=True)
        return path

    def make_directory_link(self, link, target):
        try:
            link.symlink_to(target, target_is_directory=True)
        except (NotImplementedError, OSError) as error:
            if os.name != "nt":
                self.skipTest(f"directory links unavailable: {error}")
            subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(link), str(target)],
                check=True,
                capture_output=True,
            )


class VersionAndPlatformTests(PackagingTestCase):
    def test_read_version_removes_build_number(self):
        self.write_pubspec("name: example\nversion: 1.2.3+42\n")

        self.assertEqual(packaging.read_version(self.root), "1.2.3")

    def test_read_version_rejects_missing_pubspec(self):
        with self.assertRaises(packaging.PackagingError):
            packaging.read_version(self.root)

    def test_read_version_rejects_missing_or_invalid_version(self):
        invalid_contents = (
            "name: example\n",
            "name: example\nversion: 1.2\n",
            "name: example\nversion: 1.2.3.4+42\n",
        )
        for contents in invalid_contents:
            with self.subTest(contents=contents):
                self.write_pubspec(contents)
                with self.assertRaises(packaging.PackagingError):
                    packaging.read_version(self.root)

    def test_platform_dist_returns_supported_platform_directories(self):
        for platform in ("android", "windows", "linux", "macos"):
            with self.subTest(platform=platform):
                self.assertEqual(
                    packaging.platform_dist(self.root, platform),
                    self.root / "dist" / platform,
                )

    def test_platform_dist_rejects_unsupported_platform(self):
        for platform in ("ios", "../windows", ""):
            with self.subTest(platform=platform):
                with self.assertRaises(packaging.PackagingError):
                    packaging.platform_dist(self.root, platform)


class CopyArtifactTests(PackagingTestCase):
    def test_copy_artifact_copies_file(self):
        source = self.make_source()

        destination = packaging.copy_artifact(
            source, self.root, "windows", "example.zip"
        )

        self.assertEqual(destination, self.root / "dist" / "windows" / "example.zip")
        self.assertEqual(destination.read_bytes(), b"artifact")

    def test_copy_artifact_replaces_via_temporary_file_in_destination(self):
        source = self.make_source(b"new")
        expected = self.root / "dist" / "windows" / "example.zip"
        expected.parent.mkdir(parents=True)
        expected.write_bytes(b"old")

        with mock.patch("scripts.packaging.os.replace", wraps=os.replace) as replace:
            destination = packaging.copy_artifact(
                source, self.root, "windows", "example.zip"
            )

        replace.assert_called_once()
        temporary, target = replace.call_args.args
        self.assertEqual(Path(temporary).parent, expected.parent)
        self.assertNotEqual(Path(temporary), expected)
        self.assertEqual(Path(target), expected)
        self.assertEqual(destination.read_bytes(), b"new")
        self.assertEqual(list(expected.parent.iterdir()), [expected])

    def test_copy_artifact_rejects_empty_source(self):
        source = self.make_source(b"")

        with self.assertRaises(packaging.PackagingError):
            packaging.copy_artifact(source, self.root, "windows", "example.zip")

    def test_copy_artifact_rejects_missing_source(self):
        with self.assertRaises(packaging.PackagingError):
            packaging.copy_artifact(
                self.root / "missing.zip", self.root, "windows", "example.zip"
            )

    def test_copy_artifact_rejects_non_file_names(self):
        source = self.make_source()
        invalid_names = (
            "../example.zip",
            "/tmp/example.zip",
            r"C:\example.zip",
            "nested/example.zip",
            r"nested\example.zip",
            "..",
            "",
        )
        for name in invalid_names:
            with self.subTest(name=name):
                with self.assertRaises(packaging.PackagingError):
                    packaging.copy_artifact(source, self.root, "windows", name)

    def test_copy_artifact_rejects_linked_dist_directory(self):
        source = self.make_source()
        target_directory = tempfile.TemporaryDirectory()
        self.addCleanup(target_directory.cleanup)
        target = Path(target_directory.name)
        self.make_directory_link(self.root / "dist", target)

        with self.assertRaises(packaging.PackagingError):
            packaging.copy_artifact(source, self.root, "windows", "example.zip")

        self.assertFalse((target / "windows" / "example.zip").exists())

    def test_copy_artifact_rejects_linked_platform_directory(self):
        source = self.make_source()
        target_directory = tempfile.TemporaryDirectory()
        self.addCleanup(target_directory.cleanup)
        target = Path(target_directory.name)
        (self.root / "dist").mkdir()
        self.make_directory_link(self.root / "dist" / "windows", target)

        with self.assertRaises(packaging.PackagingError):
            packaging.copy_artifact(source, self.root, "windows", "example.zip")

        self.assertFalse((target / "example.zip").exists())

    @unittest.skipUnless(os.name == "posix", "POSIX executable mode test")
    def test_copy_artifact_preserves_appimage_executable_mode(self):
        source = self.make_source()
        source.chmod(0o755)

        destination = packaging.copy_artifact(
            source, self.root, "linux", "Example.AppImage"
        )

        self.assertTrue(destination.stat().st_mode & stat.S_IXUSR)
        self.assertTrue(destination.stat().st_mode & stat.S_IXGRP)
        self.assertTrue(destination.stat().st_mode & stat.S_IXOTH)

    def test_copy_artifact_cleans_temporary_file_on_keyboard_interrupt(self):
        source = self.make_source()
        destination = self.root / "dist" / "windows" / "example.zip"

        with mock.patch(
            "scripts.packaging.shutil.copyfile", side_effect=KeyboardInterrupt
        ):
            with self.assertRaises(KeyboardInterrupt):
                packaging.copy_artifact(source, self.root, "windows", "example.zip")

        self.assertTrue(destination.parent.exists())
        self.assertEqual(list(destination.parent.iterdir()), [])


class ValidateZipTests(PackagingTestCase):
    def make_zip(self):
        path = self.root / "example.zip"
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
            archive.writestr("app/bin/example", b"executable")
            archive.writestr("app/README.txt", b"readme")
        return path

    def test_validate_zip_accepts_complete_archive(self):
        path = self.make_zip()

        packaging.validate_zip(path, ["app/bin/example", "app/README.txt"])

    def test_validate_zip_accepts_real_windows_layout_with_windows_separators(self):
        path = self.root / "windows.zip"
        entries = {
            "Release/anx_reader.exe": b"executable",
            "Release/flutter_windows.dll": b"flutter",
            "Release/data/app.so": b"library",
            "Release/data/flutter_assets/AssetManifest.json": b"{}",
        }
        with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
            for name, contents in entries.items():
                archive.writestr(name, contents)

        packaging.validate_zip(
            path,
            [
                r"Release\anx_reader.exe",
                r"Release\flutter_windows.dll",
                r"Release\data\app.so",
                r"Release\data\flutter_assets\AssetManifest.json",
            ],
        )

    def test_validate_zip_rejects_missing_required_entry(self):
        path = self.make_zip()

        with self.assertRaises(packaging.PackagingError):
            packaging.validate_zip(path, ["app/bin/missing"])

    def test_validate_zip_rejects_crc_damage(self):
        path = self.make_zip()
        contents = bytearray(path.read_bytes())
        payload_offset = contents.index(b"executable")
        contents[payload_offset] ^= 0xFF
        path.write_bytes(contents)

        with self.assertRaises(packaging.PackagingError):
            packaging.validate_zip(path, ["app/bin/example"])

    def test_validate_zip_rejects_missing_archive(self):
        with self.assertRaises(packaging.PackagingError):
            packaging.validate_zip(self.root / "missing.zip", [])


class CleanupPathsTests(PackagingTestCase):
    def test_cleanup_deletes_only_registered_temporary_paths(self):
        temporary = self.make_build_path("windows", "packaging-tmp")
        (temporary / "artifact").write_bytes(b"artifact")
        cmake_cache = self.make_build_path("windows", "CMakeFiles") / "cache.txt"
        cmake_cache.write_text("keep", encoding="utf-8")
        gradle_cache = self.make_build_path("android", ".gradle") / "cache.txt"
        gradle_cache.write_text("keep", encoding="utf-8")

        packaging.cleanup_paths(self.root, [temporary])

        self.assertFalse(temporary.exists())
        self.assertEqual(cmake_cache.read_text(encoding="utf-8"), "keep")
        self.assertEqual(gradle_cache.read_text(encoding="utf-8"), "keep")

    def test_cleanup_rejects_unsafe_roots_and_outside_paths(self):
        outside = self.root.parent / (self.root.name + "-outside")
        unsafe_paths = (
            self.root,
            self.root / "dist",
            outside,
            self.root / "build",
            self.root / "build" / "windows",
        )
        for path in unsafe_paths:
            with self.subTest(path=path):
                with self.assertRaises(packaging.PackagingError):
                    packaging.cleanup_paths(self.root, [path])

    def test_cleanup_rejects_caches_and_build_outputs(self):
        platform_roots = (
            self.make_build_path("windows", "compiler-root"),
            self.make_build_path("windows", "packaging-tmp"),
        )
        for platform_root in platform_roots:
            for name in (".gradle", "CMakeFiles", "x64", "runner", "bundle"):
                with self.subTest(parent=platform_root, name=name):
                    protected_directory = platform_root / name
                    protected_directory.mkdir()
                    protected = protected_directory / "keep.txt"
                    protected.write_text("keep", encoding="utf-8")

                    with self.assertRaises(packaging.PackagingError):
                        packaging.cleanup_paths(self.root, [protected_directory])
                    self.assertTrue(protected.exists())

    def test_cleanup_validates_every_path_before_deleting(self):
        temporary = self.make_build_path("windows", "packaging-tmp/work")
        artifact = temporary / "artifact"
        artifact.write_bytes(b"artifact")
        cache = self.make_build_path("windows", ".gradle")
        protected = cache / "keep.txt"
        protected.write_text("keep", encoding="utf-8")

        with self.assertRaises(packaging.PackagingError):
            packaging.cleanup_paths(self.root, [temporary, cache])

        self.assertTrue(artifact.exists())
        self.assertTrue(protected.exists())

    def test_cleanup_rejects_directory_link(self):
        target_directory = tempfile.TemporaryDirectory()
        self.addCleanup(target_directory.cleanup)
        target = Path(target_directory.name)
        protected = target / "keep.txt"
        protected.write_text("keep", encoding="utf-8")
        staging = self.make_build_path("windows", "packaging-tmp")
        link = staging / "linked-tmp"
        self.make_directory_link(link, target)

        with self.assertRaises(packaging.PackagingError):
            packaging.cleanup_paths(self.root, [link])
        self.assertEqual(protected.read_text(encoding="utf-8"), "keep")

    def test_cleanup_skips_nonexistent_registered_path(self):
        packaging.cleanup_paths(
            self.root,
            [self.root / "build" / "linux" / "packaging-tmp" / "missing-tmp"],
        )

    def test_cleanup_deletes_registered_file(self):
        directory = self.make_build_path("macos", "packaging-tmp")
        artifact = directory / "artifact.zip"
        artifact.write_bytes(b"artifact")

        packaging.cleanup_paths(self.root, [artifact])

        self.assertFalse(artifact.exists())
        self.assertTrue(directory.exists())

    def test_cleanup_deletes_registered_directory(self):
        directory = self.make_build_path("android", "packaging-tmp")
        (directory / "nested").mkdir()
        (directory / "nested" / "artifact").write_bytes(b"artifact")

        packaging.cleanup_paths(self.root, [directory])

        self.assertFalse(directory.exists())

    def test_cleanup_wraps_deletion_failure_and_stops(self):
        first = self.make_build_path("windows", "packaging-tmp/first")
        second = self.make_build_path("windows", "packaging-tmp/second")

        with mock.patch(
            "scripts.packaging.shutil.rmtree", side_effect=OSError("denied")
        ) as remove_directory:
            with self.assertRaises(packaging.PackagingError):
                packaging.cleanup_paths(self.root, [first, second])

        remove_directory.assert_called_once()
        self.assertTrue(second.exists())


class BuildLockTests(PackagingTestCase):
    @property
    def lock_path(self):
        return self.root / "build" / ".packaging.lock"

    def test_ensure_no_active_build_returns_unique_owner_token(self):
        token = packaging.ensure_no_active_build(self.root)
        self.addCleanup(
            packaging.release_build_lock, self.root, owner_token=token
        )

        self.assertIsInstance(token, str)
        self.assertGreaterEqual(len(token), 16)

    def test_ensure_no_active_build_is_reentrant_for_current_pid(self):
        first = packaging.ensure_no_active_build(self.root, current_pid=os.getpid())
        self.addCleanup(
            packaging.release_build_lock, self.root, owner_token=first
        )

        second = packaging.ensure_no_active_build(
            self.root, current_pid=os.getpid()
        )

        self.assertEqual(second, first)

    def test_ensure_no_active_build_replaces_stale_metadata(self):
        (self.root / "build").mkdir()
        self.lock_path.write_text(
            json.dumps({"pid": 2**31 - 1, "token": "stale"}), encoding="ascii"
        )

        token = packaging.ensure_no_active_build(self.root, current_pid=os.getpid())
        self.addCleanup(
            packaging.release_build_lock, self.root, owner_token=token
        )

        self.assertNotEqual(token, "stale")
        self.assertIsInstance(token, str)

    def test_release_build_lock_requires_matching_owner_token(self):
        token = packaging.ensure_no_active_build(self.root)

        try:
            with self.assertRaises(packaging.PackagingError):
                packaging.release_build_lock(self.root, owner_token="wrong-token")
            with self.assertRaises(packaging.PackagingError):
                packaging.release_build_lock(self.root)
        finally:
            packaging.release_build_lock(self.root, owner_token=token)

    def test_release_build_lock_releases_owned_lock(self):
        token = packaging.ensure_no_active_build(self.root, current_pid=os.getpid())

        packaging.release_build_lock(self.root, owner_token=token)
        second = packaging.ensure_no_active_build(self.root, current_pid=os.getpid())
        self.addCleanup(
            packaging.release_build_lock, self.root, owner_token=second
        )

        self.assertNotEqual(second, token)

    def test_build_lock_allows_only_one_process_during_contention(self):
        gate = self.root / "gate"
        ready_directory = self.root / "ready"
        ready_directory.mkdir()
        events = self.root / "events.log"
        processes = [
            subprocess.Popen(
                [
                    sys.executable,
                    "-I",
                    "-B",
                    "-c",
                    LOCK_COMPETITOR_CODE,
                    str(ROOT),
                    str(self.root),
                    str(gate),
                    str(ready_directory),
                    str(events),
                ],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            for _ in range(2)
        ]

        def stop_processes():
            for process in processes:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)

        self.addCleanup(stop_processes)
        deadline = time.monotonic() + 10
        while len(list(ready_directory.glob("*.ready"))) < len(processes):
            if time.monotonic() >= deadline:
                self.fail("lock competitors did not become ready")
            time.sleep(0.02)
        gate.write_text("go", encoding="ascii")
        results = [process.communicate(timeout=15) for process in processes]

        for process, (_, stderr) in zip(processes, results):
            self.assertIn(process.returncode, (0, 23), stderr)
        self.assertTrue(events.exists())
        active = 0
        entered = 0
        for line in events.read_text(encoding="ascii").splitlines():
            event, _ = line.split()
            if event == "enter":
                active += 1
                entered += 1
                self.assertEqual(active, 1, "two processes held the lock together")
            else:
                active -= 1
                self.assertEqual(active, 0)
        self.assertGreaterEqual(entered, 1)
        self.assertEqual(active, 0)

    def test_build_lock_recovers_after_owner_process_exits(self):
        owner = subprocess.Popen(
            [
                sys.executable,
                "-I",
                "-B",
                "-c",
                STALE_LOCK_OWNER_CODE,
                str(ROOT),
                str(self.root),
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        stdout, stderr = owner.communicate(timeout=15)
        self.assertEqual(owner.returncode, 0, stderr)
        self.assertNotEqual(stdout.strip(), "None")
        metadata = json.loads(self.lock_path.read_text(encoding="ascii"))
        self.assertEqual(metadata["pid"], owner.pid)
        self.assertEqual(metadata["token"], stdout.strip())

        token = packaging.ensure_no_active_build(self.root)
        self.addCleanup(packaging.release_build_lock, self.root, owner_token=token)

        self.assertIsInstance(token, str)
        self.assertNotEqual(token, stdout.strip())

    def test_run_with_build_lock_holds_lock_for_entire_subprocess(self):
        probe_code = r"""
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1])
from scripts import packaging
try:
    token = packaging.ensure_no_active_build(Path(sys.argv[2]))
except packaging.PackagingError:
    sys.exit(0)
packaging.release_build_lock(Path(sys.argv[2]), owner_token=token)
sys.exit(9)
"""

        returncode = packaging.run_with_build_lock(
            self.root,
            [
                sys.executable,
                "-I",
                "-B",
                "-c",
                probe_code,
                str(ROOT),
                str(self.root),
            ],
        )

        self.assertEqual(returncode, 0)
        token = packaging.ensure_no_active_build(self.root)
        self.addCleanup(packaging.release_build_lock, self.root, owner_token=token)

    def test_lock_cli_propagates_build_exit_code_and_releases(self):
        completed = subprocess.run(
            [
                sys.executable,
                "-I",
                "-B",
                str(ROOT / "scripts" / "packaging.py"),
                str(self.root),
                sys.executable,
                "-I",
                "-B",
                "-c",
                "import sys; sys.exit(7)",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=15,
        )

        self.assertEqual(completed.returncode, 7, completed.stderr)
        token = packaging.ensure_no_active_build(self.root)
        self.addCleanup(packaging.release_build_lock, self.root, owner_token=token)


if __name__ == "__main__":
    unittest.main()
