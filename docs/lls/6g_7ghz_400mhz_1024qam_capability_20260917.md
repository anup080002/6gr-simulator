# Requested 6G capability: 7 GHz, 400 MHz, TDD, DL/UL 1024-QAM

## Scope and status

User reprioritized on 17 September: stop bug repairs, finish the already
running 5 MHz / 12 dB diagnostic, then work on this new capability. Existing
unfinished mixed-feedback edits are preserved; they are not verified or
included in the frozen diagnostic. No existing acceptance assertion, noise
level, detector threshold or transmit power is to be changed to obtain a pass.

The preconfigured research lab link now executes; the requested fully
qualified/best-throughput capability is **not complete yet**. This is an
explicit 6G research experiment, not an assertion of standardized 6G behavior.
Retain the requested 7 GHz center frequency; do not substitute 28/30 GHz or
mislabel the carrier as FR2/FR3 just to pass NR bandwidth validation. Retain
the requested SINR-sweep style operating point, not geometry-controlled noise.
Use the established configured reference-Es/N0 authority and separately export
measured reference/post-equalization SINR. Initial requested operating point
from the preceding request is 30 dB; preserve the later sweep
[-30, -20, -10, 0, 10, 20, 30, 40] dB.

## Existing capability and verified source boundaries

### Selected-source regression failure (17 September, observed 14:42 IST)

The unfiltered suite on `6be2985f9f6b78b4349c91ab71da81f32e25f7c8`
has a confirmed **`testResearchTDDLink` failure** (123.20 seconds):
`MATLAB:table:UnrecognizedVarName`, `ClippedComponents`, at test line 33.
The preceding line uses `readtable` without an explicit CSV delimiter.
The original CSV contains that column; independent comma-delimited parsing
reads eight rows with zero clipped components. This establishes an import/
table-access failure, not a missing column in the exported file. Automatic
delimiter detection is the leading explanation, consistent with the earlier
selected-capture verifier issue; its inferred delimiter has not been inspected
in this failed test's MATLAB workspace.

The native 1 ms fixture manifest records completed execution and 7/7 successful
transport blocks. Assertions after the failing table access were not executed;
this run must not be relabeled as a passing test. It is separate from the
previously completed 10 ms, rate-0.82 capture. Original manifest and CSV receipts
are preserved in `evidence_20260917/research_tdd_test_csv_failure`.

On this same source, research carrier, coded UL, coded DL and rate-matrix
configuration tests passed. The full suite continues after the failure; there
is no terminal full-suite verdict yet. No source/test repair, threshold change,
or rerun was made, respecting the instruction not to fix bugs. The narrow
prospective repair is to make the test's CSV import explicit, then rerun its
unchanged assertions; that repair is not implemented or verified here.

### Completed focused-regression checkpoint (17 September, 13:29 IST)

All **21 focused guards passed** on immutable source
`3f0ed1e4ae7debe3d4136c733fd2dcce4d2e4b40` (MATLAB R2026a Update 4,
8,488.69 seconds). Coverage includes research carrier/DL/UL/TDD components,
configuration and scenario runners, DL/UL reference points, strict proxy
guards, scheduler grants, exports/artifact preservation and both required
E2E truth/proxy tests. The summary, per-test results and zero-failure report
are retained in `evidence_20260917/checkpoint_3f0ed1e4_focused_guards`.

This source predates the rate-comparison profile and later selected-rate
YAML additions. It is not a final-source full-suite result, R2023b
qualification, detector qualification, or a change to the failed 12 dB
acceptance verdict. Its queued unfiltered `testAll` began at 13:29 IST in
the same existing process. The selected-capture source `6be2985f` also
continues its own unfiltered suite; no new MATLAB process was launched for
this checkpoint transition.

### Selected capture operating point (17 September, 11:55 IST)

The intermediate **rate 0.82 passed 30/30 DL and 40/40 UL TBs** over 80
slots / 10 ms from clean commit `15aa291cc7115519e6cdfd7de59276f907f98350`.
Native allocation produced 622,760 information bits per TB. Actual delivered
goodput is **1.868280 Gbit/s DL, 2.491040 Gbit/s UL**, or 4.359320 Gbit/s
combined over the full TDD clock. This is the highest passing tested point
among rates 0.75, 0.80, 0.82, 0.85 and 0.90 for the fixed two-layer setup.

