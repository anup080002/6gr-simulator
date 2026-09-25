function ok=testTypeIIRuntimeCSIReportBinding()
% Actual measured CSI-RS report through the runtime publication/queue adapter.
% The called component also verifies physical PUSCH report decoding. This
% test does not claim shared access, periodic scheduling, or future DL grant
% execution; those must be verified separately in an integrated scenario.
[passed,measured,request,received,~,~,rx]=testNRCSIReportEngineTypeII();
assert(passed && isnan(measured.PMI) && isstruct(measured.PMIComponents));
% These fields came from the actual PUSCH decoder, not the UE's report
% reference. JSON must retain both matrix components and exact orientation.
audit=jsondecode(sixgr.phy.mimo.encodeCSIReportAudit(received));
restored=sixgr.phy.mimo.MatrixContract.deserialize(string(audit.PrecoderMatrixToken), ...
    'ExpectedDigest',string(audit.PrecoderMatrixSHA256));
assert(isequal(restored,received.Precoder_W) && ~isfield(audit,'Precoder_W') && ...
    audit.RI==received.RI && audit.CQI_CW0==received.CQI_CW0);
assert(sixgr.phy.mimo.encodeCSIReportAudit(struct('RI',1,'PMI',2))== ...
    string(jsonencode(struct('RI',1,'PMI',2))),'Scalar Type-I audit output must remain unchanged.');
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
logRoot=fullfile(pwd,'logs','typeii_runtime_binding');
if ~isfolder(logRoot), mkdir(logRoot); end
root=tempname(logRoot); mkdir(root);
fprintf('TYPEII_RUNTIME_BINDING_ARTIFACT_ROOT=%s\n',root);
cfg=sixgr.lls6g.buildInternalConfig(scenario,root);
cfg.phy.csi.reportConfiguration=request;
cfg.phy.csi.reportConfigurationEpoch=request.Epoch;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
    'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),58);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
% The component measured slot zero. The runtime's row index is one-based.
% Flags below describe the CSI-RS extraction/estimation actually performed
% by testNRCSIReportEngineTypeII, not a configured CQI or a data-TB CRC.
row=table(1,1,1,measured.CQI,measured.RI,measured.PMI,measured.LI,measured.CRI, ...
    'VariableNames',{'Slot','UEIndex','ServingCell','CQI','RI','PMI','LI','CRI'});
row.WidebandCQI=measured.CQI;
row.CSIReportConfigID=measured.CSIReportConfiguration.ReportConfigID;
row.CSIConfigurationEpoch=measured.CSIReportConfiguration.Epoch;
row.CSIUCIChannel=measured.CSIReportConfiguration.UCIChannel;
row.CSIPart1BitsToken=string(sixgr.runtime.RawCSVArrayCodec.encode(measured.CSIPart1Bits));
row.CSIPart2BitsToken=string(sixgr.runtime.RawCSVArrayCodec.encode(measured.CSIPart2Bits));
record=table2struct(row);
bound=sixgr.phy.mimo.bindMeasuredCSIWireReport(measured.CSIReportConfiguration,record);
assert(isequal(bound.Part1Bits,measured.CSIPart1Bits) && ...
    isequal(bound.Part2Bits,measured.CSIPart2Bits));
bad=record; bad.CSIConfigurationEpoch=bad.CSIConfigurationEpoch+1;
localReject(@()sixgr.phy.mimo.bindMeasuredCSIWireReport(measured.CSIReportConfiguration,bad), ...
    'sixgr:mimo:MeasuredCSIConfigurationMismatch');
bad=record; bad.CQI=mod(bad.CQI+1,16);
localReject(@()sixgr.phy.mimo.bindMeasuredCSIWireReport(measured.CSIReportConfiguration,bad), ...
    'sixgr:mimo:MeasuredCSIFieldMismatch');
bad=rmfield(record,'CSIPart2BitsToken');
localReject(@()sixgr.phy.mimo.bindMeasuredCSIWireReport(measured.CSIReportConfiguration,bad), ...
    'sixgr:mimo:MissingMeasuredCSIWireReport');
bad=record; bad.PMI=0;
localReject(@()sixgr.phy.mimo.bindMeasuredCSIWireReport(measured.CSIReportConfiguration,bad), ...
    'sixgr:mimo:MeasuredCSIFieldMismatch');
bad=record; fractional=double(measured.CSIPart1Bits); fractional(1)=0.5;
bad.CSIPart1BitsToken=string(sixgr.runtime.RawCSVArrayCodec.encode(fractional));
localReject(@()sixgr.phy.mimo.bindMeasuredCSIWireReport(measured.CSIReportConfiguration,bad), ...
    'sixgr:mimo:CSIDeserializationMismatch');
