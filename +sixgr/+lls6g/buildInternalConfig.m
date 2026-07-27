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
schemaVersionText = char(string(localGetNested(s, "meta.schema_version", ...
    localGetNested(s, "meta.schemaVersion", sixgr.lls6g.config.currentVersion()))));
cfg.meta.schema_version = schemaVersionText;
cfg.meta.schemaVersion = localSchemaMajorVersion(schemaVersionText);
cfg.meta.configHash = char(string(localGetNested(s, "meta.config_hash", localGetNested(s, "meta.configHash", ""))));
cfg.run.seed = double(localRequireFirstNested(s, ...
    ["seeds.global_seed","simulation.random_seed"], ...
    "seeds.global_seed or simulation.random_seed"));
runnerProfile = lower(string(localRequireNested(s, "scenario.runner_profile", "scenario.runner_profile")));
localAssertGeometryRuntimeAuthoritySurface(s);
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
    "scenario.unsupported_output_policy", "blank_unmeasured_values")));
cfg.run.provenanceLogging = logical(localGetNested(s, "scenario.provenance_logging", true));
protocolConfig = localGetNested(s,"protocol",struct());
if isstruct(protocolConfig) && isscalar(protocolConfig) && ...
        ~isempty(fieldnames(protocolConfig))
    protocolEnabled = logical(localGetNested(protocolConfig,"enabled",false));
    if protocolEnabled
        requiredProtocolFields = ["profile_id","configuration_epoch", ...
            "strict","rlc","pdcp","sdap","rrc","traffic"];
        missingProtocolFields = requiredProtocolFields( ...
            ~arrayfun(@(name)isfield(protocolConfig,char(name)), ...
            requiredProtocolFields));
        if ~isempty(missingProtocolFields)
            error("sixgr:lls6g:config:IncompleteProtocolStack", ...
                "Enabled protocol_stack is missing: %s.", ...
                strjoin(cellstr(missingProtocolFields),", "));
        end
        if ~logical(protocolConfig.strict)
            error("sixgr:lls6g:config:ProtocolStackMustBeStrict", ...
                "The bounded Release-18 protocol stack requires strict=true.");
        end
    end
    cfg.protocol = protocolConfig;
    if protocolEnabled
        protocolResolution = ...
            sixgr.protocol.ProtocolConfigurationValidator.validate( ...
            protocolConfig);
        cfg.protocol.capability_resolution = ...
            table2struct(protocolResolution);
    end
end
if isfield(s, "seeds")
    cfg.run.seedCatalog = s.seeds;
end
cfg.run.numWorkers = max(0, round(double(localRequireNested(s, "run_control.num_workers", "run_control.num_workers"))));
cfg.run.parallelRequestedWorkers = double(cfg.run.numWorkers);
cfg.run.useParallel = logical(cfg.run.numWorkers > 1);
cfg.run.parallelPoolKind = char(lower(strtrim(string(localGetNested(s, "run_control.parallel_pool_kind", "auto")))));
cfg.run.parallelPoolIdleTimeoutMinutes = max(1, double(localGetNested(s, ...
    "run_control.parallel_pool_idle_timeout_minutes", 1440)));
cfg.run.autoStartParallelPool = logical(localGetNested(s, "run_control.auto_start_parallel_pool", true));
cfg.run.batchSizeLinks = max(1, round(double(localRequireNested(s, "run_control.batch_size_links", "run_control.batch_size_links"))));
cfg.run.studyMode = char(string(localRequireNested(s, "run_control.study_mode", "run_control.study_mode")));
cfg.run.simulationMode = char(string(localRequireNested(s, "run_control.simulation_mode", "run_control.simulation_mode")));
cfg.run.runProfile = char(string(localRequireNested(s, "run_control.run_profile", "run_control.run_profile")));
pdschExecutionProfile = lower(strtrim(string(localGetNested( ...
    s, "pdsch.execution_profile", ""))));
allowedPDSCHExecutionProfiles = [ ...
    "connected_strict","sps_strict","ra_si_strict","phy_calibration"];
if ~isscalar(pdschExecutionProfile) || ...
        (strlength(pdschExecutionProfile) > 0 && ...
        ~any(pdschExecutionProfile == allowedPDSCHExecutionProfiles))
    error("sixgr:lls6g:config:InvalidPDSCHExecutionProfile", ...
        "pdsch.execution_profile must be one of: %s.", ...
        strjoin(cellstr(allowedPDSCHExecutionProfiles), ", "));
end
if strlength(pdschExecutionProfile) > 0
    cfg.run.pdschExecutionProfile = char(pdschExecutionProfile);
    cfg.phy.pdsch.executionProfile = char(pdschExecutionProfile);
end
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
snrSweepOffsets_dB = double(localGetNested(s, "simulation.snr_sweep_offsets_db", []));
cfg.run.snrSweepOffsets_dB = snrSweepOffsets_dB(:).';
cfg.run.snrSweepEnabled = logical(localGetNested(s, "sweeps_and_matrix.snr_sweep.enabled", ...
    ~isempty(cfg.run.snrSweepOffsets_dB)));

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
cfg.outputs.rawIQCaptureEnabled = logical(localGetNested(s, "run_control.raw_iq_capture_enable", false));
cfg.outputs.rawGridCaptureEnabled = logical(localGetNested(s, "run_control.raw_grid_capture_enable", false));
cfg.outputs.saveRawWaveforms = logical(localGetNested(s, "output_control.save_raw_waveforms", cfg.outputs.rawIQCaptureEnabled));
cfg.outputs.saveChannelSnapshots = logical(localGetNested(s, "output_control.save_channel_snapshots", ...
    localGetNested(s, "run_control.save_channel_tensors", false)));
cfg.outputs.saveConstellations = logical(localGetNested(s, "output_control.save_constellations", ...
    localGetNested(s, "run_control.save_constellations", false)));
cfg.outputs.savePlots = logical(localGetNested(s, "output_control.save_plots", cfg.outputs.saveFigures));
diagnosticRequested = logical(localGetNested(s, "output.phy_signal_diagnostic_enabled", false));
diagnosticCaptureReady = cfg.outputs.rawIQCaptureEnabled && ...
    logical(localGetNested(s, "run_control.save_channel_tensors", false)) && ...
    logical(localGetNested(s, "run_control.save_constellations", false)) && ...
    cfg.outputs.saveRawWaveforms && cfg.outputs.saveChannelSnapshots && ...
    cfg.outputs.saveConstellations && cfg.outputs.savePlots && ...
    cfg.outputs.saveFigures && cfg.outputs.savePNG;
diagnosticMissingGates = strings(0, 1);
if ~cfg.outputs.rawIQCaptureEnabled
    diagnosticMissingGates(end+1, 1) = "run_control.raw_iq_capture_enable"; %#ok<AGROW>
end
if ~logical(localGetNested(s, "run_control.save_channel_tensors", false))
    diagnosticMissingGates(end+1, 1) = "run_control.save_channel_tensors"; %#ok<AGROW>
end
if ~logical(localGetNested(s, "run_control.save_constellations", false))
    diagnosticMissingGates(end+1, 1) = "run_control.save_constellations"; %#ok<AGROW>
end
if ~cfg.outputs.saveRawWaveforms
    diagnosticMissingGates(end+1, 1) = "output_control.save_raw_waveforms"; %#ok<AGROW>
end
if ~cfg.outputs.saveChannelSnapshots
    diagnosticMissingGates(end+1, 1) = "output_control.save_channel_snapshots"; %#ok<AGROW>
end
if ~cfg.outputs.saveConstellations
    diagnosticMissingGates(end+1, 1) = "output_control.save_constellations"; %#ok<AGROW>
end
if ~cfg.outputs.savePlots
    diagnosticMissingGates(end+1, 1) = "output_control.save_plots"; %#ok<AGROW>
end
if ~cfg.outputs.saveFigures
    diagnosticMissingGates(end+1, 1) = "output.save_figures"; %#ok<AGROW>
end
if ~cfg.outputs.savePNG
    diagnosticMissingGates(end+1, 1) = "output.save_png"; %#ok<AGROW>
end
cfg.outputs.phySignalDiagnosticRequested = diagnosticRequested;
cfg.outputs.phySignalDiagnosticCaptureReady = diagnosticCaptureReady;
if diagnosticRequested && ~diagnosticCaptureReady
    error("sixgr:lls6g:config:PHYSignalDiagnosticPrerequisites", ...
        "PHY signal diagnostics were requested, but these capture/save gates " + ...
        "are disabled: %s.", strjoin(diagnosticMissingGates, ", "));
end
cfg.outputs.phySignalDiagnosticEnabled = diagnosticRequested;
if ~diagnosticRequested
    cfg.outputs.phySignalDiagnosticUnavailableReason = "capture_not_requested";
else
    cfg.outputs.phySignalDiagnosticUnavailableReason = "";
end
cfg.outputs.phySignalDiagnosticWaveformSamples = double(localGetNested(s, ...
    "output.phy_signal_diagnostic_waveform_samples", 1024));
cfg.outputs.phySignalDiagnosticFFTLength = double(localGetNested(s, ...
    "output.phy_signal_diagnostic_fft_length", 1024));
cfg.outputs.phySignalDiagnosticChannelPoints = double(localGetNested(s, ...
    "output.phy_signal_diagnostic_channel_points", 1024));
cfg.outputs.phySignalDiagnosticConstellationPoints = double(localGetNested(s, ...
    "output.phy_signal_diagnostic_constellation_points", 512));
cfg = sixgr.util.structSet(cfg, "run.rawIQCaptureEnabled", cfg.outputs.rawIQCaptureEnabled);
cfg = sixgr.util.structSet(cfg, "run.rawGridCaptureEnabled", cfg.outputs.rawGridCaptureEnabled);
cfg.outputs.databaseHost = char(string(localResolveDatabaseField(s, "output.database_host", cfg.outputs.storageBackend)));
cfg.outputs.databasePort = double(localResolveDatabaseField(s, "output.database_port", cfg.outputs.storageBackend));
cfg.outputs.databaseSchema = char(string(localResolveDatabaseField(s, "output.database_schema", cfg.outputs.storageBackend)));
timeProfileEnabled = logical(localGetNested(s, "run_control.time_profiling_enable", ...
    localGetNested(s, "analytics.export_time_profile", ...
    localGetNested(s, "output.profiler_enabled", false))));
cfg = sixgr.util.structSet(cfg, "perf.timeProfilingEnabled", timeProfileEnabled);
cfg = sixgr.util.structSet(cfg, "perf.timeProfilingGranularity", ...
    char(string(localGetNested(s, "run_control.time_profiling_granularity", "function"))));
cfg = sixgr.util.structSet(cfg, "perf.exportTimeProfile", logical(localGetNested(s, ...
    "analytics.export_time_profile", timeProfileEnabled)));
cfg = sixgr.util.structSet(cfg, "run.timeProfilingEnabled", timeProfileEnabled);

[profileName, propagationScenario] = localResolveScenarioSemantics(s);
cfg.scenario.id = char(string(s.meta.scenario_id));
cfg.scenario.name = char(profileName);
cfg.scenario.profileName = char(profileName);
cfg.run.scenario = char(propagationScenario);
cfg.scenario.bs.nTxAnt = double(s.mimo.n_tx_ant);
cfg.scenario.bs.txPower_dBm = double(s.energy_efficiency.tx_power_dbm);
bsHeight_m = localResolveFirstFiniteNumeric(s, ...
    ["scenario.bs.height_m", ...
     "scenario.tx.height_m", ...
     "base_station.height_m", ...
     "deployment_topology.bs_height_m"], NaN);
if isfinite(bsHeight_m)
    cfg = sixgr.util.structSet(cfg, "scenario.bs.height_m", double(bsHeight_m));
    cfg = sixgr.util.structSet(cfg, "scenario.tx.height_m", double(bsHeight_m));
end
sectorAzimuths_deg = localGetNested(s, "scenario.sectorization.azimOffsets_deg", ...
    localGetNested(s, "deployment_topology.sector_azimuths_deg", []));
if ~isempty(sectorAzimuths_deg)
    sectorAzimuths_deg = double(sectorAzimuths_deg(:).');
    if any(~isfinite(sectorAzimuths_deg))
        error("sixgr:lls6g:config:InvalidSectorAzimuths", ...
            "scenario.sectorization.azimOffsets_deg must contain finite azimuth values in degrees.");
    end
    cfg = sixgr.util.structSet(cfg, "scenario.sectorization.azimOffsets_deg", sectorAzimuths_deg);
end
geometryArea_m = localGetNested(s, "scenario.geometry.area_m", []);
if ~isempty(geometryArea_m)
    geometryArea_m = double(geometryArea_m(:).');
    if numel(geometryArea_m) ~= 2 || any(~isfinite(geometryArea_m)) || any(geometryArea_m <= 0)
        error("sixgr:lls6g:config:InvalidScenarioArea", ...
            "scenario.geometry.area_m must contain two positive finite dimensions in meters.");
    end
    cfg = sixgr.util.structSet(cfg, "scenario.geometry.area_m", geometryArea_m);
end
cfg.scenario.ue.nRxAnt = double(s.mimo.n_rx_ant);
ueTxAnt = localResolveFirstFiniteNumeric(s, ["scenario.ue.nTxAnt","mimo.ue_n_tx_ant","mimo.n_ue_tx_ant"], NaN);
if ~(isfinite(ueTxAnt) && ueTxAnt >= 1)
    ueTxAnt = min(double(s.mimo.n_rx_ant), double(s.mimo.n_tx_ant));
end
cfg.scenario.ue.nTxAnt = double(max(1, round(ueTxAnt)));
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
minUEDistanceFromBS_m = localResolveFirstFiniteNumeric(s, ...
    ["deployment_topology.min_ue_distance_from_bs_m", ...
     "scenario.ue.distribution.min_bs_dist_m", ...
     "scenario.ue.distribution.minBsDistance_m"], NaN);
maxUEDistanceFromBS_m = localResolveFirstFiniteNumeric(s, ...
    ["deployment_topology.max_ue_distance_from_bs_m", ...
     "deployment_topology.cell_radius_m", ...
     "scenario.ue.distribution.max_bs_dist_m", ...
     "scenario.ue.distribution.maxBsDistance_m"], NaN);
if isfinite(minUEDistanceFromBS_m) && minUEDistanceFromBS_m >= 0
    cfg = sixgr.util.structSet(cfg, "scenario.ue.distribution.min_bs_dist_m", double(minUEDistanceFromBS_m));
    cfg = sixgr.util.structSet(cfg, "scenario.ue.distribution.minBsDistance_m", double(minUEDistanceFromBS_m));
end
if isfinite(maxUEDistanceFromBS_m) && maxUEDistanceFromBS_m > 0
    cfg = sixgr.util.structSet(cfg, "scenario.ue.distribution.max_bs_dist_m", double(maxUEDistanceFromBS_m));
    cfg = sixgr.util.structSet(cfg, "scenario.ue.distribution.maxBsDistance_m", double(maxUEDistanceFromBS_m));
end
if isfinite(minUEDistanceFromBS_m) && isfinite(maxUEDistanceFromBS_m) && ...
        minUEDistanceFromBS_m > maxUEDistanceFromBS_m
    error("sixgr:lls6g:config:InvalidUEDistanceBounds", ...
        "deployment_topology.min_ue_distance_from_bs_m must be <= max_ue_distance_from_bs_m/cell_radius_m.");
end

mobilitySpeedKmh = localResolveFirstFiniteNumeric(s, ...
    ["mobility.ue_speed_kmh","channels.mobility_kmph"], NaN);
if ~isfinite(mobilitySpeedKmh)
    error("sixgr:lls6g:config:MissingResolvedConfigValue", ...
        "Resolved scenario config is missing required value 'mobility.ue_speed_kmh or channels.mobility_kmph'.");
end
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
cfg.scenario.mobility.userPaths = sixgr.lls6g.config.normalizeMobilityUserPaths( ...
    localGetNested(s, "mobility.user_paths", struct([])));
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
% Keep the canonical scenario spellings available to production PHY
% components as well as the legacy camel-case facade.  Both aliases are
% populated from the resolved YAML; neither introduces a MATLAB default.
cfg.frequency.range_name = cfg.phy.frequencyRange;
cfg.frequency.band_name = char(string(localRequireNested( ...
    s, "frequency.band_name", "frequency.band_name")));
cfg.frequency.center_frequency_hz = double(s.frequency.center_frequency_hz);
cfg.frequency.bandwidth_hz = double(s.frequency.bandwidth_hz);
cfg.channel.nTxAnt = double(s.mimo.n_tx_ant);
cfg.channel.nRxAnt = double(s.mimo.n_rx_ant);
cfg.channel.snr_dB = localNumericScalarOrNaN(localGetNested(s, "simulation.snr_db", NaN));
cfg = sixgr.util.structSet(cfg, "run.noiseOperatingMode", char(localResolveNoiseOperatingMode(s)));
dopplerSourceMode = localResolveDopplerSourceMode(s);
resolvedDopplerHz = localResolveChannelDopplerHz(s, mobilitySpeedKmh, dopplerSourceMode);
cfg.channel.dopplerSourceMode = char(dopplerSourceMode);
cfg.channel.dopplerConfigured_Hz = double(localRequireNested(s, "channels.doppler_hz", "channels.doppler_hz"));
cfg.channel.doppler_Hz = double(resolvedDopplerHz);
cfg.channel.dopplerHz = double(resolvedDopplerHz);
cfg.channel.maxDoppler_Hz = double(resolvedDopplerHz);
cfg.channel.maxDopplerHz = double(resolvedDopplerHz);
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
cfg.channel.fading.maxDopplerHz = double(resolvedDopplerHz);
cfg.channel.fading.delaySpread_s = double(s.channels.delay_spread_ns) * 1e-9;
cfg = sixgr.util.structSet(cfg, "channel.pathlossEnabled", logical(s.channels.pathloss_enabled));
cfg = sixgr.util.structSet(cfg, "channel.shadowFadingEnabled", logical(s.channels.shadow_fading_enabled));
cfg = sixgr.util.structSet(cfg, "channel.spatialConsistencyEnabled", logical(s.channels.spatial_consistency_enabled));
cfg = sixgr.util.structSet(cfg, "channel.losEnabled", logical(s.channels.los_enabled));
phase10 = localGetNested(s, "channels.phase10_strict", ...
    localGetNested(s, "channel.phase10_strict", struct()));
cfg = sixgr.util.structSet(cfg, "channel.phase10Strict", phase10);
if isstruct(phase10) && ~isempty(fieldnames(phase10))
    phase10Enabled = logical(localGetNested(phase10, "enabled", false));
    cfg = sixgr.util.structSet(cfg, "channel.phase10Strict.enabled", phase10Enabled);
    cfg = localStructSetIfPresent(cfg, "channel.pathloss.streetWidth_m", ...
        localGetNested(phase10, "pathloss.street_width_m", []));
    cfg = localStructSetIfPresent(cfg, "channel.pathloss.buildingHeight_m", ...
        localGetNested(phase10, "pathloss.building_height_m", []));
    cfg = localStructSetIfPresent(cfg, "channel.oxygenAbsorptionEnabled", ...
        localGetNested(phase10, "oxygen_absorption.enabled", []));
    cfg = localStructSetIfPresent(cfg, "scenario.mobility.seed", ...
        localGetNested(phase10, "ue_drop.seed", []));
    if phase10Enabled
        localValidatePhase10Surface(phase10);
        cfg.channel.complianceMode = "strict_38901";
        cfg.channel.pathloss.model = char(string( ...
            localGetNested(phase10, "pathloss.model", s.channels.pathloss_model)));
        cfg.channel.pathlossModel = cfg.channel.pathloss.model;
        cfg.channel.propagationScenario = char(string( ...
            localGetNested(phase10, "propagation_scenario", propagationScenario)));
    end
end
o2iModel = localResolveO2IModel(localGetNested(s, "channels.o2i_model", ...
    localGetNested(s, "channels.o2i_loss_model", "none")));
cfg = sixgr.util.structSet(cfg, "channel.o2i.model", o2iModel);
cfg = sixgr.util.structSet(cfg, "channel.o2i.enabled", ...
    ~any(lower(strtrim(string(o2iModel))) == ["", "none", "disabled", "off"]));
cfg = localStructSetIfPresent(cfg, "channel.o2i.custom_dB", localGetNested(s, "channels.o2i_loss_db", []));
if isstruct(phase10) && ~isempty(fieldnames(phase10)) && ...
        logical(localGetNested(phase10, "enabled", false))
    phase10O2I = char(string(localGetNested(phase10, "o2i.profile", o2iModel)));
    cfg = sixgr.util.structSet(cfg, "channel.o2i.model", phase10O2I);
    cfg = sixgr.util.structSet(cfg, "channel.o2i.enabled", ...
        logical(localGetNested(phase10, "o2i.enabled", false)));
    cfg = localStructSetIfPresent(cfg, "channel.o2i.indoorDistance_m", ...
        localGetNested(phase10, "o2i.indoor_distance_m", []));
    cfg = localStructSetIfPresent(cfg, "channel.o2i.randomComponentEnabled", ...
        localGetNested(phase10, "o2i.random_component_enabled", []));
    cfg = localStructSetIfPresent(cfg, "channel.o2i.seed", ...
        localGetNested(phase10, "o2i.seed", []));
end
interferenceModelToken = lower(strtrim(string(localGetNested(s, "air_interface.interference_model", "none"))));
cfg = sixgr.util.structSet(cfg, "channel_rf.interferenceEnabled", ...
    ~any(interferenceModelToken == ["", "none", "disabled", "off"]));

channelModel = upper(string(s.channels.model_type));
configuredProfile = upper(string(s.channels.profile));
[profile, profileResolutionSource, profileResolutionReason] = ...
    localResolveChannelProfileForRuntime(s, channelModel, configuredProfile, mobilitySpeedKmh);
if profile ~= configuredProfile
    s.channels.profile = char(profile);
    if isfield(s, "channel_model") && isstruct(s.channel_model)
        s.channel_model.scenario_label = char(profile);
    end
end
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
cfg.channel.configuredDelayProfile = char(configuredProfile);
cfg.channel.profileResolutionSource = char(profileResolutionSource);
cfg.channel.profileResolutionReason = char(profileResolutionReason);

cfg.phy.carrier.SubcarrierSpacing = double(s.frame.scs_khz);
cfg.phy.carrier.SubcarrierSpacing_kHz = double(s.frame.scs_khz);
cfg.phy.carrier.CyclicPrefix = char(string(s.frame.cp_type));
cfg.phy.carrier.NSizeGrid = double(s.frequency.n_size_grid);
scsKHz = double(cfg.phy.carrier.SubcarrierSpacing_kHz);
declaredMu = double(localRequireNested(s, ...
    "global_radio_scope.numerology_mu", ...
    "global_radio_scope.numerology_mu"));
slotsPerFrame = double(localRequireNested(s, ...
    "frame_timing.slots_per_frame", "frame_timing.slots_per_frame"));
slotDuration_ms = double(localRequireNested(s, ...
    "frame_timing.slot_duration_ms", "frame_timing.slot_duration_ms"));
symbolsPerSlot = double(localRequireNested(s, ...
    "frame_timing.symbols_per_slot", "frame_timing.symbols_per_slot"));
cfg = sixgr.util.structSet(cfg, "phy.numerology.mu", declaredMu);
cfg = sixgr.util.structSet(cfg, "phy.numerology.scs_kHz", double(scsKHz));
cfg = sixgr.util.structSet(cfg, "phy.numerology.slotsPerFrame", double(slotsPerFrame));
cfg = sixgr.util.structSet(cfg, "phy.numerology.slotDuration_ms", double(slotDuration_ms));
cfg = sixgr.util.structSet(cfg, "phy.numerology.symbolsPerSlot", ...
    symbolsPerSlot);
cfg = sixgr.util.structSet(cfg, "frame_timing.slots_per_frame", double(slotsPerFrame));
cfg = sixgr.util.structSet(cfg, "frame_timing.slot_duration_ms", double(slotDuration_ms));
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridNumRBs", double(cfg.phy.carrier.NSizeGrid));
cfg = sixgr.util.structSet(cfg, "phy.numerology.configuredGridNumRBs", double(s.frequency.n_size_grid));
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridSource", "pending_canonical_carrier_resolution");
cfg = sixgr.util.structSet(cfg, "phy.numerology.numerologySource", ...
    "declared_scenario_pending_canonical_validation");
cfg = sixgr.util.structSet(cfg, "phy.numerology.timingInterpretationSource", ...
    "declared_scenario_pending_canonical_validation");
cfg.phy.duplex.mode = upper(char(string(s.frequency.duplex_mode)));
if strcmpi(cfg.phy.duplex.mode, "TDD")
    tddCommon = localGetNested(s, "frame.tdd_common", []);
    if ~(isstruct(tddCommon) && isscalar(tddCommon) && ...
            ~isempty(fieldnames(tddCommon)))
        error("sixgr:phy:frame:MissingTDDCommonConfig", ...
            "frame.tdd_common is required for TDD scenarios; compact S-slot " + ...
            "patterns and implicit special-slot splits are not resolved.");
    end
    cfg = sixgr.util.structSet(cfg, "phy.duplex.tddCommon", tddCommon);
    tddDedicated = localGetNested(s, "frame.tdd_dedicated", struct([]));
    if ~isempty(tddDedicated)
        cfg = sixgr.util.structSet(cfg, ...
            "phy.duplex.tddDedicated", tddDedicated);
    end
elseif strcmpi(cfg.phy.duplex.mode, "FDD")
    dlCenterFrequencyHz = double(localRequireNested(s, ...
        "frequency.dl_center_frequency_hz", ...
        "frequency.dl_center_frequency_hz"));
    ulCenterFrequencyHz = double(localRequireNested(s, ...
        "frequency.ul_center_frequency_hz", ...
        "frequency.ul_center_frequency_hz"));
    if ~(isscalar(dlCenterFrequencyHz) && ...
            isfinite(dlCenterFrequencyHz) && ...
            dlCenterFrequencyHz > 0 && ...
            isscalar(ulCenterFrequencyHz) && ...
            isfinite(ulCenterFrequencyHz) && ...
            ulCenterFrequencyHz > 0 && ...
            dlCenterFrequencyHz ~= ulCenterFrequencyHz)
        error("sixgr:phy:frame:FDDRequiresSeparateFrequencies", ...
            "FDD scenarios require distinct, explicit, positive DL and UL center frequencies.");
    end
    cfg = sixgr.util.structSet(cfg, ...
        "phy.duplex.fdd.dlCenterFrequencyHz", dlCenterFrequencyHz);
    cfg = sixgr.util.structSet(cfg, ...
        "phy.duplex.fdd.ulCenterFrequencyHz", ulCenterFrequencyHz);
else
    error("sixgr:config:BadEnum", ...
        "frequency.duplex_mode must resolve to TDD or FDD.");
end
cfg.phy.waveform.dl = char(string(s.waveform.dl_waveform));
cfg.phy.waveform.ul = char(string(s.waveform.ul_waveform));
cfg = sixgr.util.structSet(cfg, "phy.waveform.windowingEnabled", logical(s.waveform.windowing_enabled));
windowingPercent = double(localGetNested(s, "waveform.windowing_percent", 0));
cfg = sixgr.util.structSet(cfg, "phy.waveform.windowingPercent", windowingPercent);
cfg = sixgr.util.structSet(cfg, "phy.waveform.ofdmWindowingPercent", windowingPercent);
cfg = sixgr.util.structSet(cfg, "phy.ofdm.windowingPercent", windowingPercent);
cfg = sixgr.util.structSet(cfg, "phy.waveform.experimentalDLDftsOfdmEnabled", ...
    logical(s.waveform.experimental_dl_dfts_ofdm_enabled));
cfg = sixgr.util.structSet(cfg, "phy.channelEstimation.method", char(string(localGetNested(s, ...
    "phy.channelEstimation.method", localGetNested(s, "receiver_algorithms.channel_estimation_method", "LS")))));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.ptrs.enableCPECorrection", logical(localGetNested(s, ...
    "phy.pdsch.ptrs.enableCPECorrection", true)));

