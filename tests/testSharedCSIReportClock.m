function ok=testSharedCSIReportClock(mode,withHARQ,staleScalarMetadata)
% Actual PUCCH IQ/CDL/RF/thermal noise, followed by decoded CSI delivery.
% Input CSI and DL clock/TAG are declared component inputs. Optional HARQ
% comes from an actual isolated PDSCH connector, not this shared CDL owner;
% this fixture does not qualify simulated access or measured CSI generation.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
if nargin<2, withHARQ=false; end
if nargin<3, staleScalarMetadata=false; end
file='lls_pdcch_shared_queue_fixture.yaml';
if string(mode)=="FDD", file='lls_trs_shared_scoring_fdd_fixture.yaml'; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,10,12);
state.CurrentServingIdx(:)=1;
state.TestStaleCSIScalarMetadata=logical(staleScalarMetadata);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
state.ConnectedULTimingByUE={struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.02*fs))};
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;
[~,fixtureLink]=sixgr.link.applyWaveformImpairments(complex(zeros(1,1)),ul,fs,'ApplyRFChain',false);
pl=double(fixtureLink.AppliedLargeScaleLoss_dB);
measurement=table(0,pl,"SSB-0","analytic_component_pathloss_selector_fixture",1,-pl,0, ...
    'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB','PathlossReferenceRS', ...
    'MeasuredReferenceSignalPathlossSource','ServingCell','SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
row=table(1,10,18.5,1,2,true,"receiver_post_equalization_sinr", ...
    "measured_post_equalization_scheduling_input","OK", ...
    'VariableNames',{'Slot','WidebandCQI','SINR_dB','RIEstimate','PMI','CRCPass', ...
    'SINRSource','SINRValueRole','SINRValueStatus'});
row.CRI=0; % Declared CSI component input for the configured single resource.
assert(cfg.phy.csi.reportConfiguration.NumCSIResources==1);
for badCRI={NaN,Inf,0.25,[0 0]}
    malformed=row; malformed.CRI=badCRI{1};
    localRejectCRI(@()sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
        state,1,'DL',malformed,cfg,table()));
end
state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',row,cfg,table());
expected=state.PendingCSITable(1,:); due=double(expected.DueSlot);
assert(expected.RI==row.RIEstimate,'The measured RI alias must survive the runtime producer adapter.');
missingRank=removevars(row,'RIEstimate'); rejected=false;
try
    sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',missingRank,cfg,table());
catch err
    if ~strcmp(err.identifier,'sixgr:truth:InvalidCSIReportRank'), rethrow(err); end
    rejected=true;
end
assert(rejected,'Missing received RI must not be serialized as invented rank one.');
assert(due>1 && due<10 && ~expected.RightCensored);
% Retain history and an unrelated future report around the active report.
% A one-row fixture concealed a row-mask/whole-column-overwrite API mismatch
% in prepareSharedPUCCHFeedbackRuntime. Neither sentinel may be rebound.
history=expected;
history.Processed=true;
history.SourceSlot=0;
history.DueSlot=0;
history.CSIUCITransport="pucch_decoded";
history.ReportIdentity=string(expected.ReportIdentity)+"|history_fixture";
future=expected;
future.SourceSlot=20;
future.DueSlot=24;
future.RightCensored=true;
future.CSIUCITransport="pucch";
future.ReportIdentity=string(expected.ReportIdentity)+"|future_fixture";
state.PendingCSITable=[history;expected;future];
state.TestCSIReportIndex=2;
state.TestCSIUnrelatedReports=state.PendingCSITable([1 3],:);
if withHARQ
    [dl,receiveFields]=receivedDLFeedbackFixture(cfg,3,0,1e-13);
    assert(dl.TrialTable.CRCPass==1);
    g=dl.HARQ.GrantSnapshot;
    a=state.DLHarq.allocate(1,3,g.TBSBytes,'NewData',true);
    assert(a.HARQ.HarqID==g.HARQ.HarqID && a.HARQ.NDI==g.HARQ.NDI);
    state.DLHarq.onTx(1,a.HARQ.HarqID,uint8(dl.HARQ.TransportBlockBits),g,3);
    f=struct('Direction',"DL",'FeedbackForDirection',"DL",'UEIndex',1,'RNTI',1, ...
        'HarqID',a.HARQ.HarqID,'SourceSlot',3,'DueSlot',due,'ScheduledAbsoluteSlot',due, ...
        'Ack',true,'CurrentDecodeOK',true,'CombinedDecodeOK',true,'ServingCell',1,'BaseStationID',1, ...
        'TBSBits',g.TBSBits,'UCIBitCount',1,'UCIType',"harq_ack",'RequestedFormat',0,'ResolvedFormat',0, ...
        'PUCCHResourceId',"0",'PUCCHPRBStart',0,'PUCCHPRBCount',1,'PUCCHSymbolStart',12, ...
        'PUCCHNumSymbols',2,'ComponentCarrier',0,'ActiveULBWP',0,'PUCCHGrantId',"csi_component_ack", ...
        'Processed',false,'MultiplexedOnPUSCH',false,'PUSCHGrantContextId',"",'RightCensored',false);
    for name=string(fieldnames(receiveFields)).', f.(name)=receiveFields.(name); end
    state.PendingFeedbackTable=struct2table(f);
    state=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,state.PendingFeedbackTable);
