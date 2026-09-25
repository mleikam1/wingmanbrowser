# Native macOS browser workstream

This separate worktree/branch starts at the completed UI checkpoint `3a6cd00`.
The native macOS target is a real AppKit `WKWebView` embedded with Flutter
`AppKitView`. It uses the redesigned application entrypoint, not the web companion.

## Local target and scope

- Minimum macOS: **13.0**. The development host is macOS15.7.4 arm64.
- Local application name: **Wingman Browser Preview**.
- New sandboxed identifier: `com.wingmanbrowser.redesign.macos`. Existing Android
  and iOS identifiers/signing are unchanged. No default-browser setting changes.
- The target is locally built/ad hoc signed. It is not notarized, distributed,
  submitted to a store, or pushed remotely.
- Standard build: `flutter build macos --release`.
- Local run: `scripts/run_macos.sh`.
- Native tests: `xcodebuild test -workspace macos/Runner.xcworkspace -scheme Runner
  -configuration Debug -destination 'platform=macOS,arch=arm64'
  -parallel-testing-enabled NO`.

No new browser plugin or external rendering engine was added. AppKit, WebKit,
Flutter and the repository's existing packages supply the implementation.

## Implemented capabilities

| Area | Native behavior |
| --- | --- |
| Website rendering | WKWebView with JavaScript, forms, persistent normal cookies/storage, actual native history/reload/stop, progress and title |
| Mandatory protection | Shared Apple policy parsing/digest validation, URL/search canonicalization, signed update receipts and compiled resource rules; startup capability is withheld until mandatory preparation succeeds |
| Private pages | Fresh nonpersistent WK store per private renderer; native child windows inherit the opener's store and captured ownership |
| New windows | Native opener/POST retained; adoption leases recheck document, origin, profile, restriction generation and expiry |
| Search | Existing strict provider construction/canonicalization; no fabricated search results or unrestricted proxy |
| Find/share | Native WK find and explicit AppKit sharing picker; picker closes on inactive/closed owner |
| Uploads | Native open panel, main-frame/origin/document ownership and completion revalidation |
| Downloads | Native WK transfer, destination/redirect policy checks, explicit confirmation and save panel; app-owned staging files cleaned on close/failure/restart; no automatic execution |
| Permissions | Origin-checked WebKit prompts plus OS camera/microphone approval; inactive pages end capture |
| Background/private UI | Every inactive application window is natively covered; inactive pages suspend playback and end capture; returning never grants capture automatically |
| Data deletion | Requested default-store deletion awaits WebKit completion; startup does not clear current normal cookies |
| Observed block counters | **Unobservable** on WKWebView; null counts, no invented totals |
| Default browser / Hand It Over | Explicitly unavailable on this new target; no unsupported capability claim |
| Windows/Linux | No native target in this milestone |

`darwin/ConsumerProtection.swift` is compiled by both Apple targets. The iOS
adapter retains its UIKit presentation; the macOS adapter owns AppKit sheets,
window lifecycle, and NSView ownership. SQLite and update metadata use the native
Application Support path rather than shared Documents. The app sandbox separates
this new local target from existing installations.

## Ownership corrections

Native navigation callbacks reject retired renderer identities. Restriction
compilation may restore an address only when both the captured request ID and
renderer lifecycle revision still match. Deferred opens also carry that revision,
so closing during rule preparation cannot reopen a page after cleanup completes.
Blocked events contain categorical reasons and captured request identity, never
the blocked URL/title. Upload, dialog and download completions are tied to their
captured renderer/document/origin and rechecked before completing.

## Verification ledger

| Check | Result |
| --- | --- |
| Initial debug application build | Passed |
| Focused Dart AppKit/storage/controller/update tests | 60 passed |
| Focused Dart analysis | No issues |
| Initial adapted current-consumer XCTest suite | 14 passed; real WebKit fixtures |
| Ownership regression/native suite | 14 passed, 0 failures, 21.258s; includes real retired-callback, superseded-restore and close-during-compile checks |
| Ordinary desktop runtime/screenshots | Pending final run |
| Release app | Pending final build |

Native fixtures run on generated benign loopback pages, reserved policy test
destinations, and ephemeral private stores. They test real POST/opener behavior,
same-document history, redirected-denial nonarrival, compiled resource blocking,
normal/private cookie separation, hidden media handling, signed metadata and
missing-policy gating. Test-only script evaluation and loopback servers are not
production bridge methods. Raw Xcode logs stay local and ignored; concise results
will be saved alongside the final runtime evidence.

Remaining platform limits follow [protection coverage](../../../PROTECTION_COVERAGE.md):
installed domain/path/rule data cannot classify every changing page or image,
and WK content rules do not expose enforcement counts. Flutter's macOS platform
view gesture support requires actual mouse/keyboard/scroll and overlay acceptance;
compilation alone does not establish that acceptance.

API references: [Flutter macOS platform views](https://docs.flutter.dev/platform-integration/macos/platform-views),
[AppKitView](https://api.flutter.dev/flutter/widgets/AppKitView-class.html),
[WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore),
[nonpersistent website stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()).
