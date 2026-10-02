function ok=testSystemFTP3CalibratedDelivery(direction,spatialMode,uciMode)
% Real scheduler/grant TBS and file ledger; TEST-ONLY BLER/spatial fixtures.
% This verifies software integration, not physical/study performance.
if nargin<1, direction="DL"; end
if nargin<2, spatialMode="fixture"; end
if nargin<3, uciMode="dedicated"; end
automatic=string(uciMode)=="automatic";
assert(any(string(uciMode)==["dedicated","automatic"]));
spatialMode=string(spatialMode); assert(any(spatialMode==["fixture","network"]));
direction=string(direction); assert(isscalar(direction) && any(direction==["DL","UL"]));
nTTI=2; if direction=="UL", nTTI=10; end
if direction=="DL" && spatialMode=="network", nTTI=20; end
if automatic, assert(direction=="UL" && spatialMode=="network"); nTTI=20; end
sc=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
sc=sc.toStruct();
sc.reference_signals.ssb_enabled=false; sc.initial_access.ssb.enabled=false;
sc.reference_signals.pbch_enabled=false; sc.initial_access.mib.enabled=false;
sc.mimo.beam_sweep_enabled=false; sc.reference_signals.trs_enabled=false;
sc.reference_signals.tracking_rs_enabled=false; sc.reference_signals.srs_enabled=false;
sc.control.pucch_enabled=false; sc.control.pdcch_enabled=true;
sc.control.blind_search_enabled=true; sc.reference_signals.pdcch_dmrs_enabled=true;
sc.phy.sib1.enable=false; sc.initial_access.sib1.enabled=false;
sc.mimo.qcl_tci.enabled=false; sc.control.connected_dci.tci_present=false;
sc.channels.pathloss_enabled=false; sc.channels.shadow_fading_enabled=false; sc.channels.los_enabled=false;
cfg=sixgr.lls6g.buildInternalConfig(sc,tempname);
cfg.run.shortRun=true; cfg.run.strictMode=false; cfg.run.useMex=false;
cfg.run.runTag='calibrated_backend_development_fixture'; cfg.run.executionID=cfg.run.runTag;
fragment=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,fragment);
cfg.system.resourceReservations.enabled=true;
cfg.system.linkAbstraction.allowDevelopmentFixtures=true;
cfg.system.linkAbstraction.spatialProviderClass='SLSAbstractionFixtureProvider';
cfg.scenario.layout.nSites=1; cfg.scenario.layout.nSectorsPerSite=1;
cfg.scenario.layout.wrapAround=false; cfg.scenario.ue.nUE=1; cfg.scenario.nUE=1;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true; cfg.channel.fading.enable=false;
cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false; cfg.channel.losEnabled=false;
cfg.phy.pucch.enable=false; cfg.phy.srs.enable=false; cfg.phy.pdcch.enable=true;
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg.traffic.model='ftp3'; cfg.traffic.ftp3.fileSizeBytes=100;
cfg.traffic.ftp3.arrivalRatePerCell_s=2e4; cfg.traffic.ftp3.direction=direction; cfg.traffic.ftp3.seed=7;
if automatic
    % This small-band reservation test leaves tiny real TBs. Use small
    % files so the unchanged completion/conservation assertions are also
    % exercised inside twenty slots; this is not FTP3 load calibration.
    cfg.traffic.ftp3.fileSizeBytes=8;
end
cfg.mac.scheduler.type='rr';
for name=["pdsch","pusch"]
    cfg.phy.(name).numLayers=1; cfg.phy.(name).nLayers=1;
    cfg.phy.(name).modulation='QPSK'; cfg.phy.(name).codeRate=120/1024;
