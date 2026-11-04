import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts import packaging


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
        temporary = self.make_build_path("windows", "package-tmp")
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

    def test_cleanup_rejects_directory_link(self):
        target_directory = tempfile.TemporaryDirectory()
        self.addCleanup(target_directory.cleanup)
        target = Path(target_directory.name)
        protected = target / "keep.txt"
        protected.write_text("keep", encoding="utf-8")
        build = self.make_build_path("windows", "package-tmp")
        link = build.parent / "linked-tmp"
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

        with self.assertRaises(packaging.PackagingError):
            packaging.cleanup_paths(self.root, [link])
        self.assertEqual(protected.read_text(encoding="utf-8"), "keep")

    def test_cleanup_skips_nonexistent_registered_path(self):
        packaging.cleanup_paths(
            self.root, [self.root / "build" / "linux" / "missing-tmp"]
        )

    def test_cleanup_deletes_registered_file(self):
        directory = self.make_build_path("macos", "package-tmp")
        artifact = directory / "artifact.zip"
        artifact.write_bytes(b"artifact")

        packaging.cleanup_paths(self.root, [artifact])

        self.assertFalse(artifact.exists())
        self.assertTrue(directory.exists())

    def test_cleanup_deletes_registered_directory(self):
        directory = self.make_build_path("android", "package-tmp")
        (directory / "nested").mkdir()
        (directory / "nested" / "artifact").write_bytes(b"artifact")

        packaging.cleanup_paths(self.root, [directory])

        self.assertFalse(directory.exists())

    def test_cleanup_wraps_deletion_failure_and_stops(self):
        first = self.make_build_path("windows", "first-tmp")
        second = self.make_build_path("windows", "second-tmp")

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

    def test_ensure_no_active_build_writes_current_pid(self):
        packaging.ensure_no_active_build(self.root)

        self.assertEqual(self.lock_path.read_text(encoding="ascii"), str(os.getpid()))

    def test_ensure_no_active_build_allows_current_pid(self):
        (self.root / "build").mkdir()
        self.lock_path.write_text(str(os.getpid()), encoding="ascii")

        packaging.ensure_no_active_build(self.root, current_pid=os.getpid())

        self.assertEqual(self.lock_path.read_text(encoding="ascii"), str(os.getpid()))

    def test_ensure_no_active_build_replaces_nonexistent_pid(self):
        (self.root / "build").mkdir()
        self.lock_path.write_text(str(2**31 - 1), encoding="ascii")

        packaging.ensure_no_active_build(self.root, current_pid=os.getpid())

        self.assertEqual(self.lock_path.read_text(encoding="ascii"), str(os.getpid()))

    def test_ensure_no_active_build_rejects_other_live_pid(self):
        (self.root / "build").mkdir()
        self.lock_path.write_text(str(os.getpid()), encoding="ascii")

        with self.assertRaises(packaging.PackagingError):
            packaging.ensure_no_active_build(self.root, current_pid=os.getpid() + 1)

        self.assertEqual(self.lock_path.read_text(encoding="ascii"), str(os.getpid()))

    def test_release_build_lock_removes_owned_lock(self):
        packaging.ensure_no_active_build(self.root, current_pid=os.getpid())

        packaging.release_build_lock(self.root, current_pid=os.getpid())

        self.assertFalse(self.lock_path.exists())

    def test_release_build_lock_keeps_other_process_lock(self):
        (self.root / "build").mkdir()
        self.lock_path.write_text(str(os.getpid()), encoding="ascii")

        packaging.release_build_lock(self.root, current_pid=os.getpid() + 1)

        self.assertTrue(self.lock_path.exists())
        self.assertEqual(self.lock_path.read_text(encoding="ascii"), str(os.getpid()))


if __name__ == "__main__":
    unittest.main()
