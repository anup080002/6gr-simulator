function cfg = buildInternalConfig(scfg, runFolder)
%BUILDINTERNALCONFIG Translate resolved ScenarioConfig into simulator cfg.

if isa(scfg, "sixgr.lls6g.config.ScenarioConfig")
    s = scfg.toStruct();
else
    s = scfg;
end
catalog = sixgr.lls6g.config.loadParameterCatalog("scenario");

cfg = sixgr.config.defaultConfig();

cfg.meta.loadedFrom = char(string(s.meta.scenario_id));
cfg.meta.configHash = char(string(localGetNested(s, "meta.config_hash", localGetNested(s, "meta.configHash", ""))));
cfg.run.seed = double(localRequireFirstNested(s, ...
    ["seeds.global_seed","simulation.random_seed"], ...
    "seeds.global_seed or simulation.random_seed"));
runnerProfile = lower(string(localRequireNested(s, "scenario.runner_profile", "scenario.runner_profile")));
if runnerProfile == "system_level_lls"
    cfg.run.mode = "system";
else
    cfg.run.mode = "link";
end
cfg.run.module = "run_6g_phy_lls_single";
cfg.run.resultsRoot = "results";
cfg.run.runTag = "";
cfg.run.shortRun = false;
runTiming = localResolveRunTiming(s);
cfg.run.numFrames = runTiming.NumFrames;
cfg.run.numTTI = runTiming.TotalSlots;
cfg.run.failFast = logical(s.logging.strict_validation);
cfg.run.verbose = logical(s.logging.echo_to_console);
cfg.run.noProxyTruthContract = true;
cfg.run.strictMode = logical(s.logging.strict_validation);
cfg.run.deterministicMode = logical(s.simulation.deterministic_mode);
cfg.run.honestyMode = char(string(localGetNested(s, "scenario.honesty_mode", "strict")));
cfg.run.unsupportedOutputPolicy = char(string(localGetNested(s, ...
    "scenario.unsupported_output_policy", "show_unavailable_with_reason")));
cfg.run.provenanceLogging = logical(localGetNested(s, "scenario.provenance_logging", true));
if isfield(s, "seeds")
    cfg.run.seedCatalog = s.seeds;
end
cfg.run.numWorkers = max(0, round(double(localRequireNested(s, "run_control.num_workers", "run_control.num_workers"))));
cfg.run.parallelRequestedWorkers = double(cfg.run.numWorkers);
cfg.run.useParallel = logical(cfg.run.numWorkers > 1);
cfg.run.parallelPoolKind = char(lower(strtrim(string(localGetNested(s, "run_control.parallel_pool_kind", "auto")))));
cfg.run.parallelPoolIdleTimeoutMinutes = max(1, double(localGetNested(s, ...
    "run_control.parallel_pool_idle_timeout_minutes", 1440)));
cfg.run.batchSizeLinks = max(1, round(double(localRequireNested(s, "run_control.batch_size_links", "run_control.batch_size_links"))));
cfg.run.studyMode = char(string(localRequireNested(s, "run_control.study_mode", "run_control.study_mode")));
cfg.run.simulationMode = char(string(localRequireNested(s, "run_control.simulation_mode", "run_control.simulation_mode")));
cfg.run.runProfile = char(string(localRequireNested(s, "run_control.run_profile", "run_control.run_profile")));
cfg.run.executionMode = char(localResolveBrowserExecutionMode(s));
cfg.run.warmupTime_ms = runTiming.WarmupTime_ms;
cfg.run.measurementTime_ms = runTiming.MeasurementTime_ms;
cfg.run.totalTime_ms = runTiming.TotalTime_ms;
cfg.run.totalSlots = runTiming.TotalSlots;
cfg.run.warmupSlots = runTiming.WarmupSlots;
cfg.run.measurementSlots = runTiming.MeasurementSlots;
cfg.run.checkpointEverySlots = runTiming.CheckpointEverySlots;
cfg.run.snapshotEverySlots = runTiming.SnapshotEverySlots;
cfg.run.logEverySlots = runTiming.LogEverySlots;
cfg.run.saveIntermediateArtifacts = runTiming.SaveIntermediateArtifacts;
cfg.run.deterministicReplay = runTiming.DeterministicReplay;

cfg.outputs.saveCSV = logical(s.output.save_csv);
cfg.outputs.saveMAT = logical(s.output.save_mat);
cfg.outputs.saveFigures = logical(s.output.save_figures);
cfg.outputs.saveFIG = false;
cfg.outputs.savePNG = logical(s.output.save_png);
cfg.outputs.plotVisible = false;
cfg.outputs.livePublishFrameInterval = double(localGetNested(s, "output.live_publish_frame_interval", 1));
cfg.outputs.liveHeavyRefreshFrameInterval = double(localGetNested(s, "output.live_heavy_refresh_interval_frames", 4));
cfg.outputs.storageBackend = char(string(localRequireNested(s, "output.backend", "output.backend")));
cfg.outputs.persistenceMode = char(string(localGetNested(s, "output.persistence_mode", ...
    localGetNested(s, "output_control.output_persistence_mode", ...
    localResolveOutputPersistenceMode(cfg.outputs.storageBackend)))));
cfg.outputs.persistenceEffectiveMode = char(string(localGetNested(s, "output.persistence_effective_mode", cfg.outputs.persistenceMode)));
cfg.outputs.persistToDatabase = logical(localGetNested(s, "output.persist_to_database", lower(string(cfg.outputs.storageBackend)) == "mysql_web"));
cfg.outputs.persistToResultsFolder = logical(localGetNested(s, "output.persist_to_results_folder", true));
cfg.outputs.persistenceFallbackReason = char(string(localGetNested(s, "output.persistence_fallback_reason", "")));
cfg.outputs.resultsRoot = char(string(localGetNested(s, "output.results_root", "results")));
cfg.outputs.databaseHost = char(string(localResolveDatabaseField(s, "output.database_host", cfg.outputs.storageBackend)));
cfg.outputs.databasePort = double(localResolveDatabaseField(s, "output.database_port", cfg.outputs.storageBackend));
cfg.outputs.databaseSchema = char(string(localResolveDatabaseField(s, "output.database_schema", cfg.outputs.storageBackend)));

[profileName, propagationScenario] = localResolveScenarioSemantics(s);
cfg.scenario.id = char(string(s.meta.scenario_id));
cfg.scenario.name = char(profileName);
cfg.scenario.profileName = char(profileName);
cfg.run.scenario = char(propagationScenario);
cfg.scenario.bs.nTxAnt = double(s.mimo.n_tx_ant);
cfg.scenario.bs.txPower_dBm = double(s.energy_efficiency.tx_power_dbm);
cfg.scenario.ue.nRxAnt = double(s.mimo.n_rx_ant);
cfg.scenario.ue.nTxAnt = double(s.mimo.n_rx_ant);
cfg.scenario.ue.noiseFigure_dB = double(localResolveUENoiseFigure_dB(s));

ueCount = max(1, round(double(localRequireFirstNested(s, ...
    ["users.n_users","deployment_topology.num_ues"], ...
    "users.n_users or deployment_topology.num_ues"))));
cfg.scenario.ue.nUE = ueCount;
cfg.scenario.nUE = ueCount;
indoorFraction = double(localGetNested(s, "deployment_topology.indoor_ue_fraction", ...
    localGetNested(s, "topology.indoor_ue_fraction", ...
    localGetNested(s, "scenario.ue.indoorFraction", NaN))));
if isfinite(indoorFraction)
    indoorFraction = min(max(indoorFraction, 0), 1);
    cfg.scenario.ue.indoorFraction = indoorFraction;
    cfg = sixgr.util.structSet(cfg, "scenario.ue.distribution.indoorFraction", indoorFraction);
end
minInterUEDistance_m = localResolveFirstFiniteNumeric(s, ...
    ["deployment_topology.min_inter_ue_distance_m", ...
     "users.min_inter_ue_distance_m", ...
     "scenario.ue.min_inter_ue_distance_m"], NaN);
if isfinite(minInterUEDistance_m) && minInterUEDistance_m > 0
    cfg = sixgr.util.structSet(cfg, "scenario.ue.minInterUEDistance_m", double(minInterUEDistance_m));
    cfg = sixgr.util.structSet(cfg, "scenario.ue.distribution.minInterUEDistance_m", double(minInterUEDistance_m));
end

mobilitySpeedKmh = double(localRequireFirstNested(s, ...
    ["mobility.ue_speed_kmh","channels.mobility_kmph"], ...
    "mobility.ue_speed_kmh or channels.mobility_kmph"));
cfg.scenario.mobility.enable = mobilitySpeedKmh > 0;
cfg.scenario.mobility.speed_kmh = [mobilitySpeedKmh mobilitySpeedKmh];
cfg.scenario.mobility.speed_mps = [mobilitySpeedKmh mobilitySpeedKmh] ./ 3.6;
cfg.scenario.mobility.model = char(localResolveMobilityModel(s));
cfg.scenario.mobility.updatePeriod_s = double(localGetNested(s, "mobility.update_period_s", ...
    localGetNested(s, "mobility.updatePeriod_s", NaN)));
cfg.scenario.mobility.zigzagSegmentDuration_s = double(localGetNested(s, "mobility.zigzag_segment_duration_s", ...
    localGetNested(s, "mobility.zigzagSegmentDuration_s", NaN)));
cfg.scenario.mobility.segmentDuration_s = double(localGetNested(s, "mobility.segment_duration_s", ...
    localGetNested(s, "mobility.segmentDuration_s", cfg.scenario.mobility.zigzagSegmentDuration_s)));
cfg.scenario.mobility.zigzagTurnAngle_deg = double(localGetNested(s, "mobility.zigzag_turn_angle_deg", ...
    localGetNested(s, "mobility.zigzagTurnAngle_deg", NaN)));
cfg.scenario.mobility.turnAngle_deg = double(localGetNested(s, "mobility.turn_angle_deg", ...
    localGetNested(s, "mobility.turnAngle_deg", cfg.scenario.mobility.zigzagTurnAngle_deg)));
localAssertFiniteConfigValue(cfg.scenario.mobility.updatePeriod_s, "mobility.update_period_s");
localAssertFiniteConfigValue(cfg.scenario.mobility.zigzagSegmentDuration_s, "mobility.zigzag_segment_duration_s");
localAssertFiniteConfigValue(cfg.scenario.mobility.zigzagTurnAngle_deg, "mobility.zigzag_turn_angle_deg");
cfg = localApplyDeploymentTopology(cfg, s);

cfg.channel.fc_Hz = double(s.frequency.center_frequency_hz);
cfg.phy.fc_Hz = double(s.frequency.center_frequency_hz);
cfg.channel.bandwidth_Hz = double(s.frequency.bandwidth_hz);
cfg.channel.subcarrierSpacing_kHz = double(s.frame.scs_khz);
cfg.phy.channelBandwidth_MHz = double(s.frequency.bandwidth_hz) / 1e6;
cfg.phy.frequencyRange = char(upper(string(localGetNested(s, "frequency.range_name", ...
    localGetNested(s, "global_radio_scope.frequency_range_label", "")))));
cfg.frequency.rangeName = cfg.phy.frequencyRange;
cfg.frequency.centerFrequencyHz = double(s.frequency.center_frequency_hz);
cfg.frequency.bandwidthHz = double(s.frequency.bandwidth_hz);
cfg.channel.nTxAnt = double(s.mimo.n_tx_ant);
cfg.channel.nRxAnt = double(s.mimo.n_rx_ant);
cfg.channel.snr_dB = double(s.simulation.snr_db);
cfg = sixgr.util.structSet(cfg, "run.noiseOperatingMode", char(localResolveNoiseOperatingMode(s)));
dopplerSourceMode = localResolveDopplerSourceMode(s);
resolvedDopplerHz = localResolveChannelDopplerHz(s, mobilitySpeedKmh, dopplerSourceMode);
cfg.channel.dopplerSourceMode = char(dopplerSourceMode);
cfg.channel.dopplerConfigured_Hz = double(localRequireNested(s, "channels.doppler_hz", "channels.doppler_hz"));
cfg.channel.doppler_Hz = double(resolvedDopplerHz);
cfg.channel.dopplerHz = double(resolvedDopplerHz);
cfg.channel.awgnOnly = upper(string(s.channels.model_type)) == "AWGN";
cfg.channel.propagationScenario = char(propagationScenario);
cfg.channel.pathloss.model = char(string(s.channels.pathloss_model));
cfg.channel.pathlossModel = char(string(s.channels.pathloss_model));
cfg.channel.complianceMode = char(string(sixgr.util.structGet(s, "channels.compliance_mode", ...
    localTernary(logical(sixgr.util.structGet(s, "run_control.strict_mode", false)), "strict_38901", "approximate_38901_plus"))));
cfg.channel.shadowFadingStd_dB = double(s.channels.shadow_fading_std_db);
cfg.channel.shadowSigma_dB = double(s.channels.shadow_fading_std_db);
cfg.channel.receiverNoiseFigure_dB = double(cfg.scenario.ue.noiseFigure_dB);
cfg.channel.fading.enable = ~cfg.channel.awgnOnly;
cfg.channel.fading.maxDoppler_Hz = double(resolvedDopplerHz);
cfg.channel.fading.delaySpread_s = double(s.channels.delay_spread_ns) * 1e-9;
cfg = sixgr.util.structSet(cfg, "channel.pathlossEnabled", logical(s.channels.pathloss_enabled));
cfg = sixgr.util.structSet(cfg, "channel.shadowFadingEnabled", logical(s.channels.shadow_fading_enabled));
cfg = sixgr.util.structSet(cfg, "channel.spatialConsistencyEnabled", logical(s.channels.spatial_consistency_enabled));
cfg = sixgr.util.structSet(cfg, "channel.losEnabled", logical(s.channels.los_enabled));

channelModel = upper(string(s.channels.model_type));
profile = upper(string(s.channels.profile));
switch channelModel
    case "AWGN"
        cfg.channel.model = "AWGN";
        cfg.channel.delayProfile = "";
        cfg.channel.tdlProfile = "";
        cfg.channel.cdlProfile = "";
        cfg.channel.fading.model = "";
        cfg.channel.fading.profile = "";
    case "TDL"
        cfg.channel.model = "TDL";
        cfg.channel.tdlProfile = char(profile);
        cfg.channel.delayProfile = char(profile);
        cfg.channel.fading.model = "TDL";
        cfg.channel.fading.profile = char(profile);
    case "CDL"
        cfg.channel.model = "CDL";
        cfg.channel.cdlProfile = char(profile);
        cfg.channel.delayProfile = char(profile);
        cfg.channel.fading.model = "CDL";
        cfg.channel.fading.profile = char(profile);
    otherwise
        error("sixgr:lls6g:config:UnsupportedChannelModel", ...
            "Unsupported channels.model_type '%s'.", channelModel);
end

cfg.phy.carrier.SubcarrierSpacing = double(s.frame.scs_khz);
cfg.phy.carrier.SubcarrierSpacing_kHz = double(s.frame.scs_khz);
cfg.phy.carrier.CyclicPrefix = char(string(s.frame.cp_type));
cfg.phy.carrier.NSizeGrid = double(s.frequency.n_size_grid);
scsKHz = double(cfg.phy.carrier.SubcarrierSpacing_kHz);
if isfinite(scsKHz) && scsKHz > 0
    numerologyMu = log2(scsKHz / 15);
else
    numerologyMu = NaN;
end
if isfinite(numerologyMu)
    numerologyMu = round(double(numerologyMu));
