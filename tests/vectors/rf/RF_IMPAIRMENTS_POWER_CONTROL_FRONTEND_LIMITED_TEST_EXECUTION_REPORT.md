# RF impairments, power control and receiver-front-end execution report

Execution date: 2026-07-26/27 IST

Branch: `main`

MATLAB: R2026a Update 4

5G Toolbox: 26.1

Python: 3.12.4

## Honest status

Phase-11 focused implementation and artifact gates pass. The mandatory full-repository acceptance gate is unresolved:

- Phase-11 independent vectors: PASS, 474/474 checks.
- Phase-11 focused MATLAB tests: PASS, 86/86.
- Mandatory name-filter selections: PASS, 114/114 selected executions.
- Base runner: PASS, 72/72 mandatory tests; 32 CSV and 22 PNG artifacts.
- Base artifact verifier: PASS, 334/334 checks.
- Impact runner: PASS, 768/768 experiments, 384/384 matched pairs and 96/96 rules; 16 CSV and 30 PNG artifacts.
- Impact artifact verifier: PASS, 338/338 checks.
- Config/DL/UL/reference-point smoke batch: PASS, exit 0.
- `testAll`: UNRESOLVED, timeout exit 124 after 3,605.7 seconds; no failed-test summary was emitted.
- E2E truth-integrity batch: UNRESOLVED, timeout exit 124 after 1,205.9 seconds; no failure summary was emitted.

The two timed-out batch process trees were stopped by exact command-line/PID matching. IDE and unrelated MATLAB sessions were not stopped.

Final repository-wide acceptance status: **FAIL / UNRESOLVED** because the full regression and the additional E2E integrity batch did not complete. This does not invalidate the completed Phase-11 gates, but it prevents a claim that the whole repository regression passes.

## Implemented production behavior

- One canonical `+sixgr/+rf/+runtime` package with explicit profile, capability, planning, reference-plane, state-trace and stage-ledger authority.
- Separate ideal, RF-impaired research and RF conformance-emulation execution classes; RF-device conformance claims reject.
- Explicit Tx/Rx oscillator state, blind CFO acquisition/tracking, timing acquisition/tracking and relative oscillator ownership.
- Stateful anti-aliased Farrow sample-clock resampling with phase, drift and timestamp state; fixed-length linear SCO is not used.
- Explicit phase-noise masks, state continuity and configurable multi-chain LO correlation.
- Frequency-flat/frequency-selective IQ imbalance, DC/LO leakage, measured IQ estimation and independent compensation state.
- Rapp, Saleh, memory-polynomial and GMP PA kernels; no output-power restoration.
- CFR, DPD training/holdout/profile/ageing evidence with separate waveform hashes.
- Explicit DAC, reconstruction filter, selectivity/LNA/mixer, stateful AGC, anti-alias filter and ADC models.
- Sample-domain EVM, ACLR, SEM/OBUE, frequency-error and time-alignment measurements. SEM rows use actual generated complex samples, explicit RBW integration and source-waveform hashes.
- Event-sourced PUSCH, PUCCH, SRS and PRACH power-control controllers with actual waveform-power reconciliation.
- Friis/ENBW thermal-noise accounting and actual post-converter error/covariance evidence.
- Both master YAML files own the same complete RF field tree; the resolved immutable RF profile is stored in the internal configuration.
- Impact rows remain labelled `bounded_rf_runtime_evidence`; they are not relabelled as device conformance or unsupported waveform truth.

Specification profiles pin selected conducted-method baselines. TS 38.141-2 radiated execution remains disabled as `SPEC_LOOKUP_REQUIRED`; no hardware certification claim is made.

## Commands and outcomes

