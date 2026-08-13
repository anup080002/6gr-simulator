# RAN1 AI 10.5.2.2 scenario catalog

Fifteen WebGUI-visible YAMLs are under `simulator/configs/scenarios`: single-slot TD-DMRS, nested MU-MIMO, cross-slot, FD-OCC/CDM, sequence indexing, port count, wideband RF regions, bundle interleaving, region PT-RS, TB mapping, MCS segmentation, codeword/layer mapping, multi-TRP common profile, MRSS, and SLS port utilisation.

All inherit `simulator/configs/ran1_10522/study_defaults.yaml`. That file owns study enablement, evidence mode, seed, bounded execution counts, image policy and all proposed DM-RS/wideband settings. The strict canonical scenario loader validates the study sections with `scenario_parameter_catalog_extension_22.yaml` and includes them in the resolved SHA-256. `parameter_contract.yaml` records type, unit, default, allowed values, applicability and error semantics.

Family A and the exact Family K arithmetic are deterministic-ready. The bounded canonical PDSCH baseline supporting the execution plumbing is available, but it is not mislabeled as the proposed TD-OCC waveform. Families requiring candidate waveform mappings or genuine SLS remain explicit in `scenario_matrix.csv`.
