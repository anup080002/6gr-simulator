# Two-Mode WebGUI LLS Scenarios

This repo exposes exactly two operator-facing master configurations:

- `master_sinr_sweep.yaml`: configured AWGN SNR is the input, and BLER/BER/throughput curves are the output evidence.
- `master_geometry_based.yaml`: UE placement and mobility are the inputs, and measured SINR, goodput, latency, pathloss, Doppler, and propagation evidence are the output evidence.

In the fixed-link case, the operator-facing label may say SINR sweep, but the implementation input is controlled AWGN SNR. In the single-link AWGN case, SNR and SINR are equivalent at the input, while the runtime still exports measured post-equalization SINR where available.

## Commands

Quick smoke run:

```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); run_two_mode_lls_smoke"
```

Full truth-level run:

```matlab
matlab -batch "setup6GRSimToolkit('Verbose',false); run_two_mode_lls_full"
```

There are no checked-in smoke copies. The smoke command writes bounded transient
overlays under `results/runtime_configs`, each inheriting one of the two masters.
The runner does not contain smoke values: it copies each master's
`execution_scales.smoke.overlay` verbatim. The checked-in masters currently select
`[-2, 4, 10]` dB with 20–40 trials per sweep point and 10 total/eight measured
geometry slots. Edit those blocks in the two masters to change the smoke scale.

The full command runs both catalog YAMLs as-is, with no trial-count weakening. It is intentionally expensive.

Both commands:

- run the two scenarios through `run_6g_phy_lls_single`
- run the scenario-specific audit
- run `sixgr.validation.auditRunArtifacts`
- write a summary CSV
- fail closed if any audit fails

Summary CSV locations:

- `results/two_mode_smoke_summary.csv`
- `results/two_mode_full_summary.csv`

## What To Check

For the fixed SNR/SINR sweep scenario, check these CSVs:

- `reports/csv/run_classification.csv`
- `air_interface/csv/lls_fixed_link_campaign.csv`
- `air_interface/csv/fixed_link_campaign_task_plan.csv`
- `air_interface/csv/dl_fixed_link_campaign_trials.csv`
- `air_interface/csv/ul_fixed_link_campaign_trials.csv`
- `reports/csv/fixed_snr_sweep_curve_summary.csv`
- `reports/csv/dl_fixed_snr_bler_curve.csv`
- `reports/csv/ul_fixed_snr_bler_curve.csv`
- `reports/csv/dl_fixed_snr_ber_curve.csv`
- `reports/csv/ul_fixed_snr_ber_curve.csv`
- `reports/csv/fixed_snr_sweep_audit.csv`
- `reports/csv/all_csv_artifact_audit.csv`
- `reports/csv/all_image_artifact_audit.csv`

For the fixed SNR/SINR sweep scenario, check these plots:

- `reports/image/dl_bler_vs_snr.png`
- `reports/image/ul_bler_vs_snr.png`
- `reports/image/dl_ber_vs_snr.png`
- `reports/image/ul_ber_vs_snr.png`
- `reports/image/dl_throughput_vs_snr.png`
- `reports/image/ul_throughput_vs_snr.png`
- `reports/image/measured_sinr_vs_configured_snr.png`

For the geometry placement scenario, check these CSVs:

- `reports/csv/run_classification.csv`
- `geometry/csv/topology_nodes.csv`
- `geometry/csv/ue_initial_positions.csv`
- `geometry/csv/trajectory_geometry.csv`
- `geometry/csv/serving_cell_assignment.csv`
- `mobility/csv/trajectory_segment_table.csv`
- `mobility/csv/doppler_reconciliation.csv`
- `mobility/csv/pathloss_reconciliation.csv`
- `mobility/csv/propagation_delay_reconciliation.csv`
- `mobility/csv/channel_continuity_reconciliation.csv`
- `reports/csv/measured_sinr_timeseries.csv`
- `reports/csv/geometry_runtime_audit.csv`
- `reports/csv/all_csv_artifact_audit.csv`
- `reports/csv/all_image_artifact_audit.csv`

For the geometry placement scenario, check these plots:

- `geometry/image/topology_map.png`
- `geometry/image/ue_trajectory_xy.png`
- `geometry/image/distance_vs_slot.png`
- `mobility/image/doppler_vs_slot.png`
- `mobility/image/pathloss_vs_slot.png`
- `reports/image/measured_sinr_vs_slot.png`
- `reports/image/mcs_rank_vs_slot.png`
- `reports/image/geometry_scenario_dashboard.png`

## WebGUI Launch

From the WebGUI Home page:

1. Select `master_sinr_sweep.yaml` for fixed-link curve validation.
2. Select `master_geometry_based.yaml` for placement and mobility validation.
3. Confirm the `Scenario Validation Mode` panel shows the expected run class before launch.

After the run completes:

- use the Result page mode-specific panel for a quick verdict
- use the Tables page buckets `Fixed SNR / SINR Sweep`, `Geometry / Mobility`, and `Artifact Audit`
- use the Plots page buckets with the same names to inspect the generated evidence
