# Local live strain estimate

`LiveStrainEngine` provides a bounded streaming estimate for a live heart-rate session. It uses recovered Android smoothing, heart-rate reserve, logistic weighting, normalization, and the packaged 211-row display lookup. Its duration accounting is an explicit local integration choice. It does **not** reproduce the complete Android controller, daily WHOOP strain, Recovery, sleep staging, or historical server calculations. The UI should call its output **Local strain estimate**.

```swift
var engine = try LiveStrainEngine(restingHeartRate: 60, maximumHeartRate: 190)
try engine.append(HeartRateSample(timestamp: Date(), bpm: 145))
let displayedEstimate = engine.scaledScore
```

The member supplies resting and maximum heart rate; no age, biological sex, fitness level, or physiological baseline is fabricated. Rates must be finite and in `(0, 300]`, and maximum must exceed resting. `maximumHeartRate` is the profile maximum before the recovered helper's `+3` offset. Each scoring point uses `max(profileMaximum, smoothedPointHeartRate)` as its maximum, rather than selecting a maximum over an arbitrarily sized delivery batch.

Dates are rounded to epoch **milliseconds** at this API boundary. Timestamps must be nonnegative, representable, unique after rounding, and strictly increasing. Duplicate, reversed, nonfinite, and invalid samples throw before changing engine state. A consecutive gap of **30,000 milliseconds or more** also throws without scoring, filling the gap, or accepting that point. The caller can start a separate engine after a disconnect; its score must remain a separate estimate. This validation is a local integration policy, not a claim about Android's validation behavior.

## Observed shipped algorithm

Evidence concerns WHOOP Android 5.444.1 / 431134, repacked artifact SHA-256 `1a00151e0a6933e075167586290d07df648e1e3eab3f2f24e1c9b561ea41f241`. Its DEX entries were previously matched to the supplied base APK. These are static observations; WHOOP was not executed.

| Behavior | Retained evidence |
| --- | --- |
| Combine previous leftovers and new points, equality-based duplicate handling, smoothing, retain suffix starting at `max(0, lastUsedIndex-60)` | `phase3/results/529-health-straincalc-k.json`, `ev_047fa34c0868cfe0a28e8550007efd6d2fa27c6318b745450f6a5fcf9553499a` |
| Smoothing bounds and largest-gap trim | `phase3/results/536-health-straincalc-n.json`, `ev_4a37e2baa6fb41082b347b4844affaa777772e02703de5f6a28c9096aba424f4` |
| Exact timestamp-index search | `phase3/results/557-health-strain-timeindex.json`, `ev_b64fb767691c44cb4b0d41488cf0a0ee97745a109a8fb69ceb76e11c573891b2` |
| Linear 0.25 quantile | `phase3/results/556-health-strain-smoothquantile.json`, `ev_6562933df5a9b2c1049ce3e8209b20d140062087c0a060c1cac391e18382c638` |
| Reserve clipping and 0.3 cutoff | `phase3/results/555-health-strain-reserve.json`, `ev_81250535675ce8c00ec3945c4f3e085be32c708c457c1733c98f387f2080e585` |
| Duration branches | `phase3/results/543-health-strain-duration.json`, `ev_68ae8bfbb0987a9d8292d19d6283fde7aacaf6087bea69135164f5b77ea68cc1` |
| Accumulate returned batch raw contributions and convert cumulative total | `phase3/results/548-health-realtime-strain-flow.json`, `ev_63aa9b9f6bef97dcd2472cbb91deedff906de8d12df8e15bfd75e7ec80454cb2` |

Paths are relative to `/workspace/whoop-analysis`. The broader record is `phase3/HEALTH-CALCULATIONS.md`; `phase3/health-supplemental-dex.json` retains instruction-level corroboration. In that supplemental record, `vd0.d.e` returns the **first** matching gap index; `vd0.d.g` calls `i` with divisor `1`, and `i` emits adjacent timestamp differences plus a terminal zero. No new runtime or REA session was required for this implementation.

