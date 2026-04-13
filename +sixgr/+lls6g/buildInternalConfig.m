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
cfg.outputs.storageBackend = char(string(localRequireNested(s, "output.backend", "output.backend")));
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
cfg.phy.waveform.dl = char(string(s.waveform.dl_waveform));
cfg.phy.waveform.ul = char(string(s.waveform.ul_waveform));
cfg = sixgr.util.structSet(cfg, "phy.waveform.windowingEnabled", logical(s.waveform.windowing_enabled));
cfg = sixgr.util.structSet(cfg, "phy.waveform.experimentalDLDftsOfdmEnabled", ...
    logical(s.waveform.experimental_dl_dfts_ofdm_enabled));

cfg.phy.ssb.enable = logical(s.reference_signals.ssb_enabled);
cfg = sixgr.util.structSet(cfg, "phy.ssb.blockPattern", ...
    localDefaultSSBBlockPattern(double(s.frequency.center_frequency_hz), double(s.frame.scs_khz)));
cfg.phy.pbch.enable = logical(s.reference_signals.pbch_enabled);
cfg.phy.mib.enable = logical(s.reference_signals.pbch_enabled);
cfg.phy.sib1.enable = logical(s.reference_signals.pbch_enabled);

cfg.phy.pdcch.enable = logical(s.control.pdcch_enabled);
cfg.phy.pdcch.searchSpaceType = char(string(s.control.search_space_type));
cfg.phy.pdcch.aggregationLevel = double(localFirstValue(s.control.aggregation_levels));
cfg.phy.pdcch.dciFormat = char(string(localFirstValue(s.control.dci_formats)));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.blindDecodeCandidates", double(s.control.blind_decode_candidates));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.duration", double(s.control.coreset_duration));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.frequencyResources", double(s.control.coreset_frequency_resources));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.searchSpace.numCandidates", double(s.control.search_space_num_candidates));

targetCases = lower(string(s.scenario.target_cases));
linkAdaptationMode = lower(string(localRequireNested(s, "link_adaptation.fixed_or_amc", "link_adaptation.fixed_or_amc")));
linkAdaptationUsesFixedMCS = ismember(linkAdaptationMode, ["fixed","fixed_mcs","configured_fixed","disabled","off","none","false"]);
dlConfiguredMCSIndex = double(s.modulation.dl_mcs_index);
ulConfiguredMCSIndex = double(s.modulation.ul_mcs_index);
cfg.phy.pdsch.enable = any(ismember(targetCases, localCatalogStringList(catalog.value_maps.target_case_groups.pdsch_enable)));
cfg.phy.pdsch.nLayers = double(s.mimo.n_layers);
cfg.phy.pdsch.enablePTRS = logical(s.reference_signals.ptrs_enabled);
cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = double(s.reference_signals.pdsch_dmrs_num_cdm_groups_without_data);
cfg.phy.pdsch.dmrs.typeApos = double(s.reference_signals.pdsch_dmrs_type_a_position);
cfg.phy.pdsch.dmrs.configType = double(s.reference_signals.pdsch_dmrs_config_type);
cfg.phy.pdsch.configuredMCSIndex = dlConfiguredMCSIndex;
cfg.phy.pdsch.mcsIndex = localTernary(linkAdaptationUsesFixedMCS, dlConfiguredMCSIndex, NaN);
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
cfg.phy.pusch.mcsIndex = localTernary(linkAdaptationUsesFixedMCS, ulConfiguredMCSIndex, NaN);
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsTable", char(string(s.modulation.mcs_table)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.nPorts", double(s.reference_signals.pusch_dmrs_ports));
cfg = sixgr.util.structSet(cfg, "phy.pusch.pi2BPSKEnabled", logical(s.modulation.pi2_bpsk_enabled));
cfg = sixgr.util.structSet(cfg, "phy.modulation.constellationShapingEnabled", ...
    logical(s.modulation.constellation_shaping_enabled));

cfg.phy.srs.enable = logical(s.reference_signals.srs_enabled);
cfg.phy.srs.nPorts = double(s.reference_signals.srs_ports);
cfg = sixgr.util.structSet(cfg, "phy.srs.period_slots", max(1, round(double(localRequireFirstNested(s, ...
    ["control_gating.srs_max_age_slots","reference_signals.srs_periodicity_ms"], ...
    "control_gating.srs_max_age_slots or reference_signals.srs_periodicity_ms")))));
