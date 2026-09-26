import argparse
from .gateway import SearchApplication, serve
from .provider import FixtureProvider

def main():
    p = argparse.ArgumentParser(description='Local Wingman gateway. Fixture mode makes zero Brave calls.')
    p.add_argument('command', choices=('serve', 'serve-fixtures'))
    p.add_argument('--port', type=int, default=8895)
    p.add_argument('--origin', action='append', default=[])
    p.add_argument('--ads-fixture-store', help='Explicit existing test-money campaign store; fixture command only')
    args = p.parse_args()
    if not 1024 <= args.port <= 65535:
        p.error('Use a local unprivileged port.')
    provider = FixtureProvider() if args.command == 'serve-fixtures' else None
    ads = None
    if args.ads_fixture_store:
        if args.command != 'serve-fixtures':
            p.error('Ad fixtures require serve-fixtures; live finance is a separate authorization.')
        from wingman_ads.service import open_fixture_service
        ads = open_fixture_service(args.ads_fixture_store)
    print('Wingman Search local gateway; ' + ('synthetic fixtures only.' if provider else 'live search disabled.'), flush=True)
    try:
        serve(SearchApplication(provider, ads=ads), port=args.port, origins=args.origin)
    finally:
        if ads:
            ads.close()

if __name__ == '__main__':
    main()
