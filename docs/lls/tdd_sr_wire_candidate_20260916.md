# TDD configured SR wire-layout candidate

16 September 2026, 18:13 IST. Development evidence, **not** final-source full-suite,
independent combined-gNB receiver, positive MAC-SR lifecycle or 12 dB acceptance.

## Demonstrated repair

The exact 5 MHz TDD configured-12-dB scenario previously omitted the SR field
on slot 4 despite one installed, available, same-priority overlapping SR
opportunity. Its CSI-only plan contained 7 bits and its one-HARQ-plus-CSI plan
contained 8. They now contain 8 and 9 respectively, including one SR bit.

- `PUCCHConfigBuilder` now counts the union of configured SR opportunities
  overlapping the original HARQ/CSI resources before multiplexing, and includes
  the compact indicator before allocation. Existing CRC/rate and resource
  selection are reused, not replaced with larger resources or power.
- Width comes from configuration; value comes from explicit typed UE state.
  Missing, duplicate, stale or wrong-identity state rejects. Multiple positive
  requests require explicit selection; short-format unresolved arbitration
  remains guarded rather than reusing a fictitious long format.
- Coupled runtime explicitly installs initially untriggered SR procedures,
  with UE/RNTI/cell/carrier/BWP/epoch identity. All four runtime PUCCH
  reservation/preparation paths share one snapshot adapter. Planning does not
  consume an SR or count a transmission. Actual preparation retains its
  TX-time snapshot for later TX audit, not gNB receiver authority.
- Enabled MAC-SR trigger/timer integration is still incomplete and explicitly
  rejects instead of being replaced by permanent negative SR.
- The retained physical-PUCCH-TX candidate supplies an identity-bound callback
  after the first actual transmitted sample, with duplicate/early/altered
  commit rejection. It does not itself implement MAC-SR counters or timers.

## Focused execution

The second batch exited 0; engine and launcher were absent when checked at
12:43:09 UTC. All 31 captured source-file hashes matched. The underlying source
was parent `cd397f3301ebffa8edeae5ede84cc3bda93fff9d` plus this candidate's diff.
Raw byte hashes refer to that Windows worktree, not a line-ending-normalized
checkout on another server.

| Test | Seconds | What was exercised |
| --- | ---: | --- |
| `testSharedConfiguredSRCSIClock` | 309.251 | Both actual shared-PUCCH cases: 7 CSI + 1 SR; 1 HARQ + 7 CSI + 1 SR. Received SR, CSI publication and power-export CSV checks passed. CSI/TAG inputs remain component declarations, not normal gNB-schedule qualification. |
| `testSharedPUCCHFeedbackClock` | 145.100 | Existing HARQ physical feedback-clock and PUCCH-TX commit guards. |
| `testConfiguredSRCalendar` | 38.342 | Installed/blocked occasions, K=0..8, identity and missing-calendar guards. |
| `testConfiguredSRWirePlanning` | 13.820 | Exact target planner, 44 declared SR width/ordinal cases, explicit positive selection, prohibited/missing/stale/wrong-identity states, independent configured-count component check. No RF claim for this test. |
| `testPUCCHCodeRateAllocation` | 14.185 | Existing CRC/rate/resource boundaries, whole-CSI omission and TX/RX/power allocation binding. |
| `testPUCCHResourcePlanningWithoutPower` | 11.315 | Pure scheduling remains separate from actual transmit-power authority. |

Logs and source receipts are preserved in the development checkout's `logs/`:

- `sr_wire_planner_v2_20260916.log`, SHA-256
  `608F2EA5161D38048E7B63FD69A26865D030E820E7CE166F9828397EDB0A6CC2`.
- `sr_wire_planner_v2_20260916_source_binding.json`.
- First attempt `sr_wire_planner_v1_20260916.log`, exit 1, SHA-256
  `15A3D4E4C4B2D53D3D08657BA55A966BDCE19B9D90A2D1BE3230E51FB14DE1B0`.
  It exposed the missing snapshot in CSI reservation planning. No assertion
  was relaxed: that caller, HARQ reservation and interference contribution
  now use the same adapter as actual preparation.

## Still required

1. Unfiltered `testAll` and applicable NR/config/strict/scheduler/E2E guards on
   the committed candidate. The older live root suite validates `cd397f33`,
   not this diff. Keep its source and HEAD unchanged until it terminates.
2. Independent combined receive hypotheses and completion, including
   missing/all-missed DCI, DAI wrap, PUSCH overlap, absent CSI and ambiguity.
   Current normal combined PUCCH still uses the retained TX schema. The new
   test states this limitation explicitly; it is not receiver independence.
3. Positive MAC-SR trigger/prohibit/counter/physical-TX coordination; remaining
   short-format resource arbitration and multi-request selection.
4. The two older `runWaveformLinkBundle` callers (`localCollectPUCCHTrials`,
   `localBuildConnectedPUCCHInterferer`) do not supply this SR-state contract.
   The standalone collector is segregated as diagnostic in coupled mode;
   the older interferer also has default-ACK/identity assumptions requiring
   review before broader interference runs. Do not add implicit idle state
   to make either route pass. No new observed failure in the target run is
   attributed to those source-review findings.
5. SRS estimation/prediction, detector qualification, measurement/export
   repairs, historical-edit reconciliation, MATLAB R2023b verification and
   integrated 5 MHz TDD / 12 dB acceptance remain open. FDD and 400 MHz stay
   deferred; the sweep is unchanged.

The source decisions follow the configuration-authority and NR-validation
skills: reuse installed configuration, retain guards and keep test scope
separate from truth/qualification claims. No detector threshold, noise, power,
loss, source CSI value, original pass assertion or sweep point was changed.
