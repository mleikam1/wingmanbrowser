# Launchpad specification

Implementation base: clean `e93fc0e` on `launchpad/implementation`. The user-facing feature is **Your Launchpad**. It extends the existing Home and uses the same current policy, local stores, session ownership and navigation callbacks. It does not add a live renderer or grant website access.

## Three distinct records

| Record | Owner and purpose | Relationship to other data |
|---|---|---|
| Shortcut | A user-selected navigation preference: typed destination, name, local icon, position and optional folder. | Pinning/removing does not create/delete a bookmark, history entry, account or Space resource. |
| Starter catalog entry | A suggestion with a stable ID, description, category, canonical candidate target, region, editorial source URLs and review dates. | Never contains a permission. Catalog refreshes do not rewrite saved shortcut titles, addresses, icons, folders or order. |
| Collection preference | Explicit Sports, Shopping or Learning selection, visibility/order and a finite list of independently owned typed sources. | Sources retain their own target descriptors. Deleting a shortcut does not delete its chosen collection source; adding a source does not silently pin a shortcut. |

The installed catalog currently combines eight Wingman tools, up to 100 currently supplied signed resources, and eight researched website candidates. The shipped signed library has 18 resources, giving 34 suggestions when it is available. Tool and resource candidates can be useful now; website candidates remain inactive local review records. The researched identities and actual platform limitations are recorded in [LAUNCHPAD_SITE_COMPATIBILITY.md](LAUNCHPAD_SITE_COMPATIBILITY.md). Editorial website provenance was reviewed September 11, 2026, with a 30-day refresh window. Those dates do not authorize content or website navigation.

## Interaction references

