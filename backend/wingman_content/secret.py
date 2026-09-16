"""Explicit backend-only local credential input; no secret values in diagnostics."""
import json
import os
import stat
from pathlib import Path


def load_currents_secret(path):
    """Environment takes precedence; reject unsafe local files without reading them."""
    existing = os.environ.get('CURRENTS_API_KEY')
    if existing:
        return existing
    target = Path(path)
    try:
        fd = os.open(target, os.O_RDONLY | os.O_NOFOLLOW)
    except FileNotFoundError:
        return None
    except OSError:
        raise ValueError('Currents secret file cannot be opened safely') from None
    with os.fdopen(fd, 'r') as stream:
        info = os.fstat(stream.fileno())
        if (not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077
                or info.st_uid != os.getuid() or info.st_size > 8192):
            raise ValueError('Currents secret file must be owned by this user with mode 0600')
        value = stream.read(8193)
    try:
        name, encoded = value.strip().split('=', 1)
        secret = json.loads(encoded)
        if (name != 'CURRENTS_API_KEY' or not isinstance(secret, str)
                or not 1 <= len(secret) <= 4096 or not secret.isascii()
                or any(c.isspace() or ord(c) < 33 or ord(c) == 127 for c in secret)):
            raise ValueError()
    except (ValueError, TypeError):
        raise ValueError('Invalid backend Currents secret file') from None
    return secret
