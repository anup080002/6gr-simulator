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
cfg.run.seed = double(s.simulation.random_seed);
cfg.run.mode = "link";
cfg.run.module = "run_6g_phy_lls_single";
cfg.run.resultsRoot = "results";
cfg.run.runTag = "";
cfg.run.shortRun = false;
cfg.run.numFrames = max(1, round(double(s.simulation.n_frames)));
cfg.run.numTTI = max(1, round(double(s.simulation.n_slots)));
cfg.run.failFast = logical(s.logging.strict_validation);
cfg.run.verbose = logical(s.logging.echo_to_console);
cfg.run.noProxyTruthContract = true;
cfg.run.strictMode = logical(s.logging.strict_validation);
cfg.run.deterministicMode = logical(s.simulation.deterministic_mode);
cfg.run.numWorkers = max(0, round(double(localGetNested(s, "run_control.num_workers", 0))));
cfg.run.useParallel = logical(cfg.run.numWorkers > 1);

cfg.outputs.saveCSV = logical(s.output.save_csv);
cfg.outputs.saveMAT = logical(s.output.save_mat);
cfg.outputs.saveFigures = logical(s.output.save_figures);
cfg.outputs.saveFIG = false;
cfg.outputs.savePNG = logical(s.output.save_png);
cfg.outputs.plotVisible = false;

[profileName, propagationScenario] = localResolveScenarioSemantics(s);
cfg.scenario.id = char(string(s.meta.scenario_id));
cfg.scenario.name = char(profileName);
cfg.scenario.profileName = char(profileName);
cfg.run.scenario = char(propagationScenario);
cfg.scenario.bs.nTxAnt = double(s.mimo.n_tx_ant);
cfg.scenario.bs.txPower_dBm = double(s.energy_efficiency.tx_power_dbm);
cfg.scenario.ue.nRxAnt = double(s.mimo.n_rx_ant);
cfg.scenario.ue.nTxAnt = double(s.mimo.n_rx_ant);
cfg.scenario.ue.nUE = double(localGetNested(s, "users.n_users", 1));
cfg.scenario.nUE = double(localGetNested(s, "users.n_users", 1));
cfg.scenario.mobility.enable = double(s.channels.mobility_kmph) > 0;
cfg.scenario.mobility.speed_kmh = [double(s.channels.mobility_kmph) double(s.channels.mobility_kmph)];

cfg.channel.fc_Hz = double(s.frequency.center_frequency_hz);
cfg.phy.fc_Hz = double(s.frequency.center_frequency_hz);
cfg.channel.bandwidth_Hz = double(s.frequency.bandwidth_hz);
cfg.channel.subcarrierSpacing_kHz = double(s.frame.scs_khz);
cfg.phy.channelBandwidth_MHz = double(s.frequency.bandwidth_hz) / 1e6;
cfg.channel.snr_dB = double(s.simulation.snr_db);
cfg.channel.doppler_Hz = double(s.channels.doppler_hz);
cfg.channel.dopplerHz = double(s.channels.doppler_hz);
cfg.channel.awgnOnly = upper(string(s.channels.model_type)) == "AWGN";
cfg.channel.propagationScenario = char(propagationScenario);
cfg.channel.pathloss.model = char(string(s.channels.pathloss_model));
cfg.channel.pathlossModel = char(string(s.channels.pathloss_model));
cfg.channel.shadowFadingStd_dB = double(s.channels.shadow_fading_std_db);
cfg.channel.shadowSigma_dB = double(s.channels.shadow_fading_std_db);
cfg.channel.fading.enable = ~cfg.channel.awgnOnly;
cfg.channel.fading.maxDoppler_Hz = double(s.channels.doppler_hz);
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
cfg.phy.pdsch.enable = any(ismember(targetCases, localCatalogStringList(catalog.value_maps.target_case_groups.pdsch_enable)));
cfg.phy.pdsch.nLayers = double(s.mimo.n_layers);
cfg.phy.pdsch.enablePTRS = logical(s.reference_signals.ptrs_enabled);
cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = double(s.reference_signals.pdsch_dmrs_num_cdm_groups_without_data);
cfg.phy.pdsch.dmrs.typeApos = double(s.reference_signals.pdsch_dmrs_type_a_position);
cfg.phy.pdsch.dmrs.configType = double(s.reference_signals.pdsch_dmrs_config_type);
cfg.phy.pdsch.mcsIndex = double(s.modulation.dl_mcs_index);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", char(string(s.modulation.mcs_table)));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.dmrs.nPorts", double(s.reference_signals.pdsch_dmrs_ports));

