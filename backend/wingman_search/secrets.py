"""Owner-only local secret handling. Errors never contain supplied values.

Only the dedicated, ignored backend/.env.brave file is supported. Production
must use its approved secret-manager integration rather than this local helper.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile


class SecretError(ValueError):
    pass


def default_secret_path(repo_root: Path) -> Path:
    return Path(repo_root).absolute() / "backend" / ".env.brave"


def validate_key(value: str) -> str:
    if (not isinstance(value, str) or not 12 <= len(value) <= 4096
            or not value.isascii()
            or any(c.isspace() or ord(c) < 33 or ord(c) == 127 for c in value)):
        raise SecretError("invalid_secret")
    return value


def validate_local_path(path: Path, *, require_file: bool = False) -> Path:
    """Reject symlinks, non-owned leaf paths and writable ancestor directories."""
    path = Path(path).absolute()
    if ".." in path.parts:
        raise SecretError("unsafe_path")
    uid = os.getuid()
    for item in reversed((path, *path.parents)):
        try:
            info = item.lstat()
        except FileNotFoundError:
            if item != path or require_file:
                raise SecretError("missing_path") from None
            continue
        if stat.S_ISLNK(info.st_mode):
            raise SecretError("symlink_path")
        if info.st_uid not in {0, uid} or (item == path and info.st_uid != uid):
            raise SecretError("non_owner_path")
        if item != path:
            if not stat.S_ISDIR(info.st_mode) or info.st_mode & 0o022:
                raise SecretError("unsafe_parent")
        elif not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
            raise SecretError("unsafe_file")
        elif info.st_nlink != 1:
            raise SecretError("linked_file")
    return path


def _check_target(path: Path, repo_root: Path, *, require_file: bool = False) -> Path:
    root = Path(repo_root).absolute()
    target = Path(path).absolute()
    if target != default_secret_path(root):
        raise SecretError("unsupported_secret_path")
    # Check before reading/writing: a tracked file remains unsafe even if ignored.
    relative = str(target.relative_to(root))
    try:
        tracked = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--error-unmatch", "--", relative],
            capture_output=True, check=False, timeout=5,
        )
        ignored = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "--quiet", "--", relative],
            capture_output=True, check=False, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        raise SecretError("git_check_failed") from None
    if tracked.returncode != 1 or ignored.returncode != 0:
        raise SecretError("secret_must_be_untracked_and_ignored")
    return validate_local_path(target, require_file=require_file)


def secret_status(path: Path, repo_root: Path) -> str:
    """Metadata-only status. Does not read, hash or validate the credential."""
    try:
        target = _check_target(path, repo_root)
        return "configured_unverified" if target.exists() else "unconfigured"
    except SecretError:
        return "unsafe_configuration"


def write_secret(path: Path, key: str, repo_root: Path) -> None:
    key = validate_key(key)
    target = _check_target(path, repo_root)
    fd, temporary = tempfile.mkstemp(prefix=".env.brave.", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write("BRAVE_API_KEY=" + json.dumps(key) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        _check_target(target, repo_root)
        os.replace(temporary, target)
        directory = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_secret(path: Path, repo_root: Path) -> str:
    target = _check_target(path, repo_root, require_file=True)
    fd = None
    try:
        fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW)
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or info.st_mode & 0o077 or info.st_nlink != 1 or info.st_size > 8192):
            raise SecretError("unsafe_file")
        with os.fdopen(fd, "r", encoding="utf-8") as stream:
            fd = None
            value = stream.read(8193)
        prefix = "BRAVE_API_KEY="
        if not value.startswith(prefix):
            raise SecretError("invalid_secret_configuration")
        return validate_key(json.loads(value[len(prefix):]))
    except (OSError, UnicodeError, json.JSONDecodeError, TypeError):
        raise SecretError("invalid_secret_configuration") from None
    finally:
        if fd is not None:
            os.close(fd)