row.MeasurementSource="measured_noisy_csirs_ofdm_component";
row.CQISource="measured_typeII_csirs_report_engine";
row.MeasurementClockDomain="slot_only";
for field=["Transmitted","Observed","Consumed","ResourceExtractionAvailable", ...
        "ChannelEstimateAvailable","CSIMeasurementAvailable"]
    row.(field)=true;
end
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime( ...
    state,1,'DL',row,cfg,row);
assert(height(state.PendingCSITable)==1);
queued=state.PendingCSITable(1,:);
part1=int8(sixgr.runtime.RawCSVArrayCodec.decode(queued.CSIPart1BitsToken));
part2=int8(sixgr.runtime.RawCSVArrayCodec.decode(queued.CSIPart2BitsToken));
assert(isequal(part1(:),measured.CSIPart1Bits(:)) && ...
    isequal(part2(:),measured.CSIPart2Bits(:)), ...
    'Runtime queue must preserve the measured Type-II codebook report exactly.');
installed=request; installed.Rank=3-measured.RI;
receiver=sixgr.phy.mimo.CSIReportConfiguration(installed,request.Epoch);
decoded=receiver.decode(part1,part2);
assert(decoded.RI==measured.RI && decoded.CQI_CW0==measured.CQI && ...
    isequal(decoded.PMIComponents,measured.PMIComponents) && ...
    isequal(decoded.Precoder_W,measured.Precoder_W));
assert(isnan(queued.PMI),'Type-II must not acquire a fabricated scalar PMI.');
% Feed actual PHY-decoded CSI to the publication adapter. Only the ledger
% binding below is declared by this component (not physical DCI evidence).
due=double(queued.DueSlot);
state.CurrentSlot=due; state.CurrentCanonicalSlot=due;
state.PendingCSITable.CSIUCITransport=cellstr("pusch_bound");
state.PendingCSITable.CSIUCIMultiplexedOnPUSCH(1)=true;
state.PendingCSITable.CSIUCIPUSCHGrantContextId=cellstr("typeII_publication_component");
% Poison UE reference bits without touching independently decoded samples.
poison=1-int8(measured.CSIPart2Bits);
state.PendingCSITable.CSIPart2BitsToken=cellstr(string(sixgr.runtime.RawCSVArrayCodec.encode(poison)));
grant=struct('Direction',"UL",'RNTI',1,'UEIndex',1,'Slot',due, ...
    'GrantContextId',"typeII_publication_component",'UCIOnPUSCHCSIReportIdentity',string(queued.ReportIdentity));
out=struct('GrantSnapshot',grant,'ExpectedHARQACKBits',int8([]), ...
    'ExpectedCSIPart1Bits',measured.CSIPart1Bits,'ExpectedCSIPart2Bits',poison, ...
    'DecodedCSIPart1Bits',rx.DecodedCSIPart1Bits,'DecodedCSIPart2Bits',rx.DecodedCSIPart2Bits, ...
    'UCIReceiverEvidence',rx.UCIReceiverEvidence);
state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,out);
assert(cfg.phy.linkAdaptation.rankIncreaseConfirmationReports==2 && received.RI==2);
assert(state.PendingCSITable.SchedulerSpatialDecisionDeferred(1) && ...
    state.PendingCSITable.SchedulerAcceptedRank(1)==1 && ~state.LatestDLFeedback(1).Valid, ...
    'One physically decoded higher-RI report must not bypass rank confirmation.');
firstObservation=rx.UCIReceiverEvidence;
% A second actual CSI-RS capture and PUSCH reception, not a second delivery
% of the first receiver result. Ledger timing/assignment bindings remain
% explicitly component inputs, not a claim of received DCI/shared access.
[secondPassed,measured,secondRequest,received,~,~,rx]= ...
    testNRCSIReportEngineTypeII(due,38214226);
assert(secondPassed && received.RI==2 && isequaln(secondRequest,request));
assert(~isequaln(firstObservation,rx.UCIReceiverEvidence), ...
    'Rank confirmation requires a distinct receiver observation.');
