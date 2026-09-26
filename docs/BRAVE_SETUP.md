# Brave setup — fixtures first

Run all commands from the Wingman repository root. The owner already has a
Brave account. Do not create a replacement account or paste credentials into a
conversation. The existing chat-exposed key should be replaced within that
account before continued development/production.

## Hidden local key entry

In your own interactive Terminal:

```sh
python3 backend/setup_brave_secret.py
```

Enter the replacement key at the hidden prompt. No key argument is accepted.
The command writes only `backend/.env.brave` with mode 0600 after verifying
that it is ignored and untracked. It rejects symlinks, hard links, non-owner
files, unsafe ancestor directories and group/world file permissions. Atomic
replacement preserves file confidentiality; unrelated environment files are
never overwritten. It makes no network call and changes no budget. Metadata
status is `configured_unverified`, never proof of valid authentication.

Production must use an owner-approved Secret Manager reference and a runtime
identity with access only to the necessary secret. The local file loader is
not a production secret-manager implementation. A key must never enter an app
bundle, Flutter asset/dart-define, URL, command argument, log, screenshot or
public diagnostic response. The committed `backend/.env.example` contains the
variable name only. Key rotation never resets attempt accounting.

## Dependencies and offline checks

Use the existing backend environment, or create an isolated local environment:

```sh
python3 -m venv work/brave-venv
work/brave-venv/bin/python -m pip install -r backend/requirements.txt
PYTHONPATH=backend work/brave-venv/bin/python -m unittest backend.tests.test_brave_foundation backend.tests.test_brave_contracts -v
```

The foundation module itself uses only the standard library. Provider/contracts
also reuse the existing backend parsing dependency (`defusedxml`). Package
installation is local development setup, not permission to buy infrastructure.

## One bounded smoke allowance

After hidden entry, initialize the launcher-authorized allowance exactly once:

```sh
PYTHONPATH=backend work/brave-venv/bin/python backend/brave_smoke_test.py --status
PYTHONPATH=backend work/brave-venv/bin/python backend/brave_smoke_test.py --initialize
PYTHONPATH=backend work/brave-venv/bin/python backend/brave_smoke_test.py
```

`--status` reports metadata/accounting without network access or credential
content reads. `--initialize` creates the durable ledger and its permanent
initialization marker under the repository's common Git directory,
`wingman-operations/brave_budget.sqlite3` and `.initialized`. All worktrees share
that one allowance. It refuses existing state;
missing or corrupt established ledgers do not automatically initialize.
The final command uses the actual adapter and at most one Web and one News
attempt with count=1, strict filtering, synthetic input and no retry. It stops
on the first failure and never prints response bodies, headers, queries or keys.
Do not add the command to CI, app startup, hot reload or an automatic scheduler.

Two successful calls at the reviewed $5/1,000 list rate would be $0.01 before
credits/account adjustments. No account balance or invoice has been verified.
If the applicable rate is higher, stop and obtain approval first. This allowance
does not approve ongoing search, scheduled news, an additional account or the
previously proposed $25 development cap.

Preserve **both** `brave_budget.sqlite3` and `brave_budget.sqlite3.initialized`
across restart, key replacement, rollback and cache deletion. If either file is
missing/corrupt after initialization, restore the latest valid accounting state
or obtain a separately approved reconciled allowance. Never delete/recreate the
pair to try a failing key again. A partly run smoke cannot be rerun.

## Production dry run and rollback

Before a deployment proposal, identify a dedicated owner-approved project and
domain, actual pricing/rights, request-level global and endpoint ceilings,
transactional shared persistence, approved secret reference, minimal runtime
permissions and logging configuration. Exercise contention, quota exhaustion,
auth failure, timeouts and restore against that specific datastore in an approved
test environment. Configure HTTPS-only service ingress, consumer payload
redaction and no cache for query-bearing responses. Budget alerts complement
dispatch enforcement; they do not replace it.

No cloud resource, DNS/IAM change, subscription, recharge, production deployment
or advertiser charge is authorized by these commands. `SearchConfig` requires
explicit approved deployment/provider-spend references, a nonzero cap, approved
domain, secret-manager reference and shared GCS ledger configuration before its
production profile validates. `BudgetLedger` always rejects production SQLite.
The GCS adapter is implemented and fixture-tested; its production target and
measured operating costs remain unapproved/unverified. Advertiser billing is a
separate gate and need not be enabled for organic search.

Rollback closes live feature gates and restores the previous application build,
preserving budget ledgers/markers, advertiser finance records and user data.
Do not uninstall personal-device builds, erase app data or delete accounting to
make an old build start. Existing permitted ordinary browsing and local tools
must remain available when provider spending is stopped.
