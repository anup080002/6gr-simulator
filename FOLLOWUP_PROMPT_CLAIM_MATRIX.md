# Follow-Up Prompt Claim Matrix

This matrix records the current repo status against the 12 findings in `sixgr_codex_followup_prompts.md`.

| Item | Status | Current repo note |
|---|---|---|
| 1 | `fixed` | Channel normalization now rejects bare family names without a concrete profile and preserves `TDL-C` style inputs. |
| 2 | `fixed` | Config validation now rejects bare `TDL`/`CDL` and contradictory AWGN-vs-fading combinations. |
| 3 | `fixed` | `ChannelFactory` now validates normalized profiles instead of silently defaulting concrete TDL/CDL profiles. |
| 4 | `fixed` | Link fallback reruns are quarantined in sidecar artifacts and primary link exports are guarded by `enforcePrimaryLinkExportIntegrity`. |
| 5 | `fixed` | The DL PDSCH path now applies explicit precoding and has regression coverage for multi-port mapping. |
| 6 | `fixed` | Scalar fast channel-estimation shortcuts are blocked on fading truth paths and covered by validation tests. |
| 7 | `fixed` | Fast system grant exports now have grant-level consistency guards and no longer claim synthetic per-grant TBS as truth. |
| 8 | `partially true` | The fast E2E path is still synthetic by design, but it is now explicitly labeled as proxy and its deadline accounting is guarded. |
| 9 | `fixed` | E2E packet-integrity summaries are now derived from the packet trace, including deadline-miss accounting from latency vs PDB. |
| 10 | `fixed` | `run_full_2min_60cell_profile.m` has been removed from the active repo so the old stress/proxy profiling entry point can no longer be mistaken for a truth runner. |
| 11 | `fixed` | The removed 60-cell stress/proxy runner no longer contributes heavy profiling defaults to the supported execution surface. |
| 12 | `fixed` | `config/suite_config_linkfull.json` is no longer used as the truth-validation surface and the shipped preset set is kept to clean fading-truth configs only. |

Remaining active gap:
- the waveform-only repo no longer ships `AbstractPHY`, LUT/DB BLER backends, hybrid calibration flows, or the removed 60-cell proxy runner, but long-duration large-scale waveform SLS remains constrained by runtime/scale and still needs more validation before any full 20-site, 60-cell production claim.

Implemented phase-1 truth package:
- `run_truth_validation_profile.m` now provides the short-term strict truth runner for waveform LLS + truth E2E with module-scoped artifact verification and no system/SLS truth claims.

Phase-2 handoff:
- `docs/phase2_waveform_system_truth_plan.md` records the architecture work required before any 20-site, 60-cell waveform system truth claim can be made.
