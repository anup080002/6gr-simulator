# 100 MHz checkpoint-45 measurement repairs

All code changes are in the main checkout on `main`. No additional codebase or branch was created. Only affected tests were run; **testAll was not run**.

The interrupted run is `h4_100mhz_local_e_20261019_v3`, under `E:/SixGRResults/lls/h4_100_cdlc100_connected_impaired_40db_adaptation/`.
Its completed checkpoint45 was verified before stopping the original MATLAB process. State SHA256: `9db68e9b442efeeb4caf6ea4f161f7e0be51ae133ec41cdc1314ad73fe6429b1`. The next slot is46. The operational resume YAML is `logs/lls_repairs/h4_checkpoint45_resume_20261020_v1/resume.yaml`.

| Issue | Root cause and production repair | Verified scope / remaining acceptance |
|---|---|---|
| Missing exact DL overhead counts | `PDSCH_Tx.m` canonical adapters did not expose the resource-summary schema. `pdschPlanResourceSets.m` converts immutable zero-based resource identities to explicitly one-based carrier-plane sets, including exact PRB/symbol allocation. Both facade paths now bind it. | Coded TX/RX and report propagation pass. Independent resource checks cover200 DL and200 UL allocations with zero TBS difference. New resumed rows still require integrated inspection. No TBS or waveform mapping was changed. |
| Missing TRS EVM | `scoreTRSPilotDisturbance.m` did not retain independent complex pilot pairs. It now retains exact desired/received samples by observation and RX branch; `summarizePilotEVM.m` computes pooled error/reference energies. `runTRSTracking.m`, `runWaveformLinkBundle.m` and `exportControlEVMSamples.m` carry the samples and their reference plane to CSV. | Complex arithmetic, independent-reference guards and actual CSV writing pass. This is received-pilot diagnostic EVM, **not** equalized modulation-EVM or RF-conformance qualification. No conversion from SINR/NMSE or fitted gain/phase. |
| Missing TRS post-correction frequency | `measureTRSResidualFrequency.m` measures corrected received samples with an observable different from acquisition (CP versus pilot-phase slope). `bindTRSFrequencyEvidence.m` preserves source, role and observable evidence. | Full-band273-PRB correction-on/off and poisoned-reference tests pass; direct Toolbox IQ calculation independently matches the result. For -400Hz injection, corrected result is approximately -4.28e-14Hz; uncorrected pilot estimate is -399.792486Hz. Uncorrected OFDM ICI means it is not algebraically identical to injected CFO. The original configured accuracy requirement is unchanged. This is common received frequency, not separately identified oscillator CFO. |
| SSB legend collision | `lls_radio_measurement_plots.py` omitted observation identity in series labels. | Four observations across eight sweep points remain distinct in the joint CSV/plot. No per-point split or merged-beam substitution. |
| Misleading SRS full-carrier wording | `computeSRSCoverage.m` conflated exact coverage with configured tolerance. It now distinguishes literal `full_carrier` from `within_configured_carrier_edge_tolerance`; gap, tolerance and literal-coverage flag propagate through receiver, runtime and GUI. | Actual native mapping remains272/273PRBs. Negative tests reject false full-carrier claims and excess gaps. No added pilot REs, reduced numerical gate or extrapolated measurement. |
| Broadcast memory duplication | Pending receiver contexts retained `Prototype.PreparedBroadcast` and unused `RuntimeTx` copies of large waveforms. `compactBroadcastReceiveContext.m` checks exact equality, keeps the frozen samples and actual TX grids, and removes redundant owners at queue/legacy restore. | Ownership, real four-SSB reception/delivery and CDL/RF/pending-window/HARQ checkpoint continuity pass. Actual full-band working-set reduction must still be observed in continuation; legitimate64-port IQ/channel arrays remain large. No precision reduction or skipped channel/RF evolution. |
| Live publication | Added paired TRS received-pilot EVM and measured post-correction frequency chart families and GUI metadata. Restarted WebGUI with `SIXGR_RESULTS_ROOT=E:\SixGRResults`. |254 Python checks pass. Actual new TRS/CSI/PUSCH populations and final publication remain necessary; missing historical samples were not invented. |
| Statistical qualification | Four earlier successful DL trials are not a statistical campaign. | Remains unqualified: BLER, adaptation gain, detector reliability and full conformance need separately designed populations. |

## Evidence

Latest results across the four affected-test receipts give **14 distinct MATLAB tests passing**. Earlier failed receipts are preserved; they are not rewritten. The checkpoint guard correctly rejected a mid-test source change; its frozen-source rerun passed.

- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v1/receipt.json`
- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v2/receipt.json`
- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v3/receipt.json`
- `logs/lls_repairs/h4_checkpoint45_measurements_20261020_v4/receipt.json`
- `logs/h4_checkpoint45_python_20261020_v1.xml`:254 passing tests
- Continuation launcher: `logs/h4_100mhz_local_e_20261019_v3_resume_slot45_20261020.log`

The continuation is explicitly source-repaired diagnostic evidence, not a frozen-source primary statistical result. The checkpoint system preserves the interrupted attempt and restores artifact watermarks. Earlier measurements are not retroactively replaced with later values. Configured RF/noise, seed, channel state, waveform mapping and scheduling policies remain unchanged.

The126-PRB allocations at slots41/42 remain valid under the existing contiguous-allocation policy: SSB reservations split the available band into two126-PRB segments. Slots43/44 used273PRBs. This repair does not change that policy.

## Standards boundary

SRS bandwidth uses the TS38.211 section6.4.1.4 resource mapping, including its discrete bandwidth table; a tolerance label is not additional measured coverage. See [MathWorks SRS configuration](https://www.mathworks.com/help/5g/ref/nrsrsconfig.html).

RF-conformance EVM requires the specified waveform and measurement procedure, not merely a paired-error formula. See [MathWorks NR EVM measurement and TS38.104/38.141 distinction](https://www.mathworks.com/help/5g/ug/evm-measurement-of-5g-nr-downlink-waveforms.html). TRS diagnostics here do not claim that qualification.