Rate 0.85 completed with 6/30 DL and 5/40 UL TBs correct (observed BLER 0.8
and 0.875); its actual goodput fell to 0.3833904 / 0.319492 Gbit/s. Rate
0.90 subsequently completed with 0/30 DL and 0/40 UL TBs correct: observed
BLER is 1 in both directions and delivered goodput is zero. The completed
four-rate comparison and independent accounting receipt are retained in
`evidence_20260917/research_rate_matrix_10ms`. Execution completion does not
mean all candidates passed. The original four-rate
matrix excludes the later refinement point and therefore selects 0.80;
the independent 0.82 run provides the additional selection evidence.

A read-only native allocation audit subsequently sampled 301 rates from
0.82 through 0.85 in each direction, keeping the executed allocation fixed.
Rates 0.8200--0.8296 on that grid all map to 622,760 TB bits; rates
0.8297--0.8500 map to 638,984 bits. Increasing the nominal rate within the
first group therefore cannot increase this run's already error-free payload
goodput. The next sampled TB size equals the executed failing 0.85
candidate's size. Native rate recovery was identical at each group's sampled
endpoints using a synthetic position-label probe (not received LLRs).
This is allocation/coding evidence only: no additional waveform trials,
continuous-range optimum, or reliability qualification is claimed. MATLAB
exited 0; the script and output are retained as `audit_rate_quantization.m`
and `rate_quantization.log` in `evidence_20260917/research_selected_iq_10ms`.

`lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml` repeats the selected
point with full-frame IQ capture, playback export, plots and strict all-TB
success enabled. It changes only output/acceptance flags and scenario
identity, not PHY/noise/decoder settings. The capture reruns the actual
waveforms and receiver; it does not reuse a pass flag or fabricate samples.
The capture completed from immutable commit
`6be2985f9f6b78b4349c91ab71da81f32e25f7c8`, with native manifest
`Status=completed`, `ResultOk=true`, and **70/70 TBs correct**. Its 58-file,
804,357,388-byte package is under
`logs/research_selected_iq_6be2985f_20260917/execution/lls/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq/committed_source`.
All eight TX/RX port streams contain 4,915,200 samples. Exact raw MAT and
playback-file readback passed in the exporter; clipping is zero. Independent
PowerShell verification passed all 20 unique file hashes, eight WIQ lengths
and VSA MAT headers, 80 contiguous TDD slots, 11,057,920 inactive zero TX
samples, 180 inactive RX intervals containing noise, and unique-TB goodput.
The 70 same-seed EVM values match the earlier rate-0.82 execution exactly.

The original auxiliary MATLAB verifier failed after capture because
`readtable` guessed `_` as the delimiter and did not recognize the CSV
header. This did not change the native capture verdict. A separate read-only
MATLAB verification specifying comma delimiter and first-line variable names
passed (exit 0), retaining the original sample-count, quantization, CRC,
exact-TB and same-seed metric assertions. Both the original failure and
successful verification are preserved in
`evidence_20260917/research_selected_iq_10ms`; no captured file or PHY policy
was changed. Use explicit CSV options when reading this path-rich manifest.

Unfiltered `testAll` started on the capture source at 12:22 IST, with required
focused guards queued afterward. Final-source full regression and actual
Keysight import remain unverified. A same-seed capture repeat is not an
independent statistical reliability trial. Research/initial-access
limitations remain unchanged.

```powershell
New-Item -ItemType Directory -Path logs/wideband_selected_iq_01 -ErrorAction Stop
matlab -wait -singleCompThread -logfile logs/wideband_selected_iq_01/matlab.log -batch "setup6GRSimToolkit('Verbose',false); r=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml','logs/wideband_selected_iq_01','run_01'); assert(r.Ok);"
```

The source and small measured receipts are on the work branch. Large raw
IQ stays under `logs`; running the command regenerates it on the server.

### Fixed-budget code-rate comparison (17 September, 11:16 IST)

