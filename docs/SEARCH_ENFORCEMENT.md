# Search enforcement

Status: local approved-library search implemented. External search providers and broad search results are disabled pending review.

The production field searches approved titles, summaries, collection labels and article text on-device. This makes approved support and educational content discoverable by words in its body, without keyword bans. It never calls DuckDuckGo, Google, Bing, Brave, an AI service, or a classification endpoint. Old provider settings sanitize to the local provider. Keystrokes and submitted queries are not written as search history. Private search uses the same catalog eligibility and does not add history-based suggestions.

Typed URLs, unsupported schemes and encoded URL-like input produce a fixed unavailable message. They never fall back to a web provider. Unmatched ordinary text produces an empty local result set. Queries involving educational/support topics are not blocked simply because a word could be sensitive; only exact approved results can appear.

Results, summaries, saved titles and article opens all pass the current policy. Unknown/revoked/expired/incorrect-context/additionally-blocked records do not appear. Source URLs remain noninteractive text. The native content engines, external dispatch plugins, raw WebView channels and their success routes are removed, so parameter stripping and provider redirects cannot create a supported path.

The search field disables personalized IME learning, autocorrect and suggestion requests from Wingman. Its custom Flutter context menu includes only cut, copy, paste and select-all. Article text has no native selection menu. Android's raw process-text handler is addressed in the native security matrix. The host browser and third-party keyboard/OS behavior are outside Wingman's application boundary; this is not a device-wide filter.

Future live search would need a reviewed scoped result source plus enforcement of every destination/resource/redirect, not a SafeSearch URL parameter. No such provider integration is claimed here. Relevant native limitations and current official references are in FILTER_COVERAGE_AND_LIMITATIONS.md and SECURITY_TEST_MATRIX.md.
