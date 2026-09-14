# Model-derived detector development candidate, not qualification

## Decision and scope

The original retained 12 false ACKs / 1,024 bits failure at threshold 0.42
remains a failure. Independent replay matched the existing correlation metric;
the noise-tail policy, not a changed counter, needs development.

A separate two-symbol Format-0 candidate uses threshold **0.77**. Production
defaults, the baseline 12 dB/sweep configuration, original assertions and
receiver implementation remain unchanged. The new scenario inherits the
baseline signal fixture and overrides only this receiver threshold and metadata.
No RF power, noise, channel, timing, coding or decoder iteration value changes.

The candidate pilot retains the original development seed and case calendar
for a paired comparison. It is not a new independent qualification episode.
Neither this candidate nor the baseline is claimed statistically qualified.

## Derivation, with explicit assumptions

The API describes maximum normalized reference-correlation thresholding:
[MathWorks nrPUCCHDecode](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html).
The retained implementation audit additionally established the mean of
per-symbol/per-branch correlation magnitudes. That latter detail comes from
the local audit, not an assertion that the API page specifies the combining rule.

Our mathematical model assumes circular white complex-Gaussian noise within
each length-L resource block. For a fixed unit reference direction, normalized
projection energy U has Beta(1,L-1) distribution: a unitary rotation makes
the numerator one exponential component and the denominator the sum of L
independent exponential components. For magnitude R=sqrt(U),
P(R >= t)=(1-t^2)^(L-1).

If a candidate's mean of B nonnegative magnitudes exceeds t, at least one
block exceeds t. A union bound over H hypotheses and B blocks therefore gives
P(false detection) <= min(1, H*B*(1-t^2)^(L-1)). No independence between
blocks or hypotheses is needed for this bound; whiteness within each block
is still an assumption. False ACK is a subset of false detection.

The declared model uses L=12, B=2 symbols * 2 receive branches, H=4.
The engineering target 0.001 is a conservative design margin, NOT a 3GPP
requirement or a changed physical acceptance gate. Solving the bound gives
0.7650033068912473; upward rounding to two decimal places gives 0.77 and
model bound 0.0008143893934884291. The executable derivation reads only
the authored model policy, never trial outcomes. It generates no noise or RF
episodes. The receipt explicitly labels analytical origin and qualification=false.

## What has actually run

The Python derivation and its monotonicity/malformed-policy checks exited zero.
The receipt is in `evidence_20260914/detector_analytical_design/analytical_design.json`.
Configuration and script hashes are retained. The output is an analytical
design artifact, not a primary PHY KPI or a substitute for measured data.

## Required next evidence

1. Validate the new scenario through the normal MATLAB configuration loader;
   verify exactly the intended threshold change and inherited physical settings.
2. Run the paired eight-case physical pilot using
   `pucch_tdd_detector_model_candidate_pilot.yaml`; inspect receiver usability,
   noise false ACKs and every signal payload/erasure against retained samples.
3. Do not promote this deliberately conservative threshold unless joint
   signal-present and noise-only requirements pass. Time-varying AGC,
   nonwhite interference, acquisition and fading can invalidate the ideal
   within-block assumption or hurt sensitivity. The original 1% physical
   error limits and predeclared confidence gates are unchanged.
4. Freeze source, configuration, receiver policy and disjoint held-out seeds
   before the full independent physical campaign. Its runner and qualification
   remain pending, as do required full regressions and integrated 12 dB.

No physical candidate run has started; three older MATLAB suites are still
using their frozen sources. No FDD repair is included.
