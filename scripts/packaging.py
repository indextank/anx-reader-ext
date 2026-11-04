"""Shared helpers for safe distribution packaging."""

import errno
import os
import re
import shutil
import tempfile
import zipfile
from pathlib import Path, PureWindowsPath


class PackagingError(RuntimeError):
    """Raised when a packaging operation cannot be completed safely."""


_SUPPORTED_PLATFORMS = frozenset({"android", "windows", "linux", "macos"})
_VERSION_PATTERN = re.compile(
    r"^[ \t]*version:[ \t]*(\d+\.\d+\.\d+)(?:\+\d+)?[ \t]*(?:#.*)?$",
    re.MULTILINE,
)


def read_version(root: Path) -> str:
    """Read the semantic version from pubspec.yaml without its build number."""
    try:
        contents = (Path(root) / "pubspec.yaml").read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise PackagingError("Unable to read pubspec.yaml") from error

    match = _VERSION_PATTERN.search(contents)
    if match is None:
        raise PackagingError("pubspec.yaml has no valid version")
    return match.group(1)


def platform_dist(root, platform) -> Path:
    """Return the distribution directory for a supported platform."""
    if platform not in _SUPPORTED_PLATFORMS:
        raise PackagingError(f"Unsupported packaging platform: {platform!r}")
    return Path(root) / "dist" / platform


def _validate_artifact_name(name):
    if not isinstance(name, str) or not name or name in {".", ".."}:
        raise PackagingError("Artifact name must be an ordinary file name")
    if (
        "/" in name
        or "\\" in name
        or "\0" in name
        or Path(name).is_absolute()
        or PureWindowsPath(name).drive
    ):
        raise PackagingError("Artifact name must not contain a path")


def copy_artifact(source, root, platform, name) -> Path:
    """Copy a non-empty artifact to its platform directory atomically."""
    _validate_artifact_name(name)
    source = Path(source)
    try:
        if not source.is_file():
            raise PackagingError(f"Artifact source is not a file: {source}")
        if source.stat().st_size == 0:
            raise PackagingError(f"Artifact source is empty: {source}")
    except OSError as error:
        raise PackagingError(f"Unable to inspect artifact source: {source}") from error

    destination = platform_dist(root, platform) / name
    temporary = None
    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{name}.", suffix=".tmp", dir=destination.parent
        )
        temporary = Path(temporary_name)
        with os.fdopen(descriptor, "wb"):
            pass
        shutil.copyfile(source, temporary)
        os.replace(temporary, destination)
    except OSError as error:
        if temporary is not None:
            try:
                temporary.unlink()
            except OSError:
                pass
        raise PackagingError(f"Unable to copy artifact to {destination}") from error
    return destination


def validate_zip(path, required_entries: list[str]):
    """Check every ZIP member's CRC and require the specified entries."""
    try:
        with zipfile.ZipFile(Path(path), "r") as archive:
            damaged_entry = archive.testzip()
            if damaged_entry is not None:
                raise PackagingError(f"ZIP entry failed its CRC check: {damaged_entry}")
            entries = set(archive.namelist())
            missing = [entry for entry in required_entries if entry not in entries]
            if missing:
                raise PackagingError(
                    "ZIP archive is missing required entries: " + ", ".join(missing)
                )
    except PackagingError:
        raise
    except (OSError, RuntimeError, NotImplementedError, zipfile.BadZipFile) as error:
        raise PackagingError(f"Unable to validate ZIP archive: {path}") from error


def _relative_to(path, parent):
    try:
        return path.relative_to(parent)
    except ValueError as error:
        raise PackagingError(f"Path is outside the allowed build directory: {path}") from error


def _is_directory_link(path):
    junction_check = getattr(path, "is_junction", None)
    return path.is_symlink() or (junction_check is not None and junction_check())


