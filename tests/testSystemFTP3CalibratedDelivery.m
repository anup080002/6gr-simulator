function ok=testSystemFTP3CalibratedDelivery(direction,spatialMode,uciMode,resourceBindingMode,networkConfigFile,configuredBackend)
% Real scheduler/grant TBS and file ledger; TEST-ONLY BLER/spatial fixtures.
% This verifies software integration, not physical/study performance.
if nargin<1, direction="DL"; end
if nargin<2, spatialMode="fixture"; end
if nargin<3, uciMode="dedicated"; end
if nargin<4, resourceBindingMode="shared_configured_resources"; end
if nargin<5, networkConfigFile=""; end
if nargin<6, configuredBackend="calibrated_link_abstraction"; end
assert(any(string(resourceBindingMode)==["shared_configured_resources","per_cell_frequency_pool"]));
automatic=string(uciMode)=="automatic";
nonoverlap=string(uciMode)=="nonoverlapping";
withUCI=automatic || nonoverlap;
assert(any(string(uciMode)==["dedicated","automatic","nonoverlapping"]));
spatialMode=string(spatialMode); assert(any(spatialMode==["fixture","network","deferred_fixture"]));
direction=string(direction); assert(isscalar(direction) && any(direction==["DL","UL"]));
nTTI=2; if direction=="UL", nTTI=10; end
if direction=="DL" && spatialMode=="network", nTTI=20; end
if withUCI, assert(direction=="UL" && spatialMode=="network"); nTTI=20; end
if spatialMode=="deferred_fixture", assert(direction=="DL"); nTTI=3; end
sc=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
sc=sc.toStruct();
if nonoverlap
    sc=sixgr.util.mergeStruct(sc,sixgr.lls6g.config.readConfigFile( ...
        'simulator/configs/validation/sls_nonoverlapping_uci_fixture.yaml'));
end
sc.reference_signals.ssb_enabled=false; sc.initial_access.ssb.enabled=false;
sc.reference_signals.pbch_enabled=false; sc.initial_access.mib.enabled=false;
sc.mimo.beam_sweep_enabled=false; sc.reference_signals.trs_enabled=false;
sc.reference_signals.tracking_rs_enabled=false;
% Resolve enabled feedback producers through scenario authority, not by
% switching a disabled runtime consumer on after buildInternalConfig.
sc.reference_signals.srs_enabled=spatialMode=="network" && direction=="UL";
sc.control.pucch_enabled=spatialMode=="network" && (direction=="DL" || withUCI);
sc.control.pdcch_enabled=true;
sc.control.blind_search_enabled=true; sc.reference_signals.pdcch_dmrs_enabled=true;
sc.phy.sib1.enable=false; sc.initial_access.sib1.enabled=false;
sc.mimo.qcl_tci.enabled=false; sc.control.connected_dci.tci_present=false;
sc.channels.pathloss_enabled=false; sc.channels.shadow_fading_enabled=false; sc.channels.los_enabled=false;
networkOverlay=struct();
if spatialMode=="network"
    % This arm installs a concrete fading channel below. The inherited
    % identity-AWGN operator is incompatible with that and with pathloss.
    sc.channels.shared_identity_awgn_enabled=false;
    sc=sixgr.util.mergeStruct(sc,sixgr.lls6g.config.readConfigFile( ...
        'simulator/configs/validation/sls_ideal_rf_feedback_fixture.yaml'));
    if any(strlength(string(networkConfigFile))>0)
        for fragmentPath=reshape(string(networkConfigFile),1,[])
            networkOverlay=sixgr.util.mergeStruct(networkOverlay,sixgr.lls6g.config.readConfigFile(fragmentPath));
        end
        % This overlay is in internal-config units. Resolve its feature
        % switches into the scenario before buildInternalConfig freezes
        % authority; never mutate runtime.features to excuse a bypass.
        pairs={ 'pathlossEnabled','pathloss_enabled'; ...
            'shadowFadingEnabled','shadow_fading_enabled'; 'losEnabled','los_enabled'};
        for flag=1:size(pairs,1)
            value=sixgr.util.structGet(networkOverlay,"channel."+string(pairs{flag,1}),[]);
            if ~isempty(value), sc.channels.(pairs{flag,2})=value; end
        end
    end
