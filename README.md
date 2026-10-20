# SixGR Foundation v2

## 20 October 2026: consolidated main codebase and current H4 commands

This is the current status; older dated sections below are retained as history.
All MATLAB, Python, YAML, tests and documentation use the **single `main`
checkout**. External drives hold simulation evidence, not a second codebase.
Committing these repairs is **not** a claim of complete scenario acceptance.

| Area | Implemented / verified | Still required |
| --- | --- | --- |
| Exact PDSCH resource accounting | Both canonical TX entry paths expose the immutable gross/data/pilot resource sets; coded TX/RX and exact allocation checks pass. | Inspect new integrated DL rows and terminal exports. Earlier missing counts are not reconstructed from throughput. |
| TRS measurements | Actual desired/received pilot pairs, diagnostic EVM and a post-correction common-frequency measurement using an observable different from acquisition. Full-band correction-on/off and poisoned-reference checks pass. | New integrated observations and final CSV/PNG acceptance. Same-capture observables are not independent statistical trials; these diagnostics do not certify RF-conformance EVM or isolated oscillator CFO. |
| Beam plots and SRS coverage | SSB series retain observation/beam identity. SRS distinguishes exact full-carrier coverage from configured edge tolerance. | Verify the resumed publications. Actual native SRS coverage remains **272/273 PRBs**, not 273 measured PRBs. |
| Memory ownership | Redundant pending broadcast preparation owners are removed with equality guards; frozen samples, receiver clocks and required TX grids remain intact. | Whole-run memory/paging measurement; genuine 64-port arrays remain large. No precision reduction or skipped RF/channel evolution. |
| Handoff and adaptation audit | Slots **40--60** check DL/UL handoff. Causal CSI-to-data use is checked through the unchanged **100-slot** horizon. Both are mandatory via `AllChecksPassed`. | Actual completed radio slots, received feedback and data trials. A report in slot 59 UL symbols cannot adapt earlier DL symbols; slot 60 is UL. |
| Overall acceptance | Completed checkpoint 45 was verified; a source-repaired continuation is configured to resume at 46, retaining the interrupted attempt. | All 100 slots, connected PUSCH, sustained causal adaptation, final measurement/export audit and separate statistical qualification. A resumed repair run is not a frozen-source primary study result. |

Latest affected-check evidence: **14 distinct MATLAB checks** have passing
latest results across `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v1`
through `v4`; **254 Python publication checks** and **59 slot-window audit
checks** pass. Earlier failed receipts remain preserved. **No `testAll` was
run**, following the operator's affected-tests-only instruction. These checks
do not qualify every configuration or the full scenario.

Consolidation verification: **78/78 Python server-handoff and slot-window
checks passed**. The fresh-run command above/below was checked with `--plan`
without starting MATLAB or writing a new run. No full suite was launched.

See the [repair details](docs/lls/h4_checkpoint45_repairs_20261020.md) and
[complete issue ledger](docs/lls/h4_100mhz_20261015_issue_status.csv). Runtime
receipts/logs and large IQ archives are local evidence, not files shipped by
GitHub; preserve them or transfer them with the documented evidence bundle.

### Fresh 100 MHz run: Windows Command Prompt

Use a new tag and a committed, clean checkout. This command launches **one
fresh 100-slot run**, then performs the handoff/adaptation audit; it does not
start directly at slot 40. Do not launch it alongside the already active run.
On another server, change the checkout, MATLAB executable and output paths.

```cmd
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
python scripts\run_lls_slot_window.py --config simulator/configs/validation/h4_100_slot40_60.yaml --matlab "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" --results "E:\SixGRResults" --tag h4_100mhz_40db_100slots_20261020_01
```

Add `--plan` for a dry command preview. The wrapper preserves failures and
does not automatically rerun. It requires successful scenario execution
**and** `AllChecksPassed`; `WindowChecksPassed` alone is insufficient.

- Scenario YAML: [`h4_100_cdlc100_connected_impaired_40db_adaptation.yaml`](simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml).
- Run folder: `E:\SixGRResults\lls\h4_100_cdlc100_connected_impaired_40db_adaptation\h4_100mhz_40db_100slots_20261020_01\`.
- Launcher logs: `logs\server\h4_100mhz_40db_100slots_20261020_01\`.
- Additional audit: `reports\validation\slot40_60\` within that run, with source hashes, scope-labelled checks and separate post-window adaptation extracts. The primary CSVs are not replaced.

The executed configuration is 4 GHz, 100 MHz, 30 kHz SCS, 273 PRBs, 64 gNB TXRU/four UE
chains, TDD `D,D,D,S(10DL/2guard/2UL),U`, adaptive DL/UL rank up to 4 and physical
control/feedback with configured CDL-C/RF impairments. Full-buffer traffic is
bidirectional. PUSCH uses symbols 0--10; K2=4 maps control slot 46 to data slot 50.
Slots 45/50/55/etc. are UL opportunities, not automatic PUSCH transmissions.
In the retained attempt, SRS at 45 passed and UL DCI at 46 for PUSCH at 50 decoded; this
does not establish that the subsequent PUSCH decoded successfully.

### Resume and WebGUI

Use the [completed-slot checkpoint procedure](#completed-slot-restart-checkpoints)
with the original scientific configuration and intact archive dependencies.
After-slot-45 resumes at 46; it does not repeat initial access. The visible run
folder is restored to the checkpoint while the interrupted attempt is preserved.
Source changes require a reviewed repair reason and remain diagnostic evidence.
Checkpoint restoration verifies large retained files before PHY progression;
the observed checkpoint-45 dependency set contains 1,196 files totaling 41.51 GiB.
Do not start a second MATLAB writer because the startup log is temporarily quiet.

For the external results tree, start the GUI in a **separate Command Prompt**
from this same checkout, only if port 62906 is not already serving it:

```cmd
set "SIXGR_RESULTS_ROOT=E:\SixGRResults"
set "SIXGR_OUTPUT_BACKEND_OVERRIDE=filesystem"
"apps\.webgui-venv\Scripts\python.exe" apps\lls_web_dashboard.py --host 127.0.0.1 --port 62906 --server auto --threads 32 --no-browser
```

Open <http://127.0.0.1:62906/realtime> and select the intended run. This command
requires the existing WebGUI virtual environment; see the setup section below
for a fresh machine. The GUI reports persisted evidence: an old slot number is
not proof that a newly started MATLAB process has already reached that slot.

Other commands remain documented below: [5 MHz TDD](#5-mhz-tdd-saturated-20-db-or-eight-point-awgn-sweep),
[20 MHz TDD](#20-mhz-n39-tdd-cdl-c-commands),
[400 MHz research / Keysight](#400-mhz--7-ghz-research-waveform-and-keysight-package),
and [LLS BLER/HARQ calibration](#generic-lls-blerharq-calibration-bounded-collection-not-qualification).
The newer 4 GHz / 20 MHz / 64-TXRU / four-chain draft is distinct from the older n39
scenario; local 20 MHz development remains paused behind 100 MHz acceptance.

### 19 October: authorized local verification and external storage

The operator has now authorized local 100 MHz verification. This supersedes
the earlier server-only execution restriction below; it does not establish
scenario acceptance. Use **one main source checkout** and keep large evidence
under **`E:\SixGRResults`**, with launcher logs under the repository's `logs/`.

The first local launch (`h4_100mhz_local_e_20261019_v1`) was stopped during
initialization: the MATLAB results resolver silently redirected its external
output argument to the repository's C: results tree. Its files are preserved.
H4-170 repairs the production resolver and server launcher, not the PHY.
Three affected MATLAB tests and 59 Python routing/window/handoff tests pass;
these checks do not constitute a physical scenario pass. No `testAll` was run.

For direct MATLAB commands, explicitly opt in to the **same absolute directory**
passed to the runner. A drive root or a directory containing the source checkout
is not an allowed production evidence root. Relative `results` continues to
mean the repository's results folder; setting the environment alone does not
silently relocate those legacy callers.

```cmd
set "SIXGR_RESULTS_ROOT=E:\SixGRResults"
set "SIXGR_OUTPUT_BACKEND_OVERRIDE=filesystem"
```

Then pass `'E:\SixGRResults'` as the runner's output argument and assert
`strcmpi(sixgr.report.resolveResultsRoot('E:\SixGRResults'),'E:\SixGRResults')`
before calling it. Always use a new tag. The server/window launchers now set
that environment binding automatically from `--results "E:\SixGRResults"`
and reject a redirected MATLAB root before starting PHY work. Their clean-source
guard is unchanged; local dirty-source execution is **repair validation**, not
frozen-source study qualification. Start the WebGUI with the same environment
so it discovers the external results tree.

## 19 October 2026: server handoff and current acceptance

**Server handoff procedure; use the latest status above.** All source,
YAML, tests, WebGUI and documentation belong to this repository's **`main`**
branch. There is no separate repair codebase. Historical dated evidence below
is retained for traceability; this dated status does not supersede newer evidence above.

| Item | Current evidence / limitation |
| --- | --- |
| Latest H4 run | Operator interrupted MATLAB after slot-46 exports. No final completion/failure receipt was written. **Not an accepted 100-slot result.** |
| Restart boundary | Historical completed checkpoint: **45**, next slot **46**. A slot-46 CSV is not proof that slot 46 or the scenario finished. The first server verification must start fresh; a historical checkpoint number does not establish that its complete dependencies are currently available. |
| Large paired-CSI export | Bounded MATLAB writer retained all 1,677,312 sample pairs; the live CSV matched its independently replayed SHA256. No sample decimation. |
| Occupancy plot memory | Python renderer now reduces CSV records as a stream, instead of retaining the entire approximately 498 MB input as dictionaries. **217 affected Python tests pass**. The full retained-data replay completed: **23 PNGs**, all **87 source/output hashes matched**, all 1,677,312 CSI sample pairs and 810,338 executed-RE rows accounted for. This remains a partial diagnostic replay, not terminal qualification or proof of the earlier exit cause. |
| Live radio-clock progress | Core runtime and WebGUI now separate the active one-based radio slot/frame, processed slots/symbols and DL/UL trial rows. Five distinct affected MATLAB checks and 78 Python checks pass. A processed slot is not a durable checkpoint or scenario acceptance. |
| Duplicate RE serialization | Core exporter now serializes each carrier/native RE table once and publishes verified byte copies to the component/live destinations. **Four affected MATLAB checks and 69 Python consumer checks pass**; the retained 497,999,464-byte CSV also copied with matching SHA256. Full-run timing and live MySQL qualification remain pending. |
| PDCCH H0/H1 qualification | Noise-only results alone can no longer qualify the detector. AWGN campaign checks pass; the installed H4 single-occasion executor now also passes one noise-only case and independently decoded DL/UL DCI cases. A core LLR-scale repair and seven related checks pass (**eight affected MATLAB tests total**). Independent resets and these small populations do **not** establish continuous H4 execution, statistical or NR conformance qualification. |
| Server handoff utilities | **18 orchestration/packaging tests pass**, with MATLAB mocked. These verify command construction, failure handling, evidence hashes and exclusions—not a physical server run. |
| Integrated acceptance | Connected UL, delivered CSI/UCI-driven adaptation, all 100 slots, complete terminal CSV/PNG publication and statistical qualification remain **unaccepted**. A larger server does not by itself fix or qualify these. |
| Verification policy | Affected tests only at the operator's request. **No full `testAll` and no new scenario were launched for this handoff.** |

Final handoff verification: **253/253 focused Python checks passed**, covering
the launcher/collector, refreshed documentation and affected publication paths.
The three initially stale documentation-snapshot checks passed after regeneration
with the actual MATLAB loader/builder. Local receipts are
`logs/server_handoff_final_20261019.xml` and
`logs/server_handoff_guide_refresh_20261019.log`; the original failed check receipt
is preserved. This does not replace MATLAB PHY or full-scenario qualification.

Current work order: finish known **100 MHz repairs first**. The draft local
20 MHz / 4 GHz / 64-TXRU / four-chain-UE configuration is paused; no 20 MHz
scenario has been launched. The original handoff assigned full 100 MHz execution
to the server; the later explicit local authorization is recorded above.

### Targeted slot-40--60 regression (100 MHz / 4 GHz TDD)

The validation policy is
[`h4_100_slot40_60.yaml`](simulator/configs/validation/h4_100_slot40_60.yaml).
It uses the **unchanged 100-slot production scenario**, including real initial
access, 64 gNB TXRU/four UE chains, adaptive rank up to four, CSI/SRS/TRS,
physical control and RF impairments. It does not create a pre-attached UE at
slot 40, reset a channel, shorten the CSI calendar, remove the SRS guard, or
force rank/MCS/ACK values. Slots are **one-based absolute carrier slots**;
symbol indices remain zero-based.

The production timing preflight verifies control slots **41/46/51/56** to UL
data slots **45/50/55/60**, CSI reporting occasion **59**, and TRS observation
start **47**. These are configured opportunities, not promises that access,
traffic admission or physical decoding succeeds at those times.

| Window check | Required evidence |
| --- | --- |
| Progress | Completed-radio counter reaches 60 and each slot 40--60 appears exactly once. CurrentSlot=60 alone does not pass. |
| DL and UL | Actual shared-stream decoder rows, at least one CRC pass in each direction, matching UE/RNTI/frozen grant/TBS, legal symbol allocation, and measured DMRS-port count consistent with transmitted layers. |
| Direction changes | Actual DL then UL and UL then DL data activity; configured K2 legality; rejected opposite-direction targets retain their blocker. |
| CSI/adaptation | Independently received CSI-UCI, causal source/due/delivery ordering, and received CSI linked through scheduler admission to a future PDSCH trial through slot 100. This is a separate mandatory scope from the 40--60 handoff window; rank need not increase merely to pass. |
| PUCCH / UCI | Receiver-owned HARQ/SR/CSI typed lengths, a successful PUCCH reception, and exact logical/physical feedback identities. A failed decode is not misreported as a missing trial. |
| Grant closure | Each scheduled DL/UL grant has one real trial or explicit receive/no-decode disposition. UCI-on-PUSCH transfer requires matching actual PUSCH evidence. |
| Missing activity | No PUSCH, no delivered CSI, or an empty/header-only file fails coverage. Window-end censoring cannot conceal feedback due inside a 100-slot run. |

**Verified so far:** three affected MATLAB tests pass, including Type-2
HARQ DAI wrap/gap guards; 40 Python audit/launcher regression cases plus 18
existing server-handoff guards pass (**58 affected Python tests**).
Receipts: `logs/lls_repairs/h4_slot40_60_preflight_20261019_v1/receipt.json`
and `logs/h4_slot40_60_final_20261019_v4.xml`.
The window audit also rejects explicitly unfinished PUCCH rows, unfinalized
cancellation/censoring and failed UCI-on-PUSCH transfer status. Five separate
affected RF/channel-scoring tests pass in
`logs/lls_repairs/h4_postdecode_export_20261019_v1/receipt.json`; these cover
actual bounded RF streams and receiver/scoring operators, not the entire
100 MHz production export.
The production PUCCH disposition classifier now checks UE/RNTI, occasion,
carrier/BWP and available run/sweep identity as well as the grant ID, and
does not credit proxy/placeholder evidence. Three affected MATLAB tests,
including actual runtime-written grant/trial CSV schemas, pass in
`logs/lls_repairs/h4_feedback_identity_20261019_v2/receipt.json`.
The audit fixtures are not waveform results. **The production physical
slot-40--60 window has not yet passed this new gate.** No `testAll` was run.

The subsequent production channel-scoring repair (H4-169) also passes its
affected checks. `pilotChannelNMSE.m` and
`buildReceiverChannelEstimateTable.m` now score the exact compact pilot
capture directly, without reconstructing a full channel-estimate tensor.
The 273-PRB / 64-RX / four-port storage fixture preserves all 838,656 scored
pilot/branch values and exact table/scoring equality; its compact capture is
13,524,117 bytes versus 187,858,944 bytes for the discarded dense estimate.
This is an allocation comparison, **not a whole-process peak-memory claim**.
Eight physical DL/UL receiver cases also retain byte-identical measurement
CSVs before/after the repair. The bounded shared SRS/DCI/PUSCH test passes
through the production scoring exporters with real decoded data and retained
reference-IQ/coefficient archives. It is not the full-band H4 window.
Four existing affected checks passed in
`logs/lls_repairs/h4_compact_scoring_20261019_v1/receipt.json`; that receipt
also preserves an initial bookkeeping failure in the new test, subsequently
fixed. Both new checks pass in
`logs/lls_repairs/h4_compact_scoring_20261019_v2/receipt.json`.

On the **high-capacity Windows server**, from the repository root after the
reviewed source has been committed and transferred, this launches one fresh
production run and audits the window even if scenario acceptance fails:

```cmd
python scripts\run_lls_slot_window.py --config simulator/configs/validation/h4_100_slot40_60.yaml --matlab "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" --results results --tag h4_slot40_60_server_01
```

Use a new run tag. The existing server launcher rejects dirty source and an
existing run/log destination. Add `--plan` to inspect the command without
starting MATLAB or writing outputs. **A fresh launch executes slots 1--100;
40--60 is the audited interval, not an artificial starting point.** The full
horizon is retained so late grants and feedback are not changed by truncation.
There is no automatic rerun on failure.

Outputs stay together under
`results/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/h4_slot40_60_server_01/`.
The additional `reports/validation/slot40_60/` contains `checks.csv`,
`receipt.json`, source hashes and unchanged, source-labelled window rows for
each available input table. Separate `adaptation_*` extracts retain the later
records used by the through-slot100 causal check. These are diagnostic extracts,
not replacement primary measurements. Launcher/MATLAB logs are in
`logs/server/h4_slot40_60_server_01/`.

To audit an already stopped/completed run without MATLAB:

```cmd
python scripts\audit_lls_slot_window.py --config simulator/configs/validation/h4_100_slot40_60.yaml --run-folder "results\lls\h4_100_cdlc100_connected_impaired_40db_adaptation\h4_slot40_60_server_01"
```

Do not repeat that command over an existing audit; use `--output` with a new
diagnostic folder to preserve the earlier receipt. Missing evidence is reported
as a failed check; no replacement PHY rows are generated. `WindowChecksPassed`
and `AdaptationChecksPassed` describe their separate scopes; `AllChecksPassed`
requires both and remains separate from full scenario acceptance and statistical
qualification.

For a retry, use the existing [completed-slot checkpoint workflow](#completed-slot-restart-checkpoints)
with the same scientific configuration and intact IQ/archive dependencies.
To **re-execute all of 40--60**, choose a verified checkpoint **before 40**
(for example, after 35, resuming at 36). After-40 resumes at 41 and does not
retest slot 40. A changed-source continuation remains repair-validation
evidence. If no suitable checkpoint survives, a real fresh prefix is required.

19 October shared-runtime memory repair (H4-157):

- The production coordinator no longer requests and discards the full
  completed-observation output. Its slot and receive-tail wrappers propagate
  that choice to `CoupledWaveformStream.m`, which releases delivered
  callback captures and interval temporaries before the next physical interval.
- Explicit two-output callers still receive every requested observation.
  Pending captures, channel/RF/noise state, HARQ, exact channel archives and
  continuous IQ are not shortened, reset, decimated or replaced.
- **9/9 final affected MATLAB checks pass** in
  `logs/lls_repairs/h4_completion_lifetime_final_20261019_v2/receipt.json`.
  The unchanged lifetime regression first failed in
  `h4_completion_lifetime_red_20261019_v1`; both receipts are preserved.
  The checks cover callback identity and clocks, actual narrow-grid coded
  transmissions/channel archives, both receive-tail APIs, CSI-RS measurements
  and continuous IQ. They do not establish decoded-data BLER or full H4 acceptance.
- Full 100-slot MATLAB/Python memory qualification remains open. The separate
  lifetime receive-only PUSCH capture/result cache repair is recorded below
  under H4-158. No full scenario or `testAll` was launched; 20 MHz work remains
  paused.

19 October receive-only evidence ownership repair (H4-158):

- `CoupledWaveformStream.m` and `completeSharedPUSCHAfterRejectedControl.m`
  now archive successfully completed receive-only captures and decoder arrays
  through `SharedReceiveOnlyEvidence.m` before releasing their live cache
  entries. Both actual pre/post-RF sample planes, the receiver observation,
  frozen grant, decoder result and sample clocks remain losslessly available.
  State holds checksum-bound receipts, not another lifetime IQ/decoder copy.
  Active receiver-owned HARQ soft buffers remain in memory.
- Explicit on-demand reads verify the archive identity, bytes and sample hashes.
  Missing/corrupt files and duplicate completion/archive attempts are rejected;
  no UE transmission, TB delivery or performance row is invented. Checkpoints
  retain verified immutable-file dependencies instead of copying every large
  historical MAT file into each checkpoint generation.
- **6/6 final affected MATLAB tests pass** in
  `logs/lls_repairs/h4_receive_only_archive_20261019_v2/receipt.json`:
  single and repeated missing-DCI reception, due HARQ, CSI, the original
  capture API and checkpoint continuation. The repeated case retains two
  actual captures and receiver-owned soft combining with zero UE transmissions.
  The first archive batch exposed a cell-array row-deletion bug; its **4/5**
  result is preserved, and the production deletion was corrected without
  weakening the test.
- Actual pre/post-repair receiver samples, control samples, audit tables and
  **all 326 non-wall-clock receiver fields match exactly**. Four other fields
  are measured `tic/toc` execution durations and legitimately differ; their
  original values and the initial all-fields comparison are retained in
  `physical_equivalence_with_timing_separation.json` beside the final receipt.
  The audit CSV bytes also match. This is semantic preservation for the
  measured fixture, not a benchmark speedup or statistical qualification.
- A separate stale timing-test prerequisite was repaired (H4-159). A native
  PDCCH with an explicitly authored 64-sample delay now exercises the bounded
  `[0,16]` receive search; it does not rely on an incidental noise peak.
  The receiver algorithm, RF/channel settings and rejection/CRC guards were
  not changed to make that test pass.
- Whole-run RSS, sustained adaptive DL/UL, complete terminal CSV/PNG and
  statistical acceptance still require the fresh 100-slot server execution.
  These focused checks do not close H4-46 or qualify the full 100 MHz scenario.

19 October continuous UL handoff check (H4-160, **not yet qualified**):

- `testH4100ContinuousULFeedback.m` retains the physical owner returned by
  the actual two-occasion full-band SRS check. Its new optional delivery mode
  calls the production SRS adaptation consumer at the first subsequent
  canonical slot boundary, before advancing that boundary's samples.
- The check enumerates future configured TDD/K2 opportunities, preserves
  SRS age and rank-confirmation policy, and is intended to execute actual
  received DCI and PUSCH without restarting channel/RF/noise state.
  Initial DL timing and TAG remain explicitly declared component boundaries;
  PBCH/PRACH/RRC, sustained scheduling and MAC feedback acceptance are **not**
  claimed. A physical control/CRC failure must remain a failure.
- The initial diagnostic was stopped with evidence preserved after static
  review found it consumed slot 11 before attempting the legal control-11 /
  data-15 handoff. The test now returns the live owner at the unexecuted
  delivery boundary. The configured five-slot SRS age and K2 remain unchanged;
  `testH4100ULPlanningTimingEvidence` passes the explicit boundary regression
  (`logs/lls_repairs/h4_continuous_ul_preflight_20261019_v2/receipt.json`).
- V2 physically completed both SRS receptions on the same owner. Source 5
  was delivered at 6 (measured RI 4 / CQI 14, accepted rank still 1); source
  10 was delivered at 11 (RI 4 / CQI 15, accepted rank 4 / MCS 25).
  Its NMSE operands reproduce -26.879 and -26.878 dB respectively. Evidence:
  `results/lls/h4_shared_srs_scoring/20261019_161412_975`.
- **V2 failed before PDCCH transmission** with
  `sixgr:truth:SharedPDCCHResourceCollision`: the new test omitted the
  common-resource reservations which production already passes to the
  candidate allocator. The test now passes those reservations; a new
  allocation-only preflight checks both the original collision and legal
  reassignment without changing aggregation level or disabling common signals.
  This is a test-integration repair, not a claimed production decoder fix.
  The first new preflight omitted the installed C-RNTI and failed before
  allocation; that receipt is retained. The corrected exact-H4 preflight
  **passes** in `logs/lls_repairs/h4_continuous_ul_preflight_20261019_v4/receipt.json`.
  The existing shared-slot resource regression also passes in the v3 batch.
- Continuous control/data reception remains unverified. The stopped v1
  evidence remains in `results/lls/h4_shared_srs_scoring/20261019_160219_176`
  with an explicit interruption receipt; the failed v2 receipt is preserved.
  V3 completed both SRS deliveries and actually decoded the shared-stream
  PDCCH (AL 4, all 49 DCI bits matched, 16 candidates / 32 hypotheses).
  It prepared rank-4/MCS-25 PUSCH from that received command, without a
  channel reset, but **failed in the post-receiver diagnostic exporter**:
  `buildPHYSignalDiagnosticSnapshot.m` exhausted memory while concatenating
  the full channel-grid table. No completed PUSCH trial/CRC receipt was
  published, so a physical data pass is not claimed. The failed receipt is
  `logs/lls_repairs/h4_continuous_ul_feedback_20261019_v3/receipt.json`;
  completed evidence is in `results/lls/h4_shared_srs_scoring/20261019_164224_497`.
  The process left after its terminal failure was closed; no full scenario
  or `testAll` was started. Earlier independent-reset passes remain separate.

19 October full-grid diagnostic memory repair (H4-161 / H4-162):

- The core snapshot now retains a compact, checksum-bound measured tensor
  for large grids. The core exporter expands complete RX/TX frequency-time
  planes through the existing atomic CSV stream, preserving all coefficients,
  phase unwrap continuity, coordinates and metadata in the same canonical CSV.
  `SourceTableComplete=false` explicitly identifies the bounded in-memory
  panel table; `SourceRowCount` includes every deferred coefficient row.
- The new declared-array regression passes: **11,741,184 H4-size values**
  retained in a **210,161,081-byte snapshot**, byte-identical small inline and
  streamed CSVs, and corrupt-tensor rejection without overwriting the prior
  complete CSV. This is an object-size/export regression, **not** a measured
  whole-process memory reduction or physical scenario acceptance.
- The MATLAB inventory now scans the complete source once in bounded blocks;
  the availability gate checks every row, including identities and all required
  panels. Python selects only the requested measured panel while streaming;
  Hest heatmaps use two passes, retain every port row (including genuine zero
  coefficients and undefined phase), and reject a source that changes between
  passes. Publication's status-column finalizer also streams instead of
  rebuilding a list of every plotted row.
- **Focused results:** `testPHYDiagnosticGridStreaming`,
  `testPHYSignalDiagnostic`, `testPHYDiagnosticCSVConsumers`, and actual DL/UL
  `testPHYDiagnosticWaveformWindow` pass. The latter's stale fixture lacked
  its run root and installed antennas; it now uses the production context
  binder before waveform execution. Both directions retain identical CRC,
  bit-error, SINR, EVM and timing/CFO metrics with capture on versus off.
  This is a 100-MHz carrier / 24-allocated-PRB test, not full-band qualification.
  The new reader's initial header-only failure was fixed, not suppressed.
  Receipts are under `logs/lls_repairs/h4_diagnostic_grid_streaming_20261019_v2/`,
  `h4_diagnostic_consumers_20261019_v1/` and `h4_diagnostic_consumers_20261019_v2/`.
  Failed intermediate receipts remain preserved. Python publication checks:
  **103/103 pass**, `logs/h4_diagnostic_publication_20261019_v1.xml`.
- Further filesystem-publication repair (H4-163): completed output files now
  have a path/size/SHA256 receipt instead of a lifetime in-memory payload copy.
  Reuse verifies the actual bytes before and after reading. A new negative
  test caught buffered-prefix reuse during checksum verification; verification
  now reads the underlying descriptor. The failed intermediate receipt is
  retained (`h4_diagnostic_publication_20261019_v3.xml`: 105 pass / 1 fail);
  **all 10 affected filesystem/publication checks pass** after correction
  (`logs/h4_diagnostic_publication_20261019_v4.xml`). The 24-MiB fixture retains
  less than 1 MiB of Python index state; this is not whole-scenario RSS evidence.
- Complete output-buffer ownership is also repaired (H4-164): large Hest
  plotted CSVs spill to sealed private temporary files, rather than becoming
  population-sized Python byte strings. The finalizer, atomic filesystem
  writer, database chunk writer, publication index, live publisher and plot
  lineage consume this explicit file-backed payload. Small outputs retain the
  byte interface. Every row is retained; the 8-MiB spill threshold is a storage
  boundary, **not** a sample limit. Existing chart/alias lineage hashes CSVs
  as streams rather than loading them again. A discovered filesystem-only
  metadata lookup bug is corrected without fabricating database provenance.
  **Seven new focused checks pass** (`logs/h4_file_backed_publication_20261019_v4.xml`):
  exact byte/file CSV and PNG identity, final filesystem and live publication,
  database chunk order/completion, corrupted-payload rejection, bounded Python
  allocation and existing-alias linkage. The initial failed integration checks
  are preserved. The final affected publication suite, including existing-chart
  stream reuse, completes **169/169 pass** in
  `logs/h4_final_publication_20261019_v1.xml`. These are publication regressions,
  not statistical PHY qualification or complete server-run acceptance.
- WebGUI filesystem delivery is repaired (H4-165): CSV previews and logical-row
  counts read the actual file without retaining its full byte payload. Downloads
  use bounded chunks and the opened file's size/version, not stale index metadata.
  A missing or changing file cannot be served as a cached success. The Waitress
  adapter now spools large responses and releases them after consumption or
  disconnect, instead of rebuilding a complete in-memory response. All download
  bytes are preserved. **99 affected checks pass**, including eight new delivery,
  memory and failure-path checks, in `logs/h4_dashboard_streaming_20261019_v3.xml`.
  This qualifies the tested filesystem path; database-backed payload buffering
  and full-run process memory are not covered by that claim.
- Constellation producer output ownership is repaired too (H4-166). The six
  exact data-constellation/error-histogram producers no longer read a complete
  temporary CSV back into one byte buffer before finalization. Large outputs
  use the same sealed file-backed protocol, with no sample removal or change
  to receiver/reference pairs. **234 affected checks pass** in
  `logs/h4_constellation_output_20261019_v2.xml`. A 50,000-row fixture retains
  all 7,628,152 CSV bytes with 2,493,613 Python-tracked peak bytes; SQLite/native
  allocation and whole-run RSS are separate. All six byte/file comparisons
  preserve CSV, plot bytes and lineage. Live publication also verifies the
  3,522 actual retained receiver pairs under both storage paths. These are
  publication checks, not additional independent PHY trials.
- The continuous UL v4 component has now published its **slot-15 PUSCH CRC
  pass with zero bit errors** after the two measured SRS reports and actual
  received DCI, without resetting the shared CDL/RF owner. It retains 273 PRBs,
  rank 4, MCS 25, 64-QAM, rate 0.802734375, a 507,984-bit TB and 103,188 EVM
  pairs. EVM 0.0541486182162825 closes from retained error/reference energies;
  the decoder-noise domain/value audits pass. The final component receipt is
  **PASS** (`logs/lls_repairs/h4_continuous_ul_feedback_20261019_v4/receipt.json`),
  with all 16 component slots completed. This is **not** a full MAC
  feedback or 100-slot result. Its raw job CSV precedes the production
  coordinator's shared RF and independent channel-scoring binders; do not
  interpret those unbound flat RF flags as evidence that RF was disabled.
- **Still open:** full-width integrated publication and whole-process peak
  memory. Other plot families may still construct complete datasets; this
  repair does not establish constant memory for the entire publisher. Continuous
  physical SRS/DCI/PUSCH component v4 has completed after these focused checks
  (`logs/h4_continuous_ul_feedback_20261019_v4_launcher.log`); it retains
  exact receiver inputs before decoder/export execution. That replay file is
  not a restorable whole-channel checkpoint. Full 100-slot execution remains
  on the server; 20 MHz is paused and `testAll` has not been started.

19 October transport-publication repairs (H4-153 through H4-156):

- Production `writeRFInterferenceReconciliation.m` and
  `generateMeasuredSINRCurves.m` now share
  `buildSchedulerKPIReconciliation.m` for numeric scheduler accounting.
  The separate anchor-case gate is published as
  `reports/csv/scheduler_anchor_case_reconciliation.csv`; it cannot overwrite
  the numeric `scheduler_kpi_reconciliation.csv` schema. Connected canonical
  acceptance requires both accounting and anchor coverage, not either alone.
- Goodput uses the existing `TransportGoodput/v1` first-success TB ledger.
  Retries, warmup exclusion and SINR/UE/bin slicing cannot credit the same
  payload twice. Actual retained trial durations (or explicitly configured
  numerology when no duration column exists) provide the denominator.
  Missing durations, TB identity or CRC evidence do not become fabricated zeros.
- Unknown CRCs are separate from observed failures. The scheduler CSV labels
  its BLER as **all-attempt CRC BLER**, not initial or residual TB BLER.
  Its goodput and the measured-SINR KPI summary are **bits / summed trial
  exposure**, not full elapsed-run throughput. The measured-SINR distribution
  additionally identifies its mean/percentiles as observed per-trial rate
  statistics and exports their known/unknown populations.
- **13/13 final affected MATLAB checks pass** in
  `logs/lls_repairs/h4_transport_publication_20261019_v2/receipt.json`.
  Earlier 8/8 checks and the original failing reproductions remain retained
  under `h4_scheduler_reconciliation_20261019_v1`,
  `h4_scheduler_reconciliation_red_20261019_v1` and
  `h4_measured_sinr_credit_red_20261019_v1` in the same receipt directory.
  These are explicitly declared arithmetic/publication fixtures, not new
  physical observations or statistical populations. No historical raw output
  was rewritten, no scenario was launched, and no `testAll` was run.

Full 100-slot server execution, continuous DL/UL adaptation, complete terminal
artifact acceptance and independent qualification remain open. These focused
repairs do not establish that every H4 issue is closed.

Latest installed-control campaign repair (19 October, H4-151/152):

- PDCCH now has a YAML-driven resumable campaign using the shared
  `+sixgr/+link/runInstalledControlReceiverCampaign.m` journal. PDCCH and PUCCH
  retain their separate physical executors and event definitions. Resume checks
  source, configuration, seed and retained-IQ identities; unfinished attempts
  are preserved for inspection, not replaced by new samples.
- Fixed a production PUCCH accounting defect: a nonbinary presence value such
  as `2` was coerced to true. Invalid presence/independence flags now fail
  validation before any confidence calculation. No RF or decoder threshold changed.
- **Eight affected MATLAB checks pass**: six configuration/accounting/lock checks
  and two physical resume checks. Four PUCCH episodes retain two H0 DTX outcomes
  with no false acceptance and two exact 17-bit, CRC-passing H1 receptions.
  Three PDCCH episodes retain one H0 with no false CRC/context acceptance and
  exact DL 1_1 / UL 0_1 payload recovery. Every PDCCH waveform executes all
  16 installed candidates and both formats (32 hypotheses), counted as **one**
  independent trial. Repeated regression seeds are not new statistical samples.
- Receipts: `logs/lls_repairs/h4_control_campaign_contracts_20261019_v1/receipt.json`
  and `logs/lls_repairs/h4_control_campaign_physical_20261019_v1/receipt.json`.
  Physical evidence: `results/lls/installed_pucch_campaign/20261019_142617_146/`
  and `results/lls/installed_pdcch_campaign/20261019_143153_694/`.

These are independent-reset **development** populations, not the continuous
100-slot run or NR conformance qualification. All case confidence decisions
remain inconclusive; the configured 1% error limit is an engineering target,
not an asserted 3GPP requirement. Source/configuration changes require a new
campaign tag. Both APIs write one joint `reports/csv/receiver_episodes.csv`,
`qualification_status.csv`, the actual per-episode IQ/receiver/RF evidence,
frozen inputs and `receipt.json` within their own run folder.

Optional bounded PDCCH development/resume command, from the repository root
in **Windows Command Prompt** (three episodes total, at most two per call):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\h4_installed_pdcch_campaign_development.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=sixgr.link.runInstalledPDCCHReceiverCampaign('simulator/configs/validation/h4_100_installed_pdcch_campaign_development.yaml','results/lls/installed_pdcch_campaign','h4_pdcch_development_v1'); disp(receipt);"
```

