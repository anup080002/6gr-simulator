function ok=testTypeICSIReceivedGrantProvenance()
% Authored decoded-report/clock boundaries and real MAC/codebook freezing.
% NOT physical CSI-RS/PUCCH/PDSCH, access, BLER or complete n40 qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
% Keep every YAML TDD/timing alias installed. The FDD-only scheduler fixture
% must not replace this scenario's D,D,D,S,U symbol-level frame authority.
assert(sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD");
installedFrame=cfg.phy.frameStructure;
% buildInternalConfig removes legacy phy.tddTiming; production timing reads
% this canonical snapshot through TimingRelationEngine.resolveProductionGrant.
installedTiming=cfg.phy.frameStructure.TimingContext;
% CoupledTruthRuntime.defaultSlotBudget maps one-based runtime Slot to an
% explicit zero-based ControlAbsoluteSlot. TimingRelationEngine must never
% infer that conversion from the scheduler's legacy Slot fallback.
controlSlots0=[30 35 40];
runtimeSlots=controlSlots0+1;
cfg.phy.linkAdaptation.rankIncreaseConfirmationReports=2;
cfg.mac.scheduler.maxUEPerSlot=1;
cfg.mac.scheduler.minPRBPerUE=12;
cfg.phy.linkAdaptation.cqiSmoothingMode='fixed';
cfg.phy.linkAdaptation.cqiSmoothingAlpha=1;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',701, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),5);
state.CurrentServingIdx(:)=1;
state.AccessState(:)="succeeded"; % Declared fixture, not received access proof.
state.BeamManagementRuntimeEnabled=false;
state.DLQueueBits(:)=8e6;
state.CurrentSlot=29;
report=localReport(cfg,28,29,1,4,3);
[state,accepted]=sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(state,report);
assert(~accepted.SchedulerSpatialDecisionDeferred);
first=state.LatestDLFeedback(1);
assert(first.CSIReportProvenance.ReportIdentity==report.ReportIdentity && ...
    first.PMI==4 && first.CRI==3 && isempty(fieldnames(first.ReceivedCSIReport)));
assert(~first.CSIReportProvenance.ReceiverObservationBound, ...
    'A declared report without an executed owner clock is not physical receipt qualification.');
for forbidden=["UEReferenceRecordJSON","CSIDeliveryAuditJSON","CSIMeasurementID", ...
        "SpatialSignatureToken","SINR_dB"]
    assert(~isfield(first.CSIReportProvenance,forbidden));
end
assert(first.CSIReportProvenance.PMI_I11==report.PMI_I11 && ...
    first.CSIReportProvenance.PMI_I2==report.PMI_I2 && ...
    first.CSIReportProvenance.CSIUCIDecodedBitsToken==report.CSIUCIDecodedBitsToken);
state.CurrentSlot=runtimeSlots(1);
[state,oldUE]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,'DL',1);
assert(isequaln(oldUE.CSIReportProvenance,first.CSIReportProvenance));
oldUE=localSchedulingFixture(oldUE);

% A held higher rank, duplicate and stale source cannot relabel the old
% executable spatial observation. Raw decoded rank remains available.
state.CurrentSlot=31;
held=localReport(cfg,30,31,2,0,1);
[state,deferred]=sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(state,held);
assert(deferred.RI==2 && deferred.SchedulerSpatialDecisionDeferred && ...
    isequaln(state.LatestDLFeedback(1),first));
state.CurrentSlot=32;
[state,duplicate]=sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(state,report);
assert(duplicate.SchedulerSpatialDecisionDeferred && ...
    isequaln(state.LatestDLFeedback(1),first));
