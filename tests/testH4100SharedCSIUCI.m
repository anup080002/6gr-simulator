function ok=testH4100SharedCSIUCI()
% Actual H4 CSI-RS -> PUCCH -> scheduler on one shared RF/CDL sample clock.
% Access/TAG are declared component boundary inputs; this is NOT a full
% access/data scenario, a statistical UCI qualification, or a BLER result.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
% Mirror the production runner's configured seed before any user/channel
% initialization. A preceding component test must not select this episode.
priorRNG=rng;
rngCleanup=onCleanup(@()rng(priorRNG)); %#ok<NASGU>
assert(logical(source.get('simulation.deterministic_mode')));
rng(double(source.get('simulation.random_seed')),'twister');
folder=fullfile(pwd,'results','lls','h4_shared_csi_uci', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(source,folder);
cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),40);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,200,40);
state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
assert(carrier.NSizeGrid==273 && carrier.SubcarrierSpacing==30 && ...
    fs==122.88e6 && cfg.phy.nTxAnt==64 && cfg.phy.nRxAnt==4);
% Explicit preconnected component context. Do not claim PBCH/PRACH/RRC
% execution or publish these inputs as received acquisition measurements.
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs, ...
    'DLPhaseOffsetSamples',0,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1", ...
    'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
state.ConnectedULTimingByUE={struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,30,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.1*fs))};
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=30;
state.AccessState(1)="succeeded";
state.BeamManagementMachines{1}=sixgr.phy.beam.BeamManagementStateMachine("TCI_PENDING");
state.PendingBeamCRIByUE(1)=0;
state.PendingTCIStateIDByUE(1)=16;
state.PendingTCICodepointByUE(1)=0;
state.PendingBeamSourceByUE(1)="declared_preconnected_SSB_boundary";
scope=struct('Scope',"shared_CSI_UCI_component_with_declared_access_TAG", ...
    'AccessExecuted',false,'DataReceiverQualified',false, ...
    'ScenarioAccepted',false,'SourceScenario',string(source.ConfigPath));
save(fullfile(folder,'configuration.mat'),'cfg','scope');
reportPeriod=double(cfg.phy.csi.reportPeriodicitySlots);
confirmationCount=double(cfg.phy.linkAdaptation.rankIncreaseConfirmationReports);
assert(reportPeriod==20 && confirmationCount==2, ...
    'This physical H4 integration must retain the installed two-report rank confirmation.');
