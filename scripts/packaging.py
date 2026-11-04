"""Shared helpers for safe distribution packaging.

BAT, PowerShell, and Bash callers can hold the build lock for a complete build
from the project root with:
    python -I scripts/packaging.py . <build-command> [argument ...]
The child exit code is propagated and the lock is released in all cases.
"""

import json
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PureWindowsPath


class PackagingError(RuntimeError):
    """Raised when a packaging operation cannot be completed safely."""


_SUPPORTED_PLATFORMS = frozenset({"android", "windows", "linux", "macos"})
_PACKAGING_TEMP_DIRECTORY = "packaging-tmp"
_PROTECTED_BUILD_DIRECTORIES = frozenset(
    {".gradle", "cmakefiles", "x64", "runner", "bundle"}
)
_VERSION_PATTERN = re.compile(
    r"^[ \t]*version:[ \t]*(\d+\.\d+\.\d+)(?:\+\d+)?[ \t]*(?:#.*)?$",
    re.MULTILINE,
)
_HELD_LOCKS = {}


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


def _relative_to(path, parent):
    try:
        return path.relative_to(parent)
    except ValueError as error:
        raise PackagingError(f"Path is outside its allowed parent: {path}") from error


def _is_directory_link(path):
    junction_check = getattr(path, "is_junction", None)
    return path.is_symlink() or (junction_check is not None and junction_check())


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


def _validated_destination(root, platform, name):
    root_path = Path(root)
    destination = platform_dist(root_path, platform) / name
    resolved_root = root_path.resolve()
    dist_root = root_path / "dist"
    platform_root = dist_root / platform

    try:
        for directory in (dist_root, platform_root):
            if _is_directory_link(directory):
                raise PackagingError(f"Distribution directory must not be a link: {directory}")
        resolved_dist = dist_root.resolve(strict=False)
        _relative_to(resolved_dist, resolved_root)
        resolved_destination = destination.resolve(strict=False)
        relative = _relative_to(resolved_destination, resolved_dist)
        if relative.parts != (platform, name):
            raise PackagingError(f"Artifact destination escapes its platform directory: {destination}")
    except PackagingError:
        raise
    except (OSError, RuntimeError) as error:
        raise PackagingError(f"Unable to validate artifact destination: {destination}") from error
    return destination


def copy_artifact(source, root, platform, name) -> Path:
    """Copy a non-empty artifact atomically, retaining its permission mode."""
    _validate_artifact_name(name)
    source = Path(source)
    try:
        if not source.is_file():
            raise PackagingError(f"Artifact source is not a file: {source}")
        if source.stat().st_size == 0:
            raise PackagingError(f"Artifact source is empty: {source}")
    except OSError as error:
        raise PackagingError(f"Unable to inspect artifact source: {source}") from error

    destination = _validated_destination(root, platform, name)
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
        shutil.copystat(source, temporary)
        os.replace(temporary, destination)
    except OSError as error:
        raise PackagingError(f"Unable to copy artifact to {destination}") from error
    finally:
        if temporary is not None:
            try:
                temporary.unlink()
            except OSError:
                pass
    return destination


def validate_zip(path, required_entries: list[str]):
    """Check CRCs and exact archive paths; Windows separators are normalized."""
    try:
        with zipfile.ZipFile(Path(path), "r") as archive:
            damaged_entry = archive.testzip()
            if damaged_entry is not None:
                raise PackagingError(f"ZIP entry failed its CRC check: {damaged_entry}")
            entries = set(archive.namelist())
            missing = [
                entry
                for entry in required_entries
                if entry.replace("\\", "/") not in entries
            ]
            if missing:
                raise PackagingError(
                    "ZIP archive is missing required entries: " + ", ".join(missing)
                )
    except PackagingError:
        raise
    except (OSError, RuntimeError, NotImplementedError, zipfile.BadZipFile) as error:
        raise PackagingError(f"Unable to validate ZIP archive: {path}") from error


def _validate_cleanup_path(root, path):
    root = Path(root).resolve()
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = root / candidate
    candidate = Path(os.path.abspath(candidate))
    build_root = root / "build"

    try:
        relative = _relative_to(candidate, build_root)
        if (
            len(relative.parts) < 2
            or relative.parts[0] not in _SUPPORTED_PLATFORMS
            or relative.parts[1] != _PACKAGING_TEMP_DIRECTORY
        ):
            raise PackagingError(
                f"Path is outside the platform packaging staging directory: {path}"
            )
        if any(
            part.casefold() in _PROTECTED_BUILD_DIRECTORIES
            for part in relative.parts[1:]
        ):
            raise PackagingError(f"Refusing to remove build cache or output: {path}")

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
    """Delete registered paths below build/<platform>/packaging-tmp/ only."""
    candidates = [_validate_cleanup_path(root, path) for path in paths]
    for candidate in candidates:
        try:
            if not candidate.exists():
                continue
            if candidate.is_dir():
                shutil.rmtree(candidate)
            else:
                candidate.unlink()
        except OSError as error:
            raise PackagingError(f"Unable to remove packaging path: {candidate}") from error


def _validated_pid(current_pid):
    pid = os.getpid() if current_pid is None else current_pid
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        raise PackagingError("Build lock PID must be a positive integer")
    return pid


def _lock_key(lock_path):
    return os.path.normcase(str(Path(os.path.abspath(lock_path))))