row.Slot=due+1;
row.CQI=measured.CQI; row.WidebandCQI=measured.CQI;
row.RI=measured.RI; row.PMI=measured.PMI; row.LI=measured.LI; row.CRI=measured.CRI;
row.CSIPart1BitsToken=string(sixgr.runtime.RawCSVArrayCodec.encode(measured.CSIPart1Bits));
row.CSIPart2BitsToken=string(sixgr.runtime.RawCSVArrayCodec.encode(measured.CSIPart2Bits));
state.CurrentSlot=double(row.Slot); state.CurrentCanonicalSlot=double(row.Slot);
state=sixgr.truth.CoupledTruthRuntime.applyCSIRSTrial(state,1,row);
state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',row,cfg,row);
assert(height(state.PendingCSITable)==2);
secondQueued=state.PendingCSITable(2,:);
assert(string(secondQueued.ReportIdentity)~=string(queued.ReportIdentity));
due=double(secondQueued.DueSlot);
state.CurrentSlot=due; state.CurrentCanonicalSlot=due;
state.PendingCSITable.CSIUCITransport(2)=cellstr("pusch_bound");
state.PendingCSITable.CSIUCIMultiplexedOnPUSCH(2)=true;
state.PendingCSITable.CSIUCIPUSCHGrantContextId(2)=cellstr("typeII_publication_component_second");
poison=1-int8(measured.CSIPart2Bits);
state.PendingCSITable.CSIPart2BitsToken(2)=cellstr(string(sixgr.runtime.RawCSVArrayCodec.encode(poison)));
grant.Slot=due; grant.GrantContextId="typeII_publication_component_second";
grant.UCIOnPUSCHCSIReportIdentity=string(secondQueued.ReportIdentity);
out.GrantSnapshot=grant;
out.ExpectedCSIPart1Bits=measured.CSIPart1Bits; out.ExpectedCSIPart2Bits=poison;
out.DecodedCSIPart1Bits=rx.DecodedCSIPart1Bits; out.DecodedCSIPart2Bits=rx.DecodedCSIPart2Bits;
out.UCIReceiverEvidence=rx.UCIReceiverEvidence;
state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,out);
assert(~state.PendingCSITable.SchedulerSpatialDecisionDeferred(2) && ...
    state.PendingCSITable.SchedulerAcceptedRank(2)==2, ...
    'Two independent compatible reports must release the accepted rank.');
feedback=state.LatestDLFeedback(1);
assert(feedback.Valid && feedback.RI==received.RI && isnan(feedback.PMI));
published=feedback.ReceivedCSIReport;
assert(isequal(int8(sixgr.runtime.RawCSVArrayCodec.decode(published.CSIPart1BitsToken)),rx.DecodedCSIPart1Bits) && ...
    isequal(int8(sixgr.runtime.RawCSVArrayCodec.decode(published.CSIPart2BitsToken)),rx.DecodedCSIPart2Bits), ...
    'Publication must retain received Type-II bits, never poisoned transmitter reference bits.');
cfg.phy.linkAdaptation.queueAwareRankMCSReductionEnable=true;
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction',"DL");
ue=struct('RNTI',1,'CQI',feedback.CQI,'RI',received.RI, ...
    'DLBufferBytes',512,'ReceivedCSIReport',published);
for queueBytes=[1 512]
    plan=scheduler.buildNewDataGrantPlan(ue,0:24,[2 12],queueBytes);
    fprintf('TYPEII_QUEUE_PLAN bytes=%g valid=%d rank=%g expectedRI=%g layerSteps=%g blocker=%s feedback=%s rawTBS=%g\n', ...
        queueBytes,plan.Valid,plan.NumLayers,received.RI,plan.LayerReductionSteps, ...
        string(plan.GrantBlocker),string(plan.CausalFeedbackStatus),plan.RawEstimatedTBSBits);
    assert(plan.Valid && plan.NumLayers==received.RI && plan.LayerReductionSteps==0, ...
        'Queue reduction may change MCS/PRBs, not truncate a received Type-II rank-bound precoder.');
    expectedTBS=nrTBS(plan.Modulation,plan.NumLayers,numel(plan.PRBSet), ...
        plan.NREPerPRB,plan.TargetCodeRate,plan.XOverhead);
    assert(plan.TBSBits==expectedTBS && ...
        plan.QueuePaddingBits==max(0,expectedTBS-8*queueBytes), ...
        'A short queue must use a legal allocation-derived TB with explicit padding.');
end
future=struct('Slot',due+1,'RNTI',1,'MCSIndex',0,'MCS',0, ...
    'PRBSet',0:24,'SymbolAllocation',[2 12]);
future=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime(future,feedback,[],cfg,'DL');
assert(isequaln(future.ReceivedCSIReport,published) && future.NumLayers==received.RI);
issued=future; issued.ExactPHYFeasibilityChecked=true;
newFeedback=feedback; newFeedback.ReceivedCSIReport.ReportIdentity="later_report";
retained=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime(issued,newFeedback,[],cfg,'DL');
assert(isequaln(retained.ReceivedCSIReport,published),'Already issued grants must retain their original received CSI.');
disp('TYPEII_RECEIVED_CSI_PUBLICATION_TO_FUTURE_GRANT_PASS');
disp('TYPEII_RUNTIME_CSI_REPORT_BINDING_PASS');
ok=true;
end

function localReject(action,id)
try, action(); catch ex
    assert(string(ex.identifier)==id,'Expected %s, got %s: %s',id,ex.identifier,ex.message);
    return;
end
error('test:ExpectedFailure','Invalid measured CSI was accepted.');
end
