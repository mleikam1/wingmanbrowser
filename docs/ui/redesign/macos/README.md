# Native macOS browser workstream

This separate worktree/branch starts at the completed UI checkpoint `3a6cd00`
and includes the shared UI follow-up `33c1cc0` (original `1a31bfd`).
The native macOS target is a real AppKit `WKWebView` embedded with Flutter
`AppKitView`. It uses the redesigned application entrypoint, not the web companion.

## Local target and scope

- Minimum macOS: **13.0**. The development host is macOS 15.7.4 arm64.
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

The ordinary release run caught an additional integration defect: macOS Flutter
assets live in `App.framework/Resources/flutter_assets`, so the inherited iOS
main-bundle lookup correctly failed closed but withheld live browsing. The macOS
resolver now reads the sealed App.framework bundle; production and native tests
use that same resolver. No fallback policy or bypass was added.

The ordinary application integration also caught a real same-document history
publication race. WebKit may report its pending Back/Forward URL before updating
the committed history item, and then finish without a second URL notification.
Both Apple adapters now recheck committed URL state on loading/history availability
changes, plus a deferred URL observation fenced by renderer, request and lifecycle.
The existing committed-item/policy guard remains intact. Native fixtures cover
endpoint and middle-to-middle traversal (both navigation buttons remain enabled),
with stable renderer/document identity and no extra page request. The ordinary
macOS integration proves native Back/Forward updates the visible Flutter address.

## Verification ledger

| Check | Result |
| --- | --- |
| Initial debug application build | Passed |
| Focused Dart AppKit/storage/controller/update tests | 60 passed |
| Focused Dart analysis | No issues |
| Initial adapted current-consumer XCTest suite | 14 passed; real WebKit fixtures |
| Native suite with production bundle resolver, before final history correction | 14 passed, 0 failures, 23.821s; includes real retired-callback, superseded-restore and close-during-compile checks |
| Final native history-regression rerun | Compiled; test host stalled in dyld before any case began, reproduced once; added macOS endpoint/middle-to-middle native assertions remain unexecuted |
| Corresponding iOS native history regressions | 13 passed, 0 failures, 20.346s in sibling UI worktree; endpoint and middle-to-middle Back/Forward included |
| Full desktop Flutter suite | 1,055 passed; six existing opt-in checks skipped; 2m06; exit 0 |
| Final whole-project analyzer | No issues; 4.4 seconds; exit 0 |
| Ordinary app integration | 1 passed, 11 seconds, exit 0; actual `app.main`, native HTML/JavaScript, Back/Forward, redirect denial, branded boundary and Home cleanup |
| Packaged ordinary release input | Passed via CUA: address keyboard/Return, native form text, native button, native scrolling, links and toolbar Back/Forward; screenshots 05–08 |
| Hide/return acceptance | Hide menu visibly shields page; after Raise/titlebar content returns but active native input could not be re-established; context-preserving return remains open |
| Final ordinary release app | Passed; explicit lib/main.dart with normal pub; 74.3MB; universal x86_64+arm64; deep/strict signature valid; no test bundle or integration plugin |

Native fixtures run on generated benign loopback pages, reserved policy test
destinations, and ephemeral private stores. They test real POST/opener behavior,
same-document history, redirected-denial nonarrival, compiled resource blocking,
normal/private cookie separation, hidden media handling, signed metadata and
missing-policy gating. Test-only script evaluation and loopback servers are not
production bridge methods. Raw Xcode logs stay local and ignored; concise results
are saved alongside the final runtime evidence. See the [ordinary app integration
result](evidence/ordinary-app-integration-final.txt), [full Flutter suite
result](evidence/flutter-full-suite-final.txt), the [final native-host launch
limitation](evidence/native-tests-history-launch.txt), and [screenshot provenance](screenshots/README.md).

Remaining platform limits follow [protection coverage](../../../PROTECTION_COVERAGE.md):
installed domain/path/rule data cannot classify every changing page or image,
and WK content rules do not expose enforcement counts. Flutter's macOS platform
view gesture support requires actual mouse/keyboard/scroll and overlay acceptance;
compilation alone does not establish that acceptance.

## Runtime evidence and remaining acceptance

- [Release onboarding](screenshots/01-welcome.jpg) and
  [release native Home](screenshots/02-home.jpg) are actual application captures.
- [Native page in the expanded shell](screenshots/03-integration-native-page.jpg)
  is the real `app.main` Flutter integration run, using a benign loopback page
  inside AppKitView/WKWebView. It is not a mockup or Flutter-painted page.
- [Native redirect boundary](screenshots/04-integration-native-boundary.jpg)
  is that same real integration journey after a native policy-denied redirect.
- The initial [fail-closed capability state](screenshots/initial-capability-unavailable.jpg)
  records the production asset resolver failure before the fix.

**Foreground input passed in the final packaged release.** A clean exact-path
launch, Raise and address click accepted real keyboard/Return navigation. The
native HTML form accepted `Wingman release QA`, its button changed the page's
status, scrolling reached the footer, a link loaded `/next`, and native toolbar
Back/Forward settled to the matching visible page and Flutter address. See
[the input capture](screenshots/05-release-native-input.jpg),
[scroll capture](screenshots/06-release-native-scroll.jpg),
[Back](screenshots/07-release-native-back.jpg) and
[Forward](screenshots/08-release-native-forward.jpg).

**Return from inactivity remains partly unverified.** The native Hide menu
visibly replaced webpage content with a [privacy shield](screenshots/09-release-hidden-cover.jpg).
Raise/titlebar restored visible page content, but the window still appeared
inactive and native typing could not be re-established. A later attempted
interaction ended at [Home](screenshots/10-release-after-return.jpg); that sequence
does not establish context-preserving resume. A bounded follow-up reopened the
fixture through Flutter address controls but could not enter the unique native
form marker needed to isolate a second hide/show check. No privacy behavior was
weakened. Earlier CUA/Flutter foreground failures (`open returned 1`) remain
historical launch evidence; they do not negate the successful final input journey.

Native file panels, camera/microphone approval, context-preserving active return,
Intel runtime, and public distribution remain untested. This local preview is not
desktop release certification. The final added native history assertions also
need a successful macOS XCTest host launch; the last 14-test pass predates that
observer correction, while the ordinary-app integration and corresponding iOS
history regressions passed afterward.

## Packaged preview

- [Application](<../../../../artifacts/macos/Wingman Browser Preview.app>)
- [Universal macOS ZIP](../../../../artifacts/macos/Wingman-Browser-Preview-macOS.zip),
  32,138,440 bytes, SHA256 `22c05cd53eb26a67e45bfe661de81f926c652b88b5f5f321110f72d340c862da`
- [Build manifest](../../../../artifacts/macos/BUILD_MANIFEST.json) records source,
  asset and executable digests and the exact verification scope.

The bundle version is 0.16.0 (19), minimum macOS 13.0, locally ad hoc signed.
Runtime acceptance used Apple Silicon/macOS 15.7.4. Standard dependency hooks
warned about differing architecture-specific framework names for objective_c and
sqlite3; both selected packaged frameworks pass deep/strict signature validation.
To repeat the benign manual journey, run `python3 tool/macos_manual_fixture.py`
from the repository root and enter its printed loopback port in the app. The
fixture never loads external resources or changes production policy.

API references: [Flutter macOS platform views](https://docs.flutter.dev/platform-integration/macos/platform-views),
[AppKitView](https://api.flutter.dev/flutter/widgets/AppKitView-class.html),
[WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore),
[nonpersistent website stores](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()).
