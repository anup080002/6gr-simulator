# Channel/RF Configured-Vs-Applied Evidence

`AUD-CHANNEL-RF-001` is closed for the strict Channel/RF mini profile:
`configs/lls/lls_channel_rf_strict_mini_anchor.yaml`.

The profile is intentionally narrow. It proves that configured Channel/RF
features are not accepted from labels alone. The runner applies each enabled
feature to samples or fails the strict gate.

## Evidence Artifacts

- `channel/csv/channel_rf_config_strict.csv`: resolved Channel/RF config hash,
  concrete channel profile, RF enablement, and strict validation result.
- `channel/csv/link_geometry.csv`: site/sector/UE geometry used by the
  large-scale and interference evidence.
- `channel/csv/large_scale_parameters.csv`: TR 38.901-style pathloss,
  shadowing, O2I, waveform power before/after, and delta tolerance.
- `channel/csv/channel_realizations.csv`: AWGN, TDL, and CDL realization rows
  with waveform hashes, path-gain export status, snapshots, Doppler, delay
  spread, and `TruthStatus=real_lls_evidence`.
- `channel/csv/channel_configured_vs_applied.csv`: positive cases that must pass
  and negative configured-vs-applied faults that must fail closed.
- `rf/csv/rf_impairment_chain.csv`: RF CFO, sample-domain phase noise, IQ
  imbalance, PA compression, timing offset, quantization, before/after waveform
  hashes, and measured EVM. Sample-clock offset requests fail closed until a
  real resampling/SCO model is implemented.
- `rf/csv/thermal_noise_validation.csv`: thermal noise variance derived from
  bandwidth, temperature, and receiver noise figure, with measured variance.
- `interference/csv/interference_topology.csv`: overlapping waveform
  interference, signal/interference/noise powers, and computed SINR.
- `air_interface/csv/downstream_channel_references.csv`: strict Channel/RF
  evidence IDs made available for downstream trial-table lineage.

## Strict Gate

The runtime truth contract requires all primary Channel/RF evidence rows to be
real LLS evidence. Unsupported or mismatched cases must appear as negative rows
or fail the run. The gate also rejects oracle-style perfect channel access in
strict pass/fail evidence.

Configured phase noise is materialized through `sixgr.rf.PhaseNoiseModel` and
must report changed phase-noise before/after waveform hashes. It is not accepted
as a label-only RF setting.

## Scope Boundary

This closure does not claim every production PDSCH/PUSCH trial row now carries
complete ChannelRealizationId and RFImpairmentChainId lineage. That integration
must be implemented and tested separately for the data-plane runners.

Unsupported or not-yet-integrated items include sample-clock offset resampling,
exhaustive TR 38.901 map-based/hybrid models, spatial consistency/blockage,
dual mobility, NTN/HST cases, FR2 oxygen absorption, RIS/reconfigurable-surface
models, and sub-THz/6G-specific channel models.
