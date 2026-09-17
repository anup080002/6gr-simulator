# Measured 400 MHz adaptive 5-DL / 2-UL outcome

## Verdict

The user-approved attempt completed on 18 September 2026. Payload delivery
passed; the separate **DL >6 Gbit/s goal did not pass**. No settings, decoder,
power, seed or acceptance thresholds were changed during execution. No rerun
was selected to replace this observation.

- Executed source: `ef799fcb13c44f8f407c3b94c15ba09e59f2f5bc`, clean `main`.
- MATLAB: R2026a; seed: 20260920, distinct from both calibration campaigns.
- Scenario: `simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml`.
- Output: `results/lls/lls_7ghz_400mhz_adaptive_dl5_ul2_30db/committed_ef799fcb`.
- Log: `logs/research_adaptive_dl5_ul2_20260918/execution_ef799fcb.log`.
- Terminal marker: `DL5_UL2_EXECUTION_COMPLETE_CHECK_MEASURED_GOODPUT`.
- Manifest: `Status=completed`, `ResultOk=true`, zero pending/dropped TBs.

## Executed configuration and measurements

7 GHz center-frequency metadata, 400 MHz channel bandwidth, 120 kHz SCS,
264 PRBs, FFT 4096, sampling 491.52 MHz, four physical TX/RX ports. The
identity-AWGN benchmark uses perfect configured-channel CSI, received-DMRS
noise estimation, actual coded data waveforms and explicitly ideal delayed
HARQ/measurement feedback. It is not a standardized 6G conformance result,
physical-control-waveform qualification or a statistical BLER campaign.

The ten TDD periods contain 50 full DL and 20 full UL opportunities.
The full-slot data allocations do not use the mixed slot's partial DL symbols.
The denominator includes all 80 data slots plus four feedback-drain slots:
84 slots, 10.5 ms, 5,160,960 samples per stream.

| Measured quantity | DL | UL |
| --- | ---: | ---: |
| Transmission attempts | 50 | 20 |
| Unique payloads delivered | 49 / 49 | 20 / 20 |
| Delivered unique bits | 62,228,776 | 25,166,880 |
| Full-clock goodput, Gbit/s | 5.926550095 | 2.396845714 |
| First-transmission BLER | 1 / 49 (2.0408%) | 0 / 20 |
| Attempt BLER | 1 / 50 (2%) | 0 / 20 |
| Residual delivery BLER | 0 | 0 |
| Decoded-bit BER across attempts | 4.983881780e-6 | 0 |
| Mean trial RMS EVM | 3.16044% | 3.16129% |
| Mean reference-error SINR, dB | 30.005061 | 30.002728 |
| Pending / dropped TBs | 0 / 0 | 0 / 0 |

Reference-error SINR above is derived from equalized symbols against the
transmitted reference, not an independently acquired feedback SINR. These
are arithmetic means of the exported per-attempt measurements. The reference
noise setting was 30 dB; it was not used to overwrite measured results.

Every executed allocation used four layers. DL used four bootstrap
256-QAM/rate-0.9 initial attempts, 41 1024-QAM/rate-0.85 initial attempts,
four 1024-QAM/rate-0.9 initial attempts and one rate-0.9 retransmission.
UL used two bootstrap 256-QAM/rate-0.9 and eighteen 1024-QAM/rate-0.85 attempts.
Rank 2 remained in the calibrated menu but was not selected in this run.

## Observed DL failure and throughput shortfall

At slot 64, delayed-feedback OLLA had reached a -2 dB margin and selected
1024-QAM/rank 4/rate 0.9. That initial attempt failed CRC. Slots 65--67
passed at the same rate while the slot-64 feedback was still in flight.
At slot 68, the failed payload recovered on its second HARQ attempt. The
later new-data allocations returned to rate 0.85. All successful CRCs also
had exact payload recovery, and the delivery ledger counted each TB once.

The result is 73.449905 Mbit/s (1.2242%) below 6 Gbit/s. At the same finite
horizon, 50 successful rate-0.85 payloads would provide 6.085676 Gbit/s before
bootstrap costs; the four smaller bootstrap DL payloads alone reduce that
arithmetic ceiling to 6.010827 Gbit/s. The observed retransmission cost,
partly offset by four larger rate-0.9 unique payloads, brought the actual
result to 5.926550 Gbit/s. This arithmetic explains the observation; it is
not a substitute for another waveform execution or a guarantee for any
different horizon, allocation or policy.

No active-DL-only denominator, ignored retransmission, changed noise power,
disabled OLLA or relaxed delivery assertion was used to manufacture a pass.
Further throughput work is separate from this completed attempt.

## Artifact audit

The post-run read-only audit passed:

- 16 IQ receipts: four ports at each of DL TX, DL RX, UL TX and UL RX.
- 36 unique raw-MAT/WIQ/VSA-MAT files independently SHA256-verified,
  totaling 1,669,440,933 bytes.
- All streams have 5,160,960 samples at 491.52 MHz and 7 GHz RF metadata.
- Each WIQ has 20,643,840 bytes; no clipped components; quantization error
  within the recorded half-int16-step bound.
- All seven snapshotted execution-source hashes match the repository files.
- 84 timeline rows are contiguous and end at the exact exported sample count.
- Delivery-ledger sums match summary unique bits and full-clock goodput.
- `reports/image/tdd_goodput.png` exists alongside the CSVs.

The exporter also performed exact raw-MAT readback, exact WIQ integer
readback and VSA single-precision readback during the run. Actual import
into a Keysight application has **not** been performed; the IQ receipts
retain `InstrumentImportVerified=false`.

| Evidence file under the output folder | SHA256 |
| --- | --- |
| `reports/csv/summary.csv` | `5fc60b3b5d98ddd76c71299aecc4e890c830596d360d66244407bee1d7829a1a` |
| `reports/csv/trials.csv` | `f75950c86fde79460c95cda3575f55437cf0c57a4d66981d685220c28eea8232` |
| `waveform/iq_manifest.csv` | `6b418a88eb230f4bdf98bb4959dc792ca0bb5502f3f0a983daaf8eac1b496d8c` |
| `meta/manifest.json` | `892c240c851288d84e32e18d5b3d84bdbb35f48346e7a23790964b119aea8b89` |

Large results and logs remain preserved locally in their documented folders,
not committed as Git source. GitHub contains the configuration, runner,
calibration commands, focused tests and this measured outcome. Recalibrate
on another MATLAB version before executing its integrated run.

`testAll` and unrelated fixes remain stopped as requested. The older 5 MHz /
12 dB execution finished but failed its separate acceptance; this 400 MHz
payload pass does not change that result.