end
before=owner.Events.NextSampleIndex;
state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
assert(owner.Events.NextSampleIndex==before && numel(owner.Pending)==1);
assert(height(state.PUCCHGrantTraceTable)==1+double(withHARQ));
csiGrant=state.PUCCHGrantTraceTable(string(state.PUCCHGrantTraceTable.UCIType)=="csi_part1_part2",:);
assert(height(csiGrant)==1 && isnan(csiGrant.HarqID) && ~csiGrant.GrantExecutedFlag);
assert(isnan(csiGrant.PRIValue) && ...
    string(csiGrant.PRIProvenance)=="configured_csi_report_resource", ...
    'CSI-only reservation must not export a manufactured HARQ PRI.');
state.TestCSIExpected=expected; state.TestCSIWithHARQ=withHARQ;
for slot=1:due+1
    [state,~,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
        state,cfg,'DL',1,1,slot,10,12,repmat(struct(),0,1),true);
    assert(isempty(blocked));
    if slot<=due, assert(~state.PendingCSITable.Processed(state.TestCSIReportIndex)); end
    [state,~]=owner.advanceSlot(state,cfg,@localReceive);
end
report=state.PendingCSITable(state.TestCSIReportIndex,:);
assert(isequaln(state.PendingCSITable([1 3],:),state.TestCSIUnrelatedReports), ...
    'Shared PUCCH delivery must not alter unrelated CSI history or future reports.');
assert(report.Processed && report.CSIUCIDecodeOk && string(report.CSIUCITransport)=="pucch_decoded");
% Raw decoded CSI and policy-adjusted scheduler CQI have distinct authority.
assert(report.CQI==expected.CQI && report.RI==expected.RI && report.PMI==expected.PMI, ...
    'test:DecodedCSIFields','Received CQI/RI/PMI=[%g %g %g]; sent=[%g %g %g].', ...
    report.CQI,report.RI,report.PMI,expected.CQI,expected.RI,expected.PMI);
assert(report.CRI==row.CRI,'Actual CSI delivery must preserve its configured resource identity.');
assert(state.LatestDLFeedback.Valid && ...
    state.LatestDLFeedback.SchedulerCQIRawCQI==expected.CQI && ...
    state.LatestDLFeedback.CQI==report.SchedulerResolvedCQI);
assert(isequal(sixgr.runtime.RawCSVArrayCodec.decode(report.CSIUCIDecodedBitsToken), ...
    [sixgr.runtime.RawCSVArrayCodec.decode(expected.CSIPart1BitsToken); ...
     sixgr.runtime.RawCSVArrayCodec.decode(expected.CSIPart2BitsToken)]));
assert(height(state.ControlTrials.PUCCH)==1 && state.ControlTrials.PUCCH.PUCCHDecodeOk);
verifyPUCCHPowerExport(state.ControlTrials.PUCCH,cfg);
assert(state.ControlTrials.PUCCH.LogicalFeedbackCount==1+double(withHARQ));
assert(all(state.PUCCHGrantTraceTable.GrantExecutedFlag));
assert(state.DLHarq.Stats.Ack==double(withHARQ) && state.DLHarq.Stats.Nack==0);
assert(~owner.hasPending('PUCCH',1));
% The PUCCH above actually decoded CSI. Inject an explicitly analytic SRS
% delivery-boundary fixture afterward: opposite-direction quality/TPMI must
% not replace those received bits or refresh their measurement/delivery age.
state.CfgMobility=sixgr.util.structSet(state.CfgMobility, ...
    'lls6g.reference_signals.csi_acquisition_mode','joint_dl_ul');
