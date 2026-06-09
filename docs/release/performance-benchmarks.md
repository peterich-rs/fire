# Fire Performance Benchmarks

These benchmark definitions are release gates. Current scripts provide repeatable measurement workflows, but final baselines must be recorded on real release builds before submission.

## Targets

| Metric | Target | Failure Threshold |
| --- | --- | --- |
| Cold start to home visible | < 3.0s | > 5.0s |
| Home feed scroll fluency | >= 58 fps average | < 55 fps average or > 5% janky frames |
| Topic detail first screen | < 2.0s | > 3.0s |
| Home feed memory | < 200 MB | > 300 MB |
| Topic detail memory after 100 posts | < 350 MB | > 500 MB |

## Required Devices

| Platform | Preferred Device | Fallback |
| --- | --- | --- |
| iOS | Current physical iPhone Pro device | iPhone simulator for smoke runs only |
| Android | Pixel 8-class physical device | Pixel emulator for smoke runs only |

## Scripts

```bash
scripts/benchmark-cold-start.sh ios
scripts/benchmark-cold-start.sh android
scripts/benchmark-scroll-fps.sh ios
scripts/benchmark-scroll-fps.sh android
scripts/benchmark-topic-load.sh ios
scripts/benchmark-topic-load.sh android
scripts/benchmark-memory-peak.sh ios
scripts/benchmark-memory-peak.sh android
```

## Results Log

| Date | Commit | Platform | Device | Build Type | Metric | Result | Pass/Fail | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | | |

Use exactly the metric names from the target table. `Pass/Fail` accepts `Pass`
for measurements inside the release threshold or `Accepted` for an explicit
ship/no-ship decision on a threshold failure. Results must include metric-bound
numeric units: seconds or milliseconds for timing metrics, `fps` plus a
janky-frame percentage tied to `jank`/`janky` for scroll fluency, and MB/GB for
memory metrics. If a memory result includes multiple values, label the peak
value with `peak` (`peak 190 MB` or `190 MB peak`); otherwise the verifier
treats the row as ambiguous. The verifier uses the highest labelled peak memory
value for threshold comparison.
`Accepted` rows must include approval/waiver context and a reason, risk,
exception, or no-ship decision in `Notes`; use a clear shape such as
`Approved by <owner>; reason: <decision>`. Simulator and emulator rows may be
linked as supporting context elsewhere, but they do not satisfy this log. Device,
build type, result, and notes metadata must not contain fake/mock/placeholder
markers or placeholder URL hosts such as localhost, `.local`, `.test`, or
`.invalid`. Keep exactly one row per platform and metric pair; duplicate rows
are rejected because they make release evidence ambiguous.

## Release Rule

Do not mark P4 performance complete until this log contains release-build measurements for iOS and Android, and any failures have an explicit owner, approver, and reasoned ship/no-ship decision.

Before marking performance evidence complete, run:

```bash
scripts/verify-performance-benchmarks.sh
```

The verifier fails until each target metric has an iOS and Android
release-build physical-device row with date, commit, device, result, and
`Pass` or reasoned `Accepted` disposition. `Pass` rows must parse to values
inside the release targets. `Date` must be a real calendar date in `YYYY-MM-DD`
form. Duplicate platform/metric rows and rows with missing or extra Markdown
table columns are rejected; keep the exact table shape and escape literal `|`
characters in cell text.
