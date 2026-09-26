# Search cost controls

All money is integer USD micros: one dollar is 1,000,000 micros. The reviewed
Brave Search list rate is 5,000 micros per successful request ($5/1,000), before
credits or account-specific adjustments. Provider pricing/account eligibility
must be rechecked before approval; free credits never enlarge Wingman's caps.

`backend/wingman_search/budget.py` is a local SQLite implementation with full
synchronous transactions. `reserve()` uses `BEGIN IMMEDIATE`, validates durable
state, commits the reservation, and only then returns to the adapter for network
dispatch. A rollback or process error cannot refund a committed attempt.
Networking must never happen inside the accounting transaction.

## Current authorized allowance

The v2 launcher authorizes one local smoke run: global 2 attempts / 10,000
reserved micros, with independent lifetime ceilings of 1 web and 1 news. It is
not daily replenishment. All other development/production allowances default to
zero. Initialize explicitly once; an independent owner-only `.initialized`
marker binds the allowance to the ledger and survives ledger deletion. Missing,
corrupt, non-owner, symlinked or unsafe ledger state blocks paid dispatch.

Any smoke failure permanently halts remaining dispatch. An abandoned in-flight
reservation is an unknown outcome and prevents continuation. The smoke runner
also refuses to restart a partially used allowance. There are no implicit
retries, pagination, suggestions, image, LLM or enrichment calls. Unsupported
endpoint kinds are rejected rather than being assigned an unmetered path.

`initialize_approved()` is an operator-only API for a future explicitly approved
local allowance with a nonsecret approval reference, total cap, endpoint daily
caps and fixed rate. Nothing invokes it for normal operation. The approval
reference is an audit pointer, not proof of authorization. The cumulative total
never resets at UTC midnight; endpoint daily caps are additional limits. A new
key, deployment or billing credit cannot increase either ceiling.

## Concurrency and rate metadata

Web/news workers share one ledger, one in-flight attempt and a minimum one-second
dispatch spacing. This is a conservative client limit, not an assumption about
the account's purchased QPS. Every returned `X-RateLimit-Limit`, `Policy`,
`Remaining` and `Reset` window is parsed and persisted; active windows decrement
on reservation and zero remaining blocks until reset. `Retry-After` supports
delta seconds and HTTP dates. No malformed or partially returned metadata is
interpreted as permission to spend: it halts dispatch for operator inspection.
401/403 outcomes pause for operator intervention. Smoke never retries 429 or 5xx.

The provider adapter passes sanitized status classes and the operational rate
headers only. Neither accounting nor failure diagnostics store query content,
result bodies, destination URLs, referrers, cookies, IPs or consumer identifiers.

## Honest accounting and reconciliation

The aggregate report separates:

| Field | Meaning |
| --- | --- |
| `attempts` | Durable reservations committed before dispatch |
| `conservative_reserved_micros` | Fixed rate × all attempts; hard safety ceiling |
| `confirmed_successes` | Received HTTP 2xx responses, including bad result schema |
| `schema_successes` | Responses accepted by the provider contract parser |
| `estimated_success_cost_micros` | List-rate estimate for received successful responses |
| `unknown_outcomes` | No received HTTP status, including unfinished attempts |
| `unknown_reserved_micros` | Conservative cost held for unknown outcomes |
| `reconciled_attempts` | Attempts matched privately to billing evidence |
| `reconciled_billed_micros` | Actual separately recorded billing amount |

Zero reconciled attempts means unverified invoice charges, not proof of a zero
bill. A 200 with an invalid schema may still be a billable provider success; it
is not useful-result acceptance. An HTTP failure/transport error is not labeled
a confirmed invoice charge. Private operator reconciliation never restores
attempt capacity, even when the reconciled charge is zero.

## Production dependency and recovery

SQLite is explicitly refused in production. The deployment target is unapproved;
there is no claim that ephemeral container storage is a global ceiling. An
approved shared datastore must provide serializable reservation/settlement,
durable ceiling configuration, contention tests, restore procedures and a cost
review before production can activate. No quota-block leasing is implemented.

Keep operational accounting outside content-cache cleanup. Rollbacks restore
code while retaining ledger/marker and finance records. A lost/corrupt ledger
requires restore/reconciliation and an explicit owner decision, never automatic
fresh initialization. Search outage copy must be honest and preserve ordinary
browsing/local features without weakening filtering or switching providers.