cfg.phy.csirs.enable = logical(s.reference_signals.csi_rs_enabled);
cfg.phy.csirs.nPorts = double(s.reference_signals.pdsch_dmrs_ports);
cfg = sixgr.util.structSet(cfg, "phy.csirs.numResources", ...
    double(localGetNested(s, "deployment_topology.num_trps", localGetNested(s, "mimo.trp_count", 1))));
csiMode = string(localGetNested(s, "csi_acquisition_and_reporting.channel_state_information_mode", ...
    localGetNested(s, "reference_signals.channel_state_information_mode", ...
    localGetNested(s, "reference_signals.csi_feedback_mode", "none"))));
pmiCodebookMode = string(localGetNested(s, "csi_acquisition_and_reporting.pmi_codebook_mode", ...
    localGetNested(s, "reference_signals.pmi_codebook_mode", localLegacyPMICodebookMode(s.mimo.codebook_type))));
reportCQI = localPolicyFlag(localGetNested(s, "csi_acquisition_and_reporting.cqi_policy", ...
    localGetNested(s, "reference_signals.cqi_reporting_enabled", true)));
reportPMI = localPolicyFlag(localGetNested(s, "csi_acquisition_and_reporting.pmi_policy", ...
    localGetNested(s, "reference_signals.pmi_reporting_enabled", true)));
reportRI = localPolicyFlag(localGetNested(s, "csi_acquisition_and_reporting.ri_policy", ...
    localGetNested(s, "reference_signals.ri_reporting_enabled", true)));
reportCRI = localPolicyFlag(localGetNested(s, "csi_acquisition_and_reporting.cri_policy", ...
    localGetNested(s, "reference_signals.cri_reporting_enabled", false)));
reportCSI = logical(localGetNested(s, "reference_signals.csi_reporting_enabled", any([reportCQI reportPMI reportRI reportCRI])));
reportPayloadMode = string(localGetNested(s, "csi_acquisition_and_reporting.report_payload_mode", "compressed"));
crcAttachedMode = logical(localGetNested(s, "csi_acquisition_and_reporting.crc_attached_mode", true));
crcFreeMode = logical(localGetNested(s, "csi_acquisition_and_reporting.crc_free_mode", false));
cfg.phy.csi.enable = logical(s.reference_signals.csi_rs_enabled) || reportCSI;
cfg.phy.csi.feedbackMode = char(csiMode);
cfg = sixgr.util.structSet(cfg, "phy.csi.channelStateInformationMode", char(csiMode));
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCSI", reportCSI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", reportCQI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMI", reportPMI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportRI", reportRI);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCRI", reportCRI);
cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", char(pmiCodebookMode));
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", char(string(s.mimo.codebook_type)));
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
cfg.phy.pusch.mcsIndex = double(s.modulation.ul_mcs_index);
cfg = sixgr.util.structSet(cfg, "phy.pusch.mcsTable", char(string(s.modulation.mcs_table)));
cfg = sixgr.util.structSet(cfg, "phy.pusch.dmrs.nPorts", double(s.reference_signals.pusch_dmrs_ports));
cfg = sixgr.util.structSet(cfg, "phy.pusch.pi2BPSKEnabled", logical(s.modulation.pi2_bpsk_enabled));
cfg = sixgr.util.structSet(cfg, "phy.modulation.constellationShapingEnabled", ...
    logical(s.modulation.constellation_shaping_enabled));

cfg.phy.srs.enable = logical(s.reference_signals.srs_enabled);
cfg.phy.srs.nPorts = double(s.reference_signals.srs_ports);
cfg = sixgr.util.structSet(cfg, "phy.trs.enable", logical(s.reference_signals.trs_enabled));
cfg = sixgr.util.structSet(cfg, "phy.trs.nPorts", double(localGetNested(s, "reference_signals.trs.num_ports", 1)));
cfg = sixgr.util.structSet(cfg, "phy.trs.scramblingID", double(localGetNested(s, "reference_signals.trs.scrambling_id", 1)));
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
cfg.mac.harq.maxRetx = double(localGetNested(s, "harq.max_retx", sixgr.util.structGet(cfg, "mac.harq.maxRetx", 3)));
cfg = sixgr.util.structSet(cfg, "phy.harq.feedbackTimingSlots", double(s.harq.feedback_timing_slots));
cfg = sixgr.util.structSet(cfg, "phy.harq.combiningMode", char(string(s.harq.combining_mode)));
cfg = sixgr.util.structSet(cfg, "phy.harq.cbgEnabled", logical(s.harq.cbg_enabled));
cfg = sixgr.util.structSet(cfg, "phy.harq.validationMode", char(string(localGetNested(s, "harq.validation_mode", "observation"))));

