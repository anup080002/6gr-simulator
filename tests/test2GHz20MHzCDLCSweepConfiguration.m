function tests = test2GHz20MHzCDLCSweepConfiguration
tests = functiontests(localfunctions);
end

function testReferenceAndRFStudyAreSeparated(testCase)
root = localRoot();
reference = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml")).toStruct();
rfStudy = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_rf_impairments.yaml")).toStruct();

verifyEqual(testCase, string(reference.frequency.band_name), ...
    "n39_1900mhz_20mhz_tdd");
verifyEqual(testCase, double(reference.frequency.center_frequency_hz), 1.9e9);
verifyEqual(testCase, double(reference.frequency.bandwidth_hz), 20e6);
verifyEqual(testCase, double(reference.frequency.n_size_grid), 106);
verifyEqual(testCase, double(reference.frame.scs_khz), 15);
verifyEqual(testCase, double(reference.waveform.sample_rate_hz), 30.72e6);
verifyEqual(testCase, upper(string(reference.frequency.duplex_mode)), "TDD");
verifyEqual(testCase, upper(string(reference.global_radio_scope.duplex_mode)), "TDD");
verifyEqual(testCase, string(reference.channels.profile), "CDL-C");
verifyFalse(testCase, logical(reference.channels.pathloss_enabled));
verifyEqual(testCase, lower(string(reference.channels.o2i_model)), "none");
verifyFalse(testCase, logical(reference.impairments.phase_noise_enabled));
verifyTrue(testCase, logical(rfStudy.impairments.phase_noise_enabled));
verifyTrue(testCase, logical(rfStudy.impairments.iq_imbalance_enabled));
verifyTrue(testCase, logical(rfStudy.impairments.pa_nonlinearity_enabled));
verifyTrue(testCase, logical(rfStudy.impairments.adc_quantization_enabled));
verifyTrue(testCase, logical(rfStudy.impairments.dac_quantization_enabled));
verifyTrue(testCase, logical(rfStudy.impairments.timing_offset_enabled));
verifyEqual(testCase, lower(string(rfStudy.channels.o2i_model)), "none");
end

function testAllPhysicalSignalFamiliesAndExportsEnabled(testCase)
root = localRoot();
s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml")).toStruct();
verifyEqual(testCase, string(s.scenario.target_cases), "bundle");
rs = s.reference_signals;
for name = ["ssb_enabled","pbch_enabled","pdcch_dmrs_enabled", ...
        "csi_rs_enabled","srs_enabled","trs_enabled", ...
        "tracking_rs_enabled","ptrs_enabled","csi_reporting_enabled", ...
        "cqi_reporting_enabled","pmi_reporting_enabled", ...
        "ri_reporting_enabled","cri_reporting_enabled"]
    verifyTrue(testCase, logical(rs.(name)));
end
verifyTrue(testCase, logical(s.harq.enabled));
verifyEqual(testCase, double(s.reference_signals.csi_rs_periodicity_slots), 5);
verifyEqual(testCase, double(s.reference_signals.csi_rs_offset_slots), 1);
verifyEqual(testCase, string(s.integration.power_reference_mode), ...
    "normalized_unit_es");
verifyTrue(testCase, logical(s.integration.configured_snr_is_link_authority));
for name = ["save_csv","save_mat","save_figures","save_png", ...
        "save_yaml_snapshot","save_json_snapshot", ...
        "organize_by_block","generate_summary_plots"]
    verifyTrue(testCase, logical(s.output.(name)));
end
verifyFalse(testCase, logical(s.output.emit_placeholder_artifacts));
verifyTrue(testCase, logical(s.random_access.enabled));
verifyTrue(testCase, logical(s.pdcch.enabled));
verifyTrue(testCase, logical(s.pucch.enabled));
verifyTrue(testCase, logical(s.pdsch.enabled));
verifyTrue(testCase, logical(s.pusch.enabled));
end