lastSlot=reportPeriod*confirmationCount;
feedbackByReport=cell(confirmationCount,1);
adaptationByReport=cell(confirmationCount,1);
recorded=0;
for slot=1:lastSlot
    state=sixgr.truth.CoupledTruthRuntime.beginSlot( ...
        state,cfg,cfg,1,'DL',1,1,slot,200,40);
    state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
    if mod(slot-1,reportPeriod)==5
        [dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
        [state,queued]=sixgr.truth.queueSharedPeriodicCSIRS(state,dl,1,slot,1,1,1,40);
        assert(queued,'H4 must transmit its configured offset-5 CSI-RS.');
    end
    [state,~]=owner.advanceSlot(state,cfg,@complete);
    count=height(sixgr.util.structGet(state,'SharedGNBCSIReportTable',table()));
    if count>recorded
        assert(count==recorded+1 && count<=confirmationCount);
        feedbackByReport{count}=state.LatestDLFeedback;
        adaptationByReport{count}=state.DLLinkAdaptationState{1};
        recorded=count;
        % Preserve decoded evidence even if a later scheduler assertion fails.
        localPersist(folder,state,scope,feedbackByReport,adaptationByReport);
    end
    fprintf('H4_SHARED_CSI_UCI_SLOT=%d/%d measured=%d received_reports=%d\n', ...
        slot,lastSlot,height(state.ControlTrials.CSIRS), ...
        height(sixgr.util.structGet(state,'SharedGNBCSIReportTable',table())));
end
measured=state.ControlTrials.CSIRS;
received=state.SharedGNBCSIReportTable;
localPersist(folder,state,scope,feedbackByReport,adaptationByReport);
assert(height(measured)==2 && isequal(double(measured.Slot(:)),[6;26]) && ...
    all(measured.CSIMeasurementAvailable));
assert(height(received)==2 && isequal(double(received.DueSlot(:)),[19;39]) && ...
    all(received.CSIUCIDecodeOk) && all(received.CSIUCITransport=="pucch_independently_received"));
assert(all(received.RI==measured.RI & received.PMI==measured.PMI & ...
    received.CRI==measured.CRI & received.CQI==measured.CQI));
assert(all(isnan(received.SINR_dB) & received.SourceSignal=="received_CSI_UCI"), ...
    'Unreported UE-side SINR must not become a received UCI field.');
assert(received.RI(1)>cfg.phy.pdsch.numLayers && received.RI(2)==received.RI(1), ...
    'Retain the actual reports: this qualification requires two independently measured higher-RI observations.');
assert(received.SchedulerSpatialDecisionDeferred(1) && ...
    received.RankIncreaseConfirmationCount(1)==1 && ...
    ~feedbackByReport{1}.Valid && adaptationByReport{1}.SchedulerAcceptedRank==1, ...
    'One decoded higher RI must not bypass the configured confirmation policy.');
assert(~received.SchedulerSpatialDecisionDeferred(2) && ...
    received.RankIncreaseConfirmationCount(2)==confirmationCount, ...
    'Two causal physical reports must complete, not reset, the same rank candidate.');
assert(state.LatestDLFeedback.Valid && ...
    state.LatestDLFeedback.RI==received.RI(end) && ...
    state.LatestDLFeedback.PMI==received.PMI(end) && ...
    state.LatestDLFeedback.CRI==received.CRI(end));
assert(state.PendingBeamCRIByUE(1)==received.CRI(end) && ...
    state.PendingTCICodepointByUE(1)==received.CRI(end) && ...
    state.PendingTCIStateIDByUE(1)==16+received.CRI(end));
assert(isnan(state.ActiveTCIStateIDByUE(1)), ...
    'CSI reception alone must not activate a TCI state without received DCI.');
assert(numel(owner.CSIRSTransmissions)==2 && ...
    all(received.AvailableAtSample>=measured.ResultAvailableAtSample));
fprintf('H4_SHARED_CSI_UCI_PASS RI=%g PMI=%g CRI=%g CQI=%g folder=%s\n', ...
    received.RI(end),received.PMI(end),received.CRI(end),received.CQI(end),folder);
ok=true;
end

function localPersist(folder,state,scope,feedbackByReport,adaptationByReport)
measured=state.ControlTrials.CSIRS;
received=state.SharedGNBCSIReportTable;
pucch=state.ControlTrials.PUCCH;
sixgr.util.csvWriteTable(fullfile(folder,'csirs_trials.csv'),measured,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'received_csi_reports.csv'),received,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'pucch_trials.csv'),pucch,'PreserveSchema',true);
feedback=state.LatestDLFeedback;
beamTrace=state.BeamManagementStateTraceTable;
save(fullfile(folder,'received_evidence.mat'),'measured','received','pucch', ...
    'feedback','beamTrace','scope','feedbackByReport','adaptationByReport');
end

function state=complete(state,items)
for item=reshape(items,1,[])
    switch string(item.Kind)
        case "CSIRS"
            [state,~,~,~]=sixgr.truth.completeSharedCSIRSReception(state,item);
        case "PreparePUCCH"
            state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        case "PUCCHTX"
            state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
        case "PUCCH"
            state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
        case "PUCCHReceiveOnly"
            state=sixgr.truth.CoupledTruthRuntime.completeConfiguredPUCCHCSI(state,item);
        otherwise
            error('test:UnexpectedH4CSIEvent','Unexpected event %s.',item.Kind);
    end
end
end