The supplied brief adapts familiar Speed Dial interactions, with Wingman's own branding, persistence and current-content boundary. Opera's official desktop documentation describes a plus entry for suggested or typed destinations, editing names/addresses, dragging to reorder and grouping entries into folders. Wingman uses those organizing patterns with explicit folder deletion choices and accessible alternatives to dragging. [Opera desktop Start Page](https://help.opera.com/en/latest/start-page/)

Opera's iOS documentation describes saving the current page through its page menu and using a long press for move/edit/remove actions. Wingman's reviewed-page pin preview and shortcut action menu follow that interaction pattern, while capturing the originating page and privacy scope. [Opera iOS Start Page](https://help.opera.com/en/mobileios/start-page/)

Opera's Android article describes suggested and custom destinations, long-press editing, current-page addition and folders. Wingman's atomic multi-selection comes from this product brief; that source is not evidence that Opera implements the same batch behavior. These references establish interaction provenance, not endorsement, copied assets or permission to load a website. [Opera for Android tips](https://blogs.opera.com/mobile/2026/08/five-ways-to-get-more-out-of-opera-for-android/)

## Data schema and bounds

`lib/signature/launchpad/launchpad.dart` exports models, controller, catalog and eligibility helpers. `SignatureServices.launchpad` participates in initialize, flush and disposal. The existing `SignatureDocumentStore` adds only the `launchpad` key; the underlying SQLite schema and unrelated feature documents are unchanged.

One version-1 document contains the complete Launchpad state:

| Element | Fields / invariant | Bound |
|---|---|---|
| Shortcut | `id`, `title`, typed `target`, `localIconKey`, nullable `folderId`, `order`, `source`, nullable `catalogEntryId`, UTC `createdAt` / `updatedAt` | 64 shortcuts; title 80 characters; resource/record IDs 80; provenance ID 128 |
| Target | Exactly `kind` (`resource`, `tool`, `website`) and `value`; known tool enums and strict typed parsing | Website string up to 8,192 characters, also subject to document byte limit |
| Folder | `id`, `title`, `localIconKey`, top-level `order`; no parent-folder field | 12 folders; name 80 characters; one level only |
| Collection | `kind`, `visible`, `order`, independent source `title` / `target` / `localIconKey` | Three named collection kinds, 24 sources each |
| Preferences | `showShortcuts`, `showCollections`, `density` (`compact`, `comfortable`), `setup` (`notStarted`, `completed`, `dismissed`) | Typed booleans/enums only |
| Migration | `version: 1`, `legacyMigrated: true` | Written atomically with the first converted document |

The complete JSON document is capped at **512 KiB**, so its byte limit can be reached before the item count when addresses are unusually long. Every restore and durable mutation validates the exact schema. Unknown fields such as an `isApproved` flag are rejected rather than retained as authority. Duplicate IDs, duplicate shortcut targets, duplicate collection targets, orphaned folder references and noncontiguous sibling ordering are invalid. Root ordering combines folders with unfiled shortcuts; each folder has its own contiguous child order. Folder cycles cannot be represented.

Local icon presets are `link`, `book`, `science`, `sports`, `shopping`, `tools`, `home`, `star`, `folder`, `globe`, `school`, `receipt` and `checklist`. An initials key is exactly `initials:` followed by one or two uppercase ASCII letters/digits. There is no remote icon, image, executable SVG or HTML field. Text labels reject control and directional-override characters and render as Flutter text.

## Atomic mutation and restoration

Every mutation enters one controller queue and merges with the latest committed snapshot inside that queue. It checks that initialization succeeded, the controller is not disposed, and the optional captured `canContinue` callback still approves the action. It validates the proposed complete document and writes it before publishing a new snapshot or reporting success. Failed writes retain the previous in-memory/durable state and return fixed, non-sensitive errors. A subsequent valid write can retry; unreadable restoration is a separate state that cannot overwrite the preserved document.

Shortcut additions, batch additions, edits, folder moves/deletions and each reorder are single-document atomic operations. Batch addition skips identical existing targets, returns the IDs actually added and rejects an invalid member without publishing a partial batch. Reorder methods require the exact current sibling set, so a stale form cannot omit newly added siblings. Collection UI uses `updateCollection(kind, transform)` with the latest record inside the queue; independent source and visibility edits do not overwrite each other. `setCollection` remains the explicit full-record operation.

Successful explicit addition completes first-use setup. Dismissal is durable, and deleting the last shortcut does not reopen setup. `resetConfirmed()` reopens the suggested picker only: it does not repin removed defaults, reset protection, clear existing shortcuts, erase collections or restore an old layout.

Folder deletion explicitly chooses between moving children to the root and deleting children with the folder. Undo tokens are bounded by the already bounded removed records, private to the creating controller, session-only and single-use. Undo merges only those records into current state; it does not restore a whole previous document or an approval. It rechecks destination eligibility. If a moved child was edited, reparented or removed, or a deleted target was already added again, stale undo is rejected rather than overwriting newer work. An in-flight token cannot be replayed; a failed durable undo can be retried. A closed session cannot use its old token.

## Once-only migration

Startup reads the `launchpad` document first. If it exists and validates, the legacy shortcut list is never imported again. If it is absent, the controller reads and strictly parses the existing version-1 `ui` document. It converts `ui.shortcutIds` in their original order, preserves even currently unavailable resource IDs as inert records, and writes the complete new document with its migration marker in one atomic operation. A nonempty converted list marks setup completed. A fresh or explicitly empty legacy list produces an empty Launchpad with setup not started.

The legacy `ui` document is left unchanged. Bookmarks, tabs, quarantined history, reading marks, Spaces, tasks, findings, receipts and policy checkpoints are untouched. A read error, malformed source, unknown future version or failed first write leaves existing data intact and exposes a fixed restore error. Restart can retry a transient failure. There is no fallback that overwrites a malformed document with defaults. Confirming “restore suggestions” cannot bypass that protection.

The migration marker lives in the new document, avoiding a two-document transaction: either the whole converted snapshot exists, or the next startup retries from the unchanged legacy source. Later removal or renaming cannot be undone by a catalog update or restart.

## URL recognition and current authority

`normalizeLaunchpadWebsite` calls the existing `OmniboxParser` and `requireWebUri`. A bare public hostname becomes HTTPS. Host case/trailing dots and an empty root path are normalized; meaningful paths, query order/duplicates and fragments are retained. Matching shortcut targets use the resulting complete typed destination, not a root-domain comparison.

Unsupported schemes, embedded credentials, invalid ports, control characters, ambiguous host escapes, raw Unicode hostnames, IP literals, single-label/local hostnames and numeric terminal labels are rejected. This milestone accepts public ASCII hostnames and their explicit ASCII IDN form; it does not pretend to implement a new Unicode hostname canonicalizer. No validation step performs a title lookup, DNS request, favicon fetch, preconnect, hidden WebView or navigation.

`LaunchpadEligibilityService.assess` is uncached. Resource checks use the caller's current policy, edition/private context and additional restrictions. Tool checks use known local keys and actual session capability. Websites enter the authoritative `PolicyRequest.navigation` evaluation; the compiled absence of live-content support also prevents an incorrect injected allowance from making a website openable. The UI receives `canOpen`, a fixed explanation and policy code. An unsupported/unreviewed website can be retained only with explicit inactive-record consent. A known mandatory/security denial is not retainable through that exception. No decision, expiry bypass, allow-once token or user-editable approval is stored.

Editing a destination normalizes and rechecks it, then clears the old catalog provenance and changes its source to user-authored. Renaming or changing the icon for the same normalized destination preserves provenance. A saved catalog ID is only a hint; current catalog metadata may be shown as matching provenance only if the catalog target still equals the saved target. Names, folder labels and presentation categories never influence permission.

Rendering and opening reassess current eligibility, with root policy/state notifications triggering fresh UI. Revoked resource titles/targets are redacted through the presentation helpers rather than showing old signed content metadata. Restored unavailable records remain removable; cleanup and reordering do not require a new approval. New source additions and undo do require current checks. Policy revocation during a pending disk write cannot produce a cached active permission because none exists; the displayed/opened state is always reevaluated.

## Session privacy and navigation ownership

Normal consumer Launchpad choices use the existing local SQLite/IndexedDB document store. `SessionSignatureDocumentStore` gives private, Student and unknown editions distinct memory storage before any read. Their Launchpad controller never reads the owner's `ui`, `launchpad`, folder names or selected sources and never writes to normal storage. Disposal rejects queued mutations, and private scope is not a policy exemption. Hand It Over does not create an owner Launchpad or expose editing/navigation into it.

The normal document can contain user-chosen website addresses (including their path/query/fragment), collection source domains, names and folder labels. These are explicit local preferences; they are neither sent to a service nor included in the Trust Receipt. Privacy & data exposes a normal-only **Your Launchpad and sources** deletion choice. `clearSavedData()` atomically replaces the document with empty records, default Launchpad display settings, a retained migration marker and dismissed setup. It preserves unrelated feature documents and protection. Successful deletion invalidates even an undo already queued behind that deletion; a failed/canceled write retains both the old state and its undo validity. The legacy `ui` document remains unchanged, and the retained marker prevents it from being reimported. This is logical local deletion, not a promise to erase backups, exported copies or every physical storage remnant.

Root supplies `LaunchpadActions`: captured-origin checks, current policy notifications, eligible bookmark drafts, safe feature navigation and resource-only Add to Space. Page pinning uses an explicit preview tied to the current committed reviewed resource. All opens return to existing Wingman policy/navigation callbacks; there is no external launcher, iframe or raw renderer load. New Wingman tabs apply only to supported reviewed resource targets and retain the existing tab limit/privacy scope. Website entries remain local inactive records on Android, iOS and Web.

## Focused core evidence

`test/signature/launchpad_core_test.dart` contains 25 focused cases for normalization, unsupported/forged permission, setup/removal/restart, exact-once migration, malformed data/read/write failures, private store exclusion, batch atomicity, provenance invalidation, duplicate distinctions, pending writes, origin/disposal guards, folder reorder/delete/undo, stale/replayed tokens, independent collection updates, immutable queued inputs, scoped deletion and storage limits. It also loads the actual signed bundle and evaluates real resource/additional/revocation and website decisions. The first run passed the initial 22 cases plus all eight existing `SignatureServices` regressions (30 total); scoped analysis was clean. The three additional queued-input/deletion cases are included in the final combined gate. UI, native, browser and final combined evidence belong in [LAUNCHPAD_QA.md](LAUNCHPAD_QA.md), separately from these core checks.
