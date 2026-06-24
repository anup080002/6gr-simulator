# Phase 5 Operating Instructions

Status: scaffold only. Do not use this branch to claim `Phase5Ok`.

1. Review `phase5_baseline/existing_phase5_gaps.md`.
2. Run the documentation guard:

   ```matlab
   setup6GRSimToolkit('Verbose', false);
   testPhase5DocumentationSet;
   ```

3. Before modifying receiver, scheduler or link-adaptation behavior, reproduce
   UE2 slot 24 using `debug/ue2_slot24/reproduction_command.txt`.
4. Keep every Phase 5 runtime result in a new empty result directory.
5. Resolve all scenario values from
   `simulator/configs/scenarios/lls_mobile_2ue_100kmh_1sector_full_capture.yaml`.
6. Keep the run rank 1. Do not enable rank-2, multi-layer or MU-MIMO under this
   phase.
7. Keep missing primary evidence empty, skipped or failed loudly. Do not add
   synthetic rows to primary result tables.

Recommended first implementation slice:

- ASN.1 RRCSetupComplete encode/decode.
- Dedicated CellGroupConfig ownership table.
- C-RNTI DCI lineage from scheduler to UE blind decode.
- One high-SNR RRCSetupComplete PUSCH loopback test.
