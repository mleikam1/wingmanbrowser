"""Hidden local entry only; no network I/O and no credential CLI arguments."""
import getpass
from pathlib import Path
import sys
import warnings

from wingman_search.secrets import SecretError, default_secret_path, write_secret


def main() -> int:
    if len(sys.argv) != 1:
        print("No arguments are accepted. Enter the key only at the hidden prompt.", file=sys.stderr)
        return 2
    if not sys.stdin.isatty() or not sys.stderr.isatty():
        print("Run python3 backend/setup_brave_secret.py in an interactive Terminal.", file=sys.stderr)
        return 2
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", getpass.GetPassWarning)
            key = getpass.getpass("Brave API key (hidden): ")
        root = Path(__file__).absolute().parent.parent
        write_secret(default_secret_path(root), key, root)
    except (SecretError, getpass.GetPassWarning, EOFError, KeyboardInterrupt):
        print("No secret saved: hidden input or secure file validation failed.", file=sys.stderr)
        return 1
    print("Configured ignored backend/.env.brave with owner-only permissions; not verified.")
    print("No network request was made and no spending allowance was changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