end
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
cfg.channel.pathlossEnabled=sc.channels.pathloss_enabled;
cfg.channel.shadowFadingEnabled=sc.channels.shadow_fading_enabled;
cfg.channel.losEnabled=sc.channels.los_enabled;
cfg.phy.pucch.enable=sc.control.pucch_enabled;
cfg.phy.srs.enable=sc.reference_signals.srs_enabled; cfg.phy.pdcch.enable=true;
cfg.phy.ssb.enable=false; cfg.phy.sib1.enable=false; cfg.phy.trs.enable=false;
cfg.traffic.model='ftp3'; cfg.traffic.ftp3.fileSizeBytes=100;
cfg.traffic.ftp3.arrivalRatePerCell_s=2e4; cfg.traffic.ftp3.direction=direction; cfg.traffic.ftp3.seed=7;
if withUCI
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
folder=fullfile(pwd,'logs','sls_calibrated_delivery_fixtures', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
if ~isfolder(folder), mkdir(folder); end
file=fullfile(folder,'development_fixture_calibration.mat');
curve=struct('CurveID',"dummy_not_used",'Key',struct('Unmatched',true,'EffectiveSINRMethod',"calibrated_eesm"),'RVSequence',0, ...
    'SINRAxes_dB',{{[-100;100]}},'BetaLinear',1,'TrialCount',[2000;2000], ...
    'ErrorCount',[200;200],'ValidationTrialCount',[2000;2000],'ValidationErrorCount',[200;200]);
calibration=struct('Schema',"sixgr.calibrated_sls_link/v1",'CalibrationID',"development_fixture", ...
    'SourceClassification',"development_fixture_not_physical_calibration",'Curves',curve);
provider=SLSAbstractionFixtureProvider();
if spatialMode=="deferred_fixture"
    cfg.system.linkAbstraction.spatialProviderClass='SLSDeferredFixtureProvider';
    cfg.system.linkAbstraction.networkSpatial.sinrPredictorModel='finite_committed_shared_data';
    provider=SLSDeferredFixtureProvider();
end
if direction=="UL"
    cfg.system.linkAbstraction.spatialFeedback.enabled=true;
    cfg.system.linkAbstraction.spatialFeedback.allowedRanks=1;
    provider.FeedbackConfig=cfg;
end
if spatialMode=="network"
    % Recording subclass delegates unchanged model execution to the real
    % provider; bind its identity explicitly rather than bypassing the guard.
    cfg.system.linkAbstraction.spatialProviderClass='SLSRecordingNetworkProvider';
    % Preserve the explicitly disabled RF consumers and their authority.
    % Deleting these structs conceals configuration instead of modeling ideal RF.
    % Replace the inherited AWGN arm completely before normalization. A
    % residual awgnOnly=true otherwise silently disables the fading arm.
    cfg.channel.awgnOnly=false; cfg.channel.model='TDL';
    cfg.channel.tdlProfile='TDL-A'; cfg.channel.cdlProfile='';
    cfg.channel.delayProfile='TDL-A';
    cfg.channel.fading.enable=true; cfg.channel.fading.model='TDL';
    cfg.channel.fading.profile='TDL-A'; cfg.channel.fading.tdlProfile='TDL-A';
    cfg.channel.normalizeChannelOutputs=false; cfg.channel.delaySpread_s=30e-9;
    cfg.phy.srs.enable=true; cfg.phy.srs.period_slots=5; cfg.phy.srs.period_offset=4;
    cfg.phy.srs.slotNumbers=4:5:(nTTI-1); cfg.phy.srs.SymbolStart=13;
    cfg.scenario.ue.txPower_dBm=-30; % component-test link budget, not a study result
    cfg.scenario.bs.txPower_dBm=-30;
    bs=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,'bs','Signal','PDSCH','MinimumPorts',1);
    ue=sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg,'ue','Signal','PUSCH','MinimumPorts',1);
    cfg.system.linkAbstraction.networkSpatial.bsPorts=bs.NumPorts;
    cfg.system.linkAbstraction.networkSpatial.uePorts=ue.NumPorts;
    if direction=="DL" || withUCI
        if direction=="DL", cfg.phy.srs.enable=false; end
        cfg.system.linkAbstraction.dlFeedback.enabled=true;
        cfg.system.linkAbstraction.dlFeedback.allowedRanks=[1 2];
        cfg.system.linkAbstraction.dlFeedback.panel.Ports=bs.NumPorts;
        cfg.system.resourceReservations.commonChannelCalendarEnabled=true;
        cfg.phy.pucch.enable=true; cfg.phy.pucch.uciOnPUSCHEnabled=false;
        cfg.system.linkAbstraction.dynamicPUCCH.enabled=true;
        if withUCI
            cfg.phy.csi.reportOffsetSlots=4;
        end
        if automatic
            cfg.phy.pucch.uciOnPUSCHEnabled=true;
            cfg.system.linkAbstraction.dynamicPUCCH.transportPolicy='causal_native_pusch_multiplexing';
            % Put periodic CSI on full UL slots (4 mod 5), where this
            % fixture's K2 grants execute. The baseline special-slot CSI
            % calendar (3 mod 5) does not overlap PUSCH and must not move.
            cfg.phy.csi.reportOffsetSlots=4;
        end
    end
    if string(resourceBindingMode)=="per_cell_frequency_pool"
        assert(cfg.system.linkAbstraction.dynamicPUCCH.enabled);
        resources=cfg.validation.pucch_resources.resources;
        span=0;
        for resource=reshape(resources,1,[])
            starts=double(resource.starting_prb);
            if resource.intra_slot_hopping, starts=[starts double(resource.second_hop_start_prb)]; end
            span=max(span,max(starts)+resource.nrof_prbs);
        end
        cfg.system.linkAbstraction.dynamicPUCCH.resourceBinding=struct( ...
            'mode','per_cell_frequency_pool','firstPRB',0,'stridePRB',span,'capacityPerCell',1);
    end
    if any(strlength(string(networkConfigFile))>0)
        cfg=sixgr.util.mergeStruct(cfg,networkOverlay);
    end
    cfg=sixgr.config.normalizeConfig(cfg);
    sixgr.config.validateConfig(cfg);
    assert(~cfg.channel.awgnOnly && strcmp(cfg.channel.model,'TDL') && ...
        strcmp(cfg.channel.tdlProfile,'TDL-A') && cfg.channel.fading.enable && ...
        strcmp(cfg.channel.fading.model,'TDL') && strcmp(cfg.channel.fading.profile,'TDL-A'), ...
        'The network fixture must retain its configured concrete fading channel after normalization.');
    provider=SLSRecordingNetworkProvider(cfg);