function testO2IUsesThermalNoiseNotFixedSNRAuthority(testCase)
root = localRoot();
s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml")).toStruct();
verifyTrue(testCase, logical(s.channels.pathloss_enabled));
verifyTrue(testCase, logical(s.channels.shadow_fading_enabled));
verifyEqual(testCase, lower(string(s.channels.o2i_model)), "low");
verifyEqual(testCase, string(s.simulation.noise_operating_mode), ...
    "receiver_noise_figure_thermal_noise");
verifyFalse(testCase, logical(s.integration.configured_snr_is_link_authority));
verifyEqual(testCase, upper(string(s.integration.run_mode)), "GEOMETRY_NETWORK");
verifyEqual(testCase, string(s.integration.power_reference_mode), ...
    "absolute_calibrated_sqrt_mw");
verifyEqual(testCase, upper(string(s.frequency.duplex_mode)), "TDD");
verifyEqual(testCase, upper(string(s.global_radio_scope.duplex_mode)), "TDD");
verifyTrue(testCase, logical(s.channels.o2i_receiver_indoor));
verifyEqual(testCase, double(s.channels.link_tx_position_m(:)), [0; 0; 25]);
verifyEqual(testCase, double(s.channels.link_rx_position_m(:)), [100; 0; 1.5]);
end

function testPowerAndNoiseStudyArmsCannotBeMixed(testCase)
root = localRoot();
scenarioRoot = fullfile(root,"simulator","configs","scenarios");
fixed = sixgr.lls6g.config.loadScenarioConfig(fullfile(scenarioRoot, ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml")).toStruct();
fixed.integration.power_reference_mode = "absolute_calibrated_sqrt_mw";
verifyError(testCase, @()sixgr.lls6g.config.validateScenarioConfig( ...
    fixed,"Kind","scenario","AllowPartial",false,"Context","mixed-fixed-snr"), ...
    "sixgr:lls6g:config:MixedFixedSNRAndAbsolutePower");

physical = sixgr.lls6g.config.loadScenarioConfig(fullfile(scenarioRoot, ...
    "lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml")).toStruct();
physical.integration.power_reference_mode = "normalized_unit_es";
verifyError(testCase, @()sixgr.lls6g.config.validateScenarioConfig( ...
    physical,"Kind","scenario","AllowPartial",false,"Context","mixed-link-budget"), ...
    "sixgr:lls6g:config:PhysicalLinkBudgetNeedsAbsolutePower");
end

function testEightPointSweepIsJointAndIndependent(testCase)
root = localRoot();
for file = ["lls_2ghz_20mhz_rank2_cdlc_snr_sweep.yaml", ...
        "lls_2ghz_20mhz_rank2_cdlc_rf_snr_sweep.yaml"]
    s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
        "simulator","configs","scenarios",file)).toStruct();
    overrides = s.scenario.sweep.overrides;
    verifyEqual(testCase, numel(overrides), 8);
    actual = zeros(1, numel(overrides));
    seeds = zeros(1, numel(overrides));
    for k = 1:numel(overrides)
        actual(k) = double(overrides(k).config.simulation.snr_db);
        seeds(k) = double(overrides(k).config.simulation.random_seed);
    end
    verifyEqual(testCase, actual, [40 30 20 10 0 -10 -20 -30]);
    verifyEqual(testCase, numel(unique(seeds)), 8);
    verifyEqual(testCase, string(s.scenario.runner_profile), "generic_sweep");
    verifyEqual(testCase, string(s.scenario.sweep.execution_error_policy), ...
        "retain_failure_and_continue");
    verifyTrue(testCase, logical(s.output.save_csv));
    verifyTrue(testCase, logical(s.output.save_png));
end
end

