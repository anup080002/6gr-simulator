# 5 MHz v3 browser publication failure: diagnosed and repaired

## Retained failure

Run: `results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v3`.
Log: `logs/5mhz_full_control_acceptance_20260922_v3.log`.

At 05:52:19 UTC the browser contract reported zero missing tables and five
missing charts. All 58 PHY slots had executed. The subsequent runtime truth
check passed, but that does not override the browser publication failure.
The original MATLAB process was still writing its final MAT bundle during
this focused repair. No MATLAB production source was changed in this repair.

| Required chart | Proven cause | Production repair |
| --- | --- | --- |
| Pre-equalization constellation | Consumer did not route to the captured `pre_equalization_re_cloud` panel; post-equalization files cannot supply this plane. | Consume only finite I/Q from the exact pre-equalization panel, separating snapshots, directions and receive-antenna series. Do not label antenna-domain REs as demixed layers. |
| True H(tau) | Generic trend guard rejected the valid single unit-gain AWGN tap (0 dB, 0 degrees). | Render captured taps as bounded observations, retaining complex values and tensor hash. |
| Channel impulse response | Legacy channel table was empty despite captured executed path gains being present. | Route to the same executed impulse-response panel, not a configured PDP or receiver estimate. |
| True H(f) | Generic trend guard rejected the valid flat 0 dB / 0 degree executed response. | Render exact paired frequency observations; constant responses are allowed only under the existing explicit observed-relation policy. |
| Tap power profile | Legacy tap table was empty. | Derive instantaneous linear tap power as I^2+Q^2 from the captured complex path gains. Label it instantaneous, not an ensemble-averaged PDP. No normalization or artificial power floor. |

Implementation: `apps/lls_contract_materializer.py`. The materializer version
was bumped to invalidate old source-cache results. Generic missing-data and
zero-trend guards remain unchanged. The previously staged bounded column-name
lookup cache was also integrated; it caches no measurement values.

The completed external browser process was no longer active when its Python
source was integrated. The original failed artifacts and acceptance status
were not edited. Other staged MATLAB receiver/export/MAT-publication changes
remain separate from this chart repair.

Subsequent finalization review found that `runSingle` invokes the external
browser materializer **again after the optional MAT save**. That later call
will see the repaired Python publisher even though the PHY execution used the
earlier source snapshot. Therefore v3 is mixed-revision derived-publication
evidence, not a clean final-source qualification. The first failed browser
manifest and coverage were preserved before that refresh in
`logs/5mhz_v3_pre_terminal_browser_failure_20260922`. Any later terminal pass
must not be presented as verification of the staged MATLAB receiver repairs.

## Verification

- New regression reproduced six failures before repair (five chart paths plus
  tap-power conversion); all twelve new positive/negative cases now pass.
- Focused browser, CSV semantic, physical-axis, sweep-applicability,
  constellation and lookup tests: **198 passed**.
  Log: `logs/captured_phy_chart_fix_focused_20260922.log`.
- Actual retained-source replay: all five CSV/PNG pairs generated and PNG
  semantic gates passed. Pre-equalization: 2,048 rows (1,024 DL + 1,024 UL).
  True H(tau), CIR and tap power: one captured DL tap each. True H(f): 300
  captured DL frequency points. Channel charts explicitly retain their
  selected snapshot; they do not claim to summarize every link/time sample.
- Replay outputs:
  `results/lls/diagnostics/5mhz_v3_chart_replay_20260922_v2`.
  `receipt.json` records source-run path, source-table SHA-256, renderer
  SHA-256/version and per-artifact hashes. The replay filters only the three
  relevant panels to bound memory; it is not a complete contract/scenario run.
- Replay log: `logs/5mhz_v3_chart_replay_20260922_v2.log`.

Reproduce into a **new** folder:

```text
python tools/replay_lls_captured_charts.py "results/lls/lls_tdd_5mhz_rank2_shared_awgn_20db/5mhz_rank2_20db_full_control_20260922_v3" "results/lls/diagnostics/5mhz_v3_chart_replay_new"
```

`testAll` was not started. Complete post-fix scenario acceptance, broader
MATLAB export regressions, and the 400 MHz shared-control run are **not**
claimed by this focused repair.

## Normal terminal publisher verification

The original runner's second, strict external materialization completed on
22 September at approximately 12:06 IST. Its actual coverage CSV now records
publisher `2026-09-22-contract-v70-captured-phy-planes`, 194 tables (165
available, 29 policy-disabled, **0 missing**) and 388 charts (290 available,
98 policy-disabled, **0 missing**). Thus all five repaired charts also passed
the normal complete publication path. This is still older-PHY/newer-publisher
evidence, not a clean final-source execution or detector qualification.

## Follow-up failure review, 22 September 2026

The preceding v2 run failed at slot 31 with `MATLAB:nonExistentField`,
`Unrecognized field name "SNR"`. Shared noise bookkeeping now receives the
active configured operating point explicitly rather than reading a missing
prepared-request field. The subsequent v3 execution passed that boundary and
completed all 58 PHY slots. Its raw DL (20 rows) and UL (5 rows) tables each
record `ConfiguredSNR_dB=20` and `AppliedAWGNSNR_dB=20` throughout. The separate
eight-point physical-noise test passed with a maximum absolute sample/grid
noise error of 0.047171 dB; this does not claim full low-SNR access acceptance.

The captured-plane/export Python regression was rerun against the current
working tree during this review: **198 passed in 16.25 seconds**. Retained
PUCCH evidence also confirms slot 34 is 3 HARQ + 1 SR + 0 CSI, 4/4 bits, and
slot 39 is 4 HARQ + 1 SR + 10 CSI, 15/15 bits with CRC pass. Slot 34 has no
applicable CRC; its unavailable CRC value must not be rewritten as a pass.

Separate receiver-only PUCCH export repairs are now integrated in MATLAB:
they preserve the independently decoded width, receiver usability and
context digest without fabricating transmitted bits or a successful UE
transmission. Those changes postdate v3 PHY execution. Existing v3 rows
therefore remain historical evidence, not proof that the new MATLAB export
path ran. The main-source focused batch is retained in
`logs/5mhz_receiver_export_main_focus_20260922.log`.
It subsequently completed **9/9 passed, 0 failed**, including independent
PUCCH/PUSCH reception, export integrity, MAT round-trip and both truth/proxy
packet-accounting guards. The machine-readable ledger is
`logs/5mhz_receiver_export_main_focus_20260922.csv`.

The terminal publisher/lineage validation was still active at this review.
Zero missing chart/table counts are not a substitute for its final verdict.
No new full scenario, `testAll`, or 400 MHz execution was started during this
follow-up review; no thresholds or physical measurements were changed to
force acceptance.

## Later terminal verdict and scientific limitation

The retained v3 launcher eventually finished at 07:16:55 UTC on
22 September with `out.Ok=1` and `FIVE_MHZ_FULL_CONTROL_INTEGRATION_PASS`.
The earlier pending-terminal statements above are historical checkpoints.
This confirms publication completion, not correctness of the old SRS
prediction: an independent native-codebook/MMSE test subsequently proved
rank-two/rank-four SINR inflation of +3.0103/+6.0206 dB. That correction
postdates v3. The v4 attempt was deliberately interrupted and preserved;
neither run is evidence of full execution of the corrected predictor.
See the SRS correction section in `5mhz_400mhz_completion_plan_20260922.md`
and `logs/srs_pusch_rank_power_independent_20260922_v2.log`.