end
slotsPerFrame = NaN;
slotDuration_ms = NaN;
if isfinite(numerologyMu)
    slotsPerFrame = 10 * 2^double(numerologyMu);
    slotDuration_ms = 1 / 2^double(numerologyMu);
end
cfg = sixgr.util.structSet(cfg, "phy.numerology.mu", double(numerologyMu));
cfg = sixgr.util.structSet(cfg, "phy.numerology.scs_kHz", double(scsKHz));
cfg = sixgr.util.structSet(cfg, "phy.numerology.slotsPerFrame", double(slotsPerFrame));
cfg = sixgr.util.structSet(cfg, "phy.numerology.slotDuration_ms", double(slotDuration_ms));
cfg = sixgr.util.structSet(cfg, "phy.numerology.symbolsPerSlot", 14);
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridNumRBs", double(cfg.phy.carrier.NSizeGrid));
cfg = sixgr.util.structSet(cfg, "phy.numerology.configuredGridNumRBs", double(s.frequency.n_size_grid));
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridSource", "configured_n_size_grid");
cfg = sixgr.util.structSet(cfg, "phy.numerology.numerologySource", "carrier_subcarrier_spacing_khz");
cfg = sixgr.util.structSet(cfg, "phy.numerology.timingInterpretationSource", "nr_mu_from_scs");
cfg.phy.duplex.mode = upper(char(string(s.frequency.duplex_mode)));
cfg.phy.duplex.tddPattern = char(string(s.frame.tdd_pattern));
cfg = sixgr.util.structSet(cfg, "phy.duplex.specialSlot.numDLSymbols", ...
    double(localGetNested(s, "frame.special_slot_downlink_symbols", ...
    localGetNested(s, "frame_timing.special_slot_downlink_symbols", 7))));
cfg = sixgr.util.structSet(cfg, "phy.duplex.specialSlot.numGuardSymbols", ...
    double(localGetNested(s, "frame.ul_dl_guard_symbols", ...
    localGetNested(s, "frame_timing.ul_dl_guard_symbols", 0))));
cfg = sixgr.util.structSet(cfg, "phy.duplex.specialSlot.numULSymbols", ...
    double(localGetNested(s, "frame.special_slot_uplink_symbols", ...
    localGetNested(s, "frame_timing.special_slot_uplink_symbols", 7))));
cfg.phy.waveform.dl = char(string(s.waveform.dl_waveform));
cfg.phy.waveform.ul = char(string(s.waveform.ul_waveform));
cfg = sixgr.util.structSet(cfg, "phy.waveform.windowingEnabled", logical(s.waveform.windowing_enabled));
cfg = sixgr.util.structSet(cfg, "phy.waveform.experimentalDLDftsOfdmEnabled", ...
    logical(s.waveform.experimental_dl_dfts_ofdm_enabled));

cfg.phy.ssb.enable = logical(s.reference_signals.ssb_enabled);
cfg = sixgr.util.structSet(cfg, "phy.ssb.blockPattern", ...
    localDefaultSSBBlockPattern(double(s.frequency.center_frequency_hz), double(s.frame.scs_khz)));
cfg = sixgr.util.structSet(cfg, "phy.ssb.Lmax", ...
    localDefaultSSBLmax(double(s.frequency.center_frequency_hz), double(s.frame.scs_khz)));
cfg = sixgr.util.structSet(cfg, "phy.ssb.nBeams", double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", 8)));
cfg.phy.pbch.enable = logical(s.reference_signals.pbch_enabled);
cfg.phy.mib.enable = logical(s.reference_signals.pbch_enabled);
cfg.phy.sib1.enable = logical(s.reference_signals.pbch_enabled);

cfg.phy.pdcch.enable = logical(s.control.pdcch_enabled);
cfg.phy.pdcch.searchSpaceType = char(string(s.control.search_space_type));
cfg.phy.pdcch.aggregationLevels = double(s.control.aggregation_levels);
cfg.phy.pdcch.aggregationLevel = double(localResolveDefaultPDCCHAggregationLevel(s.control.aggregation_levels));
cfg.phy.pdcch.candidateAggregationLevels = double(localGetNested(s, "control.candidate_aggregation_levels", cfg.phy.pdcch.aggregationLevels));
cfg.phy.pdcch.aggregationSelectionPolicy = char(string(localGetNested(s, "control.aggregation_selection_policy", "snr_threshold")));
cfg.phy.pdcch.schedulerAggregationLevel = double(localGetNested(s, "control.scheduler_aggregation_level", NaN));
cfg.phy.pdcch.dciFormat = char(string(localFirstValue(s.control.dci_formats)));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.blindDecodeCandidates", double(s.control.blind_decode_candidates));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.duration", double(s.control.coreset_duration));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.frequencyResources", double(s.control.coreset_frequency_resources));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.numCandidates", double(s.control.search_space_num_candidates));

cfg.ctrl6gr.enable = logical(localGetNested(s, "control.pdcch6gr.enable_6gr_pdcch", false));
cfg.ctrl6gr.RNTI = double(localGetNested(s, "control.pdcch6gr.rnti", 4660));
cfg.ctrl6gr.NumSlots = double(localGetNested(s, "control.pdcch6gr.num_slots", max(1, cfg.run.totalSlots)));
cfg.ctrl6gr.NTx = double(localGetNested(s, "control.pdcch6gr.n_tx", 1));
cfg.ctrl6gr.NRx = double(localGetNested(s, "control.pdcch6gr.n_rx", max(1, cfg.channel.nRxAnt)));
cfg.ctrl6gr.ChannelModel = char(string(localGetNested(s, "control.pdcch6gr.channel_model", cfg.channel.model)));
cfg.ctrl6gr.DelaySpread = double(localGetNested(s, "control.pdcch6gr.delay_spread_s", cfg.channel.fading.delaySpread_s));
cfg.ctrl6gr.DopplerHz = double(localGetNested(s, "control.pdcch6gr.doppler_hz", cfg.channel.doppler_Hz));
cfg.ctrl6gr.SNRdB = double(localGetNested(s, "control.pdcch6gr.snr_db", cfg.channel.snr_dB));
cfg.ctrl6gr.NoiseVarianceMode = char(string(localGetNested(s, "control.pdcch6gr.noise_variance_mode", "from_snr_db")));
cfg.ctrl6gr.ChannelEstimationMode = char(string(localGetNested(s, "control.pdcch6gr.channel_estimation_mode", "realistic")));
cfg.ctrl6gr.EqualizerType = char(string(localGetNested(s, "control.pdcch6gr.equalizer_type", "MMSE")));
cfg.ctrl6gr.BlindDetectionEnabled = logical(localGetNested(s, "control.pdcch6gr.blind_detection_enabled", true));
cfg.ctrl6gr.MonitoringPeriodicitySlots = double(localGetNested(s, "control.pdcch6gr.monitoring_periodicity_slots", 1));
cfg.ctrl6gr.EnableCSS = logical(localGetNested(s, "control.pdcch6gr.enable_css", true));
cfg.ctrl6gr.EnableUSS = logical(localGetNested(s, "control.pdcch6gr.enable_uss", true));
cfg.ctrl6gr.EnableMRSS = logical(localGetNested(s, "control.pdcch6gr.enable_mrss", false));
cfg.ctrl6gr.EnableRepetition = logical(localGetNested(s, "control.pdcch6gr.enable_repetition", false));
cfg.ctrl6gr.RepetitionMode = char(string(localGetNested(s, "control.pdcch6gr.repetition_mode", "none")));
cfg.ctrl6gr.RepetitionCount = double(localGetNested(s, "control.pdcch6gr.repetition_count", 1));
cfg.ctrl6gr.EnableTransmitDiversity = logical(localGetNested(s, "control.pdcch6gr.enable_transmit_diversity", false));
cfg.ctrl6gr.DiversityMode = char(string(localGetNested(s, "control.pdcch6gr.diversity_mode", "single_port_baseline")));
cfg.ctrl6gr.PrecoderGranularity = char(string(localGetNested(s, "control.pdcch6gr.precoder_granularity", "none")));
cfg.ctrl6gr.OutputDir = char(string(runFolder));
cfg.ctrl6gr.Seed = double(cfg.run.seed);
cfg.ctrl6gr.PayloadLengthBits = double(localGetNested(s, "control.pdcch6gr.payload_length_bits", ...
    localGetNested(s, "control.pdcch_payload_bits", 64)));
cfg.ctrl6gr.Modulation = char(string(localGetNested(s, "control.pdcch6gr.modulation", "QPSK")));
cfg.ctrl6gr.CRCPolynomial = char(string(localGetNested(s, "control.pdcch6gr.crc_polynomial", "24C")));
cfg.ctrl6gr.CRCScramblingEnabled = logical(localGetNested(s, "control.pdcch6gr.crc_scrambling_enabled", true));
cfg.ctrl6gr.PayloadScramblingEnabled = logical(localGetNested(s, "control.pdcch6gr.payload_scrambling_enabled", true));
cfg.ctrl6gr.PayloadSequenceInit = double(localGetNested(s, "control.pdcch6gr.payload_sequence_init", cfg.phy.carrier.NCellID));
cfg.ctrl6gr.WaveformMode = char(string(localGetNested(s, "control.pdcch6gr.waveform_mode", "full_ofdm")));
cfg.ctrl6gr.RepetitionCombiningMode = char(string(localGetNested(s, "control.pdcch6gr.repetition_combining_mode", "coherent")));
cfg.ctrl6gr.CORESET = localGetNested(s, "control.pdcch6gr.coreset", struct());
cfg.ctrl6gr.SearchSpaces = localGetNested(s, "control.pdcch6gr.search_spaces", struct([]));
cfg.ctrl6gr.StudyAggregationLevels = double(localGetNested(s, "control.pdcch6gr.study.aggregation_levels", [1 2 4 8 16]));
cfg.ctrl6gr.StudyCORESETDurations = double(localGetNested(s, "control.pdcch6gr.study.coreset_durations", [1 2 3]));
cfg.ctrl6gr.StudyMappingTypes = cellstr(string(localGetNested(s, "control.pdcch6gr.study.mapping_types", ["noninterleaved","interleaved"])));
cfg.ctrl6gr.StudyFrequencyAllocationModes = cellstr(string(localGetNested(s, "control.pdcch6gr.study.frequency_allocation_modes", ["contiguous","noncontiguous"])));
cfg.ctrl6gr.StudyRepetitionModes = cellstr(string(localGetNested(s, "control.pdcch6gr.study.repetition_modes", ["none","intra_slot","inter_slot"])));
cfg.ctrl6gr.StudySNRdB = double(localGetNested(s, "control.pdcch6gr.study.snr_db", cfg.ctrl6gr.SNRdB));
cfg.ctrl6gr.StudyChannelModels = cellstr(string(localGetNested(s, "control.pdcch6gr.study.channel_models", [string(cfg.ctrl6gr.ChannelModel)])));
cfg.ctrl6gr.StudySearchSpaceTypes = cellstr(string(localGetNested(s, "control.pdcch6gr.study.search_space_types", ["CSS","USS"])));
cfg.ctrl6gr.StudyDMRSVariants = cellstr(string(localGetNested(s, "control.pdcch6gr.study.dmrs_variants", ["single_port_density_3_per_rb"])));
cfg.ctrl6gr.StudyCRCScrambling = double(localGetNested(s, "control.pdcch6gr.study.crc_scrambling", double(cfg.ctrl6gr.CRCScramblingEnabled)));
cfg.ctrl6gr.StudyPayloadScrambling = double(localGetNested(s, "control.pdcch6gr.study.payload_scrambling", double(cfg.ctrl6gr.PayloadScramblingEnabled)));
cfg.ctrl6gr.StudyREGBundleSizes = double(localGetNested(s, "control.pdcch6gr.study.reg_bundle_sizes", localGetNested(s, "control.pdcch6gr.coreset.reg_bundle_size", 2)));
cfg.ctrl6gr.StudyNumREGPerCCE = double(localGetNested(s, "control.pdcch6gr.study.num_reg_per_cce", localGetNested(s, "control.pdcch6gr.coreset.num_reg_per_cce", 6)));
cfg.ctrl6gr.StudyMRSSModes = cellstr(string(localGetNested(s, "control.pdcch6gr.study.mrss_modes", ["exclusive_6gr"])));

cfg.pdsch6gr.enable = logical(localGetNested(s, "pdsch6gr.enabled", false));
cfg.pdsch6gr.RNTI = double(localGetNested(s, "pdsch6gr.rnti", 4660));
cfg.pdsch6gr.FrameNumber = double(localGetNested(s, "pdsch6gr.frame_number", 0));
cfg.pdsch6gr.SlotNumber = double(localGetNested(s, "pdsch6gr.slot_number", 0));
cfg.pdsch6gr.Numerology = double(localGetNested(s, "pdsch6gr.numerology", cfg.phy.numerology.mu));
cfg.pdsch6gr.CarrierFrequencyHz = double(localGetNested(s, "pdsch6gr.carrier_frequency_hz", cfg.phy.fc_Hz));
cfg.pdsch6gr.DuplexMode = char(string(localGetNested(s, "pdsch6gr.duplex_mode", cfg.phy.duplex.mode)));
cfg.pdsch6gr.NSizeGrid = double(localGetNested(s, "pdsch6gr.n_size_grid", cfg.phy.carrier.NSizeGrid));
cfg.pdsch6gr.ChannelBandwidthMHz = double(localGetNested(s, "pdsch6gr.channel_bandwidth_mhz", double(s.frequency.bandwidth_hz) / 1e6));
cfg.pdsch6gr.NTx = double(localGetNested(s, "pdsch6gr.n_tx", sixgr.util.structGet(cfg, "channel.nTxAnt", 1)));
cfg.pdsch6gr.NRx = double(localGetNested(s, "pdsch6gr.n_rx", sixgr.util.structGet(cfg, "channel.nRxAnt", 1)));
cfg.pdsch6gr.NumLayers = double(localGetNested(s, "pdsch6gr.num_layers", cfg.phy.pdsch.nLayers));
cfg.pdsch6gr.NumCodewords = double(localGetNested(s, "pdsch6gr.num_codewords", 1));
cfg.pdsch6gr.ModulationPerCodeword = cellstr(string(localGetNested(s, "pdsch6gr.modulation_per_codeword", {char(string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "16QAM")))})));
cfg.pdsch6gr.TargetCodeRatePerCodeword = double(localGetNested(s, "pdsch6gr.target_code_rate_per_codeword", sixgr.util.structGet(cfg, "phy.pdsch.codeRate", 0.4785)));
cfg.pdsch6gr.MCSMode = char(string(localGetNested(s, "pdsch6gr.mcs_mode", "fixed")));
cfg.pdsch6gr.FixedMCS = double(localGetNested(s, "pdsch6gr.fixed_mcs", sixgr.util.structGet(cfg, "phy.pdsch.configuredMCSIndex", 10)));
cfg.pdsch6gr.LinkAdaptationMode = char(string(localGetNested(s, "pdsch6gr.link_adaptation_mode", "actual_bler_based")));
cfg.pdsch6gr.HARQEnabled = logical(localGetNested(s, "pdsch6gr.harq_enabled", true));
cfg.pdsch6gr.HARQProcessCount = double(localGetNested(s, "pdsch6gr.harq_process_count", 4));
cfg.pdsch6gr.MaxHARQTx = double(localGetNested(s, "pdsch6gr.max_harq_tx", 1));
cfg.pdsch6gr.EnableCrossSlotPDSCH = logical(localGetNested(s, "pdsch6gr.enable_cross_slot_pdsch", false));
cfg.pdsch6gr.CrossSlotMode = char(string(localGetNested(s, "pdsch6gr.cross_slot_mode", "disabled")));
cfg.pdsch6gr.EnablePDSCHRepetition = logical(localGetNested(s, "pdsch6gr.enable_pdsch_repetition", false));
cfg.pdsch6gr.RepetitionMode = char(string(localGetNested(s, "pdsch6gr.repetition_mode", "none")));
cfg.pdsch6gr.RepetitionCount = double(localGetNested(s, "pdsch6gr.repetition_count", 1));
cfg.pdsch6gr.EnablePTRS = logical(localGetNested(s, "pdsch6gr.enable_ptrs", false));
cfg.pdsch6gr.PTRSBandPolicy = char(string(localGetNested(s, "pdsch6gr.ptrs_band_policy", "disabled")));
cfg.pdsch6gr.ChannelEstimationMode = char(string(localGetNested(s, "pdsch6gr.channel_estimation_mode", "realistic")));
cfg.pdsch6gr.ParameterEstimationMode = char(string(localGetNested(s, "pdsch6gr.parameter_estimation_mode", "practical")));
cfg.pdsch6gr.ReceiverType = char(string(localGetNested(s, "pdsch6gr.receiver_type", "MMSE_IRC")));
muMimoEnabled = logical(localGetNested(s, "mimo.mu_mimo_enable", ...
    localGetNested(s, "mimo.mu_mimo_enabled", ...
    localGetNested(s, "mimo_and_beam_management.mu_mimo_enabled", ...
    localGetNested(s, "system.scheduler.muMimoEnabled", ...
    localGetNested(s, "pdsch6gr.enable_mumimo_study", localScenarioHasTag(s, "mu-mimo")))))));