end
assert(all(strlength(string(networkConfigFile))==0) || spatialMode=="network");
expectedUEs=double(cfg.scenario.ue.nUE);
params=struct('NumTTI',nTTI,'PHYBackend','calibrated_link_abstraction','SpatialGrantProvider',provider);
params.RNTIByUE=(4660+(0:expectedUEs-1)).';
% Discover the actual scheduler's allocation, never invent a grant/TBS from
% throughput. Preflight failures cannot become a result or successful TB.
complete=false;
for attempt=1:(8*expectedUEs)
    if spatialMode=="deferred_fixture"
        provider=SLSDeferredFixtureProvider(); params.SpatialGrantProvider=provider;
    end
    if spatialMode=="network"
        % Each calibration-key discovery attempt is a NEW simulation, not
        % continuation of the previous provider's channel/slot/UCI history.
        provider=SLSRecordingNetworkProvider(cfg);
        params.SpatialGrantProvider=provider;
    end
    save(file,'calibration');
    cfg.system.linkAbstraction.calibrationFile=file;
    cfg.system.linkAbstraction.calibrationSHA256=sixgr.csi.studyFileSHA256(file);
    context=sixgr.core.SimContext(cfg,'RunFolder',fullfile(folder,"attempt_"+attempt));
    % Exercise runtime mode selection without changing the provider's
    % explicitly modeled calibration/feedback assumptions.
    context.Cfg.system.phyBackend=char(configuredBackend);
    cleanup=onCleanup(@()context.Logger.close()); %#ok<NASGU>
    try
        r=sixgr.system.SystemLevelRunner.run(context,params);
        complete=true; break;
    catch ME
        if ~strcmp(ME.identifier,'sixgr:abstraction:CalibrationCoverage'), rethrow(ME); end
        assert(contains(string(ME.message),"KeySHA256=") && ...
            contains(string(ME.message),"KeyJSON="), ...
            'Missing calibration must retain the exact physical key for audit.');
        actual=provider.LastContext;
        curve.Key=sixgr.system.CalibratedLinkPHY.calibrationKey(actual,provider.LastObservation);
        curve.CurveID="actual_scheduler_key_fixture_"+attempt;
        calibration.Curves(end+1)=curve;
    end
    clear cleanup;
end
assert(complete && r.Ok && ~r.Details.WaveformBacked && r.Details.ProxyPHYActive && ~r.Details.FallbackUsed);
G=r.Details.SchedulerGrants; F=r.Details.FTP3Files;
if logical(sixgr.util.structGet(cfg,'system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC.enabled',false))
    sr=r.Details.ModeledSchedulingRequestProcedures;
    if direction=="UL"
        assert(~isempty(sr) && any(sr.Event=="trigger") && all(~sr.WaveformBacked));
        assert(all(sr.RNTI==params.RNTIByUE(sr.UEIndex)));
        srCSV=readtable(fullfile(context.RunFolder,'csv','system_modeled_sr_procedure.csv'));
        assert(height(srCSV)==height(sr) && isequal(string(srCSV.Event),sr.Event));
    else
        % DL arrivals do not create a UE UL buffer or a positive SR. Keep
        % the absence of events honest rather than inventing a trigger.
        assert(isempty(sr),'DL-only arrivals must not trigger uplink SR.');
        assert(~isfile(fullfile(context.RunFolder,'csv','system_modeled_sr_procedure.csv')));
        assert(all(r.Details.DynamicUCICompletions.PositiveSRCount==0) && ...
            ~any(r.Details.DynamicUCICompletions.SRDeliveryClaimed));
    end
    assert(string(r.Details.SchedulingRequestMACPolicy.schedulerBufferKnowledge)== ...
        "ideal_instantaneous_unallocated_buffer");
    completions=r.Details.DynamicUCICompletions;
    assert(all(completions.SRPayloadKnown(completions.Transport=="PUCCH")) && ...
        ~any(completions.SRDeliveryClaimed(completions.Transport=="PUSCH")));
    fprintf('SLS_SR_RUNTIME_WIRING_PASS owned_events=%d ideal_buffer_knowledge=1 full_MAC_qualified=0\n',height(sr));
