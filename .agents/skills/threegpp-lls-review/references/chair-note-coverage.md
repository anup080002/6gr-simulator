# RAN1#126 Chair-note output review

Source supplied by the user:
`C:/Users/anup0/Downloads/Chair notes RAN1#126_eom1(1).docx`.
SHA256: `99e44d237970377736d06c42512361a55be5641a798438012d037538dca3ff91`.
Resolve the actual source path on another host; do not require this laptop path.

Reuse the repository's 37 content-based output families in
`docs/lls/ran1_126_100mhz_output_requirements.csv` and source record
`docs/lls/ran1_126_100mhz_output_requirements_source.json`.
Paragraph indices are zero-based `w:p` descendants of `w:body`, including table
cells and empty paragraphs. The recorded review/readiness is dated 2026-10-14:
it is a requirements inventory, NOT the current implementation/test status.
If the document hash changes, reread affected agreements and reconcile the map.
Referenced TDoc spreadsheets are not embedded; retrieve them before claiming
their exact columns or assumptions have been implemented.

## Study separation

| Study family | Scope and evidence required |
|---|---|
| Baseline LLS | Physical access, control, DL/UL data, CSI/SRS/beam/TCI, sync, RF, exact resource and received-trial evidence; short integration is not statistical acceptance. |
| Waveform/modulation/coding | Matched waveform/MCS/coding/rank allocations; actual CRC/error counts, RF/PAPR/PSD/EVM and decoder complexity. Keep candidate constellations/indication fields separate from NR. |
| CSI/codebook/RS | Explicit precoded/nonprecoded and joint DL/UL feedback comparators; channel/array/port layouts, quantization, report cost, NMSE/SGCS operands, overhead, received indices and applied grants. |
| CBG HARQ | Paragraphs 4240-4289 specify a common Category-A comparison: 4 GHz, 100 MHz, 30 kHz, TDL-A/30 ns or CDL-C/100 ns, 3 km/h, four-RX UE, reported fixed/adaptive rank, realistic estimation, OLLA/10% target and NR 2/4/6/8 CBG baseline. Optional alternatives remain distinct. Retain per-group selective retransmission and feedback/control cost. |
| Multi-user/network | Independent paired SLS drops, channel/topology/antenna assumptions, calibrated BLER/HARQ domain, load and user/cell CDFs; one-UE LLS does not produce these distributions. |
| Control/detection/CB-PUSCH | Signal-present and independent no-signal populations, frozen detector policy, exact payload/resource costs, contention/collision and actual decoded outcomes. A scheduled one-UE PUSCH is not contention-based PUSCH. |
| Beam/multi-TRP/BFR | Actual candidate transmissions, received selection, activation timing, physical failure/recovery and channel/geometry; no recovery latency without a failure episode. |
| WUS/energy | Dedicated WUS waveform/detector/traffic and wake states plus declared power model. PDCCH decode is not WUS evidence; always-awake operation cannot claim sleep savings. |
| Multi-carrier/CLI/MRSS | Actual additional carriers/interferers and resource/switching/coexistence procedures, not single-link AWGN relabelled as cross-link interference. |
| NTN | Separate orbit/topology/link budget and residual timing/frequency scenarios; inspect `configs/ntn_resilient_sync/` and `+sixgr/+ntn/+resilientsync/`. Existing files do not establish accepted execution. |
| ISAC | Separate sensing scenes and receiver estimators, detection/false-alarm populations, delay/Doppler/angle errors and ambiguity analysis; inspect `configs/isac/joint_isac_tdoc_master.yaml` and `+sixgr/+isac/`. Communications-channel reference paths are not detected objects. |

The current n40 2.35-GHz/20-MHz/15-kHz integration configuration is deliberately
different from the CBG-HARQ common assumptions above. Keep it; create a separate
qualified comparator family instead of silently relabelling it as that study.
`simulator/configs/campaigns/ran1_126bis_4ghz_only.yaml` explicitly executes
Stage 0 only; its name is not proof of complete Chair-note coverage.

## Required result discipline

For each family map configured experiment -> active producer -> required raw
fields -> aggregation -> plotted CSV -> PNG -> claim. Preserve all SNR points
in one joint CSV/plot per metric/physical comparison, with point/seed/beam/
resource/direction identity. Do not pool different MCS/rank/RF conditions into
a fixed-configuration BLER curve. Missing points must remain visible in the
coverage audit, not synthesized in the plotted data.

List separately: implemented producer, runtime wired, exercised evidence,
statistical qualification, final export acceptance. Check nonempty data and
correct operands, not just path existence. Export flags do not implement a
missing estimator. Keep normative TS, meeting agreement, FFS proposal,
toolbox default and simulator policy distinct in reports and HTML guidance.