```text
python tests/vectors/rf/verify_rf_vector_pack.py tests/vectors/rf
PASS: 474/474

matlab -batch "setup6GRSimToolkit('Verbose',false); r=runtests({...three RF files...}); assertSuccess(r)"
PASS: 86/86

matlab -batch "setup6GRSimToolkit('Verbose',false); ok=testRFImpairmentOrderedChain; ... testRFImpairmentChainApplied; ... testPDCCHCFOAndTiming ..."
PASS: 2 direct anchors and 1/1 PDCCH integration test

matlab -batch "addpath(pwd); s=sixgr.rf.runtime.runRFFrontEndPhaseValidation(...); assert(s.Passed);"
PASS: 72/72 mandatory Phase-11 tests

python tests/vectors/rf/verify_rf_artifacts.py artifacts/rf_frontend_phase
PASS: 334/334

matlab -batch "addpath(pwd); s=sixgr.rf.runtime.runRFFrontEndImpactAnalysis(...); assert(s.Passed);"
PASS: 768 experiments, 384 pairs, 96 rules

python tests/vectors/rf/verify_rf_impact_artifacts.py artifacts/rf_frontend_impact
PASS: 338/338

runtests('tests','IncludeSubfolders',true,'Name','*RF*')
PASS: 87/87
runtests('tests','IncludeSubfolders',true,'Name','*CFO*')
PASS: 9/9
runtests('tests','IncludeSubfolders',true,'Name','*Timing*')
PASS: 8/8
runtests('tests','IncludeSubfolders',true,'Name','*PowerControl*')
PASS: 7/7
runtests('tests','IncludeSubfolders',true,'Name','*EVM*')
PASS: 3/3

matlab -batch "setup6GRSimToolkit('Verbose',false); testConfig; testLLS_DL; testLLS_UL; testLLS_ReferencePoints"
PASS: exit 0

matlab -batch "setup6GRSimToolkit('Verbose',false); testAll"
UNRESOLVED: exit 124 after 3,605.7 seconds

matlab -batch "setup6GRSimToolkit('Verbose',false); testE2E_FastVsTruth; testE2E_TruthPacketSemanticCampaign"
UNRESOLVED: exit 124 after 1,205.9 seconds
```

## Exact changed production/test/config inventory

Canonical runtime files (73):

```text
+sixgr/+rf/+runtime/+oracle/ACLRFilterSpec.m
+sixgr/+rf/+runtime/+oracle/CFOAnalyticalSpec.m
+sixgr/+rf/+runtime/+oracle/EVMReferenceSpec.m
+sixgr/+rf/+runtime/+oracle/FractionalDelaySpec.m
+sixgr/+rf/+runtime/+oracle/FriisNoiseFigureSpec.m
+sixgr/+rf/+runtime/+oracle/IQWidelyLinearSpec.m
+sixgr/+rf/+runtime/+oracle/MemoryPolynomialSpec.m
+sixgr/+rf/+runtime/+oracle/PhaseNoisePSDOracle.m
+sixgr/+rf/+runtime/+oracle/PowerControlSpec.m
+sixgr/+rf/+runtime/+oracle/QuantizerSpec.m
+sixgr/+rf/+runtime/+oracle/RappSalehSpec.m
+sixgr/+rf/+runtime/+oracle/ResamplingSpec.m
+sixgr/+rf/+runtime/AbsolutePowerLedger.m
+sixgr/+rf/+runtime/ACLRMeasurement.m
+sixgr/+rf/+runtime/ADCModel.m
+sixgr/+rf/+runtime/AGCState.m
+sixgr/+rf/+runtime/AntiAliasFilter.m
+sixgr/+rf/+runtime/BlockerScenario.m
+sixgr/+rf/+runtime/CFOAcquisitionEngine.m
+sixgr/+rf/+runtime/CFOState.m
+sixgr/+rf/+runtime/CFOTrackingLoop.m
+sixgr/+rf/+runtime/CrestFactorReduction.m
+sixgr/+rf/+runtime/DACModel.m
+sixgr/+rf/+runtime/DCOffsetAndLOLeakage.m
+sixgr/+rf/+runtime/DPDProfile.m
+sixgr/+rf/+runtime/DPDTrainer.m
+sixgr/+rf/+runtime/EVMMeasurement.m
+sixgr/+rf/+runtime/FrequencyErrorMeasurement.m
+sixgr/+rf/+runtime/GeneralizedMemoryPolynomialPA.m
+sixgr/+rf/+runtime/InBandEmissionMeasurement.m
+sixgr/+rf/+runtime/IntermodulationScenario.m
+sixgr/+rf/+runtime/IQImbalanceCompensator.m
+sixgr/+rf/+runtime/IQImbalanceEstimator.m
+sixgr/+rf/+runtime/IQImbalanceProfile.m
+sixgr/+rf/+runtime/LNAProfile.m
+sixgr/+rf/+runtime/MemoryPolynomialPA.m
+sixgr/+rf/+runtime/MixerProfile.m
+sixgr/+rf/+runtime/NoisePowerLedger.m
+sixgr/+rf/+runtime/OFDMScalingLedger.m
+sixgr/+rf/+runtime/OscillatorState.m
+sixgr/+rf/+runtime/PAProfile.m
+sixgr/+rf/+runtime/PhaseNoiseCorrelationState.m
+sixgr/+rf/+runtime/PhaseNoiseProcess.m
+sixgr/+rf/+runtime/PhaseNoiseProfile.m
+sixgr/+rf/+runtime/PRACHPowerController.m
+sixgr/+rf/+runtime/PUCCHPowerController.m
+sixgr/+rf/+runtime/PUSCHPowerController.m
+sixgr/+rf/+runtime/ReceiverFrontEnd.m
+sixgr/+rf/+runtime/ReconstructionFilter.m
+sixgr/+rf/+runtime/RFArtifactExporter.m
+sixgr/+rf/+runtime/RFCapabilityProfile.m
+sixgr/+rf/+runtime/RFChainConfiguration.m
+sixgr/+rf/+runtime/RFImpactArtifactExporter.m
+sixgr/+rf/+runtime/RFImpactEvidenceBuilder.m
+sixgr/+rf/+runtime/RFPhaseEvidenceBuilder.m
+sixgr/+rf/+runtime/RFPlanningResult.m
+sixgr/+rf/+runtime/RFReferencePlane.m
+sixgr/+rf/+runtime/RFSelectivityFilter.m
+sixgr/+rf/+runtime/RFSpecificationProfile.m
+sixgr/+rf/+runtime/RFSpecificationTableRegistry.m
+sixgr/+rf/+runtime/RFStageLedger.m
+sixgr/+rf/+runtime/RFStateTrace.m
+sixgr/+rf/+runtime/runRFFrontEndImpactAnalysis.m
+sixgr/+rf/+runtime/runRFFrontEndPhaseValidation.m
+sixgr/+rf/+runtime/SampleClockState.m
+sixgr/+rf/+runtime/SpectrumEmissionMeasurement.m
+sixgr/+rf/+runtime/SRSPowerController.m
+sixgr/+rf/+runtime/StatefulSampleRateOffsetResampler.m
+sixgr/+rf/+runtime/TimeAlignmentMeasurement.m
+sixgr/+rf/+runtime/TimingAcquisitionEngine.m
+sixgr/+rf/+runtime/TimingTrackingLoop.m
+sixgr/+rf/+runtime/TransmitterFrontEnd.m
+sixgr/+rf/+runtime/UplinkPowerControlState.m
```