function testEverySweepChildResolvesToTDDNormalizedCDLC(testCase)
root = localRoot();
scenarioPath = fullfile(root,"simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_snr_sweep.yaml");
parent = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
overrides = parent.get("scenario.sweep.overrides");
expected = [40 30 20 10 0 -10 -20 -30];
for pointIndex = 1:numel(overrides)
    authority = overrides(pointIndex).config;
    resolved = sixgr.util.mergeStruct(parent.toStruct(),authority);
    resolved = sixgr.lls6g.config.normalizeScenarioAliases(resolved, ...
        "SourceFiles",parent.SourceFiles,"ConfigPath",parent.ConfigPath, ...
        "Authority",authority);
    resolved.scenario.runner_profile = "waveform_bundle";
    sixgr.lls6g.config.validateScenarioConfig(resolved, ...
        "Kind","scenario","AllowPartial",false, ...
        "Context",parent.ConfigPath+"::"+string(overrides(pointIndex).label));
    child = sixgr.lls6g.config.ScenarioConfig(resolved, ...
        "SourceFiles",parent.SourceFiles,"ConfigPath",parent.ConfigPath, ...
        "ConfigHash",sixgr.lls6g.config.hashResolvedScenario(resolved), ...
        "Kind","scenario");
    cfg = sixgr.lls6g.buildInternalConfig(child,tempname);
    verifyEqual(testCase, string(cfg.integration.run_mode), "FIXED_SNR_SWEEP");
    verifyTrue(testCase, logical(cfg.integration.configured_snr_is_link_authority));
    verifyEqual(testCase, string(cfg.integration.power_reference_mode), ...
        "normalized_unit_es");
    verifyTrue(testCase, sixgr.rf.isNormalizedFixedSNRPowerReference(cfg));
    verifyEqual(testCase, string(cfg.phy.duplex.mode), "TDD");
    verifyFalse(testCase, isfield(cfg.phy.duplex,"fdd"));
    verifyEqual(testCase, string(cfg.channel.model), "CDL");
    verifyEqual(testCase, string(cfg.channel.cdlProfile), "CDL-C");
    verifyEqual(testCase, double(cfg.channel.snr_dB), expected(pointIndex));
end
end

function testTDDFrameGridAndSymbolMapping(testCase)
root = localRoot();
s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
engine = sixgr.phy.FrameStructureEngine(cfg,"FrameCoreOnly",true);

verifyEqual(testCase, engine.DuplexMode, "TDD");
verifyEqual(testCase, engine.Mu, 0);
verifyEqual(testCase, engine.SCSkHz, 15);
verifyEqual(testCase, engine.NRB, 106);
verifyEqual(testCase, engine.FFTSize, 2048);
verifyEqual(testCase, engine.SampleRate_Hz, 30.72e6);
verifyEqual(testCase, engine.SlotsPerFrame, 10);
verifyEqual(testCase, engine.SymbolsPerSlot, 14);
verifyEqual(testCase, arrayfun(@(slot)engine.TDDToken(slot),0:4), ...
    ['D','D','D','F','U']);
