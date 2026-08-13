# RAN1 AI 10.5.2.2 simulation methodology

The study has two deliberately separated layers. `DeterministicSuite` derives time-domain group starts, nested sets, sequence indices, region-anchored bundles, interleaver maps, phase terms and NR codeword/layer round trips without a performance claim. `ControlledSuite` calls the existing `sixgr.link.runDLPDSCHThroughput` canonical PDSCH path. That path invokes the established transmitter, configured concrete fading channel, practical DM-RS channel estimator, equalizer, DL-SCH decoder and CRC. It does not replace those blocks with a study-specific PHY.

The bounded campaign uses one transport block at each configured Es/N0 point to test end-to-end execution quickly. Every point is therefore marked `INCOMPLETE`; the publication rule requires confidence-driven execution with at least 200 block errors near the target or another stated precision rule. Common-EVM and multi-cell SLS modes fail closed until their prerequisites are supplied.

Every generated report uses this truth statement:

> Deterministic PDSCH DMRS placement, nesting, sequence-index and PRB-bundle results are exact derivations under the stated configuration. Link-level results are produced by the identified SixGR MATLAB/5G Toolbox waveform, channel, receiver, coding and CRC path. They are not claimed to be 3GPP-conformance-calibrated unless a separate common-EVM calibration record is explicitly identified. Simplified Jakes, coherence-bandwidth or phase-only sanity models are diagnostic and shall not be used as TDoc-grade or filing-grade performance evidence. System-level claims require an actual multi-cell traffic, scheduler, interference and PHY-coupled run; a single-link or abstract-load proxy is not sufficient.