Integrated production/config/test/report files:

```text
+sixgr/+lls6g/buildInternalConfig.m
+sixgr/+rf/PhaseNoiseModel.m
+sixgr/+rf/applyPowerContext.m
+sixgr/+rf/applyRFImpairmentChain.m
simulator/configs/scenarios/master_geometry_based.yaml
simulator/configs/scenarios/master_sinr_sweep.yaml
tests/testRFCanonicalRuntimeCoverage.m
tests/testRFFrontEndPhase11.m
tests/testRFMasterYAMLAuthority.m
tests/testRFImpairmentOrderedChain.m
tests/vectors/rf/RF_IMPAIRMENTS_POWER_CONTROL_FRONTEND_LIMITED_TEST_EXECUTION_REPORT.md
```

The two RF artifact directories contain the 100 regenerated contracted outputs listed below. The worktree also contains pre-existing Phase-10/channel and earlier-phase changes; those are not attributed to Phase 11 here.

## CSV row counts and SHA-256

### Base (32/32)

| CSV | Rows | SHA-256 |
|---|---:|---|
| rf_aclr_measurement.csv | 100 | `477a36d140bd818cc4fa7ffa18e8d91940129ca4fc36e6e4f6a3fcdec63f0209` |
| rf_adc_quantization.csv | 189 | `4af092c356b5f313dd565977f089654fc5df9dbcc7b182a48de3633487aec965` |
| rf_agc_trace.csv | 100 | `8503c32154fcc62228352402ed92a2c8d228fd4b01b2fd67c80d7dc8d9ad890f` |
| rf_blocker_trials.csv | 144 | `3c253e4468c37b5afe4ffe9d903239dc1226df6871ccf3ac87ed727b26c966b2` |
| rf_cfo_acquisition.csv | 100 | `94df612438f8233c04d42ece68cc20c5d31cd0c5c79ea787e4a2af938e6c955b` |
| rf_cfo_tracking.csv | 200 | `9a2db3bfffca15422ed786683b692e3aa583e1c84368c1a5571762b0449c0a52` |
| rf_chain_stage_ledger.csv | 100 | `5d6902625bb9de735a21a3064431d85cb5d9ad2670069cc2a16ab0dd8538da24` |
| rf_dac_quantization.csv | 189 | `5b3a04643a3d451d58bc8e747f9ccfa32a272f95ef113a2628f0c2c1adf2e6f2` |
| rf_dpd_training.csv | 72 | `855ff052ff9985e90d8f88a3de22c012eeb0852899402e3ab816910952186be2` |
| rf_dpd_validation.csv | 72 | `5e9fa74314e5bbde2f35c8922169a8c7e5936e13f5557a9589730276919f5df3` |
| rf_evm_measurement.csv | 105 | `5e42d2e5cedda3e3a2443a405b7d419f79c660046f3ac41699b3cde8dbe4d043` |
| rf_image_semantic_audit.csv | 22 | `f82c00ef714f2895c91298ae6391bdeea191175130fd9779ad9e0762c83d60d0` |
| rf_intermodulation_trials.csv | 144 | `34d44c116f171133919ded861d8d97354ef246497ce8ff4db07a16305e808799` |
| rf_iq_compensation.csv | 100 | `12981b06dc6c9be14cccc78b871907648614b6544027dc4776948d1fc315e558` |
| rf_iq_imbalance.csv | 140 | `d7da8070d184bfe2d23cdeba21d3db5e8077412d09d7717313d5ca0b97e3c226` |
| rf_negative_tests.csv | 180 | `079b814439b12dfd298766f655bd320342939f73a58ae22c0decb3c3a5d8db53` |
| rf_noise_figure_cascade.csv | 108 | `b5a65c23f69033a5c8484034753b7851663eb591d5e44e6f17a5ddae65d43e6f` |
| rf_pa_characterization.csv | 189 | `3ec2725a778475c61762f916e96776fd6a5e163de640a1b651bfac87bc1f4ee4` |
| rf_pa_memory.csv | 189 | `33cc63ce97b810410ca8284802a8fc617b9b6853ff371e714282f60d6b15f155` |
| rf_phase_noise_psd.csv | 360 | `a44330abd6336ba1bb1597993be3ffeb56be445441dd307653b66a64a942fe0b` |
| rf_phase_noise_tracking.csv | 100 | `f619538456e664318059d05e8fa1e29f8762be2cf1563f8be3703252d76b3bde` |
| rf_power_control_state.csv | 192 | `ab10fd45e27f4e717bca6f8745dbaca68dfb5e1dbb7b204486ec2210746b7328` |
| rf_profile_resolution.csv | 210 | `91f8489ee07f6ec25e65853baf386582b51d75bafaeb5420891f221b3faa58a3` |
| rf_receiver_dynamic_range.csv | 100 | `b54cb4ceedb2f05b368cd947d8414f945eff12ef6ec2390e972480dd23ecabb8` |
| rf_receiver_metrics.csv | 100 | `494f66bda04b20cde5a760bbaee1e04eb8294ced0c1e25fe6391ab3c74707b0c` |
| rf_reference_plane_power.csv | 100 | `2642cf14a04229cf48e9c8844351c69931aba8b91573d168debf45b593c7cbf0` |
| rf_sco_resampler.csv | 150 | `29c825fb99ee153da47e68eb6cfc62dca38a54b85f113a69a12782257da809ff` |
| rf_sem_obue_measurement.csv | 100 | `b2140cbcc2093d69d17be763dda6b232ef68acf7325b1c89f7fa244394bc7a2f` |
| rf_test_summary.csv | 1 | `9c143a0f5d0764225627415d32cc74da990fad6e68d00e404ceccb592d1d8560` |
| rf_timing_acquisition.csv | 100 | `fb6b5e5142b1e2594e6913fe6704169db0056622a102044ca747c4aab5e5fd89` |
| rf_timing_tracking.csv | 200 | `5e14bcf7ae5168b5987aba3ab0285d1c692c4dc51b923013b8e5b07525d3d401` |
| rf_ul_power_control.csv | 192 | `992aa41e99ab99f16f728a54464673d1705d381cd38b65772dc6fe70c0797f08` |