ulMuMimoEnabled = logical(localGetNested(s, "mimo.ul_mu_mimo_enable", ...
    localGetNested(s, "system.scheduler.ulMuMimoEnabled", false)));
muMimoMaxUsers = max(2, min(4, round(double(localGetNested(s, "mimo.mu_mimo_max_users_per_prb", ...
    localGetNested(s, "system.scheduler.muMimoMaxUsersPerPRB", 2))))));
cfg.pdsch6gr.EnableMUMIMOStudy = logical(localGetNested(s, "pdsch6gr.enable_mumimo_study", false)) || muMimoEnabled;
cfg = sixgr.util.structSet(cfg, "mimo.mu_mimo_enable", muMimoEnabled);
cfg = sixgr.util.structSet(cfg, "phy.mimo.muMimoEnabled", muMimoEnabled);
cfg = sixgr.util.structSet(cfg, "phy.mimo.ulMuMimoEnabled", ulMuMimoEnabled);
cfg = sixgr.util.structSet(cfg, "phy.mimo.muMimoMaxUsersPerPRB", muMimoMaxUsers);
cfg = sixgr.util.structSet(cfg, "mac.scheduler.muMimoEnabled", muMimoEnabled);
cfg = sixgr.util.structSet(cfg, "mac.scheduler.ulMuMimoEnabled", ulMuMimoEnabled);
cfg = sixgr.util.structSet(cfg, "mac.scheduler.muMimoMaxUsersPerPRB", muMimoMaxUsers);
cfg.pdsch6gr.EnableMRSS = logical(localGetNested(s, "pdsch6gr.enable_mrss", false));
cfg.pdsch6gr.EnablePhaseNoise = logical(localGetNested(s, "pdsch6gr.enable_phase_noise", false));
cfg.pdsch6gr.EnableWidebandUncalibratedPhaseErrors = logical(localGetNested(s, "pdsch6gr.enable_wideband_uncalibrated_phase_errors", false));
cfg.pdsch6gr.ChannelModel = char(string(localGetNested(s, "pdsch6gr.channel_model", cfg.channel.model)));
cfg.pdsch6gr.DelaySpread_s = double(localGetNested(s, "pdsch6gr.delay_spread_s", cfg.channel.fading.delaySpread_s));
cfg.pdsch6gr.SpeedKmh = double(localGetNested(s, "pdsch6gr.speed_kmh", 3));
cfg.pdsch6gr.SNRdB = double(localGetNested(s, "pdsch6gr.snr_db", cfg.channel.snr_dB));
cfg.pdsch6gr.FDRAType = char(string(localGetNested(s, "pdsch6gr.fdra_type", "type1_riv")));
cfg.pdsch6gr.RBBitmap = double(localGetNested(s, "pdsch6gr.rb_bitmap", []));
cfg.pdsch6gr.RIV = double(localGetNested(s, "pdsch6gr.riv", 0));
cfg.pdsch6gr.NumRB = double(localGetNested(s, "pdsch6gr.num_rb", cfg.phy.carrier.NSizeGrid));
cfg.pdsch6gr.RBStart = double(localGetNested(s, "pdsch6gr.rb_start", 0));
cfg.pdsch6gr.GranularityRB = double(localGetNested(s, "pdsch6gr.granularity_rb", 1));
cfg.pdsch6gr.StartSymbol = double(localGetNested(s, "pdsch6gr.start_symbol", 2));
cfg.pdsch6gr.NumSymbols = double(localGetNested(s, "pdsch6gr.num_symbols", 10));
cfg.pdsch6gr.DMRSConfigType = double(localGetNested(s, "pdsch6gr.dmrs_config_type", 1));
cfg.pdsch6gr.DMRSAdditionalPosition = double(localGetNested(s, "pdsch6gr.dmrs_additional_position", 1));
cfg.pdsch6gr.DMRSNumPorts = double(localGetNested(s, "pdsch6gr.dmrs_num_ports", 1));
cfg.pdsch6gr.DMRSPortSet = double(localGetNested(s, "pdsch6gr.dmrs_port_set", 0));
cfg.pdsch6gr.PTRSTimeDensity = double(localGetNested(s, "pdsch6gr.ptrs_time_density", 2));
cfg.pdsch6gr.PTRSFrequencyDensity = double(localGetNested(s, "pdsch6gr.ptrs_frequency_density", 2));
cfg.pdsch6gr.PTRSREOffset = char(string(localGetNested(s, "pdsch6gr.ptrs_re_offset", "00")));
cfg.pdsch6gr.QueueBits = double(localGetNested(s, "pdsch6gr.queue_bits", 1000000));
cfg.pdsch6gr.Seed = double(localGetNested(s, "pdsch6gr.seed", cfg.run.seed));
cfg.pdsch6gr.OutputDir = char(string(runFolder));
cfg.pdsch6gr.StudySNRdB = double(localGetNested(s, "pdsch6gr.study_snr_db", cfg.pdsch6gr.SNRdB));
cfg.pdsch6gr.StudyFDRATypes = cellstr(string(localGetNested(s, "pdsch6gr.study_fdra_types", {cfg.pdsch6gr.FDRAType})));
cfg.pdsch6gr.StudyStartSymbols = double(localGetNested(s, "pdsch6gr.study_start_symbols", cfg.pdsch6gr.StartSymbol));
cfg.pdsch6gr.StudyNumSymbols = double(localGetNested(s, "pdsch6gr.study_num_symbols", cfg.pdsch6gr.NumSymbols));
cfg.pdsch6gr.StudyChannelModels = cellstr(string(localGetNested(s, "pdsch6gr.study_channel_models", {cfg.pdsch6gr.ChannelModel})));
cfg.pdsch6gr.StudyDelaySpread_ns = double(localGetNested(s, "pdsch6gr.study_delay_spread_ns", cfg.pdsch6gr.DelaySpread_s * 1e9));
cfg.pdsch6gr.StudySpeedKmh = double(localGetNested(s, "pdsch6gr.study_speed_kmh", cfg.pdsch6gr.SpeedKmh));
cfg.pdsch6gr.StudyRanks = double(localGetNested(s, "pdsch6gr.study_ranks", cfg.pdsch6gr.NumLayers));
cfg.pdsch6gr.StudyRepetitionModes = cellstr(string(localGetNested(s, "pdsch6gr.study_repetition_modes", {cfg.pdsch6gr.RepetitionMode})));
cfg.pdsch6gr.StudyPTRSModes = cellstr(string(localGetNested(s, "pdsch6gr.study_ptrs_modes", {localPdschPTRSMode(cfg.pdsch6gr.EnablePTRS)})));
cfg.pdsch6gr.StudyDMRSAdditionalPositions = double(localGetNested(s, "pdsch6gr.study_dmrs_additional_positions", cfg.pdsch6gr.DMRSAdditionalPosition));
cfg.pdsch6gr.StudyNumTrials = double(localGetNested(s, "pdsch6gr.study_num_trials", 1));

targetCases = lower(string(s.scenario.target_cases));
linkAdaptationMode = lower(string(localRequireNested(s, "link_adaptation.fixed_or_amc", "link_adaptation.fixed_or_amc")));
linkAdaptationUsesFixedMCS = ismember(linkAdaptationMode, ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"]);
explicitPDSCHMCSMode = lower(strtrim(string(localGetNested(s, "pdsch6gr.mcs_mode", ""))));
if ~linkAdaptationUsesFixedMCS && (strlength(explicitPDSCHMCSMode) == 0 || ismember(explicitPDSCHMCSMode, ["fixed","fixed_mcs","configured_fixed"]))
    cfg.pdsch6gr.MCSMode = 'amc';
elseif linkAdaptationUsesFixedMCS && (strlength(explicitPDSCHMCSMode) == 0 || explicitPDSCHMCSMode == "amc")
    cfg.pdsch6gr.MCSMode = 'fixed';
end
cfg.pdsch6gr.FixedMCSActive = logical(linkAdaptationUsesFixedMCS);
dlConfiguredMCSIndex = double(s.modulation.dl_mcs_index);
ulConfiguredMCSIndex = double(s.modulation.ul_mcs_index);
cfg.phy.pdsch.enable = any(ismember(targetCases, localCatalogStringList(catalog.value_maps.target_case_groups.pdsch_enable)));
cfg.phy.pdsch.nLayers = double(s.mimo.n_layers);
cfg.phy.pdsch.enablePTRS = logical(s.reference_signals.ptrs_enabled);
cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = double(s.reference_signals.pdsch_dmrs_num_cdm_groups_without_data);
cfg.phy.pdsch.dmrs.typeApos = double(s.reference_signals.pdsch_dmrs_type_a_position);
cfg.phy.pdsch.dmrs.configType = double(s.reference_signals.pdsch_dmrs_config_type);
cfg.phy.pdsch.configuredMCSIndex = dlConfiguredMCSIndex;
cfg.phy.pdsch.mcsIndex = dlConfiguredMCSIndex;
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", char(string(s.modulation.mcs_table)));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.dmrs.nPorts", double(s.reference_signals.pdsch_dmrs_ports));

cfg.phy.csirs.enable = logical(s.reference_signals.csi_rs_enabled);
cfg.phy.csirs.nPorts = double(s.reference_signals.pdsch_dmrs_ports);
cfg = sixgr.util.structSet(cfg, "phy.csirs.numResources", ...
    double(localRequireFirstNested(s, ["deployment_topology.num_trps","mimo.trp_count"], ...
    "deployment_topology.num_trps or mimo.trp_count")));
csiMode = string(localRequireFirstNested(s, ...
    ["csi_acquisition_and_reporting.channel_state_information_mode", ...
    "reference_signals.channel_state_information_mode", ...
    "reference_signals.csi_feedback_mode"], ...
    "csi_acquisition_and_reporting.channel_state_information_mode or reference_signals.channel_state_information_mode"));
pmiCodebookMode = string(localRequireFirstNested(s, ...
    ["csi_acquisition_and_reporting.pmi_codebook_mode","reference_signals.pmi_codebook_mode"], ...
    "csi_acquisition_and_reporting.pmi_codebook_mode or reference_signals.pmi_codebook_mode"));
cqiPolicy = localRequireFirstNested(s, ...
    ["csi_acquisition_and_reporting.cqi_policy","reference_signals.cqi_reporting_enabled"], ...
    "csi_acquisition_and_reporting.cqi_policy or reference_signals.cqi_reporting_enabled");
pmiPolicy = localRequireFirstNested(s, ...
    ["csi_acquisition_and_reporting.pmi_policy","reference_signals.pmi_reporting_enabled"], ...
    "csi_acquisition_and_reporting.pmi_policy or reference_signals.pmi_reporting_enabled");
riPolicy = localRequireFirstNested(s, ...
    ["csi_acquisition_and_reporting.ri_policy","reference_signals.ri_reporting_enabled"], ...
    "csi_acquisition_and_reporting.ri_policy or reference_signals.ri_reporting_enabled");
criPolicy = localRequireFirstNested(s, ...
    ["csi_acquisition_and_reporting.cri_policy","reference_signals.cri_reporting_enabled"], ...
    "csi_acquisition_and_reporting.cri_policy or reference_signals.cri_reporting_enabled");
reportCQI = localPolicyFlag(cqiPolicy);
reportPMI = localPolicyFlag(pmiPolicy);
reportRI = localPolicyFlag(riPolicy);
reportCRI = localPolicyFlag(criPolicy);
reportCSI = logical(localRequireNested(s, "reference_signals.csi_reporting_enabled", "reference_signals.csi_reporting_enabled"));
reportPayloadMode = string(localRequireNested(s, "csi_acquisition_and_reporting.report_payload_mode", ...
    "csi_acquisition_and_reporting.report_payload_mode"));
crcAttachedMode = logical(localRequireNested(s, "csi_acquisition_and_reporting.crc_attached_mode", ...
    "csi_acquisition_and_reporting.crc_attached_mode"));
crcFreeMode = logical(localRequireNested(s, "csi_acquisition_and_reporting.crc_free_mode", ...
    "csi_acquisition_and_reporting.crc_free_mode"));
cfg.phy.csi.enable = logical(s.reference_signals.csi_rs_enabled) || reportCSI;
cfg.phy.csi.feedbackMode = char(csiMode);
cfg = sixgr.util.structSet(cfg, "phy.csi.channelStateInformationMode", char(csiMode));
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCSI", reportCSI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", reportCQI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMI", reportPMI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportRI", reportRI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCRI", reportCRI);
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiPolicy", char(localPolicyTokenString(cqiPolicy)));
cfg = sixgr.util.structSet(cfg, "phy.csi.pmiPolicy", char(localPolicyTokenString(pmiPolicy)));
cfg = sixgr.util.structSet(cfg, "phy.csi.riPolicy", char(localPolicyTokenString(riPolicy)));
cfg = sixgr.util.structSet(cfg, "phy.csi.criPolicy", char(localPolicyTokenString(criPolicy)));
cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", char(pmiCodebookMode));
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", char(string(s.mimo.codebook_type)));
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", char(localResolveCQITableToken(s)));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.cqiTable", char(localResolveCQITableToken(s)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.cqiTable", char(localResolveCQITableToken(s)));
sinrToCQIMode = lower(strtrim(string(localGetNested(s, "csi_acquisition_and_reporting.sinr_to_cqi_mode", ...
    localGetNested(s, "link_adaptation.sinr_to_cqi_mode", "")))));
if strlength(sinrToCQIMode) > 0
    cfg = sixgr.util.structSet(cfg, "phy.csi.sinrToCQIMode", char(sinrToCQIMode));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.sinrToCQIMode", char(sinrToCQIMode));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.sinrToCQIMode", char(sinrToCQIMode));
end
effectiveSINRMethod = lower(strtrim(string(localGetNested(s, "csi_acquisition_and_reporting.effective_sinr_method", ...
    localGetNested(s, "link_adaptation.effective_sinr_method", "")))));
