# RAN1 10.5.3.1 DL-CSI simulation methodology

The suite separates `ANALYTICAL`, `SANITY`, `PROCEDURE`, `LLS_CONTROLLED`,
`LLS_COMMON_EVM`, `SLS`, and `NOT_EVALUATED` evidence. A controlled waveform
result is never promoted to common-EVM evidence. UPT percentiles,
simultaneous multi-UE event load, and network/UE energy savings require SLS
and remain `NOT_EVALUATED_IN_LLS`.

All scenario policy is resolved from layered YAML. Strict execution forbids
fallback, channel-profile ambiguity, logical-port reduction, perfect-CSI
substitution, and configured-feature disabling. The high-port CSI-RS kernel
processes one CDM group through NR OFDM at a time to bound memory while
preserving every requested logical port. Production PDSCH evidence delegates
coding, rate matching, modulation, OFDM, channel, channel estimation,
equalization, demodulation, LDPC and CRC to the existing SixGR chain.

Every figure is created in a separate replay phase after its source CSV is
closed and reopened. The figure manifest binds the source and PNG hashes,
dimensions, nonblank check, selected columns and replay result. Repository
policy emits PNG rather than SVG.