cfg.phy.ssb.enable = logical(s.reference_signals.ssb_enabled);
cfg = sixgr.util.structSet(cfg, "phy.ssb.blockPattern", ...
    char(string(localRequireNested(s, ...
    "reference_signals.ssb_case", "reference_signals.ssb_case"))));
cfg = sixgr.util.structSet(cfg, "phy.ssb.Lmax", ...
    double(localRequireNested(s, ...
    "reference_signals.ssb_lmax", "reference_signals.ssb_lmax")));
cfg = sixgr.util.structSet(cfg, "phy.ssb.nBeams", double(sixgr.util.structGet(cfg, "phy.ssb.Lmax", 8)));
configuredSSBBeamCount = double(localGetNested(s, "reference_signals.ssb_beam_count", ...
    sixgr.util.structGet(cfg, "phy.ssb.nBeams", sixgr.util.structGet(cfg, "phy.ssb.Lmax", 8))));
cfg = sixgr.util.structSet(cfg, ...
    "phy.ssb.beamCount", configuredSSBBeamCount);
cfg = sixgr.util.structSet(cfg, ...
    "phy.ssb.nBeams", configuredSSBBeamCount);
cfg = sixgr.util.structSet(cfg, "phy.ssb.scs_kHz", ...
    double(localRequireNested(s, ...
    "reference_signals.ssb_scs_khz", ...
    "reference_signals.ssb_scs_khz")));
cfg.phy.pbch.enable = logical(s.reference_signals.pbch_enabled);
cfg.phy.mib.enable = logical(s.reference_signals.pbch_enabled);
ssbPeriodSlots = localResolvePeriodSlotsFromMsOrSlots(s, runTiming, ...
    ["reference_signals.ssb_periodicity_slots","reference_signals.ssb.periodicity_slots","phy.ssb.period_slots"], ...
    ["reference_signals.ssb_periodicity_ms","reference_signals.ssb.periodicity_ms"], NaN);
if isfinite(ssbPeriodSlots) && ssbPeriodSlots >= 1
    cfg = sixgr.util.structSet(cfg, "phy.ssb.period_slots", double(ssbPeriodSlots));
    cfg = sixgr.util.structSet(cfg, "phy.pbch.period_slots", double(ssbPeriodSlots));
end
cfg.phy.sib1.enable = logical(localGetNested(s, "phy.sib1.enable", ...
    localGetNested(s, "initial_access.sib1.enabled", ...
    localGetNested(s, "signals_and_channels_common.sib1_related_pdcch.enable_flag", false) && ...
    localGetNested(s, "signals_and_channels_common.sib1_related_pdsch.enable_flag", false))));
initialAccess = localGetNested(s, "initial_access", struct());
if builtin("isstruct", initialAccess) && ~isempty(fieldnames(initialAccess))
    cfg = sixgr.util.structSet(cfg, "initial_access", initialAccess);
    cfg = localStructSetIfPresent(cfg, "phy.ssb.periodicity_ms", ...
        localGetNested(initialAccess, "ssb.periodicity_ms", []));
    cfg = localStructSetIfPresent(cfg, "phy.ssb.positionsInBurst", ...
        localGetNested(initialAccess, "ssb.positions_in_burst", []));
    cfg = localStructSetIfPresent(cfg, "phy.ssb.perSSBPower_dB", ...
        localGetNested(initialAccess, "ssb.per_ssb_power_db", []));
    cfg = localStructSetIfPresent(cfg, "phy.ssb.precoderIDs", ...
        localGetNested(initialAccess, "ssb.precoder_ids", []));
    cfg = localStructSetIfPresent(cfg, "phy.ssb.KSSB", ...
        localGetNested(initialAccess, "ssb.k_ssb", []));
    cfg = localStructSetIfPresent(cfg, "phy.ssb.NCRBSSB", ...
        localGetNested(initialAccess, "ssb.n_crb_ssb", []));
    cfg = localStructSetIfPresent(cfg, "phy.ssb.runtimeSSBIndex", ...
        localGetNested(initialAccess, "ssb.selected_ssb_index", []));
    cfg = localStructSetIfPresent(cfg, "phy.sib1.ssbObservationSubframes", ...
        localGetNested(initialAccess, "ssb.observation_subframes", []));
    cfg = localStructSetIfPresent(cfg, "phy.mib.pdcchConfigSIB1", ...
        localGetNested(initialAccess, "mib.pdcch_config_sib1", []));
    cfg = localStructSetIfPresent(cfg, "phy.mib.dmrsTypeAPosition", ...
        localGetNested(initialAccess, "mib.dmrs_type_a_position", []));
    cfg = localStructSetIfPresent(cfg, "validation.sib1.siRNTI", ...
        localGetNested(initialAccess, "sib1.si_rnti", []));
end

cfg.phy.pdcch.enable = logical(s.control.pdcch_enabled);
cfg.phy.pdcch.searchSpaceType = char(localNormalizePDCCHSearchSpaceType(s.control.search_space_type));
cfg.phy.pdcch.aggregationLevels = double(s.control.aggregation_levels);
cfg.phy.pdcch.aggregationLevel = double(localResolveDefaultPDCCHAggregationLevel(s.control.aggregation_levels));
cfg.phy.pdcch.candidateAggregationLevels = double(localGetNested(s, "control.candidate_aggregation_levels", cfg.phy.pdcch.aggregationLevels));
cfg.phy.pdcch.aggregationSelectionPolicy = char(string(localGetNested(s, "control.aggregation_selection_policy", "snr_threshold")));
cfg.phy.pdcch.schedulerAggregationLevel = double(localGetNested(s, "control.scheduler_aggregation_level", NaN));
cfg.phy.pdcch.dciFormats = cellstr(string(s.control.dci_formats(:)));
cfg.phy.pdcch.dciFormat = char(string(localFirstValue(s.control.dci_formats)));
cfg.phy.pdcch.operatorControl = s.control;
cfg.phy.pdcch.configuredPayloadBits = double(localGetNested(s, "control.pdcch_payload_bits", NaN));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.blindDecodeCandidates", double(s.control.blind_decode_candidates));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.duration", double(s.control.coreset_duration));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.frequencyResources", double(s.control.coreset_frequency_resources));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.numCandidates", double(s.control.search_space_num_candidates));
strictControl = localGetNested(s, "control.pdcch_strict", struct());
if isstruct(strictControl) && isfield(strictControl, "dci_context")
    formats = string(s.control.dci_formats(:));
    contextData = cell(numel(formats), 1);
    contextDigests = strings(numel(formats), 1);
    payloadSizes = zeros(numel(formats), 1);
    for contextIndex = 1:numel(formats)
        dciContext = sixgr.phy.pdcch.DCIContextFactory.fromOperatorControl( ...
            s.control, formats(contextIndex));
        contextData{contextIndex} = dciContext.Data;
        contextDigests(contextIndex) = dciContext.Digest;
        aligned = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(dciContext);
        payloadSizes(contextIndex) = aligned.Selected.AlignedBits;
    end
    cfg.phy.pdcch.dciContextData = contextData;
    cfg.phy.pdcch.dciContextDigests = contextDigests;
    cfg.phy.pdcch.dciPayloadSizesByFormat = payloadSizes;
    cfg.phy.pdcch.dciPayloadBits = payloadSizes(1);
    cfg.phy.pdcch.KBits = payloadSizes(1);
    cfg.phy.pdcch.payloadSizeSource = "contextual_release18_schema";
end

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
cfg.ctrl6gr.PayloadLengthBits = double(localGetNested(s, ...
    "control.pdcch6gr.payload_length_bits", ...
    sixgr.util.structGet(cfg, "phy.pdcch.dciPayloadBits", ...
    localGetNested(s, "control.pdcch_payload_bits", 64))));
cfg.ctrl6gr.Modulation = char(string(localGetNested(s, "control.pdcch6gr.modulation", "QPSK")));
cfg.ctrl6gr.CRCPolynomial = char(string(localGetNested(s, "control.pdcch6gr.crc_polynomial", "24C")));
cfg.ctrl6gr.CRCScramblingEnabled = logical(localGetNested(s, "control.pdcch6gr.crc_scrambling_enabled", true));
cfg.ctrl6gr.PayloadScramblingEnabled = logical(localGetNested(s, "control.pdcch6gr.payload_scrambling_enabled", true));
cfg.ctrl6gr.PayloadSequenceInit = double(localGetNested(s, "control.pdcch6gr.payload_sequence_init", cfg.phy.carrier.NCellID));
cfg.ctrl6gr.PDCCHScramblingID = double(localGetNested(s, "control.pdcch6gr.pdcch_scrambling_id", ...
    localGetNested(s, "control.pdcch6gr.coreset_scrambling_id", cfg.ctrl6gr.PayloadSequenceInit)));
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
cfg.pdsch6gr.MCSUECapability1024QAM = logical(localGetNested(s, "pdsch6gr.mcs_ue_capability_1024qam", []));
cfg.pdsch6gr.MCSRRCEnabled1024QAM = logical(localGetNested(s, "pdsch6gr.mcs_rrc_enabled_1024qam", []));
cfg.pdsch6gr.MCSDCIEnabled1024QAM = logical(localGetNested(s, "pdsch6gr.mcs_dci_enabled_1024qam", []));
cfg.pdsch6gr.MCSDeploymentAllows1024QAM = logical(localGetNested(s, "pdsch6gr.mcs_deployment_allows_1024qam", []));
cfg.pdsch6gr.MCSFrequencyRange = char(string(localGetNested(s, "pdsch6gr.mcs_frequency_range", "")));
cfg.pdsch6gr.MCSOperatingBand = char(string(localGetNested(s, "pdsch6gr.mcs_operating_band", "")));
cfg.pdsch6gr.MCSDeploymentClass = char(string(localGetNested(s, "pdsch6gr.mcs_deployment_class", "")));
cfg.pdsch6gr.MCSFrequencyRangeAllows1024QAM = logical(localGetNested(s, "pdsch6gr.mcs_frequency_range_allows_1024qam", []));
cfg.pdsch6gr.MCSBandAllows1024QAM = logical(localGetNested(s, "pdsch6gr.mcs_band_allows_1024qam", []));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsContext", struct( ...
    "UECapability1024QAM", cfg.pdsch6gr.MCSUECapability1024QAM, ...
    "RRCEnabled1024QAM", cfg.pdsch6gr.MCSRRCEnabled1024QAM, ...
    "DCIEnabled1024QAM", cfg.pdsch6gr.MCSDCIEnabled1024QAM, ...
    "DeploymentAllows1024QAM", cfg.pdsch6gr.MCSDeploymentAllows1024QAM, ...
    "FrequencyRange", cfg.pdsch6gr.MCSFrequencyRange, ...
    "OperatingBand", cfg.pdsch6gr.MCSOperatingBand, ...
    "DeploymentClass", cfg.pdsch6gr.MCSDeploymentClass, ...
    "FrequencyRangeAllows1024QAM", cfg.pdsch6gr.MCSFrequencyRangeAllows1024QAM, ...
    "BandAllows1024QAM", cfg.pdsch6gr.MCSBandAllows1024QAM));
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
cfg.pdsch6gr.PTRSPortSet = double(localGetNested(s, "pdsch6gr.ptrs_port_set", []));
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
dlConfiguredMCSIndex = localNumericScalarOrNaN(localGetNested(s, ...
    "modulation_and_mapping.dl_mcs_index", localGetNested(s, "modulation.dl_mcs_index", NaN)));
ulConfiguredMCSIndex = localNumericScalarOrNaN(localGetNested(s, ...
    "modulation_and_mapping.ul_mcs_index", localGetNested(s, "modulation.ul_mcs_index", NaN)));
dlMCSTable = localResolveDirectionalMCSTable(s, "DL");
ulMCSTable = localResolveDirectionalMCSTable(s, "UL");
dlLayerCount = localNumericScalarOrNaN(localGetNested(s, "mimo.max_dl_layers", s.mimo.n_layers));
if ~(isfinite(dlLayerCount) && dlLayerCount >= 1)
    dlLayerCount = max(1, round(double(s.mimo.n_layers)));
else
    dlLayerCount = max(1, round(double(dlLayerCount)));
end
ulLayerCount = localNumericScalarOrNaN(localGetNested(s, "mimo.max_ul_layers", s.mimo.n_layers));
if ~(isfinite(ulLayerCount) && ulLayerCount >= 1)
    ulLayerCount = max(1, round(double(s.mimo.n_layers)));
else
    ulLayerCount = max(1, round(double(ulLayerCount)));
end
cfg.phy.pdsch.enable = any(ismember(targetCases, localCatalogStringList(catalog.value_maps.target_case_groups.pdsch_enable)));
cfg.phy.pdsch.nLayers = double(dlLayerCount);
cfg.phy.pdsch.numLayers = double(dlLayerCount);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.maxLayers", double(dlLayerCount));
cfg = sixgr.util.structSet(cfg, "phy.maxDLLayers", double(dlLayerCount));
cfg.phy.pdsch.enablePTRS = logical(s.reference_signals.ptrs_enabled);
cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = double(s.reference_signals.pdsch_dmrs_num_cdm_groups_without_data);
cfg.phy.pdsch.dmrs.typeApos = double(s.reference_signals.pdsch_dmrs_type_a_position);
cfg.phy.pdsch.dmrs.configType = double(s.reference_signals.pdsch_dmrs_config_type);
cfg.phy.pdsch.dmrs.additionalPositions = double(localGetNested(s, "reference_signals.pdsch_dmrs_additional_positions", 0));
cfg.phy.pdsch.dmrs.maxLength = double(localGetNested(s, "reference_signals.pdsch_dmrs_max_length", 1));
cfg.phy.pdsch.configuredMCSIndex = dlConfiguredMCSIndex;
cfg.phy.pdsch.mcsIndex = dlConfiguredMCSIndex;
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", char(dlMCSTable));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.dmrs.nPorts", double(s.reference_signals.pdsch_dmrs_ports));

cfg.phy.csirs.enable = logical(s.reference_signals.csi_rs_enabled);
cfg.phy.csirs.nPorts = double(s.reference_signals.pdsch_dmrs_ports);
cfg.phy.csirs.scramblingID = double(localGetNested(s, "reference_signals.csirs_scrambling_id", ...
    localGetNested(s, "reference_signals.csi_rs_scrambling_id", cfg.phy.carrier.NCellID)));
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
csiAcquisitionMode = string(localGetNested(s, "reference_signals.csi_acquisition_mode", ""));
operationOrientation = string(localGetNested(s, "reference_signals.operation_orientation", ""));
cfg = sixgr.util.structSet(cfg, "phy.csi.acquisitionMode", char(csiAcquisitionMode));
cfg = sixgr.util.structSet(cfg, "phy.csi.operationOrientation", char(operationOrientation));
cfg = sixgr.util.structSet(cfg, "referenceSignals.csiAcquisitionMode", char(csiAcquisitionMode));
cfg = sixgr.util.structSet(cfg, "referenceSignals.operationOrientation", char(operationOrientation));
cfg = sixgr.util.structSet(cfg, "reference_signals.csi_acquisition_mode", char(csiAcquisitionMode));
cfg = sixgr.util.structSet(cfg, "reference_signals.operation_orientation", char(operationOrientation));
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
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", char(localNormalizeCoreCodebookType(s.mimo.codebook_type)));
cqiTableToken = char(localResolveCQITableToken(s));
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", cqiTableToken);
cfg = sixgr.util.structSet(cfg, "phy.csi.dlCQITable", cqiTableToken);
cfg = sixgr.util.structSet(cfg, "phy.csi.ulCQITable", cqiTableToken);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.cqiTable", cqiTableToken);
cfg = sixgr.util.structSet(cfg, "phy.pusch.cqiTable", cqiTableToken);
maxTrustedReferenceSINR = double(localGetNested(s, "csi_acquisition_and_reporting.max_trusted_reference_sinr_db", ...
    localGetNested(s, "csi_acquisition_and_reporting.maxTrustedReferenceSINR_dB", ...
    localGetNested(s, "reference_signals.max_trusted_reference_sinr_db", NaN))));
if isfinite(maxTrustedReferenceSINR) && maxTrustedReferenceSINR > 0
    cfg = sixgr.util.structSet(cfg, "phy.csi.maxTrustedReferenceSINR_dB", double(maxTrustedReferenceSINR));
end
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
eesmBetaByMCS_dB = double(localGetNested(s, "csi_acquisition_and_reporting.eesm_beta_by_mcs_db", ...
    localGetNested(s, "link_adaptation.eesm_beta_by_mcs_db", [])));
if ~isempty(eesmBetaByMCS_dB)
    eesmBetaByMCS_dB = reshape(double(eesmBetaByMCS_dB), 1, []);
    cfg = sixgr.util.structSet(cfg, "phy.csi.eesmBetaByMCS_dB", eesmBetaByMCS_dB);
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.eesmBetaByMCS_dB", eesmBetaByMCS_dB);
    cfg = sixgr.util.structSet(cfg, "phy.pusch.eesmBetaByMCS_dB", eesmBetaByMCS_dB);
end
eesmBetaMCSIndex = double(localGetNested(s, "csi_acquisition_and_reporting.eesm_beta_mcs_index", ...
    localGetNested(s, "link_adaptation.eesm_beta_mcs_index", [])));
if ~isempty(eesmBetaMCSIndex)
    eesmBetaMCSIndex = reshape(double(eesmBetaMCSIndex), 1, []);
    cfg = sixgr.util.structSet(cfg, "phy.csi.eesmBetaMCSIndex", eesmBetaMCSIndex);
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.eesmBetaMCSIndex", eesmBetaMCSIndex);
    cfg = sixgr.util.structSet(cfg, "phy.pusch.eesmBetaMCSIndex", eesmBetaMCSIndex);
end
targetBLER = double(localGetNested(s, "csi_acquisition_and_reporting.target_bler", ...
    localGetNested(s, "link_adaptation.target_bler", NaN)));
if isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1
    cfg = sixgr.util.structSet(cfg, "phy.csi.targetBLER", double(targetBLER));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.targetBLER", double(targetBLER));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.targetBLER", double(targetBLER));
end
targetBLERDL = double(localGetNested(s, "csi_acquisition_and_reporting.target_bler_dl", ...
    localGetNested(s, "link_adaptation.target_bler_dl", targetBLER)));
if isfinite(targetBLERDL) && targetBLERDL > 0 && targetBLERDL < 1
    cfg = sixgr.util.structSet(cfg, "phy.csi.dlTargetBLER", double(targetBLERDL));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.targetBLER", double(targetBLERDL));
end
targetBLERUL = double(localGetNested(s, "csi_acquisition_and_reporting.target_bler_ul", ...
    localGetNested(s, "link_adaptation.target_bler_ul", targetBLER)));
if isfinite(targetBLERUL) && targetBLERUL > 0 && targetBLERUL < 1
    cfg = sixgr.util.structSet(cfg, "phy.csi.ulTargetBLER", double(targetBLERUL));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.targetBLER", double(targetBLERUL));
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
cfg = localApplyPhase07MIMOConfig(cfg,s);

cfg.phy.pucch.enable = logical(s.control.pucch_enabled);
cfg.phy.pucch.calibrationFormatHint = double(s.control.pucch_format);
cfg.phy.pucch.assignmentMode = "rrc_procedure_state";

cfg.phy.pusch.enable = any(ismember(targetCases, localCatalogStringList(catalog.value_maps.target_case_groups.pusch_enable)));
cfg.phy.pusch.nLayers = double(ulLayerCount);
cfg.phy.pusch.numLayers = double(ulLayerCount);
cfg = sixgr.util.structSet(cfg, "phy.pusch.maxLayers", double(ulLayerCount));
cfg = sixgr.util.structSet(cfg, "phy.maxULLayers", double(ulLayerCount));
cfg.phy.pusch.transformPrecoding = logical(s.waveform.transform_precoding_enabled);
cfg.phy.pusch.enablePTRS = logical(s.reference_signals.ptrs_enabled);
cfg.phy.pusch.configuredMCSIndex = ulConfiguredMCSIndex;
cfg.phy.pusch.mcsIndex = ulConfiguredMCSIndex;
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsTable", char(ulMCSTable));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.nPorts", double(s.reference_signals.pusch_dmrs_ports));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.typeApos", double(localGetNested(s, "reference_signals.pusch_dmrs_type_a_position", 2)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.configType", double(localGetNested(s, "reference_signals.pusch_dmrs_config_type", ...
    localGetNested(s, "reference_signals.pdsch_dmrs_config_type", 1))));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.additionalPositions", double(localGetNested(s, "reference_signals.pusch_dmrs_additional_positions", 0)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.maxLength", double(localGetNested(s, "reference_signals.pusch_dmrs_max_length", ...
    localGetNested(s, "reference_signals.pdsch_dmrs_max_length", 1))));