For source-list index `i`, the smoother processes only while `i < count-30`. Its window is `[max(0,i-30), i+30)`, with the upper bound excluded. Therefore the first smoothed center becomes eligible only on accepted sample **31**, although that final newly accepted point is outside its quantile window. A mature full window contains 60 points. The selected rates are sorted and linearly interpolated at `0.25*(count-1)`.

The source finds the largest adjacent timestamp gap in that window. If it is at least `30000`, it takes the first matching gap index `e`: when `e >= 30`, retain the prefix of length `e`; otherwise skip `e+1` points. The prefix rule also excludes the left endpoint at index `e`, and its threshold is the literal constant 30, even in a shorter initial window. `recoveredSmoothedHeartRate` preserves those exact bounds for inspection and tests. Public live input rejects such gaps, so the local estimate never relies on that trim to bridge a disconnect.

Recovered reserve and contribution helpers remain unchanged:

```text
M = max(userMaximum, smoothedPointHR)
q = clamp((HR - restingHR) / (M + 3 - restingHR), 0, 1)
q <= 0.3 => zero contribution
weight = 16 / (exp((1-q)/0.15) + 1) * durationSeconds
raw interval = clamp(weight / 691200, 0, 1)
cumulative raw += raw interval
display = recovered step lookup(cumulative raw)
```

The cumulative total is not clamped to one. The lookup saturates at 21.0 at its final raw threshold.

## Explicit local duration and state differences

The Android smoother starts **at** the exact prior `lastUsed` index, re-emitting that point. The retained singleton duration expression is `j == -1 ? 1 : min(j - timestamp/1000, 3)`, mixing the terminal timestamp with an integer-divided timestamp. The multi-point branch instead uses seconds between adjacent timestamps and a terminal duration, capped above at three seconds. Passing the smoother's last-used time normally makes the final multi-point duration zero. On a first singleton at a modern epoch timestamp, the literal helper can produce three seconds, followed by another credit when that same point is re-emitted in a later multi-point call. This is a static source consequence; actual startup timing and runtime impact have not been observed.

The existing `StrainCalculator.durationScales` and `rawContribution` preserve the literal singleton expression. **The live engine deliberately does not invoke that singleton expression.** It advances a cursor to the next unprocessed center, retains one pending smoothed point, and bills that point once when another mature center supplies its observed following interval. Duration is the real positive millisecond difference divided by 1000 and capped at three seconds. There is no terminal extrapolation, synthetic sample, repeated leftover contribution, or end-of-session flush. The first possible positive contribution arrives at accepted sample **32**. At a regular one-Hz cadence, 31 points remain pending at steady state; variable cadence changes the time delay because the recovered window is defined in sample counts.

This also means scores are independent of how callers group their ordered deliveries. Android's batch maximum and per-batch clamping can depend on batch size; this local engine scores each mature interval using its own point maximum. It never retrospectively rescales previously accumulated intervals when a new high heart rate arrives.

Only the raw context required by the next 60-point window is retained, plus one smoothed pending point. `bufferedSampleCount` is at most 60 after each append (61 transiently); `pendingSampleCount` is at most 31. Each append sorts at most 60 rates and searches at most 59 gaps, giving bounded memory and O(n) total processing for n accepted samples. `sampleCount` counts accepted inputs; `processedSampleCount` counts billed smoothed points, even if their reserve produces zero strain.

## Verification and remaining unknowns

`LiveStrainTests` independently builds whole-array quantile windows and compares their duration-weighted result with streaming under eight delivery chunk sizes. It also checks known constant-rate totals; exact 30-sample eligibility and the pending endpoint; reserve cutoff and observed maxima; duration capping; duplicate/rounded-zero-interval, reversed, invalid, and 30-second-gap rejection without state changes; literal source gap trim; unchanged singleton helper behavior; and bounded retention over 10,000 samples.

These tests verify the stated local contract. They do not verify the incoming Android timestamp producer, actual strap cadence, controller startup/resume scheduling, feature gates, all profile validations, physiological accuracy, or agreement with Android or cloud scores. No Recovery or sleep-scoring formula is inferred from these helpers.
