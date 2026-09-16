# Unqualified TDD UCI receiver checkpoint

Branch: `work/tdd-uci-wire-receiver-20260916`, cumulative over `5d20e64d`.

This is preservation of implementation and bounded evidence, not a qualified-main release or an accepted 12 dB run. Normal independent CSI transport ownership, combined SR, detector qualification, measurement closure, older patch reconciliation and final-source full-suite acceptance remain open. See the root-cause audit in `docs/lls/tdd_12db_root_cause_audit_20260916.md`.

The original log/receipt files here were copied byte-for-byte from the development checkout's ignored `logs` directory and checked by SHA-256. Local attributes prevent line-ending conversion of retained evidence.

- Presence v1: nine selected tests passed, including present/absent actual PUSCH waveforms. No statistical detector qualification claim.
- Consumer reproducer: retained pre-fix TDD failure.
- Consumer v1: fourteen selected tests passed, including shared TDD late CSI delivery and NR/configuration/strict guards.
- Wire-authority reproducer: retained pre-fix failure; identical decoded CSI with UE-side SINR changed from 11.25 to 80 dB altered scheduler feedback.
- Wire-authority v1: nine selected tests plus CSI-only and combined HARQ/CSI shared TDD PUCCH cases passed.
- `received_csi_report.csv`: declared reducer/actual UCI-codec fixture, not an RF measurement at 80 dB. Raw UE reference values are explicitly audit-only; received SINR/source-data CRC are unavailable. Original physical waveform artifacts remain under local `logs` and temporary fixture folders.

The source-binding receipts identify dirty source snapshots over the base revision. A subsequent small refinement preserves schema/numeric text in both production CSI feedback CSV writers and their round-trip test. That refinement is included in this checkpoint and requires its follow-up validation; the earlier receipts do not by themselves qualify it. Required final-source unfiltered `testAll`, E2E guards and integrated 12 dB acceptance are not complete.
