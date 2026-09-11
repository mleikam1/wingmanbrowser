# Shell visual QA

Independent inspection on 2026-09-11 of all 20 `shell-*.png` captures, with emphasis on F02 and F04–F09. These are the actual Flutter app navigator with synthetic, ephemeral fixture data at 390×788 logical pixels, captured by `test/ui/shell_visual_test.dart`. They are not native device screenshots or evidence that live browsing is enabled. Home F03, Settings G01 and Protection P01 receive their detailed comparison in the root QA record.

## Comparison method and limits

The supplied [master specification](../../Wingman_UI_Design_Handoff/Wingman_UI_Master_Prompt.md) is authoritative about flow intent. Visual references were the supplied overview and `reference-previews/browser-dark.png`; reference and implementation images were inspected together. For Welcome, focused search, menus and tabs, the supplied interactive HTML's corresponding page composition was also inspected. There is no standalone reference PNG for each of those states, so this is not a claim of pixel matching for them. No reference HTML was counted as implemented application UI.

Reference browser imagery is 390×812 and includes a decorative OS status strip and outer rounded device corners. App captures are 390×788 and exclude OS chrome. The overall 24-pixel height difference is not a 24-pixel Flutter layout defect; the HTML's declared status-bar height is 28 pixels, so the comparison aligns app-content and dock edges rather than stretching either image or assuming every source coordinate differs by exactly 24. Native safe-area and system-keyboard behavior need their own device evidence.

The audit checked hierarchy, line wrapping, spacing, card edges, actual W asset rendering, semantic color roles, selected/disabled states, visible dismissal actions and clipping. It did not change application source or run Flutter/CUA. The existing `work/ui-root-final-layout.log` records 17 passing tests in four seconds, including the Shell's 320×480 and 844×390 layouts at 200% text. The subsequent `work/ui-shell-final-review.log` passed all 10 Home/navigation, Shell/capture and Home semantics tests in three seconds after the final corrections; it regenerated all 20 Shell images. This supports those exercised reflows and semantic assertions; it does not establish full accessibility conformance or universal display support.

## Findings and correction evidence

Final scoped result: no unresolved P0–P2 issue in the inspected Shell states. The final F05 replacement images were reopened in both themes and show consistent full-width cards. This is a scoped visual result, not whole-product acceptance.

| Priority | Finding | Action and current evidence |
|---|---|---|
| P2 | F02's earlier light capture showed a blank white medallion while dark showed the W. | Capture helper now awaits actual image precaching/painting. Reopened refreshed Welcome images show the preserved W in both themes. Resolved as a capture defect. |
| P2 | Earlier F04 “suggestions” images duplicated the empty focused state and contained neither a query nor suggestions. | Reopened refreshed images show `moon` and two real reviewed matches in both themes. The capture test now asserts the entered query and a visible reviewed match before capture. Resolved visually; these are local installed-catalog suggestions. |
| P2 | Earlier F07 information sheet reserved about 80% of the screen, leaving several hundred pixels empty. | The current shared adaptive sheet sizes to its content. Reopened light/dark captures show the whole explanation, dates and visible Close with balanced bottom padding. Resolved. |
| P2 | F05 result cards had inconsistent right edges: the shorter first card ended around x326 while the next ended at x370. | The root owner applied full-width cards within the existing bounded results column. Reopened final light/dark images now share the x20–x370 card edges. Resolved. |

The earlier blank-logo and empty-suggestion images were rejected as evidence, not treated as acceptable alternate states. The files now contain the corrected captures.

## Inspected state matrix

Each row covers both linked themes. “No additional issue” is a finding about the visible captured state, not a claim that every transition, platform or data variant has been exercised manually.