end
cfg.outputs.saveCSV=true; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.outputs.saveFIG=false; cfg.outputs.exportSLSOutputCatalog=false;
cfg=sixgr.config.normalizeConfig(cfg); sixgr.config.validateConfig(cfg);
folder=fullfile(pwd,'logs','ai1032_calibrated_delivery_fixtures', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
if ~isfolder(folder), mkdir(folder); end
file=fullfile(folder,'development_fixture_calibration.mat');
curve=struct('CurveID',"dummy_not_used",'Key',struct('Unmatched',true,'EffectiveSINRMethod',"calibrated_eesm"),'RVSequence',0, ...
    'SINRAxes_dB',{{[-100;100]}},'BetaLinear',1,'TrialCount',[2000;2000], ...
    'ErrorCount',[200;200],'ValidationTrialCount',[2000;2000],'ValidationErrorCount',[200;200]);
calibration=struct('Schema',"sixgr.calibrated_sls_link/v1",'CalibrationID',"development_fixture", ...
    'SourceClassification',"development_fixture_not_physical_calibration",'Curves',curve);
provider=SLSAbstractionFixtureProvider();
if direction=="UL"
    cfg.system.linkAbstraction.spatialFeedback.enabled=true;
    cfg.system.linkAbstraction.spatialFeedback.allowedRanks=1;
    provider.FeedbackConfig=cfg;
end
if spatialMode=="network"
    cfg.system.linkAbstraction.spatialProviderClass='sixgr.system.abstraction.NetworkSpatialGrantProvider';
    cfg.rf=struct(); cfg.phy.impairments=struct(); % explicit ideal-RF test arm
    cfg.channel.model='TDL-A'; cfg.channel.tdlProfile='TDL-A';
    cfg.channel.fading.enable=true; cfg.channel.fading.tdlProfile='TDL-A';
    cfg.channel.normalizeChannelOutputs=false; cfg.channel.delaySpread_s=30e-9;
    cfg.phy.srs.enable=true; cfg.phy.srs.period_slots=5; cfg.phy.srs.period_offset=4;
    cfg.phy.srs.slotNumbers=4:5:(nTTI-1); cfg.phy.srs.SymbolStart=13;
    cfg.scenario.ue.txPower_dBm=-30; % component-test link budget, not a study result
    cfg.scenario.bs.txPower_dBm=-30;
    bs=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,'bs','Signal','PDSCH','MinimumPorts',1);
    ue=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,'ue','Signal','PUSCH','MinimumPorts',1);
    cfg.system.linkAbstraction.networkSpatial.bsPorts=bs.NumPorts;
    cfg.system.linkAbstraction.networkSpatial.uePorts=ue.NumPorts;
    if direction=="DL" || automatic
        if direction=="DL", cfg.phy.srs.enable=false; end
        cfg.system.linkAbstraction.dlFeedback.enabled=true;
        cfg.system.linkAbstraction.dlFeedback.allowedRanks=[1 2];
        cfg.system.linkAbstraction.dlFeedback.panel.Ports=bs.NumPorts;
        cfg.system.resourceReservations.commonChannelCalendarEnabled=true;
        cfg.phy.pucch.enable=true; cfg.phy.pucch.uciOnPUSCHEnabled=false;
        cfg.system.linkAbstraction.dynamicPUCCH.enabled=true;
        if automatic
            cfg.phy.pucch.uciOnPUSCHEnabled=true;
            cfg.system.linkAbstraction.dynamicPUCCH.transportPolicy='causal_native_pusch_multiplexing';
            % Put periodic CSI on full UL slots (4 mod 5), where this
            % fixture's K2 grants execute. The baseline special-slot CSI
            % calendar (3 mod 5) does not overlap PUSCH and must not move.
            cfg.phy.csi.reportOffsetSlots=4;
        end
    end
    provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