### Impact (16/16)

| CSV | Rows | SHA-256 |
|---|---:|---|
| rf_impact_blocker_receiver.csv | 100 | `0e3cddf4c9c8b7c456d0d45e666c85cd7ca64d295a8266a2eb6e7238646bd8a1` |
| rf_impact_cfo_timing.csv | 156 | `14841c04ea8520b1720ea6a35e910d548c5ae4a624dea3f19db82767dd0ea0d7` |
| rf_impact_data_converters.csv | 100 | `cfcc06dffe7e624a04ac1a23a6d6bca47a79caa3551a72aebfed27ab5aeb42c8` |
| rf_impact_image_semantic_audit.csv | 30 | `c38ece2f9521de5541f31446e05d18672d7c035b2c9853bda9b18a45415addd4` |
| rf_impact_interactions.csv | 64 | `6f4df184b348cede31a832db0ac7e536491e80ac4d5e9d70c5387e900ae40e76` |
| rf_impact_operating_points.csv | 384 | `abbad574ad34380ce8d75bfa8ba08f9948e16425d0f3e2c350583017b1d40bd3` |
| rf_impact_pa_dpd.csv | 100 | `165cf85c61fa49e06b89cb79abbe4d6c47d65f493b882edcb868170b7cea5dfa` |
| rf_impact_pairwise_effects.csv | 64 | `b387462555a23e69487bf7a9e70609aa0c7f69dca33732eb48f4661917a31532` |
| rf_impact_phase_noise_iq.csv | 132 | `271be89c38c503f5fa8ca64667dc573431b7393ad725995c9825605c568561f4` |
| rf_impact_power_control.csv | 144 | `17fe8a63b50f1fb060acf3003932598e1a1f71c22cde2528a0f2279be047049e` |
| rf_impact_raw_trials.csv | 768 | `4e48626253f756a8000c2d463d04c9cc01cc3ee7d3e2b94e2436f0b71b3e948c` |
| rf_impact_rule_evaluation.csv | 96 | `fe9721862807a4ffc4c0518a5f87dd2ceb51a39c652229f9d2cb30cf68ba4cd4` |
| rf_impact_run_manifest.csv | 64 | `42d8a1dd6c8bda5b6101e4e92a477dd36a0e94f714ca4c41dd16094cafdefc6b` |
| rf_impact_runtime.csv | 64 | `92f76686643183d8755841ec4b5829c604d82007e59e0c6b26d03c927dc00582` |
| rf_impact_summary.csv | 64 | `4e3e16f69b786fc7b0e4178079eb2bbac84621faebf9775dca2000551b056808` |
| rf_impact_waveform_quality.csv | 100 | `737d1b216e99603d31921aea54969c9bad7a2c877a9c593d0431f32b7f2ca937` |

