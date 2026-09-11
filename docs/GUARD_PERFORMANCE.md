> Historical Phase 1–3A document. Optional Guard, live browsing, external search, Reader and ad behavior described here is superseded by [permanent protection 0.4](RELEASE_READINESS.md). It is not a current capability or release claim.

# Guard lookup and storage measurements

Measured on 2026-09-10 with Flutter host tests, Dart 3.12.2, macOS 15.7.4 ARM64.
These are debug host SQLite FFI measurements, not phone performance promises.
The benchmark creates an ephemeral test signing key and a 100,000-rule synthetic
pack, verifies/imports it, closes/reopens the database, and performs real indexed
suffix queries. Its key is never trusted by the app.

| Measurement | Result |
| --- | ---: |
| Signed synthetic rules | 100,000 |
| NDJSON artifact | 13,400,000 bytes |
| SQLite database, one release and index | 21,966,848 bytes |
| Import including signature, archive, and index verification | 3,019 ms |
| Reopen including signed archive and full index verification | 554 ms |
| Uncached suffix lookup, 1,000 samples, p50 / p95 / maximum | 199 / 327 / 1,619 µs |
| Warm cache lookup, 1,000 samples, p50 / p95 / maximum | 9 / 14 / 542 µs |
| Cached hosts after 2,000 distinct additional hosts | 512 |

SQLite's query plan was `SEARCH r USING PRIMARY KEY (generation=? AND host=?)`.
The integrity scan uses the primary-key range `(generation=? AND host>?)` and
500-row keyset batches. No navigation query scans all rules or creates a Dart
set containing every domain. The normal session LRU cache has a 10-minute TTL;
private requests bypass both its reads and writes. Native readers use the same
indexed database and do not receive an exported list of all domains.

Process RSS was 244,301,824 bytes before import and 163,676,160 after import;
before/after the 2,000-host churn it was 194,478,080 / 173,359,104 bytes. These
point readings include the Flutter test VM, signing-fixture construction,
garbage collection, and allocator history. They do not establish a reduction in
memory use or isolate the repository's retained memory. The cache-size assertion
and indexed query plans provide the bounded-navigation evidence.

The production importer accepts at most 64 MiB and 500,000 rules per artifact,
with a 64 KiB manifest. It retains the active and previous successful releases.
An update temporarily holds bounded artifact bytes and decodes records in chunks
with 500-row insertion batches; its peak memory is higher than steady navigation.
The shipped starter has only 49 rules and 6,386 NDJSON bytes. Large-pack update
peak memory and animation behavior on low-memory physical phones remain unverified.

Reproduce from the repository root:

```sh
flutter test test/guard/filter_pack_benchmark_test.dart \
  --dart-define=GUARD_BENCHMARK=true \
  --dart-define=GUARD_BENCHMARK_OUTPUT=/absolute/path/guard-performance.json
```

The benchmark is intentionally skipped in the ordinary suite. The measurement
run passed separately. Raw local evidence lives in the workspace's
`work/phase2-guard-benchmark.log` and `work/phase2-guard-performance.json`.

## Android emulator sample

The native engine agent also measured the same 100,000-rule indexed shape on an
Android API 36 emulator reporting 1,971 MB RAM. Across 1,000 uncached, varied
subdomain queries, native lookup p50 was 1,725.458 µs and p95 was 11,239.458 µs.
Main-process debug PSS was 331,477 KB idle and 334,803 KB with three WebViews
(+3,326 KB); renderer processes are separate and this delta is not the browser's
total memory cost.

The host had about 21 GB swap in use while an iOS build ran concurrently.
Observed page loads were 18.9 / 6.8 / 4.9 seconds, and test-pump-inclusive tab
switch durations were 280 ms p50 / 1,140 ms p95. These stressed debug emulator
readings are unsuitable evidence for a claim of smooth animation or production
latency. Low-memory physical Android devices and older physical iPhones remain
unverified. Full native fixture/memory context is recorded in
[the native validation notes](phase2/NATIVE_GUARD_VALIDATION.md).


## Quieter native lookup rerun

With concurrent builds stopped, the Android lookup-only fixture passed in three
seconds plus two seconds teardown. The first 1,000 varied native evaluations
measured p50 **0.509 ms** and p95 **4.981 ms**. Repeating 1,000 evaluations with
SQLite pages warm measured **0.122 ms / 0.308 ms**. There is still no native
hostname-result cache. These timings exclude MethodChannel transport and use a
separate debug-only unsigned 100,000-rule indexed fixture; they do not measure
production signature verification or full application startup. The earlier
stressed memory/page/switch results remain relevant qualifications, not results
replaced by the lookup-only run. See the exact native method and fixture in
[the native validation notes](phase2/NATIVE_GUARD_VALIDATION.md).

## Performance budgets and release gates

These are engineering targets, not claims of measured physical-device success:

| Budget | Requirement and current evidence |
| --- | --- |
| Foreground indexed decision lookup | p95 at most **5 ms**, p99 at most **10 ms** on each supported physical-device tier. The quieter emulator p95 fits this target; physical-device p95/p99 and end-to-end decision latency remain unverified. |
| Incremental release Guard cold startup | At most **150 ms** for an already-installed shipped starter pack, including integrity checks. This is an unverified release/physical-device target. The final measured 1,622 ms debug UI initialization includes new database creation/import and is not evidence that this target is met. First import must be measured separately. |
| Normal-session host cache | Hard cap **512 entries**, **10-minute TTL**; private requests bypass reads and writes. Covered by repository tests. |
| Live native browser views | Hard cap **3 engines**; up to 50 persisted normal-tab metadata entries. Native integration verifies the live-view bound; renderer processes must be included in release memory measurement. |
| Large-pack import/reopen | The 64 MiB/500,000-rule input caps bound admitted work, not peak memory. Signature/index verification, temporary artifact memory and the active/previous releases must fit measured low-memory physical-device headroom before shipping larger packs. The host 100,000-rule reopen took 554 ms, so the starter startup budget cannot be extrapolated to that pack. |

No animation or release frame-time budget is marked achieved from debug test
pumps. Release profiling must measure UI frames and end-to-end navigation while
imports, rollback and three live views are active, on low-memory Android hardware
and the oldest supported physical iPhone. Failure to meet these budgets is a
release gate requiring optimization or a smaller supported pack/device scope.
