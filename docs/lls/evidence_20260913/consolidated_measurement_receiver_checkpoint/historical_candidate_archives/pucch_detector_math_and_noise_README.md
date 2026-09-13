# Format-0 detector math and retained noise-plane audit — 2026-09-13

Neither audit qualifies the receiver, the 12 dB scenario, or 3GPP conformance.
No detector threshold, ACK bit, waveform, power/noise parameter or primary KPI
was changed. All three MATLAB suites continue with unchanged source checkouts.

## What the new evidence establishes

The retained configuration has one PRB, two OFDM symbols, two receiver branches,
HARQ-only layouts of one or two bits, and threshold 0.42. The threshold belongs
to the two-symbol resource, not to the number of HARQ bits.

An independent CSV recheck confirms the original results:

| Layout | False detections / occasions | False ACK bits / bit opportunities |
| --- | --- | --- |
| One-bit HARQ | 8 / 512 | 2 / 512 |
| Two-bit HARQ | 16 / 512 | 12 / 1,024 |

The cases score the same 512 IQ captures; they are not independent repetitions.
The two-bit empirical false-ACK fraction remains 1.171875%, above the unchanged
1% requirement. Signal-present missed ACK is still unqualified.

## Independent mathematical model, not replacement PHY data

The documented receiver compares a maximum normalized reference correlation to
a threshold. The installed R2026a implementation averages correlation magnitudes
across symbol/antenna blocks. Its source is SHA-identified in audit.json but is
not redistributed. See the [MathWorks nrPUCCHDecode reference](https://www.mathworks.com/help/5g/ref/nrpucchdecode.html).

Our derivation assumes independent circular white complex-Gaussian noise and
orthogonal HARQ-only reference hypotheses. For each length-L block, unit-vector
projection energy divided by total noise energy has distribution Beta(1,L-1).
Thus the normalized correlation magnitude R satisfies P(R <= r)=1-(1-r^2)^(L-1).
Here L=12 and the existing metric averages M=4 such magnitudes per hypothesis.

Discretized CDF convolution with explicit quantization bounds gives a
single-hypothesis exceedance probability between 0.00881483 and 0.00883532 at
threshold 0.42. A separately generated two-million-occasion Dirichlet null model
agrees with this bound within its reported 99.9% binomial interval. The model is
seeded mathematical test data, NOT an RF waveform run or truth KPI table.

The two-bit/four-hypothesis model yields detection probability 3.5187% and false
ACK bit fraction 1.7594%. Exchangeability of the winning labels predicts half the
detection probability per ACK bit. Its 99% binomial prediction interval is 8–30
false detections in 512 occasions, containing the observed 16. The one-bit model
yields approximately 0.8749% false-ACK bits.

This is evidence that the fixed setting can exceed 1% even under an idealized
noise model; a counting correction alone is not a detector qualification fix.
It does not select a new threshold. Any receiver-policy change needs independent
noise and signal-present qualification, including the actual AGC, layout,
receiver branches, timing hypotheses and enabled channel/RF impairments.

CDF and interval computations use the installed
[SciPy 1.13.1 beta-distribution API](https://docs.scipy.org/doc/scipy-1.13.1/reference/generated/scipy.stats.beta.html).

## Actual saved IQ: power planes and AGC

The raw-IQ audit verified the retained MAT file SHA and read all 3,932,160 complex
samples on each of two branches in bounded-memory chunks. Recorded post-RF
centered powers are 0.23873529 and 0.23863643, versus declared pre-RF injected
variance 0.0001232338563. Their roughly 1,937-fold ratio compares DIFFERENT planes;
it is not itself evidence of additional injected noise.

The saved configuration enables hardware AGC with target RMS 0.5. The final
receiver replay confirms one applied RF stage, AGC applied causally with
time-varying gain. The final captured occasion has exact recorded sample gains
32.0152–33.4136 dB. Dividing only that retained post-RF IQ by its recorded
per-sample amplitude gains reproduces the separately recorded pre-RF powers
0.0001240211825 and 0.0001240412202 with relative errors below 1.1e-15.
This inverse calculation is audit-only; no practical decoder receives it.

Exact gain accounting covers only 1 of the 512 occasions because only the final
complete replay was retained. Do not claim all-occasion gain/noise closure. The
small branch/lag correlations and near-Gaussian fourth moments are descriptive
checks, not proofs of independence. Time-varying AGC makes the ideal IID null
model an approximation to this captured receiver, not an exact replay.

For full measurement closure, retain the actual pre/post-RF samples or exact
per-sample stage/gain evidence for EVERY qualification occasion, then check
noise and desired-signal accounting at matching planes. Do not substitute the
injected pre-RF variance for post-RF receiver noise estimates.

## Files and validation status

- audit_pucch_format0_null.py and pucch_format0_null_audit_01/audit.json: executed,
  exit 0; count recheck plus independent mathematical consistency checks.
- audit_retained_noise_covariance.py and pucch_noise_covariance_audit_02/audit.json:
  executed, exit 0; full IQ moments and exact final-occasion AGC accounting.
- The earlier covariance-only audit_01 and its exact v1 script are preserved.
- Source receiver evidence remains under docs/lls/evidence_20260913/
  pucch_baseline_noise_rf_01 in the type2 runtime checkout. The evidence bundle
  copies configuration, final replay, CSV counts and provenance, and identifies
  the large retained IQ file by SHA; it does not duplicate that IQ payload.

These audit scripts are outside the live source checkouts. No new MATLAB suite
was launched under the present memory pressure. The separate 21-file integrated
feedback/CSI/preview candidate remains staged and runtime-unvalidated; these
audits do not replace any required final-source regression or 12 dB gate.