end
params=struct('NumTTI',nTTI,'PHYBackend','calibrated_link_abstraction','SpatialGrantProvider',provider);
% Discover the actual scheduler's allocation, never invent a grant/TBS from
% throughput. Preflight failures cannot become a result or successful TB.
complete=false;
for attempt=1:8
    save(file,'calibration');
    cfg.system.linkAbstraction.calibrationFile=file;
    cfg.system.linkAbstraction.calibrationSHA256=sixgr.csi.studyFileSHA256(file);
    context=sixgr.core.SimContext(cfg,'RunFolder',fullfile(folder,"attempt_"+attempt));
    cleanup=onCleanup(@()context.Logger.close()); %#ok<NASGU>
    try
        r=sixgr.system.SystemLevelRunner.run(context,params);
        complete=true; break;
    catch ME
        if ~strcmp(ME.identifier,'sixgr:abstraction:CalibrationCoverage'), rethrow(ME); end
        actual=provider.LastContext;
        curve.Key=sixgr.system.CalibratedLinkPHY.calibrationKey(actual,provider.LastObservation);
        curve.CurveID="actual_scheduler_key_fixture_"+attempt;
        calibration.Curves(end+1)=curve;
    end
    clear cleanup;
end
assert(complete && r.Ok && ~r.Details.WaveformBacked && r.Details.ProxyPHYActive && ~r.Details.FallbackUsed);
G=r.Details.SchedulerGrants; F=r.Details.FTP3Files;
assert(~isempty(G) && any(F.Completed) && sum(F.DeliveredBits)>0);
assert(all(G.PHYDecisionRole=="calibrated_sls_estimate") && ~any(G.WaveformReplayExecuted));
assert(all(G.SourceClassification=="development_fixture_not_study_result") && ~any(G.CalibrationQualified));
assert(all(isfinite(G.ModeledEffectiveSINR_dB)) && all(isnan(G.PostEqSINR_dB)));
assert(~r.KPITable.PrimaryResultEligible && ~r.Details.PrimaryResultEligible);
assert(r.KPITable.SINRMetricDefinition=="large_scale_link_budget_not_decoding_effective_sinr");
other="UL"; if direction=="UL", other="DL"; end
if spatialMode=="fixture"
    assert(abs(r.KPITable.("MeanModeledEffectiveSINR_"+direction+"_dB"))<1e-12);
else
    if direction=="UL"
        assert(all(G.ScheduledAbsoluteSlot>=5),'No UL grant before first modeled SRS delivery.');
    else
        csi=r.Details.ModeledDLCSI;
        assert(~isempty(csi) && all(csi.AvailableAbsoluteSlot0<=csi.ControlAbsoluteSlot0));
        assert(all(G.ScheduledAbsoluteSlot>=min(csi.AvailableAbsoluteSlot0)));
        assert(any(csi.RI==2) && any(G.NumLayers==2), ...
            'The frequency-selective integration case must actually schedule selected rank 2.');
        assert(any(r.Details.ResourceReservationTable.Channel=="PUCCH"));
        uci=r.Details.DynamicPUCCHObligations;
        assert(any(uci.HARQBits>0 & uci.CSIPart1Bits>0 & uci.SRBits>0), ...
            'Integration must exercise combined HARQ/CSI/SR, not only standalone SR.');
        assert(sum(uci.HARQBits)==sum(G.ScheduledAbsoluteSlot+G.K1<nTTI), ...
            'Every in-window issued DL feedback obligation must be accounted for exactly once.');
        assert(all(G.SchedulerCQISource=="modeled_csi_not_waveform_measurement") && ...
            all(G.MCSValueStatus=="modeled_cqi_mapped_not_waveform_measurement"));
        persistedUCI=readtable(fullfile(context.RunFolder,'csv','system_dynamic_pucch_obligations.csv'));
        assert(height(persistedUCI)==height(uci) && ~any(uci.WaveformBacked));
        assert(~any(csi.WaveformBacked));
        exported=readtable(fullfile(context.RunFolder,'csv','system_modeled_dl_csi.csv'));
        assert(height(exported)==height(csi));
    end
    network=r.Details.NetworkSpatialEvidence;
    assert(height(network)==height(G) && all(~network.WaveformBacked) && ...
        all(~network.ArrayQualified) && all(~network.RFQualified));
    persisted=readtable(fullfile(context.RunFolder,'csv','system_network_spatial_evidence.csv'));
    assert(height(persisted)==height(network),'Persist every executed modeled network observation.');