cfg.phy.ldpc.maxIterations = double(s.coding.max_decoder_iterations);
cfg.phy.rx.cfoCompensation = abs(double(s.impairments.cfo_hz)) > 0;
cfg.phy.rx.useFastChannelEstMex = false;
cfg.phy.nTxAnt = double(s.mimo.n_tx_ant);
cfg.phy.nRxAnt = double(s.mimo.n_rx_ant);
cfg = sixgr.util.structSet(cfg, "phy.impairments.cfoHz", double(s.impairments.cfo_hz));
cfg = sixgr.util.structSet(cfg, "phy.impairments.phaseNoiseEnabled", logical(s.impairments.phase_noise_enabled));
cfg = sixgr.util.structSet(cfg, "phy.impairments.iqImbalanceEnabled", logical(s.impairments.iq_imbalance_enabled));
cfg = sixgr.util.structSet(cfg, "phy.impairments.paNonlinearityEnabled", logical(s.impairments.pa_nonlinearity_enabled));
cfg = sixgr.util.structSet(cfg, "phy.impairments.adcQuantizationBits", double(s.impairments.adc_quantization_bits));
cfg = sixgr.util.structSet(cfg, "phy.impairments.dacQuantizationBits", double(s.impairments.dac_quantization_bits));
cfg = sixgr.util.structSet(cfg, "phy.impairments.timingOffsetSamples", double(s.impairments.timing_offset_samples));

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
    double(localGetNested(s, "deployment_topology.num_trps", localGetNested(s, "mimo.trp_count", 1))));

cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", char(string(localGetNested(s, "link_adaptation.fixed_or_amc", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", logical(localGetNested(s, "link_adaptation.outer_loop_flag", false)));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.innerLoopFlag", logical(localGetNested(s, "link_adaptation.inner_loop_flag", false)));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.cqiSource", char(string(localGetNested(s, "link_adaptation.cqi_source", "csi_feedback"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaCQIPolicy", char(string(localGetNested(s, "link_adaptation.delta_cqi_policy", "none"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSPolicy", char(string(localGetNested(s, "link_adaptation.delta_mcs_policy", "none"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", char(string(localGetNested(s, "link_adaptation.pdsch_link_adaptation_policy", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ulPolicy", char(string(localGetNested(s, "link_adaptation.pusch_link_adaptation_policy", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.pdcchPolicy", char(string(localGetNested(s, "link_adaptation.pdcch_link_adaptation_policy", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.rankPolicy", char(string(localGetNested(s, "link_adaptation.rank_adaptation_policy", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.alPolicy", char(string(localGetNested(s, "link_adaptation.al_adaptation_policy", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.beamPolicy", char(string(localGetNested(s, "link_adaptation.beam_adaptation_policy", "fixed"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.periodicity", char(string(localGetNested(s, "link_adaptation.adaptation_periodicity", "slot"))));
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.delayModel", char(string(localGetNested(s, "link_adaptation.adaptation_delay_model", "baseline"))));

cfg.traffic.model = "traceReplay";
cfg.traffic.trace.offeredBitsDL = zeros(max(1, cfg.run.numFrames), 1);
cfg.traffic.trace.offeredBitsUL = zeros(max(1, cfg.run.numFrames), 1);

cfg = sixgr.util.structSet(cfg, "meta.lls6gScenarioID", char(string(s.meta.scenario_id)));
cfg = sixgr.util.structSet(cfg, "lls6g.resolvedConfig", s);
cfg = sixgr.util.structSet(cfg, "lls6g.frequency", s.frequency);
cfg = sixgr.util.structSet(cfg, "lls6g.frame", s.frame);
cfg = sixgr.util.structSet(cfg, "lls6g.waveform", s.waveform);
cfg = sixgr.util.structSet(cfg, "lls6g.channels", s.channels);
cfg = sixgr.util.structSet(cfg, "lls6g.reference_signals", s.reference_signals);
cfg = sixgr.util.structSet(cfg, "lls6g.mimo", s.mimo);
if isfield(s, "users")
    cfg = sixgr.util.structSet(cfg, "lls6g.users", s.users);
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

function value = localGetNested(s, path, defaultValue)
value = sixgr.util.structGet(s, path, defaultValue);
end

function tf = localPolicyFlag(value)
if islogical(value) || (isnumeric(value) && isscalar(value))
    tf = logical(value);
    return;
end
token = lower(string(value));
tf = ~ismember(token, ["disabled","none","off","false"]);
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