state.CurrentSlot=33;
newReport=localReport(cfg,32,33,1,5,1);
[state,newAccepted]=sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(state,newReport);
assert(~newAccepted.SchedulerSpatialDecisionDeferred);
latest=state.LatestDLFeedback(1);
state.CurrentSlot=34;
stale=localReport(cfg,27,28,1,0,0);
[state,rejected]=sixgr.truth.CoupledTruthRuntime.publishReceivedCSIReportRuntime(state,stale);
assert(rejected.SchedulerSpatialDecisionDeferred && isequaln(state.LatestDLFeedback(1),latest));
state.CurrentSlot=runtimeSlots(2);
[state,newUE]=sixgr.truth.CoupledTruthRuntime.buildSchedulerUEStateRuntime(state,cfg,1,'DL',1); %#ok<ASGLU>
newUE=localSchedulingFixture(newUE);

budget=struct('NPRB',24,'SymbolAllocation',[2 12], ...
    'ControlSymbolAllocation',cfg.phy.pdcch.symbolAllocation);
for control0=controlSlots0
    partition=sixgr.util.resolveTDDSlotPartition(cfg,control0);
    assert(partition.SlotToken=='D' && isequal(partition.DLSymbolAllocation,[0 14]));
end
assert(isequaln(cfg.phy.frameStructure,installedFrame) && ...
    isequaln(cfg.phy.frameStructure.TimingContext,installedTiming));
for kind=["PF","RR"]
  for callerSlotOrigin=[0 1]
    % Production coupled scheduling passes zero-based Slot; older MAC
    % callers pass one-based Slot. The explicit control clock owns timing.
    callerSlots=controlSlots0+callerSlotOrigin;
    harq=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL','NumProcesses',4,'MaxRetx',3,'StoreTB',true);
    constructor=str2func("sixgr.l2.mac.Scheduler"+kind);
    scheduler=constructor(cfg,'Direction','DL','HARQ',harq);
    budget.ControlAbsoluteSlot=controlSlots0(1);
    [grants,~]=scheduler.schedule(callerSlots(1),oldUE,budget);
    assert(numel(grants)==1,'The dedicated grant fixture must produce one old-CSI grant.');
    g=grants(1);
    localTDDTiming(cfg,g,callerSlots(1),controlSlots0(1));
    localMatrix(cfg,g,report);
    assert(isequaln(g.PHYGrant.LegacyGrantSnapshot.CSIReportProvenance,g.CSIReportProvenance));
    assert(g.CSIReportApplication.ReportedCQI==report.CQI && ...
        g.CSIReportApplication.ScheduledMCS==g.MCSIndex && ...
        ~g.CSIReportApplication.WaveformApplicationVerified);
    original=g;
    laterScheduler=constructor(cfg,'Direction','DL');
    budget.ControlAbsoluteSlot=controlSlots0(2);
    [later,~]=laterScheduler.schedule(callerSlots(2),newUE,budget);
    assert(numel(later)==1);
    localTDDTiming(cfg,later(1),callerSlots(2),controlSlots0(2));
    localMatrix(cfg,later(1),newReport);
    assert(isequaln(g,original),'A later decision must not mutate an issued grant.');
    preserved=scheduler.attachULSRSAuthorityToGrant(g,newUE);
    assert(isequaln(preserved.CSIReportProvenance,g.CSIReportProvenance) && ...
        isequaln(preserved.PHYGrant,g.PHYGrant));
    % Declared MAC transmission/feedback boundary; no radio ACK claim.
    harq.onTx(g.RNTI,g.HARQ.HarqID,zeros(g.TBSBits,1,'uint8'),g,g.Slot);
    harq.onFeedback(g.RNTI,g.HARQ.HarqID,"NACK", ...
        'SourceSlot',g.Slot,'FeedbackSlot',g.HARQFeedbackAbsoluteSlot+1);
    budget.ControlAbsoluteSlot=controlSlots0(3);
    [replays,~]=scheduler.schedule(callerSlots(3),newUE,budget);
    replay=replays(arrayfun(@(x)sixgr.phy.grant.isExplicitHARQRetransmission(x),replays));
    assert(isscalar(replay),'Exercise the actual scheduler HARQ replay path.');
    localTDDTiming(cfg,replay,callerSlots(3),controlSlots0(3));
    assert(isequaln(replay.CSIReportProvenance,g.CSIReportProvenance) && ...
        string(replay.PHYGrant.PrecodingState.AppliedMatrixSHA256)== ...
        string(g.PHYGrant.PrecodingState.AppliedMatrixSHA256) && ...
        string(replay.PHYGrant.PrecodingState.SelectedMatrixSHA256)== ...
        string(g.PHYGrant.PrecodingState.SelectedMatrixSHA256), ...
        'HARQ must retain original CSI provenance and both frozen matrices.');
    metadataOnly=g;
    metadataOnly.CSIReportProvenance.ReportIdentity="metadata_only_counterfactual";
    metadataOnly.CSIReportApplication.ReportIdentity="metadata_only_counterfactual";
    before=scheduler.buildDCIBitfield(g);
    after=scheduler.buildDCIBitfield(metadataOnly);
    assert(isequal(before.Bits,after.Bits),'Provenance does not add or change DCI fields.');
  end
