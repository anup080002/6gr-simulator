# 6G PHY LLS Deliverables Pack

This folder contains the required architecture and specification deliverables for the config-driven 6G PHY link-level simulator framework in this repository.

## Deliverables

1. [Delivery Overview](delivery_overview.md)
2. [Simulator Architecture](architecture.md)
3. [Configuration Schema Reference](config_schema_reference.md)
4. [Block Diagrams and Parameter Lists](block_diagrams_and_parameters.md)
5. [Exact Processing Chains](processing_chains.md)
6. [Scenario Library](scenario_library.md)
7. [Scenario Library Manifest](scenario_library_manifest.json)
8. [Scenario Family Library](scenario_family_library.md)
9. [Scenario Family Manifest](scenario_family_manifest.json)
10. [Result Specification](result_specification.md)
11. [Validation Rules](validation_rules.md)
12. [Sweep Framework](sweep_framework.md)

## Canonical Machine-Readable Sources

The human-readable documents in this folder are anchored to these machine-readable sources:

- `simulator/configs/schema/scenario_parameter_catalog.yaml`
- `simulator/configs/schema/matrix_parameter_catalog.yaml`
- `simulator/configs/schema/core_parameter_catalog.yaml`
- `simulator/configs/defaults/*.yaml`
- `simulator/configs/scenarios/*.yaml`
- `simulator/configs/scenario_families/*.yaml`
- `docs/result_output_layout.md`

## Front-Door Entry Points

- `run_6g_phy_lls_single(configPath, outputDir, runTag)`
- `run_6g_phy_lls_matrix(configPath, outputDir, runTag)`

Only the following runtime arguments are allowed at the front door:

- config file path
- output directory
- optional run tag
- optional log level

All PHY, channel, waveform, AI/ML, impairment, KPI, logging, and output behavior must be driven by resolved configuration.

## Design Contract

- All scenario behavior must be expressed through layered YAML configuration.
- Every module must consume one validated resolved `ScenarioConfig`.
- Every run must save raw config inputs, resolved config, validation context, seeds, version information, and environment summary.
- Every feature must be tagged as one of:
  - `baseline_benchmark`
  - `agreed_starting_point`
  - `study_item_candidate`
  - `optional_research_experiment`

## Relationship To Existing Framework Docs

- [docs/6g_phy_lls_config_driven_framework.md](../6g_phy_lls_config_driven_framework.md) is the compact framework overview.
- This folder is the fuller architecture/specification pack requested for laboratory use and long-horizon maintenance.