ulCodebookEnabled = ~logical(s.waveform.transform_precoding_enabled) && reportPMI && ...
    pmiCodebookMode ~= "noncodebook" && lower(string(s.mimo.codebook_type)) ~= "noncodebook";
if ulCodebookEnabled
    ulNumPorts = double(localGetNested(s, "reference_signals.pusch_dmrs_ports", ...
        localGetNested(s, "mimo.n_tx_ant", double(ulLayerCount))));
    allowedPorts = [1 2 4];
    if ~(isfinite(ulNumPorts) && ulNumPorts >= double(ulLayerCount))
        ulNumPorts = double(ulLayerCount);
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
powerControlEnabled = logical(localGetNested(s, "power_control.ul_open_loop_enable", false)) || ...
    logical(localGetNested(s, "power_control.f_closed_loop_enable", false));
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.enabled", powerControlEnabled);
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.open_loop_enabled", ...
    logical(localGetNested(s, "power_control.ul_open_loop_enable", false)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.closed_loop_enabled", ...
    logical(localGetNested(s, "power_control.f_closed_loop_enable", false)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.p0_pusch_dbm", ...
    double(localGetNested(s, "power_control.p0_pusch_dBm", -80)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.alpha", ...
    double(localGetNested(s, "power_control.alpha_pusch", 0.8)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.delta_tf_db", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.closed_loop_accumulation_db", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.tpc_command_bits", ...
    double(localGetNested(s, "power_control.tpc_command_bits", 0)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.power_control.phr_report_enabled", ...
    logical(localGetNested(s, "power_control.phr_report_enable", false)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.enabled", powerControlEnabled);
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.openLoopEnabled", ...
    logical(localGetNested(s, "power_control.ul_open_loop_enable", false)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.closedLoopEnabled", ...
    logical(localGetNested(s, "power_control.f_closed_loop_enable", false)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.p0PUSCH_dBm", ...
    double(localGetNested(s, "power_control.p0_pusch_dBm", -80)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.alpha", ...
    double(localGetNested(s, "power_control.alpha_pusch", 0.8)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.deltaTF_dB", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.closedLoopAccumulation_dB", 0);
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.tpcCommandBits", ...
    double(localGetNested(s, "power_control.tpc_command_bits", 0)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.phrReportEnabled", ...
    logical(localGetNested(s, "power_control.phr_report_enable", false)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.powerControl.pcmax_dBm", ...
    double(localGetNested(s, "power_control.pcmax_dBm", localGetNested(s, "power_control.ue_max_power_dBm", 23))));
cfg = sixgr.util.structSet(cfg, "powerAndRF.puschPowerControlEnabled", powerControlEnabled);
cfg = sixgr.util.structSet(cfg, "powerAndRF.uePcmax_dBm", ...
    double(localGetNested(s, "power_control.pcmax_dBm", localGetNested(s, "power_control.ue_max_power_dBm", 23))));
cfg = sixgr.util.structSet(cfg, "powerAndRF.referenceTxPower_dBm", ...
    double(localGetNested(s, "power_control.ue_max_power_dBm", localGetNested(s, "power_control.pcmax_dBm", 23))));

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
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals.srs", localGetNested(s, "reference_signals.srs", struct()));
cfg = localStructSetIfPresent(cfg, "phy.srs.resourceType", localGetNested(s, "reference_signals.srs.resource_type", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.resourceSetUsage", localGetNested(s, "reference_signals.srs.resource_set_usage", []));
srsSlotNumbers = localGetNested(s, "reference_signals.srs.slot_numbers", []);
srsSlotWithinPeriod = localGetNested(s, "reference_signals.srs_slot_within_period", []);
cfg = localStructSetIfPresent(cfg, "phy.srs.slotNumbers", srsSlotNumbers);
cfg = localStructSetIfPresent(cfg, "phy.srs.slotWithinPeriod1Based", srsSlotWithinPeriod);
cfg = localStructSetIfPresent(cfg, "phy.srs.period_offset", localGetNested(s, "reference_signals.srs.period_offset", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.SymbolStart", localGetNested(s, "reference_signals.srs.symbol_start", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.NumSRSSymbols", localGetNested(s, "reference_signals.srs.num_srs_symbols", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.Repetition", localGetNested(s, "reference_signals.srs.repetition_factor", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.KTC", localGetNested(s, "reference_signals.srs.comb_number", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.KBarTC", localGetNested(s, "reference_signals.srs.comb_offset", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.CyclicShift", localGetNested(s, "reference_signals.srs.cyclic_shift", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.NSRSID", localGetNested(s, "reference_signals.srs.sequence_id", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.GroupSeqHopping", localGetNested(s, "reference_signals.srs.group_or_sequence_hopping", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.FrequencyStart", localGetNested(s, "reference_signals.srs.frequency_position", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.FrequencyShift", localGetNested(s, "reference_signals.srs.frequency_shift", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.FrequencyHopping", localGetNested(s, "reference_signals.srs.frequency_hopping", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.BHop", localGetNested(s, "reference_signals.srs.b_hop", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.CSRS", localGetNested(s, "reference_signals.srs.c_srs", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.BSRS", localGetNested(s, "reference_signals.srs.b_srs", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.bandwidthRB", localGetNested(s, "reference_signals.srs.num_rb", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.coverageRequirement", localGetNested(s, "reference_signals.srs.coverage_requirement", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.fullCarrierSoundingRequired", localGetNested(s, "reference_signals.srs.full_carrier_sounding_required", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.detectionThreshold", localGetNested(s, "reference_signals.srs.detection_threshold", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.channelNMSEThresholddB", localGetNested(s, "reference_signals.srs.channel_nmse_threshold_db", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.timingToleranceSamples", localGetNested(s, "reference_signals.srs.timing_tolerance_samples", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.dciTriggerReferenceId", localGetNested(s, "reference_signals.srs.dci_trigger_reference_id", []));
cfg = localStructSetIfPresent(cfg, "phy.srs.activationMACCEReferenceId", localGetNested(s, "reference_signals.srs.activation_mac_ce_reference_id", []));
cfg = sixgr.util.structSet(cfg, "phy.srs.strictEvidenceRequired", runnerProfile == "srs_strict_validation" || any(targetCases == "srs"));
cfg = sixgr.util.structSet(cfg, "phy.trs.enable", logical(s.reference_signals.trs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trs.nPorts", double(localRequireNested(s, "reference_signals.trs.num_ports", "reference_signals.trs.num_ports")));
cfg = sixgr.util.structSet(cfg, "phy.trs.scramblingID", double(localRequireNested(s, "reference_signals.trs.scrambling_id", "reference_signals.trs.scrambling_id")));
cfg = localStructSetIfPresent(cfg, "phy.trs.csirsRowNumber", localGetNested(s, "reference_signals.trs.row_number", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.symbolLocation", localGetNested(s, "reference_signals.trs.symbol_location", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.subcarrierLocation", localGetNested(s, "reference_signals.trs.subcarrier_location", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.rbOffset", localGetNested(s, "reference_signals.trs.rb_offset", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.numRB", localGetNested(s, "reference_signals.trs.num_rb", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.slotNumbers", localGetNested(s, "reference_signals.trs.slot_numbers", []));
trsPeriodSlots = localResolvePeriodSlotsFromMsOrSlots(s, runTiming, ...
    ["reference_signals.trs_periodicity_slots","reference_signals.trs.periodicity_slots","control_gating.trs_period_slots","phy.trs.period_slots"], ...
    ["reference_signals.trs_periodicity_ms","reference_signals.trs.periodicity_ms"], NaN);
if isfinite(trsPeriodSlots) && trsPeriodSlots >= 1
    cfg = sixgr.util.structSet(cfg, "phy.trs.period_slots", double(trsPeriodSlots));
end
cfg = localStructSetIfPresent(cfg, "phy.trs.detectionThreshold", localGetNested(s, "reference_signals.trs.detection_threshold", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.minCoverageRatio", localGetNested(s, "reference_signals.trs.min_coverage_ratio", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.timingToleranceSamples", localGetNested(s, "reference_signals.trs.timing_tolerance_samples", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.frequencyToleranceHz", localGetNested(s, "reference_signals.trs.frequency_tolerance_hz", []));
cfg = localStructSetIfPresent(cfg, "phy.trs.channelNMSEThresholddB", localGetNested(s, "reference_signals.trs.channel_nmse_threshold_db", []));
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals.trs", localGetNested(s, "reference_signals.trs", struct()));
cfg = sixgr.util.structSet(cfg, "phy.ptrs.enable", logical(s.reference_signals.ptrs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trackingRS.enable", logical(s.reference_signals.tracking_rs_enabled));
cfg = localInstallRSLAStrictConfig(cfg,s);

cfg.random_access = s.random_access;
cfg.phy.prach.enable = logical(s.random_access.enabled);
cfg.phy.prach.preambleFormat = char(string(localGetNested(s, "random_access.prach_format", "")));
cfg = sixgr.util.structSet(cfg, "phy.prach.preambleCount", double(s.random_access.preamble_count));
cfg.phy.prach.configurationIndex = double(s.random_access.configuration_index);
cfg.phy.prach.subcarrierSpacing_kHz = double(s.random_access.subcarrier_spacing_khz);
cfg.phy.prach.rootSeqIndex = double(s.random_access.root_sequence_index);
cfg = localStructSetIfPresent(cfg, "phy.carrier.NCellID", localGetNested(s, "random_access.n_cell_id", []));
cfg.phy.prach.zeroCorrelationZone = double(s.random_access.zero_correlation_zone);
cfg.phy.prach.preambleIndex = double(s.random_access.preamble_index);
cfg = localStructSetIfPresent(cfg, "phy.prach.sequenceIndex", localGetNested(s, "random_access.sequence_index", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.logicalRootSequenceIndex", localGetNested(s, "random_access.logical_root_sequence_index", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.restrictedSet", localGetNested(s, "random_access.restricted_set", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.frequencyStart", localGetNested(s, "random_access.frequency_start", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.detectionThreshold", localGetNested(s, "random_access.detection_threshold", []));
cfg = localStructSetIfPresent(cfg, "phy.prach.falseAlarmCandidateScope", localGetNested(s, "random_access.false_alarm_candidate_scope", []));
prachPeriodSlots = localResolvePeriodSlotsFromMsOrSlots(s, runTiming, ...
    ["random_access.prach_periodicity_slots","random_access.periodicity_slots","phy.prach.period_slots"], ...
    ["random_access.prach_periodicity_ms","random_access.periodicity_ms"], NaN);
if isfinite(prachPeriodSlots) && prachPeriodSlots >= 1
    cfg = sixgr.util.structSet(cfg, "phy.prach.period_slots", double(prachPeriodSlots));
end
cfg = localStructSetIfPresent(cfg, "prach_lls.FrequencyRange", localGetNested(s, "random_access.frequency_range", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DuplexMode", localGetNested(s, "frequency.duplex_mode", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.CarrierFrequencyHz", localGetNested(s, "frequency.center_frequency_hz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.CarrierSCSkHz", localGetNested(s, "frame.scs_khz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NSizeGrid", localGetNested(s, "frequency.n_size_grid", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PRACHConfigurationIndex", localGetNested(s, "random_access.configuration_index", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PRACHFormat", localGetNested(s, "random_access.prach_format", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.PRACHSubcarrierSpacing", localGetNested(s, "random_access.subcarrier_spacing_khz", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.SequenceIndex", localGetNested(s, "random_access.sequence_index", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.NCellID", localGetNested(s, "random_access.n_cell_id", []));
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
prachNumRxAntennas = localResolveFirstFiniteNumeric(s, ...
    ["random_access.num_rx_antennas", "antenna_and_array.bs_num_rxrus", ...
     "mimo.bs_num_rx_ant", "mimo.n_tx_ant"], ...
    double(sixgr.util.structGet(cfg, "scenario.bs.nTxAnt", 1)));
prachNumTxAntennas = localResolveFirstFiniteNumeric(s, ...
    ["random_access.num_tx_antennas", "antenna_and_array.ue_num_txrus", ...
     "scenario.ue.nTxAnt", "mimo.ue_n_tx_ant", "mimo.n_ue_tx_ant", "mimo.n_rx_ant"], ...
    double(sixgr.util.structGet(cfg, "scenario.ue.nTxAnt", 1)));
cfg = sixgr.util.structSet(cfg, "prach_lls.NumRxAntennas", max(1, round(double(prachNumRxAntennas))));
cfg = sixgr.util.structSet(cfg, "prach_lls.NumTxAntennas", max(1, round(double(prachNumTxAntennas))));
cfg = localStructSetIfPresent(cfg, "prach_lls.NumUEsPerRO", localGetNested(s, "random_access.num_ues_per_ro", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableCollisionMode", localGetNested(s, "random_access.enable_collision_mode", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableInterCellInterference", localGetNested(s, "random_access.enable_inter_cell_interference", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableFrequencyOffset", localGetNested(s, "random_access.enable_frequency_offset", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnablePhaseNoise", localGetNested(s, "random_access.enable_phase_noise", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableTimingUncertainty", localGetNested(s, "random_access.enable_timing_uncertainty", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.EnableFrequencyEstimationMetric", localGetNested(s, "random_access.enable_frequency_estimation_metric", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DetectionThresholdMode", localGetNested(s, "random_access.detection_threshold_mode", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.DetectionThreshold", localGetNested(s, "random_access.detection_threshold", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.FalseAlarmCandidateScope", localGetNested(s, "random_access.false_alarm_candidate_scope", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.SNRSweep_dB", localGetNested(s, "random_access.snr_sweep_db", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.ThresholdSweep", localGetNested(s, "random_access.threshold_sweep", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.TimingOffsetSweepSamples", localGetNested(s, "random_access.timing_offset_sweep_samples", []));
cfg = localStructSetIfPresent(cfg, "prach_lls.FrequencyOffsetSweepHz", localGetNested(s, "random_access.frequency_offset_sweep_hz", []));
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
cfg = localStructSetIfPresent(cfg, "random_access.prach_design", localGetNested(s, "random_access.prach_design", []));
cfg = localStructSetIfPresent(cfg, "random_access.zcdpe_enabled", localGetNested(s, "random_access.zcdpe_enabled", []));
cfg = localStructSetIfPresent(cfg, "random_access.zcdpe_dpi_D", localGetNested(s, "random_access.zcdpe_dpi_D", []));
cfg = localStructSetIfPresent(cfg, "random_access.zcdpe_dpi_d", localGetNested(s, "random_access.zcdpe_dpi_d", []));
cfg = localStructSetIfPresent(cfg, "random_access.zcdpe_num_symbols", localGetNested(s, "random_access.zcdpe_num_symbols", []));
cfg = localStructSetIfPresent(cfg, "random_access.zcdpe_freq_search_points", localGetNested(s, "random_access.zcdpe_freq_search_points", []));
cfg = localStructSetIfPresent(cfg, "random_access.zcdpe_residual_freq_bound_hz", localGetNested(s, "random_access.zcdpe_residual_freq_bound_hz", []));
cfg = localStructSetIfPresent(cfg, "ZCDPE.Enable", localGetNested(s, "random_access.zcdpe_enabled", []));
cfg = localStructSetIfPresent(cfg, "ZCDPE.DPI_D", localGetNested(s, "random_access.zcdpe_dpi_D", []));
cfg = localStructSetIfPresent(cfg, "ZCDPE.DPI_d", localGetNested(s, "random_access.zcdpe_dpi_d", []));
cfg = localStructSetIfPresent(cfg, "ZCDPE.NumSymbols", localGetNested(s, "random_access.zcdpe_num_symbols", []));
cfg = localStructSetIfPresent(cfg, "ZCDPE.FreqSearchPoints", localGetNested(s, "random_access.zcdpe_freq_search_points", []));
cfg = localStructSetIfPresent(cfg, "ZCDPE.ResidualFreqBound_Hz", localGetNested(s, "random_access.zcdpe_residual_freq_bound_hz", []));
if isfield(s, "random_access") && isstruct(s.random_access)
    cfg.random_access = sixgr.util.mergeStruct( ...
        sixgr.util.structGet(cfg, "random_access", struct()), s.random_access);
end
cfg = sixgr.util.structSet(cfg, "prach_lls.OutputDir", runFolder);
cfg = sixgr.util.structSet(cfg, "prach_lls.ScenarioName", char(string(s.meta.scenario_id)));

cfg.phy.harq.enable = logical(s.harq.enabled);
cfg.phy.harq.nProcesses = double(s.harq.process_count);
cfg.phy.harq.rvSequence = double(s.harq.rv_sequence);
cfg.mac.harq.enable = logical(s.harq.enabled);
cfg.mac.harq.numProcesses = double(s.harq.process_count);
cfg.mac.harq.maxRetx = double(localRequireNested(s, "harq.max_retx", "harq.max_retx"));
harqSaveBuffers = logical(localGetNested(s, "harq.save_harq_buffers", ...
    localGetNested(s, "run_control.save_harq_buffers", false)));
harqStopCondition = lower(strtrim(string(localGetNested(s, "harq.stop_condition", "max_retransmissions"))));
if strlength(harqStopCondition) == 0
    harqStopCondition = "max_retransmissions";
end
cfg = sixgr.util.structSet(cfg, "phy.harq.saveBuffers", harqSaveBuffers);
cfg = sixgr.util.structSet(cfg, "mac.harq.saveBuffers", harqSaveBuffers);
cfg = sixgr.util.structSet(cfg, "run.saveHARQBuffers", harqSaveBuffers);
cfg = sixgr.util.structSet(cfg, "phy.harq.stopCondition", char(harqStopCondition));
cfg = sixgr.util.structSet(cfg, "mac.harq.stopCondition", char(harqStopCondition));
harqFeedbackTimingSlots = max(0, round(double(s.harq.feedback_timing_slots)));
harqK2Slots = localNumericScalarOrNaN(localGetNested(s, "harq.k2", ...
    localGetNested(s, "tdd_timing.ul_grant_k2", NaN)));
if ~(isfinite(harqK2Slots) && harqK2Slots >= 0)
    error("sixgr:lls6g:MissingHARQK2", ...
        "harq.k2 or tdd_timing.ul_grant_k2 must be explicitly configured.");
end
harqK2Slots = max(0, round(double(harqK2Slots)));
cfg = sixgr.util.structSet(cfg, "phy.harq.feedbackTimingSlots", double(harqFeedbackTimingSlots));
cfg = sixgr.util.structSet(cfg, "mac.harq.k1", double(harqFeedbackTimingSlots));
cfg = sixgr.util.structSet(cfg, "mac.harq.k2", double(harqK2Slots));
cfg = sixgr.util.structSet(cfg, "phy.harq.staleProcessTimeoutSlots", NaN);
cfg = sixgr.util.structSet(cfg, "mac.harq.staleProcessTimeoutSlots", NaN);
cfg = sixgr.util.structSet(cfg, "mac.harq.processLifetimePolicy", "event_driven");
cfg = sixgr.util.structSet(cfg, "phy.pusch.k2_slots", double(harqK2Slots));
cfg = sixgr.util.structSet(cfg, "phy.ul.grantK2Slots", double(harqK2Slots));
cfg = sixgr.util.structSet(cfg, "phy.harq.combiningMode", char(string(s.harq.combining_mode)));
cfg = sixgr.util.structSet(cfg, "phy.harq.cbgEnabled", logical(s.harq.cbg_enabled));
cfg = sixgr.util.structSet(cfg, "phy.harq.validationMode", char(string(localRequireNested(s, "harq.validation_mode", "harq.validation_mode"))));
if isfield(s, "mac_phase08") && isstruct(s.mac_phase08)
    cfg = sixgr.util.structSet(cfg, "mac.phase08", s.mac_phase08);
end

cfg.phy.ldpc.maxIterations = double(s.coding.max_decoder_iterations);
cfg = sixgr.util.structSet(cfg, "phy.ldpc.useMexBatchDecode", ...
    ~localShouldDisableExactMexForStrictCoupledTruthWaveform(s, runnerProfile));
cfoHz = localResolveRuntimeCFOHz(s);
timingOffsetSamples = localResolveRuntimeTimingOffsetSamples(s);
cfg.phy.rx.cfoCompensation = abs(double(cfoHz)) > 0;
cfg.phy.rx.useFastChannelEstMex = false;
cfg = sixgr.util.structSet(cfg, "phy.rx.useIdealTimingSync", logical(localRequireNested(s, ...
    "receiver.use_ideal_timing_sync", "receiver.use_ideal_timing_sync")));
cfg.phy.nTxAnt = double(s.mimo.n_tx_ant);
cfg.phy.nRxAnt = double(s.mimo.n_rx_ant);
cfg = localApplyRuntimeAntennaConfig(cfg, s);
cfg = sixgr.util.structSet(cfg, "phy.impairments.cfoHz", double(cfoHz));
cfg = sixgr.util.structSet(cfg, "phy.impairments.cfoEstimationMethod", ...
    char(string(localGetNested(s, "impairments.cfo_estimation_method", "cyclic_prefix"))));
cfoCorrectionEnabled = logical(localGetNested(s, "impairments.cfo_correction_enable", true));
cfg = sixgr.util.structSet(cfg, "phy.impairments.cfoCorrectionEnabled", cfoCorrectionEnabled);
cfg = sixgr.util.structSet(cfg, "phy.rx.cfoCorrectionEnabled", cfoCorrectionEnabled);
phaseNoiseEnabled = logical(s.impairments.phase_noise_enabled) || ...
    logical(localGetNested(s, "impairments.phase_noise.enabled", false));
cfg = sixgr.util.structSet(cfg, "phy.impairments.phaseNoiseEnabled", logical(phaseNoiseEnabled));
cfg = sixgr.util.structSet(cfg, "rf.phaseNoise.enable", logical(phaseNoiseEnabled));
phaseNoiseModel = string(localGetNested(s, "impairments.phase_noise_model", ...
    localGetNested(s, "impairments.phase_noise.model", "")));
if strlength(strtrim(phaseNoiseModel)) > 0
    cfg = sixgr.util.structSet(cfg, "rf.phaseNoise.model", char(phaseNoiseModel));
end
phaseNoiseL0_dBcHz = double(localGetNested(s, "impairments.phase_noise_L0_dBcHz", NaN));
phaseNoiseF3dB_Hz = double(localGetNested(s, "impairments.phase_noise_f3dB_Hz", NaN));
phaseNoiseFloor_dBcHz = double(localGetNested(s, "impairments.phase_noise_floor_dBcHz", NaN));
if isfinite(phaseNoiseL0_dBcHz)
    cfg = sixgr.util.structSet(cfg, "rf.phaseNoise.L0_dBcHz", phaseNoiseL0_dBcHz);
end
if isfinite(phaseNoiseF3dB_Hz) && phaseNoiseF3dB_Hz > 0
    cfg = sixgr.util.structSet(cfg, "rf.phaseNoise.f3dB_Hz", phaseNoiseF3dB_Hz);
end
if isfinite(phaseNoiseFloor_dBcHz)
    cfg = sixgr.util.structSet(cfg, "rf.phaseNoise.floor_dBcHz", phaseNoiseFloor_dBcHz);
end
cfg = sixgr.util.structSet(cfg, "rf.cfo_Hz", double(cfoHz));
iqModel = localResolveIQModelToken(s);
iqGainImb_dB = localResolveFirstFiniteNumeric(s, [ ...
    "power_and_rf_frontend.iq_imbalance.gain_imbalance_db"
    "power_and_rf_frontend.iq_imbalance.amp_imbalance_db"
    "power_and_rf_frontend.iq_imbalance.amp_imb_db"
    "power_and_rf_frontend.iq_imbalance.amplitude_imbalance_db"
    "impairments.iq_amplitude_imbalance_dB"
    "impairments.iq_amplitude_imbalance_db"
    "impairments.iq_gain_imbalance_dB"
    "impairments.iq_gain_imbalance_db"
    "impairments.iq_imbalance.gain_imbalance_db"
    "impairments.iq_imbalance.amp_imbalance_db"
    "impairments.iq_imbalance.amp_imb_db"
    "impairments.iq_imbalance.amplitude_imbalance_db"], NaN);
iqPhaseImb_deg = localResolveFirstFiniteNumeric(s, [ ...
    "power_and_rf_frontend.iq_imbalance.phase_imbalance_deg"
    "power_and_rf_frontend.iq_imbalance.phase_imb_deg"
    "impairments.iq_phase_imbalance_deg"
    "impairments.iq_imbalance.phase_imbalance_deg"
    "impairments.iq_imbalance.phase_imb_deg"], NaN);
iqEnabled = logical(s.impairments.iq_imbalance_enabled) || ...
    logical(localGetNested(s, "impairments.iq_imbalance.enabled", false)) || ...
    (isfinite(iqGainImb_dB) && abs(double(iqGainImb_dB)) > 1e-12) || ...
    (isfinite(iqPhaseImb_deg) && abs(double(iqPhaseImb_deg)) > 1e-12);
cfg = sixgr.util.structSet(cfg, "rf.enable", ...
    abs(double(cfoHz)) > 0 || logical(phaseNoiseEnabled) || logical(iqEnabled) || ...
    logical(s.impairments.pa_nonlinearity_enabled) || abs(double(timingOffsetSamples)) > 0);
cfg = sixgr.util.structSet(cfg, "phy.impairments.iqImbalanceEnabled", logical(iqEnabled));
iqCorrectionEnabled = logical(localGetNested(s, "impairments.iq_imbalance_correction_enable", true));
cfg = sixgr.util.structSet(cfg, "phy.impairments.iqImbalanceCorrectionEnabled", iqCorrectionEnabled);
cfg = sixgr.util.structSet(cfg, "phy.rx.iqImbalanceCorrectionEnabled", iqCorrectionEnabled);
cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.enable", logical(iqEnabled));
cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.model", char(iqModel));
if isfinite(iqGainImb_dB)
    cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.ampImb_dB", double(iqGainImb_dB));
    cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.gainImbalance_dB", double(iqGainImb_dB));
end
if isfinite(iqPhaseImb_deg)
    cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.phaseImb_deg", double(iqPhaseImb_deg));
    cfg = sixgr.util.structSet(cfg, "rf.iqImbalance.phaseImbalance_deg", double(iqPhaseImb_deg));
end
cfg = sixgr.util.structSet(cfg, "phy.impairments.paNonlinearityEnabled", logical(s.impairments.pa_nonlinearity_enabled));
cfg = sixgr.util.structSet(cfg, "rf.pa.enable", logical(s.impairments.pa_nonlinearity_enabled));
cfg = sixgr.util.structSet(cfg, "rf.pa.backoff_dB", double(localGetNested(s, "impairments.pa_output_backoff_dB", 3)));
cfg = sixgr.util.structSet(cfg, "phy.impairments.adcQuantizationBits", double(s.impairments.adc_quantization_bits));
cfg = sixgr.util.structSet(cfg, "phy.impairments.dacQuantizationBits", double(s.impairments.dac_quantization_bits));
cfg = sixgr.util.structSet(cfg, "phy.impairments.timingOffsetSamples", double(timingOffsetSamples));
cfg = sixgr.util.structSet(cfg, "rf.adcBits", double(s.impairments.adc_quantization_bits));
cfg = sixgr.util.structSet(cfg, "rf.dacBits", double(s.impairments.dac_quantization_bits));
cfg = sixgr.util.structSet(cfg, "rf.timingOffsetSamples", double(timingOffsetSamples));
interferenceExecutionMode = localResolveInterferenceExecutionMode(s);
if any(interferenceExecutionMode == ["abstract_large_scale_scheduler_context","explicit_activity_power_sum","waveform_overlap_large_scale"])
    error("sixgr:lls6g:config:NonWaveformInterferenceModeRemoved", ...
        "interference.inter_cell_execution_mode='%s' is not allowed for no-proxy LLS runs. Use 'full_per_link_channel_waveform_sum' for waveform-backed inter-cell interference or 'none' when no inter-cell interference is configured.", ...
        char(interferenceExecutionMode));
end
cfg = sixgr.util.structSet(cfg, "run.interferenceExecutionMode", char(interferenceExecutionMode));
cfg = sixgr.util.structSet(cfg, "run.useAbstractInterferenceModel", false);
interCellInterferenceEnabled = logical(localGetNested(s, "interference.inter_cell_interference_flag", ...
    localGetNested(s, "interference.inter_cell_interference_enable", false)));
intraCellInterferenceEnabled = logical(localGetNested(s, "interference.intra_cell_interference_flag", ...
    localGetNested(s, "interference.intra_cell_interference_enable", false)));
cfg = sixgr.util.structSet(cfg, "channel.interference.interCellEnabled", interCellInterferenceEnabled);
cfg = sixgr.util.structSet(cfg, "channel.interference.intraCellEnabled", intraCellInterferenceEnabled);
cfg = sixgr.util.structSet(cfg, "interference.interCellEnabled", interCellInterferenceEnabled);
cfg = sixgr.util.structSet(cfg, "interference.intraCellEnabled", intraCellInterferenceEnabled);
pbchRequired = logical(localRequireNested(s, "control_gating.pbch_required", "control_gating.pbch_required"));
prachRequired = logical(localRequireNested(s, "control_gating.prach_required", "control_gating.prach_required"));
pdcchRequired = logical(localRequireNested(s, "control_gating.pdcch_required", "control_gating.pdcch_required"));
srsRequired = logical(localRequireNested(s, "control_gating.srs_required", "control_gating.srs_required"));
srsMaxAgeSlots = max(0, round(double(localRequireNested(s, ...
    "control_gating.srs_max_age_slots", "control_gating.srs_max_age_slots"))));
trsRequired = logical(localRequireNested(s, "control_gating.trs_required", "control_gating.trs_required"));
trsMaxAgeSlots = max(0, round(double(localRequireNested(s, ...
    "control_gating.trs_max_age_slots", "control_gating.trs_max_age_slots"))));
cfg = sixgr.util.structSet(cfg, "run.controlGating.pbchRequired", pbchRequired);
cfg = sixgr.util.structSet(cfg, "run.controlGating.prachRequired", prachRequired);
cfg = sixgr.util.structSet(cfg, "run.controlGating.pdcchRequired", pdcchRequired);
cfg = sixgr.util.structSet(cfg, "run.controlGating.srsRequired", srsRequired);
cfg = sixgr.util.structSet(cfg, "run.controlGating.srsMaxAgeSlots", srsMaxAgeSlots);
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsRequired", trsRequired);
cfg = sixgr.util.structSet(cfg, "run.controlGating.trsMaxAgeSlots", trsMaxAgeSlots);
cfg = sixgr.util.structSet(cfg, "control_gating.pdcch_required", pdcchRequired);
cfg = sixgr.util.structSet(cfg, "control_gating.srs_required", srsRequired);
cfg = sixgr.util.structSet(cfg, "control_gating.srs_max_age_slots", srsMaxAgeSlots);
cfg = sixgr.util.structSet(cfg, "control_gating.trs_required", trsRequired);
cfg = sixgr.util.structSet(cfg, "control_gating.trs_max_age_slots", trsMaxAgeSlots);
if pdcchRequired
    cfg = localAppendValidationObjectives(cfg, "pdcch_strict_validation");
end
if srsRequired
    cfg = localAppendValidationObjectives(cfg, "srs_strict_validation");
end
if trsRequired
    cfg = localAppendValidationObjectives(cfg, "trs_strict_validation");
end
preAttachBeforeMeasurement = logical(localGetNested(s, "control_gating.pre_attach_ues_before_measurement", ...
    localGetNested(s, "run.controlGating.preAttachUEsBeforeMeasurement", false)));
cfg = sixgr.util.structSet(cfg, "run.controlGating.preAttachUEsBeforeMeasurement", preAttachBeforeMeasurement);
cfg = sixgr.util.structSet(cfg, "control_gating.pre_attach_ues_before_measurement", preAttachBeforeMeasurement);
taUpdateMode = lower(strtrim(string(localGetNested(s, "control_gating.timing_advance_update_mode", "measurement_only"))));
allowedTAUpdateModes = ["measurement_only","geometry_predictive","disabled"];
if ~ismember(taUpdateMode, allowedTAUpdateModes)
    error("sixgr:lls6g:config:InvalidTimingAdvanceUpdateMode", ...
        "control_gating.timing_advance_update_mode='%s' is invalid. Allowed values are: %s.", ...
        char(taUpdateMode), strjoin(allowedTAUpdateModes, ", "));
end
taUpdateThresholdSamples = double(localGetNested(s, "control_gating.timing_advance_update_threshold_samples", 1));
if ~(isfinite(taUpdateThresholdSamples) && isscalar(taUpdateThresholdSamples) && taUpdateThresholdSamples >= 0)
    error("sixgr:lls6g:config:InvalidTimingAdvanceUpdateThreshold", ...
        "control_gating.timing_advance_update_threshold_samples must be a finite nonnegative scalar.");
end
cfg = sixgr.util.structSet(cfg, "run.controlGating.timingAdvanceUpdateMode", char(taUpdateMode));
cfg = sixgr.util.structSet(cfg, "run.controlGating.timingAdvanceUpdateThresholdSamples", double(taUpdateThresholdSamples));
cfg = sixgr.util.structSet(cfg, "control_gating.timing_advance_update_mode", char(taUpdateMode));
cfg = sixgr.util.structSet(cfg, "control_gating.timing_advance_update_threshold_samples", double(taUpdateThresholdSamples));

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
exportSSBBeamSweep = logical(localGetNested(s, "outputs.export_ssb_beam_sweep", ...
    localGetNested(s, "output.export_ssb_beam_sweep", ...
    localGetNested(s, "analytics.export_ssb_beam_sweep", ...
    logical(localGetNested(s, "analytics.export_beam_analytics", false)) && logical(s.mimo.beam_sweep_enabled)))));
cfg = sixgr.util.structSet(cfg, "outputs.exportSSBBeamSweep", exportSSBBeamSweep);
cfg = sixgr.util.structSet(cfg, "analytics.export_ssb_beam_sweep", exportSSBBeamSweep);

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
bootstrapMCSIndex = localNumericScalarOrNaN(localGetNested(s, "link_adaptation.bootstrap_mcs_index", ...
    localGetNested(s, "link_adaptation.bootstrapMCSIndex", NaN)));
if isfinite(bootstrapMCSIndex) && bootstrapMCSIndex >= 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.bootstrapMCSIndex", max(0, min(31, round(double(bootstrapMCSIndex)))));
end
cqiSmoothingAlpha = localNumericScalarOrNaN(localGetNested(s, "link_adaptation.cqi_smoothing_alpha", NaN));
cqiSmoothingMode = lower(strtrim(string(localGetNested(s, "link_adaptation.cqi_smoothing_mode", ""))));
if strlength(cqiSmoothingMode) > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingMode", char(cqiSmoothingMode));
end
if isfinite(cqiSmoothingAlpha) && cqiSmoothingAlpha >= 0 && cqiSmoothingAlpha <= 1
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", double(cqiSmoothingAlpha));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", 0.2);
end
ollaStepDown = localNumericScalarOrNaN(localGetNested(s, "link_adaptation.olla_step_down", ...
    localGetNested(s, "link_adaptation.olla_step_down_db", NaN)));
if isfinite(ollaStepDown) && ollaStepDown > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", double(ollaStepDown));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", 1.0);
end
ollaStepUp = localNumericScalarOrNaN(localGetNested(s, "link_adaptation.olla_step_up", ...
    localGetNested(s, "link_adaptation.olla_step_up_db", NaN)));
if isfinite(ollaStepUp) && ollaStepUp > 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", double(ollaStepUp));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", 0.12);
end
ollaMarginMinDb = double(localGetNested(s, "link_adaptation.olla_margin_min_db", ...
    localGetNested(s, "link_adaptation.delta_mcs_min", NaN)));
if isfinite(ollaMarginMinDb)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMinDb", double(ollaMarginMinDb));
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMin", double(ollaMarginMinDb));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMinDb", -10);
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMin", -10);
end
ollaMarginMaxDb = double(localGetNested(s, "link_adaptation.olla_margin_max_db", ...
    localGetNested(s, "link_adaptation.delta_mcs_max", NaN)));
if isfinite(ollaMarginMaxDb)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMaxDb", double(ollaMarginMaxDb));
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMax", double(ollaMarginMaxDb));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMaxDb", 10);
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSMax", 10);
end
resetOnRIChange = localGetNested(s, "link_adaptation.reset_on_ri_change", []);
if ~isempty(resetOnRIChange)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.resetOnRIChange", logical(resetOnRIChange));
elseif scenarioId == "lls_3gpp_rel20_anchor_4ghz_100mhz_waveform_honest_200ue_1frame"
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.resetOnRIChange", true);
end
rankThreshold = double(localGetNested(s, "link_adaptation.rank_threshold", NaN));
if isfinite(rankThreshold) && rankThreshold >= 0
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankThreshold", double(rankThreshold));
    cfg = sixgr.util.structSet(cfg, "phy.mimo.svRankThreshold", double(rankThreshold));
end
minSINRForRank2_dB = double(localGetNested(s, "link_adaptation.min_sinr_for_rank2_dB", NaN));
if isfinite(minSINRForRank2_dB)
    cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.minSINRForRank2_dB", double(minSINRForRank2_dB));
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
cfg = localApplyScenarioAuditExtensions(cfg, s);

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
initialAccessSection = localGetNested(s, "initial_access", struct());
if builtin("isstruct", initialAccessSection) && ~isempty(fieldnames(initialAccessSection))
    cfg = sixgr.util.structSet(cfg, "initial_access", initialAccessSection);
end
cfg = sixgr.util.structSet(cfg, "lls6g.impairments", s.impairments);
cfg = sixgr.util.structSet(cfg, "lls6g.ai_ml", s.ai_ml);
cfg = sixgr.util.structSet(cfg, "lls6g.energy_efficiency", s.energy_efficiency);
cfg = sixgr.util.structSet(cfg, "lls6g.kpis", s.kpis);
cfg = sixgr.util.structSet(cfg, "lls6g.logging", s.logging);
cfg = sixgr.util.structSet(cfg, "lls6g.scenario", s.scenario);
cfg = sixgr.util.structSet(cfg, "lls6g.outputRunFolder", char(string(runFolder)));
for extraSection = ["pucch_resources", "initial_access", "sib1_and_initial_access", "random_access_evidence", ...
        "channel_rf_configured_vs_applied", "decoder_output_capture", "dut_reference_validation"]
    if isfield(s, extraSection)
        cfg = sixgr.util.structSet(cfg, "lls6g." + extraSection, s.(extraSection));
    end
end

if localShouldDisableExactMexForStrictCoupledTruthWaveform(s, runnerProfile)
    cfg = sixgr.util.structSet(cfg, "run.useMex", false);
end

cfg = sixgr.config.normalizeConfig(cfg);
[cfg, ~, frameEngine] = sixgr.config.validateConfig(cfg);
cfg = localApplyFrameStructureEngine(cfg, frameEngine);
% normalizeConfig/validateConfig may derive a generic diagnostic class from
% adaptive PHY knobs.  Reapply the explicit source field directly so that
% the operator-owned execution contract survives that derivation.
explicitRunClass = localNormalizeRunClassToken(localGetNested( ...
    s, "validation.run_class", ""));
if strlength(explicitRunClass) > 0
    cfg = sixgr.util.structSet(cfg, ...
        "validation.RunClass", char(explicitRunClass));
    cfg = sixgr.util.structSet(cfg, ...
        "validation.run_class", char(explicitRunClass));
else
    cfg = localApplyValidationRunClass(cfg, s);
end
end

function cfg = localApplyScenarioAuditExtensions(cfg, s)
cfg = sixgr.util.structSet(cfg, "validation.strict", logical(localGetNested(s, "logging.strict_validation", false)));

pucchSection = localGetNested(s, "pucch_resources", struct());
if builtin("isstruct", pucchSection) && ~isempty(fieldnames(pucchSection))
    cfg = sixgr.util.structSet(cfg, "validation.pucch_resources", pucchSection);
    if logical(localGetNested(s, "pucch_resources.enabled", false))
        profile = string(localGetNested(s,"pucch_resources.profile",""));
        epoch = double(localGetNested(s,"pucch_resources.configuration_epoch",NaN));
        resourceSets = localGetNested(s,"pucch_resources.resource_sets",struct([]));
        resources = localGetNested(s,"pucch_resources.resources",struct([]));
        if profile ~= "nr_rel18_pucch_strict" || ...
                ~(isscalar(epoch)&&isfinite(epoch)&&epoch>=0&&epoch==fix(epoch)) || ...
                ~isstruct(resourceSets) || isempty(resourceSets) || ...
                ~isstruct(resources) || isempty(resources)
            error("sixgr:lls6g:config:InvalidStrictPUCCHConfiguration", ...
                "Enabled connected PUCCH requires the strict profile, epoch, resource sets and resources.");
        end
        cfg = sixgr.util.structSet(cfg,"phy.pucch.profile",char(profile));
        cfg = sixgr.util.structSet(cfg,"phy.pucch.configurationEpoch",epoch);
        cfg = sixgr.util.structSet(cfg,"phy.pucch.resourceSets",resourceSets);
        cfg = sixgr.util.structSet(cfg,"phy.pucch.resources",resources);
        cfg = sixgr.util.structSet(cfg,"phy.pucch.dlDataToULACK", ...
            localGetNested(s,"pucch_resources.dl_data_to_ul_ack",[]));
        harqACKResourceID = double(localGetNested(s, ...
            "pucch_resources.harq_ack.resource_id", NaN));
        if ~(isscalar(harqACKResourceID) && isfinite(harqACKResourceID) && ...
                harqACKResourceID >= 0 && harqACKResourceID == fix(harqACKResourceID))
            error("sixgr:lls6g:config:MissingPUCCHHARQACKResource", ...
                "Enabled connected PUCCH requires pucch_resources.harq_ack.resource_id.");
        end
        resourceIDs = double([resources.id]);
        resourceIndex = find(resourceIDs == harqACKResourceID, 1);
        if isempty(resourceIndex) || ...
                ~isfield(resources(resourceIndex), "starting_symbol") || ...
                ~isfield(resources(resourceIndex), "nrof_symbols")
            error("sixgr:lls6g:config:InvalidPUCCHHARQACKResource", ...
                "PUCCH HARQ-ACK resource %d must identify a configured resource with explicit symbol allocation.", ...
                harqACKResourceID);
        end
        harqACKSymbolAllocation = double([ ...
            resources(resourceIndex).starting_symbol, ...
            resources(resourceIndex).nrof_symbols]);
        cfg = sixgr.util.structSet(cfg, "phy.pucch.harqACKResourceID", ...
            harqACKResourceID);
        cfg = sixgr.util.structSet(cfg, "phy.pucch.symbolAllocation", ...
            harqACKSymbolAllocation);
        cfg = sixgr.util.structSet(cfg, "phy.pucch.SymbolAllocation", ...
            harqACKSymbolAllocation);
        cfg = sixgr.util.structSet(cfg,"phy.pucch.assignmentMode", ...
            "rrc_procedure_state");
    end
end

decoderSection = localGetNested(s, "decoder_output_capture", struct());
if builtin("isstruct", decoderSection) && ~isempty(fieldnames(decoderSection))
    cfg = sixgr.util.structSet(cfg, "validation.decoder_output_capture", decoderSection);
end

dutRefSection = localGetNested(s, "dut_reference_validation", struct());
if builtin("isstruct", dutRefSection) && ~isempty(fieldnames(dutRefSection))
    cfg = sixgr.util.structSet(cfg, "validation.dut_reference_validation", dutRefSection);
    cfg = localStructSetIfPresent(cfg, "validation.referenceMissingPolicy", ...
        localGetNested(s, "dut_reference_validation.if_reference_missing_policy", []));
    cfg = localStructSetIfPresent(cfg, "validation.dutReferenceArtifact", ...
        localGetNested(s, "dut_reference_validation.write_artifact", []));
end

sib1Section = localGetNested(s, "sib1_and_initial_access", struct());
if builtin("isstruct", sib1Section) && ~isempty(fieldnames(sib1Section))
    cfg = sixgr.util.structSet(cfg, "validation.sib1_and_initial_access", sib1Section);
    sib1Required = logical(localGetNested(s, "sib1_and_initial_access.sib1_required", false)) || ...
        logical(localGetNested(s, "sib1_and_initial_access.cell_search_required", false)) || ...
        logical(localGetNested(s, "sib1_and_initial_access.sib1_decode_from_waveform_required", false));
    if sib1Required
        cfg = sixgr.util.structSet(cfg, "phy.sib1.enable", true);
        cfg = localAppendValidationObjectives(cfg, "cell_search_mib_sib1");
    end
    siRNTI = double(localGetNested(s, "sib1_and_initial_access.si_rnti", NaN));
    if isfinite(siRNTI) && siRNTI >= 0
        cfg = sixgr.util.structSet(cfg, "validation.sib1.siRNTI", round(double(siRNTI)));
    end
    if logical(localGetNested(s, "sib1_and_initial_access.coreset0_from_mib_required", false))
        cfg = sixgr.util.structSet(cfg, "phy.sib1.coreset0Index", ...
            double(localGetNested(s, "phy.sib1.coreset0Index", 0)));
    end
    if logical(localGetNested(s, "sib1_and_initial_access.searchspace0_from_mib_required", false))
        cfg = sixgr.util.structSet(cfg, "phy.sib1.searchSpaceZero", ...
            double(localGetNested(s, "phy.sib1.searchSpaceZero", 0)));
    end
end

raSection = localGetNested(s, "random_access_evidence", struct());
if builtin("isstruct", raSection) && ~isempty(fieldnames(raSection))
    cfg = sixgr.util.structSet(cfg, "validation.random_access_evidence", raSection);
    if logical(localGetNested(s, "random_access_evidence.four_step_ra_required", false)) || ...
            logical(localGetNested(s, "random_access_evidence.msg1_prach_required", false)) || ...
            logical(localGetNested(s, "random_access_evidence.msg3_pusch_required", false))
        cfg = localAppendValidationObjectives(cfg, "random_access_four_step");
    end
end

channelRFSection = localGetNested(s, "channel_rf_configured_vs_applied", struct());
channelRFEnabledExplicit = localHasNestedPath(s, "channel_rf_configured_vs_applied.enabled");
channelRFDerivedRequired = localChannelRFStrictRequiredByRuntime(cfg);
if channelRFDerivedRequired && ~channelRFEnabledExplicit
    channelRFSection = sixgr.util.structSet(channelRFSection, "enabled", true);
    channelRFSection = sixgr.util.structSet(channelRFSection, "required_by", "strict_reference_signal_or_random_access_channel_rf");
end
if builtin("isstruct", channelRFSection) && ~isempty(fieldnames(channelRFSection))
    cfg = sixgr.util.structSet(cfg, "validation.channel_rf_configured_vs_applied", channelRFSection);
    if logical(sixgr.util.structGet(channelRFSection, "enabled", false))
        cfg = localAppendValidationObjectives(cfg, "channel_rf_strict_validation");
    end
end

fixedLinkCampaignSection = localGetNested(s, "validation.fixed_link_campaign", struct());
if builtin("isstruct", fixedLinkCampaignSection) && ~isempty(fieldnames(fixedLinkCampaignSection))
    cfg = sixgr.util.structSet(cfg, "validation.fixed_link_campaign", ...
        localNormalizeFixedLinkCampaignSection(fixedLinkCampaignSection));
end
cfg = localApplyValidationRunClass(cfg, s);

cfg = localApplyConfigDrivenPHYRuntimeSurfaces(cfg, s);
end

function cfg = localApplyConfigDrivenPHYRuntimeSurfaces(cfg, s)
% Map optional deep PHY YAML surfaces into the internal runtime cfg. These
% mappings are intentionally generic; they expose reusable NR-like controls
% without fabricating measurements or changing receiver evidence.
for section = ["bwp","pdsch","pusch","pdcch","channel_estimation","equalization", ...
        "synchronization","rf_hardware","tdd_timing"]
    if isfield(s, char(section))
        cfg = sixgr.util.structSet(cfg, "lls6g." + section, s.(char(section)));
    end
end

cfg = localApplyBWPSurface(cfg, s);
cfg = localApplyDataChannelSurface(cfg, s, "pdsch", "phy.pdsch");
cfg = localApplyDataChannelSurface(cfg, s, "pusch", "phy.pusch");
cfg = localReconcileULWaveformPUSCHSurface(cfg, s);
cfg = localApplyPDCCHSurface(cfg, s);
cfg = localApplyReceiverSurface(cfg, s);
cfg = localApplyTimingAndRFHardwareSurface(cfg, s);
cfg = localApplyAuxiliaryPHYKnobs(cfg, s);
end

function cfg = localApplyBWPSurface(cfg, s)
directions = ["dl","ul"];
for i = 1:numel(directions)
    dir = directions(i);
    src = "bwp." + dir;
    [bwpStruct, found] = localTryGetNestedStrict(s, src);
    if ~found || ~(isstruct(bwpStruct) || iscell(bwpStruct))
        continue;
    end
    configured = localNormalizeBWPSurfaceSequence(bwpStruct, upper(dir));
    active = localInitialBWPSurface(configured, upper(dir));
    base = "phy.bwp." + dir;
    cfg = sixgr.util.structSet(cfg, ...
        "phy.bwp.configured" + upper(dir), configured);
    % The scalar compatibility view is the explicitly selected initial BWP;
    % the full configured array remains authoritative and is attached to
    % the production frame runtime state below.
    cfg = sixgr.util.structSet(cfg, base, active);
end
if isfield(s, "component_carriers")
    cfg = sixgr.util.structSet(cfg, ...
        "phy.frame.componentCarriers", s.component_carriers);
elseif isfield(s, "bwp") && isstruct(s.bwp) && isscalar(s.bwp) && ...
        isfield(s.bwp, "component_carriers")
    cfg = sixgr.util.structSet(cfg, ...
        "phy.frame.componentCarriers", s.bwp.component_carriers);
end
end

function configured = localNormalizeBWPSurfaceSequence(raw, direction)
if iscell(raw)
    if isempty(raw) || ~all(cellfun(@(x) isstruct(x) && isscalar(x), raw(:)))
        error("sixgr:lls6g:config:InvalidBWPArray", ...
            "bwp.%s must contain scalar configuration structs.", lower(direction));
    end
    configured = raw{1};
    for index = 2:numel(raw)
        names = union(fieldnames(configured), fieldnames(raw{index}), "stable");
        configured = localAddMissingBWPFields(configured, names);
        item = localAddMissingBWPFields(raw{index}, names);
        configured(end + 1) = item; %#ok<AGROW>
    end
elseif isstruct(raw)
    configured = raw(:);
else
    error("sixgr:lls6g:config:InvalidBWPArray", ...
        "bwp.%s must be a struct array.", lower(direction));
end
aliasTargets = { ...
    'Direction', 'BWPID', 'id', 'NSizeBWP', 'NStartBWP', ...
    'SubcarrierSpacing_kHz', 'SCSKHz', 'CyclicPrefix'};
configured = localAddMissingBWPFields(configured, ...
    union(fieldnames(configured), aliasTargets, "stable"));
for index = 1:numel(configured)
    configured(index).Direction = char(direction);
    configured(index) = localCopyBWPAlias(configured(index), ...
        "bwp_id", "BWPID");
    configured(index) = localCopyBWPAlias(configured(index), ...
        "bwp_id", "id");
    configured(index) = localCopyBWPAlias(configured(index), ...
        "n_size_bwp", "NSizeBWP");
    configured(index) = localCopyBWPAlias(configured(index), ...
        "n_start_bwp", "NStartBWP");
    configured(index) = localCopyBWPAlias(configured(index), ...
        "scs_khz", "SubcarrierSpacing_kHz");
    configured(index) = localCopyBWPAlias(configured(index), ...
        "scs_khz", "SCSKHz");
    configured(index) = localCopyBWPAlias(configured(index), ...
        "cp_type", "CyclicPrefix");
end
end

function output = localAddMissingBWPFields(input, names)
output = input;
for index = 1:numel(names)
    if ~isfield(output, names{index})
        [output.(names{index})] = deal([]);
    end
end
output = orderfields(output, names);
end

function item = localCopyBWPAlias(item, sourceName, targetName)
if isfield(item, sourceName) && ~isempty(item.(sourceName))
    item.(targetName) = item.(sourceName);
end
end

function active = localInitialBWPSurface(configured, direction)
if isempty(configured)
    error("sixgr:lls6g:config:EmptyBWPArray", ...
        "bwp.%s must contain at least one BWP.", lower(direction));
end
if numel(configured) == 1
    active = configured(1);
    return;
end
flags = false(numel(configured), 1);
explicit = false(numel(configured), 1);
for index = 1:numel(configured)
    names = ["ActiveInitial","active_initial","Active","active"];
    for name = names
        if isfield(configured(index), char(name))
            value = configured(index).(char(name));
            if isempty(value)
                continue;
            end
            if ~((islogical(value) || isnumeric(value)) && isscalar(value) && ...
                    isfinite(double(value)) && any(double(value) == [0, 1]))
                error("sixgr:lls6g:config:InvalidInitialBWPState", ...
                    "bwp.%s ActiveInitial values must be scalar logical.", ...
                    lower(direction));
            end
            flags(index) = logical(value);
            explicit(index) = true;
            break;
        end
    end
end
if ~all(explicit) || nnz(flags) ~= 1
    error("sixgr:lls6g:config:AmbiguousInitialBWPState", ...
        "A multi-BWP bwp.%s array must explicitly select exactly one initial BWP.", ...
        lower(direction));
end
active = configured(flags);
end

function cfg = localApplyDataChannelSurface(cfg, s, section, targetBase)
if ~isfield(s, char(section))
    return;
end
cfg = sixgr.util.structSet(cfg, targetBase + ".yamlSurface", s.(char(section)));
fieldPairs = {
    "resource_allocation_type", "resourceAllocationType"
    "vrb_to_prb_mapping", "vrbToPRBMapping"
    "prb_bundling_type", "prbBundlingType"
    "prb_bundle_size", "prbBundleSize"
    "rate_matching_pattern", "rateMatchingPattern"
    "tbs_scaling", "tbsScaling"
    "cbg_transmission", "cbgTransmission"
    };
for i = 1:size(fieldPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, section + "." + fieldPairs{i,1}, targetBase + "." + fieldPairs{i,2});
end
[mappingType, hasMappingType] = localTryGetNestedStrict(s, section + ".mapping_type");
if hasMappingType
    cfg = sixgr.util.structSet(cfg, targetBase + ".mappingType", ...
        localNormalizeDataChannelMappingType(mappingType, section + ".mapping_type"));
end
cfg = localApplyDataChannelFrequencyAllocation(cfg, s, section, targetBase);
if section == "pdsch"
    cfg = localCopyRuntimeField(cfg, s, "pdsch.xoh_pdsch", targetBase + ".xOverhead");
    cfg = localCopyRuntimeField(cfg, s, "pdsch.xoh_pdsch", targetBase + ".XOverhead");
else
    cfg = localApplyPUSCHDetailSurface(cfg, s, targetBase);
    cfg = localCopyRuntimeField(cfg, s, "pusch.intra_slot_frequency_hopping", targetBase + ".intraSlotFrequencyHopping");
    cfg = localCopyRuntimeField(cfg, s, "pusch.inter_slot_frequency_hopping", targetBase + ".interSlotFrequencyHopping");
    cfg = localCopyRuntimeField(cfg, s, "pusch.transform_precoding", targetBase + ".transformPrecoding");
    cfg = localCopyRuntimeField(cfg, s, "pusch.codebook_based_transmission", targetBase + ".codebookBasedTransmission");
    cfg = localCopyRuntimeField(cfg, s, "pusch.xoh_pusch", targetBase + ".xOverhead");
    cfg = localCopyRuntimeField(cfg, s, "pusch.xoh_pusch", targetBase + ".XOverhead");
    cfg = localCopyRuntimeField(cfg, s, "pusch.tp_pi2_bpsk", targetBase + ".pi2BPSKTransformPrecoding");
end

[startSymbol, hasStart] = localTryGetNestedStrict(s, section + ".start_symbol");
[numSymbols, hasNum] = localTryGetNestedStrict(s, section + ".num_symbols");
if xor(hasStart, hasNum)
    error("sixgr:phy:frame:InvalidTDRA", ...
        "%s.start_symbol and %s.num_symbols must be configured together.", ...
        section, section);
end
if hasStart && hasNum
    % Preserve the configured values byte-for-value at this translation
    % boundary. Canonical TDRA validation owns integer/range checks; this
    % adapter must not round or auto-shift an invalid allocation into one
    % that appears standard-compliant.
    startValue = double(startSymbol);
    numValue = double(numSymbols);
    cfg = sixgr.util.structSet( ...
        cfg, targetBase + ".startSymbol", startValue);
    cfg = sixgr.util.structSet( ...
        cfg, targetBase + ".numSymbols", numValue);
    cfg = sixgr.util.structSet( ...
        cfg, targetBase + ".symbolAllocation", ...
        [startValue numValue]);
    cfg = sixgr.util.structSet( ...
        cfg, targetBase + ".SymbolAllocation", ...
        [startValue numValue]);
end
end

function cfg = localApplyPUSCHDetailSurface(cfg, s, targetBase)
% Preserve the operator-owned PUSCH surface using the exact field names
% consumed by the production allocator, transmitter, receiver, and power
% controller. Runtime grants may replace scheduling state, but MATLAB
% literals must not silently replace configured initial PHY policy.
scalarPairs = {
    "rnti", "RNTI"
    "scrambling_id", "NID"
    "mcs_table", "mcsTable"
    "mcs_index", "mcsIndex"
    "modulation", "modulation"
    "target_code_rate_per_codeword", "codeRate"
    "num_layers", "numLayers"
    "num_antenna_ports", "NumAntennaPorts"
    "transmission_scheme", "transmissionScheme"
    "codebook_type", "codebookType"
    "tpmi", "TPMI"
    "sri", "SRI"
    "rv_per_codeword", "rv"
    "ndi_per_codeword", "ndi"
    "harq_process_id", "HARQProcessId"
    "dmrs_configuration_type", "dmrs.configurationType"
    "dmrs_length", "dmrs.length"
    "dmrs_additional_position", "dmrs.additionalPositions"
    "dmrs_type_a_position", "dmrs.typeAPosition"
    "dmrs_num_cdm_groups_without_data", "dmrs.numCDMGroupsWithoutData"
    "dmrs_port_set", "dmrs.portSet"
    "dmrs_nid_nscid", "dmrs.NIDNSCID"
    "dmrs_nscid", "dmrs.NSCID"
    "dmrs_nrs_id", "dmrs.NRSID"
    "dmrs_group_hopping", "dmrs.groupHopping"
    "dmrs_sequence_hopping", "dmrs.sequenceHopping"
    "ptrs_enabled", "enablePTRS"
    "ptrs_time_density", "ptrs.timeDensity"
    "ptrs_frequency_density", "ptrs.frequencyDensity"
    "ptrs_re_offset", "ptrs.reOffset"
    "ptrs_port_set", "ptrs.portSet"
    "ptrs_nid", "ptrs.NID"
    "uci_beta_offset_ack", "uci.betaOffsetACK"
    "uci_beta_offset_csi1", "uci.betaOffsetCSI1"
    "uci_beta_offset_csi2", "uci.betaOffsetCSI2"
    "uci_scaling", "uci.scaling"
    "repetition_type", "repetition.type"
    "repetition_count", "repetition.count"
    };
for i = 1:size(scalarPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, ...
        "pusch." + scalarPairs{i,1}, targetBase + "." + scalarPairs{i,2});
end

% Maintain the aliases used by existing grant and HARQ materializers.
cfg = localCopyRuntimeField(cfg, s, "pusch.num_layers", targetBase + ".nLayers");
cfg = localCopyRuntimeField(cfg, s, "pusch.num_layers", targetBase + ".maxLayers");
cfg = localCopyRuntimeField(cfg, s, "pusch.num_antenna_ports", targetBase + ".numAntennaPorts");
cfg = localCopyRuntimeField(cfg, s, "pusch.transmission_scheme", targetBase + ".TransmissionScheme");
cfg = localCopyRuntimeField(cfg, s, "pusch.codebook_type", targetBase + ".CodebookType");
cfg = localCopyRuntimeField(cfg, s, "pusch.tpmi", targetBase + ".PMI");
cfg = localCopyRuntimeField(cfg, s, "pusch.tpmi", targetBase + ".tpmi");
cfg = localCopyRuntimeField(cfg, s, "pusch.mcs_index", targetBase + ".configuredMCSIndex");

[allocationType, hasAllocationType] = localTryGetNestedStrict( ...
    s, "pusch.resource_allocation_type");
if hasAllocationType
    cfg = sixgr.util.structSet(cfg, targetBase + ".resourceAllocationType", ...
        localNormalizePUSCHResourceAllocationType(allocationType));
end

[hoppingMode, hasHoppingMode] = localTryGetNestedStrict( ...
    s, "pusch.frequency_hopping");
if hasHoppingMode
    hoppingMode = localNormalizePUSCHFrequencyHoppingMode(hoppingMode);
    cfg = sixgr.util.structSet(cfg, targetBase + ".frequencyHopping.mode", ...
        char(hoppingMode));
end
cfg = localCopyRuntimeField(cfg, s, "pusch.second_hop_start_prb", ...
    targetBase + ".frequencyHopping.secondHopStartPRB");

[codebookFlag, hasCodebookFlag] = localTryGetNestedStrict( ...
    s, "pusch.codebook_based_transmission");
[schemeValue, hasScheme] = localTryGetNestedStrict( ...
    s, "pusch.transmission_scheme");
if hasScheme
    scheme = localNormalizePUSCHTransmissionScheme(schemeValue);
    cfg = sixgr.util.structSet(cfg, targetBase + ".transmissionScheme", char(scheme));
    cfg = sixgr.util.structSet(cfg, targetBase + ".TransmissionScheme", char(scheme));
    if hasCodebookFlag && logical(codebookFlag) ~= (scheme == "codebook")
        error("sixgr:lls6g:config:PUSCHCodebookPolicyConflict", ...
            "pusch.codebook_based_transmission conflicts with pusch.transmission_scheme.");
    end
end
[transformPrecoding, hasTransformPrecoding] = localTryGetNestedStrict( ...
    s, "pusch.transform_precoding");
if hasTransformPrecoding && hasCodebookFlag && ...
        logical(transformPrecoding) && logical(codebookFlag)
    error("sixgr:lls6g:config:PUSCHPrecodingPolicyConflict", ...
        "Transform-precoded PUSCH cannot also select codebook-based transmission.");
end

powerPairs = {
    "enabled", "enabled"
    "open_loop_enabled", "openLoopEnabled"
    "closed_loop_enabled", "closedLoopEnabled"
    "p0_pusch_dbm", "p0PUSCH_dBm"
    "alpha", "alpha"
    "delta_tf_db", "deltaTF_dB"
    "closed_loop_accumulation_db", "closedLoopAccumulation_dB"
    "tpc_command_bits", "tpcCommandBits"
    "pcmax_dbm", "pcmax_dBm"
    "reference_tx_power_dbm", "referenceTxPower_dBm"
    "pathloss_source", "pathlossSource"
    };
for i = 1:size(powerPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, ...
        "pusch.power_control." + powerPairs{i,1}, ...
        targetBase + ".powerControl." + powerPairs{i,2});
end
[pcEnabled, hasPCEnabled] = localTryGetNestedStrict( ...
    s, "pusch.power_control.enabled");
if hasPCEnabled
    cfg = sixgr.util.structSet(cfg, ...
        "powerAndRF.puschPowerControlEnabled", logical(pcEnabled));
end
cfg = localCopyRuntimeField(cfg, s, "pusch.power_control.pcmax_dbm", ...
    "powerAndRF.uePcmax_dBm");
cfg = localCopyRuntimeField(cfg, s, ...
    "pusch.power_control.reference_tx_power_dbm", ...
    "powerAndRF.referenceTxPower_dBm");

srsPairs = {
    "required", "required"
    "max_age_slots", "maxAgeSlots"
    "configuration_epoch_required", "configurationEpochRequired"
    "configured_tpmi_fallback_allowed", "configuredTPMIFallbackAllowed"
    };
for i = 1:size(srsPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, ...
        "pusch.srs_authority." + srsPairs{i,1}, ...
        targetBase + ".srsAuthority." + srsPairs{i,2});
end
end

function value = localNormalizePUSCHResourceAllocationType(raw)
if isnumeric(raw) && isscalar(raw) && isfinite(double(raw)) && ...
        double(raw) == fix(double(raw)) && any(double(raw) == 0:2)
    value = double(raw);
    return;
end
token = lower(strrep(strtrim(string(raw)), "_", ""));
switch token
    case {"0","type0"}
        value = 0;
    case {"1","type1"}
        value = 1;
    case {"2","type2"}
        value = 2;
    otherwise
        error("sixgr:lls6g:config:InvalidPUSCHResourceAllocationType", ...
            "pusch.resource_allocation_type must be type0, type1, type2, 0, 1, or 2.");
end
end

function mode = localNormalizePUSCHFrequencyHoppingMode(raw)
token = lower(strrep(strtrim(string(raw)), "-", "_"));
switch token
    case {"none","disabled","neither","off"}
        mode = "none";
    case {"intra_slot","intraslot"}
        mode = "intra_slot";
    case {"inter_slot","interslot"}
        mode = "inter_slot";
    otherwise
        error("sixgr:lls6g:config:InvalidPUSCHFrequencyHoppingMode", ...
            "pusch.frequency_hopping must be none, intra_slot, or inter_slot.");
end
end

function scheme = localNormalizePUSCHTransmissionScheme(raw)
token = lower(strrep(strtrim(string(raw)), "_", ""));
switch token
    case "codebook"
        scheme = "codebook";
    case {"noncodebook","noncodebookbased"}
        scheme = "nonCodebook";
    otherwise
        error("sixgr:lls6g:config:InvalidPUSCHTransmissionScheme", ...
            "pusch.transmission_scheme must be codebook or nonCodebook.");
end
end

function cfg = localApplyDataChannelFrequencyAllocation(cfg, s, section, targetBase)
[explicitPRBSet, hasExplicitPRBSet] = localTryGetNestedStrict( ...
    s, section + ".prb_set");
[prbStart, hasPRBStart] = localTryGetNestedStrict( ...
    s, section + ".prb_start");
[numPRB, hasNumPRB] = localTryGetNestedStrict( ...
    s, section + ".num_prb");

if hasExplicitPRBSet && (hasPRBStart || hasNumPRB)
    error("sixgr:lls6g:config:AmbiguousDataChannelPRBAllocation", ...
        "%s must configure either prb_set or the prb_start/num_prb " + ...
        "pair, not both.", section);
end
if xor(hasPRBStart, hasNumPRB)
    error("sixgr:lls6g:config:IncompleteDataChannelPRBAllocation", ...
        "%s.prb_start and %s.num_prb must be configured together.", ...
        section, section);
end
if ~hasExplicitPRBSet && ~hasPRBStart
    return;
end

if hasExplicitPRBSet
    prbSet = double(explicitPRBSet(:).');
else
    startValue = double(prbStart);
    countValue = double(numPRB);
    if ~(isscalar(startValue) && isfinite(startValue) && ...
            startValue == fix(startValue) && startValue >= 0)
        error("sixgr:lls6g:config:InvalidDataChannelPRBStart", ...
            "%s.prb_start must be a nonnegative integer.", section);
    end
    if ~(isscalar(countValue) && isfinite(countValue) && ...
            countValue == fix(countValue) && countValue >= 1)
        error("sixgr:lls6g:config:InvalidDataChannelPRBCount", ...
            "%s.num_prb must be a positive integer.", section);
    end
    prbSet = startValue + (0:(countValue - 1));
end

if isempty(prbSet) || any(~isfinite(prbSet) | prbSet ~= fix(prbSet) ...
        | prbSet < 0) || numel(unique(prbSet)) ~= numel(prbSet)
    error("sixgr:lls6g:config:InvalidDataChannelPRBSet", ...
        "%s.prb_set must contain unique nonnegative integers.", section);
end
carrierNRB = double(sixgr.util.structGet(cfg, ...
    "phy.carrier.NSizeGrid", NaN));
if ~(isscalar(carrierNRB) && isfinite(carrierNRB) && ...
        carrierNRB == fix(carrierNRB) && carrierNRB >= 1)
    error("sixgr:lls6g:config:MissingCanonicalCarrierGrid", ...
        "A valid phy.carrier.NSizeGrid is required before applying " + ...
        "%s PRB allocation.", section);
end
if any(prbSet >= carrierNRB)
    error("sixgr:lls6g:config:DataChannelPRBOutsideCarrier", ...
        "%s PRB allocation %s exceeds the canonical carrier " + ...
        "NSizeGrid=%d.", section, mat2str(prbSet), carrierNRB);
end
if section == "pdsch"
    bwpDirection = "dl";
else
    bwpDirection = "ul";
end
activeBWP = sixgr.util.structGet(cfg, ...
    "phy.bwp." + bwpDirection, struct());
bwpSize = double(sixgr.util.structGet(activeBWP, "NSizeBWP", ...
    sixgr.util.structGet(activeBWP, "n_size_bwp", NaN)));
if ~(isscalar(bwpSize) && isfinite(bwpSize) && ...
        bwpSize == fix(bwpSize) && bwpSize >= 1)
    error("sixgr:lls6g:config:MissingDataChannelActiveBWP", ...
        "%s requires an explicit active %s BWP size.", ...
        section, upper(bwpDirection));
end
if any(prbSet >= bwpSize)
    error("sixgr:lls6g:config:DataChannelPRBOutsideActiveBWP", ...
        "%s PRB allocation %s must use BWP-relative indices in " + ...
        "[0,NSizeBWP-1], where NSizeBWP=%d.", ...
        section, mat2str(prbSet), bwpSize);
end

cfg = sixgr.util.structSet(cfg, targetBase + ".PRBSet", prbSet);
cfg = sixgr.util.structSet(cfg, targetBase + ".prbSet", prbSet);
cfg = sixgr.util.structSet(cfg, targetBase + ".prbStart", min(prbSet));
cfg = sixgr.util.structSet(cfg, targetBase + ".numPRB", numel(prbSet));
end

function cfg = localReconcileULWaveformPUSCHSurface(cfg, s)
ulWaveform = upper(strtrim(string(localGetNested(s, "waveform.ul_waveform", ""))));
transformEnabled = logical(localGetNested(s, "waveform.transform_precoding_enabled", false));
if ulWaveform == "DFT-S-OFDM" || transformEnabled
    cfg = sixgr.util.structSet(cfg, "phy.pusch.transformPrecoding", true);
    cfg = sixgr.util.structSet(cfg, "phy.pusch.codebookBasedTransmission", false);
    cfg = sixgr.util.structSet(cfg, "phy.pusch.transmissionScheme", "noncodebook");
    cfg = sixgr.util.structSet(cfg, "phy.pusch.TransmissionScheme", "noncodebook");
end
if localUsePi2BPSKULMode(s)
    % The inherited generic PUSCH surface may still carry its baseline
    % modulation token.  The explicit DFT-s-OFDM/pi/2-BPSK scenario owns
    % the effective waveform modulation and must win at this final
    % reconciliation boundary.
    cfg = sixgr.util.structSet(cfg, "phy.pusch.modulation", "pi/2-BPSK");
    cfg = sixgr.util.structSet(cfg, "phy.pusch.pi2BPSKEnabled", true);
    cfg = sixgr.util.structSet(cfg, "phy.pusch.pi2BPSKTransformPrecoding", true);
end
end

function cfg = localApplyPDCCHSurface(cfg, s)
if ~isfield(s, "pdcch")
    return;
end
cfg = sixgr.util.structSet(cfg, "phy.pdcch.yamlSurface", s.pdcch);
cfg = localCopyRuntimeField(cfg, s, "pdcch.blind_decoding_attempts", "phy.pdcch.blindDecodingAttempts");
cfg = localCopyRuntimeField(cfg, s, "pdcch.dmrs_scrambling_id_source", "phy.pdcch.dmrsScramblingIdSource");
cfg = localCopyRuntimeField(cfg, s, "pdcch.rnti_config", "phy.pdcch.rntiConfig");
[startSymbol, hasStart] = localTryGetNestedStrict(s, "pdcch.start_symbol");
[numSymbols, hasNum] = localTryGetNestedStrict(s, "pdcch.num_symbols");
if xor(hasStart, hasNum)
    error("sixgr:phy:frame:InvalidPDCCHTimingAllocation", ...
        "pdcch.start_symbol and pdcch.num_symbols must be configured together.");
end
if hasStart && hasNum
    startValue = double(startSymbol);
    numValue = double(numSymbols);
    cfg = sixgr.util.structSet(cfg, "phy.pdcch.startSymbol", startValue);
    cfg = sixgr.util.structSet(cfg, "phy.pdcch.numSymbols", numValue);
    cfg = sixgr.util.structSet(cfg, "phy.pdcch.symbolAllocation", ...
        [startValue numValue]);
    cfg = sixgr.util.structSet(cfg, "phy.pdcch.SymbolAllocation", ...
        [startValue numValue]);
end
[coresets, hasCoreset] = localTryGetNestedStrict(s, "pdcch.coreset");
if ~hasCoreset
    [coresets, hasCoreset] = localTryGetNestedStrict(s, "pdcch.coresets");
end
if hasCoreset
    cfg = sixgr.util.structSet(cfg, "phy.pdcch.coresets", coresets);
    if isstruct(coresets) && ~isempty(coresets)
        first = coresets(1);
        cfg = localSetFromStructIfPresent(cfg, first, "duration_symbols", "phy.pdcch.coreset.duration");
        cfg = localSetFromStructIfPresent(cfg, first, "coreset_id", "phy.pdcch.coreset.id");
        cfg = localSetFromStructIfPresent(cfg, first, "cce_to_reg_mapping", "phy.pdcch.coreset.cceToREGMapping");
        cfg = localSetFromStructIfPresent(cfg, first, "reg_bundle_size", "phy.pdcch.coreset.regBundleSize");
        cfg = localSetFromStructIfPresent(cfg, first, "interleaver_size", "phy.pdcch.coreset.interleaverSize");
        cfg = localSetFromStructIfPresent(cfg, first, "shift_index", "phy.pdcch.coreset.shiftIndex");
        cfg = localSetFromStructIfPresent(cfg, first, "precoder_granularity", "phy.pdcch.coreset.precoderGranularity");
    end
end
[spaces, hasSpaces] = localTryGetNestedStrict(s, "pdcch.search_spaces");
if hasSpaces
    cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpaces", spaces);
end
end

function localAssertGeometryRuntimeAuthoritySurface(s)
runClass = lower(strtrim(string(localGetNested( ...
    s, "validation.run_class", ""))));
if runClass ~= "ue_placement_geometry_lls"
    return;
end

requiredPaths = [ ...
    "bwp.dl"
    "bwp.ul"
    "bwp.component_carriers"
    "pdsch.execution_profile"
    "pdsch.mapping_type"
    "pdsch.start_symbol"
    "pdsch.num_symbols"
    "pusch.mapping_type"
    "pusch.start_symbol"
    "pusch.num_symbols"
    "pdcch.start_symbol"
    "pdcch.num_symbols"
    "tdd_timing.pdcch_to_pdsch_k0"
    "tdd_timing.pdcch_to_pusch_k2"
    "tdd_timing.dl_harq_feedback_k1"
    "tdd_timing.ul_grant_k2"
    "tdd_timing.n1_pdsch_processing_time_symbols"
    "tdd_timing.n2_pusch_preparation_time_symbols"
    "tdd_timing.capability_profile_id"];
missing = strings(0, 1);
for index = 1:numel(requiredPaths)
    [value, found] = localTryGetNestedStrict(s, requiredPaths(index));
    if ~found || isempty(value)
        missing(end + 1, 1) = requiredPaths(index); %#ok<AGROW>
    end
end
for section = ["pdsch", "pusch"]
    [prbSet, hasPRBSet] = localTryGetNestedStrict( ...
        s, section + ".prb_set");
    [prbStart, hasPRBStart] = localTryGetNestedStrict( ...
        s, section + ".prb_start");
    [numPRB, hasNumPRB] = localTryGetNestedStrict( ...
        s, section + ".num_prb");
    hasExplicitSet = hasPRBSet && ~isempty(prbSet);
    hasExplicitRange = hasPRBStart && ~isempty(prbStart) && ...
        hasNumPRB && ~isempty(numPRB);
    if ~(hasExplicitSet || hasExplicitRange)
        missing(end + 1, 1) = section + ...
            ".prb_set or (" + section + ".prb_start + " + ...
            section + ".num_prb)"; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("sixgr:lls6g:config:MissingGeometryRuntimeAuthority", ...
        "validation.run_class='ue_placement_geometry_lls' requires explicit " + ...
        "geometry runtime fields; missing: %s.", ...
        strjoin(cellstr(missing), ", "));
end

profile = lower(strtrim(string(localGetNested( ...
    s, "pdsch.execution_profile", ""))));
if profile ~= "connected_strict"
    error("sixgr:lls6g:config:GeometryRequiresConnectedStrictPDSCH", ...
        "Geometry truth execution requires pdsch.execution_profile='connected_strict'; received '%s'.", ...
        profile);
end
end

function cfg = localApplyReceiverSurface(cfg, s)
cePairs = {
    "algorithm", "algorithm"
    "interpolation_method", "interpolationMethod"
    "filter_length_time", "filterLengthTime"
    "filter_length_freq", "filterLengthFrequency"
    "noise_variance_source", "noiseVarianceSource"
    "noise_variance_averaging_window_slots", "noiseVarianceAveragingWindowSlots"
    "delay_spread_assumption_ns", "delaySpreadAssumption_ns"
    "doppler_assumption_hz", "dopplerAssumption_Hz"
    "temporal_filtering_enable", "temporalFilteringEnabled"
    "frequency_smoothing_enable", "frequencySmoothingEnabled"
    "perfect_csi", "perfectCSI"
    "ce_extrapolation_mode", "extrapolationMode"
    "ce_bound_delay_ns", "boundDelay_ns"
    "ce_reference_signal", "referenceSignal"
    };
for i = 1:size(cePairs, 1)
    cfg = localCopyRuntimeField(cfg, s, "channel_estimation." + cePairs{i,1}, "phy.channelEstimation." + cePairs{i,2});
end

eqPairs = {
    "algorithm", "algorithm"
    "regularization_method", "regularizationMethod"
    "noise_variance_for_equalizer", "noiseVarianceForEqualizer"
    "post_equalization_snr_estimation", "postEqualizationSNREstimation"
    "irc_interference_covariance_window_slots", "ircInterferenceCovarianceWindowSlots"
    "irc_covariance_estimation", "ircCovarianceEstimation"
    "sv_threshold", "singularValueThreshold"
    "condition_number_cap", "conditionNumberCap"
    "per_prb_equalization", "perPRBEqualization"
    "per_symbol_equalization", "perSymbolEqualization"
    "equalizer_output_scaling", "outputScaling"
    "sic_enable", "sicEnabled"
    "sic_stages", "sicStages"
    };
for i = 1:size(eqPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, "equalization." + eqPairs{i,1}, "phy.equalization." + eqPairs{i,2});
end

rxEqualizer = string(localGetNested(s, "receiver_algorithms.equalizer", ...
    localGetNested(s, "equalization.algorithm", "")));
rxEqualizer = upper(strtrim(rxEqualizer));
if strlength(rxEqualizer) > 0
    cfg = sixgr.util.structSet(cfg, "phy.rx.equalizer", char(rxEqualizer));
    cfg = sixgr.util.structSet(cfg, "phy.pdsch.equalizer", char(rxEqualizer));
    cfg = sixgr.util.structSet(cfg, "phy.pusch.equalizer", char(rxEqualizer));
    cfg = sixgr.util.structSet(cfg, "phy.equalization.algorithm", char(rxEqualizer));
end
end

function cfg = localApplyTimingAndRFHardwareSurface(cfg, s)
syncPairs = {
    "timing_sync_algorithm", "timingSyncAlgorithm"
    "frequency_sync_algorithm", "frequencySyncAlgorithm"
    "symbol_timing_recovery", "symbolTimingRecovery"
    "integer_cfo_correction_enable", "integerCFOCorrectionEnabled"
    "fractional_cfo_correction_enable", "fractionalCFOCorrectionEnabled"
    "timing_tracking_mode", "timingTrackingMode"
    "frequency_tracking_mode", "frequencyTrackingMode"
    "pss_detection_threshold", "pssDetectionThreshold"
    "sss_hypothesis_test_threshold", "sssHypothesisTestThreshold"
    "max_timing_uncertainty_samples", "maxTimingUncertaintySamples"
    "ota_timing_advance_enable", "otaTimingAdvanceEnabled"
    "timing_advance_granularity_ts", "timingAdvanceGranularityTs"
    };
for i = 1:size(syncPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, "synchronization." + syncPairs{i,1}, "phy.synchronization." + syncPairs{i,2});
end

rfPairs = {
    "adc_resolution_bits", "adc.resolutionBits"
    "dac_resolution_bits", "dac.resolutionBits"
    "adc_dynamic_range_db", "adc.dynamicRange_dB"
    "adc_full_scale_power_dBm", "adc.fullScalePower_dBm"
    "adc_full_scale", "adc.fullScale"
    "agc_enable", "agc.enabled"
    "agc_target_level_dBm", "agc.targetLevel_dBm"
    "agc_target_rms", "agc.targetRms"
    "agc_max_gain_db", "agc.maxGain_dB"
    "agc_min_gain_db", "agc.minGain_dB"
    "agc_attack_time_us", "agc.attackTime_us"
    "agc_release_time_us", "agc.releaseTime_us"
    "dc_offset_enable", "dcOffset.enabled"
    "dc_offset_level_dBc", "dcOffset.level_dBc"
    "dc_offset_compensation_enable", "dcOffset.compensationEnabled"
    "lna_gain_dB", "lna.gain_dB"
    "rx_gain_dB", "rxGain_dB"
    "tx_gain_dB", "txGain_dB"
    "mutual_coupling_matrix_enable", "mutualCouplingMatrixEnabled"
    };
for i = 1:size(rfPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, "rf_hardware." + rfPairs{i,1}, "rf.hardware." + rfPairs{i,2});
end

rfFrontend = localGetNested(s, "rf_frontend", struct());
if isstruct(rfFrontend) && ~isempty(fieldnames(rfFrontend))
    cfg = sixgr.util.structSet(cfg, "rf.frontend", rfFrontend);
    cfg = localCopyRuntimeField(cfg, s, "rf_frontend.enabled", "rf.enable");
    cfg = localCopyRuntimeField(cfg, s, "rf_frontend.profile_id", ...
        "rf.specification.profile_id");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.specification_version", ...
        "rf.specification.version");
    cfg = localCopyRuntimeField(cfg, s, "rf_frontend.claim_class", ...
        "rf.specification.claim_class");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.configuration_epoch", "rf.configurationEpoch");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.reference_plane.impedance_ohm", ...
        "rf.referencePlane.impedance_Ohm");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.agc.enabled", "rf.rx.agc.enable");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.agc.target_rms", "rf.rx.agc.targetRms");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.agc.max_gain_db", "rf.rx.agc.maxGain_dB");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.agc.min_gain_db", "rf.rx.agc.minGain_dB");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.adc.enabled", "rf.adc.enable");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.adc.bits", "rf.adcBits");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.receiver.adc.full_scale", "rf.adc.fullScale");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.dac.bits", "rf.dacBits");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.pa.enabled", "rf.pa.enable");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.pa.model", "rf.pa.method");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.pa.input_backoff_db", "rf.pa.backoff_dB");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.phase_noise.enabled", "rf.phaseNoise.enable");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.phase_noise.mask_offsets_hz", ...
        "rf.phaseNoise.maskOffsets_Hz");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.phase_noise.mask_levels_dbchz", ...
        "rf.phaseNoise.maskLevels_dBcHz");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.timing_and_sample_clock.sco_ppm", ...
        "phy.impairments.sampleClockOffsetPpm");
    cfg = localCopyRuntimeField(cfg, s, ...
        "rf_frontend.ul_power_control.require_measured_reference_rs", ...
        "phy.pusch.power_control.requireMeasuredReferenceRS");
    profileId = string(localGetNested(rfFrontend, "profile_id", ""));
    if strlength(strtrim(profileId)) > 0
        profile = sixgr.rf.runtime.RFSpecificationProfile.resolve(profileId);
        configuredClaim = upper(strtrim(string(localGetNested( ...
            rfFrontend, "claim_class", profile.ClaimClass))));
        if configuredClaim ~= upper(string(profile.ClaimClass))
            error("RF:UnsupportedProfile", ...
                "RF profile claim_class does not match the immutable profile.");
        end
        cfg = sixgr.util.structSet(cfg, ...
            "rf.specification.resolvedProfile",profile);
    end
end

tddPairs = {
    "pdcch_to_pdsch_k0", "pdcchToPDSCHK0"
    "pdcch_to_pusch_k2", "pdcchToPUSCHK2"
    "dl_harq_feedback_k1", "dlHARQFeedbackK1Candidates"
    "ul_grant_k2", "ulGrantK2"
    "harq_roundtrip_slots", "harqRoundtripSlots"
    "dl_to_ul_guard_time_us", "dlToULGuardTime_us"
    "timing_advance_max_us", "timingAdvanceMax_us"
    "n1_pdsch_processing_time_symbols", "n1PDSCHProcessingTimeSymbols"
    "n2_pusch_preparation_time_symbols", "n2PUSCHPreparationTimeSymbols"
    "capability_profile_id", "capabilityProfileID"
    };
for i = 1:size(tddPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, "tdd_timing." + tddPairs{i,1}, "phy.tddTiming." + tddPairs{i,2});
end
cfg = localCopyRuntimeField(cfg, s, "tdd_timing.ul_grant_k2", "mac.harq.k2");
cfg = localCopyRuntimeField(cfg, s, "tdd_timing.ul_grant_k2", "phy.pusch.k2_slots");
cfg = localCopyRuntimeField(cfg, s, "tdd_timing.pdcch_to_pusch_k2", "phy.ul.grantK2Slots");
end

function cfg = localApplyPhase07MIMOConfig(cfg,s)
section = localGetNested(s,"mimo.phase07_strict",struct());
if ~isstruct(section) || isempty(fieldnames(section))
    cfg = sixgr.util.structSet(cfg,"phy.mimo.strict",false);
    return;
end
enabled = logical(localGetNested(section,"enabled",false));
profileID = string(localGetNested(section,"profile_id",""));
direction = upper(string(localGetNested(section,"direction","DL")));
codebookType = string(localGetNested(section,"codebook_type",""));
ports = double(localGetNested(section,"ports",NaN));
panels = double(localGetNested(section,"panels",NaN));
n1 = double(localGetNested(section,"n1",NaN));
n2 = double(localGetNested(section,"n2",NaN));
o1 = double(localGetNested(section,"o1",NaN));
o2 = double(localGetNested(section,"o2",NaN));
maxRank = double(localGetNested(section,"max_rank",NaN));
rankDomain = double(localGetNested(section,"rank_domain",[]));
receiver = upper(string(localGetNested(section,"receiver","MMSE")));

cfg = sixgr.util.structSet(cfg,"phy.mimo.strict",enabled);
cfg = sixgr.util.structSet(cfg,"phy.mimo.profileID",char(profileID));
cfg = sixgr.util.structSet(cfg,"phy.mimo.specificationProfile",char(string( ...
    localGetNested(section,"specification_profile","3GPP_R18_MIMO_CSI_V1"))));
cfg = sixgr.util.structSet(cfg,"phy.mimo.direction",char(direction));
cfg = sixgr.util.structSet(cfg,"phy.mimo.codebookType",char(codebookType));
cfg = sixgr.util.structSet(cfg,"phy.mimo.ports",ports);
cfg = sixgr.util.structSet(cfg,"phy.mimo.panels",panels);
cfg = sixgr.util.structSet(cfg,"phy.mimo.N1",n1);
cfg = sixgr.util.structSet(cfg,"phy.mimo.N2",n2);
cfg = sixgr.util.structSet(cfg,"phy.mimo.O1",o1);
cfg = sixgr.util.structSet(cfg,"phy.mimo.O2",o2);
cfg = sixgr.util.structSet(cfg,"phy.mimo.maxRank",maxRank);
cfg = sixgr.util.structSet(cfg,"phy.csi.maxRank",maxRank);
cfg = sixgr.util.structSet(cfg,"phy.csi.rankDomain",rankDomain(:).');
cfg = sixgr.util.structSet(cfg,"phy.rx.detector",char(receiver));
cfg = sixgr.util.structSet(cfg,"phy.mimo.precoderPRGSizeRBs",double( ...
    localGetNested(section,"precoder_prg_size_rbs",NaN)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.requireActiveTCIState",logical( ...
    localGetNested(section,"require_active_tci_state",false)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.measurementMaxAgeSlots",double( ...
    localGetNested(section,"measurement_max_age_slots",8)));

covariance = localGetNested(section,"covariance",struct());
cfg = sixgr.util.structSet(cfg,"phy.mimo.covariance.minSamples",double( ...
    localGetNested(covariance,"min_samples",16)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.covariance.maxAgeSlots",double( ...
    localGetNested(covariance,"max_age_slots",8)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.covariance.shrinkageFactor",double( ...
    localGetNested(covariance,"shrinkage_factor",.05)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.covariance.conditionNumberLimit",double( ...
    localGetNested(covariance,"condition_number_limit",1e12)));

srsAuthority = localGetNested(section,"ul_srs_authority",struct());
cfg = sixgr.util.structSet(cfg,"phy.mimo.ulSRSAuthority.enabled",logical( ...
    localGetNested(srsAuthority,"enabled",false)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.ulSRSAuthority.maxAgeSlots",double( ...
    localGetNested(srsAuthority,"max_age_slots",8)));
cfg = sixgr.util.structSet(cfg,"phy.mimo.ulSRSAuthority.configuredOverrideForbidden",logical( ...
    localGetNested(srsAuthority,"configured_override_forbidden",true)));

report = localGetNested(section,"csi_report",struct());
reportRequest = struct( ...
    "ReportConfigID",string(localGetNested(report,"report_config_id","")), ...
    "Epoch",double(localGetNested(report,"epoch",NaN)), ...
    "CodebookType",codebookType, ...
    "Ports",ports, ...
    "Rank",maxRank, ...
    "ReportQuantity",string(localGetNested(report,"report_quantity","")), ...
    "NumCSIResources",double(localGetNested(report,"num_csi_resources",NaN)), ...
    "FrequencyGranularity",string(localGetNested(report,"frequency_granularity","")), ...
    "UCIChannel",upper(string(localGetNested(report,"uci_channel","PUCCH"))), ...
    "NumSubbands",double(localGetNested(report,"num_subbands",1)), ...
    "NumberOfBeams",double(localGetNested(report,"number_of_beams",1)), ...
    "PhaseAlphabetSize",double(localGetNested(report,"phase_alphabet_size",4)));
cfg = sixgr.util.structSet(cfg,"phy.csi.reportConfiguration",reportRequest);
cfg = sixgr.util.structSet(cfg,"phy.csi.reportConfigurationEpoch",reportRequest.Epoch);

if ~enabled
    return;
end
numericPositive = [ports panels n1 n2 o1 o2 maxRank];
if any(~isfinite(numericPositive) | numericPositive < 1 | ...
        numericPositive ~= round(numericPositive)) || isempty(rankDomain)
    error("sixgr:mimo:UnsupportedAntennaTuple", ...
        "Enabled Phase-07 MIMO requires explicit positive integer ports, panel, N/O and rank fields.");
end
if any(rankDomain < 1 | rankDomain > maxRank | rankDomain ~= round(rankDomain))
    error("sixgr:mimo:InvalidRI", ...
        "mimo.phase07_strict.rank_domain is outside max_rank.");
end
if ~ismember(receiver,["MMSE","IRC","ZF"])
    error("sixgr:mimo:InvalidReceiver", ...
        "Phase-07 receiver must be MMSE, IRC or ZF.");
end
request = struct("ProfileID",profileID,"Direction",direction, ...
    "CodebookType",codebookType,"Ports",ports,"Panels",panels, ...
    "N1",n1,"N2",n2,"O1",o1,"O2",o2,"Rank",maxRank);
sixgr.phy.mimo.MIMOCapabilityProfile().resolve(request);
sixgr.phy.mimo.CSIReportConfiguration(reportRequest,reportRequest.Epoch);
if direction == "DL"
    cfg = sixgr.util.structSet(cfg,"phy.pdsch.numPorts",ports);
    cfg = sixgr.util.structSet(cfg,"phy.pdsch.normalizePrecodingMatrix",false);
end
end

function cfg = localApplyAuxiliaryPHYKnobs(cfg, s)
auxPairs = {
    "coding.ldpc_lifting_size_z_selection", "phy.ldpc.liftingSizeZSelection"
    "coding.ldpc_schedule_type", "phy.ldpc.scheduleType"
    "coding.ldpc_min_sum_offset", "phy.ldpc.minSumOffset"
    "coding.polar_reliability_sequence_source", "phy.polar.reliabilitySequenceSource"
    "coding.polar_rate_matching_type", "phy.polar.rateMatchingType"
    "mimo.sv_rank_threshold", "phy.mimo.svRankThreshold"
    "mimo.precoder_prg_size_rbs", "phy.mimo.precoderPRGSizeRBs"
    "mimo.codebook_subset_restriction", "phy.mimo.codebookSubsetRestriction"
    "mimo.type2_codebook_oversampling_factor_O1", "phy.mimo.type2CodebookOversamplingO1"
    "mimo.type2_codebook_oversampling_factor_O2", "phy.mimo.type2CodebookOversamplingO2"
    "mimo.csi_rs_based_precoder_update", "phy.mimo.csirsBasedPrecoderUpdate"
    "reference_signals.srs_comb_size", "phy.srs.KTC"
    "reference_signals.srs_comb_offset", "phy.srs.KBarTC"
    "reference_signals.srs_nrof_symbols", "phy.srs.NumSRSSymbols"
    "reference_signals.srs_nrof_antenna_ports", "phy.srs.nPorts"
    "reference_signals.srs_guard_band_nrof_rbs", "phy.srs.guardBandNumRBs"
    "reference_signals.srs_freq_domain_position", "phy.srs.FrequencyStart"
    "reference_signals.srs_freq_domain_shift", "phy.srs.FrequencyShift"
    "reference_signals.srs_cyclic_shift", "phy.srs.CyclicShift"
    "reference_signals.srs_resource_type", "phy.srs.resourceType"
    "reference_signals.csi_rs_row_index", "phy.csirs.rowIndex"
    "reference_signals.csi_rs_first_ofdm_symbol_in_time_domain", "phy.csirs.firstOFDMSymbol"
    "reference_signals.csi_rs_sequence_id", "phy.csirs.scramblingID"
    "reference_signals.dmrs_scrambling_id_source", "phy.dmrs.scramblingIdSource"
    "reference_signals.dmrs_scrambling_id", "phy.dmrs.scramblingID"
    "reference_signals.dmrs_port_to_layer_mapping", "phy.dmrs.portToLayerMapping"
    "link_adaptation.olla_init_offset_db", "phy.linkAdaptation.ollaInitialOffset_dB"
    "link_adaptation.olla_max_offset_db", "phy.linkAdaptation.ollaMaxOffset_dB"
    "link_adaptation.olla_min_offset_db", "phy.linkAdaptation.ollaMinOffset_dB"
    "link_adaptation.olla_window_size_slots", "phy.linkAdaptation.ollaWindowSizeSlots"
    "link_adaptation.olla_forgetting_factor", "phy.linkAdaptation.ollaForgettingFactor"
    "link_adaptation.rank_threshold", "phy.linkAdaptation.rankThreshold"
    "link_adaptation.rank_threshold", "phy.mimo.svRankThreshold"
    "link_adaptation.min_sinr_for_rank2_dB", "phy.linkAdaptation.minSINRForRank2_dB"
    "link_adaptation.bootstrap_min_cqi_for_scheduling", "phy.linkAdaptation.bootstrapMinCQIForScheduling"
    "link_adaptation.dl_bootstrap_min_cqi_for_scheduling", "phy.linkAdaptation.dlBootstrapMinCQIForScheduling"
    "link_adaptation.ul_bootstrap_min_cqi_for_scheduling", "phy.linkAdaptation.ulBootstrapMinCQIForScheduling"
    "link_adaptation.bootstrap_preview_backoff_db", "phy.linkAdaptation.bootstrapPreviewBackoff_dB"
    "link_adaptation.bootstrap_preview_backoff_dB", "phy.linkAdaptation.bootstrapPreviewBackoff_dB"
    "link_adaptation.dl_bootstrap_preview_backoff_db", "phy.linkAdaptation.dlBootstrapPreviewBackoff_dB"
    "link_adaptation.ul_bootstrap_preview_backoff_db", "phy.linkAdaptation.ulBootstrapPreviewBackoff_dB"
    "link_adaptation.ul_srs_to_pusch_sinr_backoff_db", "phy.linkAdaptation.ulSRSToPUSCHSINRBackoff_dB"
    "link_adaptation.ul_reference_signal_scheduling_backoff_db", "phy.linkAdaptation.ulReferenceSignalSchedulingBackoff_dB"
    "link_adaptation.age_reported_cqi", "phy.linkAdaptation.ageReportedCQI"
    "link_adaptation.use_aged_measured_sinr_for_cqi", "phy.linkAdaptation.useAgedMeasuredSINRForCQI"
    "link_adaptation.max_csi_aging_penalty_db", "phy.linkAdaptation.maxCSIAgingPenalty_dB"
    "link_adaptation.cqi_aging_step_db", "phy.linkAdaptation.cqiAgingStep_dB"
    "link_adaptation.max_csi_age_slots", "phy.linkAdaptation.maxCSIAgeSlots"
    "link_adaptation.dl_max_csi_age_slots", "phy.linkAdaptation.dlMaxCSIAgeSlots"
    "link_adaptation.ul_max_csi_age_slots", "phy.linkAdaptation.ulMaxCSIAgeSlots"
    "link_adaptation.mcs_backoff_dl_db", "phy.linkAdaptation.dlMCSBackoff_dB"
    "link_adaptation.mcs_backoff_ul_db", "phy.linkAdaptation.ulMCSBackoff_dB"
    "link_adaptation.sinr_to_cqi_mapping_table", "phy.linkAdaptation.sinrToCQITable"
    "link_adaptation.queue_aware_rank_mcs_reduction_enable", "phy.linkAdaptation.queueAwareRankMCSReductionEnable"
    "link_adaptation.queue_aware_layer_decrement_max", "phy.linkAdaptation.queueAwareLayerDecrementMax"
    "link_adaptation.queue_aware_mcs_decrement_max", "phy.linkAdaptation.queueAwareMCSDecrementMax"
    "link_adaptation.queue_aware_mcs_decrement_step1", "phy.linkAdaptation.queueAwareMCSDecrementStep1"
    "link_adaptation.queue_aware_mcs_decrement_step2", "phy.linkAdaptation.queueAwareMCSDecrementStep2"
    "link_adaptation.queue_aware_prb_delta1_fraction", "phy.linkAdaptation.queueAwarePRBDelta1Fraction"
    "link_adaptation.queue_aware_prb_delta2_fraction", "phy.linkAdaptation.queueAwarePRBDelta2Fraction"
    "channels.cdl_delay_profile_scaling", "channel.cdlDelayProfileScaling"
    "channels.xpr_db", "channel.xpr_dB"
    "channels.antenna_element_spacing_dl_lambda", "channel.antennaElementSpacingDL_lambda"
    "channels.antenna_element_spacing_ul_lambda", "channel.antennaElementSpacingUL_lambda"
    "channels.spatial_filter_order", "channel.spatialFilterOrder"
    "channels.channel_filter_length_samples", "channel.filterLengthSamples"
    "channels.perfect_csi", "channel.perfectCSI"
    "harq.cbg_nrof_code_block_groups", "phy.harq.cbgNumCodeBlockGroups"
    "harq.dl_harq_ack_codebook_type", "phy.harq.dlACKCodebookType"
    "harq.harq_process_ndi_initialization", "phy.harq.ndiInitialization"
    "impairments.clipping_ratio_db", "phy.impairments.clippingRatio_dB"
    "impairments.oob_emission_limit_dBr", "phy.impairments.oobEmissionLimit_dBr"
    "impairments.rx_spur_level_dBc", "phy.impairments.rxSpurLevel_dBc"
    "impairments.local_oscillator_leakage_dBc", "phy.impairments.localOscillatorLeakage_dBc"
    };
for i = 1:size(auxPairs, 1)
    cfg = localCopyRuntimeField(cfg, s, auxPairs{i,1}, auxPairs{i,2});
end

% Accept both common spellings and drive one internal DMRS type-A field.
cfg = localCopyRuntimeField(cfg, s, "reference_signals.pdsch_dmrs_typeA_position", "phy.pdsch.dmrs.typeApos");
cfg = localCopyRuntimeField(cfg, s, "reference_signals.pusch_dmrs_typeA_position", "phy.pusch.dmrs.typeApos");
end

function cfg = localCopyRuntimeField(cfg, s, sourcePath, targetPath)
[value, found] = localTryGetNestedStrict(s, sourcePath);
if found
    cfg = sixgr.util.structSet(cfg, targetPath, value);
end
end

function mappingType = localNormalizeDataChannelMappingType(value, sourcePath)
tokens = string(value);
if numel(tokens) ~= 1
    error("sixgr:lls6g:config:BadDataChannelMappingType", ...
        "Scenario field '%s' must be a scalar PDSCH/PUSCH mapping type.", string(sourcePath));
end
token = lower(regexprep(strtrim(tokens), "[_\-\s]", ""));
switch token
    case {"a", "typea"}
        mappingType = "A";
    case {"b", "typeb"}
        mappingType = "B";
    otherwise
        error("sixgr:lls6g:config:BadDataChannelMappingType", ...
            "Scenario field '%s' has invalid mapping type '%s'. Allowed values are A, B, typeA, or typeB.", ...
            string(sourcePath), tokens);
end
end

function cfg = localSetFromStructIfPresent(cfg, valueStruct, fieldName, targetPath)
if isstruct(valueStruct) && isfield(valueStruct, char(fieldName))
    cfg = sixgr.util.structSet(cfg, targetPath, valueStruct.(char(fieldName)));
end
end

function cfg = localAppendValidationObjectives(cfg, tokens)
existing = localStringVector(sixgr.util.structGet(cfg, "validation.objectives", strings(0, 1)));
tokens = localStringVector(tokens);
values = unique([existing; tokens], "stable");
cfg = sixgr.util.structSet(cfg, "validation.objectives", cellstr(values));
end

function tf = localChannelRFStrictRequiredByRuntime(cfg)
strictReferenceRequired = any([
    logical(sixgr.util.structGet(cfg, "run.controlGating.prachRequired", false))
    logical(sixgr.util.structGet(cfg, "run.controlGating.srsRequired", false))
    logical(sixgr.util.structGet(cfg, "run.controlGating.trsRequired", false))]);
channelModel = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
fadingProfile = strtrim(string(sixgr.util.structGet(cfg, "channel.fading.profile", ...
    sixgr.util.structGet(cfg, "channel.delayProfile", ""))));
rfEnabled = logical(sixgr.util.structGet(cfg, "rf.enable", false));
interferenceEnabled = logical(sixgr.util.structGet(cfg, "channel_rf.interferenceEnabled", false));
interferenceMode = lower(strtrim(string(sixgr.util.structGet(cfg, "run.interferenceExecutionMode", "none"))));
hasNonAwgnChannel = ~(channelModel == "" || channelModel == "AWGN") || strlength(fadingProfile) > 0;
hasRFOrInterference = rfEnabled || interferenceEnabled || ~any(interferenceMode == ["", "none", "disabled", "off"]);
tf = strictReferenceRequired && (hasNonAwgnChannel || hasRFOrInterference);
end

function tf = localHasNestedPath(s, path)
tf = false;
if ~(isstruct(s) && isscalar(s))
    return;
end
parts = split(string(path), ".");
cur = s;
for ii = 1:numel(parts)
    key = char(parts(ii));
    if ~(isstruct(cur) && isscalar(cur) && isfield(cur, key))
        return;
    end
    cur = cur.(key);
end
tf = true;
end

function values = localStringVector(raw)
if isempty(raw)
    values = strings(0, 1);
elseif isstring(raw)
    values = raw(:);
elseif ischar(raw)
    values = string(raw);
elseif iscell(raw)
    values = strings(numel(raw), 1);
    for i = 1:numel(raw)
        values(i) = string(raw{i});
    end
else
    values = string(raw);
end
values = strtrim(values(:));
values = values(strlength(values) > 0);
end

function tf = localShouldDisableExactMexForStrictCoupledTruthWaveform(s, runnerProfile)
% Coupled waveform truth on fading channels is currently unsafe under
% exact-MEX acceleration on this server. Keep these runs on the MATLAB path
% so the scenario completes honestly instead of crashing the process.
runnerProfile = lower(strtrim(string(runnerProfile)));
executionModel = lower(strtrim(string(localGetNested(s, "users.execution_model", ""))));
channelModel = upper(strtrim(string(localGetNested(s, "channels.model_type", "AWGN"))));
tf = channelModel ~= "AWGN" && (runnerProfile == "system_level_lls" || ...
    (runnerProfile == "waveform_bundle" && executionModel == "slot_coupled_truth"));
end

function cfg = localApplyFrameStructureEngine(cfg, fs)
if nargin < 2 || ~isa(fs, "sixgr.phy.FrameStructureEngine") || ...
        ~isscalar(fs)
    error("sixgr:lls6g:config:MissingValidatedFrameStructure", ...
        "buildInternalConfig requires the FrameStructureEngine instance produced by validateConfig.");
end
fsStruct = fs.toStruct();

cfg = sixgr.util.structSet(cfg, "phy.frameStructure", fsStruct);
cfg = sixgr.util.structSet(cfg, "resolved_runtime_view.frame_structure", fsStruct);

cfg.phy.carrier.SubcarrierSpacing = double(fs.SCSkHz);
cfg.phy.carrier.SubcarrierSpacing_kHz = double(fs.SCSkHz);
cfg.phy.carrier.CyclicPrefix = char(fs.CyclicPrefix);
cfg.phy.carrier.NSizeGrid = double(fs.NRB);

cfg = sixgr.util.structSet(cfg, "phy.numerology.mu", double(fs.Mu));
cfg = sixgr.util.structSet(cfg, "phy.numerology.scs_kHz", double(fs.SCSkHz));
cfg = sixgr.util.structSet(cfg, "phy.numerology.slotsPerFrame", double(fs.SlotsPerFrame));
cfg = sixgr.util.structSet(cfg, "phy.numerology.slotDuration_ms", double(fs.SlotDuration_ms));
cfg = sixgr.util.structSet(cfg, "phy.numerology.symbolsPerSlot", double(fs.SymbolsPerSlot));
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridNumRBs", double(fs.NRB));
cfg = sixgr.util.structSet(cfg, "phy.numerology.configuredGridNumRBs", double(fs.ConfiguredGridNumRBs));
cfg = sixgr.util.structSet(cfg, "phy.numerology.activeGridSource", char(fs.ActiveGridSource));
cfg = sixgr.util.structSet(cfg, "phy.numerology.numerologySource", ...
    char(fs.Numerology.Source));
cfg = sixgr.util.structSet(cfg, "phy.numerology.timingInterpretationSource", ...
    "canonical_numerology_catalog");
cfg = sixgr.util.structSet(cfg, "resolved_runtime_view.active_grid_num_rbs", double(fs.NRB));
cfg = sixgr.util.structSet(cfg, "resolved_runtime_view.configured_grid_num_rbs", double(fs.ConfiguredGridNumRBs));
cfg = sixgr.util.structSet(cfg, "resolved_runtime_view.active_grid_source", char(fs.ActiveGridSource));

cfg = sixgr.util.structSet(cfg, "phy.waveform.fftSize", double(fs.FFTSize));
cfg = sixgr.util.structSet(cfg, "phy.waveform.sampleRate_Hz", double(fs.SampleRate_Hz));
cfg = sixgr.util.structSet(cfg, "phy.ofdm", fs.OFDMSampling);
cfg = sixgr.util.structSet(cfg, "waveform.fft_size", double(fs.FFTSize));
cfg = sixgr.util.structSet(cfg, "waveform.sample_rate_hz", double(fs.SampleRate_Hz));

cfg.phy.duplex.mode = char(fs.DuplexMode);
if fs.DuplexMode == "FDD"
    cfg = sixgr.util.structSet(cfg, "phy.duplex.fddContexts", ...
        fsStruct.FDDContexts);
    cfg = sixgr.util.structSet(cfg, "frame_timing.tdd_pattern_applicable", false);
    cfg = sixgr.util.structSet(cfg, "frame_timing.active_tdd_pattern", "not_applicable");
else
    common = fsStruct.SlotState.CommonDirection;
    resolved = fsStruct.SlotState.ResolvedDirection;
    compactTokens = repmat('F', 1, size(common, 1));
    compactTokens(all(common == 'D', 2)) = 'D';
    compactTokens(all(common == 'U', 2)) = 'U';
    cfg.phy.duplex.tddPattern = compactTokens;
    cfg = sixgr.util.structSet(cfg, "phy.duplex.slotState", fsStruct.SlotState);
    cfg = sixgr.util.structSet(cfg, "frame_timing.tdd_pattern", compactTokens);
    cfg = sixgr.util.structSet(cfg, "frame_timing.tdd_pattern_applicable", true);
    cfg = sixgr.util.structSet(cfg, "frame_timing.active_tdd_pattern", compactTokens);
    cfg = sixgr.util.structSet(cfg, ...
        "frame_timing.common_direction", common);
    cfg = sixgr.util.structSet(cfg, ...
        "frame_timing.resolved_direction", resolved);
end
cfg = sixgr.util.structSet(cfg, "frame_timing.symbols_per_slot", double(fs.SymbolsPerSlot));
cfg = sixgr.util.structSet(cfg, "frame_timing.slots_per_frame", double(fs.SlotsPerFrame));
cfg = sixgr.util.structSet(cfg, "frame_timing.slot_duration_ms", double(fs.SlotDuration_ms));

if ~isempty(fieldnames(fs.SSBTiming))
    cfg = sixgr.util.structSet(cfg, "phy.ssb.timing", fs.SSBTiming);
    cfg = sixgr.util.structSet(cfg, "phy.ssb.case", char(fs.SSBCase));
    cfg = sixgr.util.structSet(cfg, "phy.ssb.Lmax", double(fs.SSBLmax));
    configuredSSBBeamCount = double(sixgr.util.structGet(cfg, ...
        "reference_signals.ssb_beam_count", ...
        sixgr.util.structGet(cfg, "phy.ssb.beamCount", ...
        sixgr.util.structGet(cfg, "phy.ssb.nBeams", fs.SSBLmax))));
    if ~(isscalar(configuredSSBBeamCount) && ...
            isfinite(configuredSSBBeamCount) && ...
            configuredSSBBeamCount == round(configuredSSBBeamCount) && ...
            configuredSSBBeamCount >= 1 && ...
            configuredSSBBeamCount <= fs.SSBLmax)
        error("sixgr:phy:frame:InvalidSSBBeamCount", ...
            "Configured SSB beam count must be an integer in [1,Lmax=%d].", ...
            fs.SSBLmax);
    end
    cfg = sixgr.util.structSet(cfg, ...
        "phy.ssb.beamCount", configuredSSBBeamCount);
    cfg = sixgr.util.structSet(cfg, ...
        "phy.ssb.nBeams", configuredSSBBeamCount);
    cfg = sixgr.util.structSet(cfg, ...
        "phy.ssb.candidateSymbols", double(fs.SSBCandidateSymbols));
end

localValidatePreservedAllocation(cfg, "phy.pdsch", fs.SymbolsPerSlot);
localValidatePreservedAllocation(cfg, "phy.pusch", fs.SymbolsPerSlot);

if ~isempty(fieldnames(fs.PRACHTiming))
    cfg = sixgr.util.structSet(cfg, "phy.prach.timing", fs.PRACHTiming);
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.preambleFormat", char(fs.PRACHFormat));
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.startSymbol", double(fs.PRACHStartSymbol));
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.durationSymbols", double(fs.PRACHDurationSymbols));
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.validSlots1Based", double(fs.PRACHValidSlots1Based));
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.validSlots0Based", double(fs.PRACHValidSlots0Based));
    cfg = sixgr.util.structSet(cfg, ...
        "phy.prach.validationStatus", char(fs.PRACHValidationStatus));
    cfg = sixgr.util.structSet(cfg, "prach_lls.NSizeGrid", double(fs.NRB));
    cfg = sixgr.util.structSet(cfg, ...
        "prach_lls.PRACHFormat", char(fs.PRACHFormat));
    cfg = sixgr.util.structSet(cfg, ...
        "prach_lls.ValidSlots1Based", double(fs.PRACHValidSlots1Based));
    cfg = sixgr.util.structSet(cfg, ...
        "prach_lls.ValidSlots0Based", double(fs.PRACHValidSlots0Based));
end

[runtimeState, ~] = sixgr.phy.frame.FrameRuntimeStateBuilder.build(cfg);
cfg = sixgr.util.structSet(cfg, ...
    "phy.frameStructure.TimingContext", runtimeState);
cfg = sixgr.util.structSet(cfg, ...
    "resolved_runtime_view.frame_structure.TimingContext", runtimeState);
cfg = sixgr.util.structSet(cfg, ...
    "phy.frame.ComponentCarriers", runtimeState.ComponentCarriers);
cfg = sixgr.util.structSet(cfg, ...
    "phy.frame.BWPState", runtimeState.BWPState);
cfg = sixgr.util.structSet(cfg, ...
    "phy.frame.Policy", runtimeState.Policy);
cfg = sixgr.util.structSet(cfg, ...
    "phy.frame.DefaultIdentity", runtimeState.DefaultIdentity);
end

function localValidatePreservedAllocation(cfg, basePath, symbolsPerSlot)
allocation = sixgr.util.structGet(cfg, basePath + ".symbolAllocation", []);
if isempty(allocation)
    start = sixgr.util.structGet(cfg, basePath + ".startSymbol", []);
    count = sixgr.util.structGet(cfg, basePath + ".numSymbols", []);
    if isempty(start) && isempty(count)
        return;
    end
    if isempty(start) || isempty(count)
        error("sixgr:phy:frame:InvalidTDRA", ...
            "%s requires both startSymbol and numSymbols.", basePath);
    end
    allocation = [double(start), double(count)];
end
values = double(allocation(:).');
if numel(values) ~= 2
    error("sixgr:phy:frame:InvalidTDRA", ...
        "%s.symbolAllocation must be [StartSymbol NumSymbols].", basePath);
end
tdra = struct("StartSymbol", values(1), "NumSymbols", values(2));
sixgr.phy.frame.ResourceAllocationValidator.resolveTDRA( ...
    tdra, symbolsPerSlot);
end

function timing = localResolveRunTiming(s)
mu = double(localRequireNested(s, ...
    "global_radio_scope.numerology_mu", ...
    "global_radio_scope.numerology_mu"));
slotDuration_ms = double(localRequireNested(s, ...
    "frame_timing.slot_duration_ms", ...
    "frame_timing.slot_duration_ms"));
slotsPerFrame = double(localRequireNested(s, ...
    "frame_timing.slots_per_frame", ...
    "frame_timing.slots_per_frame"));
if ~(isscalar(mu) && isfinite(mu) && mu >= 0 && mu == fix(mu) && ...
        isscalar(slotDuration_ms) && isfinite(slotDuration_ms) && ...
        slotDuration_ms > 0 && isscalar(slotsPerFrame) && ...
        isfinite(slotsPerFrame) && slotsPerFrame >= 1 && ...
        slotsPerFrame == fix(slotsPerFrame))
    error("sixgr:lls6g:config:InvalidDeclaredFrameTiming", ...
        "Declared numerology_mu, slot_duration_ms, and slots_per_frame must be finite and valid.");
end

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

function slots = localResolvePeriodSlotsFromMsOrSlots(s, runTiming, slotPaths, msPaths, defaultSlots)
slots = NaN;
for i = 1:numel(slotPaths)
    candidate = localNumericScalarOrNaN(localGetNested(s, slotPaths(i), NaN));
    if isfinite(candidate) && candidate > 0
        slots = max(1, round(double(candidate)));
        return;
    end
end
slotDurationMs = max(eps, double(runTiming.TotalTime_ms) / max(double(runTiming.TotalSlots), 1));
for i = 1:numel(msPaths)
    candidateMs = localNumericScalarOrNaN(localGetNested(s, msPaths(i), NaN));
    if isfinite(candidateMs) && candidateMs > 0
        slots = max(1, round(double(candidateMs) / slotDurationMs));
        return;
    end
end
candidate = localNumericScalarOrNaN(defaultSlots);
if isfinite(candidate) && candidate > 0
    slots = max(1, round(double(candidate)));
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

function token = localNormalizePDCCHSearchSpaceType(value)
raw = lower(strtrim(string(value)));
switch raw
    case {"uss", "ue_specific", "ue-specific", "ue"}
        token = "ue";
    case {"css", "common"}
        token = "common";
    otherwise
        token = char(raw);
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

trafficModel = char(localNormalizeTrafficModel(localRequireNested(s, "traffic.model", "traffic.model")));
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

function token = localNormalizeTrafficModel(value)
raw = string(value);
normalized = lower(strtrim(raw));
switch normalized
    case {"full_buffer", "fullbuffer"}
        token = "fullBuffer";
    case {"tracereplay", "trace_replay"}
        token = "traceReplay";
    otherwise
        token = char(raw);
end
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
    tbsMode = char(string(localGetNested(s, "system.scheduler.tbsMode", "faithful")));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.tbsMode", tbsMode);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.tbsMode", tbsMode);
    fastNREApprox = logical(localGetNested(s, "system.scheduler.fastNREApprox", false));
    if any(strcmpi(tbsMode, {'faithful','strict'}))
        fastNREApprox = false;
    end
    cfg = sixgr.util.structSet(cfg, "system.scheduler.fastNREApprox", fastNREApprox);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.fastNREApprox", fastNREApprox);
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
    beamUpdatePeriodSlots = double(localRequireNested(s, "system.beam.updatePeriod_slots", "system.beam.updatePeriod_slots"));
    beamUpdatePeriodMs = localNumericScalarOrNaN(localGetNested(s, "system.beam.updatePeriod_ms", NaN));
    if isfinite(beamUpdatePeriodMs) && beamUpdatePeriodMs > 0
        slotDurationForBeamMs = localNumericScalarOrNaN(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", NaN));
        if ~isfinite(slotDurationForBeamMs) || slotDurationForBeamMs <= 0
            slotDurationForBeamMs = localNumericScalarOrNaN(localGetNested(s, "frame_timing.slot_duration_ms", NaN));
        end
        if isfinite(slotDurationForBeamMs) && slotDurationForBeamMs > 0
            beamUpdatePeriodSlots = max(1, round(beamUpdatePeriodMs / slotDurationForBeamMs));
        end
        cfg = sixgr.util.structSet(cfg, "system.beam.updatePeriod_ms", double(beamUpdatePeriodMs));
    end
    cfg = sixgr.util.structSet(cfg, "system.beam.enable", ...
        logical(localRequireNested(s, "system.beam.enable", "system.beam.enable")));
    cfg = sixgr.util.structSet(cfg, "system.beam.numBeams", ...
        double(localRequireNested(s, "system.beam.numBeams", "system.beam.numBeams")));
    cfg = sixgr.util.structSet(cfg, "system.beam.updatePeriod_slots", ...
        double(beamUpdatePeriodSlots));
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
modStr = string(localOrderToModulation(double(localResolveDirectionalModulationOrder(s, ...
    "UL", localGetNested(s, "modulation.ul_modulation_order", 2)))));
if localUsePi2BPSKULMode(s)
    modStr = "pi/2-BPSK";
end
modStr = char(modStr);
end

function [modStr, codeRate] = localResolveFixedMCSProfile(s, direction)
direction = upper(string(direction));
tableName = string(localResolveDirectionalMCSTable(s, direction));
if direction == "DL"
    mcsIndex = double(localGetNested(s, "modulation_and_mapping.dl_mcs_index", ...
        localGetNested(s, "modulation.dl_mcs_index", NaN)));
else
    mcsIndex = double(localGetNested(s, "modulation_and_mapping.ul_mcs_index", ...
        localGetNested(s, "modulation.ul_mcs_index", NaN)));
end

profile = sixgr.link.resolveMCSProfile(tableName, mcsIndex);
if profile.Valid
    modStr = string(profile.Modulation);
    codeRate = double(profile.TargetCodeRate);
elseif direction == "UL"
    modStr = string(localResolveULModulation(s));
    codeRate = 0.75;
else
    modStr = string(localOrderToModulation(double(localResolveDirectionalModulationOrder(s, "DL", 2))));
    codeRate = 0.75;
end

% pi/2-BPSK UL retains its explicit waveform-mode modulation.
if direction == "UL" && localUsePi2BPSKULMode(s)
    modStr = "pi/2-BPSK";
end
end

function tableName = localResolveDirectionalMCSTable(s, direction)
direction = upper(string(direction));
if direction == "UL"
    tableName = string(localGetNested(s, "modulation_and_mapping.ul_mcs_table", ...
        localGetNested(s, "modulation_and_mapping.mcs_table", ...
        localGetNested(s, "modulation.mcs_table", ""))));
else
    tableName = string(localGetNested(s, "modulation_and_mapping.dl_mcs_table", ...
        localGetNested(s, "modulation_and_mapping.mcs_table", ...
        localGetNested(s, "modulation.mcs_table", ""))));
end
end

function order = localResolveDirectionalModulationOrder(s, direction, defaultValue)
direction = upper(string(direction));
if direction == "UL"
    raw = localGetNested(s, "modulation_and_mapping.ul_max_modulation", ...
        localGetNested(s, "modulation.ul_max_modulation", ...
        localGetNested(s, "modulation.ul_modulation_order", defaultValue)));
else
    raw = localGetNested(s, "modulation_and_mapping.dl_max_modulation", ...
        localGetNested(s, "modulation.dl_max_modulation", ...
        localGetNested(s, "modulation.dl_modulation_order", defaultValue)));
end
order = localModulationToOrder(raw);
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
requestedSitesCompatible = isfinite(nSitesRequested) && nSitesRequested >= 1 && ...
    max(1, round(nSitesRequested)) * nSectorsPerSite == numCells;
if isfinite(nSitesRequested) && nSitesRequested >= 1 && (numCells <= 1 || requestedSitesCompatible)
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

function [profile, source, reason] = localResolveChannelProfileForRuntime(s, channelModel, configuredProfile, mobilitySpeedKmh)
channelModel = upper(strtrim(string(channelModel)));
configuredProfile = upper(strtrim(string(configuredProfile)));
profile = configuredProfile;
source = "configured_channels_profile";
reason = "";
if channelModel ~= "CDL"
    return;
end

losEnabled = logical(localGetNested(s, "channels.los_enabled", true));
if any(configuredProfile == ["CDL-D", "CDL-E"]) && ~losEnabled
    error("sixgr:lls6g:config:ChannelProfileLOSConflict", ...
        "Configured channels.profile='%s' is a LOS CDL profile, but " + ...
        "channels.los_enabled=false. Select a compatible concrete profile " + ...
        "in YAML; MATLAB will not silently replace it.", configuredProfile);
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

function o2iModel = localResolveO2IModel(rawValue)
token = lower(strtrim(string(rawValue)));
if ismember(token, ["", "none", "off", "disabled", "disable"])
    o2iModel = 'none';
elseif ismember(token, ["low", "low_loss", "low-loss", "lowloss"])
    o2iModel = 'low';
elseif ismember(token, ["high", "high_loss", "high-loss", "highloss"])
    o2iModel = 'high';
elseif token == "custom"
    o2iModel = 'custom';
else
    error("sixgr:lls6g:config:BadO2IModel", ...
        "channels.o2i_model / channels.o2i_loss_model must resolve to none, low, high, or custom; got '%s'.", ...
        char(token));
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

function cfg = localInstallRSLAStrictConfig(cfg,s)
path = "reference_signals.rsla_strict";
rsla = sixgr.util.structGet(s,path,[]);
if isempty(rsla)
    return;
end
if ~(isstruct(rsla) && isscalar(rsla))
    error("sixgr:lls6g:config:InvalidRSLAStrictConfig", ...
        "%s must be a scalar configuration structure.",path);
end
required = [
    "enabled"
    "strict"
    "profile_id"
    "configuration_epoch"
    "specification.ts_38211"
    "specification.ts_38212"
    "specification.ts_38213"
    "specification.ts_38214"
    "specification.ts_38215"
    "specification.ts_38331"
    "specification.channel_profile"
    "resource_ownership.index_base"
    "resource_ownership.collision_policy"
    "resource_ownership.require_complete_ledger_before_waveform"
    "dmrs.mapping_types"
    "dmrs.configuration_types"
    "dmrs.lengths"
    "dmrs.additional_positions"
    "dmrs.type_a_positions"
    "dmrs.nscid_values"
    "dmrs.require_independent_vector"
    "csi_rs.rows"
    "csi_rs.resource_types"
    "csi_rs.trigger_types"
    "csi_rs.muting_enabled"
    "csi_rs.require_decoded_aperiodic_trigger"
    "csi_rs.require_independent_vector"
    "srs.port_counts"
    "srs.resource_types"
    "srs.usages"
    "srs.transmission_combs"
    "srs.require_scheduler_state"
    "srs.require_independent_vector"
    "trs.resource_model"
    "trs.no_oracle_tracking"
    "trs.require_applied_correction_hash"
    "ptrs.directions"
    "ptrs.time_densities"
    "ptrs.frequency_densities"
    "ptrs.re_offsets"
    "ptrs.require_measured_cpe"
    "measurements.quantities"
    "measurements.provenance_required"
    "measurements.max_age_slots"
    "measurements.require_complete_identity"
    "filtering.l1_window_samples"
    "filtering.l3_coefficient"
    "filtering.prediction_enabled"
    "measurement_gaps.enabled"
    "measurement_gaps.period_slots"
    "measurement_gaps.offset_slots"
    "measurement_gaps.length_slots"
    "csi_reports.profiles"
    "csi_reports.transports"
    "csi_reports.crc_required"
    "csi_reports.semantic_validation_required"
    "calibration.registry_id"
    "calibration.target_bler"
    "calibration.mapping_methods"
    "calibration.missing_profile_policy"
    "olla.enabled"
    "olla.target_bler"
    "olla.ack_step_db"
    "olla.margin_min_db"
    "olla.margin_max_db"
    "olla.dtx_policy"
    "olla.inactivity_reset_slots"
    "olla.per_ue_state"
    "rrm.events"
    "rrm.hysteresis_db"
    "rrm.time_to_trigger_samples"
    "rrm.require_filtered_measurements"
    "evm.reference_point"
    "evm.rf_pass_fail_enabled"
    "validation.vector_root"
    "validation.seeds"
    "validation.impact_seeds"
    "validation.confidence_level"
    "validation.unsupported_tuple_policy"
    ];
for index = 1:numel(required)
    localRequireNested(rsla,required(index),path+"."+required(index));
end
if ~logical(rsla.strict)
    error("sixgr:lls6g:config:InvalidRSLAStrictConfig", ...
        "%s.strict must be true for the Release-18 strict profile.",path);
end
if string(rsla.profile_id)~="nr_rel18_rsla_strict"
    error("sixgr:lls6g:config:InvalidRSLAStrictConfig", ...
        "%s.profile_id is unsupported.",path);
end
if ~strcmpi(string(rsla.resource_ownership.index_base),"zero_based") || ...
        ~strcmpi(string(rsla.validation.unsupported_tuple_policy), ...
        "reject_before_waveform")
    error("sixgr:lls6g:config:InvalidRSLAStrictConfig", ...
        "RSLA strict ownership/index and rejection policies are mandatory.");
end
cfg = sixgr.util.structSet(cfg,"phy.rsla",rsla);
cfg = sixgr.util.structSet(cfg,"phy.rsla.configuration_authority", ...
    "operator_master_yaml");
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

function [value, found] = localTryGetNestedStrict(s, path)
value = [];
found = false;
parts = split(string(path), ".");
if isempty(parts) || ~isstruct(s)
    return;
end
cursor = s;
for i = 1:numel(parts)
    key = char(parts(i));
    if ~(isstruct(cursor) && isscalar(cursor) && isfield(cursor, key))
        return;
    end
    cursor = cursor.(key);
end
value = cursor;
found = true;
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

function cfoHz = localResolveRuntimeCFOHz(s)
explicit = localNumericScalarOrNaN(localGetNested(s, "impairments.cfo_hz", NaN));
explicitNonzero = isfinite(explicit) && abs(double(explicit)) > 0;
enabled = logical(localGetNested(s, "impairments.cfo_enabled", ...
    localGetNested(s, "impairments.cfo.enabled", explicitNonzero)));
enabled = logical(enabled || explicitNonzero);
if ~enabled
    cfoHz = 0;
    return;
end

model = lower(strtrim(string(localGetNested(s, "impairments.cfo_model", ...
    localGetNested(s, "impairments.cfo.model", "fixed")))));
if any(model == ["fixed","constant","explicit","deterministic"]) && isfinite(explicit)
    cfoHz = explicit;
    return;
end

fcHz = localResolveFirstFiniteNumeric(s, [ ...
    "frequency.center_frequency_hz"
    "carrier_frequency_hz"
    "carrier.carrier_frequency_hz"
    "channel.carrier_frequency_hz"], 0);
stdPpm = localResolveFirstFiniteNumeric(s, [ ...
    "impairments.cfo_std_ppm"
    "impairments.cfo.std_ppm"], NaN);
stdHz = abs(double(fcHz)) * abs(double(stdPpm)) * 1e-6;
maxHz = localResolveFirstFiniteNumeric(s, [ ...
    "impairments.cfo_max_hz"
    "impairments.cfo.value_hz"], NaN);
if ~(isfinite(maxHz) && maxHz >= 0) && isfinite(explicit)
    maxHz = abs(explicit);
end
if ~(isfinite(maxHz) && maxHz >= 0)
    maxHz = 0;
end

stream = RandStream("mt19937ar", "Seed", localBoundedSeed(localResolveImpairmentSeed(s) + 101));
switch model
    case "gaussian"
        if ~(isfinite(stdHz) && stdHz > 0)
            stdHz = maxHz / 3;
        end
        cfoHz = double(stdHz) * randn(stream, 1, 1);
    case {"uniform","bounded_uniform"}
        cfoHz = (2 * rand(stream, 1, 1) - 1) * double(maxHz);
    otherwise
        if isfinite(explicit)
            cfoHz = explicit;
        else
            cfoHz = 0;
        end
end
if isfinite(maxHz) && maxHz > 0
    cfoHz = max(-double(maxHz), min(double(maxHz), double(cfoHz)));
end
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveRuntimeTimingOffsetSamples(s)
explicit = localNumericScalarOrNaN(localGetNested(s, "impairments.timing_offset_samples", NaN));
% A nonzero numeric timing offset is itself an enabled impairment request.
% Defaults may carry timing_offset_enabled=false for the zero-offset case;
% that default must not suppress a scenario override that sets samples != 0.
enabled = logical(localGetNested(s, "impairments.timing_offset_enabled", false)) || ...
    logical(localGetNested(s, "impairments.to.enabled", false)) || ...
    (isfinite(explicit) && abs(explicit) > 0);
if ~enabled
    timingOffset = 0;
    return;
end

model = lower(strtrim(string(localGetNested(s, "impairments.timing_offset_model", ...
    localGetNested(s, "impairments.to.model", "fixed")))));
if any(model == ["fixed","constant","explicit","deterministic"]) && isfinite(explicit)
    timingOffset = explicit;
    return;
end

maxSamples = localResolveFirstFiniteNumeric(s, [ ...
    "impairments.timing_offset_max_samples"
    "impairments.to.value_samples"], NaN);
if ~(isfinite(maxSamples) && maxSamples >= 0) && isfinite(explicit)
    maxSamples = abs(explicit);
end
if ~(isfinite(maxSamples) && maxSamples >= 0)
    maxSamples = 0;
end

stream = RandStream("mt19937ar", "Seed", localBoundedSeed(localResolveImpairmentSeed(s) + 202));
switch model
    case {"uniform","bounded_uniform"}
        timingOffset = (2 * rand(stream, 1, 1) - 1) * double(maxSamples);
    case "gaussian"
        timingOffset = (double(maxSamples) / 3) * randn(stream, 1, 1);
    otherwise
        if isfinite(explicit)
            timingOffset = explicit;
        else
            timingOffset = 0;
        end
end
if isfinite(maxSamples) && maxSamples > 0
    timingOffset = max(-double(maxSamples), min(double(maxSamples), double(timingOffset)));
end
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function seed = localResolveImpairmentSeed(s)
seed = localResolveFirstFiniteNumeric(s, [ ...
    "run_control.impairment_seed"
    "simulation.impairment_seed"
    "run.impairment_seed"
    "impairments.seed"
    "run_control.seed"
    "simulation.seed"], 1);
seed = localBoundedSeed(seed);
end

function seed = localBoundedSeed(seed)
seed = round(double(seed));
if ~isfinite(seed)
    seed = 1;
end
seed = mod(seed, 2^32 - 1);
if seed < 0
    seed = seed + (2^32 - 1);
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
    value = value(:);
    value = value(isfinite(value));
    if ~isempty(value)
        value = double(value(1));
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

function token = localNormalizeCoreCodebookType(codebookType)
switch lower(strtrim(string(codebookType)))
    case {"type1_su_mimo", "type1"}
        token = "type1";
    case {"type2_mu_mimo", "type2"}
        token = "type2";
    case {"etype2_candidate", "etype2"}
        token = "etype2";
    otherwise
        token = "noncodebook";
end
end

function major = localSchemaMajorVersion(versionText)
tokens = regexp(char(string(versionText)), '^\s*(\d+)', 'tokens', 'once');
if isempty(tokens)
    tokens = regexp(char(string(sixgr.lls6g.config.currentVersion())), '^\s*(\d+)', 'tokens', 'once');
end
if isempty(tokens)
    major = 1;
else
    major = str2double(tokens{1});
    if ~(isfinite(major) && major >= 1)
        major = 1;
    end
end
major = round(double(major));
end

function section = localNormalizeFixedLinkCampaignSection(section)
if ~(builtin("isstruct", section) && isscalar(section))
    section = struct();
    return;
end

if isfield(section, "direction")
    direction = lower(strtrim(string(section.direction)));
    switch direction
        case "dl"
            section.direction = "DL";
        case "ul"
            section.direction = "UL";
        otherwise
            section.direction = "both";
    end
end

if isfield(section, "channel_model")
    model = upper(strtrim(string(section.channel_model)));
    if model == ""
        model = "AWGN";
    end
    section.channel_model = model;
end

for fieldName = ["snr_db", "mcs", "seeds", "target_bler"]
    key = char(fieldName);
    if isfield(section, key)
        value = double(section.(key));
        value = value(:).';
        value = value(isfinite(value));
        section.(key) = value;
    end
end

for fieldName = ["rank", "layers", "n_prb", "min_tb_per_point", "max_tb_per_point", "min_errors_for_ci", "trials_per_drop"]
    key = char(fieldName);
    if isfield(section, key)
        value = double(section.(key));
        if isscalar(value) && isfinite(value)
            % Preserve the configured scalar exactly. Schema/runtime
            % validation owns integer checks; this translation boundary
            % must not silently round an invalid operator value.
            section.(key) = double(value);
        end
    end
end

if isfield(section, "max_ci_half_width")
    value = double(section.max_ci_half_width);
    if isfinite(value)
        section.max_ci_half_width = double(value);
    end
end
end

function cfg = localApplyValidationRunClass(cfg, s)
raw = localFirstNonBlankString([
    localScalarString(localGetNested(s, "validation.RunClass", ""))
    localScalarString(localGetNested(s, "validation.run_class", ""))
    localScalarString(sixgr.util.structGet(cfg, "validation.RunClass", ""))
    localScalarString(sixgr.util.structGet(cfg, "validation.run_class", ""))
    ]);
runClass = localNormalizeRunClassToken(raw);
if strlength(runClass) == 0
    runClass = localDeriveValidationRunClass(cfg, s);
end
cfg = sixgr.util.structSet(cfg, "validation.RunClass", char(runClass));
cfg = sixgr.util.structSet(cfg, "validation.run_class", char(runClass));
end

function runClass = localDeriveValidationRunClass(cfg, s)
adaptiveMode = localValidationAdaptiveMode(cfg, s);
fixedMCSActive = localValidationFixedMCSActive(cfg, s);
rankFixed = localValidationRankFixed(cfg, s);
layersFixed = localValidationLayersFixed(cfg, s);
modulationFixed = localValidationModulationFixed(cfg, s, fixedMCSActive);
fixedCampaignEnabled = logical(sixgr.util.structGet(cfg, "validation.fixed_link_campaign.enabled", ...
    localGetNested(s, "validation.fixed_link_campaign.enabled", false))) || ...
    logical(sixgr.util.structGet(cfg, "sweeps_and_matrix.fixed_link_calibration.enabled", ...
    localGetNested(s, "sweeps_and_matrix.fixed_link_calibration.enabled", false)));

if fixedCampaignEnabled && adaptiveMode
    runClass = "hybrid_validation";
elseif fixedMCSActive && rankFixed && layersFixed && modulationFixed && ~adaptiveMode
    runClass = "fixed_lls_anchor";
else
    % Default to diagnostic when we cannot prove a publication-safe fixed anchor.
    runClass = "adaptive_system_diagnostic";
end
end

function tf = localValidationFixedMCSActive(cfg, s)
tokens = lower(strtrim([
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", ""))
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", ""))
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulPolicy", ""))
    localScalarString(localGetNested(s, "link_adaptation.fixed_or_amc", ""))
    localScalarString(localGetNested(s, "link_adaptation.pdsch_link_adaptation_policy", ""))
    localScalarString(localGetNested(s, "link_adaptation.pusch_link_adaptation_policy", ""))
    ]));
tokens = tokens(strlength(tokens) > 0);
fixedTokens = localValidationFixedTokens();
adaptiveTokens = localValidationAdaptiveTokens();
tf = logical(sixgr.util.structGet(cfg, "pdsch6gr.FixedMCSActive", false)) || ...
    (any(ismember(tokens, fixedTokens)) && ~any(ismember(tokens, adaptiveTokens)));
end

function tf = localValidationRankFixed(cfg, s)
tokens = lower(strtrim([
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", ""))
    localScalarString(localGetNested(s, "link_adaptation.rank_adaptation_policy", ""))
    localScalarString(localGetNested(s, "mimo.rank_adaptation_policy", ""))
    ]));
tokens = tokens(strlength(tokens) > 0);
fixedTokens = localValidationFixedTokens();
adaptiveTokens = localValidationAdaptiveTokens();
tf = ~isempty(tokens) && any(ismember(tokens, fixedTokens)) && ~any(ismember(tokens, adaptiveTokens));
if ~tf
    tf = isfinite(double(sixgr.util.structGet(cfg, "phy.pdsch.rank", NaN))) || ...
        isfinite(double(sixgr.util.structGet(cfg, "phy.pusch.rank", NaN)));
end
end

function tf = localValidationLayersFixed(cfg, s)
dlLayers = localNumericScalarOrNaN(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
    sixgr.util.structGet(cfg, "phy.pdsch.nLayers", localGetNested(s, "mimo.n_layers", NaN))));
ulLayers = localNumericScalarOrNaN(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", localGetNested(s, "mimo.n_layers", NaN))));
tf = (isfinite(dlLayers) && dlLayers >= 1) || (isfinite(ulLayers) && ulLayers >= 1);
end

function tf = localValidationModulationFixed(cfg, s, fixedMCSActive)
mods = strtrim([
    localScalarString(sixgr.util.structGet(cfg, "phy.pdsch.modulation", ""))
    localScalarString(sixgr.util.structGet(cfg, "phy.pusch.modulation", ""))
    localScalarString(localGetNested(s, "pdsch.modulation", ""))
    localScalarString(localGetNested(s, "pusch.modulation", ""))
    localScalarString(localGetNested(s, "modulation_and_mapping.pdsch_modulation", ""))
    localScalarString(localGetNested(s, "modulation_and_mapping.pusch_modulation", ""))
    ]);
mods = mods(strlength(mods) > 0);
tf = fixedMCSActive && ~isempty(mods);
end

function tf = localValidationAdaptiveMode(cfg, s)
tokens = lower(strtrim([
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", ""))
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlPolicy", ""))
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulPolicy", ""))
    localScalarString(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", ""))
    localScalarString(localGetNested(s, "link_adaptation.fixed_or_amc", ""))
    localScalarString(localGetNested(s, "link_adaptation.pdsch_link_adaptation_policy", ""))
    localScalarString(localGetNested(s, "link_adaptation.pusch_link_adaptation_policy", ""))
    localScalarString(localGetNested(s, "link_adaptation.rank_adaptation_policy", ""))
    ]));
tokens = tokens(strlength(tokens) > 0);
tf = any(ismember(tokens, localValidationAdaptiveTokens()));
end

function runClass = localNormalizeRunClassToken(raw)
token = lower(strtrim(string(raw)));
if any(token == ["fixed_lls_anchor", "adaptive_system_diagnostic", "hybrid_validation", ...
        "fixed_snr_sweep_lls", "ue_placement_geometry_lls"])
    runClass = token;
else
    runClass = "";
end
end

function tokens = localValidationFixedTokens()
tokens = ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"];
end

function tokens = localValidationAdaptiveTokens()
tokens = ["amc","adaptive","dynamic","dynamic_link_adaptation","cqi","cqi_driven", ...
    "baseline","actual_bler_based","effective_sinr_driven"];
end

function value = localFirstNonBlankString(values)
value = "";
values = string(values(:));
for i = 1:numel(values)
    candidate = strtrim(values(i));
    if strlength(candidate) > 0
        value = candidate;
        return;
    end
end
end

function value = localScalarString(raw)
value = "";
if isempty(raw)
    return;
end
vals = string(raw(:));
if ~isempty(vals)
    value = vals(1);
end
end

function localValidatePhase10Surface(section)
required = [ ...
    "profile_id"
    "specification"
    "propagation_scenario"
    "coordinate_frame"
    "pathloss.model"
    "pathloss.street_width_m"
    "pathloss.building_height_m"
    "los.state_process"
    "o2i.enabled"
    "oxygen_absorption.enabled"
    "topology.model"
    "ue_drop.profile"
    "ue_drop.seed"
    "channel_update.cadence"
    "channel_update.period_s"
    "interference.execution"
    "interference.sample_rate_hz"
    "absolute_power.reference_point"
    "absolute_power.implementation_loss_db"
    "raytracing.enabled"
    "raytracing.method"
    "raytracing.max_reflections"
    "raytracing.max_diffractions"];
missing = strings(0,1);
for index = 1:numel(required)
    [value, found] = localTryGetNestedStrict(section, required(index));
    if ~found || isempty(value)
        missing(end+1,1) = required(index); %#ok<AGROW>
    end
end
if ~isempty(missing)
    error("CHANNEL:UnsupportedProfile", ...
        "Enabled channel.phase10_strict is missing: %s.", ...
        strjoin(cellstr(missing), ", "));
end
if string(localGetNested(section, "specification", "")) ~= "TR38.901-V19.2.0"
    error("CHANNEL:UnsupportedProfile", ...
        "Phase-10 strict mode requires specification TR38.901-V19.2.0.");
end
if lower(string(localGetNested(section, "coordinate_frame", ""))) ~= ...
        "global_cartesian_enu"
    error("CHANNEL:InvalidCoordinateFrame", ...
        "Phase-10 strict geometry requires global_cartesian_enu.");
end
end
