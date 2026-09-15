# TDD 5 MHz / configured 12 dB: SSB power-reference repair

## Root cause and scope

The fixed occupied-RE reference-energy mode previously copied physical-grid dBm numbers unchanged into fields labeled relative to unit occupied-RE energy. Its SSB measurement producer divides the demodulated grid by `Nfft*sqrt(1000)`. Consequently the required reporting conversion is `relative_dB = reported_dBm + 20*log10(actual_Nfft)`. The independent generated-grid baseline at Nfft 512, amplitude 0.25, measured -66.2676 instead of -12.0822: a 54.1854 dB reporting-reference error.

The [MathWorks SSB measurement API](https://uk.mathworks.com/help/5g/ref/nrssbmeasurements.html) documents dBm for RSRP/RSSI. The offset above follows from this repository's explicit FFT/grid scaling, not a universal 3GPP correction or an additional propagation gain. No IQ samples, transmit power, noise, fading, detector, ACK, CQI or acceptance threshold were changed.

Additional defects: normalization promoted unavailable SSS measurements to available; TX EPRE lacked its own FFT/scale provenance; normalized signal/disturbance operands retained watt labels; several full-burst/periodic/export adapters dropped normalized power evidence.

## File-level repair

- `+sixgr/+link/normalizeReceivedSSBPowerReference.m`: convert RX RSRP/raw RSRP/window RSSI with the actual RX scale; convert actual TX EPRE with its own producer scale; convert linear desired/disturbance operands by scale squared into explicitly relative-energy fields. Keep SINR and receiver decisions unchanged. Preserve unavailable status and missing TX evidence, reject malformed/missing scale, and enforce exactly-once normalization. Withhold absolute dBm/pathloss claims in normalized mode.
- `+sixgr/+link/completeCellSearchBroadcast.m`: retain actual TX measurement FFT/scale and propagate same-producer power metadata through the full-burst result views.
- `+sixgr/+link/ssbPowerReferenceEvidence.m`: typed copy of optional evidence into existing actual rows; never creates substitute trial rows.
- `+sixgr/+truth/SSBOccasionResultDelivery.m`: retain relative power vectors and conversion metadata through actual periodic-reception publication and the canonical measurement ledger.
- `+sixgr/+truth/runWaveformLinkBundle.m`, `+sixgr/+link/runSSBBeamSweep.m`: preserve those fields in actual PBCH/beam-sweep rows with consistent empty-schema defaults.
- Tests: independent generated NR SSB grid/OFDM power oracle at FFT sizes 512/1024 and amplitudes 0.25/1; scale/availability guards; actual full-burst TX/RX result binding; actual periodic reception and CSV round-trip. Register the new math and broadcast tests in `testAll`.

## Retained tests, including failures

Development checkout: `C:/Users/anup0/AppData/Local/Temp/sixgr_tdd_ssb_units_20260915`. Logs remain under its `logs/` directory.

- `ssb_unit_grid_before_repair_20260915.log`: reproduced the independent power-reference failure.
- `ssb_unit_grid_after_repair_20260915.log`: first four focused checks passed.
- `ssb_unit_grid_delivery_final_20260915.log`: five passed; the new full-burst test used nonexistent top-level `BCHCrcPass`. Corrected that new fixture to read the actual public result `out.PBCH.Ok`; did not alter receiver behavior or weaken an existing assertion.
- `ssb_unit_grid_delivery_verified_20260915.log`: **6 passed, 1 failed; batch exit 1**. Math 3.06 s; authority 50.01 s; full broadcast 41.08 s; normalized periodic delivery 53.68 s; physical SSS math 0.26 s; window power 0.41 s. The physical-power periodic companion failed in 26.89 s at `sixgr:truth:InvalidSSBPowerReference`, before its later delivery/export assertions. This is not a fully passing regression batch.
- Verified-batch log SHA-256: `DD99E95E96CC49F1707A15ED59CB284B7DAED1295BA4A946A2E3B20A95076A48`.
- Pre-patch comparison: clean revision `76c39503670064646a228f4c133f55851c5fd160` in `sixgr_tdd_measurement_units_20260915` reproduced the same physical companion failure at `bindSharedSSBPowerReference` line 93 / test line 37 (99.72 s, exit 1). Log: `logs/ssb_physical_companion_baseline_76c39503_20260915.log`. Thus that failure predates this SSB unit repair; it remains unresolved and its original guard remains unchanged.

Actual full-burst relative RX power was 5.82173 dB, TX EPRE -0.814601 dB, and their difference 6.63633 dB. These are measured values on their declared reference, not forced 0 dB gain or physical pathloss. Actual periodic delivery retained four received SSBs, earliest availability slot 2, and unchanged single-transmission/filter-update guards.

## Acceptance remains open

This repairs and component-tests the normalized SSB power-reference path. It does not certify the whole simulator or close the physical-power companion failure. Final-source required config/LLS/strict/scheduler/export/E2E guards and `testAll` remain required. Integrated all-measurement and CSV/PNG verification, detector qualification, and combined feedback closure remain open.

The currently running 58-slot TDD 5 MHz / configured 12 dB retry is frozen at `5e3fc49b`; it does not contain the newer CSI or SSB measurement repairs. Do not use its outcome to qualify this source revision. The authored sweep remains `[-30,-20,-10,0,10,12,20,30,40]`; only the 12 dB point is the current execution priority. FDD and 400 MHz implementation remain deferred.
