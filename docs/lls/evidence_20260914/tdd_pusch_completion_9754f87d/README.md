# TDD shared-PUSCH focused passing receipt

Source: `9754f87def193db8a658a5472de53e6aae95bd77`.
Original run: `logs/testall_20260914T110611429Z_fea335dc`.
MATLAB R2026a Update 4; both selected tests passed; launcher exit 0.

These files are copies of emitted runtime receipts, console log, and received
DL/PUSCH CSV rows, not regenerated measurements. Nonempty scenario metadata
retains its exact resolved configuration and seed. Original waveform MATs,
channel-observation artifacts and the complete local test roots remain under
`logs/tdd_shared_pusch_independent_completion/tp78adc98d_0a41_4819_bb63_e47addbfe47d`
and `logs/tdd_shared_pusch_nonempty_completion/tp720d1cf7_bf1a_4a5a_a316_b6f96b44d1e7`.
This compact Git receipt does not contain the complete waveform archive.

Scope: component completion using actual shared SSB/SRS/PDCCH/PDSCH/PUSCH
execution, normal slot reducers, independent feedback reception and once-only
commit checks. This high-SNR fixture is NOT a 12 dB run, full coordinator
qualification, statistical detector qualification, a MATLAB-version matrix,
or complete missing-DCI/mixed-HARQ-CSI-SR acceptance. `suite_pass=false` and
`baseline_12db_qualified=false` are intentional and remain unchanged.