srs=table("PASS",state.CurrentSlot,1,true,1,0, ...
    true,true,true,true,true,true,true,10,-20,-8, ...
    false,false,false,"", ...
    VariableNames=["Status","Slot","Frame","CRCPass", ...
    "RIEstimate","TPMIEstimate","DetectionAttempted", ...
    "DetectionSuccess","ResourceExtractionAttempted", ...
    "ResourceExtractionAvailable","ChannelEstimateAttempted", ...
    "SRSChannelEstimateAvailable","SRSRuntimeEvidenceUsable", ...
    "ReceiverHestSINR_dB","NMSE_dB","ChannelNMSEThreshold_dB", ...
    "ProxyUsed","Skipped","ToolboxMissing","UsedOracleFields"]);
dlBefore=state.LatestDLFeedback;
adaptationBefore=state.DLLinkAdaptationState;
for ulSINR=[-15 45]
    srs.ReceiverHestSINR_dB=ulSINR;
    state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,1,srs);
    assert(state.SRSValidityState(1)=="valid" && ...
        state.LastSuccessfulSRSSlotByUE(1)==srs.Slot && ...
        state.LatestULFeedback(1).RI==srs.RIEstimate && ...
        state.LatestULFeedback(1).PMI==srs.TPMIEstimate, ...
        'UL SRS RI/TPMI must still be consumed; rejecting SRS is not a source-authority fix.');
    % This boundary fixture deliberately does not contain a calibrated
    % per-layer PUSCH prediction. It must not invent an UL MCS either.
    assert(~state.LatestULFeedback(1).Valid && isnan(state.LatestULFeedback(1).MCSIndex));
    assert(isequaln(state.LatestDLFeedback,dlBefore) && ...
        isequaln(state.DLLinkAdaptationState,adaptationBefore), ...
        'UL SRS SINR/TPMI must not alter actually decoded DL CSI or its adaptation state.');
end
fprintf('SHARED_CSI_REPORT_CLOCK_PASS: %s HARQ=%d CSI bits=%g due=%g delivered=%g.\n', ...
    mode,withHARQ,report.CSIUCIDecodedBitCount,due,report.DeliveredSlot);
ok=true;
end

function localRejectCRI(action)
try
    action();
catch cause
    assert(strcmp(cause.identifier,'sixgr:mimo:InvalidCRI'), ...
        'Expected invalid CRI rejection, got %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingCRIRejection','A malformed CSI resource measurement must not be serialized.');
end

function state=localReceive(state,items)
for item=items
    if item.Kind=="PreparePUCCH"
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        assert(~state.PendingCSITable.Processed(state.TestCSIReportIndex) && isempty(state.ControlTrials.PUCCH));
        assert(state.PendingCSITable.CSIUCITransport(state.TestCSIReportIndex)=="pucch_bound");
        assert(isequaln(state.PendingCSITable([1 3],:),state.TestCSIUnrelatedReports), ...
            'PUCCH preparation must bind only its selected pending CSI report.');
        p=state.SharedWaveformStream.Pending;
        p=p(string({p.Kind})=="PUCCH");
        assert(isscalar(p) && ~p.Context.AwaitingPreparation);
        late=struct('Direction','UL','UEIndex',1,'RNTI',1,'GrantContextId','late-csi-copy', ...
            'Slot',state.TestCSIExpected.DueSlot,'ScheduledAbsoluteSlot',state.TestCSIExpected.DueSlot, ...
            'SymbolAllocation',[0 14]);
        rejected=false;
        try
            sixgr.truth.CoupledTruthRuntime.multiplexDueHARQACKOnPUSCHRuntime( ...
                state,late,state.TestCSIExpected.DueSlot);
        catch err
            if ~strcmp(err.identifier,'sixgr:truth:EncodedCSITransportRebinding'), rethrow(err); end
            rejected=true;
        end
        assert(rejected,'Already encoded PUCCH CSI must not be copied into late PUSCH.');
    elseif item.Kind=="PUCCH"
        assert(~state.PendingCSITable.Processed(state.TestCSIReportIndex));
        if state.TestStaleCSIScalarMetadata
            % Fault-inject only stale scalar annotations AFTER real IQ was
            % encoded and received. Keep its identity and coded bit payload
            % intact. The reducer must recover values from received UCI,
            % not use these transmitter-side scalar values as authority.
            item.Context.CSIReport.RI=2;
            item.Context.CSIReport.PMI=1;
            item.Context.CSIReport.CQI=0;
        end
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
        assert(string(state.PendingCSITable.CSIUCITransport(state.TestCSIReportIndex))=="pucch_decoded");
        assert(state.SharedLastPUCCHAvailableAtSample==state.SharedWaveformStream.Events.NextSampleIndex);
    else
        error('test:UnexpectedCSIEvent','Unexpected shared event %s.',item.Kind);
    end
end
end
