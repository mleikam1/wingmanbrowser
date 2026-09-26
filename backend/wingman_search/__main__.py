import argparse
from .gateway import SearchApplication, serve
from .provider import FixtureProvider

def main():
    p = argparse.ArgumentParser(description='Local Wingman gateway. Fixture mode makes zero Brave calls.')
    p.add_argument('command', choices=('serve', 'serve-fixtures'))
    p.add_argument('--port', type=int, default=8895)
    p.add_argument('--origin', action='append', default=[])
    args = p.parse_args()
    if not 1024 <= args.port <= 65535:
        p.error('Use a local unprivileged port.')
    provider = FixtureProvider() if args.command == 'serve-fixtures' else None
    print('Wingman Search local gateway; ' + ('synthetic fixtures only.' if provider else 'live search disabled.'), flush=True)
    serve(SearchApplication(provider), port=args.port, origins=args.origin)

if __name__ == '__main__':
    main()
