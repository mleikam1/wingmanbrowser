"""Explicit local tools. No command enables provider access or moves money."""
import argparse
import getpass
import sys
import warnings
from pathlib import Path
from .common import AdsError
from .operator import create_server,set_password
from .service import initialize_fixture_store,open_fixture_service,open_approved_live_service
from .store import AdsStore

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['init-fixture','init-approved-live','set-password','serve'])
    parser.add_argument('--store',type=Path,required=True)
    parser.add_argument('--approval',type=Path)
    parser.add_argument('--origin')
    parser.add_argument('--port',type=int,default=8896)
    parser.add_argument('--finance-summary',type=Path,help='Owner-only verified aggregate search/cost summary JSON; no consumer records')
    args=parser.parse_args()
    try:
        if args.command=='init-fixture':
            service=initialize_fixture_store(args.store);service.close()
            print('Fresh isolated fixture store initialized. Commercial charges: zero.');return
        if args.command=='init-approved-live':
            if not args.approval: raise AdsError('explicit-owner-approval-file-required')
            AdsStore.initialize_approved_live(args.store,authorization_path=args.approval)
            print('Separate approved live store initialized with no advertisers, funds or delivery.');return
        store=AdsStore(args.store)
        if args.command=='set-password':
            if not sys.stdin.isatty() or not sys.stderr.isatty(): raise AdsError('hidden-interactive-terminal-required')
            with warnings.catch_warnings():
                warnings.simplefilter('error',getpass.GetPassWarning)
                try:
                    first=getpass.getpass('Operator password (16–256 characters; hidden): ')
                    second=getpass.getpass('Confirm password (hidden): ')
                except (getpass.GetPassWarning,EOFError,KeyboardInterrupt): raise AdsError('hidden-interactive-terminal-required') from None
            if first!=second: raise AdsError('passwords-differ')
            set_password(store,first)
            print('Password hash stored locally. Existing sessions are revoked on their next request.');return
        if not 1<=args.port<=65535: raise AdsError('invalid-port')
        service=open_fixture_service(args.store) if store.mode=='test' else open_approved_live_service(args.store)
        def summary():
            if args.finance_summary is None: return {'searchReport':None,'costs':None}
            from wingman_search.secrets import validate_local_path
            from wingman_search.contracts import decode_json
            try:
                path=validate_local_path(args.finance_summary,require_file=True)
                if path.stat().st_size>65536: raise ValueError()
                value=decode_json(path.read_bytes(),65536)
                if not isinstance(value,dict) or set(value)!={'searchReport','costs'}: raise ValueError()
                from .finance import dashboard_finance
                dashboard_finance(store.dashboard(),value['searchReport'],value['costs'])
                return value
            except Exception: raise AdsError('invalid-verified-finance-summary') from None
        summary()
        server=create_server(service,args.port,origin=args.origin,finance_summary=summary)
        print('Wingman operator ready at '+server.app.origin+'; paid pilot not open, no external payments are initiated.')
        try: server.serve_forever(poll_interval=.5)
        except KeyboardInterrupt: pass
        finally: server.server_close()
    except AdsError as error:
        parser.exit(2,'Wingman operator: '+error.code+'\n')

if __name__=='__main__': main()
