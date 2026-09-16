# Data-window carrier power reference: normalized sweep versus absolute power

Status: focused grid, actual TDD DL/UL receive/export and Python plot tests passed. Full-suite and final integrated acceptance remain pending. Parent: `41f3f8aa07ab364283186214ca53072f13e1f0ae`.

## Root cause and repair

The immutable partial `d05c1441` 12 dB snapshot exposed a real unit error: `measureReceivedDataCarrierPower` unconditionally interpreted pre-front-end samples as sqrt(mW), divided the received FFT grid by `Nfft*sqrt(1000)` and exported watts/dBm. The same trial declared normalized fixed-reference transmission. The Python plotter accepted only the physical schema, so its internally consistent arithmetic still produced an incorrect dBm claim.

The new `measureDataCarrierGridPower` helper binds units to the prepared transmission's frozen input configuration. In explicit `FIXED_SNR_SWEEP` with configured-SNR link authority, it sums actual received FFT-grid energies per symbol/receive branch and exports unit-occupied-RE-Es powers and their logarithms. It publishes neither absolute watts nor dBm. In absolute-power mode, the original FFT/1000 conversion is unchanged. Both retain the real received window, nominal frequency alignment, grant identity, all branches and observation hash. No signal/noise samples, gains, losses, decoder results or timing decisions change.

Both shared data completion paths already copy the measurement fields into their primary tables. The normalized mirror column is included in the output contract. The chart parser supports explicitly scoped physical v1 and normalized v2 records, checks linear-energy closure in the declared units, rejects reference-plane conflicts and mixed-unit axes, and labels normalized CSV/PNG results as relative power. Old physical-only metadata cannot qualify a row declaring normalized transmission.

The window remains `received_data_symbol_window_full_carrier_not_ue_NR_RSSI_report`: this is not a claim of an independently configured UE NR-RSSI/SMTC report.

## Evidence

MATLAB R2026a batch, terminal exit **0**:

```matlab
setup6GRSimToolkit('Verbose',false);
r=runFocusedTests({'testDataCarrierGridPowerReference', ...
 'testTDDSharedPUSCHIndependentCompletion'});
assert(r.ok,'Data carrier reference validation failed');
assert(testDataChannelStreamStages('TDD',1));
disp('TDD_DL_CARRIER_POWER_RECEIVE_PASS');
```

- Independent two-branch grid-energy test, FFT sizes 512/1024, relative/absolute reference separation, no IQ mutation and zero-energy rejection: PASS.
- Actual shared TDD PUSCH completion and normalized carrier-power CSV/PNG: PASS. This retained high-reference-SNR component has empty UCI; it is not integrated 12 dB or nonempty-HARQ qualification.
- Actual TDD DL stage completion, full paired-symbol EVM, received clocks, exact FFT constant-IQ power and amplitude-scaling checks, carrier-power CSV/PNG: PASS. This is a component fixture, not full access/scheduling qualification.

Log: `logs/data_carrier_reference_v2_20260916.log`

SHA-256: `21FEED3B0E7002C8B50B2C548867905579FE67592C716ECB4A3C0B26B0896D08`

The original `logs/data_carrier_reference_20260916.log` is retained: grid test passed, receive verifier failed because it still unconditionally required watt fields. The verifier now checks the configured reference plane, retains the original physical assertions for physical mode, and adds normalized energy and plotted-value assertions. The constant-IQ normalized expectation is the exact FFT DC energy (`Nfft^2`), not a fabricated 0 dBm.

Python command, **157 passed**, terminal exit **0**:

```powershell
python -m pytest tests/test_lls_radio_measurement_plots.py tests/test_live_csv_plot_publication.py tests/test_regenerate_lls_rasters_from_csv.py tests/test_lls_complete_output_contract.py -q --junitxml=logs/data_carrier_plot_tests_v2_20260916.xml
```

JUnit SHA-256: `AE2B2DAD7C5D25E338FFFB4C44339E620ECA46BFD3DF94CE02DCCBAE512EC4AC`

Retained component evidence:

- UL: `logs/tdd_shared_pusch_independent_completion/tpfc96d0c6_dd43_435e_b0c3_978b00eb4d5f/`, including `received_pusch.csv` and an unchanged archival copy of receiver plots in `receiver_plot_snapshot/`.
- DL: `logs/tpb8337276_6dd8_4d6b_a501_958759a5527b/`, including `receiver_plot_snapshot/`.

Archived plot manifests preserve their original producer/source paths and bytes; copies are not relabeled as new RF executions. The actual UL carrier-power PNG was visually inspected and shows relative units and a partial-evidence caption.

## Still required

Run `testAll`, NR/config/LLS/strict/scheduler guards, export/artifact guards and both E2E truth/proxy guards on the final consolidated revision. Repeat/review integrated 5 MHz TDD / 12 dB exports on that revision. The still-running `d05c1441` scenario intentionally keeps its original source; its old RSSI artifacts remain incorrect and are not retroactively qualified by this patch. Detector qualification, combined HARQ/CSI/SR coverage, other regression failures, all final measurements/plots and MATLAB R2023b validation remain open.