## PNG dimensions and SHA-256

The title, axes, series count, finite-point count and source-CSV SHA-256 for every image are also stored in:

- `artifacts/rf_frontend_phase/rf_image_semantic_audit.csv`
- `artifacts/rf_frontend_impact/rf_impact_image_semantic_audit.csv`

### Base (22/22)

| PNG | Dimensions | SHA-256 |
|---|---:|---|
| rf_aclr_spectrum.png | 1041x786 | `739467a0bb395656f11d9d8e45429606da41b513107db4cea48edd9d946fe065` |
| rf_agc_overload_trace.png | 1044x782 | `a3d23b5a694118fe26849b013cf95caaa41069c777c8b5090f4c55b28e462a82` |
| rf_blocker_desensitization.png | 1050x786 | `57f3c5ca8ec3f0e5c416d17f312dea20ddf932b17c1c990521ee2149986e6996` |
| rf_cfo_acquisition_tracking.png | 1044x782 | `0aa181a5248bfa31f032b4ec2d4fd0820465f27ebff1d40f65d560af6e75d293` |
| rf_cfo_residual_vs_snr.png | 1045x784 | `070636c758678332e2c75327f45a258975225e39c814cb565c40b323fcfd1093` |
| rf_chain_reference_planes.png | 1041x786 | `d07144cfacff7cfc969bf572debc1d6c94592aaffe4b8d21be490e0d6bbd0388` |
| rf_dac_adc_quantization.png | 1035x786 | `d69e10eaef4f4375648f0903eb40876d7a691f399f9aa74349c10e2559692918` |
| rf_dpd_aclr_evm.png | 1030x784 | `a2201e448e48476b02cc5b909e8916993189ef940eb702470d322ca21c889ab1` |
| rf_end_to_end_bler.png | 1035x782 | `07001b085c589a47cd2d6f612d1fbef1320097448549f93e8096da6a4a1c4bf1` |
| rf_evm_by_modulation.png | 1040x782 | `a3c4e1f184b5b0d2ca0bf0149fb272cc0c1a8a28c4b63b55615cd55c9d1da4f4` |
| rf_intermodulation_spectrum.png | 1049x788 | `70119c7e85613a0bfee57730dcf2941f8421b7ced4b04333c6bdbf143770ce96` |
| rf_iq_compensation.png | 1045x782 | `27b11354f4cbedf32a35e8187baecb53bff9dc5f442faaf2ba6ee158a3ce9775` |
| rf_iq_constellation_image.png | 1045x786 | `6beff5c6c91d856af59e64342264160becb85dc96674465cfcd9b2fd990ecfcc` |
| rf_noise_figure_cascade.png | 1035x786 | `03c3474521ade6be27219a4e128a674646ea13647aafd03fdc9b49385c8095e0` |
| rf_pa_amam_ampm.png | 1059x786 | `473ad04100f97f283de60dfcfaa6638a1fc5bb8d2c49d83b0687893adc340d49` |
| rf_pa_memory_spectrum.png | 1040x786 | `95028e5e3903fdd4fde185268364e328edf0054c57eba7f35463ca6dc7e41a8e` |
| rf_phase_noise_cpe_ici.png | 1045x782 | `c5abb1e36d530fcc98de0bfbcd7227c148ea7d1d64b2fa83e7a7f19a944f3592` |
| rf_phase_noise_mask.png | 1035x788 | `57d3fcf98d724beb8ce134d458db972bed64dd815ade54909e817c9bbfd898b2` |
| rf_sco_drift_resampling.png | 1063x782 | `c32267d2453aa27b7fd88b2f5cfacea3f8354202bac29981f20856fad1000c22` |
| rf_sem_obue_spectrum.png | 1035x788 | `ec8aad83537ad8ab2b4c31fd4b5e50770d34a652a7af8ab5c5cac8591079ef31` |
| rf_timing_tracking.png | 1044x782 | `76258a5548433d678543441bce9763419c559242904f8c337e94f35c47630c37` |
| rf_ul_power_control_convergence.png | 1044x782 | `7357099f1937381b0e577093d159105d942ac6546db2146f54c2b9045179b8dc` |