special = engine.SlotPartition(3);
verifyEqual(testCase, special.DLSymbolIndices0Based, 0:9);
verifyEqual(testCase, special.UnresolvedFlexibleSymbolIndices0Based, 10:11);
verifyEqual(testCase, special.ULSymbolIndices0Based, 12:13);
verifyTrue(testCase, engine.IsDLAllocation(3,[2 8]));
verifyFalse(testCase, engine.IsDLAllocation(3,[2 12]));
verifyTrue(testCase, engine.IsULAllocation(4,[0 13]));
verifyEqual(testCase, double(cfg.phy.bwp.dl.NSizeBWP), 106);
verifyEqual(testCase, double(cfg.phy.bwp.ul.NSizeBWP), 106);
verifyEqual(testCase, double(cfg.phy.srs.slotWithinPeriod1Based), 5);
verifyEqual(testCase, double(cfg.phy.srs.SymbolStart), 13);
verifyEqual(testCase, double(cfg.phy.pucch.dlDataToULACK(:).'), 1:8);

for controlSlot0 = 0:3
    partition = engine.SlotPartition(controlSlot0);
    configured = double(cfg.phy.pdsch.symbolAllocation(:).');
    startSymbol = max(partition.DLSymbolAllocation(1),configured(1));
    stopSymbol = min(sum(partition.DLSymbolAllocation),sum(configured));
    grant = struct("Direction","DL", ...
        "ControlAbsoluteSlot",controlSlot0, ...
        "ControlSymbolAllocation",[0 2], ...
        "SymbolAllocation",[startSymbol stopSymbol-startSymbol], ...
        "HARQProcess",0);
    decision = sixgr.phy.frame.TimingRelationEngine. ...
        resolveProductionGrant(cfg,grant);
    verifyTrue(testCase,logical(decision.Valid),string(decision.ReasonCode));
    verifyTrue(testCase,ismember(double(decision.K1),1:8));
    feedback = engine.SlotPartition(double(decision.FeedbackAbsoluteSlot));
    verifyTrue(testCase,feedback.AllowUL);
end
ulGrant = struct("Direction","UL", ...
    "ControlAbsoluteSlot",3,"ControlSymbolAllocation",[0 2], ...
    "SymbolAllocation",[0 13],"HARQProcess",0);
ulDecision = sixgr.phy.frame.TimingRelationEngine. ...
    resolveProductionGrant(cfg,ulGrant);
verifyTrue(testCase,logical(ulDecision.Valid),string(ulDecision.ReasonCode));
verifyEqual(testCase,double(ulDecision.K2),1);
verifyEqual(testCase,double(ulDecision.DataAbsoluteSlot),4);
verifyTrue(testCase,engine.IsULAllocation(4,[0 13]));
end

function testSIB1BandAndPRACHRemainTDD(testCase)
root = localRoot();
s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
txTree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits, encoded] = sixgr.rrc.asn1.encodeSIB1UPER(txTree);
[rxTree, decoded] = sixgr.rrc.asn1.decodeSIB1UPER(bits);
[equal, detail] = sixgr.rrc.asn1.compareSIB1Trees(txTree,rxTree);
txSIB1 = txTree.message.c1.systemInformationBlockType1;
rxSIB1 = rxTree.message.c1.systemInformationBlockType1;
verifyEqual(testCase, double(txSIB1.servingCellConfigCommon. ...
    downlinkConfigCommon.frequencyInfoDL.frequencyBandList.freqBandIndicatorNR),39);
verifyEqual(testCase, string(txSIB1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.preambleFormat),"B4");
verifyEqual(testCase, string(rxSIB1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.preambleFormat),"B4");
verifyTrue(testCase,equal,sprintf('SIB1 tree hash mismatch: %s != %s', ...
    detail.TxTreeHash,detail.RxTreeHash));
verifyEqual(testCase,string(encoded.PayloadHash),string(decoded.PayloadHash));
end

function testRankTwoULPTRSAssociationIsReceivedFromDCI(testCase)
root = localRoot();
s = sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    "simulator","configs","scenarios", ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml"));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
context = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,"0_1");
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
names = string([schema.Definitions.Name]);
verifyEqual(testCase, context.Data.PTRSDMRSAssociationWidth, 2);
verifyTrue(testCase, any(names == "ptrs_dmrs_association"));

grant = struct("NumLayers",2,"TPMI",0,"SRSResourceIndicator",0, ...
    "DAI",0,"TPCCommandForPUSCH",1,"SRSRequest",0, ...
    "PRBSet",0:105,"SymbolAllocation",[0 13]);
fields = struct();
for definition = schema.Definitions(:).'
    fields.(definition.Name) = definition.ValueMin;
end
fields.frequency_resource_assignment = ...
    sixgr.phy.pdcch.rivEncode(0,106,106);
fields.time_resource_assignment = 0;
fields.mcs = 1;
fields.ndi = 1;
fields = sixgr.phy.pdcch.ConnectedDCIProfile.scheduledFields( ...
    fields,context,cfg,grant,NaN);
packed = sixgr.phy.pdcch.DCIPacker.pack(fields,context);
decoded = sixgr.phy.pdcch.DCIParser.parse(packed.Bits,context);
verifyEqual(testCase, decoded.Fields.dmrs_port_set, [0 1]);
verifyEqual(testCase, decoded.Fields.ptrs_dmrs_association, 0);
verifyEqual(testCase, decoded.Fields.ptrs_dmrs_port_set, 0);

cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,3);
prepared = sixgr.link.preparePDCCHTransmission(cfg, ...
    "DCIBits",packed.Bits,"RNTI",cfg.phy.pusch.RNTI);
