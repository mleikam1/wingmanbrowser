"""Run locally in a terminal. The key is never a CLI argument or terminal output."""
import getpass
import json
import os
import sys
import tempfile
from pathlib import Path


def main():
    if not sys.stdin.isatty():
        raise SystemExit('Run this command in an interactive terminal for hidden key entry.')
    secret = getpass.getpass('Currents API key (hidden; replace any chat-exposed key): ')
    if (not 1 <= len(secret) <= 4096 or not secret.isascii()
            or any(c.isspace() or ord(c) < 33 or ord(c) == 127 for c in secret)):
        raise SystemExit('No secret saved: expected a nonempty API token without whitespace.')
    target = Path(__file__).resolve().parent / '.env.currents'
    fd, temp = tempfile.mkstemp(prefix='.env.currents.', dir=target.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write('CURRENTS_API_KEY=' + json.dumps(secret) + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    print('Saved backend/.env.currents with mode 0600. No network request was made.')
    print('Use the budgeted currents-setup command for the one-time connection check.')


if __name__ == '__main__':
    main()