end
assert(~isempty(G) && all(G.RNTI==params.RNTIByUE(G.UE)), ...
    'Grant exports must retain protocol identity separately from internal UE ownership.');
if cfg.system.linkAbstraction.spatialFeedback.enabled || cfg.system.linkAbstraction.dlFeedback.enabled
    captures=r.Details.ModeledFeedbackCapture;
    assert(height(captures)==nTTI && isequal(captures.TTI,(1:nTTI).') && ...
        isequal(captures.CaptureAbsoluteSlot0,(0:nTTI-1).') && ...
        all(captures.CapturePhase=="after_committed_scheduled_population") && ...
        all(~captures.WaveformBacked));
    captureCSV=readtable(fullfile(context.RunFolder,'csv','system_modeled_feedback_capture.csv'));
    assert(height(captureCSV)==height(captures) && ...
        isequal(captureCSV.CSIObservations,captures.CSIObservations) && ...
        isequal(captureCSV.SRSObservations,captures.SRSObservations));
end
if spatialMode=="deferred_fixture"
    censored=G.PHYDecisionStatus=="RIGHT_CENSORED";
    assert(any(censored) && ~isempty(r.Details.PendingPHYReceptions));
    assert(r.Details.RightCensoredPHYReceptionCount==sum(censored));
    assert(all(isnan(G.BLER(censored))) && all(isnan(G.ReceiveCompletionAbsoluteSlot0(censored))) && ...
        all(G.UniqueDeliveredApplicationBits(censored)==0));
    assert(sum(r.Details.HARQProcesses.Outcome=="RIGHT_CENSORED")==sum(censored));
    completed=G(~censored,:);
    assert(~isempty(completed) && all(completed.ReceiveCompletionAbsoluteSlot0==completed.TransmissionAbsoluteSlot0+1));
    assert(sum(G.UniqueDeliveredApplicationBits,'omitnan')==sum(F.DeliveredBits));
    assert(all(completed.TTI==completed.TransmissionAbsoluteSlot0+1));
    assert(r.Details.ServedBitsPerTTI_DL(1)==0 && ...
        sum(r.Details.ServedBitsPerTTI_DL)==sum(F.DeliveredBits));
    % The pending-grant loop must preserve the original SimContext through
    % persistence, not only return correct in-memory accounting.
    persistedGrants=readtable(fullfile(context.RunFolder,'csv','system_scheduler_grants.csv'));
    assert(height(persistedGrants)==height(G));
    assert(isequaln(persistedGrants.TransmissionAbsoluteSlot0,G.TransmissionAbsoluteSlot0) && ...
        isequaln(persistedGrants.ReceiveCompletionAbsoluteSlot0,G.ReceiveCompletionAbsoluteSlot0));
    assert(sum(string(persistedGrants.PHYDecisionStatus)=="RIGHT_CENSORED")==sum(censored));
    G=completed; % The remaining assertions concern completed decisions only.
    fprintf('SLS_RUNNER_DEFERRED_ACCOUNTING_PASS completed=%d censored=%d no_early_delivery=1\n',height(G),sum(censored));
end
assert(~isempty(G) && any(F.Completed) && sum(F.DeliveredBits)>0);
assert(all(G.PHYDecisionRole=="calibrated_sls_estimate") && ~any(G.WaveformReplayExecuted));
assert(all(strlength(G.CalibrationKeySHA256)==64), ...
    'Every modeled grant must export its exact calibration-key digest.');
assert(all(G.SourceClassification=="development_fixture_not_study_result") && ~any(G.CalibrationQualified));
if spatialMode=="network" && direction=="DL"
    decisions=r.Details.ModeledHARQPayloadDecisions;
    assert(~isempty(decisions) && height(decisions)==nnz(G.Direction=="DL") && ...
        ~any(decisions.WaveformBacked) && ~any(decisions.CalibrationQualified) && ...
        all(decisions.SourceClassification=="development_fixture_not_study_result"));
    for row=1:height(decisions)
        d=decisions(row,:);
        matched=G.Direction=="DL" & G.RNTI==d.RNTI & ...
            G.TransmissionAbsoluteSlot0==d.TransmissionAbsoluteSlot0;
        assert(nnz(matched)==1 && G.ReceiveCompletionAbsoluteSlot0(matched)==d.ReceiveCompletionAbsoluteSlot0 && ...
            string(G.TransportBlockIdentity(matched))==d.TransportBlockIdentity);
    end
    saved=readtable(fullfile(context.RunFolder,'csv','system_modeled_harq_payload_decisions.csv'));
    assert(height(saved)==height(decisions) && isequal(double(saved.ACK),double(decisions.ACK)) && ...
        isequal(saved.ReceiveCompletionAbsoluteSlot0,decisions.ReceiveCompletionAbsoluteSlot0));
end
assert(all(isfinite(G.ModeledEffectiveSINR_dB)) && all(isnan(G.PostEqSINR_dB)));
assert(~r.KPITable.PrimaryResultEligible && ~r.Details.PrimaryResultEligible);
if string(resourceBindingMode)=="per_cell_frequency_pool"
    bindings=r.Details.UCIResourceBindings;
    assert(height(bindings)==expectedUEs && all(bindings.Action=="installed") && ~any(bindings.WaveformBacked));
    persisted=readtable(fullfile(context.RunFolder,'csv','system_uci_resource_bindings.csv'));
    assert(height(persisted)==height(bindings));
    obligations=r.Details.DynamicPUCCHObligations;
    for b=1:height(bindings)
        owned=obligations.UEIndex==bindings.UEIndex(b) & obligations.CellID==bindings.CellID(b);
        assert(any(owned) && all(obligations.PUCCHRRCContextDigest(owned)==bindings.RRCContextDigest(b)));
    end
end
assert(r.KPITable.SINRMetricDefinition=="large_scale_link_budget_not_decoding_effective_sinr");
other="UL"; if direction=="UL", other="DL"; end
if spatialMode~="network"
    assert(abs(r.KPITable.("MeanModeledEffectiveSINR_"+direction+"_dB"))<1e-12);
else
    [history,historyEvidence]=provider.interferenceWindow(nTTI);
    assert(history{end}.TTI==nTTI && historyEvidence.HistoryComplete && ...
        historyEvidence.CommittedSlotCount==nTTI && ...
        historyEvidence.ExplicitIdleSlotCount>0 && ...
        ~historyEvidence.WaveformMeasured && ~historyEvidence.ControlRSInterferenceIncluded, ...
        'The production runner must commit every finalized slot, including idle slots.');
    fprintf('SLS_RUNTIME_SLOT_HISTORY_PASS slots=%d explicit_idle=%d waveform_measured=0\n', ...
        historyEvidence.CommittedSlotCount,historyEvidence.ExplicitIdleSlotCount);
    if direction=="UL"
        assert(all(G.ScheduledAbsoluteSlot>=5),'No UL grant before first modeled SRS delivery.');
        srs=r.Details.ModeledSpatialFeedback;
        exported=readtable(fullfile(context.RunFolder,'csv','system_modeled_spatial_feedback.csv'));
        assert(height(exported)==height(srs) && ~isempty(srs));
        emittedSRS=any(string(cfg.system.linkAbstraction.networkSpatial.interferencePopulation)== ...
            ["scheduled_shared_data_and_srs","scheduled_shared_data_and_srs_and_csirs", ...
            "scheduled_shared_data_and_srs_and_csirs_and_pdcch"]);
        assert(all(srs.ReferenceEmissionBound==emittedSRS) && ...
            isequaln(exported.ReferenceResourceID,srs.ReferenceResourceID) && ...
            isequaln(exported.ReferenceRNTI,srs.ReferenceRNTI));
        if emittedSRS
            assert(all(srs.ReferenceResourceID==srs.SRI) && ...
                all(strlength(srs.ReferenceEmissionSHA256)==64) && ...
                all(srs.ReferenceRNTI==reshape(params.RNTIByUE(srs.UEIndex),[],1)) && ...
                isequal(string(exported.ReferenceEmissionSHA256),srs.ReferenceEmissionSHA256));
        else
            assert(all(isnan(srs.ReferenceResourceID)) && all(isnan(srs.ReferenceRNTI)) && ...
                all(strlength(srs.ReferenceEmissionSHA256)==0));
        end
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
        assert(all(ismember({'ReferenceResourceID','ReferenceEmissionSHA256','ReferenceEmissionBound'}, ...
            exported.Properties.VariableNames)));
        emittedCSI=string(cfg.system.linkAbstraction.networkSpatial.interferencePopulation)== ...
            "scheduled_shared_data_and_srs_and_csirs";
        assert(all(logical(csi.ReferenceEmissionBound)==emittedCSI));
        if emittedCSI
            assert(all(isfinite(csi.ReferenceResourceID)) && all(strlength(csi.ReferenceEmissionSHA256)==64));
            assert(isequaln(exported.ReferenceResourceID,csi.ReferenceResourceID) && ...
                isequal(string(exported.ReferenceEmissionSHA256),csi.ReferenceEmissionSHA256));
        else
            assert(all(isnan(csi.ReferenceResourceID)) && all(strlength(csi.ReferenceEmissionSHA256)==0));
        end
        % Replay ownership using an actual scheduler-issued DL grant, not
        % a synthetic HARQ row. Completing its exact source digest releases
        % the old-cell obligation; merely reaching/passing K1 does not.
        actual=provider.LastContext; issued=actual.Grant;
        ownershipCfg=cfg; ownershipCfg.phy.csi.reportCSI=false;
        ownership=sixgr.system.SLSDynamicPUCCH(ownershipCfg);
        ownership.configureUEIdentities(params.RNTIByUE);
        serving=double(r.Details.ServingCell(end,:)); moved=serving;
        moved(issued.UEIndex)=max(serving)+1;
        ownership.appendDL(issued,actual.ServingCellID,issued.ControlAbsoluteSlot);
        due=issued.HARQFeedbackAbsoluteSlot;
        rejectUCI(@()ownership.configureServingCells(moved,due+1), ...
            'sixgr:system:UCIHandoverOutstanding');
        % Replay the actual retained calibrated-PHY decision, not an ACK
        % invented from reservation completion or successful file delivery.
        decisions=r.Details.ModeledHARQPayloadDecisions;
        decision=decisions(decisions.RNTI==issued.RNTI & ...
            decisions.CellID==actual.ServingCellID & ...
            decisions.TransmissionAbsoluteSlot0==issued.ScheduledAbsoluteSlot,:);
        assert(height(decision)==1 && string(actual.TransportBlockIdentity)==decision.TransportBlockIdentity);
        replay=struct('Ok',decision.ACK,'TransportBlockIdentity',decision.TransportBlockIdentity, ...
            'TransmissionAbsoluteSlot0',decision.TransmissionAbsoluteSlot0, ...
            'ReceiveCompletionAbsoluteSlot0',decision.ReceiveCompletionAbsoluteSlot0, ...
            'SourceClassification',decision.SourceClassification, ...
            'CalibrationQualified',decision.CalibrationQualified, ...
            'CalibrationSHA256',decision.CalibrationSHA256, ...
            'CalibrationCurveID',decision.CalibrationCurveID, ...
            'CalibrationKeySHA256',decision.CalibrationKeySHA256, ...
            'WaveformReplayExecuted',decision.WaveformBacked,'PHYDecisionStatus',"OK");
        ownership.recordHARQDecision(actual,replay);
        ownership.completeSlot(due,serving,struct([]),{},struct([]));
        f=struct('RNTI',issued.RNTI,'SourceSlot',issued.ScheduledAbsoluteSlot,'Ack',decision.ACK);
        ownership.requireHARQCompletion(f,actual.ServingCellID,due);
        ownership.configureServingCells(moved,due+1);
        fprintf('SLS_DL_HARQ_OWNERSHIP_RELEASE_PASS exact_issued_grant_digest=1\n');
    end
    network=r.Details.NetworkSpatialEvidence;
    assert(height(network)==height(G) && all(~network.WaveformBacked) && ...
        all(~network.ArrayQualified) && all(~network.RFQualified));
    persisted=readtable(fullfile(context.RunFolder,'csv','system_network_spatial_evidence.csv'));
    assert(height(persisted)==height(network),'Persist every executed modeled network observation.');
    snapshot=jsondecode(fileread(fullfile(context.RunFolder,'live','sls_evidence.json')));
    assert(snapshot.CommittedThroughAbsoluteSlot0==nTTI-1 && ...
        ~snapshot.PrimaryStudyAccepted && ~snapshot.WaveformBacked && ...
        snapshot.Evidence.NetworkSpatial.TotalRows==height(network) && ...
        snapshot.Evidence.NetworkSpatial.RetainedRows==min(100,height(network)), ...
        'Progress snapshots must bind the committed clock and retain bounded actual rows.');
    for binding={"UCIObligations","DynamicPUCCHObligations"; ...
            "UCICompletions","DynamicUCICompletions"; "HARQDecisions","ModeledHARQPayloadDecisions"; ...
            "PUCCHEmissions","NativePUCCHEmissionAudit"}.'
        entry=snapshot.Evidence.(binding{1}); actualRows=r.Details.(binding{2});
        assert(entry.TotalRows==height(actualRows) && entry.RetainedRows==min(100,height(actualRows)), ...
            'Live UCI reservations, completions and modeled decisions must retain separate actual populations.');
    end
    if logical(sixgr.util.structGet(cfg,'system.linkAbstraction.networkSpatial.pucchInterferenceEnabled',false))
        audit=r.Details.NativePUCCHEmissionAudit;
        assert(~isempty(audit) && any(audit.NativeWaveformExecuted) && ...
            all(~audit.PhysicalReceptionQualified) && ...
            all(audit.SourceClassification=="modeled_SLS_ideal_delayed_control"));
        due=r.Details.DynamicPUCCHObligations;
        assert(height(audit)==height(due) && ...
            isequal(sort(audit.ObligationID),sort(due.ObligationID)), ...
            'Every in-window obligation must have a retained native/negative-SR/replacement disposition.');
        native=audit(audit.NativeWaveformExecuted,:);
        assert(all(strlength(native.EmissionSHA256)==64) && ...
            any(native.HARQBits>0 & native.CSIPart1Bits>0 & native.SRBits>0), ...
            'Exercise real combined HARQ/CSI/SR transmission, not just an enabled flag.');
        saved=readtable(fullfile(context.RunFolder,'csv','system_native_pucch_emission_audit.csv'), ...
            'TextType','string');
        assert(height(saved)==height(audit) && isequal(saved.EmissionSHA256(audit.NativeWaveformExecuted),native.EmissionSHA256));
    end
    for name=["SRSInterferenceIncluded","SRSEmissionCount","CSIRSInterferenceIncluded", ...
            "CSIRSEmissionCount","ReferenceSignalInterferenceQualified"]
        assert(ismember(name,string(persisted.Properties.VariableNames)) && ...
            isequal(double(persisted.(name)),double(network.(name))), ...
            'Native reference-emission coverage must survive the primary CSV round trip: %s.',name);
    end
    if expectedUEs>1
        serving=double(r.Details.ServingCell(end,:));
        assert(numel(unique(serving))==expectedUEs, ...
            'The multicell fixture must attach one UE to each distinct configured cell.');
        assert(numel(unique(network.RNTI))==expectedUEs && ...
            numel(unique(network.ServingCell))==expectedUEs && ...
            all(network.RNTI==params.RNTIByUE(network.UEIndex)) && ...
            all(network.ServingCell==reshape(serving(network.UEIndex),[],1)), ...
            'Every UE must execute grants with its own serving-cell identity.');
        for u=1:expectedUEs
            assert(any(network.UEIndex==u & network.MaxActiveInterferersPerRE>0), ...
                'Each cell must execute an overlapping interfering shared-data allocation.');
        end
        assert(all(network.MaxActiveInterferersPerRE<=expectedUEs-1), ...
            'One grant per UE: the desired transmitter must never be counted as its own interferer.');
        ctx=provider.LastContext;
        % The final data grant can precede the final idle slot. Capture its
        % real population at evaluation, not from expired bounded history.
        active=provider.LastEvaluatedState;
        baseline=provider.evaluate(ctx,active);
        for shape=["row","column"]
            changed=active;
            gs="Grants"+direction; cs="GrantCells"+direction;
            if shape=="row"
                changed.(gs)=reshape(active.(gs),1,[]);
                changed.(cs)=reshape(active.(cs),[],1);
            else
                changed.(gs)=reshape(flip(active.(gs)),[],1);
                changed.(cs)=reshape(flip(active.(cs)),1,[]);
            end
            equivalent=provider.evaluate(ctx,changed);
            assert(isequaln(equivalent.Channel,baseline.Channel) && ...
                isequaln(equivalent.ExternalCovariance,baseline.ExternalCovariance) && ...
                isequaln(equivalent.ActiveInterferersPerRE,baseline.ActiveInterferersPerRE), ...
                'Grant/cell vector orientation and order must not change physical interference.');
        end
        if direction=="UL"
            duplicate=active;
            duplicate.GrantsUL=repmat(ctx.Grant,2,1);
            duplicate.GrantCellsUL=[ctx.ServingCellID; mod(ctx.ServingCellID,expectedUEs)+1];
            rejectUCI(@()provider.evaluate(ctx,duplicate), ...
                'sixgr:abstraction:DuplicateULTransmitter');
        end
        if direction=="DL" || automatic
            csi=r.Details.ModeledDLCSI;
            assert(numel(unique(csi.UEIndex))==expectedUEs && ...
                all(csi.ServingCell==reshape(serving(csi.UEIndex),[],1)));
        end
        if direction=="UL"
            srs=r.Details.ModeledSpatialFeedback;
            assert(numel(unique(srs.UEIndex))==expectedUEs && ...
                all(srs.ServingCell==reshape(serving(srs.UEIndex),[],1)));
        end
        fprintf('SLS_MULTICELL_FEEDBACK_PASS direction=%s cells=%d actual_interferers=1 calibration_fixture_only=1\n', ...
            direction,numel(unique(serving)));
    end
end
assert(isnan(r.KPITable.("MeanModeledEffectiveSINR_"+other+"_dB"))); % no invented unscheduled samples
assert(sum(F.DeliveredBits)==sum(G.UniqueDeliveredApplicationBits,'omitnan'));
assert(all(F.DeliveredBits+F.DroppedBits+F.RemainingBits==F.OfferedBits));
assert(sum(F.RemainingBits)==sum(r.Details.RemainingQueueBits));
if nonoverlap
    obligations=r.Details.DynamicPUCCHObligations;
    completions=r.Details.DynamicUCICompletions;
    assert(~isempty(obligations) && all(obligations.Transport=="PUCCH"));
    assert(all(ismember(obligations.ObligationID,completions.ObligationID)) && ...
        ~any(completions.WaveformBacked) && ~any(completions.PhysicalDecodeQualified));
    assert(any(ismember(G.ScheduledAbsoluteSlot,obligations.AbsoluteSlot0)), ...
        'The runner must execute PUSCH and PUCCH in the same slot, not defer one until another slot.');
    assert(all(G.SymbolStart==0 & G.NumSymbols==12));
    for k=1:height(obligations)
        resources=cfg.validation.pucch_resources.resources;
        resource=resources([resources.id]==obligations.PUCCHResourceID(k));
        assert(isscalar(resource) && resource.starting_symbol>=12, ...
            'Dedicated control must retain its disjoint configured symbols.');
    end
    fprintf('SYSTEM_NONOVERLAPPING_UCI_PASS actual_scheduled_grants=%d same_slot_dedicated_control=1 physical_qualification=0\n',height(G));
end
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
    serving=double(r.Details.ServingCell(end,:)); cellID=actual.ServingCellID;
    ue=struct('UEID',g.UEIndex,'RNTI',g.RNTI,'ServingCell',cellID,'PUCCHCell',cellID, ...
        'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
        'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
    ledger=sixgr.system.SLSDynamicPUCCH(cfg);
    ledger.configureUEIdentities(params.RNTIByUE);
    ledger.configureServingCells(serving,g.ControlAbsoluteSlot);
    calendar=sixgr.truth.buildPeriodicCSIReportObligations(ledger.configForUE(ue),ue,target+1,target+1);
    refs=struct('UEIndex',g.UEIndex,'ServingCell',cellID,'ReportAbsoluteSlot0',target, ...
        'SourceAbsoluteSlot0',calendar.CSIReferenceSlot(1)-1, ...
        'ReferenceAvailableAtSlot0',calendar.CSIReferenceSlot(1)-1);
    g=ledger.bindPUSCH(g,cellID,g.ControlAbsoluteSlot,serving,refs);
    assert(~ledger.reportCompleted(g.UEIndex,cellID,target));
    moved=serving; moved(g.UEIndex)=max(serving)+1;
    rejectUCI(@()ledger.configureServingCells(moved,g.ControlAbsoluteSlot), ...
        'sixgr:system:UCIHandoverOutstanding');
    rejectUCI(@()ledger.configureServingCells(moved,target+1), ...
        'sixgr:system:UCIHandoverOutstanding');
    rejectUCI(@()ledger.snapshot(target,target,serving,struct([])),'sixgr:system:SLSUCILateObligation');
    rejectUCI(@()ledger.completeSlot(target,serving,refs,{g},struct([])),'sixgr:system:SLSUCINotExecuted');
    changed=g; changed.PRBSet=g.PRBSet+1;
    rejectUCI(@()ledger.completeSlot(target,serving,refs,{changed},changed),'sixgr:system:PUSCHUCIReservationBinding');
    ledger.completeSlot(target,serving,refs,{g},g);
    assert(ledger.reportCompleted(g.UEIndex,cellID,target));
    rejectUCI(@()ledger.completeSlot(target,serving,refs,{g},g),'sixgr:system:SLSUCIDuplicateCompletion');
    ledger.configureServingCells(moved,target+1);
    fprintf('SLS_PUSCH_UCI_OWNERSHIP_RELEASE_PASS actual_execution_required=1\n');
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
    before=probe.advanceULSpatialFeedback(u,state,3);
    assert(~before.ModeledSRSCausalUsable && isempty(probe.FeedbackCaptureTrace), ...
        'Selecting scheduler feedback must not produce an uncommitted observation.');
    rejectUCI(@()probe.captureCommittedSpatialFeedback(),'sixgr:abstraction:FeedbackCaptureClock');
    committed=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',1, ...
        'GrantsDL',struct([]),'GrantsUL',struct([]), ...
        'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',struct());
    probe.setSlotContext(committed);
    probe.captureCommittedSpatialFeedback();
    rejectUCI(@()probe.captureCommittedSpatialFeedback(),'sixgr:abstraction:FeedbackCaptureClock');
    before=probe.advanceULSpatialFeedback(u,state,3);
    assert(~before.ModeledSRSCausalUsable,'Capture must not bypass the configured delivery delay.');
    state.AbsoluteSlot0=2;
    v=probe.advanceULSpatialFeedback(u,state,3);
    assert(v.ModeledSRSCausalUsable && ~v.CausalFeedbackUsable && v.CQI==0 && ...
        strcmp(v.CausalFeedbackStatus,'stale_cqi_test') && v.FeedbackAgeSlots==99, ...
        'Modeled spatial feedback must never authorize stale CQI.');
    fprintf('SLS_FEEDBACK_CAPTURE_CLOCK_PASS no_preview=1 delayed_delivery=1 duplicate_rejected=1\n');
    end
    % Replay a late control obligation on an actually issued future UL
    % allocation. It must be invisible at scheduling, then block BEFORE
    % that grant reaches the abstract decoder. This is not a PHY trial.
    actual=provider.LastContext; g=actual.Grant;
    assert(g.ScheduledAbsoluteSlot>g.ControlAbsoluteSlot);
    lateParams=params;
    if spatialMode=="network"
        lateParams.SpatialGrantProvider=feval(cfg.system.linkAbstraction.spatialProviderClass,cfg);
    end
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