[received,info] = sixgr.phy.dl.PDCCH_Rx( ...
    prepared.TransmitSamples,cfg,"SampleRate_Hz",prepared.SampleRateHz);
verifyTrue(testCase,received.Ok);
assignment = sixgr.phy.pdcch.materializeConnectedDCI(received,info,cfg);
verifyEqual(testCase,assignment.NumLayers,2);
verifyEqual(testCase,assignment.DMRSPortSet,[0 1]);
verifyEqual(testCase,assignment.PTRSPortSet,0);
verifyEqual(testCase,assignment.PTRSPortSetSource, ...
    "received_dci_0_1_ptrs_dmrs_association");
end

function testRuntimeReceivesCDLRFAndO2IAuthorities(testCase)
root = localRoot();
scenarioRoot = fullfile(root,"simulator","configs","scenarios");
reference = sixgr.lls6g.config.loadScenarioConfig(fullfile(scenarioRoot, ...
    "lls_2ghz_20mhz_rank2_cdlc_reference.yaml"));
rfStudy = sixgr.lls6g.config.loadScenarioConfig(fullfile(scenarioRoot, ...
    "lls_2ghz_20mhz_rank2_cdlc_rf_impairments.yaml"));
o2iStudy = sixgr.lls6g.config.loadScenarioConfig(fullfile(scenarioRoot, ...
    "lls_2ghz_20mhz_rank2_cdlc_o2i_thermal.yaml"));
cfgReference = sixgr.lls6g.buildInternalConfig(reference,tempname);
cfgRF = sixgr.lls6g.buildInternalConfig(rfStudy,tempname);
cfgO2I = sixgr.lls6g.buildInternalConfig(o2iStudy,tempname);

verifyEqual(testCase, string(cfgReference.channel.model), "CDL");
verifyEqual(testCase, string(cfgReference.channel.cdlProfile), "CDL-C");
verifyTrue(testCase, logical(cfgReference.channel.fading.enable));
verifyTrue(testCase, logical(cfgRF.phy.impairments.cfoEnabled));
verifyTrue(testCase, logical(cfgRF.phy.impairments.phaseNoiseEnabled));
verifyTrue(testCase, logical(cfgRF.phy.impairments.iqImbalanceEnabled));
verifyTrue(testCase, logical(cfgRF.phy.impairments.paNonlinearityEnabled));
verifyTrue(testCase, logical(cfgRF.phy.impairments.adcQuantizationEnabled));
verifyTrue(testCase, logical(cfgRF.phy.impairments.dacQuantizationEnabled));
verifyTrue(testCase, logical(cfgRF.phy.impairments.timingOffsetEnabled));
verifyTrue(testCase, logical(cfgO2I.channel.pathlossEnabled));
verifyTrue(testCase, logical(cfgO2I.channel.shadowFadingEnabled));
verifyTrue(testCase, logical(cfgO2I.channel.o2i.enabled));
verifyTrue(testCase, logical(cfgO2I.channel.o2i.receiverIndoor));
verifyEqual(testCase, double(cfgO2I.channel.txPosition_m(:)), [0; 0; 25]);
verifyEqual(testCase, double(cfgO2I.channel.rxPosition_m(:)), [100; 0; 1.5]);
verifyTrue(testCase, logical(cfgO2I.channel.o2i.randomComponentEnabled));
verifyEqual(testCase, double(cfgO2I.channel.o2i.seed), 20260927);
end

function root = localRoot()
root = fileparts(fileparts(mfilename("fullpath")));
end