`research_400mhz_rate_matrix.yaml` extends the normal matrix entry point with
an explicit `research_rate_comparison` result profile. Four YAML candidates
use target code rates 0.75, 0.80, 0.85 and 0.90, with unchanged two-layer
400 MHz / 7 GHz TDD, 30 dB reference SNR, unit-total-power precoding and
noise policy. Each executes 80 slots (10 ms), including 30 DL and 40 UL
TB opportunities. Waveforms are still executed when capture is disabled;
the comparison omits bulky IQ files, and the selected operating point must
subsequently be rerun with IQ capture enabled.

Both directions must meet the YAML zero-observed-BLER selection gate.
Negative observations are retained, not converted into passes; the original
strict capture scenario still requires all TBs to succeed. Comparison
completion, all-candidate success and selection availability are separate
states. Ranking uses delivered unique TB bits divided by the full TDD
sample-clock duration, never configured TBS or active-slot-only rates.
An empty qualifying set produces no selected row. The result is best
observed among these configured candidates, not a global optimum or
statistical reliability qualification.

The preflight rejects changed SNR, layer count, physical/timing policies,
duplicate IDs and abort-on-negative-result candidate policies. Focused
configuration/catalog validation exited 0 (2/2 tests, 34.34 s), with logs
under `logs/research_rate_matrix_config_20260917`. At this checkpoint the
new comparison runtime has not yet completed, and final-source regression
is pending. Existing frozen-source regressions do not qualify this new
matrix profile.

First completed candidate: rate 0.75 executed all 80 slots / 10 ms from
clean commit `91046b231f28449dea7961906a01e60deb6d648e`, with **30/30 DL
and 40/40 UL TBs correct**. The 4,915,200-sample clock gives the same
1.720512 Gbit/s DL and 2.294016 Gbit/s UL goodput as the one-ms observation.
Receipts are in `evidence_20260917/research_rate075_10ms`. This is one of
four candidates, not a final winner or statistical BLER qualification;
the remaining candidates continue in the same live process.

Rate 0.80 subsequently also completed 70/70 TBs correctly over 10 ms:
**1.819512 Gbit/s DL and 2.426016 Gbit/s UL**. The saved resolved configs
for 0.75 and 0.80 differ only in target code rates and scenario/provenance
identity. Rate 0.85 has produced real CRC failures in both directions; its
remaining observations and rate 0.90 continue without modifying the run.
`research_400mhz_rate082.yaml` adds one intermediate 10-ms point through
configuration only; no PHY, decoder, power or noise policy changes are made.
It is not declared passed or selected before execution. The completed rate
0.75 run's EVM-equivalent receive SINR averages 28.4455 dB DL / 28.4489 dB UL;
the configured 30 dB reference SNR is not forced onto that measured metric.

Run the actual comparison on the Windows server from this branch:

```powershell
New-Item -ItemType Directory -Path logs/wideband_rate_server_01 -ErrorAction Stop
matlab -wait -singleCompThread -logfile logs/wideband_rate_server_01/matlab.log -batch "setup6GRSimToolkit('Verbose',false); r=run_6g_phy_lls_matrix('simulator/configs/scenarios/research_400mhz_rate_matrix.yaml','logs/wideband_rate_server_01','run_01'); assert(r.ExecutionCompleted);"
```

Inspect `reports/csv/rate_comparison.csv`, `eligible_ranked.csv`,
`best_observed.csv` and each child run's raw `trials.csv`. A completed
comparison is not an assertion that every candidate passed.

### Integrated research lab checkpoint (17 September, 11:02 IST)

`lls_7ghz_400mhz_1024qam_tdd_30db.yaml` now uses the normal
`run_6g_phy_lls_single` entry point with the explicitly separate
`research_tdd_link` profile. Actual coded DL and UL share one continuous
eight-slot TDD clock. A two-layer, code-rate-0.75, 1024-QAM run passed all
seven TB CRC/exact-payload checks (three DL, four UL). The complete 491,520
sample interval at 491.52 Msamples/s is 1 ms, including the unused mixed
slot. Observed delivered goodput is 1.720512 Gbit/s DL and 2.294016 Gbit/s UL.

