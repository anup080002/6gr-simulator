# Configured vs Effective Operating Point

Fixed-anchor scenarios must keep configured, scheduled, transmitted, and
effective operating points separate. Dominant runtime behavior must never replace
the configured target in result summaries.

For fixed anchors, strict-eligible objective rows must match the configured
rank, layers, modulation, and MCS. A collapse such as configured rank 2/layers 2
/ 256QAM / MCS20 to effective rank 1/layer 1 / QPSK / MCS1 fails:

- `ConfiguredEffectiveOk=false`
- `ScenarioObjectiveOk=false`
- `ResultOk=false`
- AUD-002 active

Adaptive-link scenarios may select lower MCS/rank only when explicitly labeled
`adaptive_link`; the mismatch remains visible in
`configured_effective_operating_point.csv`.

Audit artifacts:

- `reports/csv/configured_effective_operating_point.csv`
- `reports/json/configured_effective_operating_point_summary.json`
