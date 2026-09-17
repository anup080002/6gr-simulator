# PUCCH invalid-evidence repair: runtime validation pending

Development parent: `74889f1bf40bf3b26387c1561f0b850c2f703ab7`.
This document describes uncommitted follow-up source, not that commit's behavior.

## Two production defects

1. `PUCCHDetector.decide` accepted invalid observation metrics whenever the
   decoder returned nonempty bits. Candidate bits are not detection evidence.
2. Before that decision, `PUCCHReceiver.receive` replaced an invalid Format-0/1
   sequence metric with the energy metric. For example, a NaN sequence metric
   with an energy ratio of 99 became 0.98 and could pass the configured threshold.
   Fixing only `decide` therefore left this upstream rescue intact.

## Minimal production repair

- Move existing metric selection into `PUCCHDetector.selectMetric`, called by
  the actual receiver. Preserve the existing finite sequence/energy formula.
- A required invalid sequence metric remains invalid. Invalid or negative
  energy ratios remain unavailable, including at a zero detection threshold.
- Noncoherent Format 0 still uses only its sequence metric; no energy gate is
  added. The existing long-format energy policy is unchanged, not qualified.
- `decide` rejects invalid evidence regardless of candidate bits, requires an
  explicit valid threshold, and exposes `DetectionMetricValid` through RX.
- No samples, channel estimates, noise/power inputs, YAML thresholds, original
  false-ACK assertions, sample counts or confidence gates are changed.

The toolbox metric is format/payload dependent; blindly replacing every
long-format policy with that metric is not part of this repair. See
[MathWorks nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html).

## Evidence and remaining tests

`testPUCCHDetectorEvidence` is registered in `testAll`. It contains 300 invalid
metric decisions, 875 finite boundary decisions, 65 policy rejections, and 227
selection cases using the same method as the production receiver. These are
authored cases, **not executed passes**. They are not RF qualification.

Standalone R2026a Code Analyzer found no syntax errors in the two production
files, new test, and testAll; existing receiver/testAll style warnings remain.
`git diff --check` passed. On 16 September at approximately 21:04 IST, all four
older suite engines (6248, 8548, 19036, 26104) were still live and the machine
reported only 144 MB available physical RAM. No additional MATLAB engine was
started, and no existing engine was stopped.

Next: run the pure detector test, retained-IQ receiver comparisons, required
unfiltered final-source `testAll` and NR guards after memory is available.
The original 12/1024 false-ACK failure and the retained finite-metric false CSI
(0.2384850435968231 against 0.2) remain open; this patch does not resolve either.
No 5 MHz/12 dB acceptance or R2023b qualification is claimed.