The channel is explicitly normalized identity AWGN: 30 dB refers to expected
data-RE energy per port after the unit-total-power precoder divided by grid
noise variance. It is not forced post-equalization SINR or geometry-based
power. DMRS-based reception uses only configured scheduling and received
IQ. RMS receive EVM was 0.0377561–0.0379933; BER was zero for these seven
TBs only. This is not a statistically qualified BLER result.

Continuous clean TX and noisy RX captures are separately labeled for both
directions and both ports. Exact raw floating-point MAT files, normalized
per-port VSA MAT and interleaved little-endian int16 WIQ files passed
readback checks; clipping was zero. `exportLabIQ` is distinct from the
full-stack TX recorder because this lab runner must not claim the latter's
shared physical RF replay provenance. No physical Keysight import occurred.
The 7 GHz value is carrier metadata, not simulated passband upconversion.

Evidence: `evidence_20260917/research_tdd_link_30db`. The entire 55-file,
80,893,047-byte package is preserved under
`logs/research_tdd_link_v2_20260917/artifacts` with zero SHA256 mismatches;
the original remains intact. Focused MATLAB validation exited 0, 2/2 tests
passed in 111.72 s. The first attempt's new-runner struct initialization
failure remains in `logs/research_tdd_link_v1_20260917`; no assertion was
weakened. This observation used the dirty development tree over `1cb4eaad`.
The subsequent checkpoint adds runner return-contract/provenance fields;
committed-source execution and complete regression are still required.

Follow-up at 11:08 IST: execution from clean, frozen commit
`3f0ed1e4ae7debe3d4136c733fd2dcce4d2e4b40` completed successfully with
`GitDirty=false`, 7/7 exact TBs, the same DL/UL goodput and completed IQ
exports. Receipts are in `evidence_20260917/research_tdd_link_committed_30db`.
The full package is directly under
`logs/checkpoint_3f0ed1e4_validation_20260917/execution/lls/lls_7ghz_400mhz_1024qam_tdd_30db/committed_source`.
That frozen checkout is now running the required guards, followed by the
unfiltered `testAll`; neither regression stage has a final verdict yet.
The separate older `cef38516` validation remains running and cannot qualify
these newer feature changes.

Explicitly disabled/unexecuted: initial access, PDCCH/PUCCH, CSI/SRS,
HARQ/UCI, acquired timing, RF impairments, AI and energy accounting. Legacy
NR data MCS/coding/MIMO fields do not own this profile's allocations;
`research_dl` and `research_ul` do. Existing 12 dB acceptance failures remain
untouched. Candidate-rate/layer search for best observed throughput, longer
qualification, final-source full regression, and actual Keysight import
remain pending. The complete requested SNR grid remains in YAML; this
single-run profile executes only `simulation.snr_db`.

Windows PowerShell, from the checked-out repository (use a new tag):

```powershell
git pull --ff-only origin work/tdd-normalized-ssb-20260914
New-Item -ItemType Directory -Path logs/wideband_30db_server_01 -ErrorAction Stop
matlab -wait -singleCompThread -logfile logs/wideband_30db_server_01/matlab.log -batch "setup6GRSimToolkit('Verbose',false); run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db.yaml','logs/wideband_30db_server_01','run_01');"
```

R2023b compatibility remains unverified; preserve and share the entire log
folder if the server rejects an API. Do not bypass failed guards.

### Research UL implementation checkpoint (17 September, 10:34 IST)

Follow-up at 10:43 IST: shared coding/receive mechanics now live in
`+sixgr/+phy/+research/SharedChannelLink.m`; `PUSCHLink` remains the explicit
UL entry point. `research_dl` adds native PDSCH 1024-QAM modulation on the
research carrier without claiming connected NR capability negotiation.
Both full-width two-layer DL and UL component tests pass at 40 and **30 dB**
configured reference Es/N0, with exact TB recovery. At 30 dB the receiver
RMS EVM was 3.77308% DL and 3.79169% UL. The UL wrong-receiver-RNTI test
correctly rejected the payload. These are single-slot component observations,
not statistically qualified BLER, integrated TDD throughput or TX EVM.
The parameter catalog test also passed: **3/3 tests, MATLAB exit 0**.
Logs: `logs/research_dl_ul_30db_components_20260917`; small receipts:
`docs/lls/evidence_20260917/research_dl_ul_30db_components`.

