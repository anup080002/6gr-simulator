# Configured 12 dB CSI power-reference math (15 Sep 2026)

## Root cause and equation

The normalized fixed-SNR path preserves the generated IFFT waveform and declares the reference energy of an occupied resource-grid RE to be one. The CSI physical-power producer divides its demodulated grid by `Nfft*sqrt(1000)` before measurement. Consequently its numerical dBm result is `10*log10(grid_power)-20*log10(Nfft)`. Copying that value unchanged into a field labeled relative to unit occupied-RE energy introduces an FFT-dependent error. The earlier CSI availability repair did not qualify this numerical conversion.

The independent generated-grid reproduction at `Nfft=512`, amplitude 0.25, reported -66.2266 dB instead of the authored -12.0412 dB: a 54.1854 dB offset. This is a reporting-reference error, not missing transmit power or excess channel loss. The transmitted CSI EPRE export had the same omission. Correcting RX alone would corrupt the reported RX-minus-TX channel gain.

The [MathWorks CSI measurement API](https://www.mathworks.com/help/5g/ref/nrcsirsmeasurements.html) documents dBm for RSRP/RSSI and dB for RSRQ, with an OFDM waveform-scaling example. The FFT-reference conversion above follows from this repository's explicit sample/grid scaling; it is not a new universal 3GPP power constant. See also the [MathWorks link SNR definition](https://uk.mathworks.com/help/5g/ug/snr-definition-used-in-link-simulations.html) for the distinction between waveform and resource-grid normalization.

## Implementation

- `+sixgr/+phy/+refsig/convertCSIRSPowerToUnitRE.m`: use the producer's actual FFT size and grid-to-watt scale, add `20*log10(Nfft)` to numeric powers and retained branch/resource power vectors. Reject missing/mismatched scale for retained measurements and malformed vector tokens. Missing values remain missing; no eval-based parsing.
- `normalizeCSIRSPowerReference.m`: apply that conversion to received RSRP, RSSI and both RSRQ power operands. Preserve the measured RSRQ itself, availability authority and physical-mode behavior. Continue withholding absolute dBm claims in normalized fixed-SNR mode.
- `+sixgr/+link/runDLPDSCHThroughput.m`: convert actual TX connector EPRE using its own producer scale, so RX-minus-TX channel gain stays on one reference.
- `+sixgr/+link/deriveMeasuredPHYEvidence.m`: normalized-mode primary evidence now takes the selected pre-front-end CSI measurement named by its source label, not the separate post-front-end grid-power diagnostic. The latter remains available under its original explicit diagnostic fields.
- Tests: independent unit-grid/OFDM RSRP, RSSI, RSRQ and actual TX connector-power comparisons at two FFT sizes and two amplitudes; primary-row source selection; malformed/missing-scale negatives; normal DL CSI-present/absent execution and export binding. Register the new math test in `testAll`.

No waveform, noise, channel, power-control, detector, ACK, CQI, scenario or acceptance-threshold changes were made.

## Retained evidence and correction to the test oracle

Development checkout: `sixgr_tdd_measurement_units_20260915`; all logs below are under its `logs/` folder.

- `csirs_unit_grid_before_repair_20260915.log`: reproduced the numerical failure on source 5e3fc49b.
- `csirs_unit_grid_after_repair_20260915.log`: four tests passed; the new receiver check incorrectly required pre-front-end CSI-RSRP to equal a distinct post-front-end raw-grid power diagnostic. No established assertion was weakened. Replace that invalid cross-plane equality with explicit primary-row binding and same-reference RSRQ/channel-gain closure; retain the independent generated-waveform power oracle.
- `csirs_unit_grid_rx_tx_final_20260915.log`: **5/5 PASS**, process exit 0. Math test 6.77 s; availability/negative guards 0.07 s; actual normalized DL CSI-present/absent 58.13 s; physical resource measurements 0.71 s; branch selection 0.03 s.
- Actual receiver evidence: pre-front-end CSI-RSRP 0.000212968 dB, separate post-front-end grid diagnostic 0.000275038 dB, actual TX EPRE 0 dB, reported channel gain 0.000212968 dB. These values explain why the two receiver quantities cannot be asserted equal at 1e-8 dB.

This is focused measurement repair, not full 12 dB acceptance or complete 3GPP qualification. The frozen 5e3fc49b retry does not contain this newer repair. Final-source required regressions, all-measurement/CSV/PNG acceptance, detector qualification and combined feedback closure remain open. SSB normalized-power reference math still requires its own audit and repair; this patch does not claim to resolve it. FDD and 400 MHz remain deferred.