if strlength(effectiveSINRMethod) > 0
    cfg = sixgr.util.structSet(cfg, "phy.csi.effectiveSINRMethod", char(effectiveSINRMethod));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.effectiveSINRMethod", char(effectiveSINRMethod));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.effectiveSINRMethod", char(effectiveSINRMethod));
end
eesmBeta_dB = double(localGetNested(s, "csi_acquisition_and_reporting.eesm_beta_db", ...
    localGetNested(s, "link_adaptation.eesm_beta_db", NaN)));
if isfinite(eesmBeta_dB) && eesmBeta_dB > 0
    cfg = sixgr.util.structSet(cfg, "phy.csi.eesmBeta_dB", double(eesmBeta_dB));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.eesmBeta_dB", double(eesmBeta_dB));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.eesmBeta_dB", double(eesmBeta_dB));
end
targetBLER = double(localGetNested(s, "csi_acquisition_and_reporting.target_bler", ...
    localGetNested(s, "link_adaptation.target_bler", NaN)));
if isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1
    cfg = sixgr.util.structSet(cfg, "phy.csi.targetBLER", double(targetBLER));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.targetBLER", double(targetBLER));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.targetBLER", double(targetBLER));
end
blerCurveSlope_dB = double(localGetNested(s, "csi_acquisition_and_reporting.bler_curve_slope_db", ...
    localGetNested(s, "link_adaptation.bler_curve_slope_db", NaN)));
if isfinite(blerCurveSlope_dB) && blerCurveSlope_dB > 0
    cfg = sixgr.util.structSet(cfg, "phy.csi.blerCurveSlope_dB", double(blerCurveSlope_dB));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.blerCurveSlope_dB", double(blerCurveSlope_dB));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.blerCurveSlope_dB", double(blerCurveSlope_dB));
end
scenarioId = string(localGetNested(s, "meta.scenario_id", ""));
if scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    if strlength(sinrToCQIMode) == 0
        cfg = sixgr.util.structSet(cfg, "phy.csi.sinrToCQIMode", "threshold_table");
        cfg = sixgr.util.structSet(cfg, "phy.pdsch.sinrToCQIMode", "threshold_table");
        cfg = sixgr.util.structSet(cfg, "phy.pusch.sinrToCQIMode", "threshold_table");
    end
    if strlength(effectiveSINRMethod) == 0
        cfg = sixgr.util.structSet(cfg, "phy.csi.effectiveSINRMethod", "eesm");
        cfg = sixgr.util.structSet(cfg, "phy.pdsch.effectiveSINRMethod", "eesm");
        cfg = sixgr.util.structSet(cfg, "phy.pusch.effectiveSINRMethod", "eesm");
    end
    if ~(isfinite(eesmBeta_dB) && eesmBeta_dB > 0)
        cfg = sixgr.util.structSet(cfg, "phy.csi.eesmBeta_dB", 1.5);
        cfg = sixgr.util.structSet(cfg, "phy.pdsch.eesmBeta_dB", 1.5);
        cfg = sixgr.util.structSet(cfg, "phy.pusch.eesmBeta_dB", 1.5);
    end
    if ~(isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1)
        cfg = sixgr.util.structSet(cfg, "phy.csi.targetBLER", 0.1);
        cfg = sixgr.util.structSet(cfg, "phy.pdsch.targetBLER", 0.1);
        cfg = sixgr.util.structSet(cfg, "phy.pusch.targetBLER", 0.1);
    end
    if ~(isfinite(blerCurveSlope_dB) && blerCurveSlope_dB > 0)
        cfg = sixgr.util.structSet(cfg, "phy.csi.blerCurveSlope_dB", 1.5);
        cfg = sixgr.util.structSet(cfg, "phy.pdsch.blerCurveSlope_dB", 1.5);
        cfg = sixgr.util.structSet(cfg, "phy.pusch.blerCurveSlope_dB", 1.5);
    end
end
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMIType1", reportPMI && pmiCodebookMode == "type1_su_mimo");
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMIType2", reportPMI && pmiCodebookMode == "type2_mu_mimo");
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMIEnhancedType2", reportPMI && pmiCodebookMode == "etype2_candidate");
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPayloadMode", char(reportPayloadMode));
cfg = sixgr.util.structSet(cfg, "phy.csi.crcAttached", crcAttachedMode);
cfg = sixgr.util.structSet(cfg, "phy.csi.crcFreeMode", crcFreeMode);
cfg = sixgr.util.structSet(cfg, "phy.csi.bitExactPayloadPacking", true);

cfg.phy.pucch.enable = logical(s.control.pucch_enabled);
cfg.phy.pucch.format = double(s.control.pucch_format);

cfg.phy.pusch.enable = any(ismember(targetCases, localCatalogStringList(catalog.value_maps.target_case_groups.pusch_enable)));
cfg.phy.pusch.nLayers = double(s.mimo.n_layers);
cfg.phy.pusch.numLayers = double(s.mimo.n_layers);
cfg.phy.pusch.transformPrecoding = logical(s.waveform.transform_precoding_enabled);
cfg.phy.pusch.configuredMCSIndex = ulConfiguredMCSIndex;
cfg.phy.pusch.mcsIndex = ulConfiguredMCSIndex;
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsTable", char(string(s.modulation.mcs_table)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.nPorts", double(s.reference_signals.pusch_dmrs_ports));
ulCodebookEnabled = ~logical(s.waveform.transform_precoding_enabled) && reportPMI && ...
    pmiCodebookMode ~= "noncodebook" && lower(string(s.mimo.codebook_type)) ~= "noncodebook";
if ulCodebookEnabled
    ulNumPorts = double(localGetNested(s, "reference_signals.pusch_dmrs_ports", ...
        localGetNested(s, "mimo.n_tx_ant", double(s.mimo.n_layers))));
    allowedPorts = [1 2 4];
    if ~(isfinite(ulNumPorts) && ulNumPorts >= double(s.mimo.n_layers))
        ulNumPorts = double(s.mimo.n_layers);
    end
    ulNumPorts = allowedPorts(find(allowedPorts >= max(1, round(ulNumPorts)), 1, "first"));
    if isempty(ulNumPorts)
        ulNumPorts = allowedPorts(end);
    end
    initialTPMI = double(localGetNested(s, "csi_acquisition_and_reporting.initial_ul_tpmi", ...
        localGetNested(s, "reference_signals.initial_ul_tpmi", ...
        localGetNested(s, "mimo.initial_ul_tpmi", 0))));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.transmissionScheme", "codebook");
    cfg = sixgr.util.structSet(cfg, "phy.pusch.TransmissionScheme", "codebook");
    cfg = sixgr.util.structSet(cfg, "phy.pusch.NumAntennaPorts", double(ulNumPorts));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.numAntennaPorts", double(ulNumPorts));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.TPMI", max(0, round(initialTPMI)));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.PMI", max(0, round(initialTPMI)));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.TPMISource", "configured_initial_ul_codebook_tpmi_replaced_by_srs_dci_when_available");
end
cfg = sixgr.util.structSet(cfg, "phy.pusch.pi2BPSKEnabled", logical(s.modulation.pi2_bpsk_enabled));
cfg = sixgr.util.structSet(cfg, "phy.modulation.constellationShapingEnabled", ...
    logical(s.modulation.constellation_shaping_enabled));

cfg.phy.srs.enable = logical(s.reference_signals.srs_enabled);
cfg.phy.srs.nPorts = double(s.reference_signals.srs_ports);
srsPeriodSlots = double(localGetNested(s, "reference_signals.srs_periodicity_slots", ...
    localGetNested(s, "control_gating.srs_period_slots", NaN)));
if ~(isfinite(srsPeriodSlots) && srsPeriodSlots >= 1)
    srsPeriodicityMs = double(localGetNested(s, "reference_signals.srs_periodicity_ms", NaN));
    slotDurationMs = max(eps, double(runTiming.TotalTime_ms) / max(double(runTiming.TotalSlots), 1));
    if isfinite(srsPeriodicityMs) && srsPeriodicityMs > 0
        srsPeriodSlots = max(1, round(srsPeriodicityMs / slotDurationMs));
    else
        srsPeriodSlots = 4;
    end
end
cfg = sixgr.util.structSet(cfg, "phy.srs.period_slots", max(1, round(double(srsPeriodSlots))));
cfg = sixgr.util.structSet(cfg, "phy.srs.maxUEsPerSlot", max(1, round(double(localGetNested(s, ...
    "reference_signals.srs_max_ues_per_slot", localGetNested(s, "control_gating.srs_max_ues_per_slot", 1))))));
cfg = sixgr.util.structSet(cfg, "phy.srs.schedulingPolicy", char(string(localGetNested(s, ...
    "reference_signals.srs_scheduling_policy", localGetNested(s, "control_gating.srs_scheduling_policy", "round_robin_phase")))));