cfg = sixgr.util.structSet(cfg, "phy.trs.enable", logical(s.reference_signals.trs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trs.nPorts", double(localRequireNested(s, "reference_signals.trs.num_ports", "reference_signals.trs.num_ports")));
cfg = sixgr.util.structSet(cfg, "phy.trs.scramblingID", double(localRequireNested(s, "reference_signals.trs.scrambling_id", "reference_signals.trs.scrambling_id")));
cfg = sixgr.util.structSet(cfg, "phy.ptrs.enable", logical(s.reference_signals.ptrs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trackingRS.enable", logical(s.reference_signals.tracking_rs_enabled));

cfg.phy.prach.enable = logical(s.random_access.enabled);
cfg.phy.prach.preambleFormat = char(string(s.random_access.prach_format));
cfg = sixgr.util.structSet(cfg, "phy.prach.preambleCount", double(s.random_access.preamble_count));
cfg.phy.prach.configurationIndex = double(s.random_access.configuration_index);
cfg.phy.prach.subcarrierSpacing_kHz = double(s.random_access.subcarrier_spacing_khz);
cfg.phy.prach.rootSeqIndex = double(s.random_access.root_sequence_index);
cfg.phy.prach.zeroCorrelationZone = double(s.random_access.zero_correlation_zone);
cfg.phy.prach.preambleIndex = double(s.random_access.preamble_index);

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
cfg.phy.rx.cfoCompensation = abs(double(s.impairments.cfo_hz)) > 0;
cfg.phy.rx.useFastChannelEstMex = false;
cfg = sixgr.util.structSet(cfg, "phy.rx.useIdealTimingSync", logical(localRequireNested(s, ...
    "receiver.use_ideal_timing_sync", "receiver.use_ideal_timing_sync")));
cfg.phy.nTxAnt = double(s.mimo.n_tx_ant);
cfg.phy.nRxAnt = double(s.mimo.n_rx_ant);
cfg = localApplyRuntimeAntennaConfig(cfg, s);
cfg = sixgr.util.structSet(cfg, "phy.impairments.cfoHz", double(s.impairments.cfo_hz));
cfg = sixgr.util.structSet(cfg, "phy.impairments.phaseNoiseEnabled", logical(s.impairments.phase_noise_enabled));
cfg = sixgr.util.structSet(cfg, "phy.impairments.iqImbalanceEnabled", logical(s.impairments.iq_imbalance_enabled));
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

cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end

function timing = localResolveRunTiming(s)
scsKHz = double(localRequireNested(s, "frame.scs_khz", "frame.scs_khz"));
mu = round(log2(scsKHz / 15));
if ~(isfinite(mu) && mu >= 0)
    mu = 0;
end
slotDuration_ms = 1 / 2^double(mu);
slotsPerFrame = 10 * 2^double(mu);

configuredTotalSlots = double(localGetNested(s, "run_control.total_slots", NaN));
if isfinite(configuredTotalSlots) && configuredTotalSlots > 0
    totalSlots = max(1, round(configuredTotalSlots));
else
    totalSlots = max(1, round(double(s.simulation.n_slots)));
end

configuredWarmupSlots = double(localGetNested(s, "run_control.warmup_slots", NaN));
if isfinite(configuredWarmupSlots) && configuredWarmupSlots >= 0
    warmupSlots = max(0, round(configuredWarmupSlots));
else
    warmupSlots = max(0, round(double(localRequireNested(s, ...
        "run_control.warmup_time_ms", "run_control.warmup_time_ms")) / slotDuration_ms));
end

configuredMeasurementSlots = double(localGetNested(s, "run_control.measurement_slots", NaN));
if isfinite(configuredMeasurementSlots) && configuredMeasurementSlots >= 0
    measurementSlots = max(0, round(configuredMeasurementSlots));
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
timing.NumFrames = max(1, ceil(double(totalSlots) / double(slotsPerFrame)));
timing.CheckpointEverySlots = max(1, round(double(localGetNested(s, ...
    "run_control.checkpoint_every_slots", max(1, totalSlots)))));
timing.SnapshotEverySlots = max(1, round(double(localGetNested(s, ...
    "run_control.snapshot_every_slots", max(1, totalSlots)))));
timing.LogEverySlots = max(1, round(double(localGetNested(s, ...
    "run_control.log_every_slots", max(1, totalSlots)))));
timing.SaveIntermediateArtifacts = logical(localGetNested(s, ...
    "run_control.save_intermediate_artifacts", localGetNested(s, "run_control.save_intermediate", false)));
timing.DeterministicReplay = logical(localGetNested(s, ...
    "run_control.deterministic_replay", localGetNested(s, "run_control.deterministic_mode", false)));
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
    maxPRBAllocationPerUE = double(localRequireNested(s, "system.scheduler.maxPRBAllocationPerUE", "system.scheduler.maxPRBAllocationPerUE"));
    cfg = sixgr.util.structSet(cfg, "system.scheduler.type", schedulerType);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.type", schedulerType);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxActiveUEsPerSlot", maxActiveUEsPerSlot);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxActiveUEsPerCellPerSlot", maxActiveUEsPerCellPerSlot);
    cfg = sixgr.util.structSet(cfg, "system.scheduler.maxPRBAllocationPerUE", maxPRBAllocationPerUE);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxUEPerSlot", maxActiveUEsPerCellPerSlot);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxActiveUEsPerSlot", maxActiveUEsPerSlot);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxActiveUEsPerCellPerSlot", maxActiveUEsPerCellPerSlot);
    cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxPRBAllocationPerUE", maxPRBAllocationPerUE);
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

function value = localGetNested(s, path, defaultValue)
value = sixgr.util.structGet(s, path, defaultValue);
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