def _validate_lock_paths(root, lock_path):
    root = Path(root).resolve()
    build_root = root / "build"
    if _is_directory_link(build_root):
        raise PackagingError(f"Build directory must not be a link: {build_root}")
    if lock_path.is_symlink():
        raise PackagingError(f"Build lock must not be a symbolic link: {lock_path}")
    _relative_to(build_root.resolve(), root)
    resolved_lock = lock_path.resolve(strict=False)
    _relative_to(resolved_lock, build_root)
    if resolved_lock != lock_path:
        raise PackagingError(f"Build lock must resolve directly inside build: {lock_path}")


def _acquire_file_lock(root, lock_path):
    stream = None
    descriptor = None
    try:
        _validate_lock_paths(root, lock_path)
        flags = os.O_RDWR | os.O_CREAT
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        descriptor = os.open(lock_path, flags, 0o666)
        file_stat = os.fstat(descriptor)
        if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_nlink != 1:
            raise PackagingError(
                f"Build lock must be a regular file with one link: {lock_path}"
            )
        stream = os.fdopen(descriptor, "r+b")
        stream.seek(0)
        if os.name == "nt":
            import msvcrt

            msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl

            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        _validate_lock_paths(root, lock_path)
        return stream
    except (OSError, PackagingError) as error:
        if stream is not None:
            try:
                _unlock_file(stream)
            except OSError:
                pass
            stream.close()
        elif descriptor is not None:
            os.close(descriptor)
        if isinstance(error, PackagingError):
            raise
        raise PackagingError(
            f"Build lock is active or unavailable: {lock_path}"
        ) from error


def _unlock_file(stream):
    stream.seek(0)
    if os.name == "nt":
        import msvcrt

        msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
    else:
        import fcntl

        fcntl.flock(stream.fileno(), fcntl.LOCK_UN)


def ensure_no_active_build(root, current_pid=None):
    """Acquire an OS build lock and return its unique owner token."""
    pid = _validated_pid(current_pid)
    lock_path = Path(root) / "build" / ".packaging.lock"
    try:
        lock_path.parent.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise PackagingError(f"Unable to create build directory: {lock_path.parent}") from error

    key = _lock_key(lock_path)
    held = _HELD_LOCKS.get(key)
    if held is not None:
        held_pid, token, _, depth = held
        if held_pid == pid:
            _HELD_LOCKS[key] = (pid, token, held[2], depth + 1)
            return token
        raise PackagingError(f"Another active build owner holds the lock: {lock_path}")

    stream = _acquire_file_lock(root, lock_path)
    token = secrets.token_hex(16)
    try:
        metadata = json.dumps({"pid": pid, "token": token}, sort_keys=True).encode("ascii")
        stream.seek(0)
        stream.truncate()
        stream.write(metadata)
        stream.flush()
        os.fsync(stream.fileno())
    except OSError as error:
        try:
            _unlock_file(stream)
        finally:
            stream.close()
        raise PackagingError(f"Unable to initialize build lock: {lock_path}") from error

    _HELD_LOCKS[key] = (pid, token, stream, 1)
    return token


def release_build_lock(root, current_pid=None, owner_token=None):
    """Release a held lock only when both its PID and owner token match."""
    pid = _validated_pid(current_pid)
    if not isinstance(owner_token, str) or not owner_token:
        raise PackagingError("Releasing the build lock requires its owner token")
    lock_path = Path(root) / "build" / ".packaging.lock"
    key = _lock_key(lock_path)
    held = _HELD_LOCKS.get(key)
    if (
        held is None
        or held[0] != pid
        or not secrets.compare_digest(held[1], owner_token)
    ):
        raise PackagingError("Build lock owner token does not match this process")

    _, _, stream, depth = held
    if depth > 1:
        _HELD_LOCKS[key] = (pid, owner_token, stream, depth - 1)
        return
    try:
        _validate_lock_paths(root, lock_path)
        file_stat = os.fstat(stream.fileno())
        if not stat.S_ISREG(file_stat.st_mode) or file_stat.st_nlink != 1:
            raise PackagingError(f"Build lock file is no longer safe: {lock_path}")
        stream.seek(0)
        try:
            metadata = json.loads(stream.read().decode("ascii"))
        except (UnicodeError, json.JSONDecodeError) as error:
            raise PackagingError("Build lock metadata is invalid") from error
        if metadata != {"pid": pid, "token": owner_token}:
            raise PackagingError("Build lock metadata no longer matches its owner")
        stream.seek(0)
        stream.truncate()
        stream.flush()
        os.fsync(stream.fileno())
    except OSError as error:
        raise PackagingError(f"Unable to release build lock: {lock_path}") from error
    finally:
        try:
            _unlock_file(stream)
        finally:
            stream.close()
            del _HELD_LOCKS[key]


def run_with_build_lock(root, command, current_pid=None):
    """Hold the build lock until a build subprocess exits, then release it."""
    if isinstance(command, (str, bytes)) or not command:
        raise PackagingError("A build command with at least one argument is required")
    token = ensure_no_active_build(root, current_pid=current_pid)
    try:
        return subprocess.run(command, check=False).returncode
    finally:
        release_build_lock(root, current_pid=current_pid, owner_token=token)


def main(argv=None):
    """Minimal locked-build wrapper for BAT, PowerShell, and Bash callers."""
    arguments = list(sys.argv[1:] if argv is None else argv)
    if len(arguments) < 2:
        print(
            "usage: python -I scripts/packaging.py ROOT BUILD_COMMAND [ARG ...]",
            file=sys.stderr,
        )
        return 2
    try:
        return run_with_build_lock(Path(arguments[0]), arguments[1:])
    except PackagingError as error:
        print(f"packaging: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