def _validate_cleanup_path(root, path):
    root = Path(root).resolve()
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = Path(os.path.abspath(candidate))
    build_root = root / "build"

    try:
        relative = _relative_to(candidate, build_root)
        if len(relative.parts) < 2 or relative.parts[0] not in _SUPPORTED_PLATFORMS:
            raise PackagingError(f"Path is not a registered platform temporary path: {path}")

        resolved_build = build_root.resolve(strict=False)
        _relative_to(candidate.resolve(strict=False), resolved_build)
        current = build_root
        if _is_directory_link(current):
            raise PackagingError(f"Build directory must not be a link: {current}")
        for part in relative.parts:
            current = current / part
            if _is_directory_link(current):
                raise PackagingError(f"Cleanup path must not contain links: {current}")
    except PackagingError:
        raise
    except (OSError, RuntimeError) as error:
        raise PackagingError(f"Unable to validate cleanup path: {path}") from error
    return candidate


def cleanup_paths(root, paths):
    """Delete only explicitly registered paths below build/<platform>/."""
    for path in paths:
        candidate = _validate_cleanup_path(root, path)
        try:
            if not candidate.exists():
                continue
            if candidate.is_dir():
                shutil.rmtree(candidate)
            else:
                candidate.unlink()
        except OSError as error:
            raise PackagingError(f"Unable to remove packaging path: {candidate}") from error


def _pid_is_alive(pid):
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        open_process = kernel32.OpenProcess
        open_process.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
        open_process.restype = wintypes.HANDLE
        get_exit_code = kernel32.GetExitCodeProcess
        get_exit_code.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
        get_exit_code.restype = wintypes.BOOL
        close_handle = kernel32.CloseHandle
        close_handle.argtypes = [wintypes.HANDLE]
        close_handle.restype = wintypes.BOOL

        handle = open_process(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5
        try:
            exit_code = wintypes.DWORD()
            if not get_exit_code(handle, ctypes.byref(exit_code)):
                return True
            return exit_code.value == 259
        finally:
            close_handle(handle)

    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError as error:
        if error.errno == errno.ESRCH:
            return False
        if error.errno == errno.EPERM:
            return True
        raise PackagingError(f"Unable to inspect build process {pid}") from error
    return True


def _validated_pid(current_pid):
    pid = os.getpid() if current_pid is None else current_pid
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        raise PackagingError("Build lock PID must be a positive integer")
    return pid


def _read_lock_pid(lock_path):
    try:
        contents = lock_path.read_text(encoding="ascii").strip()
    except FileNotFoundError:
        return None
    except OSError as error:
        raise PackagingError(f"Unable to read build lock: {lock_path}") from error
    try:
        pid = int(contents)
    except ValueError as error:
        raise PackagingError(f"Build lock contains an invalid PID: {lock_path}") from error
    if pid <= 0:
        raise PackagingError(f"Build lock contains an invalid PID: {lock_path}")
    return pid


def ensure_no_active_build(root, current_pid=None):
    """Create build/.packaging.lock unless another live process owns it."""
    pid = _validated_pid(current_pid)
    lock_path = Path(root) / "build" / ".packaging.lock"
    try:
        lock_path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise PackagingError(f"Unable to create build directory: {lock_path.parent}") from error

    locked_pid = _read_lock_pid(lock_path)
    if locked_pid is not None and locked_pid != pid and _pid_is_alive(locked_pid):
        raise PackagingError(f"Another active build holds the lock with PID {locked_pid}")
    try:
        lock_path.write_text(str(pid), encoding="ascii")
    except OSError as error:
        raise PackagingError(f"Unable to write build lock: {lock_path}") from error


def release_build_lock(root, current_pid=None):
    """Release the lock only when it belongs to this build process."""
    pid = _validated_pid(current_pid)
    lock_path = Path(root) / "build" / ".packaging.lock"
    locked_pid = _read_lock_pid(lock_path)
    if locked_pid is None or locked_pid != pid:
        return
    try:
        lock_path.unlink()
    except FileNotFoundError:
        pass
    except OSError as error:
        raise PackagingError(f"Unable to release build lock: {lock_path}") from error