Repeat the identical command only on the same frozen source/configuration to
resume or audit completion. It does not launch initial access or a full scenario.
**100 MHz continuous execution, terminal export acceptance and independent
statistical qualification remain open. Twenty MHz work remains paused.**

19 October core receiver follow-up (H4-149): `PDCCH_Rx.m` and
`PDCCHWaveformTrialEngine.m` incorrectly divided native MMSE reliability by
its mean; the receiver also clipped the normalized weights. This changed the
decoder LLR scale with common signal/noise gain. The unchanged physical-LLR
regression reproduced an approximately **100-fold overstatement** at gain 0.1.
Both core paths now use `applyMMSECSIWeighting.m`, retaining the absolute native
CSI and exactly two QPSK soft bits per symbol. No noise level, RF setting or
detector threshold was adjusted. Gains 0.1, 1 and 10 now match the independent
native calculation with zero recorded relative error. This follows the native
CSI weighting in the [MathWorks PDCCH receiver example](https://www.mathworks.com/help/5g/ug/downlink-control-processing-and-procedures.html);
it is not a claim that 3GPP specifies this receiver algorithm.

**Eight affected MATLAB checks pass** in
`logs/lls_repairs/h4_pdcch_receiver_final_20261019_v2/receipt.json`.
The YAML-driven installed H4 executor uses the actual 273-PRB / 30-kHz /
122.88-MS/s / 64-TX / four-RX CDL/RF configuration, all 16 configured candidates
and both DCI format hypotheses (32 attempts). Its noise-only case has no false
CRC or context acceptance; its DL 1_1 and UL 0_1 cases recover their exact
payloads. Transmitted bits are used only for post-reception scoring.
The three cases retain actual receiver IQ and 44 source/config hashes under
`results/lls/h4_installed_pdcch/20261019_131611_401`; all six before/after IQ
array comparisons are identical (`llr_repair_replay_audit.json`).
The input YAML is
`simulator/configs/validation/h4_100_installed_pdcch_development.yaml`.
These are **independent-reset control episodes**, not initial access, actual
PUSCH execution, continuous-runtime timing qualification or statistically
qualified detection probabilities. Repeated regression seeds are not pooled.
No `testAll`, full 100-slot scenario or 20 MHz scenario was started.

19 October measured-UL follow-up: two actual SRS occasions at source slots
5 and 10 pass on one shared 100 MHz / 4 GHz, four-UE-TX / 64-gNB-RX
CDL/RF clock. Both recommend RI 4 / TPMI 0; measured CQI is 14 then 15.
The production adaptation consumer, replayed at the actual next slot
boundaries 6 and 11, holds bootstrap rank 1 after the first observation and
accepts rank 4 / MCS 25 only after the second. SRS causes no OLLA ACK update.
Both channel-NMSE values (approximately -26.88 dB) independently reconcile
with the saved error/reference energies over 417,792 compared complex values.
The original failed diagnostic queued two pending SRS occasions at once;
the helper now obeys the unchanged production one-pending-sounding guard.
The failed receipt is retained, not overwritten.

Retained measured feedback also passes exact future-grant construction:
source 10, delivered/control 11, PUSCH 15, K2 4 and age 5. An independent
physical CDL/RF PDCCH episode recovers that grant, then the UE's received-DCI
path generates the matching **273-PRB, four-layer, 64-QAM, rate 0.802734375,
507,984-bit** PUSCH. No scheduler grant or SRS decision is passed into the
UE transmitter. This handoff replay does not continue the sounding channel
history; PUSCH generation alone is not received throughput.

Evidence: `logs/lls_repairs/h4_measured_srs_adaptation_20261019_v2/receipt.json`,
`results/lls/h4_shared_srs_scoring/20261019_133551_890`, and
`results/diagnostics/h4_measured_ul_grant/20261019_135900_118`.
Three affected baseline timing/rank checks also pass in
`logs/lls_repairs/h4_ul_handoff_baseline_20261019_v1/receipt.json`.
The matching bounded data-receiver diagnostic also completes with **CRC pass
and exact recovery of all 507,984 bits** through actual four-TX / 64-RX CDL/RF.
The receiver acquires and applies 16 samples of timing correction and reports
per-layer decision-residual-bounded SINR of 27.09, 28.24, 29.29 and 25.93 dB.
Its actual IQ, RF execution, receiver output and source/input hashes are in
`results/diagnostics/h4_measured_ul_data/20261019_140256_559/receipt.json`.
Control and data are separate independent-reset episodes: this is not a
continuous channel/SRS prediction-quality experiment or a throughput curve.
The data folder's `audits/paired_measurements_v1` contains all **103,188**
matched constellation pairs (25,797 per layer), measured DMRS/decoder fields,
and a joint four-layer CSV/PNG. Independent CSV arithmetic reproduces the
aggregate paired receiver-symbol EVM of **4.2373%** and each layer's EVM;
this is not a standards-qualified transmitter RF EVM measurement. The native
paired CSV uses layer indices 1--4; the chart CSV explicitly uses 0--3.
Timing scoring also keeps the executed earliest arrival (8 samples) separate
from the selected/corrected correlation peak (16 samples). Their -8-sample
difference is an earliest-path-relative diagnostic, not an independent
measurement of residual timing or proof of receiver failure.
Continuous access, bidirectional data, terminal exports and statistical
qualification remain open. The 20 MHz drafts remain paused.

19 October physical-feedback follow-up (H4-03): the unchanged **40-slot
shared CSI/UCI component passes** at 100 MHz / 4 GHz with the configured
64x4 CDL/RF path. Actual PUCCH reports at slots 19 and 39 each recover all
15 SR-plus-CSI bits with CRC pass. Both report RI 2 / CQI 14 / CRI 1;
PMI changes from 20 to 18. The scheduler retains rank 1 after the first
report and accepts rank 2 only after the second configured confirmation.
CSI alone leaves TCI pending. Its preconnected access/TAG inputs are declared:
**this test does not execute initial access or PDSCH/PUSCH data reception**.
The actual received feedback then passes a separate three-grant replay with
decoded logical-link PDCCH and real PDSCH TX: rank 2, MCS 24, PMI 18, CRI 1,
and 126/126/273 PRBs. That replay does not continue the original shared
channel and does not establish data BLER or delivered throughput.

Evidence: `logs/lls_repairs/h4_shared_csi_uci_20261019_v1/receipt.json`,
`results/lls/h4_shared_csi_uci/20261019_113208_842`, and
`results/diagnostics/h4_received_csi_grant/20261019_shared_uci_verified_v1`.
The component's `audits/completed_40slot_plot_replay` contains **12 CSV/PNG
pairs with both observations in the same files**, retaining 282 actual-source
CSV records. Both 69,888-value CSI channel-reference populations reconcile
independently. These are component artifacts, not a terminal 100-slot bundle;
connected UL, complete server execution and statistical acceptance remain open.

19 October follow-up (H4-145): a core PDCCH scoring defect allowed an empty
or skipped receiver observation to appear as a successful negative trial.
The strict adapter, scorer and campaign CSV now retain and require actual
candidate decode-attempt evidence; no detector threshold or PHY sample was
changed. **Five affected MATLAB checks and 38 Python publication checks pass**.
Three additional CSI cadence/rank-handoff/CSI-on-PUSCH checks pass, but these
do not establish continuous H4 adaptation. Receipts are under
`logs/lls_repairs/h4_pdcch_execution_authority_20261019_v2` and
`logs/lls_repairs/h4_csi_handoff_20261019_v1`.
The eight-plot AWGN component package is preserved byte-for-byte under
`results/diagnostics/h4_pdcch_execution_authority_20261019_v2`; its
`preservation_audit.json` identifies the original test folder. It is **not**
an accepted 100 MHz scenario or a statistical qualification campaign.

19 October follow-up (H4-146): the production channel-NMSE plotter now hashes
the same byte stream it parses instead of fetching a full resource CSV twice.
Its exact duplicate-coordinate index uses bounded-cache scratch storage, with
no sample cap or decimation. **163 affected Python plot checks and 11 live
publication checks pass**, including the original two failing regressions.
The actual slot-6 CSI resource CSV (45,837,340 bytes / 69,888 rows) reproduces
the retained NMSE with one source open and 393,456 Python-traced peak bytes.
This excludes native SQLite/runtime allocations and does not prove full-run
memory closure. Receipts: `logs/h4_nmse_stream_20261019_v2.xml` and
`logs/h4_nmse_live_publication_20261019_v1.xml`. The unchanged physical
40-slot CSI/UCI diagnostic is separate from this exporter verification; full
100-slot scenario acceptance remains pending.

19 October follow-up (H4-147): empty or negative-SR PUCCH occasions are now
labelled **not applicable to payload BLER**, rather than missing a required
measurement. A transmitted payload that was missed still counts as an error;
a transmitted payload without decode evidence remains unresolved. **198
affected Python checks pass**, with one unrelated large-memory check excluded.
Replay of the actual first-report CSV changed only the applicability label on
the three empty occasions; all metric values and PNG bytes are unchanged.
The original replay is preserved. Receipt:
`logs/h4_uci_bler_applicability_20261019_v1.xml`; actual-source comparison:
`results/lls/h4_shared_csi_uci/20261019_113208_842/audits/slot19_uci_applicability_replay/receipt.json`.
This reporting repair does not establish statistical UCI qualification or
complete scenario acceptance.

Follow-up H4-148 distinguishes **unknown transmission evidence from known
absence**. A missing bit count no longer erases a failed explicitly prepared
payload, and decoder acceptance alone cannot establish that a UE transmitted.
Invalid/conflicting counts and nonbinary presence flags remain unresolved;
`unavailable` is not interpreted as an absent transmitter. Ten new negative cases
reproduced the old behavior; **234 affected Python checks now pass** (two
large-memory checks excluded). The existing no-CRC test now explicitly declares
its transmitted one-bit payload; its decode assertion is unchanged. The final
receipt is `logs/h4_uci_bler_transmission_authority_20261019_v3.xml`.
Actual first-report replay under `audits/slot19_uci_transmission_authority_replay`
retains all four measurement/applicability rows and identical PNG bytes.

Latest installed-context work (H4-140/141): the core
`runIndependentPUCCHReceiverEpisode` now executes the configured H4 receiver
with actual RF/channel samples. The signal-present case recovers all
**2 HARQ + 1 SR + 14 CSI bits** through the 4x64 CDL/RF path; the separate
no-transmitter case observes **DTX with no actionable ACK** through the
64-channel receiver. Neither case uses a transmitted-layout oracle or a
changed detector threshold. The scoring CSV separates CRC, detection,
usable UCI, missed HARQ and false ACK; multiple bits do not become multiple
independent waveform trials. TX references are saved only for offline scoring.

The RF writer also no longer calls an arbitrary runtime interval
`positive_rf_impairment`. Rows retain the actual episode, endpoint and sample
interval. Before/after H0 RX and H1 TX/RX hashes and all nonidentity RF
measurements match. **Eight distinct affected MATLAB checks have passing
latest results** across `h4_installed_uci_executor_20261019_v3` and
`h4_rf_identity_20261019_v1` / `v2` under `logs/lls_repairs/`.
The `v1` RF batch contains a preserved adapter failure: a zero-output test
was incorrectly called with an output argument. The adapter now supports
both assertion-only and returned-value tests; that check passes unchanged in
`v2`. No PHY assertion was relaxed and no `testAll` was launched.

These are deterministic engineering checks, **not accepted statistical
populations**. Repeated regression seeds must not be pooled as independent
trials. A frozen matching campaign, confidence bounds, the continuous
100-slot server execution, delivered CSI/UCI-driven DL/UL adaptation and
complete terminal measurement/export acceptance remain pending. Twenty MHz
work remains paused. Details and evidence paths are in
[`docs/lls/h4_100mhz_20261015_issue_status.csv`](docs/lls/h4_100mhz_20261015_issue_status.csv).

Installed PUCCH campaign wiring (H4-143/144, 19 October):

- The core `sixgr.link.runInstalledPUCCHReceiverCampaign` now consumes a
  validated YAML design and the normal H4 scenario builder. It freezes the
  receiver obligation before constructing TX, uses the installed TDD symbol
  calendar, and leaves unrelated flexible symbols unresolved. An illegal
  PUCCH allocation is rejected; a different valid TX payload does not rewrite
  the RX hypothesis.
- Source/configuration/toolbox/seed identities, raw YAML, resolved configuration,
  physical receiver IQ, decoder output, RF measurements and offline TX references
  are retained. Every committed episode has checksummed evidence. Resume verifies
  existing episodes, cannot silently replace an incomplete attempt, and counts
  each independent waveform once rather than each HARQ bit.
- The bounded development check executed **two H0 and two H1 episodes** with
  distinct seeds: H0 produced DTX/no false acceptance; H1 recovered all 17 bits
  with CRC success. Resume/idempotence and corrupt/incomplete-evidence rejection
  passed. Retained output:
  `results/lls/installed_pucch_campaign/20261019_105859_102/`.
  The original launcher retains a file-lock cleanup warning. The core cleanup
  repair subsequently passed repeated-entry/concurrent-writer checks without
  warnings; the physical observations were not rewritten or recollected.
- **Six final affected checks pass** in
  `logs/lls_repairs/h4_installed_campaign_final_20261019_v1/receipt.json`.
  This includes fresh common RAR/Msg4 CFO-availability/diagnostic checks and the
  arrival-time reference check. Their passing component scope does not qualify
  a new 100 MHz access prefix or independent synchronization accuracy.

The four observations remain **development evidence, not qualification**.
Both two-episode zero-error populations have a family-adjusted upper bound of
approximately **0.8882**, so neither establishes the YAML's 1% engineering
limit. That limit is not presented as a 3GPP conformance requirement. UCI coding
uses the existing [TS 38.212-derived implementation](https://www.mathworks.com/help/5g/ref/nruciencode.html);
physical [PUCCH format 2](https://www.mathworks.com/help/5g/ref/nrpucch2config.html)
and successful decoding alone do not certify the detector or complete runtime.

Optional bounded development/resume command, from the repository root in
**Windows Command Prompt** (this is not the 100-slot scenario command):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\h4_installed_pucch_development.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=sixgr.link.runInstalledPUCCHReceiverCampaign('simulator/configs/validation/h4_100_installed_pucch_development.yaml','results/lls/installed_pucch_campaign','h4_installed_development_v1'); disp(receipt);"
```

The YAML requests two episodes per invocation, four total. The identical command
resumes **only with unchanged frozen source/config/environment**, then performs
an integrity audit without rerunning completed episodes. Use a new run tag after
repairs; preserve the old evidence and never pool repeated seeds. Data goes under
`results/lls/installed_pucch_campaign/h4_installed_development_v1/`, with one joint
`reports/csv/receiver_episodes.csv`, one `qualification_status.csv`, per-episode
physical evidence and a top-level `receipt.json`. An incomplete attempt blocks
resume for inspection. Statistical decisions occur only at the final fixed
sample size; this runner does not automatically grant detector/NR conformance
or continuous-runtime acceptance. The full scenario, wider UCI/PDCCH populations,
BLER/HARQ qualification and complete terminal plots remain separate work.

Additional core receiver/adaptation repairs (19 October, H4-132 through
H4-135):

- `PUCCHReceiver` and `runPUCCHWaveformTrial` now derive HARQ observations
  from the independent typed receiver schema and decoded HARQ field. The
  first CSI/SR bit is not an ACK; a multi-bit codebook retains all its bits
  instead of becoming one scalar ACK. Invalid CRC/DTX cannot become a valid
  observation. Live/final receiver-stage exports retain the validity and
  bit-count fields. No detector threshold, PHY decision or DCI/DAI mapping
  was changed.
- The strict format-0 SR case previously transmitted HARQ despite its name.
  It now uses an installed typed SR resource/occasion and physically decodes
  SR, with zero HARQ bits. Its CSV retains the SR counts and decoded vector.
  This is a **component** check, not installed H4 statistical qualification.
- Both link-adaptation entry points now honor `AckObservedValid=false`.
  They cannot rescue it using a colocated CRC or legacy ACK alias. Actual
  CSI-only waveform feedback leaves OLLA unchanged; valid first-TX ACK/NACK,
  retransmission exclusion and delayed application remain tested. The old
  code reproduced one erroneous update in both entry points before repair.
- `TR38901Plus` accepts explicit `pathlossEnabled=false` with model `none`
  as disabled, not as a measured 38.901 result. Active `none`, unknown models
  and strict ABG remain rejected. The actual H4 `nrPathLoss` configuration,
  independent UMa formula comparison and waveform loss operator pass unchanged.

Receipts: `logs/lls_repairs/h4_pucch_ack_evidence_20261019_v2/` (**5/5**),
`logs/lls_repairs/h4_pucch_sr_identity_20261019_v1/` (**3/3**),
`logs/lls_repairs/h4_olla_validity_20261019_v1/` (**4 pass / 1 fixture fail**),
and `logs/lls_repairs/h4_olla_validity_20261019_v2/` (**the failed test passes**).
The delay test now explicitly declares the rank-one feedback it supplies and
adds a rank-mismatch rejection check; no production rank guard was relaxed.
Earlier red reproductions and failures are preserved. These bounded checks
do not establish 100-slot connected-UL/adaptation or final export acceptance.

The related report-consumer repair (H4-136) removes the `ExpectedAck`
substitution from `control_plane_timeline.csv`. Its ACK column now requires
an actual received scalar observation, respects explicit validity, and
retains `UCI_ACKValid`/`UCI_ACKSource`. The complete analysis/CSV/Python-plot
regression passes in
`logs/lls_repairs/h4_control_ack_export_20261019_v2/receipt.json`.
The original expectation-as-observation failure and the first patch's omitted
column-registration failure are both preserved. Across these receiver,
adaptation, pathloss and analysis checks, **16 distinct affected MATLAB tests
have passing latest results**; this is not a full-suite or scenario pass.
Remaining acceptance includes the complete 100-slot server execution,
connected DL/UL and physically delivered CSI/HARQ-driven adaptation, terminal
CSV/PNG/hash reconciliation, whole-run memory profiling, and installed-context
H0/H1 and BLER statistical qualification. The last items require matching
production campaign contexts and independent populations, not more generic
component tests. **20 MHz remains paused.**

Further 100 MHz checks pass in
`logs/lls_repairs/h4_fullband_control_mapping_20261019_v1/receipt.json`
(**3/3**): installed-frequency DL/UL PDCCH decoding and wrong-frequency
rejection, 18 combined-UCI layouts with nine AWGN waveforms, and nine actual
273-PRB DL/UL transmissions covering ranks 1/2/4 and the declared CSI/SRS
feedback boundary. These are not full-channel, RF or connected adaptation
qualification. `testH4100ImpairedCombinedUCI` also **passes** its separately
labelled, single-occasion 4x64 CDL/RF receiver check: independent reception of
2 HARQ + 1 SR + 14 CSI bits, CRC pass and exact bit recovery. Its recorded
detector threshold remains 0.2. Actual inputs/outputs and RF measurements are
in `results/lls/h4_impaired_combined_uci/20261019_100050_793/`, with receipt
`logs/lls_repairs/h4_impaired_combined_uci_20261019_v2/receipt.json`.
The physical episode begins at zero and explicitly translates to the radio
occasion's slot identity; preceding shared-clock history is **not** claimed.
The first diagnostic mistakenly requested 18 preceding idle slots, was
stopped before reception, and remains preserved as incomplete. Production
channel continuity was not changed. This one episode is not H0/H1 statistics.

H4-137 corrects another core report path: the standalone PUCCH collector
must copy the **receiver CRC**, not overall trial success, into `CRCPass`.
Both standalone and connected missing-outcome labels now use the recorded
CRC value only. A missing CRC is not inferred from ACK or downstream decode
success. The production-block regression passes in
`logs/lls_repairs/h4_pucch_crc_export_20261019_v1/receipt.json`; the runtime
grant/trial CSV regression also passes in
`logs/lls_repairs/h4_pucch_runtime_export_20261019_v1/receipt.json`.
The first broader strict control-export check stalled after CSV/JSON/binary
output and before its PNGs; that attempt is preserved as incomplete. An
isolated retry **passes** in
`logs/lls_repairs/h4_strict_control_export_20261019_v2/receipt.json`:
21 PDCCH trials, seven PUCCH trials, seven valid PNGs and **40/40 artifact
hashes matched**. This bounded component design does not collect the full
H0/H1 qualification populations. Its saved MATLAB profile records 41 seconds
in PDCCH figure generation during the successful 109-second check; it does
not establish why the earlier attempt stalled. Both minimal renderer probes
also passed. No graphics-code repair or whole-run performance closure is
claimed. The original CRC failure and initial test-harness selector failure
are preserved. No detector threshold or overall acceptance assertion
changed. **Eight distinct checks now have passing latest results in this
round**, including the subsequent receiver-only check below.

The H4-137 follow-up also preserves actual recorded CRC results when a
separate detection decision is unusable. It does not relax DTX or authorize
feedback from CRC alone. The shared receiver-only check still observes
**DTX for both absent transmissions**. Final CRC-contract and actual runtime
CSV checks pass in
`logs/lls_repairs/h4_pucch_crc_dtx_20261019_v2/receipt.json`.
The first extension accidentally removed a variable still used by the
separate detection column; the adjacent export regression caught it, the
variable was restored, and that failure is preserved in the `v1` receipt.

H4-139 fixes the corresponding Python plot consumer: raw CRC no longer
overrides an explicit failed UCI reception. The plotted CSV retains separate
`crc_applicable`, `crc_pass` and `decode_ok` fields; CRC-only and detection-only
evidence cannot invent a completed UCI outcome. **177 affected Python checks
pass**, including six new negative cases that first failed on the original
code: `logs/h4_pucch_crc_plot_20261019_v1.xml`. These are publication checks,
not additional PHY trials. Historical run files were not rewritten.

Additional data-publication repair (H4-131 / H4-130, 19 October): constellation
and data-EVM readers now stream their CSV inputs and use exact disk-backed
indexes instead of retaining every sample as Python objects. No samples,
sweep identities or duplicate-coverage checks were removed. **146 affected
plus 239 adjacent Python checks pass**, and the MATLAB production-publisher
test passes with all **3,522 retained receiver pairs** and an actual PNG.
Frozen-source comparison preserves plotted CSV bytes for nine chart types;
the only intentional SVG change is labelling the reference-point limit
“up to 256”, not presenting it as a measured count. Complete output CSV bytes
still scale with population; whole-run memory and terminal acceptance are
not established by these checks. Receipts:
`logs/h4_data_plot_stream_20261019_v2.xml`,
`logs/h4_data_plot_adjacent_20261019_v1.xml`, and
`logs/lls_repairs/h4_data_publication_20261019_v2/receipt.json`.
The first MATLAB assertion incorrectly assumed homogeneous manifest entries;
its failed receipt is preserved, and the corrected test accepts the actual
JSON cell-array representation without weakening sample/PNG checks.

Additional admission diagnostics (H4-91, 19 October): the core scheduler now
records each UE's actual input **before** discarding inactive users and retains
it when future-UL planning returns to the current control slot. The live and
final writer publish `packet_flow/csv/scheduler_admission_trace.csv`; WebGUI
UE cards expose its last DL/UL decision separately. Actual queued bytes remain
separate from retransmission demand; candidate rank, causal SRS, new-data HARQ
availability, sweep identity and decision/target/knowledge clocks are retained.
These are historical scheduling inputs, **not proof of received DCI or completed
data**, and do not relax any SRS, duplex or HARQ gate. Five affected MATLAB tests
and **73 Python checks pass**. The new test is registered in `testAll` but that
suite was **not run**. Receipts:
`logs/lls_repairs/h4_admission_detail_20261019_v1/receipt.json` (two existing
tests pass; original new-test setup failure preserved),
`logs/lls_repairs/h4_admission_detail_20261019_v2/receipt.json` (three pass), and
`logs/h4_admission_web_final_20261019_v4.xml`.
The earlier retained run directory
is currently absent locally, so its measurements have not been recreated or
retrospectively certified. **20 MHz development remains paused.**

The related K2/resource-preflight gap is now repaired in
`+sixgr/+truth/evaluateULPlanningOpportunity.m` and wired into the shared
runtime before future-slot/UE scheduling. It retains actual evaluated timing
candidates and reports out-of-sweep, opposite-direction and already-queued
deferrals without changing K2, SRS or HARQ policy. The installed H4 100 MHz
configuration verifies control slot **41 → data slot 45 at K2=4** and rejects
slot **42 → DL-only slot 46**. The live/final artifacts are:

- `packet_flow/csv/ul_scheduler_timing.csv` — actual preflight decisions;
- `packet_flow/csv/ul_scheduler_timing_candidates.csv` — evaluated candidates,
  including rejected timing and exact processing/TA tick evidence.

The WebGUI's **UL timing / resource preflight** panel shows the last twelve
decisions; the CSVs retain every recorded decision across sweep points.
Untested K2 options are not invented, and timing eligibility is not a decoded
DCI, final grant or PHY success. **Five affected MATLAB tests and 75 Python
checks pass** (`logs/lls_repairs/h4_ul_timing_20261019_v1/receipt.json` and
`logs/h4_ul_timing_web_20261019_v1.xml`). Complete 100-slot server execution,
connected UL/CSI-driven adaptation, terminal acceptance and matching statistical
qualification remain unaccepted; no local full scenario or testAll was started.

Post-handoff diagnostic repair: the core runtime now persists its original
exception identifier/message/stack and logs the failure **before** rebuilding
large recovery tables. Three affected MATLAB checks and nine WebGUI failure-state
checks pass (`logs/lls_repairs/h4_failure_notice_20261019_v1/receipt.json` and
`logs/h4_failure_status_20261019_v1.xml`). An early failure record explicitly says
recovery is incomplete; it cannot be confused with a completed-slot save point.
The lost exception from the earlier manually closed MATLAB process cannot be
reconstructed by this change.

PDCCH qualification repair (H4-47):

- `runStrictPDCCHValidation` now executes explicitly configured H1 SNR/DCI
  points and counts missed intended grants per independent received waveform.
  Candidate hypotheses are not counted as independent trials. Wrong payload,
  wrong selected resource or invalid grant is not successful delivery.
- H0 and H1 use disjoint Threefry substreams; the confidence budget is divided
  across declared operating points and then the planned looks/directions.
  Both H0 and H1 SNR grids participate in the component configuration hash.
- `control.pdcch_strict.missed_detection_qualification` declares enablement,
  scope, channel, SNRs, DCI formats, target probability and trial/stopping
  budgets. The bounded example is in
  [`configs/lls/lls_pdcch_strict_mini_anchor.yaml`](configs/lls/lls_pdcch_strict_mini_anchor.yaml).
  It inherits confidence and seed families from `statistical_qualification`.
  Missing/disabled H1 remains unqualified; no target is inferred from a result.
- All H1 points share `control/csv/pdcch_missed_detection_sweep.csv` and
  `reports/figures/pdcch_missed_grant_probability.png`. Raw decisions remain in
  `pdcch_trials.csv`; JSON summaries and plot lineage bind the source files.
  `pdcch_config_binding.json` retains the resolved component design, including
  both grids, budgets and seed families, not only its hash.
- The current component producer directly applies AWGN. Its accepted scope is
  `awgn_component_not_nr_conformance`; claiming fading/RF qualification through
  that path is rejected. Both the integrated runner and acceptance contract
  reject promotion of a component PASS to installed-runtime qualification.
  Matching H4 channel, RF, spatial and control contexts still require a separate
  production campaign implementation and sufficient populations.

The physical regression produced **12 H1 trials**: for each of DCI 1_0 and 0_0,
three missed grants at -8 dB and three delivered grants at 35 dB. Those are
bounded regression observations, not qualified error-rate curves. All four
points remain statistically unresolved under the frozen confidence-width
criteria. Receipts: `logs/lls_repairs/h4_pdcch_joint_qualification_20261019_v1/`
and `logs/lls_repairs/h4_pdcch_joint_qualification_20261019_v2/`.
The final saved-design exporter check also passed:
`logs/lls_repairs/h4_pdcch_qualification_export_20261019_v3/receipt.json`.
Repeated regression executions reuse the frozen realizations and are **not**
pooled as additional independent statistical samples.
The retained CSV/PNG triage packages are under
`results/diagnostics/h4_pdcch_joint_20261019_v1/` and
`results/diagnostics/h4_pdcch_joint_20261019_v2/`; their manifests explicitly list
excluded binary grids. The final JSON-binding export is preserved in
`results/diagnostics/h4_pdcch_joint_20261019_v3/`. No full scenario or testAll
was started.

NR missed-grant requirements depend on the specified reference channel,
antenna configuration and operating point; the AWGN engineering target is not
a substituted conformance test. See
[TS 38.101-4 v18.8.0, section 5.3.3.2 and Annex C.3.1](https://www.etsi.org/deliver/etsi_ts/138100_138199/13810104/18.08.00_60/ts_13810104v180800p.pdf).

Radio-clock repair verification is retained in
`logs/lls_repairs/h4_radio_clock_20261019_v1/receipt.json` and
`logs/lls_repairs/h4_radio_clock_20261019_v2/receipt.json`, plus
`logs/h4_radio_clock_python_20261019_v2.xml`. The first batch passed four checks;
the new clock test passed its numerical/CSV checks but failed a line-ending-sensitive
source-wiring assertion. Only that test was rerun after correcting the assertion.
No failed receipt was overwritten. The completed-radio-slot counter is advanced
by the main slot loop after processing, independently of data scheduling; a
validated checkpoint supplies the counter when resuming older saved states.

Retained publication audit:
`results/diagnostics/h4_slot46_publication_audit_20261019.json`, with the 23
paired CSV/PNG outputs under
`results/diagnostics/h4_slot46_publication_20261019_v1/reports/live_measurements/`.
Eight of the 31 chart definitions lack an actual population in that interrupted
run: received CSI CQI/RI/CRI/PMI, reported-versus-applied PMI, and connected-PUSCH
RSSI/BLER/EVM. UE recommendations and access Msg3 do not replace those populations.
All original run files remain unchanged. The replay took 683.51 seconds **with
cProfile enabled**; that is not a clean runtime benchmark or a measured RAM peak.

The RE replica repair uses `csvWriteTable(...,'MirrorPaths',...)` and
`copyFileVerified`: copies are checked before replacing the old destination;
each file is published atomically, but the set of destinations is **not** a
cross-file transaction. A secondary-copy failure remains an execution error,
not a successful synchronized publication. Each destination keeps its own
artifact-store path and row/schema metadata; a live MySQL transaction was not
exercised in this filesystem verification. Existing empty-domain cleanup and
persistence-disabled behavior are unchanged.

Evidence: `logs/lls_repairs/h4_csv_replica_20261019_v1/receipt.json`,
`logs/h4_replica_consumers_20261019.xml`, and
`results/diagnostics/h4_retained_re_copy_20261019_v1/receipt.json`.
The isolated retained-file copy took **17.51 seconds including its initial
source hash**. This is not an end-to-end export speedup measurement. Original
run files were not rewritten; no rows were sampled or regenerated.

The exact launcher prints and saves the source commit for each execution.
Original local evidence stays under `logs/` and `results/`; these are ignored by
Git and **are not downloaded by cloning GitHub**. Only source, configuration,
tests and documentation are published. The current issue ledger is
[the H4 repair ledger](docs/lls/h4_100mhz_20261015_issue_status.csv), with broader
context in the [repair matrix](docs/repairs/repair_matrix.md).

### A. Prepare the higher-capacity server

The commands in this section are for **Windows Command Prompt (`cmd.exe`)**.
Use a normal Windows workstation/server with licensed MATLAB; MATLAB Production
Server, MATLAB Online, an MCP connection and a GPU are **not required** for this
batch workflow. Remote execution on your particular server has not yet been
verified. For Linux, do not paste the Windows launcher/checkpoint commands;
the shell, MEX binaries, MATLAB flags and checkpoint path assumptions need a
separate host qualification.

- Use **MATLAB R2026a** for the reference setup. Install/license 5G Toolbox,
  Communications Toolbox, Phased Array System Toolbox and any additional
  products reported as required by the selected configuration. Setup inventories
  optional products too; an inventory is not proof of usable licenses.
- Install Git including **Git LFS**, and Python **3.12**. The repository stores
  MAT reference files in LFS: do not use GitHub's source ZIP or leave pointer
  text in place of reference MAT files.
- Practical starting provision for one H4 job: **128 GB RAM** and **at least
  1 TB free fast local storage**. These are conservative engineering planning
  values, not measured minimum requirements or a runtime guarantee. The laptop
  reached approximately 31 GB private MATLAB memory before late export work,
  and individual full-slot lossless channel archives approached 2.63 GiB.
  Checkpoint prefixes, IQ and reports add storage. Keep the page file enabled;
  free disk capacity and available RAM/commit headroom are different quantities.
- Run one scenario per checkout at a time. Do not assume more CPU cores launch
  independent slots safely; channel, RF, HARQ and scheduler state are causal.
  Do not add a parallel pool or relax measurement fidelity to make it fit.
- Use local non-synced storage, not OneDrive/network storage for the active
  run. Disable sleep/logoff for the execution session according to site policy;
  disconnecting an RDP session is different from signing out or closing MATLAB.

MathWorks references: [Windows MATLAB batch options](https://www.mathworks.com/help/matlab/ref/matlabwindows.html)
(`-wait` supplies a reliable process exit status) and
[Python compatibility by MATLAB release](https://www.mathworks.com/support/requirements/python-compatibility.html).

First-time clone (change only the installation path if necessary):

```bat
if not exist "C:\SixGR" mkdir "C:\SixGR"
cd /d "C:\SixGR"
git lfs install
git clone --branch main --single-branch https://github.com/anup080002/6gr-simulator.git "6gr-simulator"
cd /d "C:\SixGR\6gr-simulator"
git lfs pull
git lfs fsck
git status --short --branch
git rev-parse HEAD
```

For a previously cloned server, **only when all runs are stopped and Git is
clean**, use the following. Do not use `reset --hard`, `clean -fd`, a force-push,
or overwrite a dirty server checkout. Bring any server edits back for review.

```bat
cd /d "C:\SixGR\6gr-simulator"
git status --short
git switch main
git pull --ff-only origin main
git lfs pull
git lfs fsck
```

Install the ignored local Python environment, then bind the same interpreter
to YAML loading, plotting and the dashboard. Repeat the three `set` lines in
each new Command Prompt; they are session-local and contain no credentials.

```bat
cd /d "C:\SixGR\6gr-simulator"
py -3.12 -m venv "apps\.webgui-venv"
"apps\.webgui-venv\Scripts\python.exe" -m pip install -r "apps\requirements-webgui.txt" pytest
set "PYTHON_EXE=C:\SixGR\6gr-simulator\apps\.webgui-venv\Scripts\python.exe"
set "SIXGR_WEBGUI_PYTHON=%PYTHON_EXE%"
set "SIXGR_MATLAB_EXE=C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
if not exist "logs" mkdir "logs"
"%PYTHON_EXE%" -m pip freeze > "logs\server_python_environment.txt"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_server_testall.ps1" -MatlabExe "%SIXGR_MATLAB_EXE%" -PreflightOnly
```

Despite its filename, **`-PreflightOnly` does not run `testAll` or a scenario**.
It saves environment/setup findings under a unique `logs/testall_*/` directory.
Stop and resolve preflight failures before starting the long run. Do not omit
`-PreflightOnly` unless you deliberately intend to run the complete suite.
Do not commit `.env`, passwords, license files or server credentials.

Optional focused checks on the server (no scenario or full-suite launch):

```bat
"%PYTHON_EXE%" -m pytest tests/test_server_handoff.py tests/test_executed_symbol_occupancy.py tests/test_live_csv_plot_publication.py tests/test_lls_radio_measurement_plots.py tests/test_data_nmse_plot_reconciliation.py -q --junitxml=logs/server_publication_checks.xml
"%SIXGR_MATLAB_EXE%" -wait -logfile "logs\server_focused_01.log" -batch "setup6GRSimToolkit('Verbose',false); addpath(fullfile(pwd,'scripts')); runLLSRepairChecks('server_focused_01',{'testCSVBoundedRoundTrip','testCSVReplicaPublication','testControlEVMDetailStorage','testRuntimeClockProgress','testRuntimeFailureNotice','testSlotCheckpoint','testH4100AdaptationHorizon'});"
```

Choose a new label if a receipt already exists. These checks do not establish
full H4 acceptance. The full-suite command is documented in
[testAll command](#testall-command), but is not part of this handoff execution.

### B. Exact fresh 100 MHz / 4 GHz TDD command

Use the **100-slot adaptation YAML**, not the 60-slot check, 200-slot parent,
old 19-site scenario, or a laptop-local `tmp/` resume YAML:

`simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml`

It retains 273 PRBs, 30 kHz SCS, normal CP, 4096 FFT, 122.88 MSa/s,
CDL-C/100 ns, 64 gNB TXRUs, four-chain UE, maximum DL/UL rank four,
four SSB/eight CSI-RS beams, physical access/control/CSI/SRS/TRS/HARQ,
configured RF impairments and completed-slot checkpoints every five slots.
Rank is selected causally; maximum rank four does **not** force every grant
to rank four. Configured 40 dB is the normalized occupied-RE reference, not a
promise of 40 dB receiver SINR or calibrated absolute dBm.

First inspect the command without executing MATLAB or writing evidence:

```bat
"%PYTHON_EXE%" "scripts\run_server_lls.py" --matlab "%SIXGR_MATLAB_EXE%" --scenario "simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml" --tag h4_server_01 --plan
```

Then run this **single line** from the server checkout:

```bat
"%PYTHON_EXE%" "scripts\run_server_lls.py" --matlab "%SIXGR_MATLAB_EXE%" --scenario "simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml" --tag h4_server_01
```

Use `h4_server_02`, etc., for a new attempt. This wrapper:

- Requires a clean tracked checkout and existing committed YAML; records the
  commit, YAML hash, OS/Python and MATLAB/toolbox versions.
- Launches the existing `run_6g_phy_lls_single` once, with filesystem output and
  the selected Python renderer. It changes **no PHY/scenario thresholds**.
- Rejects checkpoint-resume YAMLs and existing run/log destinations. It never
  retries automatically, starts another scenario or launches `testAll`.
- Requires MATLAB exit code zero, a true `out.Ok` receipt and unchanged source
  for launcher status `scenario_passed`. Missing receipts/crashes are not passes.
  A scenario pass still does not constitute statistical BLER/HARQ qualification.

Expected locations (use the printed/saved `RunFolder` as final authority):

| Content | Location |
| --- | --- |
| Launcher/console/terminal status | `logs/server/h4_server_01/launcher.json`, `matlab.log`, `scenario_receipt.json` or `matlab_failure.json` |
| Runtime environment | Same log folder: `matlab_environment.json`; Python package list in `logs/server_python_environment.txt` |
| Run root | `results/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/h4_server_01/` |
| Measured trials/access/control | Run root: `air_interface/csv/` and `air_interface/logs/` |
| Resolved configuration/identity | Run root: `meta/` (keep the entire directory, not only the leaf YAML) |
| Reports/plots/channel/IQ | Run root: `reports/`, `beamforming/`, `channel/` and the other generated component subdirectories |
| Committed checkpoint pointer | Run root: `meta/latest_slot_checkpoint.json` |
| Private restart state | `results/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/.checkpoints/h4_server_01/` |

For a larger results volume, add `--results "E:\SixGRResults"` to the launch
command **only if that drive exists and has sufficient space**. In the dashboard
Command Prompt also set `SIXGR_RESULTS_ROOT=E:\SixGRResults`. Logs remain in the
one source checkout. The separate results location is data, not another branch.

### C. WebGUI and remote monitoring without starting a duplicate

Open a **second Command Prompt on the server**, not the laptop:

```bat
cd /d "C:\SixGR\6gr-simulator"
set "SIXGR_MATLAB_EXE=C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "apps\start_lls_web_dashboard.ps1" -BindHost 127.0.0.1 -Port 62906 -NoBrowser -SkipFirewallRule
```

On the server open **http://127.0.0.1:62906/** and select `h4_server_01`.
Starting this dashboard does not start MATLAB. **Do not click Run again** to
view a CLI-launched scenario. Filesystem run discovery supports this workflow;
MySQL is optional for this filesystem run, not a prerequisite to simulate it.
Configure a private login using `apps/.env.example` as a template and keep real
credentials only in ignored local files. Do not expose this development server
directly to the Internet or share its auth file with diagnostic evidence.

For access from the laptop, use the server's remote desktop, or an approved SSH
tunnel if SSH is already enabled there. In a laptop Command Prompt, replacing
`YOUR_USER` and `YOUR_SERVER` with actual values:

```bat
ssh -N -L 62916:127.0.0.1:62906 YOUR_USER@YOUR_SERVER
```

Then open **http://127.0.0.1:62916/** on the laptop. Port 62916 avoids a conflict
with the laptop's own 62906 dashboard. SSH setup/authentication is site-specific;
this command does not install or configure an SSH service.
For text-only monitoring, run on the server in a separate terminal:

```bat
powershell.exe -NoProfile -Command "Get-Content -LiteralPath 'C:\SixGR\6gr-simulator\logs\server\h4_server_01\matlab.log' -Tail 60 -Wait"
```

GUI state can lag behind expensive exports. The authoritative completion is
the final scenario/launcher receipt plus validated artifacts, not a green card,
a last-slot CSV or a process that is still rebuilding reports.

### D. Send failures and measurements back to this laptop

Do not delete, truncate, relabel or edit failed-run measurements. First let the
run exit, or stop it deliberately at a verified completed checkpoint. Confirm
that no producer is still writing the selected run. **A stopped failed run is
not a pass.** Keep all IQ/MAT, large paired CSVs, checkpoints and external archive
targets on the server; the initial triage bundle is deliberately much smaller.

On the server, after the run has stopped:

```bat
cd /d "C:\SixGR\6gr-simulator"
"apps\.webgui-venv\Scripts\python.exe" "scripts\collect_server_evidence.py" --run-folder "results\lls\h4_100_cdlc100_connected_impaired_40db_adaptation\h4_server_01" --log-folder "logs\server\h4_server_01" --output "logs\handoff\h4_server_01.zip" --include-images --confirm-stopped
```

The ZIP includes unchanged CSV/JSON/YAML/log/text and optional PNG/SVG files up
to **16 MiB each**, with a **512 MiB uncompressed total** by default. Its
`manifest.json` lists each included file's SHA256 and **every omitted file with
the reason**. It does not silently truncate a CSV. MAT/IQ/binary files and
symlink/junction targets are not copied. Increase `--max-file-mib` and
`--max-total-mib` only when the particular large diagnostic files are needed.
`--confirm-stopped` is your confirmation, not an automatic MATLAB process stop.
Files changing during a copy cause rejection, not a fabricated consistent bundle.

Send both `h4_server_01.zip` and `h4_server_01.zip.sha256`. Also send
`logs/server_python_environment.txt` and any focused preflight/test log bundle.
Review logs for sensitive host/project information before sharing. No secret
environment files or raw environment-variable dump are collected by the helper.

On **this laptop**, place them under the ignored `logs/server_returns/` folder,
not over an existing local run. For example, after copying the two files from
an approved share/USB/SSH transfer:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs\server_returns" mkdir "logs\server_returns"
powershell.exe -NoProfile -Command "$p='logs\server_returns\h4_server_01.zip'; if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ine (Get-Content -LiteralPath ($p+'.sha256') -Raw).Trim()) { throw 'Transfer checksum mismatch' }; Expand-Archive -LiteralPath $p -DestinationPath 'logs\server_returns\h4_server_01'"
```

Tell me the extracted folder path, run tag, last observed slot, whether MATLAB
exited or was manually closed, and which GUI/table value looked wrong. I can
trace errors and measurements to the exact recorded commit, fix the main
MATLAB/Python/YAML implementation here, run the affected regressions and push
the repair. On the server, preserve the old evidence and update with the clean
`git pull --ff-only` procedure **only while no run is active**.

If the run fails before a result folder exists, send its complete
`logs/server/h4_server_01/` folder directly. The collector requires an existing
run directory. If it crashes during packaging, keep the incomplete ZIP but do
not treat it as complete: a completed package has `manifest.json` and a checksum
sidecar. Use a new package filename for the retry.

### E. Checkpoint restart and transfer limitations

For the first higher-capacity-server verification, **start fresh from slot 0**.
Do not move the laptop's slot-45 `state.mat` alone and expect portable resume:
checkpoints bind the exact MATLAB version, configuration/source identity,
saved absolute run paths, external file prefixes and channel archive ownership.
Cross-host/path remapping is **not qualified**. A diagnostic ZIP is neither a
full archival copy nor a runnable checkpoint.

On the **same server/path**, after an identified failure, inspect
`meta/latest_slot_checkpoint.json` and follow
[completed-slot restart checkpoints](#completed-slot-restart-checkpoints).
Review whether a fix invalidates state already saved before choosing a boundary.
After slot 45 means restart at slot 46, not at slot 45. A source-changing resume
needs an explicit repair reason and is labelled repair validation. Scientific
configuration changes require a fresh run. Do not edit source while resuming.
The fresh-run launcher intentionally refuses resume YAML; use the documented
direct MATLAB entry point after this review.

For complete archival transfer, retain **the entire run root, its sibling
`.checkpoints/<tag>/`, launcher logs, and all external `channel/mat` targets and
ownership receipts**. A Windows junction is not a copy of its target. Preserve
original path/hash metadata; do not rewrite it to imply a run happened on the
laptop. Keep large archives on the server unless they are needed for a specific
receiver replay. Neither storage reduction nor missing-source substitution is
an accepted repair.

### F. Other scenario commands

The same fresh-run launcher accepts another committed LLS YAML via `--scenario`
and a new tag. Choose a single scenario, not all rows at once:

| Intended execution | YAML / existing command section |
| --- | --- |
| 5 MHz 20 dB saturated traffic | `simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml` |
| 5 MHz eight-point sweep | `simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml` |
| 100 MHz H4 adaptation | `simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml` (**first priority**) |
| 400 MHz control-disabled research IQ benchmark | `simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml`; not H4 full physical-feedback acceptance |
| LLS calibration | [Generic LLS BLER/HARQ calibration](#generic-lls-blerharq-calibration-bounded-collection-not-qualification); separate resumable collector, not this fresh-run launcher |
| SLS | [YAML-selected LLS and SLS](#yaml-selected-lls-and-sls); matching accepted calibration is still required, not supplied by a 100-slot H4 pass |

For example, after H4 work and with no competing run:

```bat
"%PYTHON_EXE%" "scripts\run_server_lls.py" --matlab "%SIXGR_MATLAB_EXE%" --scenario "simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml" --tag five_mhz_server_01
```

## Interactive 100 MHz LLS documentation

The [H4 field guide](docs/lls/h4_100mhz_guide/README.md) explains the
4 GHz / 100 MHz TDD configuration in 34 chapters, with interactive diagrams,
clickable current MATLAB source, a 3GPP/MATLAB/SixGR comparison, resolved YAML,
and searchable scenario/parameter catalogs. It is read-only documentation
inside this main checkout; opening it does not launch a simulation.

Windows Command Prompt, one line:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && "C:\ProgramData\anaconda3\python.exe" "docs\lls\h4_100mhz_guide\serve.py" --port 62907
```

Then open **http://127.0.0.1:62907/**. Catalog declarations and teaching
illustrations are explicitly separate from accepted waveform results.

## 16 October: main-folder core repairs

Continued development uses this repository and its existing `main` branch only.
The audit's temporary isolated patch has been consolidated without overwriting
pre-existing edits. Original receipts are retained under
`logs/lls_repair_consolidation_20261016`; their original source paths are not
rewritten to imply they ran in main. The isolated batch passed 42 affected
MATLAB tests. Main-folder verification now passes **44/44 affected MATLAB
checks and 82/82 Python export checks**, including receiver-delivery timing.
Receipts: `logs/lls_repairs/main_consolidated_20261016_v1/receipt.json` and
`logs/lls_repair_consolidation_20261016/python_main.xml`. The temporary working
copy has been removed to the Recycle Bin; a verified ZIP is retained in the
consolidation log directory for recovery, not as an executable codebase.
The separate physical PUSCH-UCI variant also passes, as do the manifest,
exact scheduler TBS/grant and proxy-guard checks. These are additional
affected checks, not a claim that all historical failures are closed.

The [35-item repair matrix](docs/repairs/repair_matrix.md) and
[export contract](docs/repairs/export_contract_v2.md) distinguish focused fixes
from remaining integration and qualification work. The 100-slot H4 run is
**not yet accepted**; neither the isolated checks nor the main-folder checks
are a full scenario or statistical calibration result.

Transport-identity follow-up: **14/14 affected final-source checks pass**, and
both expanded physical PUCCH/PUSCH packet-publication variants pass. Core
reservation/delivery no longer substitutes MAC or current-attempt IDs for an
existing logical TB; contradictory aliases and mismatched RX/TX TB/NDI epochs
are rejected. Packet matching includes the stable logical UE. Actual DL/UL
packet mappings retain measured receiver-availability timing, while metadata
mapping is explicitly distinct from application-byte delivery. The corresponding
receipts are under `logs/lls_repairs/tb_identity_final_source_20261016_v1` and
`logs/lls_repairs/tb_packet_physical_final_20261016_v1`; the PUSCH CSVs are in
`logs/lls_repairs/tb_packet_pusch_final_20261016_v1`. Session/configuration-epoch
migration and full shared-runtime multi-TB reassembly qualification remain open;
no 100-slot or statistical acceptance is implied.

Packet-delivery follow-up: the production SDU reducer now retains the first
successful decoder proof through duplicate and later failed attempts, with
separate `LastAttemptProtocol*` fields. Application completion checks the logical
UE/direction/application owner and exact fragment coverage. A new two-TB coded
PDSCH test reproduces the former duplicate-proof loss and cross-UE completion,
then passes after repair. Five focused checks pass in
`logs/lls_repairs/packet_reassembly_after_20261016_v1/receipt.json`.
Its duplicate/failure callbacks are injected component events, not additional
measured radio attempts or BLER samples. Final fresh-process verification passes
**9/9 affected checks**, including the physical PUCCH path, and the separate
physical PUSCH-UCI variant also passes. Receipt and unchanged-source hashes:
`logs/lls_repairs/packet_delivery_final_20261016_v1/verification.json`.
The shared physical tests retain CRC-backed metadata mappings; they do not
claim protocol application-byte delivery when that mode is disabled.

Adaptation follow-up: duplicate CSI/SRS callbacks were reproduced as false
rank-confirmation events and are now ignored before scheduler-state mutation.
Older-source and backward-delivery events cannot replace newer accepted quality.
Fragment numbering also now uses the logical UE/application owner. Seven affected
checks pass in `logs/lls_repairs/adaptation_delivery_final_20261016_v1/receipt.json`;
these are consumer-boundary checks, not complete H4 adaptation qualification.

CSI storage follow-up: shared CSI-RS completion now retains complete EVM pairs
in checksum-bound MAT details instead of copying large JSON arrays through live
trial tables. The 273-PRB/64-port fixture retains all 559,104 paired samples
exactly, reducing its live row from 90.4 MB to 5.4 KB. Scalar measurements and
expanded sample CSV semantics are unchanged. Missing/corrupt details still fail
validation. Focused receipts: `logs/lls_repairs/csi_detail_after_20261016_v1` and
`logs/lls_repairs/csi_detail_clock_repaired_20261016_v1`. This is not a full-run
memory or throughput qualification.

Affected checks only, from Windows Command Prompt (use a new label each time):

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_repairs_manual_01.log" -batch "addpath(fullfile(pwd,'scripts')); runLLSRepairRegression('manual_01');"
```

This runs 50 explicitly listed affected tests, **not `testAll`**. The two
new transport-identity guards were also verified in a separate 14-check batch;
the packet-delivery guard is separately verified. The earlier 44-check receipt
remains historical evidence, not a 50-check claim. The added CSI detail-storage,
shared-receiver and event-retention checks have separate focused receipts. Receipts are
saved in `logs/lls_repairs/manual_01/receipt.json`. Do not run it concurrently
with a full scenario or modify source during either execution.

## Current LLS commands and acceptance status (15 October 2026)

These commands are for **Windows Command Prompt (`cmd.exe`)**, not PowerShell.
They document the executable entry points; they are **not a claim that every
scenario is accepted on this revision**. Run one job at a time. Use a new run
tag and log filename for each scenario execution; never delete active results.

The 15 October 4 GHz / 100 MHz TDD attempt, `h4_100mhz_4ghz_short_20261015_v4`,
failed at slot **30/60** because the shared waveform completion dropped its
registered random-access observation `ID`. Its recovery/export process was
subsequently stopped at the operator's request; all written evidence is retained.
The earlier `h4_100mhz_4ghz_short_20261014_v3` failed at slot 49/60 on stale
QCL/TRS timing. Neither run is accepted. The dropped-ID and causal-timing
repairs are now in the main codebase, not in a separate execution checkout.
Full connected DL/UL, physical CSI/UCI-driven adaptation, beam refinement and
complete CSV/PNG publication still require integrated acceptance. The 5 MHz
scenarios and historical 400 MHz benchmarks are not substitutes for that gate.
No full `testAll` is launched by the commands below. Current repair verification
is limited to affected tests at the operator's request. SLS remains on hold.

The 15 October consolidation includes the **43 previously staged repair files**
in the single `main` worktree, together with the preceding core PHY, RF,
configuration, WebGUI and publication edits. No source on `D:\SixGR\repairs`
is needed to use this checkout. Future work and the commands below use the
repository itself; retained external logs are historical evidence, not another
code branch. The **40 affected MATLAB tests passed on consolidated commit
`d4092466`**, including the actual RA callback and full-band RF component checks;
the receipt is `logs/h4_main_affected_20261015_v2/receipt.json`. The **39 affected
Python checks passed again on the consolidated main-folder code**. These are
focused results, not complete scenario or statistical qualification.

A subsequent core PDCCH reporting repair separates the decoder's RNTI-masked
CRC from semantic acceptance and transmitted-payload agreement. Six affected
checks pass, including coded-IQ replay with a poisoned TX audit, independent
connected monitoring, shared physical reception and strict grant-binding
publication. The grant rejection checks remain intact. A scheduler check
initially lacked `tests/helpers` on the launch path and passed when that
existing helper path was installed. The older standalone control-export test
remains blocked by its missing `pdcch_strict.validation_campaign` configuration;
its failure is retained, not converted into a pass or a default campaign.
See `logs/h4_pdcch_crc_20261015_v1/receipt.json` and `prelaunch_receipt.json` in
the same directory. This independent qualification-fixture issue is separate
from the H4 connected receiver and remains pending before broad acceptance.

| Integrated repair | What remains to be verified on the consolidated revision |
| --- | --- |
| Registered RA observation/timer identity survives physical completion | Full initial access beyond the slot-30 failure |
| TRS applied timing, CSI/reference SINR planes and SSB beam/branch power identity | Same-execution receiver-to-CSV/WebGUI reconciliation |
| Actual AGC gain range and exact cropped ADC/DAC error/clipping populations | Full H4 RF operating point; converter MSE is not demodulated EVM |
| Attempt goodput, HARQ terminal/censored populations, committed IQ scope and exact RE-map preservation | Complete DL/UL and terminal artifact acceptance |
| Separate 100-slot adaptation YAML with unchanged physical feedback calendars | Two received CSI confirmations followed by future adaptive grants |

The verification configuration is **100 total slots / 50 ms**, including
initial access, not 100 data slots. Completion and acceptance require the
specific run's terminal receipt; this source commit and the commands below
are not a passing 100 MHz result. The following paragraphs retain earlier, explicitly scoped
component evidence; they do not supersede this current status.

The latest follow-up has **13 affected tests passing**: standalone SR acquires
its current receiver-known sequence even when an optional retained UL clock
has expired; HARQ-bearing format-0 still requires a fresh measured clock.
Zero-energy SR remains DTX with timing unavailable. Capture replay retains
exact samples and verifies the Windows short-path readback checksum. Symbol
exports now use the NR CP-specific clock, explicitly declare their slot base,
and leave unobserved symbols unavailable instead of recording measured zeros.
The retained H4 DL row matches its transmitted sample clock without modifying
that failed run. Data-beam selection is exported separately from actual P2
refinement events. These are focused receiver/reporting checks, **not full
scenario, beam-refinement, detector-statistics or calibration acceptance**.
The two-report H4 physical component now **passes all 40 slots**. Both slot-19
and slot-39 CSI/SR PUCCH occasions independently decode 15/15 bits. The first
received RI=2 leaves the scheduler at rank 1; the second confirming RI=2
accepts rank 2. The canonical frame/slot binding fixes the earlier slot-26
fixture error without weakening the production clock guard. This test uses
explicit preconnected access/TAG inputs: it does not qualify initial access,
subsequent data grants, activated TCI or the complete 200-slot scenario.

The H4 received-TCI admission guard had two additional core defects: states
before DATA_ACTIVE could admit an unrelated codepoint, and staging a new CSI
candidate revoked the still-active previous beam. `CoupledTruthRuntime` now
rejects missing/mismatched active bindings and acquisition/failure/recovery
states under the required-TCI policy. A previously activated beam remains
usable while refinement is pending, without activating the new candidate.
Five affected tests pass, including two actual logical-port PDCCH decodes,
29 admission checks, pending-beam preservation and frozen TCI/grant binding.
The adjacent beam fixture now resolves its TRS start from the installed
calendar rather than the obsolete slot-8 constant; the timing guard remains.
See `logs/h4_tci_admission_20261014_v3/receipt.json`. Declared beam-state inputs
remain component fixtures, not full physical beam-refinement acceptance.

Large shared-channel archives now use exact time-contiguous, shuffled HDF5
compression through the existing staged MAT publisher. Native MAT metadata,
numeric precision, coefficient hashes and mandatory destination readbacks
are retained. The serializer's 16 numeric round-trip cases and four affected
publication/archive tests pass, including a physically executed H4 64-TXRU /
four-RX capture with 12,582,912 coefficients and bounded verification reads.
This preserves the v2 archive contract; it is not decimation or reconstructed
channel evidence. The subsequent full-slot preflight also passes: 61,440
samples, 377,487,360 complex-double coefficients, complete coefficient hashes
and an exact frozen-time readback. It took 1,207 seconds and produced a
2,363,299,222-byte MAT archive; see
`logs/h4_full_slot_archive_20261014_v1/receipt.json`. That test is channel/archive
execution, not scheduled data decoding or full-scenario acceptance.

`SharedWaveformPhysicalRuntime` now preserves value-shared coefficient arrays
when a capture spans the complete processor interval, instead of creating a
second full-range slice. Partial-window slicing and request-specific clocks
remain unchanged. Four affected runtime/archive tests pass, including exact
overlap comparisons, observer/RNG invariance and H4 capture/export. A separate
128-MiB MATLAB allocation probe measured 134,221,824 additional private bytes
for the old slice and zero for value sharing; this is not a measured full-run
peak-memory reduction. Evidence is under
`logs/shared_channel_capture_allocation_20261014_v1`. The full-slot preflight
above preceded this additional allocation repair; the post-repair H4 archive
regression uses 2,048 samples. Whole-run disk capacity and the 200-slot memory
gate remain unverified, and no measurement precision or coverage was reduced.

The compact shared-data scoring observation now preserves the executed RX
endpoint's timing, CFO and RF-stage metadata instead of dropping it before
NMSE reference alignment. Missing metadata still fails; no injected value is
used as a receiver estimate. Three affected tests pass, including actual shared
DL/UL channel-estimation CSV/MAT round-trips. The receipt is
`logs/shared_rx_clock_metadata_20261014_v2/receipt.json`. This component evidence
does not establish sustained impaired H4 data execution.

Seven final-worktree shared-HARQ protocol checks also pass: Type-2 gaps/wraps,
installed resource planning, scheduled DAI, producer-row identity, commit
receipts, stale/duplicate feedback and grant disposition. They include 256 DAI
sequences and preserve failed physical trials as failures rather than missing
trials. The receipt is
`logs/shared_harq_protocol_closure_20261014_v1/receipt.json`.
These declared protocol inputs are not a physical missed-DCI or detector-rate
qualification; the physical negative-path and combined-UCI gates are separate.
The subsequent six-check batch also passes: two mapping checks, actual absent
PUCCH/PUSCH observations, rejected UL control with due HARQ, and two rejected
UL commands with receiver-owned soft combining. The absent PUCCH returns DTX;
the absent PUSCH fails CRC; no UE TB transmission or successful delivery is
invented. Known-candidate control and declared connected timing inputs limit
these cases to physical components, not acquired blind-control or statistical
qualification. See `logs/shared_harq_physical_negative_20261014_v1/receipt.json`.
The absent-PUCCH files are additionally preserved under that folder's
`pucch_receive_only_evidence` subfolder; their byte hashes match the original
temporary files. Embedded source paths were not rewritten.

Independent combined PUCCH and PUSCH CSI reception also pass after removing
UE producer bookkeeping and poisoning optional TX references; received fields
remain unchanged. Late PUSCH delivery passes. The late format-2 PUCCH test
initially stopped before PHY execution because its 20-slot CSI-report calendar
inherited a five-slot recovery gap. Its dedicated YAML now declares a 20-slot
gap, retaining two-report confirmation and the production cadence validator.
The cadence negative guard and the unchanged physical late-PUCCH assertions
both pass. Original failures remain in
`logs/shared_combined_uci_closure_20261014_v1/receipt.json`; the repaired rerun is
`logs/shared_late_pucch_cadence_repair_20261014_v1/receipt.json`. These component
tests do not qualify detector probabilities or the full impaired H4 scenario.

The generic CSI-SINR discrepancy remains open. A separate 64-episode paired
diagnostic found native disturbance estimation bias on noise-only grids and
additional estimator self-noise on a frequency-selective reference. Its raw
audit inputs are not supplied to the production estimator. No fitted noise
correction, injected-noise substitution or relaxed acceptance assertion has
been introduced; the H4 configured CSI-IM measurement path is distinct.

The CSI-IM path had a separate signal-power bias: squared smoothed channel
estimates counted estimation noise as desired CSI-RS power. It now measures
port 3000 with local CDM projections and subtracts their analytically derived
disturbance contribution using the configured, actually observed CSI-IM REs.
Signed powers are retained; no signal level is forced positive. The estimator
records its locally uncorrelated-disturbance assumption and does not claim an
unbiased dB value or diversity-selected maximum. The native channel estimate
used for CSI/PMI is unchanged and its power remains a separate diagnostic.
Native `CDM4`/`CDM8` names now map to their actual frequency/time CDM lengths.
Five affected tests pass, including 4,096 measurement trials across 16 paired
CDM/SNR populations, eight-resource H4 grid reception, signed per-branch
publication, and exact unit conversion. A negative branch no longer hides
another branch's valid measurement; unexplained missing values still fail.
See `logs/csi_im_power_repair_20261014_v3/receipt.json`. This does not close the
generic no-CSI-IM estimator discrepancy or establish full RF/scenario acceptance.
The subsequent physical batch passes all three tests, including the six-slot
64-by-4 H4 CDL-C/RF CSI-IM receive occasion and its exact receiver-JSON CSV
round-trip (`logs/csi_im_power_physical_20261014_v1/receipt.json`). Another
focused check passes all 18 native CSI-RS rows in 38 density/partial-band
mapping cases (`logs/csi_cdm_geometry_20261014_v1/receipt.json`). Neither
receipt represents the complete 200-slot connected scenario.

The shared SRS scoring reference now uses the configured complete SRS port
set for CDM despreading, matching the practical receiver's existing geometry.
The old generic first-two-sequence inference selected two-port despreading for
a four-port reference. The repair changes independent scoring, not the
receiver's noise, RI/TPMI, waveform power or acceptance threshold. Actual
prepared/received four-port tests cover combs 2 and 4 and poison the scoring
reference without changing receiver decisions.

The H4 SRS YAML also now explicitly selects `C_SRS=61, B_SRS=0`: its actual
native allocation is **272 of 273 carrier PRBs**, within the existing one-edge-RB
coverage policy. The inherited `C_SRS=6` previously generated only 24 PRBs;
changing `num_rb` alone did not override that native table index. The production
SRS runner now rejects an invalid installed configuration before waveform
preparation instead of ignoring the strict validator. The coverage guard,
scoring-geometry and unchanged short-gate configuration checks pass in
`logs/srs_runtime_coverage_20261014_v1/receipt.json`. This is not yet full H4
receiver or complete-scenario acceptance; those physical gates remain separate.
The six adjacent regressions also pass in
`logs/srs_adjacent_runtime_20261014_v1/receipt.json`: full-carrier tolerance,
causal scheduling, configured-band reception and negatives, standalone scoring
timing, measured SRS-to-UL adaptation, and canonical wideband runtime reception.

The next exact H4 SRS capture exposed a separate scoring-clock mismatch:
the noiseless desired-link reference excluded the executed RX delay/CFO,
while the practical receiver operated on the post-RX-RF samples. The core
completion path now retains that execution metadata and aligns only the
post-reception scoring reference. The practical channel estimate, noise,
RI/TPMI and scheduling inputs are unchanged. The full-band four-port SRS /
64-RX CDL-C/RF component passes in
`logs/h4_shared_srs_scoring_20261014_v8/receipt.json`: **-26.05 dB NMSE**, with
the old unmatched-clock **+2.02 dB** comparison preserved separately. The
original -8 dB gate is unchanged. This is one SRS occasion with declared
access/TAG boundary inputs, not a full access/data scenario or statistical
qualification.

`testSRSReceivedScoringClock` also passes its three delay/CFO cases and
scoring-only metadata poisoning checks. The WebGUI exposes the raw and
phase-equivalent scores, reference plane, and scoring-only recorded RX
delay/CFO separately from receiver estimates. **60 affected Python tests
pass**, and the actual H4 CSV retains those values through the preview path.
Neither this scoring correction nor that display is oscillator qualification.
The subsequent eight affected MATLAB checks pass in
`D:/SixGR/logs/h4_srs_final_source_20261014_v1/receipt.json` (shared receive-only
feedback, SRS timing/configuration, short-run configuration, config and DL/UL
reference regressions). The derived public SRS measurement table also retains
the same scoring clock fields without substituting injected RF values for
missing evidence; its integrity and public-claim checks pass in
`D:/SixGR/logs/srs_public_scoring_clock_20261014_v1/receipt.json`.

The beam-publication follow-up passes **264 affected Python tests**, including
the CSV/plot semantic checks. The WebGUI materializer no longer truncates the
beam table at 1,024 rows or the beam timeline to its first 180 observations.
Selected and best-beam series retain every observed slot, separated by sweep
point, execution, direction, UE, cell and source in the same chart/CSV.
Configured TCI/QCL values are exported separately from runtime observations;
zero is retained as a valid ID. The tests inspect the rendered series and PNG
conversion. This is publication verification, **not physical P2 refinement or
complete-scenario acceptance**.

The UL SRS-to-scheduler consumer now honors the configured rank-confirmation
hold, retains the prior decision's age while held, and remembers accepted
rank per UE. Fresh PUSCH quality can be retained only for matching RI/TPMI;
it cannot become quality for a different SRS spatial decision. **Eight
affected MATLAB tests pass**, including independently executed confirming
SRS occasions, measured CQI-zero outage, OLLA ownership and frozen grants.
The two-report policy is a configured receiver/scheduler policy, not a claim
that 3GPP mandates exactly two reports.

CSI public exports and WebGUI distinguish decoded RI from accepted rank,
confirmation counters and reference-resource timing. UE-private SINR is not
presented as received CSI-UCI. The six-test rank/export batch and **79 Python
checks pass** (two MATLAB tests overlap the eight above). These results do
not establish full 100 MHz connected UL/DL, beam refinement, statistical
qualification or final publication acceptance.

### Command Prompt setup and optional WebGUI

Run these two setup lines first (the separate `if` line also works when `logs`
already exists; do not chain MATLAB behind `&& if not exist ... mkdir ...`):

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs" mkdir "logs"
```

In a **second** Command Prompt, start the existing dashboard without launching
another simulation:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\apps\start_lls_web_dashboard.ps1" -Port 62906
```

Open `http://127.0.0.1:62906/` and select the exact run tag. MATLAB batch execution
does not itself start the WebGUI. All commands assume MATLAB R2026a and the
repository dependencies are installed; a different MATLAB version requires its
own verification and calibration, not reuse of a version-mismatched dataset.

### 5 MHz TDD: saturated 20 dB or eight-point AWGN sweep

The first YAML retains physical access/control, CSI/SRS and adaptive rank up to
two. The sweep is a separate YAML with `[40,30,20,10,0,-10,-20,-30]` dB configured
reference points. Configured SNR is not a measured post-equalization SINR.

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_5mhz_20db_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml','results','lls_5mhz_20db_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'Scenario acceptance failed; preserve results and log.');"
```

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_5mhz_sweep_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml','results','lls_5mhz_sweep_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'Sweep acceptance failed; preserve parent and child artifacts.');"
```

### 100 MHz / 4 GHz H4 TDD: single gate before the sweep

The impaired H4 YAML resolves 273 PRBs, 30 kHz SCS, normal CP, 4096 FFT,
122.88 MSa/s, CDL-C/100 ns, 64 gNB TXRUs, four UE TX/RX chains, four SSB beams,
eight CSI-RS/data beam states, rank 1/2/4 adaptation, and a 10-DL/2-guard/2-UL
special slot. The configured RF profiles are research assumptions, not hardware
qualification. Beam-failure recovery is not enabled; normalized received power
must not be labelled absolute dBm. **Full scenario acceptance is still pending.**

The next verification uses
`simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml`:
**100 total slots / 50 ms**, including initial access. The number of actual data
grants is determined by the receiver/scheduler, not promised by the duration.
CSI report occasions retain one-based slots 19, 39, 59, 79 and 99; an occasion
is usable only when its causal reference/control obligations are satisfied.
Bandwidth, antennas, reference-signal cadences, enabled RF impairments,
acceptance thresholds and enabled exports are retained. The adaptation YAML
also includes `simulator/configs/rf/causal_agc_burst_headroom.yaml`: receiver
target RMS 0.25, a 6 dB next-sample gain reduction on a pre-ADC I/Q rail flag,
and a 128-sample hold. These are explicit receiver-design research settings,
not 3GPP-mandated AGC values or hardware qualification. The original 200-slot
parent keeps its RMS-only AGC profile for comparison. No clipped sample is
reconstructed, and no TX power, channel noise or detector threshold changes.
Pending feedback beyond the
horizon remains right-censored, not silently counted as successful. This is
not statistical BLER qualification. Run this command only after the affected
final-source repair checks are accepted and scenario execution is resumed:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\h4_100mhz_40db_adaptation_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml','results','h4_100mhz_40db_adaptation_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'H4 adaptation acceptance failed; preserve results and log.');"
```

Expected result root:
`results/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/h4_100mhz_40db_adaptation_manual_01/`.
Use the actual printed `RUN_FOLDER` as authority and a new tag/log name for
every attempt. Check the current log and live run state before launching;
do not start a duplicate while an adaptation run is active.

#### Completed-slot restart checkpoints

The adaptation YAML enables `run_control.runtime_checkpoint_enable` with
`checkpoint_every_slots: 5`. The default `runtime_checkpoint_keep: 3` retains
the latest three completed save points. A failure during one-based slot 42
can continue from the saved **end of slot 40**, executing slot 41 next;
a failure during slot 48 can continue after slot 45. A checkpoint cannot
be reconstructed retrospectively from an older CSV-only run.

`meta/latest_slot_checkpoint.json` inside the result folder identifies the
latest committed MAT checkpoint. Private state is stored alongside the run
under `.checkpoints/<run-tag>/`, outside the published run tree, so plot/CSV
reducers cannot ingest old failed-attempt data. This is saved execution data,
not another codebase or branch. The checkpoint retains the shared physical
channel/RF/event objects, pending observations/grants/feedback, runtime and
link-adaptation state, decoder objects, trial tables and random-generator
state. External IQ prefixes are byte-count/hash checked before restoration.
The previous failed attempt is preserved under a `recovery_*` directory in
that private checkpoint store; it is not overwritten or deleted. Rolling
retention removes only older generated checkpoint snapshots, not run evidence.

To continue, stop the failed process first, then set the following in the
same YAML and invoke the same `run_6g_phy_lls_single` command:

```yaml
run_control:
  runtime_checkpoint_resume_from: 'C:/absolute/path/from/latest_slot_checkpoint.json/state.mat'
  runtime_checkpoint_repair_reason: ''
```

Use the actual `Checkpoint` value from the JSON, not the illustrative path
above. The original run tag/folder and scientific configuration are retained.
A changed source is rejected unless an explicit repair reason is supplied
after checking that the fix does not invalidate earlier saved state. **All
checkpoint continuations are labelled repair-validation evidence and are not
clean-source study qualification.** Source hashes, repair reason and retained
attempt location are recorded in `meta/checkpoint_resume.json` and the scenario
manifest. Changes to bandwidth, channel, seeds, antenna/RF parameters, traffic,
timing or the scheduling horizon require a fresh run. Do not use a checkpoint
that already contains state produced by the defect being repaired.

Production restart also requires the actual runtime-call ledger captured at
the same completed-slot boundary. Checkpoint creation now flushes this
in-memory ledger before hashing/copying the prefix; execution identity is
persisted before the first waveform. An older checkpoint without
`reports/csv/runtime_call_ledger.csv` is rejected before moving run files.
Do not reconstruct those historical calls from trial outputs or copy a
later failed-attempt ledger into an earlier checkpoint. Use a complete
checkpoint or begin a fresh execution in that case.

Focused checkpoint mechanics cover real CDL/RF continuation, a pending receive
window and file rollback. Full 100 MHz resumed-scenario acceptance remains a
separate integrated check; enabling checkpoints does not declare that run passed.

The retained diagnostic attached at slot 40; this is an observation, **not an
attachment deadline**. Access progresses using the configured SSB/Type-0 SI
calendar, PRACH occasions, `random_access.ra_response_window_slots`,
`random_access.timing.*` processing delays, contention timer and
`random_access.preamble_trans_max` retry limit. The finite run horizon does
not fire these timers or force attachment. `control/csv/initial_access_horizon.csv`
records completed, terminally failed, or right-censored access separately,
without creating unexecuted physical trial rows.
The older **60-slot / 30-ms** YAML remains available as a short repair check.
With the unchanged two-report rank-confirmation policy, it may finish before
a confirmed rank change can be used by a later data grant. It is not proof
of completed rank adaptation. This is the optional short-check command, not
the next adaptation-verification command:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\h4_100mhz_40db_short_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_short.yaml','results','h4_100mhz_40db_short_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'H4 short-gate acceptance failed; preserve results and log.');"
```

`results` remains the repository results root. An external root such as
`D:/SixGR/results` may replace that argument when sufficient space is available;
this does not move or delete previous results. Verify the chosen disk budget
before launching. Logs in the commands remain under the repository `logs`.
One lossless full-slot channel archive measured 2.20 GiB; this is not a bound
on total storage per simulated slot. Check current free space rather than
reusing an earlier disk snapshot. The current commands deliberately keep
both logs and results in the main repository's folders. No historical files
were moved or deleted during consolidation.

The separate physical-budget child is
`simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_pathloss_short.yaml`.
It retains the 60-slot H4 PHY but enables TR 38.901 UMa NLOS path loss,
absolute array-input powers (30 dBm gNB / 23 dBm UE), and receiver thermal
noise. Its required legacy `snr_db: 0` is **not a requested SNR**:
`configured_snr_is_link_authority` is false. Received SNR/SINR and absolute
RS powers must come from the executed link; no extra gain compensates the
path loss. Shadow fading and O2I remain separately disabled. This child is
not an accepted full run and must not be mixed into the normalized SNR curve.
Its focused check is `testH4100AllocationAndPathloss` (allocation/loss-operator
scope only, not receiver qualification).

The retained slots 41/42 used 126 PRBs each: configured SSB reservations
covered PRBs 126–146, leaving two contiguous 126-PRB intervals. This was not
a 126-PRB BWP cap. Their MCS 1 / rank 1 grants were bootstrap decisions,
not CSI-driven throughput results. The first post-attach periodic CSI report
was due at slot 59, after the retained run had already aborted. Neither
full-band allocation through reserved SSB/DM-RS nor artificial early CSI is
a valid repair.

Original dedicated 40 dB diagnostic gate (200 slots; retained unchanged):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\h4_100mhz_40db_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml','results','h4_100mhz_40db_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'H4 acceptance failed; preserve results and log.');"
```

After implementation and the single-point gate are accepted, the separate
eight-point sweep command is:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\h4_100mhz_sweep_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_snr_sweep.yaml','results','h4_100mhz_sweep_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'H4 sweep acceptance failed; preserve parent and child artifacts.');"
```

### 400 MHz / 7 GHz research waveform and Keysight package

This is **400 MHz bandwidth at 7 GHz**, not the 4 GHz / 100 MHz connected H4
scenario. The fixed two-layer, 1024-QAM, rate-0.82 benchmark has idealized
AWGN/preconfigured control; it does not qualify shared physical PDCCH/PUCCH or
64-TXRU adaptive beam management. Historical successes need revalidation after
core changes. The four-layer adaptive alternatives and their calibration
requirements remain documented under [400 MHz commands](#400-mhz-commands).

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_400mhz_iq_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml','results','lls_400mhz_iq_manual_01'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'400 MHz acceptance failed; preserve results and log.');"
```

For the separate rank-two VXG/VSA digital handoff workflow (includes Python
packaging and browser checks; does not enable instrument RF):

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml" -RunTag "vxg_vsa_manual_01"
```

Physical instrument capability remains **UNKNOWN** until actual model/options,
bandwidth, sample rate and coherent-channel capability are verified.

### Generic LLS BLER/HARQ calibration: bounded collection, not qualification

The existing generic YAML is a **20 MHz-carrier, 24-PRB, SISO QPSK pilot**, with
AWGN references and TDL-A/30 ns fitting/validation. It does **not** calibrate the
100 MHz impaired rank-four or 400 MHz 1024-QAM scenarios. Do not start statistical
collection until the implementation being calibrated is frozen and verified.

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_calibration_manual_01_batch_01.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=run_link_calibration('configs/calibration/nr_dl_ul_harq_baseline.yaml','results/calibration','lls_calibration_manual_01'); disp(receipt);"
```

One invocation collects at most 292 new episodes. Resume with the **same run tag**
and a **new log filename**, only on matching source/config/MATLAB identity. Do not
loop until a statistical gate passes: inspect population/domain audits first.
The current pilot cannot meet production qualification; `PrimaryStudyAccepted`
remains false. [Calibration assumptions and population rules](#generic-dlul-bler-and-harq-calibration)
describe the required independent validation and conditional HARQ populations.

### Output locations and preservation

- Ordinary LLS: `results/lls/<scenario_id>/<run_tag>/`; use the printed
  `RUN_FOLDER` as authority. Sweeps retain child evidence plus joint parent
  tables/plots; a missing measurement is never manufactured to fill a curve.
- VXG/VSA package: `results/vxg_vsa/7ghz_400mhz_rank2_1024qam/<run_tag>/`;
  the launcher resolves the completed manifest and prints the actual folder.
- Generic calibration: `results/calibration/<run_tag>/`, including `episodes/`,
  `receipt.json`, source/config snapshots and population/domain/fitting audits.
- Console/launcher logs: `logs/` as explicitly named in each command.

GitHub contains source, YAMLs, tests and documentation. Runtime logs, results
and large IQ are intentionally ignored by Git and **must be transferred or
backed up separately**. A clean Git working tree does not mean those files were
deleted. Historical recovery stashes and archived patches are preserved; they
must not be blindly reapplied over newer production code.

## Current SLS delivery status (2 October 2026)

The repository provides YAML-selected LLS and SLS entry points, a network SLS
runner, calibration collection, causal CSI/SRS feedback, resource accounting,
and source-labelled exports. **This is not yet an accepted 21-cell study
result.** The production SLS template intentionally has no calibration file
or SHA256. The historical DL/UL SISO calibration was a population-design pilot:
292 episodes were collected in v5, 0/336 conditional audit rows qualified, and
the current v6 design has not been executed. Its SISO/ideal-RF key also cannot
validate the 4-by-4 network template. Statistical BLER/HARQ coverage, S0 load
calibration, integrated RF/array qualification and paired confidence intervals
remain open. The operator subsequently deleted the local calibration results;
the historical counts below are not currently available raw evidence and do
not establish a resumable or qualified dataset. Do not fill the empty calibration fields with a test fixture or
interpret an SLS execution receipt as primary-study acceptance.

Use the calibration command below to collect the next *pilot* increment. To
run SLS after an independently accepted, matching calibration exists, set
`sls.config.system.linkAbstraction.calibrationFile` and
`calibrationSHA256` in
`simulator/configs/scenarios/sls_network_calibrated.yaml`, then use the SLS
command in [YAML-selected LLS and SLS](#yaml-selected-lls-and-sls). Until those
fields and the matching physical coverage are supplied, that SLS command is
expected to fail closed; there is no honest "all scenarios ready" command.

## Generic DL/UL BLER and HARQ calibration

`run_link_calibration(configPath, outputRoot, runTag)` uses the existing
production PDSCH/PUSCH waveform adapters, independently of any agenda item.
The initial configuration is
`configs/calibration/nr_dl_ul_harq_baseline.yaml`: 4 GHz, 20 MHz carrier,
24 allocated PRBs, SISO QPSK / NR table-1 MCS 4 (308/1024), AWGN reference
and TDL-A/30 ns target, RV `[0,2]`. It explicitly uses practical DMRS channel
estimation, toolbox LDPC (custom MEX disabled), known noise variance, ideal timing and independent channel
realizations between attempts. These assumptions do not qualify RF-impaired,
multi-layer or correlated-channel HARQ cases.

Windows Command Prompt, from the repository root:

```bat
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\link_calibration_20261002_v6_01.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=run_link_calibration('configs/calibration/nr_dl_ul_harq_baseline.yaml','results/calibration','nr_dl_ul_20261002_v6'); disp(receipt);"
```

One invocation collects at most 292 new episodes and resumes the same tag
without rerunning committed episodes. Use a new launcher log filename when
resuming. Changed scientific configuration, source or MATLAB/toolbox versions
require a new tag; observations from different execution versions are not pooled.
The configured population-design pilot contains 14,746 episodes across two
directions, four independent roles and their Cartesian SNR histories. The
reference and fading-fit roles have 100 starts/history; the independent
held-out roles have one smoke episode/history and **cannot** qualify validation.
It is **not** a statistically accepted calibration. The four roles are reference
AWGN, independent reference-validation AWGN, fading fit and held-out fading
validation. The first invocation collects one starting TB per case/role/history.
Do not interpret the invocation budget as statistical sufficiency or loop
unattended before inspecting `population_feasibility.csv` and the
conditional-population audit. The feasibility file is a deterministic upper
bound from frozen starting TBs, **not observed trials**. Under the current
0.02 independent-AWGN BLER-difference policy, identical 95% Wilson intervals
at BLER 0.5 require at least **9,600 trials in each independent reference
cohort** even before allowing for sampling differences. The 100-start pilot
cannot qualify any conditional cell under its frozen population, even if
every eligible retransmission occurs. A separate fixed-population expansion
is required after an independent pilot; validation samples must not be reused
to choose that plan.

Reference and target coverage are now independent YAML fields:
`reference_snr_axis_db: [-24,-18,-12,-6,0,6,12,18]` and
`target_snr_axis_db: [-6,0,6]`. Widening the AWGN envelope no longer moves
the fading operating points. This is a pilot envelope, not a guarantee for
every fading realization or a qualified dense HARQ reference surface.
`reference_domain_audit.csv` checks actual fit-only per-RE features over the
declared beta bounds without consulting held-out outcomes or extrapolating.

`conditional_population_plan.csv` uses only reference/fit pilot episodes,
not validation CRCs. It estimates preceding-failure reachability with
one-sided exact binomial bounds and simultaneous Bonferroni protection,
then solves for a **fixed** fresh starting population. Reference cohorts use
the independent-pair planning floor rather than the generic 2,000-trial
minimum. This floor is necessary at the BLER transition, not a guarantee that
two random cohorts will pass the 0.02 bound. Zero observed preceding
failures, fewer than 100 pilot starts, or a requirement exceeding the declared
budget remain unsupported. No retransmission is forced after a successful CRC.
The plan is advisory: it does not top up a validation cohort until it passes.
Freeze accepted quotas in a new YAML/new run with independent seeds, using
`starting_population_overrides` entries with `case_id`, `role`,
`history_index` (MATLAB Cartesian order), and `starting_tbs`. Unlisted cells
use `populations`; fit and validation quotas are independently declared.
Actual conditional counts and confidence checks still decide acceptance.
Do not launch the entire provisional population until these pilot checks
establish feasible coverage and storage/runtime requirements.

The run retains source snapshots/hashes and `campaign.mat`, lossless physical
episodes with checksums, `receipt.json`, `conditional_population_audit.csv`
and `fitting_status.json`. Future episodes use lossless MATLAB v7 storage; an
exact load-and-compare probe reduced one episode from 1,095,096 to 33,511
bytes. `reference_validation` supplies a second physical AWGN population.
The numerical EESM fitter uses only fit CRCs to
select beta, validates each held-out history group, and rejects reused seeds,
unidentifiable beta and reference-domain extrapolation. Confidence and beta
search settings are implementation/study policy, not prescribed 3GPP values.
Collection completion and fitted reports do **not** install a production SLS
calibration: matching network-provider/allocation/RF keys and the complete
required coverage matrix must still be established.
An SLS curve may mark unobserved conditional grid cells unsupported. Its
runtime interpolation checks all required grid corners and rejects missing
coverage. Accepted curve cells still require real waveform counts, retained
independent AWGN validation and fit/held-out checks. First HARQ attempts are
recorded with `PriorAttemptsFailed=false`; later attempts require actual prior
CRC failures. Production source CSV rows must resolve to retained, checksum
protected decoder episodes and agree on SNR history, MCS, rank, TBS, ports,
channel, ideal-RF branch, equalizer, CRC and seeds. The current 4-by-4 SLS network template cannot use
the SISO pilot as its production calibration.

The first 2026-10-02 pilot (`nr_dl_ul_20261002_v2`) retained 54 episodes / 76
physical attempts. None of its 72 conditional cells meets the population
gate; five fitting attempts are outside the initial reference domain for
every permitted beta. **Do not loop that pilot grid into a production
calibration.** Reference-domain coverage and conditional HARQ population
design need revision, with fresh independent validation populations.
The dedicated regression also exposed inherited SSB exclusions in the
standalone DL builder; the builder now disables that untransmitted broadcast
signal for data-only calibration. Its unchanged baseline regression passes
after this fix. The UL builder also forwards its configured MCS-table identity.
The post-fix pilot (`nr_dl_ul_20261002_v3`) completed 54 episodes / 75 attempts;
its population and reference-domain gaps remain, and no production calibration
was installed. Earlier pilot files remain unchanged and unqualified; different
source revisions are not pooled. Physical feedback timing, access and
throughput are not qualified by this transport-block collector.

The separated-grid pilot (`nr_dl_ul_20261002_v4`) completed **164 episodes /
250 physical attempts** on 2026-10-02. Its 29 fit-role attempts are all inside
the widened reference domain across the declared beta bounds. **0/192
conditional cells qualify statistically**; the wider grid increases the
number of reference cells. All 146 second-attempt population-plan entries
still need more independent pilot starts. These are distinct new-seed data,
not relabeled or pooled v3 observations. Four dedicated calibration checks
pass; this is not acceptance of all SLS configurations or the full regression
suite. The current SLS package loader also needs validated curve-tensor and
physical-key binding from the fitted collection before production installation.

The later v5 source revision retained **292 independent episodes / 440 physical
attempts**. Its 26 observed target-fit attempts stayed inside the widened
reference domain, but 0/336 role-specific conditional audit rows qualified.
Its former location was `results/calibration/nr_dl_ul_20261002_v5`; the operator
deleted that local results folder. Do not claim those episodes are presently
retained, qualified or resumable. The population-feasibility correction and
subsequent PHY repairs changed source identity: fresh collection requires a new
tag, as shown in the current command section, not appending to an old identity.

## YAML-selected LLS and SLS

`run_sixgr(configPath, outputDir, runTag)` is the shared entry point. Existing
`run_6g_phy_lls_single` commands remain supported. Execution scope and PHY
backend are separate: SLS can use waveform replay or explicitly calibrated
link abstraction; selecting SLS does not make modeled metrics waveform truth.

| Control | LLS | SLS |
|---|---|---|
| YAML mode | `run_control.execution_mode: LLS` (legacy default) | `run_control.execution_mode: SLS` |
| Configuration | Existing ScenarioConfig YAML/inheritance | `sls.config` native configuration, plus explicit `sls.config_files` |
| Engine | Existing config-driven LLS runner | `sixgr.system.SystemLevelRunner` |
| Backend | Existing scenario-selected PHY execution | Explicit `system.phyBackend`: `waveform` or `calibrated_link_abstraction` |
| WebGUI | Existing PHY live panels and artifacts | Network progress, KPIs, UE/load/file metrics and modeled CSI/SRS/UCI tables |
| Results root | `results/lls/<scenario>/<tag>` | `results/sls/<scenario>/<tag>` |

Select a matching YAML in Configure; its fields are editable in Parameters.
LLS/SLS is also selectable in Configure. Changing the selector alone does not
convert an LLS configuration to SLS. Live and Results have an **All modes / LLS /
SLS** filter. SLS discovery uses its own durable run receipt and does not invoke
the LLS terminal materializer or manufacture missing waveform plots.

Generic SLS template: `simulator/configs/scenarios/sls_network_calibrated.yaml`.
This is **not a ready/qualified study**: its calibration path and SHA256 are
deliberately empty. Bind accepted waveform-derived calibration matching the
configured link keys before execution. Test-only calibration is rejected by
the public front door. Native fragments resolve in declared order, followed by
`sls.config`; scenario-name-derived presets and implicit local fragments are
not loaded. Default native parameters come from
`simulator/configs/schema/core_parameter_catalog.yaml` and may be overridden
under `sls.config`.

Windows **Command Prompt** (only after binding/validating a production SLS
calibration matching every configured key; the YAML as shipped fails closed):

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\sls_network_v1.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_sixgr('simulator/configs/scenarios/sls_network_calibrated.yaml','results','sls_network_v1'); disp(out); assert(out.Ok);"
```

Use a fresh tag for every SLS run; an existing folder is never overwritten.
To use the shared front door for an existing LLS scenario:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\lls_5mhz_v1.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_sixgr('simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml','results','lls_5mhz_v1'); disp(out); assert(out.Ok);"
```

Start/restart the WebGUI separately to load updated Python code:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "apps\start_lls_web_dashboard.ps1"
```

SLS output flags are `sls.config.outputs.saveCSV`, `saveMAT`, `saveFigures`,
`saveFIG`, `detailedSystemTrace` and `exportSLSOutputCatalog`. Retained outputs
include `meta/simulation_run.json`, input/config snapshots, `logs/run.log`,
`summaries`, `tables`, `traces`, `maps`, `plots` and the original `csv`/`image`
artifacts. These cover network KPIs, scheduler grants/TBS, HARQ, resource
reservations/opportunities, interference, mobility, loads and FTP3 delivery
when those producers execute. No universal set of CSV/PNG filenames constitutes
3GPP qualification. Missing measurements are not synthesized to populate plots.

**Remaining scientific acceptance work:** conditional BLER/HARQ populations and
held-out validation, DL/UL calibration coverage, S0 utilization calibration,
RF-aware network/common-control interference, mobile beam/TCI and array
qualification, broader physical UCI qualification and paired 21-cell confidence
intervals. `ExecutionOk` and `PrimaryStudyAccepted` remain separate; the generic
runner does not certify those studies. No `testAll` or production campaign is
launched by the mode-dispatch tests.

Delivery branch: **`main`**, with one Git worktree. Source, scenario YAMLs,
launchers and development patches are versioned; generated results, logs and
instrument IQ remain separate local artifacts. No result or recovery stash is
removed by source consolidation.

Current status: the 27 September 2026 TDD integration is on `main`. The
5 MHz n39 and 20 MHz n39/CDL-C YAMLs, shared-control/runtime changes, result
publication changes and focused tests are versioned in one codebase.

| Item | Verified scope and remaining limit |
|---|---|
| 400 MHz / 7 GHz rank-2 Keysight package | Digital export/demo package exists. Not a 4 GHz carrier test; not a full physical-control/shared-feedback scenario. Hardware capability remains UNKNOWN. |
| Consolidated source | Receiver, PDCCH, CSI/SRS, power-authority, reporting and WebGUI edits are committed together on `main`; generated results remain outside Git. |
| TDD scenario integration | The current 5 MHz and 20 MHz scenarios resolve as TDD; the 20 MHz carrier is n39 at 1.900 GHz, 15 kHz SCS, 106 PRBs, FFT 2048 and 30.72 MSa/s. |
| Configured-SNR power authority | Fixed-SNR sweeps use normalized occupied-RE Es/N0. Absolute dBm, pathloss, O2I and thermal noise are isolated in a separate physical link-budget arm. |
| Focused validation | The 20 MHz TDD configuration suite passed 10/10 checks. The five-MHz eight-point noise-isolation check passed all points. |
| Full acceptance | The complete `testAll` run was stopped at operator request and is not claimed as passed. Eight-point end-to-end scenario acceptance, detector qualification and full-control 400 MHz acceptance remain open. |
| H4 / 4 GHz / 100 MHz TDD | A dedicated one-UE family now resolves 273 RB at 30 kHz, a 10/2/2 special slot, a two-panel 64-TXRU gNB, a four-chain UE, four active SSB beams, eight CSI-RS/data beam states, and rank capability 1/2/4 in both directions. Focused config/runtime tests pass; complete waveform qualification is not yet claimed. |

Historical recovery patches remain evidence only; do not apply them on top of
current `main`. A committed implementation is not automatically a qualified
scenario result. Use the commands below and retain the generated logs and
artifacts for the exact checked-out commit.

### AI 10.3.2: assumed 7 GHz phase noise and SLS readiness

The working study configuration is `configs/tdoc/ai_10_3_2_modulation/study.yaml`.
Its F1 waveform calibration now selects `lls.execution.rf_branch: pn7_ptrs_compensated`.
This is an **assumed research oscillator**, not a measured hardware mask or a
normative 7 GHz requirement. The explicit profile is
`simulator/configs/rf/phase_noise_nr_inspired_7ghz.yaml`: the TR 38.803 multipole-zero
shape at 29.55 GHz is frequency-scaled to 7 GHz. The 10 kHz low-offset cutoff with
flat continuation, common TX LO across chains, ideal RX LO, and FIR synthesis
resolution are disclosed assumptions. Parameters follow the
[MathWorks TR 38.803 modeling reference](https://www.mathworks.com/help/rf/ug/model-rf-impairments-in-5g-downlink-waveform.html).

| F1 RF branch | Phase noise | Transmitted PT-RS | Receiver phase tracking |
|---|---|---|---|
| `pn7_ptrs_compensated` | Enabled in transmitted samples; CPE and ICI | Enabled | Measured PT-RS CPE correction |
| `pn7_ptrs_uncompensated` | Same assumed profile and seed | Same allocation | Disabled |
| `pn_off_ptrs_reference` | Disabled | Same allocation | Disabled |
| `ideal_debug` | Disabled | Disabled | Disabled; separate overhead-free reference |

Select the branch in the YAML; keep separate calibration run tags. Never reuse
the ideal-reference thresholds for an impaired branch. The oscillator retains
state across waveform chunks, and the receiver does not receive its phase trace.
PT-RS correction does not remove all ICI and need not improve every realization.
UL 1024-QAM remains explicitly labelled as a research transport extension.

Dedicated checks from a Windows Command Prompt already at the repository root:

```bat
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_phase_noise_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testNRInspiredPhaseNoise; testRAN1AI1032PhaseNoisePTRS(25,[1 2 4]); testRAN1AI1032PhaseNoisePTRS(273,1);"
```

Retained component/paired-waveform evidence is under
`logs/nr_inspired_phase_noise_20261001/`. These checks are not statistical BLER
calibration or an accepted 21-cell SLS campaign. Dynamic PUCCH obligations,
production spatial/interference/feedback integration, calibrated BLER/HARQ,
measured S0 offered-load calibration, exact array qualification and paired-drop
confidence intervals remain acceptance gates. Hardware qualification is UNKNOWN.
No full `testAll` or network campaign is launched by the command above.

The selected SLS feedback assumption is **ideal delayed CSI/SRS**, not
waveform-measured feedback. The UL modeled-SRS consumer now binds delivered
observations to scheduler rank/TPMI/SRI and the frozen grant. Its CP-OFDM
codebook search uses constant total power and an explicitly configured
sum-log-rate objective; that selection objective is not a mandated 3GPP rule.
Spatial validity does not make missing/stale CQI valid. Source, availability,
control and data slots are exported in `csv/system_modeled_spatial_feedback.csv`
with `WaveformBacked=false`. The policy is in
`simulator/configs/system/calibrated_link_abstraction.yaml`; it remains disabled
by default until the campaign supplies its production channel/interference
observation provider. `NetworkSpatialGrantProvider` now supplies NR TDL/CDL
frequency-domain channels, reciprocal UL/DL link ownership, actual-grant overlap
covariance and calendar-bound ideal SRS. Select it with the internal-config
overlay `simulator/configs/system/network_spatial_ideal_tdd.yaml` after the
calibrated-abstraction fragment. This is an **ideal-RF port-domain baseline**,
not acceptance of the impaired 64-TXRU study: RF/array qualification remains
false. It rejects overlapping opposite-direction cross-links, which need
additional BS-to-BS/UE-to-UE channels. The configured equal-PSD rule, allocated
PRB/symbol footprint (including pilots), and noise-only full-band sounding rank
reference are explicit model assumptions requiring matching calibration.
Interference currently covers scheduled shared-data grants; common/control
signal interference is not yet included or qualified. Resource reservation
alone must not be presented as execution of those interferers.

`networkSpatial.channelResponseSampling` is `signal_rate` by default. The
explicit zero-Doppler-only `static_exact` alternative uses native TDL `PathGainSampleRate=auto`
or CDL `SampleDensity=64` for frequency-domain **SLS model** responses, avoiding
sample-rate path-gain tensors at large array dimensions. It retains per-RE
frequency/time responses and changes the channel calibration identity. It
does not change the waveform PHY or qualify RF, polarization, or mobility.
`testSLSNetworkChannelSampling` requires numerical equality against dense static
sampling and rejects moving channels. A moving-channel comparison failed; this
option is not an equivalent mobility path. `testSLSMultiBeamMapping(true)`
exercises all eight CSI resources at 273 PRBs with Doppler explicitly zero.
This frequency-domain provider requires the R2024b-or-later 5G Toolbox
`ChannelResponseOutput` interface; it is not currently an R2023b SLS backend.

The original UL integration test uses a labelled numerical spatial fixture
and is not a study-result command:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_spatial_feedback_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSCausalSpatialFeedback; testSystemFTP3CalibratedDelivery('UL');"
```

Physical HARQ calibration collection is separate from first-transmission F1.
`study.yaml` → `harq.calibration` configures complete SNR histories, independent
fit/validation episode counts, seed base and invocation budget. The executor
keeps the same TB and position-aware mother-code soft buffer across RVs, stops
at the first CRC pass, and records only actually executed conditional attempts.
Its explicit channel assumption is **independent attempt realizations**, with
ideal delayed control; it does not qualify correlated-channel HARQ or UCI.

From the repository root in Windows Command Prompt, this bounded command can
be repeated with the same tag to resume. It executes physical waveforms:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\sls_harq_collection.log" -batch "setup6GRSimToolkit('Verbose',false); receipt=sixgr.studies.ran1ai1032.runHARQCalibrationCampaign('configs/tdoc/ai_10_3_2_modulation/study.yaml','results/ai_10_3_2_modulation','harq_waveform_v1'); disp(receipt);"
```

Outputs are under `results/ai_10_3_2_modulation/harq_waveform_v1/harq/`:
per-case/history `fit_attempts.csv`, `validation_attempts.csv`, atomic MAT
checkpoints, input/source identity and a receipt. Interrupted CSV publication
is rebuilt from the checkpoint. Scientific/source changes require a new tag.
The default three diagonal SNR histories are **not** complete SLS calibration
coverage. Independent effective-SINR fitting, conditional population/error
gates, full RV-history coverage and SLS-key matching remain required before
packaging; collection completion never sets `PrimaryStudyAccepted=true`.

The network-provider integration check uses actual NR fading and configured
SRS, but still uses a **test-only BLER curve**, not accepted LLS calibration:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_network_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSNetworkSpatialProvider; testSystemNetworkSpatialDelivery;"
```

Its run folder contains `csv/system_modeled_spatial_feedback.csv` and
`csv/system_network_spatial_evidence.csv`. The latter records resource count,
per-RE transmit/noise power, overlapping interferers, inter-layer output power,
modeled SINR, profile identities and qualification flags. No received-waveform
measurement is fabricated, and `PrimaryResultEligible` remains false.

DL CSI integration is configured separately with
`system.linkAbstraction.dlFeedback.enabled`. It uses actual configured CSI-RS
resource coordinates, the periodic CSI reference/report calendar, ideal delayed
delivery, and the existing NR Type-I codebooks. Rank selection uses the declared
sum-log-rate study objective. CQI uses the installed mapping; enabling this path
does **not** qualify its calibration. `networkSpatial.dlAntennaBasis: direct_ports`
requires CSI, PDSCH and channel ports to agree. The optional
`configured_csirs_elements` mode uses the existing YAML-resolved
`phy.csirs.precoderMatrices`: one semi-unitary physical-TXRU-by-CSI-port matrix
per CRI. It supports the configured 64-TXRU/four-logical-port/eight-beam mapping
without substituting a scalar array gain. Enable the existing element-domain
PDSCH/hybrid mapping too. The calendar retains an explicit zero-based CSI
resource index, and the frozen data matrix is `B_CRI * W_PMI`. Candidates from
one report occasion are compared across their actual sweep source slots;
availability and maximum age still apply. RF/array qualification is separate.
New grants retain the report's rank and precoder, and retransmissions retain the
original binding. Modeled reports never become `ReceivedCSIReport` waveform evidence.

`system.linkAbstraction.dynamicPUCCH.enabled` creates receive obligations from
scheduled DL K1/PRI, configured SR calendars and causally available CSI references.
The default policy is `dedicated_pucch_no_pusch_multiplexing`, with explicitly
ideal error-free delayed control. Set `phy.pucch.uciOnPUSCHEnabled=false`; the
scheduler excludes same-UE PUSCH on these feedback occasions. Installed PUCCH
resource selection, capacity and TDD checks remain active. Unsupported overlaps
and collisions fail rather than silently discard obligations. This does not
qualify physical UCI decoding, missed DCI or MU control multiplexing.

The opt-in `causal_native_pusch_multiplexing` policy requires
`phy.pucch.uciOnPUSCHEnabled=true`. It binds one same-cell HARQ/CSI obligation
known at the control slot to a symbol-overlapping, future native NR PUSCH.
The issued grant retains its native coded-bit/RE UCI plan and exact digest;
data-only BLER calibration cannot be reused for that allocation. SR is not
added as a PUSCH payload bit or claimed as delivered. Standalone SR and
multiple unsupported obligations keep dedicated PUCCH. Late changes to an
issued obligation fail closed rather than mutate its allocation. This is a
conservative ideal-control SLS subset, not physical missed-DCI qualification.
Completion requires the selected PUSCH to execute, and CSI/HARQ consumers
require the modeled transport completion. Ideal-control completion is
independent of the modeled UL-SCH CRC outcome and is labelled explicitly.

Dedicated software checks (test-only BLER calibration, not a study campaign):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_dl_csi_pucch_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSDLCSIFeedback; testSLSDynamicPUCCH; testSystemNetworkDLCSI;"
```

Additional exports are `csv/system_modeled_dl_csi.csv` and
`csv/system_dynamic_pucch_obligations.csv`, plus
`csv/system_dynamic_uci_completions.csv`. They retain zero-based causal clocks,
field counts, context digests and model/qualification labels, not fabricated RF
trial rows. Both features remain opt-in until the selected study supplies its
matching calibration and passes its integrated acceptance checks.

`sixgr.phy.ul.pusch.planUCIResources` computes native NR single-codeword
HARQ/CSI-on-PUSCH coded-bit budgets, puncturing and exact RE coordinates.
Its output is resource-accounting evidence, **not a physical UCI trial**.
The native single-codeword data-PUSCH transmitter (without configured-grant
UCI) also checks this plan against its actual encoder budget and retains it
as `NativeUCIResourcePlan`. Other existing transport variants retain their
own handling; this is not a qualification of those branches.
The calibrated backend includes an attached `SLSUCIAllocation` in its physical
allocation key, preventing data-only BLER-curve reuse. Automatic selection is
limited to the policy described above; a transport label alone never releases
PUCCH reservations. The native waveform receiver check uses separately built
receive context/schema, not expected transmitted UCI bits. Passing a few
identity-channel cases is not statistical UCI qualification.

`sixgr.system.abstraction.buildCalibrationFromTrials(spec, policy, outputFile)`
packages retained waveform fit/held-out CSV populations into the backend MAT
schema. `spec` supplies physically keyed curve templates (including fitted
beta/MI mappings and SINR-history axes) and source-file hashes. Counts are
derived from raw rows, never filled in. Incomplete populations, reused trial
identities, changed files, development fixtures or failed statistical gates
prevent publication. This packager does not execute the missing waveform
campaign or turn an F1 first-transmission curve into HARQ calibration.

Additional dedicated checks (not `testAll` or a qualified study command):

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_mapping_uci_calibration_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSMultiBeamMapping; testSLSNativePUSCHUCIResources; testSLSNativePUSCHUCITransmission; testSLSResourceReservations; testSLSCalibrationSourceIntegrity; testSystemNetworkDLCSI;"
```

Automatic SLS transport integration and separate waveform receiver checks:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\sls_automatic_uci_checks.log" -batch "setup6GRSimToolkit('Verbose',false); testSLSNativePUSCHUCIReception; testSystemAutomaticPUSCHUCI;"
```

### H4 4 GHz / 100 MHz TDD scenario family

These files are independent of the older 100-UE/19-site system scenario and
the older `lls_3gpp_4ghz_100mhz_longrun.yaml`:

- `h4_100_a0_fixed_mcs.yaml`: normalized AWGN calibration arm.
- `h4_100_tdla30_fixed_mcs.yaml`: TDL-A, 30 ns fixed operating point.
- `h4_100_cdlc100_fixed_mcs.yaml`: CDL-C, 100 ns fixed operating point.
- `h4_100_tdla30_connected_adaptive.yaml`: connected adaptive TDL-A.
- `h4_100_cdlc100_connected_adaptive.yaml`: connected adaptive CDL-C.
- `h4_100_cold_access_beam_sweep.yaml`: measured SSB/Type-0/SIB1/PRACH path.
- `h4_100_beam_refinement_tci.yaml`: measured P1/P2 and decoded-TCI binding.
- `h4_100_cdlc100_connected_impaired.yaml`: separate frozen RF-impairment
  treatment arm; its RF values are research assumptions, not 3GPP limits.
- `h4_100_cdlc100_connected_impaired_snr_sweep.yaml`: eight independent
  impaired CDL-C points at `40, 30, 20, 10, 0, -10, -20, -30 dB`, with
  four-chain UE state rebuilt at every point and joint campaign CSV/PNG
  publication under the parent run folder.

The gNB physical shape is 4×4 spatial positions × H/V × two panels = 64
elements/TXRUs. The UE is **four-chain 4×4 MIMO capability**, implemented as
1×2 spatial positions × H/V = four elements with four independent TX and RX
chains. Eight DL CSI/PDSCH logical ports are distinct from the four scheduled
layers; the UE exposes four PUSCH/SRS ports and maximum UL rank four.

Run the focused H4 configuration and causal beam-state guards from Windows
Command Prompt:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -batch "setup6GRSimToolkit('Verbose',false); assert(testH41004x4MIMOConfig); assert(testH4BeamManagementRuntimeBinding);"
```

Run one H4 waveform scenario (replace the YAML basename with another member
of the family when required):

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\h4_100_beam_refinement_tci.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_beam_refinement_tci.yaml','results','h4_100_beam_refinement_tci'); disp(out); assert(out.Ok,'H4 run failed; inspect retained evidence.');"
```

Run the complete eight-point impaired H4 sweep. Every child retains its own
truth artifacts under `sweeps/`; consolidated all-point CSVs and PNGs are
written under the parent run's `reports/csv` and `reports/image` folders:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\h4_100_cdlc100_connected_impaired_snr_sweep.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_snr_sweep.yaml','results','h4_100_cdlc100_connected_impaired_snr_sweep'); disp(out); fprintf('RUN_FOLDER=%s\n',char(out.RunFolder)); assert(out.Ok,'H4 eight-point sweep failed; inspect retained child and parent evidence.');"
```

Start the WebGUI separately from PowerShell so it remains visible while the
MATLAB process runs:

```powershell
cd 'C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apps\start_lls_web_dashboard.ps1
```

Beam-failure recovery remains unavailable: the family does not claim BFR
until physical BFD, candidate-beam measurement, BFR PRACH and response
reception are implemented and qualified.

For the dedicated **7 GHz / 400 MHz rank-2 VXG/VSA data-channel experiment**, see
[the quick-start commands and measured results below](#400-mhz--7-ghz-rank-2-keysight-waveform-demonstration)
and [the full native-IQ runbook and hardware checklist](docs/lls/vxg_vsa_rank2_runbook.md).
This is separate from shared-feedback acceptance; digital export readiness does
not verify installed Keysight options or physical RF measurements.

This repository is a MATLAB-based 5G/6G simulator with three closely related uses:

1. link-level PHY execution and diagnostics,
2. config-driven 6G PHY LLS scenario execution, and
3. broader campaign-style truth, proxy, and end-to-end validation workflows.

At the center of the repo is the `+sixgr` package tree, which holds the reusable simulator library. Around that library are a few front-door scripts, a large YAML scenario/config system for the newer 6G LLS workflow, legacy JSON-driven configuration for broader campaign runs, a GUI, tests, and a structured results/export pipeline.

This README is intended to be the practical "start here" document for the codebase:

- what the project is,
- which entry point to use,
- how configuration is organized,
- what the major folders/files do,
- how results are laid out,
- how to run the main workflows,
- how to validate changes, and
- where to read more detailed architecture/specification documents.

## Table of Contents

For the measured four-layer 400 MHz run, use the
[exact Windows PowerShell commands](#exact-command-measured-400-mhz-four-layer-adaptive-run).
`main` is the single development branch; old merged branch tips are retained
as `archive/consolidated-20260918/*` tags, not alternative runnable branches.

For the India Mobile Congress two-screen exhibit, see the
[recorded dashboard and M9484C / N9042B / N9032B operating guide](docs/lls/imc_recorded_demo_runbook.md).
It includes exact commands for the offline DL/UL replay and checked four-channel
VSA MAT packaging. This displays measured simulator results, not live RF throughput.

1. [What This Repository Contains](#what-this-repository-contains)
2. [Recommended First-Time Setup](#recommended-first-time-setup)
3. [Which Runner Should You Use](#which-runner-should-you-use)
4. [Quick Start Commands](#quick-start-commands)
5. [Repository Structure](#repository-structure)
6. [Major Entry-Point Files](#major-entry-point-files)
7. [Configuration Systems](#configuration-systems)
8. [How the Main Run Flows Work](#how-the-main-run-flows-work)
9. [Results and Artifact Layout](#results-and-artifact-layout)
10. [Important Output/Truthfulness Semantics](#important-outputtruthfulness-semantics)
11. [Tests and Validation Workflow](#tests-and-validation-workflow)
12. [How to Add or Modify a Scenario](#how-to-add-or-modify-a-scenario)
13. [Troubleshooting](#troubleshooting)
14. [Detailed Documentation Pack](#detailed-documentation-pack)

## What This Repository Contains

The codebase mixes a few layers of functionality that are related but not identical:

### 1. Reusable simulator library under `+sixgr`

This is the real engine. It contains:

- PHY blocks for DL/UL waveform generation and reception,
- channel and RF modeling,
- scenario construction,
- reporting/export utilities,
- truth-validation helpers,
- system-level and hybrid flows,
- L2/L3 packet-flow components, and
- utility/config infrastructure.

If you are changing simulation behavior, you are usually editing something inside `+sixgr`.

### 2. Config-driven 6G PHY LLS framework

This is the newer YAML-based scenario system under `simulator/configs/`. It is designed so that LLS scenario behavior is driven by resolved configuration rather than hard-coded runner defaults.

Its main front doors are:

- `run_6g_phy_lls_single.m`
- `run_6g_phy_lls_matrix.m`

This is the best starting point if your goal is "run a defined LLS scenario" or "run a regression matrix of LLS scenarios".

### 3. Broader truth/proxy/campaign orchestration

This is the more general orchestration path built around:

- `sixgr_run_3gpp_full_campaign.m`
- `run_truth_validation_profile.m`

These are used for larger combined runs, truth validation, E2E coupling, structured artifact verification, and broader result bundles.

### 4. Browser WebGUI / interactive usage

The live scenario-management browser workflow has one implementation and launcher:

- `apps/lls_web_dashboard.py`
- `apps/start_lls_web_dashboard.ps1`

It loads scenarios, edits and downloads configuration, launches MATLAB LLS
runs, and presents live status, tables, plots, files, and resource-grid
evidence in one interface. The MATLAB `uifigure` utility remains a separate
desktop tool; it is not another browser server.

The separate `apps/vxg_vsa_demo_dashboard.py` exhibition viewer replays a completed,
validated lab package. It does not launch live PHY runs or replace the scenario
manager. Its default address is `http://127.0.0.1:8991/webgui/`, and its exported
HTML also works offline.

## Recommended First-Time Setup

Open MATLAB with the repository root as the working folder, then run:

```matlab
setup6GRSimToolkit
```

What `setup6GRSimToolkit.m` does:

- adds the project root to the MATLAB path,
- optionally adds non-package subfolders,
- avoids adding `+pkg` and `@class` folders directly,
- optionally checks for toolbox/capability availability.

### Toolboxes and capabilities the setup script checks for

The setup script probes for these capabilities:

- 5G Toolbox
- Communications Toolbox
- Deep Learning Toolbox
- Parallel Computing Toolbox
- Phased Array System Toolbox
- Wireless Network Simulation Library support
- Site Viewer support
- RF Propagation support

Practical guidance:

- For serious NR/6G PHY execution, assume 5G Toolbox is required.
- Communications Toolbox is commonly needed for channel/noise helpers.
- Parallel and MEX acceleration are optional performance helpers.
- AI/ML scenarios can depend on Deep Learning Toolbox or descriptor-driven AI assets.
- Some SLS or map/site workflows can rely on phased/RF/site-viewer functionality.

### Recommended MATLAB version

The GUI header in `apps/SimSuiteGUI.m` targets `R2025b+`. Even outside the GUI, this repository is clearly written for a recent MATLAB release. If you run into odd syntax/class issues on older versions, upgrade first before assuming the simulator is broken.

## Which Runner Should You Use

Use this table as the quick decision guide.

| Goal | Recommended entry point | Notes |
| --- | --- | --- |
| Run one config-driven 6G PHY LLS scenario | `run_6g_phy_lls_single` | Best front door for a single YAML scenario |
| Run a matrix/regression of LLS scenarios | `run_6g_phy_lls_matrix` | Best front door for suite-style YAML execution |
| Run the stricter truth-validation profile | `run_truth_validation_profile` | Truth E2E plus supplemental waveform/control artifacts |
| Run the broader campaign orchestrator | `sixgr_run_3gpp_full_campaign` | More general and more configurable; used by compatibility flows too |
| Launch the live scenario-manager WebGUI | `apps/start_lls_web_dashboard.ps1` | Defaults to `http://127.0.0.1:62906/` |
| Generate the rank-2 Keysight waveform package | `scripts/run_vxg_vsa_demo.ps1` | Actual PHY execution, instrument exports, browser checks and artifact hashes |
| View a completed rank-2 exhibition package | `apps/vxg_vsa_demo_dashboard.py` | Recorded digital evidence, not live RF; defaults to port 8991 |
| Launch the MATLAB desktop utility | `Start6GRSimToolkit` or `SimSuiteGUI` | MATLAB-only interactive usage; not a browser server |
| Use older compatibility path | `SixGR_Simulator` | Deprecated wrapper; forwards to the full campaign |

## Quick Start Commands

### Current TDD command catalog: 5 MHz, 20 MHz, 400 MHz and testAll

The commands in this section are for **Windows Command Prompt (`cmd.exe`)**.
Do not paste PowerShell `&`, backticks, arrays or line continuations directly
into Command Prompt. Commands were checked against the runner signature and
the YAML paths on `main`. Change each run tag or log filename before repeating
a run so an earlier result is not confused with a new experiment.

First enter the repository and optionally launch the live WebGUI in a second
Command Prompt window:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\apps\start_lls_web_dashboard.ps1" -Port 62906
```

Open `http://127.0.0.1:62906/`. The WebGUI is a separate process; starting a
batch run does not automatically start it. All direct commands below save
scenario artifacts below `results/lls/<scenario_id>/<run_tag>/` and the MATLAB
console log below `logs/`.

#### 5 MHz TDD commands

| Purpose | YAML |
|---|---|
| n39/1.900 GHz, 5 MHz, 4TX/2RX adaptive-rank, 0 dB focused point | `simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml` |
| 5 MHz shared physical control/feedback, saturated traffic, 20 dB | `simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml` |
| n39/1.900 GHz, saturated eight-point sweep `[40,30,20,10,0,-10,-20,-30]` dB | `simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml` |
| Historical 12 dB four-port diagnostic | `simulator/configs/scenarios/lls_tdd_5mhz_four_port_shared_awgn_12db.yaml` |

Additional 5 MHz YAMLs are retained for comparison or focused diagnostics:
`lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml`,
`lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml`,
`lls_tdd_5mhz_rank2_shared_awgn_20db.yaml`,
`lls_tdd_5mhz_rank2_shared_awgn_snr_sweep.yaml`,
`lls_tdd_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml` and
`lls_tdd_5mhz_outage_publication_fixture.yaml`. The last file is a publication
fixture, not an operator acceptance scenario.

Run the 0 dB focused point:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\5mhz_n39_0db_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_4tx2rx_awgn_0db.yaml','results','5mhz_n39_0db_manual_01'); disp(out); assert(out.Ok,'5 MHz 0 dB run failed; preserve results and log.');"
```

Run the saturated 20 dB point:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\5mhz_rank2_20db_saturated_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db_saturated.yaml','results','5mhz_rank2_20db_saturated_manual_01'); disp(out); assert(out.Ok,'5 MHz 20 dB run failed; preserve results and log.');"
```

Run the complete eight-point 5 MHz sweep:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\5mhz_n39_8point_sweep_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_tdd_2ghz_5mhz_rank2_shared_awgn_snr_sweep_saturated.yaml','results','5mhz_n39_8point_sweep_manual_01'); disp(out); assert(out.Ok,'5 MHz eight-point sweep failed; preserve parent and child artifacts.');"
```

The sweep retains per-point raw child evidence and publishes joint parent-level
CSV/PNG comparisons. It must not copy configured SNR into measured-SINR fields.

#### 20 MHz n39 TDD CDL-C commands

These are TDD scenarios. The reference carrier is NR band n39 at 1.900 GHz,
20 MHz bandwidth, 15 kHz SCS, 106 PRBs, normal CP, FFT 2048 and 30.72 MSa/s.
The configured-SNR studies and the physical O2I/thermal link-budget study are
separate by design.

| Purpose | YAML |
|---|---|
| Clean CDL-C configured-SNR reference at 0 dB | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_reference.yaml` |
| Clean CDL-C eight-point configured-SNR sweep | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_snr_sweep.yaml` |
| CDL-C with declared RF impairments, single reference point | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_impairments.yaml` |
| CDL-C/RF-impairment eight-point sweep | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_snr_sweep.yaml` |
| Absolute-power CDL-C/O2I/pathloss/thermal-noise link budget; not an SNR sweep | `simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml` |

Run the clean 0 dB reference:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_0db_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_reference.yaml','results','20mhz_n39_cdlc_0db_manual_01'); disp(out); assert(out.Ok,'20 MHz reference run failed; preserve results and log.');"
```

Run the clean eight-point sweep:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_8point_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_snr_sweep.yaml','results','20mhz_n39_cdlc_8point_manual_01'); disp(out); assert(out.Ok,'20 MHz CDL-C sweep failed; preserve parent and child artifacts.');"
```

Run the RF-impairment point or its eight-point sweep:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_rf_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_impairments.yaml','results','20mhz_n39_cdlc_rf_manual_01'); disp(out); assert(out.Ok,'20 MHz RF-impairment run failed.');"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_rf_8point_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_rf_snr_sweep.yaml','results','20mhz_n39_cdlc_rf_8point_manual_01'); disp(out); assert(out.Ok,'20 MHz RF-impairment sweep failed.');"
```

Run the separate absolute-power O2I/thermal link-budget case:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\20mhz_n39_cdlc_o2i_thermal_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml','results','20mhz_n39_cdlc_o2i_thermal_manual_01'); disp(out); assert(out.Ok,'20 MHz O2I/thermal run failed.');"
```

#### 400 MHz commands

| Purpose | YAML or launcher |
|---|---|
| Rank-2 Keysight/VXG/VSA package | `lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml` through `scripts/run_vxg_vsa_demo.ps1` |
| Fixed rate-0.82 DL/UL IQ capture | `lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml` |
| Four-layer/64-element CDL-C study | `lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml` |
| Calibrated four-port adaptive DL-heavy study | `lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml` plus its calibration YAMLs |

Use the dedicated launcher for the rank-2 Keysight/VXG/VSA digital package:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml"
```

Run the fixed rate-0.82, 30 dB, DL/UL 1024-QAM IQ scenario directly:

```bat
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -wait -logfile "logs\400mhz_7ghz_rate082_iq_manual_01.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml','results','400mhz_7ghz_rate082_iq_manual_01'); disp(out); assert(out.Ok,'400 MHz rate-0.82 IQ run failed.');"
```

The adaptive DL-heavy scenario is
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml`.
It requires its version-matched calibration files; use the complete calibrated
command block in [Exact command: measured 400 MHz four-layer adaptive run](#exact-command-measured-400-mhz-four-layer-adaptive-run), not an uncalibrated direct launch.

#### testAll command

This is a reference command for a separately authorized full-suite run.
**Do not run it during the current affected-tests-only repair workflow.**

The supported server launcher requires a clean Git checkout, creates a unique
`logs/testall_*` folder, writes terminal JSON/CSV/MATLAB logs and creates a ZIP
bundle. From Command Prompt:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_server_testall.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -PreflightOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\run_server_testall.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe"
```

The first line is environment preflight only. The second line runs `testAll`.
Do not call the second line a pass unless its `summary.json` says `passed`, the
launcher exits with code zero, and the source commit/worktree identity remains
unchanged throughout execution.

### 400 MHz / 7 GHz rank-2 Keysight waveform demonstration

**7 GHz / 400 MHz 6G research waveform using 3GPP-derived NR PHY structures.**
This is **400 MHz bandwidth at 7 GHz**, not a 4 GHz carrier. The dedicated YAML is
[`lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml`](simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml).
It preserves the existing 5 MHz and four-layer/shared-feedback scenarios.

Use `scripts/run_vxg_vsa_demo.ps1` below for a **new complete digital package**;
use `apps/vxg_vsa_demo_dashboard.py` below to **view the existing package only**.
Neither command verifies physical instrument capability. Updating `main` does
not rerun this experiment or replace the sealed measurements from `20260925_v1`.

Delivery status: one branch (`main`) and one Git worktree. Source, launchers,
YAMLs, tests and preserved development patches are versioned; generated IQ,
results and logs are transferred separately. Pending 5 MHz receiver patches
do not change or qualify this sealed 400 MHz data-channel demonstration.

The sealed measurements came from source commit
`6244d24f20b2ee55d426cfab9aa81d7c203d10d7` with additional working-tree edits;
the package retains the exact executed source snapshots. A new run on current
`main` is a new experiment, not a reproduction established by `git pull` alone.
Keep its new run folder and source identity alongside the original report.

The run uses 120 kHz SCS, FFT 4096, native 491.52 MSa/s, normal CP, 264 PRBs,
2x2 logical identity MIMO and two layers. Each port has 4,915,200 samples over
10 ms. The TDD period is 5 DL slots / one 10D+2G+2U mixed slot / 2 UL slots;
data occupy full DL/UL slots only. DL uses MCS26/25/24 from the 1024-QAM table;
UL uses experimental 1024-QAM at rate 948/1024, without an invented NR UL MCS.
Real TBS/LDPC/CRC and received-DMRS estimation/MMSE are executed. Access,
physical control/feedback, HARQ and link adaptation are disabled in this
dedicated clean-waveform experiment, not silently bypassed in shared scenarios.

Requirements: MATLAB R2024a+ with the needed 5G Toolbox features (executed here
with R2026a), Python numpy/scipy/pandas/matplotlib/Playwright and its Chromium
browser. The launcher checks Python/browser availability before MATLAB.

From **Windows Command Prompt**, this one line executes MATLAB, exports and
reads back the files, checks the browser, and seals the artifact inventory.
The run tag is generated automatically; existing runs are not overwritten:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml"
```

On another PC, substitute that PC's checkout path. From its repository root,
the portable command is:

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "scripts\run_vxg_vsa_demo.ps1" -MatlabExe "C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -Config "simulator/configs/scenarios/lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml"
```

For a **new checkout** on the other PC, first run these two commands from a
directory where you want to keep the repository, then use the portable
launcher above. Change `-MatlabExe` to the supported MATLAB installation on
that PC; these commands do not install MATLAB, Python or their dependencies.

```bat
git clone --branch main --single-branch https://github.com/anup080002/6gr-simulator.git
cd /d "6gr-simulator"
```

Outputs are saved to `results/vxg_vsa/7ghz_400mhz_rank2_1024qam/<run_tag>/`;
launcher, packaging and browser logs are in `logs/`. The package is about
12.1 GB because full native/noisy IQ and multiple validated formats are retained.
The launcher does not run `testAll` or enable RF.

For this test, use the rank-2 `vxg_vsa` YAML above, not the older four-layer
adaptive or shared-feedback YAMLs later in this README. From an existing clean
checkout, update the single delivery branch before executing the launcher:

```bat
git switch main && git pull --ff-only origin main
```

The launcher prints `RUN_FOLDER` for the exact new execution. Within that folder:

| What to inspect or share | Location |
|---|---|
| Engineering summary and all-case measurements | `reports/engineering_report.md`, `reports/csv/` |
| Spectrum, PSD, PAPR, EVM and constellation plots | `reports/image/` |
| Recorded WebGUI, without starting another simulation | `webgui/index.html` |
| VSG/VSA file mapping and hardware checklist | `keysight/instrument_handoff.json`, `keysight/hardware_checklist_and_runbook.md` |
| Readback validation and immutable file inventory | `validation/export_receipts.json`, `manifest.json` |

These generated files are not downloaded by `git pull`: either run the launcher
or transfer the existing complete package separately. Do not overwrite the
sealed `20260925_v1` package with results from a newer source revision.

The completed local run `20260925_v1` contains 630 receiver trials across
MCS26/25/24 and 30/35/40 dB. Primary MCS26 results are:

| Simulated SNR | DL CRC passes | UL CRC passes | DL full-frame goodput | UL full-frame goodput | DL / UL RMS EVM |
|---|---:|---:|---:|---:|---:|
| 30 dB | 0/50 | 0/20 | 0 | 0 | 3.7814% / 3.7796% |
| 35 dB | 50/50 | 20/20 | 3.524520 Gbit/s | 1.409808 Gbit/s | 2.1278% / 2.1285% |
| 40 dB | 50/50 | 20/20 | 3.524520 Gbit/s | 1.409808 Gbit/s | 1.1964% / 1.1970% |

All profiles passed their tested payloads at 35/40 dB. At 30 dB, MCS24 DL passed
10/50 TBs; MCS25 DL and the fixed-rate UL failed all tested TBs. These finite
samples are **not statistical BLER qualification**. Export/demo readiness is
not an all-SNR payload pass, shared-feedback acceptance or RF measurement.
The [versioned validation record](docs/lls/vxg_vsa_validation_20260925.md) preserves
the test scope and sealed package identity; all cases remain in the CSVs/GUI.

Open the completed local package without rerunning MATLAB:

```bat
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main" && python apps\vxg_vsa_demo_dashboard.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\20260925_v1"
```

Open `http://127.0.0.1:8991/webgui/`, or open `<run_folder>/webgui/index.html`
offline. Use F for fullscreen and Space for recorded replay. For another run,
replace `20260925_v1` with its actual tag. After transfer, verify the complete
package without modifying its bytes:

```bat
python apps\seal_lab_waveform_package.py "results\vxg_vsa\7ghz_400mhz_rank2_1024qam\20260925_v1" --verify-only
```

For Keysight, share these primary-profile files (paths relative to the run folder):

| Destination | Files |
|---|---|
| VSG DL, two coherent outputs | `dl_tx/mcs26/dl_tx_port1.wiq`, `dl_tx/mcs26/dl_tx_port2.wiq` |
| VSG UL, separate playback experiment | `ul_tx/mcs26/ul_tx_port1.wiq`, `ul_tx/mcs26/ul_tx_port2.wiq` |
| 89600 VSA, DL two-channel recording | `vsa/mcs26/dl_tx_2ch_vsa.mat` |
| 89600 VSA, UL two-channel recording | `vsa/mcs26/ul_tx_2ch_vsa.mat` |

Also share `keysight/instrument_handoff.json`,
`keysight/hardware_checklist_and_runbook.md`, `vsa/vsa_demod_config.json` and
`validation/export_receipts.json`. WIQ is signed int16 **little-endian**,
interleaved I/Q, with a common scale across both ports. Set native Fs to
491.52 MSa/s and RF center to 7 GHz; preserve simultaneous start and port order.
Do not use simulated noisy RX files for clean VSG transmission. The demodulation
JSON is an engineering description, not a proprietary Keysight setup file.

**PHYSICAL INSTRUMENT CAPABILITY VERIFIED: UNKNOWN.** Actual `*IDN?`/`*OPT?`,
installed options, coherent TX/RX channels and import success remain unverified.
The sealed results and logs stay local under existing Git ignore rules; cloning
GitHub downloads the implementation, not this multi-GB recorded package.

### Current TDD runs: 5 MHz / 12 dB and 400 MHz / 30 dB

Use **`main`** as the consolidated delivery branch. From Windows PowerShell,
clone once (Git LFS is needed for tracked MATLAB evidence):

```powershell
git clone --branch main https://github.com/anup080002/6gr-simulator.git
Set-Location .\6gr-simulator
git lfs install
git lfs pull
```

For an existing clean clone, use `git switch main` and `git pull --ff-only
origin main`. Preserve local edits first; do not reset or clean them away.

These are **different YAML scenarios**, not two bandwidth overrides of one
qualified full-stack scenario. As of 17 September 2026:

| Scenario | YAML under `simulator/configs/scenarios/` | Verified outcome |
| --- | --- | --- |
| 5 MHz TDD, configured 12 dB, continuous TX IQ | `lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml` | All 58 slots plus receive tail executed on `68140bb9`; overall acceptance **failed** despite 20/20 DL and 5/5 UL CRC-passing attempts. |
| 400 MHz TDD, 7 GHz metadata, configured 30 dB reference SNR, DL/UL 1024-QAM | `lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml` | Research capture **completed successfully** on `6be2985f`: 30/30 DL and 40/40 UL TBs correct over 10 ms; 1.868280 Gbit/s DL and 2.491040 Gbit/s UL. |

The 400 MHz run uses two layers, code rate 0.82, ideal AWGN and preconfigured
timing. Its goodput includes the complete TDD interval. It is the highest
passing rate tested for this fixed configuration, not a global throughput
maximum or standardized 6G/full-stack qualification. Control/access, HARQ,
CSI/SRS and RF impairments are disabled in that research YAML. The 30 dB value
is a configured reference SNR, not a guarantee of 30 dB measured SINR.
Full regression qualification is unfinished and has recorded failures.
The 10.5 GHz study is deferred; neither command below selects it.

Run **one scenario at a time** from the repository root. Select the installed
MATLAB executable; the recorded runs used R2026a Update 4. R2023b compatibility
is **not qualified**:

```powershell
$matlabExe = 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe'
# On the other server, use its installed path, for example:
# $matlabExe = 'C:\Program Files\MATLAB\R2023b\bin\matlab.exe'
```

**5 MHz / 12 dB diagnostic (known failed acceptance; not a passing release):**

```powershell
$runTag = 'tdd_5mhz_12db_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$runRoot/matlab.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml','$runRoot','$runTag'); assert(out.Ok,'5 MHz / 12 dB scenario acceptance failed; preserve the logs.');"
if ($LASTEXITCODE -ne 0) { throw "5 MHz run failed. Preserve $runRoot and its matlab.log." }
```

**400 MHz / 7 GHz / 1024-QAM DL+UL research run with IQ capture:**

```powershell
$runTag = 'tdd_400mhz_30db_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$runRoot/matlab.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq.yaml','$runRoot','$runTag'); assert(out.Ok && out.ResultOk,'400 MHz research scenario acceptance failed; preserve the logs.');"
if ($LASTEXITCODE -ne 0) { throw "400 MHz run failed. Preserve $runRoot and its matlab.log." }
```

Both commands retain console logs and scenario artifacts beneath their unique
`logs/<runTag>/` directory. Copy that directory when reporting failures.
In the 400 MHz scenario run folder, `waveform/dl_tx`, `ul_tx`, `dl_rx` and
`ul_rx` contain exact `raw_iq.mat`, per-port VSA MAT and WIQ files. Each stream
has 4,915,200 samples at 491.52 Msamples/s. TX is clean; RX includes AWGN, so
do not add noise again when replaying the captured receive condition.
File readback was verified; actual Keysight application import was not.
Large generated IQ/log directories stay local, not in GitHub; the source,
YAMLs and small evidence receipts are committed.

The separate **four-layer / 64 gNB-element / 4 UE-element** scenario is
`lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml`. It uses actual polarized
physical-element CDL-C propagation, fixed semi-unitary DFT beams, and
per-resource DMRS channel estimation. It is **not** the passing two-layer
identity-AWGN capture above. Its 30 dB value fixes noise relative to the
pre-channel layer power; measured SINR and decoding success are not forced.
It retains 1024-QAM/rate 0.82 and the 80-slot TDD horizon. Timing is configured,
the channel is static with independently filtered slot bursts, and there is
no adaptive CSI/beam feedback. CSV/PNG and antenna evidence go to `results/`;
raw multichannel IQ capture is disabled. Run from the repository root:

```powershell
$runTag = 'tdd_400mhz_4layer_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff')
$logRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $logRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$logRoot/matlab.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('simulator/configs/scenarios/lls_7ghz_400mhz_4layer_64gnb_4ue_30db.yaml','results','$runTag'); assert(out.Ok && out.ResultOk);"
if ($LASTEXITCODE -ne 0) { throw 'Four-layer run failed; preserve results and logs. Do not label it a pass.' }
```

The latest requested **4x4 identity-AWGN adaptive benchmark** supersedes that
physical-CDL run as the active task. Its candidate menu is 1024-QAM/rank 2,
1024-QAM/rank 4, and 256-QAM/rank 4, initially with rate 0.9 and ideal delayed HARQ.
Code-rate adaptation up to 0.9 is now approved; additional 1024-QAM/rank-4
rates 0.82 and 0.85 require their own coded calibration before selection.
The new ILLA/OLLA path requires actual coded calibration for the exact
allocation; it does not reuse the two-layer capture as calibration. See
[adaptive implementation and acceptance boundary](docs/lls/research_4x4_awgn_harq_integration_20260917.md).
The approved DL-heavy run has now completed with payload acceptance passing;
the separate >6 Gbit/s target was missed. Its exact command and measured result
are below. The earlier physical-CDL and two-layer commands are different runs.

The full-width candidate is
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_rank_qam_30db.yaml`.
It retains the existing 120 kHz / 264-PRB carrier and 3-DL/4-UL/1-mixed
pattern; it is not the proposed DL-heavy >6 Gbit/s benchmark. Calibration
executes 540 real independent initial TBs (three candidates, both directions,
three reference-SNR points, 30 trials per point). Calibration does not run
`testAll` or generate a final IQ capture. The complete command block below
generates both required calibration datasets if they are absent.

The additional rate profile executes 120 actual initial TBs (two rates, both
directions, 30 trials at 30 dB each), preserving the original calibration.
The multiple-source loader and controller integration passed focused checks.
Full-band rates 0.82 and 0.85 each had 0/30 initial CRC failures in both DL and
UL at 30 dB, meeting the configured pointwise 95%-confidence/10%-BLER gate.
The combined five-candidate configuration preflight also passed. The user has
approved the separate **5-DL/2-UL/1-mixed** scenario below for the >6 Gbit/s DL
attempt. Execution and artifacts have now been checked: see the measured
outcome below. The original 3-DL/4-UL profile is retained unchanged.

### Exact command: measured 400 MHz four-layer adaptive run

Use this YAML, not the older two-layer or 64-element CDL YAML:
`simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml`.
It reproduces the adaptive experiment that selected four layers throughout
the recorded run. Rank 2 remains allowed by the approved adaptive menu;
1024-QAM is the maximum modulation, not a forced startup modulation.
This is a throughput attempt, not a guaranteed maximum or >6 Gbit/s pass.

Open **Windows Terminal / PowerShell**. For a new server checkout, first run
these commands from the parent directory where the repository should be created:

```powershell
git clone --branch main --single-branch https://github.com/anup080002/6gr-simulator.git
if ($LASTEXITCODE -ne 0) { throw 'Clone failed; do not continue.' }
Set-Location -LiteralPath '.\6gr-simulator'
```

For an existing checkout, open its repository root and use `git switch main`
and `git pull --ff-only origin main`; stop on any error rather than discarding
local edits. Then paste this **entire self-contained block**. It prefers the
validated R2026a installation, otherwise uses the requested R2023b server
installation; the selected executable is printed. R2023b end-to-end execution
has not yet been qualified. MATLAB and 5G Toolbox must be installed/licensed.

```powershell
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath '.\setup6GRSimToolkit.m')) { throw 'Run from the repository root.' }
$matlabExe = 'C:/Program Files/MATLAB/R2026a/bin/matlab.exe'
if (-not (Test-Path -LiteralPath $matlabExe)) { $matlabExe = 'C:/Program Files/MATLAB/R2023b/bin/matlab.exe' }
if (-not (Test-Path -LiteralPath $matlabExe)) { throw 'MATLAB R2026a or R2023b was not found at its default installation path.' }
Write-Host "MATLAB executable: $matlabExe"
$scenarioYaml = 'simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_dl5_ul2_30db.yaml'
$runTag = 'adaptive_dl5_ul2_' + (Get-Date -Format 'yyyyMMdd_HHmmssfff')
$logRoot = 'logs/' + $runTag
New-Item -ItemType Directory -Path $logRoot -ErrorAction Stop | Out-Null
& $matlabExe -wait -singleCompThread -logfile "$logRoot/preflight.log" -batch "setup6GRSimToolkit('Verbose',false); assert(testResearchFixedPorts()); assert(testResearchIdealDelayedHARQ()); assert(testResearchDLHeavyConfig());"
if ($LASTEXITCODE -ne 0) { throw "Focused preflight failed. See $logRoot/preflight.log" }
if (-not (Test-Path -LiteralPath 'results/research_adaptation_calibration/full264_20260918/trials.csv')) {
    & $matlabExe -wait -singleCompThread -logfile "$logRoot/calibration.log" -batch "setup6GRSimToolkit('Verbose',false); sixgr.phy.research.calibrateAWGNAdaptation('simulator/configs/scenarios/lls_7ghz_400mhz_adaptive_rank_qam_30db.yaml');"
    if ($LASTEXITCODE -ne 0) { throw "Primary calibration failed. Preserve $logRoot/calibration.log and partial results." }
}
if (-not (Test-Path -LiteralPath 'results/research_adaptation_calibration/rates082_085_30db_20260918/trials.csv')) {
    & $matlabExe -wait -singleCompThread -logfile "$logRoot/rate_calibration.log" -batch "setup6GRSimToolkit('Verbose',false); sixgr.phy.research.calibrateAWGNAdaptation('simulator/configs/scenarios/lls_7ghz_400mhz_rate_calibration_30db.yaml');"
    if ($LASTEXITCODE -ne 0) { throw "Rate calibration failed. Preserve $logRoot/rate_calibration.log and partial results." }
}
& $matlabExe -wait -singleCompThread -logfile "$logRoot/execution.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_single('$scenarioYaml','results','$runTag'); disp(out.SummaryTable); assert(out.ResultOk,'Payload delivery failed; preserve artifacts.');"
if ($LASTEXITCODE -ne 0) { throw "Execution failed. See $logRoot/execution.log; do not delete its results." }
$resultRoot = 'results/lls/lls_7ghz_400mhz_adaptive_dl5_ul2_30db/' + $runTag
$summary = @(Import-Csv -LiteralPath "$resultRoot/reports/csv/summary.csv")
$summary | Format-Table Direction,GoodputBitsPerSecond,FirstTransmissionBLER,BLER,PendingTransportBlocks
$dl = $summary | Where-Object Direction -eq 'DL'
Write-Host ('DL >6 Gbps target met: ' + ([double]$dl.GoodputBitsPerSecond -gt 6e9))
Write-Host "Results: $resultRoot"
Write-Host "Logs: $logRoot"
```

The first invocation on a fresh checkout runs **660 calibration trials**,
then the integrated scenario. Later invocations retain existing calibration;
the MATLAB loader still checks its completeness, source/profile fingerprints
and MATLAB version. A present CSV is not assumed to be valid. On a stale,
incomplete or version-mismatched calibration, stop and preserve its evidence;
use a fresh checkout for a new-version campaign. Do not copy R2026a calibration
into the R2023b checkout. No calibration, previous run or log is overwritten.
This block runs focused checks only, **not `testAll`**.

Outputs under the printed result folder:

- `reports/csv/summary.csv`, `trials.csv`, `layer_measurements.csv`;
- `reports/image/tdd_goodput.png`;
- `harq/csv/`, `adaptation/csv/`, `air_interface/csv/timeline.csv`;
- `waveform/iq_manifest.csv` plus `dl_tx`, `dl_rx`, `ul_tx`, `ul_rx`
  subfolders containing raw MAT, per-port WIQ and VSA MAT IQ;
- `meta/manifest.json` and executed configuration/source provenance.

This uses 80 data slots plus four feedback-drain slots, with 50 full-slot DL
and 20 full-slot UL opportunities. The fixed 14-symbol data allocations do
not occupy the mixed slot. Goodput includes the complete sample-clock horizon,
including idle and drain time. `ResultOk` checks payload delivery, not the
separate >6 Gbit/s goal; inspect measured DL goodput in `reports/csv/summary.csv`.
The 7 GHz / 400 MHz / 120 kHz waveform remains an optional research experiment,
with explicitly ideal feedback, not a standardized 6G conformance result.

Measured on R2026a, source `ef799fcb`, seed 20260920: **5.926550 Gbit/s DL
and 2.396846 Gbit/s UL** over 10.5 ms. All 49 DL and 20 UL unique payloads
were delivered; one DL initial failure recovered on its second attempt.
Payload acceptance passed, but the **>6 Gbit/s DL target was not met**.
Four-port TX/RX IQ, CSV and PNG exports completed and their artifact audit
passed. See [the measured outcome and evidence](docs/lls/research_dl5_ul2_outcome_20260918.md).

The YAML chooses the calibration destination under `results/`. Existing
calibration CSVs are never overwritten: choose a new `calibration_file` in
the YAML for a new campaign. Regenerate calibration on each MATLAB version;
the current focused qualification used R2026a. MathWorks documents 1024-QAM
support since R2023a for [PDSCH configuration](https://www.mathworks.com/help/5g/ref/nrpdschconfig.html)
and [LDPC rate matching](https://www.mathworks.com/help/5g/ref/nrratematchldpc.html),
but this is not proof that the complete repository passes on R2023b. Keep the
preflight and calibration logs for that verification.

Full-suite commands below are optional operator instructions, not part of
the four-layer run; `testAll` remains stopped for the current work.
For an independent full-suite run on the other server, with logs under `logs/`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe -PreflightOnly
if ($LASTEXITCODE -ne 0) { throw 'MATLAB preflight failed; inspect logs before running the suite.' }
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_server_testall.ps1 -MatlabExe $matlabExe
if ($LASTEXITCODE -ne 0) { throw 'testAll failed; preserve its logs directory.' }
```

Details: [5 MHz terminal outcome](docs/lls/tdd_5mhz_12db_68140bb9_outcome_20260917.md),
[400 MHz IQ / Keysight handoff](docs/lls/keysight_research_iq_handoff_20260917.md),
and [source consolidation](docs/lls/main_delivery_consolidation_20260917.md).

### A. Setup once per MATLAB session

```matlab
setup6GRSimToolkit("Verbose", true);
```

### B. Run one LLS scenario

```matlab
out = run_6g_phy_lls_single( ...
    "simulator/configs/scenarios/dl_4ghz_baseline.yaml", ...
    "results", ...
    "manual_run");
```

What you get:

- a clean run folder under `results/lls/...`,
- `meta/` with resolved config and manifest,
- `reports/` with summaries, CSVs, and images,
- `air_interface/` with waveform-level exports.

### C. Run the LLS matrix/regression suite

```matlab
out = run_6g_phy_lls_matrix( ...
    "simulator/configs/scenarios/matrix_regression.yaml", ...
    "results", ...
    "matrix_run");
```

What you get:

- one matrix root under `results/lls/...`,
- per-scenario runs under `runs/`,
- combined suite/point/scenario rollups under `reports/csv/`.

### D. Run the truth-validation profile

```matlab
out = run_truth_validation_profile( ...
    "ConfigFile", "config/suite_config_truth_validation.json", ...
    "ResultsRoot", "results", ...
    "Verbose", true);
```

What this does:

- runs a base E2E truth validation campaign,
- generates supplemental waveform link/control artifacts,
- writes a truth-validation report and manifest,
- scans artifacts for proxy/fallback violations.

### E. Run the broader full campaign directly

```matlab
report = sixgr_run_3gpp_full_campaign( ...
    "config/suite_config.json", ...
    "ResultsRoot", "results", ...
    "Verbose", true);
```

Use this when you want combined campaign orchestration rather than only the LLS YAML scenario framework.

### F. Launch the single browser WebGUI

Copy the sanitized machine-local template once, then edit `apps/.env` with the
MySQL address and credentials for that system:

```powershell
Copy-Item .\apps\.env.example .\apps\.env
.\apps\start_lls_web_dashboard.ps1
```

Open <http://127.0.0.1:62906/>. The launcher creates
`apps/.webgui-venv`, installs `apps/requirements-webgui.txt`, discovers the
newest installed MATLAB release unless `SIXGR_MATLAB_EXE` is set, and starts
only `apps/lls_web_dashboard.py`. Use `SIXGR_DASHBOARD_HOST=0.0.0.0` only when
intranet access is intended; keep the real `apps/.env` untracked.

For the separate MATLAB desktop utility:

```matlab
Start6GRSimToolkit
```

## Repository Structure

This section is the "what is what" map of the repo.

### Top-level folders

| Path | Purpose |
| --- | --- |
| `+sixgr/` | Main MATLAB package tree; almost all real simulator logic lives here |
| `apps/` | MATLAB GUI and UI panels |
| `config/` | Legacy/modular JSON config fragments used by the broader campaign stack |
| `docs/` | Architecture docs, result layout docs, and the 6G LLS deliverables pack |
| `results/` | Generated run outputs |
| `simulator/configs/` | YAML-based config-driven 6G PHY LLS scenario framework |
| `tests/` | Regression and validation test suite |

### Top-level files you will actually use

| File | What it does |
| --- | --- |
| `setup6GRSimToolkit.m` | Adds paths and checks toolboxes/capabilities |
| `run_6g_phy_lls_single.m` | Front door for one YAML LLS scenario |
| `run_6g_phy_lls_matrix.m` | Front door for one YAML LLS matrix |
| `run_truth_validation_profile.m` | Truth-validation wrapper with stricter artifact checks |
| `sixgr_run_3gpp_full_campaign.m` | Unified campaign orchestrator |
| `Start6GRSimToolkit.m` | GUI launcher/helper |
| `SixGR_Simulator.m` | Deprecated compatibility wrapper over the full campaign |
| `sixgr_loadConfig.m` | Thin wrapper over `sixgr.config.loadConfig` |
| `sixgr_build_mex_accel.m` | Builds supported MEX accelerators |
| `sixgr_deep_validate_campaign.m` | Deep audit/validation helper for campaign outputs |
| `tests/testAll.m` | Master regression test entry point |

### Root-level files you can usually ignore

The repo root also contains a few scratch, probe, temp, or compatibility-oriented files such as:

- `__tmp_*.m`
- `temp_*.m`
- one-off logs or helper command files

These are not the canonical public entry points. When in doubt, start from the runner files listed above, the `+sixgr` packages, and the `simulator/configs/` tree.

### Important top-level MEX/kernel files

You will also notice several `sixgr_*_kernel.m` and `sixgr_*_kernel_mex.mexw64` files, for example:

- `sixgr_awgn_complex_kernel.*`
- `sixgr_channel_est_ls_kernel.*`
- `sixgr_corr_metric_kernel.*`
- `sixgr_freq_corr_search_kernel.*`
- `sixgr_ldpc_decode_batch_kernel.*`
- `sixgr_truth_grant_hash_kernel.*`

These are performance accelerators or performance-oriented kernels. They are not the right place to start if you are trying to understand the simulator architecture; treat them as optimized implementations supporting higher-level flows.

### The `+sixgr` package map

The `+sixgr` root is the library. Its main subpackages are:

| Package | Purpose |
| --- | --- |
| `+sixgr/+ai` | AI/ML helpers and AI-related runtime/report support |
| `+sixgr/+channel` | Channel creation and fading/channel-model plumbing |
| `+sixgr/+config` | Legacy/full-campaign JSON config loading, normalization, validation |
| `+sixgr/+core` | Core utilities such as logging, execution context, and shared run infrastructure |
| `+sixgr/+hybrid` | Hybrid/truth-vs-proxy or mixed-mode workflows |
| `+sixgr/+l2` | Layer-2 stack logic such as PDCP/RLC/SDAP |
| `+sixgr/+l3` | Layer-3 / RRC-related logic |
| `+sixgr/+link` | Link-level wrappers, KPI exporters, and experiment helpers |
| `+sixgr/+lls6g` | Config-driven 6G PHY LLS framework |
| `+sixgr/+phy` | Physical-layer blocks, TX/RX chains, coding, reference signals, modulation, synchronization |
| `+sixgr/+report` | Run folder layout, output organization, artifact verification |
| `+sixgr/+rf` | RF impairment and RF-related helpers |
| `+sixgr/+scenario` | Topology/layout generation, UE drop, scenario construction |
| `+sixgr/+system` | System-level / SLS runtime logic |
| `+sixgr/+truth` | Truth-mode waveform execution, reporting bundles, artifact scans, strict semantics |
| `+sixgr/+util` | Shared utility functions |
| `+sixgr/+visual` | Visualization helpers |

### The `+sixgr/+phy` package map

Inside the PHY tree, the first directories to know are:

| Path | Role |
| --- | --- |
| `+sixgr/+phy/+dl` | Downlink channel TX/RX helpers such as PDSCH/PDCCH/PBCH-related logic |
| `+sixgr/+phy/+ul` | Uplink channel TX/RX helpers such as PUSCH/PUCCH/PRACH/SRS |
| `+sixgr/+phy/+rx` | Shared RX-side helpers such as channel estimation/equalization-related logic |
| `+sixgr/+phy/+sync` | Synchronization/cell-search style blocks |
| `+sixgr/+phy/+refsig` | Reference signal helpers |
| `+sixgr/+phy/+mimo` | MIMO, precoding, rank/layer-related helpers |
| `+sixgr/+phy/+waveform` | Waveform construction helpers |
| `+sixgr/+phy/+phycode` | Coding/PHY-code related helpers |
| `+sixgr/+phy/+mod` | Modulation/demodulation helpers |
| `+sixgr/+phy/+tb` | Transport-block helpers |
| `+sixgr/+phy/+scramble` | Scrambling/interleaving-related helpers |
| `+sixgr/+phy/+rrc` | PHY-facing RRC helpers/data |
| `+sixgr/+phy/+grid` | Resource-grid mapping helpers |

### The `+sixgr/+lls6g` package map

This is the config-driven LLS framework introduced for scenario-defined execution.

| Path | Role |
| --- | --- |
| `+sixgr/+lls6g/+config` | YAML reader, schema validation, scenario registry, parameter catalog access, resolved-config object |
| `+sixgr/+lls6g/+runners` | Single-scenario and matrix execution |
| `+sixgr/+lls6g/+kpi` | KPI helpers used by the LLS framework |
| `+sixgr/+lls6g/+cases` | Case definitions or case helpers for LLS execution |
| `+sixgr/+lls6g/+ai` | AI-related scenario helpers within the LLS framework |

### `simulator/configs/` map

The `simulator/configs/` tree is the main home for the YAML-based LLS framework.

| Path | Purpose |
| --- | --- |
| `simulator/configs/defaults/` | Global/shared defaults |
| `simulator/configs/scenarios/` | Concrete runnable scenarios and scenario suites |
| `simulator/configs/scenario_families/` | Higher-level grouping/coverage manifests |
| `simulator/configs/schema/` | Parameter catalogs and validation schema inputs |
| `simulator/configs/bands/` | Band packs |
| `simulator/configs/channels/` | Channel packs |
| `simulator/configs/coding/` | Coding packs |
| `simulator/configs/control/` | Control-channel related packs |
| `simulator/configs/reference_signals/` | RS-related packs |
| `simulator/configs/initial_access/` | Initial-access / PRACH / access-related packs |
| `simulator/configs/harq/` | HARQ-related packs |
| `simulator/configs/mimo/` | MIMO/beam/rank/layer packs |
| `simulator/configs/impairments/` | Impairment packs |
| `simulator/configs/energy/` | Energy/profiling related packs |
| `simulator/configs/ai_ml/` | AI/ML packs |
| `simulator/configs/waveforms/` | Waveform packs |
| `simulator/configs/models/` | Supporting model-related config packs |
| `simulator/configs/releases/` | Release/profile-specific packs |

### Useful shipped scenarios to know by name

If you are browsing `simulator/configs/scenarios/` for the first time, these are especially useful anchors:

| Scenario file | Why it is useful |
| --- | --- |
| `dl_4ghz_baseline.yaml` | Simple single-scenario LLS starting point |
| `dl_700mhz_coverage.yaml` | Coverage-oriented downlink example |
| `dl_7ghz_mimo4x4.yaml` | Higher-order MIMO example |
| `ul_4ghz_cpofdm.yaml` | Basic uplink CP-OFDM example |
| `ul_4ghz_dfts_pi2bpsk.yaml` | Uplink DFT-s-OFDM / pi/2-BPSK example |
| `prach_detection.yaml` | Initial-access / PRACH-oriented scenario |
| `pdcch_blind_decode_sweep.yaml` | Control-channel sweep example |
| `lls_700mhz_20mhz_2x2_rank2_beam_truth.yaml` | Canonical truth-style LLS scenario |
| `lls_harq_retransmission_exercise.yaml` | Dedicated stressed HARQ exercise scenario |
| `matrix_regression.yaml` | Broad LLS matrix/regression suite |
| `HARQ_AND_RETRANSMISSION.yaml` | HARQ-focused grouped scenario file |
| `AI_ML_AND_ENERGY.yaml` | AI/ML and energy-focused grouped scenario file |

### The legacy `config/` tree

Do not confuse `config/` with `simulator/configs/`.

The `config/` directory is still important, but it serves the broader/older configuration path used by `sixgr.config.loadConfig` and the full campaign stack.

Main subfolders:

| Path | Purpose |
| --- | --- |
| `config/phy/` | PHY JSON fragments |
| `config/channel/` | Channel JSON fragments and tables |
| `config/traffic/` | Traffic model fragments |
| `config/energy/` | Energy model fragments |
| `config/ai/` | AI-related JSON fragments |
| `config/io/` | Output/export-related JSON fragments |
| `config/presets/` | Preset JSON configs |

### The `docs/` tree

Important docs currently present:

| File or folder | Purpose |
| --- | --- |
| `docs/result_output_layout.md` | Canonical run folder/result-tree documentation |
| `docs/6g_phy_lls_config_driven_framework.md` | Compact overview of the config-driven 6G LLS framework |
| `docs/6g_lls/` | Larger deliverables/specification pack |

### The `tests/` tree

This is a large regression suite, not just a few smoke tests. It covers:

- config normalization and validation,
- scenario schema/catalog coverage,
- PHY reference-point execution,
- LLS reporting integrity,
- availability/coverage semantics,
- HARQ exercise behavior,
- truth/proxy separation,
- E2E truth semantics,
- artifact integrity and naming,
- system/hybrid coupling behavior.

The master entry point is:

- `tests/testAll.m`

## Major Entry-Point Files

This section explains the files most people need to know first.

### `setup6GRSimToolkit.m`

Purpose:

- sets up the MATLAB path,
- optionally adds non-package subfolders,
- optionally checks toolboxes/capabilities.

Use it first in almost every session.

### `run_6g_phy_lls_single.m`

Purpose:

- minimal front door for one config-driven LLS scenario.

Behavior:

- validates required arguments,
- defaults `outputDir` to `results`,
- delegates real execution to `sixgr.lls6g.runners.runSingle`.

Use this when you want one scenario, one result bundle, and a clean front door.

### `run_6g_phy_lls_matrix.m`

Purpose:

- minimal front door for a matrix of scenarios.

Behavior:

- loads and validates a matrix config,
- creates a matrix run root,
- runs each scenario, sequentially or in parallel depending on config,
- writes scenario/point/suite summary CSVs.

Use this for regression suites and scenario sweeps.

### `run_truth_validation_profile.m`

Purpose:

- runs a stricter truth-validation wrapper flow.

Why it exists:

- it combines a base truth E2E pass with supplemental waveform link/control exports,
- verifies artifacts,
- scans for proxy/fallback contamination,
- writes a dedicated truth validation report and manifest.

Use it when your question is not just "did the simulator run?" but "did the truth-mode result bundle stay semantically honest?"

### `sixgr_run_3gpp_full_campaign.m`

Purpose:

- the broader unified campaign orchestrator.

It can coordinate:

- waveform link-level outputs,
- detailed link diagnostics,
- system-level outputs,
- mMTC probes,
- auxiliary probes,
- E2E stack probes,
- structured metadata,
- campaign plots,
- artifact verification.

If you need the most general run surface, this is the main orchestrator.

### `Start6GRSimToolkit.m`

Purpose:

- setup + GUI launch helper.

Behavior:

- runs `setup6GRSimToolkit`,
- launches `SimSuiteGUI` if available,
- otherwise prints CLI usage guidance.

### `apps/SimSuiteGUI.m`

Purpose:

- pure-code MATLAB GUI for the unified simulator.

Notable points from the file header:

- it is a `uifigure`-based GUI, not an `.mlapp`,
- it is designed to integrate with the `+sixgr` library,
- it can accept a config struct or config path.

### `SixGR_Simulator.m`

Purpose:

- deprecated compatibility wrapper.

Important:

- it is intentionally retained for backward compatibility,
- it forwards work to `sixgr_run_3gpp_full_campaign`,
- new work should generally call the full campaign directly instead.

## Configuration Systems

One of the most important things to understand in this repo is that there are two related configuration systems.

### System 1: Legacy/general JSON config path

This is used by the broader campaign stack.

Main code:

- `sixgr_loadConfig.m`
- `+sixgr/+config/loadConfig.m`
- `+sixgr/+config/normalizeConfig.m`
- `+sixgr/+config/validateConfig.m`

What it does:

1. loads defaults,
2. loads optional modular JSON fragments from `config/`,
3. optionally loads a preset,
4. merges user config over defaults/fragments/preset,
5. normalizes aliases and dependent fields,
6. validates consistency.

Use this path when you are working with:

- `sixgr_run_3gpp_full_campaign`,
- `run_truth_validation_profile`,
- the GUI in legacy/general config mode.

### System 2: Config-driven YAML LLS scenario path

This is the newer LLS scenario framework.

Main code:

- `+sixgr/+lls6g/+config/readConfigFile.m`
- `+sixgr/+lls6g/+config/loadScenarioConfig.m`
- `+sixgr/+lls6g/+config/normalizeScenarioAliases.m`
- `+sixgr/+lls6g/+config/validateScenarioConfig.m`
- `+sixgr/+lls6g/+config/ScenarioConfig.m`

What it does:

1. reads one YAML scenario file,
2. recursively resolves all `inherits` parents,
3. merges the inheritance chain,
4. normalizes aliases,
5. validates schema/compatibility,
6. computes a config hash,
7. wraps the result in an immutable `ScenarioConfig` object.

This is the config system behind:

- `run_6g_phy_lls_single`
- `run_6g_phy_lls_matrix`

### Why both systems exist

Because the repository is serving more than one execution style:

- the older/general campaign flow still uses the JSON-config stack,
- the config-driven 6G LLS framework uses the newer YAML/scenario stack.

When documenting or debugging behavior, always identify which stack you are in first.

## How the Main Run Flows Work

This section is a conceptual walkthrough of the main execution flows.

### Flow A: Single config-driven LLS scenario

High-level path:

1. `run_6g_phy_lls_single`
2. `sixgr.lls6g.runners.runSingle`
3. `sixgr.lls6g.config.loadScenarioConfig`
4. runner-specific scenario execution
5. result layout + manifests + CSV/image/report export

What `runSingle` does at a high level:

- calls `setup6GRSimToolkit`,
- loads a resolved `ScenarioConfig`,
- creates a clean run folder,
- dispatches to the appropriate runner profile,
- writes meta/report artifacts.

Inside `runSingle`, different scenario runner profiles trigger different execution branches. Examples visible from the file include:

- waveform bundle scenarios,
- PRACH detection scenarios,
- PDCCH blind decode sweeps,
- AI benchmark scenarios,
- generic sweeps.

This is why the YAML scenario field `scenario.runner_profile` matters so much.

### Flow B: Matrix config-driven LLS execution

High-level path:

1. `run_6g_phy_lls_matrix`
2. `sixgr.lls6g.runners.runMatrix`
3. matrix config validation
4. per-scenario calls to `runSingle`
5. aggregation into combined summary CSVs

What `runMatrix` adds on top of `runSingle`:

- a matrix root folder,
- scenario repetition handling,
- optional parallel scenario execution,
- combined scenario/point/suite summaries,
- matrix manifest and config snapshots.

Outputs you should expect from a matrix root:

- `meta/matrix_config_resolved.json`
- `meta/matrix_manifest.json`
- `reports/csv/matrix_scenario_summary.csv`
- `reports/csv/matrix_point_summary.csv`
- `reports/csv/matrix_suite_summary.csv`
- `runs/...` with all child scenario runs

### Flow C: Truth-validation profile

High-level path:

1. `run_truth_validation_profile`
2. setup and config load/prepare
3. `sixgr_run_3gpp_full_campaign(..., "OnlyE2E", true, ...)`
4. `sixgr.truth.runWaveformLinkBundle` for supplemental waveform artifacts
5. `sixgr.truth.exportControlPlaneTraces`
6. `sixgr.truth.scanTruthArtifacts`
7. `sixgr.report.verifyCampaignArtifacts`
8. report + manifest writeout

This profile is especially useful when you care about:

- truth-only semantics,
- no proxy/fallback contamination,
- artifact completeness,
- reproducibility evidence,
- honest reporting.

### Flow D: Full campaign

High-level path:

1. `sixgr_run_3gpp_full_campaign`
2. config load/merge/normalize/validate
3. run-folder creation and logging setup
4. optional link-level run
5. optional detailed diagnostics
6. optional system-level run
7. optional mMTC/auxiliary/E2E probes
8. export reports, manifests, checks, and summaries

It is the broadest orchestration layer in the repo.

## Results and Artifact Layout

The canonical result layout is documented in `docs/result_output_layout.md`.

### Top-level results buckets

Runs are generally organized under:

```text
results/
  lls/
  sls/
  e2e/
```

### Canonical run tree

Typical run folders are organized like this:

```text
<runFolder>/
  meta/
  reports/
    csv/
    mat/
    image/
  logs/
  air_interface/
    csv/
    mat/
    image/
    logs/
    detailed/
      csv/
      mat/
      image/
      logs/
  control/
    csv/
    image/
  harq/
    csv/
  system/
    csv/
    mat/
    image/
    logs/
  mmtc/
    csv/
    mat/
    image/
    logs/
  interference/
    csv/
  beamforming/
    csv/
  numerology/
    csv/
  rf/
    csv/
  v2x/
    csv/
  ntn/
    csv/
  packet_flow/
    csv/
    mat/
    image/
    logs/
  calibration/
```

### How to think about these folders

| Folder | Meaning |
| --- | --- |
| `meta/` | Reproducibility data: resolved config, manifests, config chains, environment/context |
| `reports/` | Human-readable and analysis-ready rollups: CSVs, MAT files, plots, markdown |
| `air_interface/` | LLS/truth waveform outputs and detailed PHY diagnostics |
| `control/` | Control-plane traces and related outputs |
| `harq/` | HARQ probe and summary CSV outputs |
| `system/` | System-level/SLS outputs |
| `packet_flow/` | E2E stack/packet-flow outputs |
| `logs/` | Run logs |

### Common files you will inspect after a run

At minimum, these are often worth opening:

- `meta/scenario_config_resolved.json`
- `meta/scenario_manifest.json`
- `reports/csv/scenario_summary.csv`
- `reports/csv/lls_output_spec_coverage.csv`
- `reports/executive_summary.md`
- `reports/technical_report.md`
- `air_interface/csv/*.csv`
- `reports/image/*.png`

For matrix runs, also inspect:

- `reports/csv/matrix_scenario_summary.csv`
- `reports/csv/matrix_point_summary.csv`
- `reports/csv/matrix_suite_summary.csv`

## Important Output/Truthfulness Semantics

This repository is opinionated about result honesty. That matters when you read the code and when you interpret outputs.

### Truth vs proxy separation

The repo distinguishes true waveform/truth execution from approximations such as:

- LUT,
- logistic,
- fast proxy,
- synthetic,
- fallback.

Important principle:

- outputs should not relabel proxy data as truth.

If you are editing exporters, manifests, summary tables, or report wording, keep this distinction explicit.

### No fake primary rows

Primary tables are not supposed to be padded with invented rows just to keep shapes stable. If real data is unavailable, the correct behavior is generally:

- leave the table empty,
- skip the artifact, or
- mark it unavailable honestly.

### Availability semantics matter

The reporting system uses semantic availability states so that:

- observed runtime evidence,
- derived metrics,
- config-only claims,
- disabled features,
- placeholders,
- unsupported items,
- not-available items,
- not-exercised items

are not all counted as the same thing.

That is a deliberate design choice. It means some metrics or plots may disappear or be marked unavailable when semantics are tightened. That is usually a correction, not a regression.

### Configured vs effective behavior

The codebase also distinguishes:

- configured/nominal parameters, and
- effective runtime-selected behavior.

That matters especially for:

- MIMO rank/layers,
- modulation,
- MCS,
- HARQ activity,
- access-delay semantics,
- compute latency vs radio/procedure delay.

When reading reports, do not assume the configured scenario description means the runtime sustained that operating point.

## Tests and Validation Workflow

The master regression entry point is:

```matlab
testAll
```

Or explicitly:

```matlab
report = testAll();
```

From `tests/testAll.m`, this is a broad suite covering:

- config/catalog/schema correctness,
- 6G LLS scenario framework coverage,
- PHY reference points and regressions,
- MIMO/precoding,
- channel-estimation and channel-profile guards,
- LLS result richness/report bundle correctness,
- availability aggregation,
- HARQ exercise semantics,
- status propagation,
- strict coverage/output completeness,
- truth/proxy guards,
- E2E truth packet semantics,
- artifact integrity,
- scheduler grant consistency,
- PDCP/RLC conservation and security profiles.

### Recommended validation commands

If you just changed code and want broad confidence:

```matlab
setup6GRSimToolkit("Verbose", false);
testAll;
```

If you are focused on config/channel/LLS reference behavior:

```matlab
setup6GRSimToolkit("Verbose", false);
testConfig;
testLLS_DL;
testLLS_UL;
testLLS_ReferencePoints;
```

If you changed truth/proxy separation, E2E semantics, manifests, or export/report integrity:

```matlab
setup6GRSimToolkit("Verbose", false);
testE2E_FastVsTruth;
testE2E_TruthPacketSemanticCampaign;
```

### Helpful targeted tests

Some especially useful focused tests to know by name:

- `testLLSReportBundle`
- `testLLSAvailabilityAggregation`
- `testLLSHARQExercise`
- `testLLSEffectiveOperatingPointSummary`
- `testLLSResultRichness`
- `testLLSScenarioStatusPropagation`
- `testStrictProxyGuards`
- `testNoProxyTruthContract`
- `testSchedulerGrantConsistency`
- `testTruthValidationProfile`

## How to Add or Modify a Scenario

### For the config-driven YAML LLS framework

This is the preferred path for new LLS scenarios.

1. Create or copy a scenario file under `simulator/configs/scenarios/`.
2. Use `inherits:` to compose it from existing packs.
3. Override only scenario-specific fields.
4. Run it through `run_6g_phy_lls_single`.
5. Inspect the resolved config and exported reports.

Very small example:

```yaml
inherits:
  - ../defaults/global.yaml
  - ../bands/band_4ghz.yaml
  - ../channels/tdl_c.yaml
  - ../waveforms/cp_ofdm.yaml

meta:
  scenario_id: my_new_scenario
  scenario_title: My New Scenario

scenario:
  runner_profile: waveform_bundle
  target_cases: ["dl_pdsch", "ul_pusch"]
```

### How inheritance resolution works

From `+sixgr/+lls6g/+config/loadScenarioConfig.m`:

1. the file is read,
2. parents in `inherits` are recursively resolved first,
3. parents are merged in order,
4. the local file is merged on top,
5. aliases are normalized,
6. validation runs,
7. a config hash is generated.

### For the legacy/full-campaign config path

If you are modifying broader campaign behavior rather than adding a YAML LLS scenario:

- work in `config/*.json` fragments or presets,
- use `sixgr.config.loadConfig`,
- run the full campaign or truth-validation profile.

## Troubleshooting

### "Function not found" or package/class not recognized

Usually means MATLAB path setup has not been done for the current session.

Run:

```matlab
setup6GRSimToolkit
```

### Scenario YAML does not resolve

Check:

- the file exists,
- `inherits` paths are correct relative to the scenario file,
- the inherited file exists under `simulator/configs/...`,
- the scenario passes schema validation.

The relevant loader/validator code is in:

- `+sixgr/+lls6g/+config/loadScenarioConfig.m`
- `+sixgr/+lls6g/+config/validateScenarioConfig.m`

### Full campaign config fails validation

Check:

- required fields exist,
- channel family/profile is concrete and not ambiguous,
- duplicated fields are not contradictory,
- waveform and transform-precoding settings are consistent.

Relevant code:

- `+sixgr/+config/normalizeConfig.m`
- `+sixgr/+config/validateConfig.m`

### Results folder looks strange or incomplete

Check:

- whether you ran a single scenario, matrix, truth-validation profile, or full campaign,
- whether artifacts were intentionally skipped by scope,
- whether the output was suppressed because a feature was disabled, not supported, not exercised, or not available,
- whether the run failed early and only partially exported.

Use:

- `meta/*.json`
- `logs/*.log`
- `reports/csv/*coverage*.csv`
- `reports/executive_summary.md`

### Performance is poor

Possible causes:

- MEX accelerators not built,
- parallelism disabled,
- truth-mode waveform execution being used intentionally,
- large matrices or large E2E truth budgets.

Things to inspect:

- `sixgr_build_mex_accel.m`
- campaign options such as `UseMexAcceleration`, `UseParallelAcceleration`, `AutoStartParallelPool`
- scenario scope and Monte Carlo settings

### GUI does not launch

Try:

```matlab
setup6GRSimToolkit
app = SimSuiteGUI();
```

If that still fails:

- check MATLAB version,
- check UI support in your installation,
- try CLI runners first to verify core simulator health.

## Shared eight-point sweep outputs

For a waveform-bundle SNR sweep, use the **parent run folder**, not a single
`sweeps/<point>` folder, for comparisons across all configured SNR points:

- `reports/csv/sweep_comparison_manifest.csv` maps each source table/plot to its
  shared output and lists missing completed points separately from unfinished points.
- `reports/csv/sweep_combined__*.csv` contains exact source rows from completed
  points, with explicit point, configured SNR, source path and completion status.
- `reports/image/sweep_combined__*.png` contains SNR-labeled original plot panels;
  unavailable or unfinished points are identified explicitly, not replaced by curves.
- `reports/csv/sweep_link_comparison.csv` and
  `reports/image/sweep_link_comparison.png` provide common-SNR-axis comparisons.
  Mean per-attempt goodput is **not** whole-run wall-clock throughput.

The WebGUI's realtime **SNR sweep progress** panel lists all points, their slot
progress, passed/failed completion, ongoing finalization and pending execution.
These are persisted states, not a guarantee that the MATLAB process is still alive.
Per-point raw evidence remains intact for diagnosis. Publication of a shared file
does not turn a failed point into a passing point or fill absent measurements with zero.

### Fixed 4.000 GHz terrestrial campaign

The RAN1#126bis research campaign front door is:

```cmd
cd /d "C:\Users\anup0\OneDrive\Documents\Simulator\6GR Simulator_v2_clean_main"
if not exist "logs" mkdir "logs"
"C:\Program Files\MATLAB\R2026a\bin\matlab.exe" -logfile "logs\ran1_126bis_4ghz_only.log" -batch "setup6GRSimToolkit('Verbose',false); out=run_6g_phy_lls_matrix('simulator/configs/campaigns/ran1_126bis_4ghz_only.yaml','results/ran1_126bis_4ghz_only','qualification_4ghz_v1'); disp(out); assert(out.Ok,'One or more 4 GHz campaign cases failed; inspect retained point evidence.');"
```

The matrix enforces the resolved physical scope before creating child runs:

- exactly 4.000 GHz for all carrier-frequency bindings;
- terrestrial single-carrier TDD only;
- no carrier aggregation or carrier-frequency sweep;
- no NTN or ISAC/sensing execution.

The current executable matrix is deliberately Stage 0: C4_20 (20 MHz,
30 kHz SCS, 51 RB, FFT 1024, 30.72 MS/s), a 4TX/2RX full-row-rank AWGN lab
operator, and targets `[-30,-20,-10,0,10,20,30,40]` dB. The campaign coverage
CSV retains later H4_100 and agenda studies as explicit blocked/partial items;
Stage-0 success must not be described as complete 25-item or 3GPP acceptance.

At matrix preflight, the runner writes `parameter_bindings.csv` and copies
`capability_coverage.csv`. The sweep parent publishes `point_status.csv`,
`metrics_long.csv`, `sinr_calibration.csv/.png`, and
`attempt_crc_failure_fraction.csv/.png`. Unsupported populations are listed in
`campaign_artifact_status.csv`; no empty or synthetic measurement rows are added.

The runner exports shared results at sweep completion. To refresh shared files as
points finish in an already-running sweep, run this separately (it does not start MATLAB):

```cmd
python scripts\export_lls_sweep.py --run-folder "<parent-run-folder>" --watch
```

## Detailed Documentation Pack

If you want more than this README, the best next documents are:

### Architecture/specification pack

- `docs/6g_lls/README.md`
- `docs/6g_lls/delivery_overview.md`
- `docs/6g_lls/architecture.md`
- `docs/6g_lls/config_schema_reference.md`
- `docs/6g_lls/block_diagrams_and_parameters.md`
- `docs/6g_lls/processing_chains.md`
- `docs/6g_lls/scenario_library.md`
- `docs/6g_lls/scenario_family_library.md`
- `docs/6g_lls/result_specification.md`
- `docs/6g_lls/validation_rules.md`
- `docs/6g_lls/sweep_framework.md`

### Supporting docs

- `docs/LLS_RUNBOOK.md` — exact YAML commands for the 12 dB TDD run, an
  eight-point configured-SNR sweep, FDD and 400 MHz examples, feature toggles,
  validation, output inspection, and timestamped `testAll` logs
- `docs/6g_phy_lls_config_driven_framework.md`
- `docs/result_output_layout.md`

## Practical "Start Here" Recommendations

If you are brand new to the repo, this is the shortest good path:

1. Run `setup6GRSimToolkit`.
2. Read this README once front to back.
3. Read `docs/6g_phy_lls_config_driven_framework.md`.
4. Open `docs/result_output_layout.md`.
5. Run one known-good scenario with `run_6g_phy_lls_single`.
6. Inspect the generated `meta/`, `reports/`, and `air_interface/` folders.
7. Read `+sixgr/+lls6g/+runners/runSingle.m`.
8. Read `+sixgr/+truth/runWaveformLinkBundle.m`.
9. Run `testAll`.

If your goal is research iteration on LLS scenarios:

1. work mostly under `simulator/configs/`,
2. use `run_6g_phy_lls_single` and `run_6g_phy_lls_matrix`,
3. inspect resolved configs and coverage/summary CSVs,
4. keep configured vs effective and truth vs proxy semantics explicit.

If your goal is broader campaign or E2E validation:

1. learn `sixgr_run_3gpp_full_campaign`,
2. learn `run_truth_validation_profile`,
3. study `+sixgr/+truth` and `+sixgr/+report`,
4. use the truth/proxy and artifact-integrity tests aggressively.