end
localClockGuards(cfg,report,oldUE);
fprintf('TYPE_I_RECEIVED_GRANT_PROVENANCE_PASS PF_RR=2 caller_origins=2 private_audit_isolated=1 frozen_HARQ=1 physical_qualification=0\n');
ok=true;
end

function localTDDTiming(cfg,grant,callerSlot,controlSlot0)
% Check the timing actually selected by MAC, not only a preflight probe.
timing=grant.TimingDecision;
assert(sixgr.phy.frame.resolveDuplexMode(cfg)=="TDD" && timing.Valid && ...
    grant.Slot==callerSlot && ismember(callerSlot-controlSlot0,[0 1]) && ...
    grant.ControlAbsoluteSlot==controlSlot0 && ...
    timing.ControlAbsoluteSlot==controlSlot0 && timing.K0==0 && ...
    timing.DataAbsoluteSlot==controlSlot0 && ...
    grant.ScheduledAbsoluteSlot==controlSlot0 && ...
    grant.HARQFeedbackAbsoluteSlot==timing.FeedbackAbsoluteSlot);
partition=sixgr.util.resolveTDDSlotPartition(cfg,double(timing.DataAbsoluteSlot));
occupied=grant.SymbolAllocation(1)+(0:grant.SymbolAllocation(2)-1);
assert(all(ismember(occupied,partition.DLSymbolIndices0Based)));
assert(grant.HARQFeedbackAbsoluteSlot>controlSlot0, ...
    'The declared HARQ feedback must follow the actual TDD data occasion.');
end

function ue=localSchedulingFixture(ue)
% This test isolates feedback→MAC, not access/QCL admission or buffer flow.
ue.Active=true; ue.SchedulingEligible=true; ue.ControlEligible=true;
ue.DLBufferBytes=1e6;
end

function report=localReport(cfg,source,due,rank,pmi,cri)
installedRequest=cfg.phy.csi.reportConfiguration;
request=installedRequest;
request.Rank=rank;
[~,tuple]=sixgr.phy.mimo.TypeISinglePanelCodebook.matrix(request,pmi);
values=tuple;
values.RI=rank; values.PMI=pmi; values.CRI=cri; values.CQI_CW0=10; values.LI=0;
% As in NRCSIReportEngine, only the TX layout takes the selected rank.
% The independent RX layout starts from installed configuration and must
% recover the rank-dependent schema from the received Part-1 prefix.
txCodec=sixgr.phy.mimo.CSIReportConfiguration(request, ...
    cfg.phy.csi.reportConfigurationEpoch);
rxCodec=sixgr.phy.mimo.CSIReportConfiguration(installedRequest, ...
    cfg.phy.csi.reportConfigurationEpoch);
