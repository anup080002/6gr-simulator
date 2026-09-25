# Rank-2 Keysight digital waveform checkpoint — 25 September 2026

**7 GHz / 400 MHz 6G research waveform using 3GPP-derived NR PHY structures.**

This is the dedicated clean-IQ/data-channel experiment, not acceptance of the
5 MHz sweep or the full physical/shared-feedback 400 MHz scenario. Earlier
failures in [the main development checkpoint](main_consolidation_20260925.md)
are not closed by this run.

## Executed configuration and preserved provenance

- Scenario: `lls_7ghz_400mhz_rank2_1024qam_vxg_vsa.yaml`.
- Local run: `results/vxg_vsa/7ghz_400mhz_rank2_1024qam/20260925_v1/`.
- MATLAB: R2026a Update 4, `26.1.0.3312084`.
- Execution base: `6244d24f20b2ee55d426cfab9aa81d7c203d10d7`, **dirty at execution**.
  The new runner/configuration was not in that base commit. Actual source
  snapshots and hashes are preserved in the package; a later source commit
  does not retroactively change the execution identity.
- 120 kHz SCS, FFT 4096, native 491.52 MSa/s, normal CP, 264 PRBs,
  2x2 identity MIMO, rank/layers 2. Exactly 4,915,200 samples/port over 10 ms.
- TDD: 5 DL / one mixed 10D+2G+2U / 2 UL; no data assigned to mixed slots.
- DL MCS26/25/24 use the MATLAB TS 38.214-derived 1024-QAM table lookup.
  UL is a research 1024-QAM extension at rate 948/1024, with no NR UL MCS claim.
- Real TBS/LDPC/CRC, received-DMRS estimation/MMSE, configured slot timing.
  No physical access/control/feedback, HARQ, adaptation or RF impairments.
- Clean TX and independent 30/35/40 dB simulated receivers. UL configuration,
  transmitted data and noise seeds repeat across the three DL profiles;
  those UL results are not independent statistical repetitions.

## Actual receiver outcomes

There are 630 receiver trials, with 50 DL and 20 UL TBs per profile/SNR pair.

| DL profile | SNR dB | DL CRC pass/total | UL CRC pass/total | DL goodput Gbit/s | UL goodput Gbit/s |
|---|---:|---:|---:|---:|---:|
| MCS26 | 30 | 0/50 | 0/20 | 0 | 0 |
| MCS26 | 35 | 50/50 | 20/20 | 3.524520 | 1.409808 |
| MCS26 | 40 | 50/50 | 20/20 | 3.524520 | 1.409808 |
| MCS25 | 30 | 0/50 | 0/20 | 0 | 0 |
| MCS25 | 35 | 50/50 | 20/20 | 3.359880 | 1.409808 |
| MCS25 | 40 | 50/50 | 20/20 | 3.359880 | 1.409808 |
| MCS24 | 30 | 10/50 | 0/20 | 0.638984 | 0 |
| MCS24 | 35 | 50/50 | 20/20 | 3.194920 | 1.409808 |
| MCS24 | 40 | 50/50 | 20/20 | 3.194920 | 1.409808 |

Goodput counts successfully delivered unique information bits over the entire
10 ms frame, including opposite-direction and mixed-slot time. All failed
cases are retained. This is not statistical BLER qualification or a guarantee
of physical RF decoding at any instrument setting.

## Verification evidence

- `testLabWaveformCampaign`: actual DL/UL coded decoding, exact TBS/native
  clock, MCS lookup and fail-closed configuration guards passed. Log:
  `logs/vxg_vsa_campaign_20260925_v1.log`.
- Five MATLAB regressions passed: `test6GScenarioConfigValidation`,
  `test6GParameterCatalog`, `testResearchTDDLink`, `testE2E_FastVsTruth`,
  `testE2E_TruthPacketSemanticCampaign`. Log:
  `logs/vxg_vsa_regressions_20260925.log`.
- 18 Python package/integrity unit tests passed. Log:
  `logs/vxg_vsa_python_unit_tests_20260925_final.log`.
- Before source consolidation, all four additional guards passed:
  `testLinkExportPipeline`, `testArtifactIntegrity`,
  `testOrganizeRunResults_E2EArtifactPreservation`,
  `testSchedulerGrantConsistency`. Log:
  `logs/vxg_vsa_commit_integrity_20260925.log`. The 18 Python tests were also
  rerun successfully (`logs/vxg_vsa_commit_python_20260925.log`). These later
  logs remain outside the already sealed, unchanged waveform package.
- Browser checks passed at 1920x1080, 2560x1440 and 3840x2160, including all
  profiles/SNRs/layers, actual KPI values, fullscreen, replay and offline use.
  Log: `logs/vxg_vsa_browser_20260925_final.log`.
- 1,260 independent NumPy FFT port/slot/SNR checks passed. Maximum retained
  reference-grid error was `8.95090418262362e-16`; maximum applied-SNR
  discrepancy was `0.09592738374113452 dB`. No exported-label-only correction.
- Raw CSV/MAT round trips are exact. WIQ int16 quantization is bounded;
  common-port scaling and VSA recording readback passed. No resampling,
  padding, truncation or clipped components were admitted.
- Full `testAll` was **not run**, following the user's standing instruction.
  These focused passes do not certify the entire repository.

## Sealed deliverable

The local package contains 626 inventoried artifacts totalling 12,072,368,639
bytes, excluding the root manifest itself. This includes 54 validated
instrument files, 167 PNGs and 145 report CSVs. All 626 artifact hashes passed
the final read-only verification:

`logs/vxg_vsa_verify_20260925_final.log`

Root `manifest.json` SHA-256:

`dbfd394b1b1781461e41f64b8475531931050c2dbdc32f6d95bda3756a67d60b`

| Final status | Value |
|---|---|
| Waveform export ready | YES |
| Web demo ready | YES |
| VXG/VSA software handoff ready | YES |
| Physical instrument capability verified | UNKNOWN |
| Payload decoding across every requested SNR | FAIL: retained 30 dB cases |

Actual `*IDN?`/`*OPT?`, options, coherent two-channel TX/RX configuration,
instrument import and physical RF measurements are still required. The
software package does not prove those capabilities.

## Single-codebase preservation

Only `main` and one worktree exist. At the consolidation inventory, freshly
fetched `origin/main` matched the local base. All current source edits are
included in the new checkpoint; no source reset or history rewrite is used.
The two historical recovery stashes remain preserved. Their documented
integration commits `cd397f33` and `471334ff` were rechecked as ancestors;
reapplying the stashes would reintroduce superseded code. See the
[earlier reconciliation](main_delivery_consolidation_20260917.md).

Generated results/logs remain local under existing ignore rules. They are
not deleted for a clean Git tree, and this source push does not upload the
12 GB waveform package to GitHub. The sealed package is not rewritten when
the source is committed. Use [the runbook](vxg_vsa_rank2_runbook.md) for exact
execution, replay, transfer-verification and instrument-handoff commands.