| Flow / state | Light | Dark | Inspection result |
|---|---|---|---|
| F02 Welcome | [Image](screenshots/shell-f02-welcome-light.png) | [Image](screenshots/shell-f02-welcome-dark.png) | Correct W, mission hierarchy, readable permanent-boundary explanation and fully visible Get started. One introduction, no account or permission carousel. Capture defect resolved. |
| F03 empty Home | [Image](screenshots/shell-f03-empty-light.png) | [Image](screenshots/shell-f03-empty-dark.png) | Visually opened for completeness. Search, useful next action, empty Spaces and Customize Home are present; detailed Home fidelity review is separate. |
| F04 focused empty | [Image](screenshots/shell-f04-focused-light.png) | [Image](screenshots/shell-f04-focused-dark.png) | Clear Back, labelled entry, clear action, Library/Official selection and explicit on-device scope. No additional visible issue. Native keyboard is absent from this host image and is not certified by it. |
| F04 local suggestions | [Image](screenshots/shell-f04-suggestions-light.png) | [Image](screenshots/shell-f04-suggestions-dark.png) | Refreshed query and two reviewed-title matches are visible. Input and result text fit; matches stay below the scope explanation. No owner-history or clipboard content is invented. |
| F05 results | [Image](screenshots/shell-f05-results-light.png) | [Image](screenshots/shell-f05-results-dark.png) | Search query/edit affordance, real collection filters, readable titles/snippets and offline review scope. Both cards now share consistent full-width edges in the final images. Content continues in a scrollable list above the dock. |
| F06 installed article | [Image](screenshots/shell-f06-article-light.png) | [Image](screenshots/shell-f06-article-dark.png) | Readable heading/body, distinct Bookmark/Read later, stable page-information row and five-position native dock. No horizontal clipping. Disabled Forward is visually subdued rather than a false active control. |
| F07 grouped menu | [Image](screenshots/shell-f07-menu-light.png) | [Image](screenshots/shell-f07-menu-dark.png) | Visible Close; page actions have distinct targets. Unsupported Find, Desktop and live-address share have precise reasons and no navigation chevron. Further groups continue below in a scrollable menu, not missing from the product. |
| F07 information | [Image](screenshots/shell-f07-information-light.png) | [Image](screenshots/shell-f07-information-dark.png) | Current compact sheet fits its full text and close action in both themes. Eligibility, identity, connection security and compatibility remain separate; there is no fabricated HTTPS/permission status. |
| F08 session tabs | [Image](screenshots/shell-f08-tabs-light.png) | [Image](screenshots/shell-f08-tabs-dark.png) | Correct real count, Normal/Private segmentation, selected card outline and independent card-close target. New normal/private and scoped Close all remain visible. Metadata placeholder has no website or private thumbnail. |
| F09 private start | [Image](screenshots/shell-f09-private-light.png) | [Image](screenshots/shell-f09-private-dark.png) | Private banner and wording distinguish the session in either theme. Empty-session surfaces show no normal goals, notes or saved resources. The last Customize action continues in the scrolling content rather than being part of the fixed dock. |

## Intentional capability differences

The source F06 illustration is a sample website, with a domain field and Reload. The implemented F06 is an approved original plain-text article. Its compact bar says “Reviewed offline article” and its status describes installed text. It does not imitate an active origin, add website artwork to signed plaintext, offer an ineffective Reload, or allocate a WebView. Those differences preserve the authoritative capability boundary.

Focused search uses the installed library and an explicit Official mode. It does not populate the source mockup's owner-history examples or imply a network search provider. The menu uses readable rows with capability explanations instead of making the source's unsupported quick actions appear active. Tab counts, titles, selected state and privacy groups come from actual session state rather than the reference's four sample tabs.

Both themes retain navy/blue identity, the supplied W artwork, restrained outlines and distinct action/secondary-text roles. The app uses bundled Roboto with 16-pixel body text and deliberately larger accessible controls than some 12/14-pixel HTML reference labels. Screenshots show legible wrapping at the capture size; exact type metrics, contrast calculations and tested target sizes are recorded in [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md), not inferred solely from raster appearance.

## Accessibility and evidence boundary

No text is visibly cut horizontally in these 20 phone frames. Article/result/menu content reaches the viewport boundary as expected for real scrolling surfaces; fixed navigation does not overlap the allocated scroll viewport. The private Home's lower Customize action is partially below the initial viewport, so its reachability depends on scrolling rather than a claim that every action fits above the fold. The compact information sheet now exposes its complete text and an explicit dismissal affordance.

Source checks confirm 48-pixel icon targets, scalable rows, opaque routes and shared reduced-motion sheets. The separate Home semantics regression exercises an enabled action and heading separation for normal/private Home; its handle-cleanup fixture was corrected and the root rerun passed both cases. These screenshots do not prove VoiceOver/TalkBack traversal, native keyboard occlusion, capture shielding, privacy persistence or policy race correctness. Those conclusions must use the functional and native evidence in [QA_REPORT.md](QA_REPORT.md) and [NAVIGATION.md](NAVIGATION.md).