end
assert(isnan(r.KPITable.("MeanModeledEffectiveSINR_"+other+"_dB"))); % no invented unscheduled samples
assert(sum(F.DeliveredBits)==sum(G.UniqueDeliveredApplicationBits,'omitnan'));
assert(all(F.DeliveredBits+F.DroppedBits+F.RemainingBits==F.OfferedBits));
assert(sum(F.RemainingBits)==sum(r.Details.RemainingQueueBits));
if automatic
    obligations=r.Details.DynamicPUCCHObligations;
    completions=r.Details.DynamicUCICompletions;
    assert(any(obligations.Transport=="PUSCH") && any(obligations.Transport=="PUCCH"), ...
        'Execute both automatic PUSCH multiplexing and retained dedicated PUCCH.');
    mux=obligations(obligations.Transport=="PUSCH",:);
    assert(all(mux.PUSCHUCIAllocatedRECount>0) && all(strlength(mux.PUSCHGrantSHA256)==64));
    assert(all(ismember(mux.ObligationID,completions.ObligationID)) && ...
        ~any(completions.WaveformBacked) && ~any(completions.PhysicalDecodeQualified));
    assert(isfile(fullfile(context.RunFolder,'csv','system_dynamic_uci_completions.csv')));
    % Replay transport decisions on the actual final issued grant. These
    % are negative contract checks, not new waveform/trial evidence.
    actual=provider.LastContext; g=actual.Grant; target=g.ScheduledAbsoluteSlot;
    assert(~isempty(fieldnames(g.SLSUCIAllocation)));
    ue=struct('UEID',g.RNTI,'RNTI',g.RNTI,'ServingCell',1,'PUCCHCell',1, ...
        'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
        'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
    calendar=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,target+1,target+1);
    refs=struct('UEIndex',g.RNTI,'ServingCell',1,'ReportAbsoluteSlot0',target, ...
        'SourceAbsoluteSlot0',calendar.CSIReferenceSlot(1)-1, ...
        'ReferenceAvailableAtSlot0',calendar.CSIReferenceSlot(1)-1);
    ledger=sixgr.system.SLSDynamicPUCCH(cfg);
    g=ledger.bindPUSCH(g,1,g.ControlAbsoluteSlot,1,refs);
    assert(~ledger.reportCompleted(g.RNTI,1,target));
    rejectUCI(@()ledger.snapshot(target,target,1,struct([])),'sixgr:system:SLSUCILateObligation');
    rejectUCI(@()ledger.completeSlot(target,1,refs,{g},struct([])),'sixgr:system:SLSUCINotExecuted');
    changed=g; changed.PRBSet=g.PRBSet+1;
    rejectUCI(@()ledger.completeSlot(target,1,refs,{changed},changed),'sixgr:system:PUSCHUCIReservationBinding');
    ledger.completeSlot(target,1,refs,{g},g);
    assert(ledger.reportCompleted(g.RNTI,1,target));
    rejectUCI(@()ledger.completeSlot(target,1,refs,{g},g),'sixgr:system:SLSUCIDuplicateCompletion');