### Impact (30/30)

| PNG | Dimensions | SHA-256 |
|---|---:|---|
| rf_impact_aclr.png | 1035x786 | `5b57bb66ecc52461366bfe2db41c94b6d52194fb4b842c1446a802bc8b3f7656` |
| rf_impact_adc_bits.png | 1035x782 | `e69f844595574d9a7e1f49a4253756d74ec92382af9e7c3bfe347e5ea9094942` |
| rf_impact_adc_fullscale.png | 1035x782 | `ad327c493408ea2e116d75332d6f828d101bcafbbc73c2503c9896fde00a72a6` |
| rf_impact_agc_dynamics.png | 1035x782 | `3cbea0ff8da510a937491363c3a34716ddb3ac2c4396fb9a15a7877bc9c75d0c` |
| rf_impact_aperture_jitter.png | 1035x782 | `f2ef30fdcb268129857b7f2c7f9bb256d670e008b884d8cb79fb749eaae7130a` |
| rf_impact_blocker_offset.png | 1031x788 | `2d718abf633ccbb0110ab70a5a05477305d03ddcab39a2cbd68e1b98a4ce5bd1` |
| rf_impact_blocker_power.png | 1031x788 | `9e741e5e4fafe890cf49d5abfcfacac92bb7816aad5fc2224ef8839d73b40558` |
| rf_impact_cfo_magnitude.png | 1044x782 | `0c5591455ab061d19108d1e2c9e334c1586d0be9280768ab54e410c8bc4f14be` |
| rf_impact_cfo_tracking.png | 1044x782 | `5a5ae900f3b9e3aac5773ed30d3dd30d9d8caacad68c2e0df52afbf3f9ed1450` |
| rf_impact_cfr_papr.png | 1041x786 | `8e05ecfd9dc91b44bb6164860a6c1563642f31f3ad529f8ab7f71f259460b117` |
| rf_impact_dac_bits.png | 1035x782 | `1bfdcc37760accd6d6eef9eea8a8c89c388bb23075bb4bc7bece0185445240f2` |
| rf_impact_dpd_ageing.png | 1041x786 | `d591d083e08187640424ace5e3507eb9dfcca5f09eb8ae68c26485c46d2b0499` |
| rf_impact_dpd_order.png | 1041x782 | `3bc278d1d59ad33df3288312e5d962cb6cb5d252d12e7a833cbfdbd8bc30aee2` |
| rf_impact_evm_method.png | 1035x782 | `1a79b89b291e6e5c740607c1c05f8aca81f4eda99477bcd89d5a5cbb93432337` |
| rf_impact_interaction_forest.png | 1058x786 | `d16fda3e6d4b7a5b0c6a83a494374571486afe563479213fbe04632ee744618a` |
| rf_impact_intermodulation.png | 1031x784 | `27b73582d0b8935e7a1e1177369391d87857cade718a37e37ed0092e5f94e7e0` |
| rf_impact_iq_compensation.png | 1049x782 | `2fd22f6968aecbeeaf7196a9a1eb94d5bd6a02fb942e590f52b005ba9ecd3884` |
| rf_impact_iq_imbalance.png | 1049x783 | `2a5f967ff4eb9ebb926d3fa13f819162640d6347d1056f770a8798dc6d37ad06` |
| rf_impact_lo_correlation.png | 1049x782 | `2ad6a51bdd7a87f6aab6581f571471d04658e0695f680da08a67c8d2fbaace71` |
| rf_impact_noise_figure.png | 1031x788 | `dc0252dec9a1f2e17a747a59ab55e4ee625be106689444b72e13193271b70102` |
| rf_impact_pa_backoff.png | 1041x782 | `8b4805f7eaa777e12ebd354795bf70ef539461c0558b3a758a3d6d5760c94c8f` |
| rf_impact_pa_memory.png | 1041x786 | `3e6141056942732f71a8471b985fa1d39f8e148ec05c1a09b0728274bc5869d7` |
| rf_impact_phase_noise_cpe_ici.png | 1049x782 | `63e7b0d995fde1ce65f1d2a92db74c6dd592a21815fc4cf19e3e143b84903474` |
| rf_impact_phase_noise_mask.png | 1049x786 | `43aea50ec60b15b06da9fefeadfb40907083718c73d47678e3ded95da60f6a35` |
| rf_impact_power_control.png | 1041x782 | `a51da9bba815d9e5d5b3c7773298f0a5000d2e39577ef65443a0ff2dea0c818f` |
| rf_impact_reciprocal_mixing.png | 1031x784 | `fb31721f9c6f50c51a6003d041aee2925b5edbf51401dd529a78853e3a581374` |
| rf_impact_runtime_scaling.png | 1035x786 | `968002ea5a90da7f0edb76cf6bcb161004ecd45d1ddc5339da10a6568d43a8cf` |
| rf_impact_sco_drift.png | 1044x786 | `3880a1f1d1655603a9f100d943b5867230719d01c7839d670f092a4d92b4266c` |
| rf_impact_sem_obue.png | 1035x782 | `738c68e8151d2de5afe6db73140e7571e215312f60b684615e152d9bb7083ff8` |
| rf_impact_timing_offset.png | 1044x786 | `114701acf998479513393f3a453af1c4a8978b714dba17451d409602f30b8615` |

## Remaining limitations

- `testAll` and the two-test E2E integrity batch did not complete within their explicit command limits; repository-wide acceptance cannot be claimed.
- The impact study is bounded execution of production RF kernels and paired effects, not a full 1,000-trial-per-point RF-device qualification campaign.
- TS 38.141-2 radiated methods remain disabled pending an exact pinned method/table implementation.
- No result is labelled as RF-device conformance or certification.
- No commit was created. The branch is `main`, and the worktree contains Phase-11 changes plus pre-existing work from other phases.