`+sixgr/+phy/+ul/+research/PUSCHLink.m` now provides explicitly opted-in
research allocation, coded transmission and independent scheduled reception.
The YAML surface is `research_ul`, with reusable settings in
`simulator/configs/coding/research_ul_1024qam.yaml`. It reuses the repository
CRC/LDPC/rate-match and canonical OFDM functions. Native PUSCH supplies only
RE and DMRS geometry; its QPSK G/TBS and native data coder/decoder are never
used as the research payload. Actual G and TBS use configured Qm=10. Outputs
retain `StandardNR=false`; the ordinary NR UL modulator still rejects 1024-QAM.

The full-width 264-PRB, two-layer, 400 MHz UL component test passed (MATLAB
exit 0): G=760320 bits, TBS=573504 bits, exact recovered TB and passing CRC,
EVM=0.0120131 (1.20131%). This first component test used a 40 dB reference
Es/N0 point and identity AWGN channel, not the requested final 30 dB point.
Measured DMRS noise variance was 5.23942e-5 versus injected grid variance
4.99195e-5. The fixed identity precoder has unit Frobenius-norm squared;
noise is transformed using the measured OFDM noise gain, not a power boost.

The receiver takes only resolved config, absolute slot and received IQ; it
rebuilds the allocation and DMRS, estimates a per-resource channel/noise,
equalizes and decodes. Timing is explicitly a preconfigured lab boundary.
UCI, HARQ and transform precoding are explicitly disabled/unsupported in
this research component, not silently bypassed. No integrated TDD, DL,
Keysight playback, fading qualification or throughput acceptance is claimed
by this component test. Logs: `logs/research_ul_coded_waveform_20260917`;
small receipts: `docs/lls/evidence_20260917/research_ul_coded_waveform_40db`.

- `+sixgr/+phy/+frame/CarrierGridConfig.m` already provides an explicit
  `custom` API with nonstandard provenance and occupied-bandwidth checks.
  Candidate geometry: 264 PRBs, 120 kHz SCS, 380.16 MHz occupied bandwidth
  inside a 400 MHz channel, with a 4096-point FFT at 491.52 Msamples/s.
  These are proposed experiment settings, not a normative 7 GHz NR profile.
- `frequency.research_mode` now exposes the existing research-grid opt-in
  through the YAML catalog, scenario validator and internal config adapter.
  The frame carrier/BWP objects retain explicit CUSTOM/nonstandard provenance;
  the source band fragment still names the physical 7 GHz range as FR1.
- `+sixgr/+phy/+ul/+pusch/PUSCHModulator.m` explicitly rejects 1024-QAM.
  `PUSCHMCSResolver.m` supports only the existing NR qam64/qam256/low-SE tables.
- `+sixgr/+phy/+ul/PUSCH_Tx.m` uses native PUSCH configuration, indices,
  UL-SCH encoding, TBS and modulation. Changing one modulation enumeration
  would not add an end-to-end coded research uplink.
- Existing DL paths and generic NR symbol functions include 1024-QAM support,
  but this does not qualify the requested wideband bidirectional scenario.