end
sixgr.report.exportSLSOutputCatalog(context.RunFolder,cfg,r,r.RuntimeSummary,r.EnvironmentSummary);
manifest=jsondecode(fileread(fullfile(context.RunFolder,'manifests','system_run_manifest.json')));
assert(~manifest.PrimaryResultEligible && ~manifest.WaveformBacked);
assert(~isfile(fullfile(context.RunFolder,'air_interface','csv','dl_pdsch_trials.csv')));
assert(~isfile(fullfile(context.RunFolder,'air_interface','csv','ul_pusch_trials.csv')));
if direction=="UL"
    feedback=r.Details.ModeledSpatialFeedback;
    assert(~isempty(feedback) && all(~feedback.WaveformBacked));
    assert(all(feedback.SourceAbsoluteSlot0<feedback.AvailableAbsoluteSlot0));
    assert(all(feedback.AvailableAbsoluteSlot0<=feedback.ControlAbsoluteSlot0));
    assert(all(feedback.EstimationAssumption=="ideal_delayed_channel_estimate"));
    exported=readtable(fullfile(context.RunFolder,'csv','system_modeled_spatial_feedback.csv'));
    assert(height(exported)==height(feedback),'Persist the exact modeled feedback trace.');
    if spatialMode=="fixture"
    probe=sixgr.system.CalibratedLinkPHY(cfg,params,11);
    u=struct('RNTI',1,'CQI',0,'CausalFeedbackUsable',false, ...
        'CausalFeedbackStatus','stale_cqi_test','FeedbackAgeSlots',99);
    state=struct('AbsoluteSlot0',0,'ServingCells',1);
    probe.advanceULSpatialFeedback(u,state,3);
    state.AbsoluteSlot0=2;
    v=probe.advanceULSpatialFeedback(u,state,3);
    assert(v.ModeledSRSCausalUsable && ~v.CausalFeedbackUsable && v.CQI==0 && ...
        strcmp(v.CausalFeedbackStatus,'stale_cqi_test') && v.FeedbackAgeSlots==99, ...
        'Modeled spatial feedback must never authorize stale CQI.');
    end
    % Replay a late control obligation on an actually issued future UL
    % allocation. It must be invisible at scheduling, then block BEFORE
    % that grant reaches the abstract decoder. This is not a PHY trial.
    actual=provider.LastContext; g=actual.Grant;
    assert(g.ScheduledAbsoluteSlot>g.ControlAbsoluteSlot);
    lateParams=params;
    lateParams.ResourceReservationObligations=struct( ...
        'ResourceID',"late_control_test",'CellID',actual.ServingCellID, ...
        'UEIndex',g.ModeledSRSFeedback.UEIndex,'Direction',"UL", ...
        'AbsoluteSlot0',g.ScheduledAbsoluteSlot, ...
        'KnownAtAbsoluteSlot0',g.ControlAbsoluteSlot+1,'Channel',"PUCCH", ...
        'Coordinates0Based',[12*double(g.PRBSet(1)) double(g.SymbolAllocation(1)) 0], ...
        'EvidenceKind',"scheduled_receive_obligation", ...
        'Source',"late_reservation_software_fixture_not_received_control",'Transport',"PUCCH");
    lateContext=sixgr.core.SimContext(cfg,'RunFolder',fullfile(folder,'late_obligation_rejection'));
    closeLate=onCleanup(@()lateContext.Logger.close()); %#ok<NASGU>
    rejected=false;
    try
        sixgr.system.SystemLevelRunner.run(lateContext,lateParams);
    catch ME
        assert(strcmp(ME.identifier,'sixgr:system:ReservedResourceCollision'), ...
            'Expected execution-time collision, got %s: %s',ME.identifier,ME.message);
        rejected=true;
    end
    assert(rejected,'A newly available control reservation must block the colliding issued grant.');
    fprintf('SYSTEM_SLS_LATE_UL_RESERVATION_REJECTED_BEFORE_DECODE slot0=%d\n',g.ScheduledAbsoluteSlot);
end
fprintf('SYSTEM_FTP3_CALIBRATED_DELIVERY_PASS calibration_fixture_only=1 spatial=%s direction=%s grants=%d unique_bits=%g folder=%s\n',spatialMode,direction,height(G),sum(F.DeliveredBits),folder);
ok=true;
end
function rejectUCI(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s',id,ME.identifier,ME.message); return; end
error('test:NoRejection','Expected %s',id);
end
