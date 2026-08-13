# RAN1 AI 10.5.2.2 known limitations

- The named controlling DOCX was not supplied; the implementation is bound to the inspected Markdown prompt SHA-256.
- Proposed configurable TD-OCC `X/L` resource mapping is not yet in the canonical PDSCH Tx/Rx path. The waveform rows therefore describe the existing NR DM-RS baseline only.
- Nested co-scheduled waveform superposition, separate/pooled covariance comparisons, cross-slot continuous execution and extended FD-OCC coded LLS remain blocked.
- Requested 24/32/48-port LLS and 64/96 structural stress lack independently verified canonical DM-RS mappings.
- 200/400 MHz controlled waveform runs were not launched in the bounded campaign.
- Per-region PT-RS, multiple independently encoded frequency-multiplexed TBs, segment-specific MCS, enhanced codeword mappings and waveform multi-TRP common-profile execution remain blocked.
- Common-EVM calibration and genuine multi-cell traffic/scheduler/interference/PHY-coupled SLS evidence are unavailable.
- The short waveform points are statistically incomplete and not TDoc-ready.