Official capability reference: [MathWorks nrPUSCHConfig](https://www.mathworks.com/help/5g/ref/nrpuschconfig.html)
lists up to 256-QAM; [nrSymbolModulate](https://www.mathworks.com/help/5g/ref/nrsymbolmodulate.html)
documents 1024-QAM since R2023a. MATLAB R2023b compatibility must be checked
on that server, not inferred from the local R2026a installation.

## Implementation boundaries and test order

1. YAML catalog/defaults: explicit custom-carrier and experimental-UL policy;
   scenario class `optional_research_experiment`; bandwidth/frequency/SCS/grid,
   modulation, coding-rate definition, reference-SNR sweep and output controls.
2. Validation and `buildInternalConfig`: carry custom grid provenance through
   the existing frame/grid path. Preserve standard NR rejection behavior.
3. Experimental UL: explicit Qm=10 coding/TBS/rate-matching, modulation and
   soft-demodulation ownership, resource accounting, layer mapping, DM-RS and
   optional UCI. Do not use a dummy 256-QAM configuration to export Qm=10 TBS,
   G, grant or decoder results. Keep standard PUSCH unchanged.
4. Components: exhaustive symbol mapping/demapping and normalization; coded
   TX/RX round trips; exact RE/G/TBS accounting; per-resource fading-channel
   estimates and EVM; independent DL/UL checks. No arbitrary power injection.
5. Short wideband DL and UL waveform runs, then the integrated TDD scenario.
   A successful run must actually transmit 1024-QAM in both directions; an
   adaptive downgrade is not acceptance of this requested capability.
6. Required configuration/PHY/integrity tests and final-source `testAll`,
   then R2023b execution and the requested sweep. Preserve failed-run logs.

Capability probes are under `logs/6g_7ghz_400mhz_1024qam_capability_20260917`.
They inspect APIs and the constellation only; they are not link-run evidence.

## Executed capability probe: 17 September, 09:30 IST

On source `f8dddfeddf594f5a39999c75e2d706df84cae2c7`, MATLAB
R2026a Update 4, the probe exited **0**. This is a capability inspection,
not a waveform-link acceptance test:

| Check | Observed result |
| --- | --- |
| Native PDSCH `1024QAM` configuration | Accepted |
| Native PUSCH `1024QAM` configuration | Rejected: `MATLAB:nrPUSCHConfig:Modulation:unrecognizedStringChoice` |
| Repository strict UL modulation `1024QAM` | Rejected: `sixgr:pusch:UnsupportedModulation` |
| Standard FR1, 400 MHz, 120 kHz grid | Rejected: `sixgr:phy:frame:UnsupportedBandwidthSCSCombination` |
| Explicit custom 7 GHz, 400 MHz, 120 kHz, 264-PRB grid | Accepted |
| All 1,024 constellation points, hard-decision round trip | Exact bit equality |
| Exhaustive constellation mean energy | 0.99999999999999956 |

Probe log SHA256:
`38020BD2F045FCDEE378189E2E8DD6AD4582375EECF62189474E3AD75C8AE6E8`.
The preserved text log is
`docs/lls/evidence_20260917/wideband_capability_probe/matlab.txt`.
No 400 MHz channel, coded UL transmission, 30 dB link or throughput result
was executed by this probe. R2023b remains unverified. The next implementation
boundary is the explicit YAML-to-runtime custom carrier and experimental
coded Qm=10 uplink described above; the strict NR rejection must remain.

## Implemented frame component: 17 September, 10:09 IST

Follow-up at 10:24 IST: the full scenario loader and `buildInternalConfig`
translation also pass in `testResearchCarrierRuntime` (MATLAB exit 0,
26.84 s test execution). The carrier fragment now owns coherent derived
timing aliases: mu=3, 0.125 ms slots and 80 slots/frame. The explicit
configuration-only fixture is `tests/fixtures/research_carrier_config_only.yaml`;
it disables initial access, SSB/PBCH and PRACH. It does not execute a waveform
or establish a connected link. The test also retains the rejection of enabled
NR SSB timing on a CUSTOM carrier; no automatic signal disabling was added.
Failed full-config and malformed-fixture iterations remain under
`logs/research_carrier_full_config_20260917` and
`logs/research_carrier_lab_config_20260917`; passing evidence is under
`logs/research_carrier_lab_config_v2_20260917` and the small tracked receipt
`docs/lls/evidence_20260917/research_carrier_full_config`.

Required guards followed by unfiltered `testAll` are running on the immutable
`cef3851621cfaa27d7362cbe7664ae2e33217b77` checkpoint in the separate validation
worktree, with logs in `logs/checkpoint_cef38516_validation_20260917`.
The original launcher failed before any tests because MATLAB `run` changed
directory; its log is retained and the retry explicitly selects the checkout.
That checkpoint run does not cover the later full-config fixture/timing-alias
addition, and is not a final-source or 400 MHz link qualification.

`simulator/configs/bands/band_7ghz_400mhz_research.yaml` is a reusable band/frame
fragment, not yet a complete runnable bidirectional 1024-QAM scenario. It
declares the research opt-in, TDD pattern, 264 PRBs at 120 kHz, 4096-point FFT,
491.52 Msamples/s and 9.92 MHz minimum guardband on each side. All values are
YAML-owned. The existing frame engine is reused; no parallel frame engine
or standard-FR1 bandwidth exception was introduced.

The new carrier/BWP runtime support preserves `ResearchMode=true`,
`StandardNR=false`, the CUSTOM runtime label, guardbands and independent
DL/UL BWP identities across serialization/reconstruction. Standard-mode
400 MHz FR1 rejection and opt-in rejection remain enforced; the new runtime
support is TDD-only. Scenario validation requires the explicit
`optional_research_experiment` classification.

Focused MATLAB validation exited **0**, **4/4 passed**:
`testResearchCarrierRuntime`, `testTransmissionBandwidthCatalog`,
`testFrameStructureEngine`, `testFrameRuntimeStateBuilder`.
Receipts are in `evidence_20260917/research_carrier_runtime` and full local
logs in `logs/research_carrier_runtime_20260917`. The new test is registered
in `testAll`. Earlier failed iterations (missing explicit guardbands, then
missing internal TDD reference-clock wiring in the new test fixture) remain
preserved under the corresponding `logs/research_carrier_frame*` folders.

This proves the YAML fragment -> frame/OFDM resolver -> carrier/BWP runtime
component path. Full resolved research-scenario construction and execution,
coded Qm=10 UL, complete regression, final wideband IQ, measured 30 dB link
performance and throughput remain unfinished. Existing 12 dB defects were
not repaired by this feature work.

## Keysight IQ deliverable

Reuse `run_control.continuous_raw_iq_capture_enable` and the existing sealed
shared-clock capture. Preserve both DL and UL physical antenna streams after
waveform composition/TX RF and before propagation, including intentional TDD
silence and original sample indices. Keep the original floating-point samples.
The existing `sixgr.truth.exportContinuousKeysightPlaybackPackage` can create
headerless I/Q CSV, little-endian interleaved signed-int16 WIQ, and per-port
89600 VSA MAT (`Y`, `XDelta`, `InputCenter`, `InputZoom`, `XDomain`) in a separate
output directory. Reuse it rather than reconstructing IQ from constellation
points or repeating one slot.

Acceptance must retain sample rate, 7 GHz center frequency, source and output
SHA256 values, port synchronization, sample extent, common per-transmitter
playback scale and quantization-error/clipping checks. Playback normalization
is a documented file-format conversion, not additional simulated TX power or
a change to the captured floating-point reference. Actual Keysight software
import/demodulation remains separate from file-generation verification.

These are transmitter-output samples, captured before the channel. They do
not contain receiver noise or embed the requested 30 dB received operating
point. Any received-IQ delivery must use a separately identified receiver
capture; do not label pre-channel TX IQ as a 30 dB received waveform.

### Executed baseline export preflight

The existing exporter was exercised on 17 September against the sealed
**5 MHz / 2.35 GHz** failed-run capture from `68140bb9`, using exporter source
`363465d9bf335429fd7d8b5b3d219c62e62a9984`. MATLAB exited **0**. All four
physical antenna streams (two DL, two UL) produced CSV, WIQ and VSA MAT
files; source hashes and format readback were checked by the exporter.
Each stream retains 445,440 samples at 7.68 Msamples/s. All int16 clipped
component counts are zero; maximum complex quantization error is about
2.16e-5 in the documented normalized playback domain.

The local package is under
`logs/keysight_5mhz_baseline_export_20260917/package`. Its small manifest
and console evidence are preserved in
`docs/lls/evidence_20260917/keysight_baseline_export`.
This verifies the existing file packaging path only: the source scenario
failed overall, no 400 MHz waveform was generated, and no physical
instrument/software import was executed. Do not promote this baseline
package as the requested wideband result.

The latest requested first operating point is explicitly **30 dB**, with the
objective of high bidirectional throughput. Compare useful successfully
decoded TB bits over both the full TDD wall-clock interval and each direction's
active allocation time; do not present the latter as full-run goodput. Keep
retransmissions, control/pilot/guard overhead, configured rank, achieved rank,
MCS/code rate, BER/BLER and actual modulation visible. A 1024-QAM label alone
does not guarantee best throughput or an error-free result at 30 dB.
