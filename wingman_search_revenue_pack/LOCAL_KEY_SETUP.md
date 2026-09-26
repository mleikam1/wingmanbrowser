# Local Brave activation — owner and Codex
The owner already has an API credential. This package intentionally contains no credential, credential fingerprint, embedded environment file or live search content. The chat credential was not installed on the owner's computer by preparing this package.

## Owner action
Use a replacement key from the existing Brave account for continued development and production because the previous value appeared in a conversation. There is no need to create another account. Do not paste a key into another chat. Enter it once into the hidden local prompt created by Codex. Brave's own [key security instructions](https://api-dashboard.search.brave.com/documentation/quickstart) say not to expose tokens in client code or version control.

## Codex implementation
Prefer an existing repository-consistent secret setup if one exists. Otherwise create `backend/setup_brave_secret.py`, and document `python3 backend/setup_brave_secret.py`. The command must use a real local interactive terminal with hidden entry; if the Codex terminal cannot accept interactive input, show the owner that exact command for their Terminal. Continue fixture work while input is pending.

Use the established local secret convention when safe, such as ignored `backend/.env.brave`, readable only by the owner. Check the file is not tracked, update ignore rules before writing, reject symlinked/non-owner/unsafe paths, and use safe creation or replacement rather than following existing links. Do not overwrite unrelated environment files. No shell history, terminal arguments, diagnostic printouts or screenshots may contain the value. The runtime must reject malformed configuration without quoting it. Do not inspect chat histories, browser profiles or other projects for credentials.

Expose only the variable name `BRAVE_API_KEY` in committed examples. Production uses an owner-approved secret-manager reference with a replacement key; no client build should receive the value. Record a nonsecret status such as configured/unconfigured/needs-rotation, not a credential-derived analytics ID.

## Bounded local smoke test
Create `backend/brave_smoke_test.py` or an equivalent documented command using the actual provider adapter, not an independent bypass. It accepts no secret arguments and loads the local backend secret. Read and reserve the persistent smoke-test allowance before networking. With the owner-executed launcher allowance, send at most one synthetic Web Search request and one synthetic News Search request; count=1 and explicit strict filtering. No retries, pagination, article fetching, image downloading or result persistence. Stop on the first failure. Never auto-run it in continuous integration, app startup, hot reload or every Codex turn.

Print only endpoint kind, sanitized status class, HTTP status when received, and result-count/schema evidence. A 200 with zero items is successful authentication but not proof of useful-result quality. Distinguish invalid credentials, entitlement/credit problems, rate limits, transport errors and malformed responses according to the actual received evidence. Never echo response bodies, headers with secrets, user queries or exception URLs. Report estimated versus known provider charges correctly. All other tests use synthetic fixtures until a new budget is explicitly approved.

## Current evidence
`CONNECTIVITY_CHECK.json` records two connection attempts from the assistant's environment. Neither returned an API response; the News endpoint was not reached. This does not establish that the key is valid or invalid and does not establish the account balance. It is not evidence of a deployed backend. The local Codex test must supply the actual integration evidence.