encoded=txCodec.build(values);
[prefix,receivedCodec]=rxCodec.decodePart1(encoded.Part1Bits);
decoded=rxCodec.decode(encoded.Part1Bits,encoded.Part2Bits);
assert(rxCodec.Rank==installedRequest.Rank && prefix.RI==rank && ...
    receivedCodec.Rank==rank && decoded.RI==rank && ...
    decoded.PMI==pmi && decoded.CRI==cri && decoded.CQI_CW0==values.CQI_CW0 && ...
    decoded.UCIChannel=="PUCCH", ...
    'The installed receiver must derive the selected rank and fields from serialized bits.');
for component=["PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    assert(isequal(decoded.(component),tuple.(component)));
end
[modulation,rate,mcs]=sixgr.link.amcFromCQI(decoded.CQI_CW0,"",NaN,cfg,'DL');
report=struct('Direction',"DL",'UEIndex',1,'RNTI',701,'ServingCell',1, ...
    'SourceSlot',source,'DueSlot',due,'DeliveredSlot',due,'CSIReferenceSlot',source, ...
    'SourceSlotAuthority',"configured_CSI_reference_resource_not_UE_measurement_slot", ...
    'ReportIdentity',"declared_decoded_csi_"+source+"_"+due, ...
    'CSIReportConfigID',string(request.ReportConfigID), ...
    'CSIConfigurationEpoch',cfg.phy.csi.reportConfigurationEpoch, ...
    'SourceSignal',"received_CSI_UCI",'CSIUCIDecodeOk',true, ...
    'CSIUCIChannel',decoded.UCIChannel,'CSIUCITransport',"declared_decoded_report_boundary", ...
    'CSIUCIDecodedBitCount',numel(encoded.Part1Bits)+numel(encoded.Part2Bits), ...
    'CSIUCIDecodedBitsToken',string(sixgr.runtime.RawCSVArrayCodec.encode( ...
        [encoded.Part1Bits;encoded.Part2Bits])), ...
    'CQI',decoded.CQI_CW0,'RI',decoded.RI,'PMI',decoded.PMI,'CRI',decoded.CRI, ...
    'SINR_dB',NaN,'SINRSource',"not_reported_in_CSI_payload", ...
    'SINRValueRole',"unavailable_not_a_received_SINR_measurement", ...
    'SINRValueStatus',"NA_not_reported", ...
    'MCSIndex',mcs,'TargetCodeRate',rate,'Modulation',string(modulation), ...
    'ObservationID',"declared_capture_"+due,'ReceiverContextDigest',"declared_receiver_schema", ...
    'ReceiverClockDomain',"shared_receiver_sample_clock/v1",'ReceiverClockEpoch',7, ...
    'ObservationStartSample',100*due,'ObservationEndSampleExclusive',100*due+20, ...
    'ObservationSampleRateHz',1000,'AvailableAtSample',100*due+25, ...
    'UEReferenceRecordJSON',"poisoned_private_UE_truth", ...
    'CSIDeliveryAuditJSON',"poisoned_private_TX_serialization", ...
    'CSIMeasurementID',"not_reported_private_measurement");
for name=["LI","PMI_I11","PMI_I12","PMI_I13","PMI_I2"]
    report.(name)=double(sixgr.util.structGet(decoded,name,NaN));
end
end

function localMatrix(cfg,g,report)
assert(g.PMI==report.PMI && g.CRI==report.CRI && ...
    g.CSIReportProvenance.ReportIdentity==report.ReportIdentity && ...
    g.CSIReportProvenance.ObservationID==report.ObservationID);
prec=g.PHYGrant.PrecodingState;
[candidates,~]=sixgr.phy.dl.pmiCodebookCandidates(cfg,report.RI,4,'Mode','type1_su_mimo');
W=candidates([candidates.PMI]==report.PMI).W;
if string(prec.NormalizationConvention)=="unit_frobenius", W=W/norm(W,'fro'); end
B=cfg.phy.csirs.precoderMatrices(:,:,report.CRI+1);
assert(prec.CSIRSPortBasisApplied && prec.CSIResourceIndex==report.CRI && ...
    norm(prec.MatrixLogicalPorts-W,'fro')<1e-12 && ...
    norm(prec.MatrixPhysicalPorts-B*W,'fro')<1e-12);
assert(g.CSIReportApplication.SelectedMatrixSHA256==string(prec.SelectedMatrixSHA256) && ...
    g.CSIReportApplication.AppliedMatrixSHA256==string(prec.AppliedMatrixSHA256));
end

function localClockGuards(cfg,report,ue)
% Declared exact-clock operands exercise contracts, not actual RF execution.
clock=struct('ClockDomain',report.ReceiverClockDomain,'ClockEpoch',7, ...
    'SampleRateHz',1000,'AtSample',report.AvailableAtSample+1);
bound=sixgr.truth.captureReceivedCSIProvenance(report,clock);
assert(bound.ReceiverObservationBound && ~bound.ReferenceAttributionQualified);
poison=report; poison.UEReferenceRecordJSON="different_oracle"; poison.CSIDeliveryAuditJSON="different_TX";
assert(isequaln(bound,sixgr.truth.captureReceivedCSIProvenance(poison,clock)));
grant=struct('Direction',"DL",'Slot',30,'ControlAbsoluteSlot',29,'RNTI',701);
ue.CSIReportProvenance=bound; ue.CSIReportDecisionContext=clock;
g=sixgr.l2.mac.bindReceivedCSIProvenance(grant,ue,cfg);
assert(g.CSIReportProvenance.ReceiverObservationBound);
future=ue; future.CSIReportDecisionContext.AtSample=report.AvailableAtSample-1;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,future,cfg),'sixgr:truth:FutureCSIProvenance');
wrong=ue; wrong.CSIReportDecisionContext.ClockEpoch=8;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,wrong,cfg),'sixgr:truth:CSIProvenanceClockMismatch');
wrong=ue; wrong.CSIReportProvenance.RNTI=702;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,wrong,cfg),'sixgr:mac:CSIProvenanceIdentityMismatch');
wrong=ue; wrong.CSIReportProvenance.Direction="UL";
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,wrong,cfg),'sixgr:mac:CSIProvenanceIdentityMismatch');
wrong=ue; wrong.CSIReportProvenance.CSIConfigurationEpoch=bound.CSIConfigurationEpoch+1;
mustFail(@()sixgr.l2.mac.bindReceivedCSIProvenance(grant,wrong,cfg),'sixgr:mac:CSIProvenanceConfigurationMismatch');
historical=ue;
historical.CSIReportProvenance=sixgr.truth.captureReceivedCSIProvenance(report);
g=sixgr.l2.mac.bindReceivedCSIProvenance(grant,historical,cfg);
assert(~g.CSIReportProvenance.ReceiverObservationBound, ...
    'A later consumer clock must not qualify an unbound historical publication.');
missing=rmfield(report,{'AvailableAtSample','ObservationID'});
historical.CSIReportProvenance=sixgr.truth.captureReceivedCSIProvenance(missing);
g=sixgr.l2.mac.bindReceivedCSIProvenance(grant,historical,cfg);
assert(~g.CSIReportProvenance.ReceiverObservationBound && ...
    isnan(g.CSIReportProvenance.AvailableAtSample));
ul=grant; ul.Direction="UL";
assert(isequaln(sixgr.l2.mac.bindReceivedCSIProvenance(ul,ue,cfg),ul), ...
    'DL received-report provenance must not alter UL/SRS authority.');
assert(isempty(fieldnames(sixgr.l2.mac.csiReportGrantApplication(ul,struct()))));
end

function mustFail(f,id)
try, f(); catch e
    assert(strcmp(e.identifier,id),'Expected %s, got %s: %s',id,e.identifier,e.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end