cfg = sixgr.util.structSet(cfg, "phy.trs.enable", logical(s.reference_signals.trs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trs.nPorts", double(localRequireNested(s, "reference_signals.trs.num_ports", "reference_signals.trs.num_ports")));
cfg = sixgr.util.structSet(cfg, "phy.trs.scramblingID", double(localRequireNested(s, "reference_signals.trs.scrambling_id", "reference_signals.trs.scrambling_id")));
cfg = sixgr.util.structSet(cfg, "phy.ptrs.enable", logical(s.reference_signals.ptrs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trackingRS.enable", logical(s.reference_signals.tracking_rs_enabled));

cfg.phy.prach.enable = logical(s.random_access.enabled);
cfg.phy.prach.preambleFormat = char(string(localGetNested(s, "random_access.prach_format", "")));
cfg = sixgr.util.structSet(cfg, "phy.prach.preambleCount", double(s.random_access.preamble_count));
cfg.phy.prach.configurationIndex = double(s.random_access.configuration_index);
cfg.phy.prach.subcarrierSpacing_kHz = double(s.random_access.subcarrier_spacing_khz);
cfg.phy.prach.rootSeqIndex = double(s.random_access.root_sequence_index);
cfg.phy.prach.zeroCorrelationZone = double(s.random_access.zero_correlation_zone);
cfg.phy.prach.preambleIndex = double(s.random_access.preamble_index);
cfg = localStructSetIfPresent(cfg, "phy.prach.sequenceIndex", localGetNested(s, "random_access.sequence_index", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.logicalRootSequenceIndex", localGetNested(s, "random_access.logical_root_sequence_index", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.restrictedSet", localGetNested(s, "random_access.restricted_set", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.frequencyStart", localGetNested(s, "random_access.frequency_start", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.detectionThreshold", localGetNested(s, "random_access.detection_threshold", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.FrequencyRange", localGetNested(s, "random_access.frequency_range", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DuplexMode", localGetNested(s, "frequency.duplex_mode", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.CarrierFrequencyHz", localGetNested(s, "frequency.center_frequency_hz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.CarrierSCSkHz", localGetNested(s, "frame.scs_khz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NSizeGrid", localGetNested(s, "frequency.n_size_grid", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PRACHConfigurationIndex", localGetNested(s, "random_access.configuration_index", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PRACHFormat", localGetNested(s, "random_access.prach_format", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PRACHSubcarrierSpacing", localGetNested(s, "random_access.subcarrier_spacing_khz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.SequenceIndex", localGetNested(s, "random_access.sequence_index", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.LogicalRootSequenceIndex", localGetNested(s, "random_access.logical_root_sequence_index", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PreambleIndex", localGetNested(s, "random_access.preamble_index", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.RestrictedSet", localGetNested(s, "random_access.restricted_set", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.ZeroCorrelationZone", localGetNested(s, "random_access.zero_correlation_zone", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.FrequencyStart", localGetNested(s, "random_access.frequency_start", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumPRACHOccasions", localGetNested(s, "random_access.num_prach_occasions", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumSlots", localGetNested(s, "random_access.num_slots", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumSubframes", localGetNested(s, "random_access.num_subframes", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumTrials", localGetNested(s, "random_access.min_detection_trials", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.ActivePreamblePattern", localGetNested(s, "random_access.active_preamble_pattern", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumRxAntennas", localGetNested(s, "random_access.num_rx_antennas", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumTxAntennas", localGetNested(s, "random_access.num_tx_antennas", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumUEsPerRO", localGetNested(s, "random_access.num_ues_per_ro", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableCollisionMode", localGetNested(s, "random_access.enable_collision_mode", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableInterCellInterference", localGetNested(s, "random_access.enable_inter_cell_interference", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableFrequencyOffset", localGetNested(s, "random_access.enable_frequency_offset", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnablePhaseNoise", localGetNested(s, "random_access.enable_phase_noise", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableTimingUncertainty", localGetNested(s, "random_access.enable_timing_uncertainty", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableFrequencyEstimationMetric", localGetNested(s, "random_access.enable_frequency_estimation_metric", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DetectionThresholdMode", localGetNested(s, "random_access.detection_threshold_mode", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DetectionThreshold", localGetNested(s, "random_access.detection_threshold", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.SNRSweep_dB", localGetNested(s, "random_access.snr_sweep_db", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.ThresholdSweep", localGetNested(s, "random_access.threshold_sweep", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.ChannelModel", localGetNested(s, "random_access.channel_model", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DelaySpread_ns", localGetNested(s, "random_access.delay_spread_ns", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.Speed_kmh", localGetNested(s, "random_access.speed_kmh", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.CellRadius_m", localGetNested(s, "random_access.cell_radius_m", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.TimingUncertaintyMin_us", localGetNested(s, "random_access.timing_uncertainty_min_us", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.TimingUncertaintyMax_us", localGetNested(s, "random_access.timing_uncertainty_max_us", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.UEFrequencyOffsetHz", localGetNested(s, "random_access.ue_frequency_offset_hz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.TRPFrequencyOffsetHz", localGetNested(s, "random_access.trp_frequency_offset_hz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PhaseNoiseStdRad", localGetNested(s, "random_access.phase_noise_std_rad", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.InterCellRelativePower_dB", localGetNested(s, "random_access.inter_cell_relative_power_db", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.TargetFalseAlarmProbability", localGetNested(s, "random_access.target_false_alarm_probability", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.TimingTolerance_us", localGetNested(s, "random_access.timing_tolerance_us", []));
cfg = sixgr.util.structSet(cfg, "prach_lls.OutputDir", runFolder);
cfg = sixgr.util.structSet(cfg, "prach_lls.ScenarioName", char(string(s.meta.scenario_id)));

cfg.phy.harq.enable = logical(s.harq.enabled);
cfg.phy.harq.nProcesses = double(s.harq.process_count);
cfg.phy.harq.rvSequence = double(s.harq.rv_sequence);
cfg.mac.harq.enable = logical(s.harq.enabled);
cfg.mac.harq.maxRetx = double(localRequireNested(s, "harq.max_retx", "harq.max_retx"));
cfg = sixgr.util.structSet(cfg, "phy.harq.feedbackTimingSlots", double(s.harq.feedback_timing_slots));
cfg = sixgr.util.structSet(cfg, "phy.harq.combiningMode", char(string(s.harq.combining_mode)));
cfg = sixgr.util.structSet(cfg, "phy.harq.cbgEnabled", logical(s.harq.cbg_enabled));
cfg = sixgr.util.structSet(cfg, "phy.harq.validationMode", char(string(localRequireNested(s, "harq.validation_mode", "harq.validation_mode"))));

cfg.phy.ldpc.maxIterations = double(s.coding.max_decoder_iterations);
cfg = sixgr.util.structSet(cfg, "phy.ldpc.useMexBatchDecode", ...
    ~localShouldDisableExactMexForStrictCoupledTruthWaveform(s, runnerProfile));
cfg.phy.rx.cfoCompensation = abs(double(s.impairments.cfo_hz)) > 0;
cfg.phy.rx.useFastChannelEstMex = false;
cfg = sixgr.util.structSet(cfg, "phy.rx.useIdealTimingSync", logical(localRequireNested(s, ...
    "receiver.use_ideal_timing_sync", "receiver.use_ideal_timing_sync")));
cfg.phy.nTxAnt = double(s.mimo.n_tx_ant);
cfg.phy.nRxAnt = double(s.mimo.n_rx_ant);
cfg = localApplyRuntimeAntennaConfig(cfg, s);
cfg = sixgr.util.structSet(cfg, "phy.impairments.cfoHz", double(s.impairments.cfo_hz));
cfg = sixgr.util.structSet(cfg, "phy.impairments.phaseNoiseEnabled", logical(s.impairments.phase_noise_enabled));
iqEnabled = logical(s.impairments.iq_imbalance_enabled) || logical(localGetNested(s, "impairments.iq_imbalance.enabled", false));
iqModel = localResolveIQModelToken(s);
iqGainImb_dB = localResolveFirstFiniteNumeric(s, [ ...
    "power_and_rf_frontend.iq_imbalance.gain_imbalance_db"
    "power_and_rf_frontend.iq_imbalance.amp_imbalance_db"
    "power_and_rf_frontend.iq_imbalance.amp_imb_db"
    "power_and_rf_frontend.iq_imbalance.amplitude_imbalance_db"
    "impairments.iq_imbalance.gain_imbalance_db"
    "impairments.iq_imbalance.amp_imbalance_db"
    "impairments.iq_imbalance.amp_imb_db"
    "impairments.iq_imbalance.amplitude_imbalance_db"], NaN);
iqPhaseImb_deg = localResolveFirstFiniteNumeric(s, [ ...
    "power_and_rf_frontend.iq_imbalance.phase_imbalance_deg"
    "power_and_rf_frontend.iq_imbalance.phase_imb_deg"
    "impairments.iq_imbalance.phase_imbalance_deg"
    "impairments.iq_imbalance.phase_imb_deg"], NaN);
cfg = sixgr.util.structSet(cfg, "phy.impairments.iqImbalanceEnabled", logical(iqEnabled));
cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.enable", logical(iqEnabled));
cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.model", char(iqModel));
if isfinite(iqGainImb_dB)
    cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.ampImb_dB", double(iqGainImb_dB));
end
if isfinite(iqPhaseImb_deg)
    cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.phaseImb_deg", double(iqPhaseImb_deg));
end
cfg = sixgr.util.structSet(cfg, "phy.impairments.paNonlinearityEnabled", logical(s.impairments.pa_nonlinearity_enabled));
cfg = sixgr.util.structSet(cfg, "phy.impairments.adcQuantizationBits", double(s.impairments.adc_quantization_bits));
cfg = sixgr.util.structSet(cfg, "phy.impairments.dacQuantizationBits", double(s.impairments.dac_quantization_bits));
cfg = sixgr.util.structSet(cfg, "phy.impairments.timingOffsetSamples", double(s.impairments.timing_offset_samples));
interferenceExecutionMode = localResolveInterferenceExecutionMode(s);
if any(interferenceExecutionMode == ["abstract_large_scale_scheduler_context","explicit_activity_power_sum","waveform_overlap_large_scale"])
    error("sixgr:lls6g:config:NonWaveformInterferenceModeRemoved", ...
        "interference.inter_cell_execution_mode='%s' is not allowed for no-proxy LLS runs. Use 'full_per_link_channel_waveform_sum' for waveform-backed inter-cell interference or 'none' when no inter-cell interference is configured.", ...
        char(interferenceExecutionMode));
end
cfg = sixgr.util.structSet(cfg, "run.interferenceExecutionMode", char(interferenceExecutionMode));
cfg = sixgr.util.structSet(cfg, "run.useAbstractInterferenceModel", false);
cfg = sixgr.util.structSet(cfg, "run.controlGating.pbchRequired", logical(localRequireNested(s, ...
    "control_gating.pbch_required", "control_gating.pbch_required")));
cfg = sixgr.util.structSet(cfg, "run.controlGating.prachRequired", logical(localRequireNested(s, ...
    "control_gating.prach_required", "control_gating.prach_required")));
cfg = sixgr.util.structSet(cfg, "run.controlGating.pdcchRequired", logical(localRequireNested(s, ...
    "control_gating.pdcch_required", "control_gating.pdcch_required")));
cfg = sixgr.util.structSet(cfg, "run.controlGating.srsRequired", logical(localRequireNested(s, ...
    "control_gating.srs_required", "control_gating.srs_required")));
cfg = sixgr.util.structSet(cfg, "run.controlGating.srsMaxAgeSlots", max(0, round(double(localRequireNested(s, ...
    "control_gating.srs_max_age_slots", "control_gating.srs_max_age_slots")))));
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsRequired", logical(localRequireNested(s, ...
    "control_gating.trs_required", "control_gating.trs_required")));
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsMaxAgeSlots", max(0, round(double(localRequireNested(s, ...
    "control_gating.trs_max_age_slots", "control_gating.trs_max_age_slots")))));

[dlModulation, dlCodeRate] = localResolveFixedMCSProfile(s, "DL");
cfg.phy.pdsch.modulation = char(dlModulation);
cfg.phy.pdsch.codeRate = double(dlCodeRate);

[ulModulation, ulCodeRate] = localResolveFixedMCSProfile(s, "UL");
cfg.phy.pusch.modulation = char(ulModulation);
cfg.phy.pusch.codeRate = double(ulCodeRate);
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.enabled", logical(s.mimo.beam_sweep_enabled));
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.beamCount", double(s.mimo.beam_count));
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.mtrpReady", logical(s.mimo.mtrp_ready));
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.multiPanelReady", logical(s.mimo.multi_panel_ready));
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.panelCount", double(s.mimo.panel_count));
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.trpCount", ...
    double(localRequireFirstNested(s, ["deployment_topology.num_trps","mimo.trp_count"], "deployment_topology.num_trps or mimo.trp_count")));

cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", char(linkAdaptationMode));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.configuredDLMCSIndex", dlConfiguredMCSIndex);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.configuredULMCSIndex", ulConfiguredMCSIndex);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", logical(localRequireNested(s, "link_adaptation.outer_loop_flag", "link_adaptation.outer_loop_flag")));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.innerLoopFlag", logical(localRequireNested(s, "link_adaptation.inner_loop_flag", "link_adaptation.inner_loop_flag")));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSource", char(string(localRequireNested(s, "link_adaptation.cqi_source", "link_adaptation.cqi_source"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaCQIPolicy", char(string(localRequireNested(s, "link_adaptation.delta_cqi_policy", "link_adaptation.delta_cqi_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSPolicy", char(string(localRequireNested(s, "link_adaptation.delta_mcs_policy", "link_adaptation.delta_mcs_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", char(string(localRequireNested(s, "link_adaptation.pdsch_link_adaptation_policy", "link_adaptation.pdsch_link_adaptation_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", char(string(localRequireNested(s, "link_adaptation.pusch_link_adaptation_policy", "link_adaptation.pusch_link_adaptation_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.pdcchPolicy", char(string(localRequireNested(s, "link_adaptation.pdcch_link_adaptation_policy", "link_adaptation.pdcch_link_adaptation_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankPolicy", char(string(localRequireNested(s, "link_adaptation.rank_adaptation_policy", "link_adaptation.rank_adaptation_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.alPolicy", char(string(localRequireNested(s, "link_adaptation.al_adaptation_policy", "link_adaptation.al_adaptation_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.beamPolicy", char(string(localRequireNested(s, "link_adaptation.beam_adaptation_policy", "link_adaptation.beam_adaptation_policy"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.periodicity", char(string(localRequireNested(s, "link_adaptation.adaptation_periodicity", "link_adaptation.adaptation_periodicity"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.delayModel", char(string(localRequireNested(s, "link_adaptation.adaptation_delay_model", "link_adaptation.adaptation_delay_model"))));
linkAdaptationDomain = lower(strtrim(string(localGetNested(s, "link_adaptation.domain", ""))));
if strlength(linkAdaptationDomain) > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.domain", char(linkAdaptationDomain));
end
bootstrapCQIMode = lower(strtrim(string(localGetNested(s, "link_adaptation.bootstrap_cqi_mode", ""))));
if strlength(bootstrapCQIMode) > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.bootstrapCQIMode", char(bootstrapCQIMode));
end
cqiSmoothingAlpha = double(localGetNested(s, "link_adaptation.cqi_smoothing_alpha", NaN));
if isfinite(cqiSmoothingAlpha) && cqiSmoothingAlpha >= 0 && cqiSmoothingAlpha <= 1
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", double(cqiSmoothingAlpha));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", 0.2);
end
ollaStepDown = double(localGetNested(s, "link_adaptation.olla_step_down", NaN));
if isfinite(ollaStepDown) && ollaStepDown > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", double(ollaStepDown));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", 1.0);
end
ollaStepUp = double(localGetNested(s, "link_adaptation.olla_step_up", NaN));
if isfinite(ollaStepUp) && ollaStepUp > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", double(ollaStepUp));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", 0.12);
end
deltaMCSMin = double(localGetNested(s, "link_adaptation.delta_mcs_min", NaN));
if isfinite(deltaMCSMin)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMin", double(deltaMCSMin));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMin", -6);
end
deltaMCSMax = double(localGetNested(s, "link_adaptation.delta_mcs_max", NaN));
if isfinite(deltaMCSMax)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMax", double(deltaMCSMax));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMax", 6);
end
resetOnRIChange = localGetNested(s, "link_adaptation.reset_on_ri_change", []);
if ~isempty(resetOnRIChange)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.resetOnRIChange", logical(resetOnRIChange));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.resetOnRIChange", true);
end
cqiJumpResetThreshold = double(localGetNested(s, "link_adaptation.cqi_jump_reset_threshold", NaN));
if isfinite(cqiJumpResetThreshold) && cqiJumpResetThreshold >= 1
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", double(cqiJumpResetThreshold));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", 4);
end
rankEigenThreshold_dB = double(localGetNested(s, "reference_signals.srs_rank_eigen_threshold_db", ...
    localGetNested(s, "link_adaptation.srs_rank_eigen_threshold_db", NaN)));
if isfinite(rankEigenThreshold_dB) && rankEigenThreshold_dB > 0
    cfg = sixgr.util.structSet(cfg, "phy.srs.rankEigenThreshold_dB", double(rankEigenThreshold_dB));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.srs.rankEigenThreshold_dB", 10);
end

cfg = localApplySystemConfig(cfg, s);
cfg = localApplyTrafficConfig(cfg, s);

cfg = sixgr.util.structSet(cfg, "meta.lls6gScenarioID", char(string(s.meta.scenario_id)));
cfg = sixgr.util.structSet(cfg, "lls6g.resolvedConfig", s);
cfg = sixgr.util.structSet(cfg, "lls6g.run_control", s.run_control);
cfg = sixgr.util.structSet(cfg, "lls6g.frequency", s.frequency);
cfg = sixgr.util.structSet(cfg, "lls6g.frame", s.frame);
cfg = sixgr.util.structSet(cfg, "lls6g.waveform", s.waveform);
cfg = sixgr.util.structSet(cfg, "lls6g.channels", s.channels);
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals", s.reference_signals);
cfg = sixgr.util.structSet(cfg, "lls6g.mimo", s.mimo);
if isfield(s, "antenna_and_array")
    cfg = sixgr.util.structSet(cfg, "lls6g.antenna_and_array", s.antenna_and_array);
end
if isfield(s, "users")
    cfg = sixgr.util.structSet(cfg, "lls6g.users", s.users);
end
if isfield(s, "system")
    cfg = sixgr.util.structSet(cfg, "lls6g.system", s.system);
end
if isfield(s, "traffic")
    cfg = sixgr.util.structSet(cfg, "lls6g.traffic", s.traffic);
end
cfg = sixgr.util.structSet(cfg, "lls6g.coding", s.coding);
cfg = sixgr.util.structSet(cfg, "lls6g.modulation", s.modulation);
cfg = sixgr.util.structSet(cfg, "lls6g.control", s.control);
cfg = sixgr.util.structSet(cfg, "lls6g.harq", s.harq);
cfg = sixgr.util.structSet(cfg, "lls6g.random_access", s.random_access);
cfg = sixgr.util.structSet(cfg, "lls6g.impairments", s.impairments);
cfg = sixgr.util.structSet(cfg, "lls6g.ai_ml", s.ai_ml);
cfg = sixgr.util.structSet(cfg, "lls6g.energy_efficiency", s.energy_efficiency);
cfg = sixgr.util.structSet(cfg, "lls6g.kpis", s.kpis);
cfg = sixgr.util.structSet(cfg, "lls6g.logging", s.logging);
cfg = sixgr.util.structSet(cfg, "lls6g.scenario", s.scenario);
cfg = sixgr.util.structSet(cfg, "lls6g.outputRunFolder", char(string(runFolder)));

if localShouldDisableExactMexForStrictCoupledTruthWaveform(s, runnerProfile)
    cfg = sixgr.util.structSet(cfg, "run.useMex", false);
end

cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end

function tf = localShouldDisableExactMexForStrictCoupledTruthWaveform(s, runnerProfile)
% Exact MEX kernels in this repo accelerate AWGN, LDPC batch decode, struct
% access, and FFT/PAPR without changing truth-vs-proxy labeling. The strict
% coupled waveform restriction is enforced separately by validateConfig when
% a fading-channel run tries to combine run.useMex with the scalar fast
% channel-estimation MEX path.
tf = false;
end

function timing = localResolveRunTiming(s)
scsKHz = double(localRequireNested(s, "frame.scs_khz", "frame.scs_khz"));
mu = round(log2(scsKHz / 15));
if ~(isfinite(mu) && mu >= 0)
    mu = 0;
end
slotDuration_ms = 1 / 2^double(mu);
slotsPerFrame = 10 * 2^double(mu);

configuredTotalFrames = localNumericScalarOrNaN(localGetNested(s, "run_control.total_frames", NaN));
configuredTotalSlots = localNumericScalarOrNaN(localGetNested(s, "run_control.total_slots", NaN));
simulationFrames = localNumericScalarOrNaN(localGetNested(s, "simulation.n_frames", NaN));
simulationSlots = localNumericScalarOrNaN(localGetNested(s, "simulation.n_slots", NaN));

if isfinite(configuredTotalFrames) && configuredTotalFrames > 0
    totalFrames = max(1, round(configuredTotalFrames));
elseif isfinite(simulationFrames) && simulationFrames > 0
    totalFrames = max(1, round(simulationFrames));
else
    totalFrames = NaN;
end

if isfinite(configuredTotalSlots) && configuredTotalSlots > 0
    totalSlots = max(1, round(configuredTotalSlots));
elseif isfinite(totalFrames) && totalFrames > 0
    totalSlots = max(1, round(totalFrames * slotsPerFrame));
elseif isfinite(simulationSlots) && simulationSlots > 0
    totalSlots = max(1, round(simulationSlots));
else
    totalSlots = max(1, round(slotsPerFrame));
end

if ~(isfinite(totalFrames) && totalFrames > 0)
    totalFrames = max(1, ceil(double(totalSlots) / double(slotsPerFrame)));
end

configuredWarmupFrames = localNumericScalarOrNaN(localGetNested(s, "run_control.warmup_frames", NaN));
configuredWarmupSlots = localNumericScalarOrNaN(localGetNested(s, "run_control.warmup_slots", NaN));
if isfinite(configuredWarmupSlots) && configuredWarmupSlots >= 0
    warmupSlots = max(0, round(configuredWarmupSlots));
elseif isfinite(configuredWarmupFrames) && configuredWarmupFrames >= 0
    warmupSlots = max(0, round(configuredWarmupFrames * slotsPerFrame));
else
    warmupSlots = max(0, round(double(localRequireNested(s, ...
        "run_control.warmup_time_ms", "run_control.warmup_time_ms")) / slotDuration_ms));
end

configuredMeasurementFrames = localNumericScalarOrNaN(localGetNested(s, "run_control.measurement_frames", NaN));
configuredMeasurementSlots = localNumericScalarOrNaN(localGetNested(s, "run_control.measurement_slots", NaN));
if isfinite(configuredMeasurementSlots) && configuredMeasurementSlots >= 0
    measurementSlots = max(0, round(configuredMeasurementSlots));
elseif isfinite(configuredMeasurementFrames) && configuredMeasurementFrames >= 0
    measurementSlots = max(0, round(configuredMeasurementFrames * slotsPerFrame));
else
    measurementSlots = max(0, totalSlots - warmupSlots);
end

if warmupSlots + measurementSlots > totalSlots
    measurementSlots = max(0, totalSlots - warmupSlots);
end

timing = struct();
timing.TotalSlots = totalSlots;
timing.WarmupSlots = warmupSlots;
timing.MeasurementSlots = measurementSlots;
timing.TotalTime_ms = double(totalSlots) * slotDuration_ms;
timing.WarmupTime_ms = double(warmupSlots) * slotDuration_ms;
timing.MeasurementTime_ms = double(measurementSlots) * slotDuration_ms;
timing.NumFrames = max(1, round(double(totalFrames)));
checkpointEveryFrames = double(localGetNested(s, "run_control.checkpoint_every_frames", NaN));
snapshotEveryFrames = double(localGetNested(s, "run_control.snapshot_every_frames", NaN));
logEveryFrames = double(localGetNested(s, "run_control.log_every_frames", NaN));
timing.CheckpointEverySlots = max(1, round(double(localGetNested(s, ...
    "run_control.checkpoint_every_slots", localFramePeriodToSlots(checkpointEveryFrames, slotsPerFrame, totalSlots)))));
timing.SnapshotEverySlots = max(1, round(double(localGetNested(s, ...
    "run_control.snapshot_every_slots", localFramePeriodToSlots(snapshotEveryFrames, slotsPerFrame, totalSlots)))));
timing.LogEverySlots = max(1, round(double(localGetNested(s, ...
    "run_control.log_every_slots", localFramePeriodToSlots(logEveryFrames, slotsPerFrame, totalSlots)))));
timing.SaveIntermediateArtifacts = logical(localGetNested(s, ...
    "run_control.save_intermediate_artifacts", localGetNested(s, "run_control.save_intermediate", false)));
timing.DeterministicReplay = logical(localGetNested(s, ...
    "run_control.deterministic_replay", localGetNested(s, "run_control.deterministic_mode", false)));
end

function slots = localFramePeriodToSlots(frameCount, slotsPerFrame, totalSlots)
if isfinite(frameCount) && frameCount > 0
    slots = max(1, round(double(frameCount) * double(slotsPerFrame)));
else
    slots = max(1, round(double(totalSlots)));
end
end

function v = localFirstValue(x)
if iscell(x)
    v = x{1};
elseif isstring(x) || isnumeric(x)
    v = x(1);
else
    v = x;
end
end

function v = localResolveDefaultPDCCHAggregationLevel(levels)
levels = double(levels(:).');
levels = unique(levels(ismember(levels, [1 2 4 8 16])), "stable");
if isempty(levels)
    v = 4;
    return;
end
if any(levels == 4)
    v = 4;
else
    [~, idx] = min(abs(levels - 4));
    v = levels(idx);
end
end

function modStr = localOrderToModulation(order)
catalog = sixgr.lls6g.config.loadParameterCatalog("scenario");
entries = sixgr.util.structGet(catalog, "value_maps.modulation_order_to_name", struct([]));
targetOrder = round(double(order));
for i = 1:numel(entries)
    if round(double(entries(i).order)) == targetOrder
        modStr = char(string(entries(i).name));
        return;
    end
end
error("sixgr:lls6g:config:BadModulationOrder", ...
    "Unsupported modulation order '%g'.", order);
end

function cfg = localApplyTrafficConfig(cfg, s)
if ~isfield(s, "traffic") || ~(isstruct(s.traffic) && isscalar(s.traffic))
    return;
end

trafficModel = char(string(localRequireNested(s, "traffic.model", "traffic.model")));
cfg = sixgr.util.structSet(cfg, "traffic.model", trafficModel);
cfg = sixgr.util.structSet(cfg, "traffic.transport", char(string(localRequireNested(s, "traffic.transport", "traffic.transport"))));
cfg = sixgr.util.structSet(cfg, "traffic.flowDirection", upper(char(string(localRequireNested(s, "traffic.flowDirection", "traffic.flowDirection")))));
cfg = sixgr.util.structSet(cfg, "traffic.dlRatio", double(localRequireNested(s, "traffic.dlRatio", "traffic.dlRatio")));
cfg = sixgr.util.structSet(cfg, "traffic.ulRatio", double(localRequireNested(s, "traffic.ulRatio", "traffic.ulRatio")));
cfg = sixgr.util.structSet(cfg, "traffic.packetDelayBudget_ms", double(localRequireNested(s, "traffic.packetDelayBudget_ms", "traffic.packetDelayBudget_ms")));
cfg = sixgr.util.structSet(cfg, "traffic.packetSize_bytes", double(localRequireNested(s, "traffic.packetSize_bytes", "traffic.packetSize_bytes")));
cfg = sixgr.util.structSet(cfg, "traffic.packetInterval_ms", double(localRequireNested(s, "traffic.packetInterval_ms", "traffic.packetInterval_ms")));
cfg = sixgr.util.structSet(cfg, "traffic.targetRate_Mbps", double(localRequireNested(s, "traffic.targetRate_Mbps", "traffic.targetRate_Mbps")));
cfg = sixgr.util.structSet(cfg, "traffic.jitterPct", double(localRequireNested(s, "traffic.jitterPct", "traffic.jitterPct")));
cfg = sixgr.util.structSet(cfg, "traffic.fullBufferBitsPerTTI", double(localRequireNested(s, "traffic.fullBufferBitsPerTTI", "traffic.fullBufferBitsPerTTI")));
cfg = sixgr.util.structSet(cfg, "traffic.tcp", localRequireNested(s, "traffic.tcp", "traffic.tcp"));
cfg = sixgr.util.structSet(cfg, "traffic.qos", localRequireNested(s, "traffic.qos", "traffic.qos"));
trafficFlowResolution = localResolveTrafficFlows(s, cfg);
cfg = sixgr.util.structSet(cfg, "traffic.flows", trafficFlowResolution.Flows);
cfg = sixgr.util.structSet(cfg, "traffic.flowSource", char(trafficFlowResolution.Source));
cfg = sixgr.util.structSet(cfg, "traffic.flowDerivationMode", char(trafficFlowResolution.DerivationMode));
cfg = sixgr.util.structSet(cfg, "traffic.flowResolvedFlag", logical(trafficFlowResolution.ResolvedFlag));
if isfield(s.traffic, "trace") && isstruct(s.traffic.trace)
    traceCfg = s.traffic.trace;
    traceFile = string(sixgr.util.structGet(traceCfg, "file", ""));
    traceHasInlineBits = ~isempty(sixgr.util.structGet(traceCfg, "offeredBitsDL", [])) || ...
        ~isempty(sixgr.util.structGet(traceCfg, "offeredBitsUL", []));
    traceHasTable = isfield(traceCfg, "flowTable") && istable(traceCfg.flowTable) && ~isempty(traceCfg.flowTable);
    traceRequested = any(strcmpi(string(trafficModel), ["traceReplay", "trace_replay", "trace"])) || ...
        strlength(strtrim(traceFile)) > 0 || traceHasInlineBits || traceHasTable;
    if traceRequested
        cfg = sixgr.util.structSet(cfg, "traffic.trace.file", char(traceFile));
        cfg = sixgr.util.structSet(cfg, "traffic.trace.offeredBitsDL", sixgr.util.structGet(traceCfg, "offeredBitsDL", []));
        cfg = sixgr.util.structSet(cfg, "traffic.trace.offeredBitsUL", sixgr.util.structGet(traceCfg, "offeredBitsUL", []));
        cfg = sixgr.util.structSet(cfg, "traffic.trace.transport", char(string(sixgr.util.structGet(traceCfg, "transport", ""))));
        cfg = sixgr.util.structSet(cfg, "traffic.trace.flowDirection", char(string(sixgr.util.structGet(traceCfg, "flowDirection", ""))));
        cfg = sixgr.util.structSet(cfg, "traffic.trace.packetDelayBudget_ms", sixgr.util.structGet(traceCfg, "packetDelayBudget_ms", []));
        if traceHasTable
            cfg = sixgr.util.structSet(cfg, "traffic.trace.flowTable", traceCfg.flowTable);
        end
    end
end
end

function out = localResolveTrafficFlows(s, cfg)
raw = localGetNested(s, "traffic.flows", []);
raw = localNormalizeTrafficFlowArray(raw);
if ~isempty(raw)
    out = struct( ...
        "Flows", raw, ...
        "Source", "traffic.flows", ...
        "DerivationMode", "explicit_yaml_or_browser", ...
        "ResolvedFlag", true);
    return;
end

requiredScalarPaths = [ ...
    "traffic.model"
    "traffic.transport"
    "traffic.flowDirection"
    "traffic.packetDelayBudget_ms"
    "traffic.packetSize_bytes"
    "traffic.packetInterval_ms"
    "traffic.targetRate_Mbps"
    "traffic.jitterPct"
    "traffic.qos.default5QI"];
missing = strings(0, 1);
for i = 1:numel(requiredScalarPaths)
    if isempty(localGetNested(s, requiredScalarPaths(i), []))
        missing(end + 1, 1) = requiredScalarPaths(i); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:lls6g:config:MissingTrafficFlowConfig", ...
        "traffic.flows is absent and cannot be derived because these equivalent scalar traffic inputs are missing: %s.", ...
        strjoin(cellstr(missing), ", "));
end

model = lower(strtrim(string(localGetNested(s, "traffic.model", ""))));
flowDirection = upper(char(string(localGetNested(s, "traffic.flowDirection", ""))));
transport = upper(char(string(localGetNested(s, "traffic.transport", ""))));
qfi = max(1, round(double(localGetNested(s, "traffic.qos.default5QI", 9))));

flow = struct();
flow.name = char("derived_" + model + "_flow");
flow.qfi = double(qfi);
flow.fiveQi = double(qfi);
flow.protocol = char(transport);
flow.direction = char(flowDirection);
flow.packetDelayBudget_ms = double(localGetNested(s, "traffic.packetDelayBudget_ms", NaN));
flow.packetSize_bytes = double(localGetNested(s, "traffic.packetSize_bytes", NaN));
flow.packetInterval_ms = double(localGetNested(s, "traffic.packetInterval_ms", NaN));
flow.rate_Mbps = double(localGetNested(s, "traffic.targetRate_Mbps", NaN));
flow.weight = 1.0;
flow.jitterPct = double(localGetNested(s, "traffic.jitterPct", NaN));
flow.burstiness = char(localDeriveTrafficBurstinessFromModel(model));
flow.service_profile = char(model);
flow.ue_class = "";
flow.ue_count = double(sixgr.util.structGet(cfg, "scenario.nUE", NaN));

out = struct( ...
    "Flows", flow, ...
    "Source", "traffic.scalar_profile_fields", ...
    "DerivationMode", "derived_from_scalar_traffic_config", ...
    "ResolvedFlag", true);
end

function flows = localNormalizeTrafficFlowArray(raw)
flows = struct([]);
if isempty(raw)
    return;
end
if isstruct(raw)
    flows = raw(:);
elseif iscell(raw)
    try
        flows = [raw{:}].';
    catch
        flows = struct([]);
    end
end
if isempty(flows)
    flows = struct([]);
end
end

function burstiness = localDeriveTrafficBurstinessFromModel(model)
model = lower(strtrim(string(model)));
switch model
    case {"fullbuffer", "full_buffer"}
        burstiness = "saturation";
    case {"xr", "traffic_xr", "extendedreality"}
        burstiness = "periodic";
    case {"genai", "traffic_genai", "ai"}
        burstiness = "bursty";
    case {"mmtc", "traffic_mmtc", "iot"}
        burstiness = "low";
    otherwise
        burstiness = "medium";
end
end

function cfg = localApplySystemConfig(cfg, s)
if ~isfield(s, "system") || ~(isstruct(s.system) && isscalar(s.system))
    return;
end

if isfield(s.system, "queueMaxBits")
    cfg = sixgr.util.structSet(cfg, "system.queueMaxBits", double(localRequireNested(s, "system.queueMaxBits", "system.queueMaxBits")));
end
if isfield(s.system, "largeScaleUpdatePeriod_slots")
    cfg = sixgr.util.structSet(cfg, "system.largeScaleUpdatePeriod_slots", ...
        double(localRequireNested(s, "system.largeScaleUpdatePeriod_slots", "system.largeScaleUpdatePeriod_slots")));
end
cfg = sixgr.util.structSet(cfg, "system.phyBackend", localResolveSystemPHYBackend(cfg.run.simulationMode));
cfg = sixgr.util.structSet(cfg, "system.simDuration_s", double(cfg.run.totalTime_ms) / 1e3);
cfg = sixgr.util.structSet(cfg, "system.warmupTime_s", double(cfg.run.warmupTime_ms) / 1e3);
cfg = sixgr.util.structSet(cfg, "system.measurementTime_s", double(cfg.run.measurementTime_ms) / 1e3);
if isfield(s.system, "scheduler") && isstruct(s.system.scheduler)
    schedulerType = char(string(localRequireNested(s, "system.scheduler.type", "system.scheduler.type")));
    maxActiveUEsPerSlot = double(localRequireNested(s, "system.scheduler.maxActiveUEsPerSlot", "system.scheduler.maxActiveUEsPerSlot"));
    maxActiveUEsPerCellPerSlot = double(localGetNested(s, "system.scheduler.maxActiveUEsPerCellPerSlot", maxActiveUEsPerSlot));
    maxActiveUEsPerCellPerSlotDL = double(localGetNested(s, "system.scheduler.maxActiveUEsPerCellPerSlotDL", maxActiveUEsPerCellPerSlot));
    maxActiveUEsPerCellPerSlotUL = double(localGetNested(s, "system.scheduler.maxActiveUEsPerCellPerSlotUL", maxActiveUEsPerCellPerSlot));
    maxPRBAllocationPerUE = double(localRequireNested(s, "system.scheduler.maxPRBAllocationPerUE", "system.scheduler.maxPRBAllocationPerUE"));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.type", schedulerType);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.type", schedulerType);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxActiveUEsPerSlot", maxActiveUEsPerSlot);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxActiveUEsPerCellPerSlot", maxActiveUEsPerCellPerSlot);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxActiveUEsPerCellPerSlotDL", maxActiveUEsPerCellPerSlotDL);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxActiveUEsPerCellPerSlotUL", maxActiveUEsPerCellPerSlotUL);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxPRBAllocationPerUE", maxPRBAllocationPerUE);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxUEPerSlot", maxActiveUEsPerCellPerSlot);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxUEPerSlotDL", maxActiveUEsPerCellPerSlotDL);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxUEPerSlotUL", maxActiveUEsPerCellPerSlotUL);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxActiveUEsPerSlot", maxActiveUEsPerSlot);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxActiveUEsPerCellPerSlot", maxActiveUEsPerCellPerSlot);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxActiveUEsPerCellPerSlotDL", maxActiveUEsPerCellPerSlotDL);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxActiveUEsPerCellPerSlotUL", maxActiveUEsPerCellPerSlotUL);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxPRBAllocationPerUE", maxPRBAllocationPerUE);
    if isfield(s.system.scheduler, "tbsMode")
        cfg = sixgr.util.structSet(cfg, "mac.scheduler.tbsMode", ...
            char(string(localGetNested(s, "system.scheduler.tbsMode", "approximate"))));
    end
    if isfield(s.system.scheduler, "fastNREApprox")
        cfg = sixgr.util.structSet(cfg, "mac.scheduler.fastNREApprox", ...
            logical(localGetNested(s, "system.scheduler.fastNREApprox", true)));
    end
    if isfield(s.system.scheduler, "allowApproximatePlanningInStrictMode")
        cfg = sixgr.util.structSet(cfg, "mac.scheduler.allowApproximatePlanningInStrictMode", ...
            logical(localGetNested(s, "system.scheduler.allowApproximatePlanningInStrictMode", false)));
    end
    cfg = sixgr.util.structSet(cfg, "system.scheduler.fairnessAlpha", ...
        double(localRequireNested(s, "system.scheduler.fairnessAlpha", "system.scheduler.fairnessAlpha")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.proportionalFairWindow_ms", ...
        double(localRequireNested(s, "system.scheduler.proportionalFairWindow_ms", "system.scheduler.proportionalFairWindow_ms")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.beamAware", ...
        logical(localRequireNested(s, "system.scheduler.beamAware", "system.scheduler.beamAware")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.energyAware", ...
        logical(localRequireNested(s, "system.scheduler.energyAware", "system.scheduler.energyAware")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.qosAware", ...
        logical(localRequireNested(s, "system.scheduler.qosAware", "system.scheduler.qosAware")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.sliceAware", ...
        logical(localRequireNested(s, "system.scheduler.sliceAware", "system.scheduler.sliceAware")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.starvationGuard", ...
        logical(localRequireNested(s, "system.scheduler.starvationGuard", "system.scheduler.starvationGuard")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.cellEdgeBoost", ...
        logical(localRequireNested(s, "system.scheduler.cellEdgeBoost", "system.scheduler.cellEdgeBoost")));
    coverageOutageGuardEnabled = logical(localGetNested(s, "system.scheduler.coverageOutageGuardEnabled", ...
        localGetNested(s, "system.scheduler.coverage_outage_guard_enabled", false)));
    minSchedulingSINR_dB = double(localGetNested(s, "system.scheduler.minSchedulingSINR_dB", ...
        localGetNested(s, "system.scheduler.min_scheduling_sinr_db", -5)));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.coverageOutageGuardEnabled", coverageOutageGuardEnabled);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.coverageOutageGuardEnabled", coverageOutageGuardEnabled);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.minSchedulingSINR_dB", minSchedulingSINR_dB);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.minSchedulingSINR_dB", minSchedulingSINR_dB);
end
if isfield(s.system, "measurement") && isstruct(s.system.measurement)
    cfg = sixgr.util.structSet(cfg, "system.measurement.periodSlots", ...
        double(localRequireNested(s, "system.measurement.periodSlots", "system.measurement.periodSlots")));
    cfg = sixgr.util.structSet(cfg, "system.measurement.filterAlpha", ...
        double(localRequireNested(s, "system.measurement.filterAlpha", "system.measurement.filterAlpha")));
end
if isfield(s.system, "beam") && isstruct(s.system.beam)
    cfg = sixgr.util.structSet(cfg, "system.beam.enable", ...
        logical(localRequireNested(s, "system.beam.enable", "system.beam.enable")));
    cfg = sixgr.util.structSet(cfg, "system.beam.numBeams", ...
        double(localRequireNested(s, "system.beam.numBeams", "system.beam.numBeams")));
    cfg = sixgr.util.structSet(cfg, "system.beam.updatePeriod_slots", ...
        double(localRequireNested(s, "system.beam.updatePeriod_slots", "system.beam.updatePeriod_slots")));
    cfg = sixgr.util.structSet(cfg, "system.beam.sectorSpan_deg", ...
        double(localRequireNested(s, "system.beam.sectorSpan_deg", "system.beam.sectorSpan_deg")));
    cfg = sixgr.util.structSet(cfg, "system.beam.maxGain_dB", ...
        double(localRequireNested(s, "system.beam.maxGain_dB", "system.beam.maxGain_dB")));
end
if isfield(s.system, "handover") && isstruct(s.system.handover)
    cfg = sixgr.util.structSet(cfg, "system.handover.enable", ...
        logical(localRequireNested(s, "system.handover.enable", "system.handover.enable")));
    cfg = sixgr.util.structSet(cfg, "system.handover.a3Offset_dB", ...
        double(localRequireNested(s, "system.handover.a3Offset_dB", "system.handover.a3Offset_dB")));
    cfg = sixgr.util.structSet(cfg, "system.handover.hysteresis_dB", ...
        double(localRequireNested(s, "system.handover.hysteresis_dB", "system.handover.hysteresis_dB")));
    cfg = sixgr.util.structSet(cfg, "system.handover.timeToTrigger_slots", ...
        double(localRequireNested(s, "system.handover.timeToTrigger_slots", "system.handover.timeToTrigger_slots")));
    cfg = sixgr.util.structSet(cfg, "system.handover.minServingSlots", ...
        double(localRequireNested(s, "system.handover.minServingSlots", "system.handover.minServingSlots")));
    cfg = sixgr.util.structSet(cfg, "system.handover.preparationSlots", ...
        double(localRequireNested(s, "system.handover.preparationSlots", "system.handover.preparationSlots")));
    cfg = sixgr.util.structSet(cfg, "system.handover.interruptionSlots", ...
        double(localRequireNested(s, "system.handover.interruptionSlots", "system.handover.interruptionSlots")));
    cfg = sixgr.util.structSet(cfg, "system.handover.blockDuringPreparation", ...
        logical(localRequireNested(s, "system.handover.blockDuringPreparation", "system.handover.blockDuringPreparation")));
end
if isfield(s.system, "waveform") && isstruct(s.system.waveform)
    cfg = sixgr.util.structSet(cfg, "system.waveform.useGrantLocalGrid", ...
        logical(localGetNested(s, "system.waveform.useGrantLocalGrid", false)));
    cfg = sixgr.util.structSet(cfg, "system.waveform.replayGridMode", ...
        char(string(localGetNested(s, "system.waveform.replayGridMode", "full_carrier"))));
    cfg = sixgr.util.structSet(cfg, "system.waveform.capReplayAntennasToLayers", ...
        logical(localGetNested(s, "system.waveform.capReplayAntennasToLayers", false)));
    cfg = sixgr.util.structSet(cfg, "system.waveform.longRunAudit.enabled", ...
        logical(localGetNested(s, "system.waveform.longRunAudit.enabled", false)));
    cfg = sixgr.util.structSet(cfg, "system.waveform.longRunAudit.periodSlots", ...
        double(localGetNested(s, "system.waveform.longRunAudit.periodSlots", Inf)));
    cfg = sixgr.util.structSet(cfg, "system.waveform.longRunAudit.maxGrantsPerAuditSlot", ...
        double(localGetNested(s, "system.waveform.longRunAudit.maxGrantsPerAuditSlot", Inf)));
    cfg = sixgr.util.structSet(cfg, "system.waveform.longRunAudit.unsampledGrantPolicy", ...
        char(string(localGetNested(s, "system.waveform.longRunAudit.unsampledGrantPolicy", "full_replay"))));
end
end

function backend = localResolveSystemPHYBackend(simulationMode)
mode = lower(string(simulationMode));
switch mode
    case "full_phy"
        backend = "waveform";
    case "lls_calibrated_link2system"
        error("sixgr:lls6g:config:ProxySimulationModeRemoved", ...
            "run_control.simulation_mode='lls_calibrated_link2system' was removed from the active no-proxy LLS runtime because it selects SINR-to-BLER link-to-system PHY. Use 'full_phy' for waveform-backed grant replay.");
    otherwise
        error("sixgr:lls6g:UnknownSimulationMode", ...
            "Unsupported run_control.simulation_mode '%s'. No-proxy LLS runtime requires 'full_phy'.", string(simulationMode));
end
end

function modStr = localResolveULModulation(s)
modStr = string(localOrderToModulation(double(s.modulation.ul_modulation_order)));
if localUsePi2BPSKULMode(s)
    modStr = "pi/2-BPSK";
end
modStr = char(modStr);
end

function [modStr, codeRate] = localResolveFixedMCSProfile(s, direction)
direction = upper(string(direction));
tableName = string(localGetNested(s, "modulation.mcs_table", ""));
if direction == "DL"
    mcsIndex = double(localGetNested(s, "modulation.dl_mcs_index", NaN));
else
    mcsIndex = double(localGetNested(s, "modulation.ul_mcs_index", NaN));
end

profile = sixgr.link.resolveMCSProfile(tableName, mcsIndex);
if profile.Valid
    modStr = string(profile.Modulation);
    codeRate = double(profile.TargetCodeRate);
elseif direction == "UL"
    modStr = string(localResolveULModulation(s));
    codeRate = 0.75;
else
    modStr = string(localOrderToModulation(double(localGetNested(s, "modulation.dl_modulation_order", 2))));
    codeRate = 0.75;
end

% pi/2-BPSK UL retains its explicit waveform-mode modulation.
if direction == "UL" && localUsePi2BPSKULMode(s)
    modStr = "pi/2-BPSK";
end
end

function tf = localUsePi2BPSKULMode(s)
tf = logical(localGetNested(s, "modulation.pi2_bpsk_enabled", false)) && ...
    logical(localGetNested(s, "waveform.transform_precoding_enabled", false)) && ...
    upper(string(localGetNested(s, "waveform.ul_waveform", ""))) == "DFT-S-OFDM" && ...
    round(double(localGetNested(s, "modulation.ul_modulation_order", NaN))) == 1;
end

function cfg = localApplyDeploymentTopology(cfg, s)
numCells = max(1, round(double(localGetNested(s, "deployment_topology.num_cells", ...
    localGetNested(s, "deployment_topology.num_trps", 1)))));
nSitesRequested = double(localGetNested(s, "deployment_topology.num_sites", ...
    localGetNested(s, "deployment_topology.num_base_stations", ...
    localGetNested(s, "deployment_topology.num_bs", NaN))));
nSectorsRequested = double(localGetNested(s, "deployment_topology.num_sectors_per_site", ...
    localGetNested(s, "deployment_topology.sectors_per_site", NaN)));

if ~(isfinite(nSectorsRequested) && nSectorsRequested >= 1)
    if isfinite(nSitesRequested) && nSitesRequested >= 1
        nSectorsRequested = max(1, round(numCells / max(1, round(nSitesRequested))));
    elseif numCells == 1
        nSectorsRequested = 1;
    elseif mod(numCells, 3) == 0
        nSectorsRequested = 3;
    else
        nSectorsRequested = 1;
    end
end

nSectorsPerSite = max(1, round(nSectorsRequested));
if isfinite(nSitesRequested) && nSitesRequested >= 1
    nSites = max(1, round(nSitesRequested));
else
    nSites = max(1, ceil(numCells / nSectorsPerSite));
end

if nSites * nSectorsPerSite < numCells
    nSites = max(1, ceil(numCells / nSectorsPerSite));
end

cfg = sixgr.util.structSet(cfg, "scenario.layout.nSites", nSites);
cfg = sixgr.util.structSet(cfg, "scenario.layout.nSectorsPerSite", nSectorsPerSite);
deploymentLayoutType = localResolveDeploymentLayoutType(s, nSites, nSectorsPerSite);
if strlength(deploymentLayoutType) > 0
    cfg = sixgr.util.structSet(cfg, "scenario.geometry.deployment", char(deploymentLayoutType));
end

wrapAroundValue = localGetNested(s, "deployment_topology.wraparound_enabled", []);
if isempty(wrapAroundValue)
    wrapAroundValue = strcmpi(char(deploymentLayoutType), "hex_grid") && nSites > 1;
end
cfg = sixgr.util.structSet(cfg, "scenario.layout.wrapAround", logical(wrapAroundValue));

interSiteDistance_m = double(localGetNested(s, "deployment_topology.inter_site_distance", NaN));
if isfinite(interSiteDistance_m) && interSiteDistance_m >= 0
cfg = sixgr.util.structSet(cfg, "scenario.layout.interSiteDistance_m", interSiteDistance_m);
end
end

function cfg = localApplyRuntimeAntennaConfig(cfg, s)
bsGeom = string(localRequireNested(s, "antenna_and_array.bs_array_geometry", "antenna_and_array.bs_array_geometry"));
ueGeom = string(localRequireNested(s, "antenna_and_array.ue_array_geometry", "antenna_and_array.ue_array_geometry"));
polToken = string(localRequireNested(s, "antenna_and_array.polarization", "antenna_and_array.polarization"));
spacingH = double(localRequireNested(s, "antenna_and_array.element_spacing_h", "antenna_and_array.element_spacing_h"));
spacingV = double(localRequireNested(s, "antenna_and_array.element_spacing_v", "antenna_and_array.element_spacing_v"));
bsCount = max(1, round(double(localRequireNested(s, "antenna_and_array.bs_num_antenna_elements", "antenna_and_array.bs_num_antenna_elements"))));
ueCount = max(1, round(double(localRequireNested(s, "antenna_and_array.ue_num_antenna_elements", "antenna_and_array.ue_num_antenna_elements"))));
bsMechanicalTiltDeg = localResolveFirstFiniteNumeric(s, ...
    ["antenna_and_array.bs_mechanical_tilt_deg", ...
     "antenna_and_array.mechanical_tilt_deg", ...
     "antenna_and_array.bs_electrical_tilt_deg"], NaN);

cfg.channel.nTxAnt = double(bsCount);
cfg.channel.nRxAnt = double(ueCount);
cfg.phy.nTxAnt = double(bsCount);
cfg.phy.nRxAnt = double(ueCount);
cfg = sixgr.util.structSet(cfg, "phy.bsArray", localResolveArrayShape(bsGeom, bsCount, polToken));
cfg = sixgr.util.structSet(cfg, "phy.ueArray", localResolveArrayShape(ueGeom, ueCount, polToken));

cfg = sixgr.util.structSet(cfg, "antenna.bs.geometry", char(lower(strtrim(bsGeom))));
cfg = sixgr.util.structSet(cfg, "antenna.bs.spacingLambda", [double(spacingH) double(spacingV)]);
cfg = sixgr.util.structSet(cfg, "antenna.bs.polarization", char(lower(strtrim(polToken))));
cfg = sixgr.util.structSet(cfg, "antenna.bs.numElements", double(bsCount));
cfg = sixgr.util.structSet(cfg, "antenna.bs.source", "browser_yaml_antenna_and_array");
if isfinite(bsMechanicalTiltDeg)
    cfg = sixgr.util.structSet(cfg, "antenna.bs.tilt_deg", double(bsMechanicalTiltDeg));
    cfg = sixgr.util.structSet(cfg, "antenna.bs.mechanicalTilt_deg", double(bsMechanicalTiltDeg));
    cfg = sixgr.util.structSet(cfg, "scenario.bs.mechanicalTilt_deg", double(bsMechanicalTiltDeg));
end
cfg = sixgr.util.structSet(cfg, "antenna.ue.geometry", char(lower(strtrim(ueGeom))));
cfg = sixgr.util.structSet(cfg, "antenna.ue.spacingLambda", [double(spacingH) double(spacingV)]);
cfg = sixgr.util.structSet(cfg, "antenna.ue.polarization", char(lower(strtrim(polToken))));
cfg = sixgr.util.structSet(cfg, "antenna.ue.numElements", double(ueCount));
cfg = sixgr.util.structSet(cfg, "antenna.ue.source", "browser_yaml_antenna_and_array");
end

function shape = localResolveArrayShape(geometryToken, totalElements, polarizationToken)
totalElements = max(1, round(double(totalElements)));
polCount = 1;
polTok = lower(strtrim(char(string(polarizationToken))));
if any(strcmp(polTok, {"dual","dual_pol","dualpolarized","dual-polarized","cross","cross_pol","cross-polarized","cross_polarized"})) && ...
        mod(totalElements, 2) == 0
    polCount = 2;
end
spatialElements = max(1, round(totalElements / polCount));
geom = lower(strtrim(char(string(geometryToken))));
switch geom
    case {"ura","upa","planar","rectangular"}
        nRow = max(1, floor(sqrt(double(spatialElements))));
        while nRow > 1 && mod(spatialElements, nRow) ~= 0
            nRow = nRow - 1;
        end
        nCol = max(1, round(spatialElements / max(nRow, 1)));
    otherwise
        nRow = 1;
        nCol = spatialElements;
end
shape = [double(nRow) double(nCol) double(polCount)];
end

function deploymentType = localResolveDeploymentLayoutType(s, nSites, nSectorsPerSite)
deploymentCandidate = string(localGetNested(s, "deployment_topology.layout_type", ...
    localGetNested(s, "deployment_topology.site_layout", ...
    localGetNested(s, "scenario.layout_type", ...
    localGetNested(s, "scenario.geometry.deployment", "")))));
if strlength(strtrim(deploymentCandidate)) > 0
    token = lower(strtrim(char(deploymentCandidate)));
    if contains(token, "indoor")
        deploymentType = "indoor_grid";
        return;
    end
    if contains(token, "hex")
        deploymentType = "hex_grid";
        return;
    end
    if contains(token, "grid") || contains(token, "rect")
        deploymentType = "rect_grid";
        return;
    end
end

scenarioClass = localNormalizeScenarioClass(string(localGetNested(s, "deployment_topology.cell_type", ...
    localGetNested(s, "scenario.profile_name", ...
    localGetNested(s, "scenario.profileName", "UMa")))));
interSiteDistance_m = double(localGetNested(s, "deployment_topology.inter_site_distance", NaN));

if strcmpi(char(scenarioClass), "InH") || strcmpi(char(scenarioClass), "InF")
    if isfinite(interSiteDistance_m) && interSiteDistance_m >= 100 && nSites > 1 && nSectorsPerSite >= 1
        deploymentType = "hex_grid";
    else
        deploymentType = "indoor_grid";
    end
    return;
end

deploymentType = "hex_grid";
end

function tableToken = localResolveCQITableToken(s)
rawToken = string(localRequireFirstNested(s, ...
    ["link_adaptation.cqi_table","reference_signals.cqi_table","csi_acquisition_and_reporting.cqi_table"], ...
    "link_adaptation.cqi_table or reference_signals.cqi_table or csi_acquisition_and_reporting.cqi_table"));
tableToken = string(sixgr.link.resolveCQIProfile(rawToken, 1).Table);
if ~ismember(lower(strtrim(tableToken)), ["table1","table2"])
    error("sixgr:lls6g:config:InvalidCQITableConfig", ...
        "Resolved scenario config produced unsupported CQI table '%s'.", string(rawToken));
end
end

function mode = localResolveNoiseOperatingMode(s)
mode = string(localGetNested(s, "simulation.noise_operating_mode", ...
    localGetNested(s, "simulation.operating_point_mode", "")));
if strlength(strtrim(mode)) == 0
    error("sixgr:lls6g:config:MissingNoiseOperatingMode", ...
        "Missing simulation.noise_operating_mode in resolved scenario config.");
end
end

function mode = localResolveBrowserExecutionMode(s)
mode = string(localGetNested(s, "run_control.execution_mode", ""));
mode = upper(strtrim(mode));
if strlength(mode) == 0
    error("sixgr:lls6g:config:MissingExecutionMode", ...
        "Missing run_control.execution_mode in resolved scenario config.");
end
end

function mode = localResolveDopplerSourceMode(s)
mode = string(localGetNested(s, "channels.doppler_source_mode", ...
    localGetNested(s, "channel_model.doppler_source_mode", "")));
mode = lower(strtrim(mode));
if strlength(mode) == 0
    error("sixgr:lls6g:config:MissingDopplerSourceMode", ...
        "Missing channels.doppler_source_mode in resolved scenario config.");
end
if mode ~= "derive_from_ue_speed"
    mode = "configured";
end
end

function dopplerHz = localResolveChannelDopplerHz(s, mobilitySpeedKmh, sourceMode)
configuredDopplerHz = double(localRequireNested(s, "channels.doppler_hz", "channels.doppler_hz"));
dopplerHz = configuredDopplerHz;
if string(sourceMode) == "derive_from_ue_speed"
    c_mps = 299792458;
    speed_mps = max(0, double(mobilitySpeedKmh)) / 3.6;
    fc_Hz = max(0, double(localRequireNested(s, "frequency.center_frequency_hz", "frequency.center_frequency_hz")));
    dopplerHz = (speed_mps / c_mps) * fc_Hz;
end
if ~(isfinite(dopplerHz) && dopplerHz >= 0)
    dopplerHz = 0;
end
end

function mode = localResolveInterferenceExecutionMode(s)
mode = string(localRequireFirstNested(s, ...
    ["interference.inter_cell_execution_mode","simulation.interference_execution_mode"], ...
    "interference.inter_cell_execution_mode or simulation.interference_execution_mode"));
end

function modelName = localResolveMobilityModel(s)
candidate = string(localGetNested(s, "mobility.model", ""));
if strlength(strtrim(candidate)) == 0
    candidate = string(localGetNested(s, "mobility.trajectory_model", ""));
end
if strlength(strtrim(candidate)) == 0
    candidate = string(localGetNested(s, "mobility.direction_model", ""));
end
token = lower(strtrim(char(candidate)));
switch token
    case {"", "randomwaypoint", "random_waypoint", "waypoint"}
        modelName = "randomWaypoint";
    case {"line", "linear", "fixed", "fixed_heading", "straight", "straightline", "straight_line"}
        modelName = "straightLine";
    case {"zigzag", "zig_zag", "zigzag_line", "zig_zag_line"}
        modelName = "zigzag";
    case {"trace", "trajectory_trace"}
        modelName = "trace";
    otherwise
        modelName = "randomWaypoint";
end
end

function [profileName, propagationScenario] = localResolveScenarioSemantics(s)
profileCandidate = string(localGetNested(s, "scenario.profile_name", ""));
if strlength(strtrim(profileCandidate)) == 0
    profileCandidate = string(localGetNested(s, "scenario.profileName", ""));
end
if strlength(strtrim(profileCandidate)) == 0
    profileCandidate = string(localGetNested(s, "deployment_topology.cell_type", ""));
end
if strlength(strtrim(profileCandidate)) == 0
    profileCandidate = "UMa";
end
profileName = localNormalizeScenarioClass(profileCandidate);

propagationCandidate = string(localGetNested(s, "channels.propagation_scenario", ""));
if strlength(strtrim(propagationCandidate)) == 0
    propagationCandidate = string(localGetNested(s, "deployment_topology.cell_type", ""));
end
if strlength(strtrim(propagationCandidate)) == 0
    propagationCandidate = profileName;
end
propagationScenario = localNormalizeScenarioClass(propagationCandidate);
end

function scenarioName = localNormalizeScenarioClass(value)
token = lower(strtrim(char(string(value))));
switch token
    case {"uma", "urbanmacro", "urban_macro"}
        scenarioName = "UMa";
    case {"umi", "urbanmicro", "urban_micro", "denseurban", "dense_urban"}
        scenarioName = "UMi";
    case {"rma", "ruralmacro", "rural_macro"}
        scenarioName = "RMa";
    case {"sma", "suburbanmacro", "suburban_macro"}
        scenarioName = "SMa";
    case {"inh", "indoorhotspot", "indoor_hotspot", "indoor", "office"}
        scenarioName = "InH";
    case {"inf", "indoorfactory", "indoor_factory", "factory"}
        scenarioName = "InF";
    otherwise
        if strlength(strtrim(string(value))) == 0
            scenarioName = "UMa";
        else
            scenarioName = string(value);
        end
end
end

function values = localCatalogStringList(rawValues)
values = lower(string(rawValues(:)));
end

function value = localRequireNested(s, path, label)
if nargin < 3 || strlength(string(label)) == 0
    label = string(path);
end
value = sixgr.util.structGet(s, path, []);
if isempty(value)
    error("sixgr:lls6g:config:MissingResolvedConfigValue", ...
        "Resolved scenario config is missing required value '%s'.", string(label));
end
end

function value = localRequireFirstNested(s, candidatePaths, label)
if nargin < 3 || strlength(string(label)) == 0
    label = strjoin(string(candidatePaths), " or ");
end
candidatePaths = string(candidatePaths(:));
for i = 1:numel(candidatePaths)
    value = sixgr.util.structGet(s, candidatePaths(i), []);
    if ~isempty(value)
        return;
    end
end
error("sixgr:lls6g:config:MissingResolvedConfigValue", ...
    "Resolved scenario config is missing required value '%s'.", string(label));
end

function value = localResolveDatabaseField(s, path, storageBackend)
storageBackend = lower(strtrim(string(storageBackend)));
value = sixgr.util.structGet(s, path, []);
if isempty(value) && startsWith(storageBackend, "mysql")
    error("sixgr:lls6g:config:MissingDatabaseOutputConfig", ...
        "Resolved scenario config is missing required DB output field '%s' for backend '%s'.", ...
        string(path), storageBackend);
end
end

function mode = localResolveOutputPersistenceMode(storageBackend)
storageBackend = lower(strtrim(string(storageBackend)));
if startsWith(storageBackend, "mysql")
    mode = "both";
else
    mode = "results_folder";
end
end

function value = localResolveUENoiseFigure_dB(s)
candidatePaths = [ ...
    "power_and_rf_frontend.ue_noise_figure_db"
    "power_and_rf_frontend.noise_figure"
    "channels.receiver_noise_figure_db"];
for i = 1:numel(candidatePaths)
    value = sixgr.util.structGet(s, candidatePaths(i), []);
    if ~isempty(value)
        value = double(value);
        if isfinite(value) && value >= 0
            return;
        end
    end
end
error("sixgr:lls6g:config:MissingUENoiseFigureConfig", ...
    "Resolved scenario config must define UE noise figure via power_and_rf_frontend.ue_noise_figure_db or power_and_rf_frontend.noise_figure.");
end

function localAssertFiniteConfigValue(value, label)
if ~(isfinite(double(value)) && isscalar(double(value)))
    error("sixgr:lls6g:config:MissingResolvedConfigValue", ...
        "Resolved scenario config is missing finite value '%s'.", string(label));
end
end

function token = localPdschPTRSMode(enabled)
if logical(enabled)
    token = "enabled";
else
    token = "disabled";
end
end

function value = localGetNested(s, path, defaultValue)
value = sixgr.util.structGet(s, path, defaultValue);
end

function tf = localScenarioHasTag(s, tag)
tags = string(sixgr.util.structGet(s, "meta.tags", ...
    sixgr.util.structGet(s, "scenario.tags", strings(0, 1))));
if isempty(tags)
    tf = false;
    return;
end
normTags = lower(strrep(strtrim(tags(:)), "_", "-"));
tag = lower(strrep(strtrim(string(tag)), "_", "-"));
tf = any(normTags == tag);
end

function s = localStructSetIfPresent(s, path, value)
if isempty(value)
    return;
end
s = sixgr.util.structSet(s, path, value);
end

function value = localNumericScalarOrNaN(raw)
if isempty(raw) || ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw)
    value = NaN;
    return;
end
value = double(raw);
if ~isfinite(value)
    value = NaN;
end
end

function value = localResolveFirstFiniteNumeric(s, candidatePaths, defaultValue)
candidatePaths = string(candidatePaths(:));
for i = 1:numel(candidatePaths)
    raw = sixgr.util.structGet(s, candidatePaths(i), []);
    if isempty(raw)
        continue;
    end
    value = double(raw);
    if isscalar(value) && isfinite(value)
        return;
    end
end
value = defaultValue;
end

function token = localResolveIQModelToken(s)
token = localNormalizeStringToken(sixgr.util.structGet(s, "power_and_rf_frontend.iq_imbalance", []));
if strlength(strtrim(token)) == 0 || any(lower(strtrim(token)) == ["none","disabled","off","false"])
    token = localNormalizeStringToken(sixgr.util.structGet(s, "impairments.iq_imbalance", token));
end
if strlength(strtrim(token)) == 0
    token = "none";
end
end

function token = localNormalizeStringToken(value)
if isstruct(value)
    if isfield(value, "model")
        value = value.model;
    else
        token = "";
        return;
    end
end
if isstring(value) || ischar(value)
    token = string(value);
elseif iscell(value) && ~isempty(value)
    token = string(value{1});
else
    token = "";
end
if ~isscalar(token)
    token = token(1);
end
token = strtrim(token);
end

function value = localTernary(condition, trueValue, falseValue)
if condition
    value = trueValue;
else
    value = falseValue;
end
end

function tf = localPolicyFlag(value)
if islogical(value) || (isnumeric(value) && isscalar(value))
    tf = logical(value);
    return;
end
token = lower(string(value));
tf = ~ismember(token, ["disabled","none","off","false"]);
end

function token = localPolicyTokenString(value)
if islogical(value) || (isnumeric(value) && isscalar(value))
    token = string(double(value));
else
    token = string(value);
end
if isempty(token)
    token = "";
    return;
end
token = strtrim(token(1));
end

function mode = localLegacyPMICodebookMode(codebookType)
switch lower(string(codebookType))
    case "type1"
        mode = "type1_su_mimo";
    case "type2"
        mode = "type2_mu_mimo";
    case "etype2"
        mode = "etype2_candidate";
    otherwise
        mode = "noncodebook";
end
end

function pattern = localDefaultSSBBlockPattern(fcHz, scsKHz)
fcHz = double(fcHz);
scsKHz = double(scsKHz);

if ~(isfinite(fcHz) && fcHz > 0)
    fcHz = 3.5e9;
end
if ~(isfinite(scsKHz) && scsKHz > 0)
    scsKHz = 30;
end

if scsKHz <= 15
    pattern = "Case A";
elseif scsKHz <= 30
    if fcHz < 3e9
        pattern = "Case B";
    else
        pattern = "Case C";
    end
elseif scsKHz <= 120
    pattern = "Case D";
else
    pattern = "Case E";
end
end

function lmax = localDefaultSSBLmax(fcHz, scsKHz)
fcHz = double(fcHz);
scsKHz = double(scsKHz);

if ~(isfinite(fcHz) && fcHz > 0)
    fcHz = 3.5e9;
end
if ~(isfinite(scsKHz) && scsKHz > 0)
    scsKHz = 30;
end

if scsKHz >= 120 || fcHz > 6e9
    lmax = 64;
elseif fcHz < 3e9
    lmax = 4;
else
    lmax = 8;
end
end
