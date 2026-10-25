function ok=testPowerWithheldPUSCHDisposition()
% Declared completed-receiver metadata and real CSV, not a waveform test.
setup6GRSimToolkit('Verbose',false);
[g,r]=fixture(); a=struct2table(r,'AsArray',true); original={g,a};
for accepted=[false true]
    trial=a;trial.ReceiverCRCAvailable=true;trial.ReceiverCRCError=double(~accepted);
    trial.ReceiverUsable=accepted;
    out=sixgr.truth.classifyPUCCHGrantDisposition(g,table(),trial);
    assert(out.AllScheduledResolved&&out.PUSCHReceiverOnlyObservedCount==2&& ...
        out.TransferredCount==0&&out.StandaloneTrialCount==0&&out.StandaloneObservedCount==0&& ...
        out.ReceiverOnlyObservedCount==0&& ...
        all(out.Rows.Disposition=="power_deferred_UE_no_transmission_selected_PUSCH_receiver_observed"), ...
        'Actual receiver acceptance is not evidence of UE transmission.');
end
falseAccept=table("physical_noise_observation","g1|g2",true,true,true,true,true,false,false, ...
    'VariableNames',{'PUCCHGrantId','LogicalPUCCHGrantIdSet','DetectionAttempted','DetectionUsable', ...
    'ReceiverUsable','PUCCHDecodeOk','UCIContentMatch','CRCApplicable','CRCPass'});
for field=["UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"]
    falseAccept.(field)=1;
end
falseAccept.RunUUID="original_run";falseAccept.ConfigHash="original_config";
out=sixgr.truth.classifyPUCCHGrantDisposition(g,falseAccept,a);
assert(out.PUSCHReceiverOnlyObservedCount==2&&out.StandaloneTrialCount==0&&out.TransferredCount==0);
out=sixgr.truth.classifyPUCCHGrantDisposition(g,falseAccept);
assert(out.UnresolvedCount==2&&out.StandaloneTrialCount==0, ...
    'An independent positive receiver outcome must never override original UE no-TX.');
for mutation=["missing","unfinished","unavailable_history","wrong_source","wrong_transport", ...
        "no_samples","future_samples","future_decision","wrong_admission","missing_member", ...
        "extra_member","duplicate_member","duplicate_audit","UE_TX","PUCCH_TX","scored", ...
        "proxy","missing_clock","wrong_epoch","bad_numeric_identity","numeric_source_identity","wrong_grant_epoch"]
    bad=a; grants=g;
    switch mutation
        case "missing", bad.ReceiverInvocationCompleted=[];
        case "unfinished", bad.ReceiverInvocationCompleted=0;
        case "unavailable_history", bad.ReceiverInvocationCompleted=NaN;
        case "wrong_source", bad.Source="copied_intent";
        case "wrong_transport", bad.SelectedGNBTransport="PUCCH";
        case "no_samples", bad.ObservationEndSampleExclusive=bad.ObservationStartSample;
        case "future_samples", bad.AvailableAtSample=bad.ObservationEndSampleExclusive-1;
        case "future_decision", bad.AdmissionDecisionSample=bad.AvailableAtSample+1;
        case "wrong_admission", bad.PowerAdmissionObservationID="other";
        case "missing_member", bad.LogicalPUCCHGrantIdSet="g1";
        case "extra_member", bad.LogicalPUCCHGrantIdSet="g1|g2|other";
        case "duplicate_member", bad.LogicalPUCCHGrantIdSet="g1|g1|g2";
        case "duplicate_audit", bad=[a;a];
        case "UE_TX", bad.UETransmissionExecuted=true;
        case "PUCCH_TX", bad.UEPUCCHTransmissionExecuted=true;
        case "scored", bad.TransmittedTBScored=true;
        case "proxy", bad.ApproximationMode="fast_proxy";
        case "missing_clock", bad.ClockEpoch=NaN;
        case "wrong_epoch", bad.ClockEpoch=2;
        case "bad_numeric_identity", grants.UEIndex=["1";"1"];
        case "numeric_source_identity", bad.GrantContextID=17;
        case "wrong_grant_epoch", grants.SweepPointIndex(2)=2;
    end
    out=sixgr.truth.classifyPUCCHGrantDisposition(grants,table(),bad);
    assert(out.UnresolvedCount==2&&out.PUSCHReceiverOnlyObservedCount==0&&out.TransferredCount==0, ...
        'Malformed admission/completion %s must not be promoted.',mutation);
end
for field=["UEIndex","RNTI","ScheduledSlot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"]
    bad=a;bad.(field)=bad.(field)+1;
    assert(sixgr.truth.classifyPUCCHGrantDisposition(g,table(),bad).UnresolvedCount==2);
end
% Old physical audit values stay intact, but missing new invocation/admission
% authority remains explicitly UNKNOWN. Never reconstruct old reception.
newFields=["PowerAdmissionObservationID","LogicalPUCCHGrantIdSet","UEProducerDisposition", ...
    "UEReceivedCodebookDigest","PhysicalOccasionID","SelectedGNBTransport","ReceivedUCIObservationID", ...
    "RunUUID","ConfigHash","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex", ...
    "AdmissionDecisionSample","ClockEpoch","ReceiverClockEpoch","ReceiverInvocationCompleted"];
old=a;old(:,cellstr(newFields))=[];old.ObservationID="historical_original";oldBefore=old;
joined=sixgr.truth.appendRejectedULReceiveAudit(old,r);
assert(height(joined)==2&&isequaln(joined(1,old.Properties.VariableNames),oldBefore)&& ...
    isnan(joined.ReceiverInvocationCompleted(1))&&joined.PowerAdmissionObservationID(1)==""&& ...
    joined.ReceiverInvocationCompleted(2)==1);
assert(sixgr.truth.classifyPUCCHGrantDisposition(g,table(),joined(1,:)).UnresolvedCount==2);
assert(sixgr.truth.classifyPUCCHGrantDisposition(g,table(),joined).AllScheduledResolved);
modern=a;modern.ReceiverInvocationCompleted=true;
retained=sixgr.truth.appendRejectedULReceiveAudit(modern,r);
assert(isequaln(retained(1,:),modern)&&islogical(retained.ReceiverInvocationCompleted));
bad=old;bad.UnrecognizedHistoricalField=1;
reject(@()sixgr.truth.appendRejectedULReceiveAudit(bad,r));
% Production writer/import boundary: missing historical fields stay NaN/empty
% while current original completion is available, even when CRC is a reject.
prior=getenv('SIXGR_PERSISTENCE_ENABLED');cleanup=onCleanup(@()setenv('SIXGR_PERSISTENCE_ENABLED',prior)); %#ok<NASGU>
setenv('SIXGR_PERSISTENCE_ENABLED','1');
folder=fullfile(pwd,'results','validation','power_withheld_pusch_disposition',char(java.util.UUID.randomUUID()));
path=fullfile(folder,'rejected_ul_receive_only_audit.csv');
sixgr.util.csvWriteTable(path,joined,'PreserveSchema',true,'RoundTripNumericText',true);
% Match the actual coverage exporter's localReadOptionalTable contract.
% Default readtable cellstr inference is not that production consumer API;
% no numeric identity is converted to text by the classifier.
sha=sixgr.util.sha256File(path);read=sixgr.util.csvReadTable(path,'TextType','string');
out=sixgr.truth.classifyPUCCHGrantDisposition(g,table(),read);
assert(out.AllScheduledResolved&&out.PUSCHReceiverOnlyObservedCount==2&& ...
    isnan(read.ReceiverInvocationCompleted(1))&&sixgr.util.sha256File(path)==sha&&isequaln({g,a},original));
source=fileread(which('sixgr.truth.exportLLSOutputCoverageArtifacts'));
assert(contains(source,'src.PUCCHGrants, src.PUCCHTrials, src.PUSCHReceiveOnlyAudit')&& ...
    contains(source,'"rejected_ul_receive_only_audit.csv"')&& ...
    contains(source,'sixgr.util.csvReadTable(pathStr,"TextType","string")'));
ok=true;fprintf('POWER_WITHHELD_PUSCH_DISPOSITION_PASS scope=declared_audit_and_actual_CSV_not_PHY historical_RX_unknown=1\n');
end

function [g,r]=fixture()
g=table(["g1";"g2"],true(2,1),false(2,1),false(2,1),true(2,1), ...
    repmat("closed_untransmitted_missing_measured_power_reference",2,1),repmat("original_admission",2,1), ...
    'VariableNames',{'PUCCHGrantId','GrantScheduledFlag','GrantExecutedFlag','MultiplexedOnPUSCH', ...
    'UETransmissionSuppressed','UEProducerDisposition','PowerAdmissionObservationID'});
for field=["UEIndex","RNTI","Slot","BaseStationID","ComponentCarrier","ActiveULBWP","SweepPointIndex"]
    g.(field)=ones(2,1);
end
g.RunUUID=repmat("original_run",2,1);g.ConfigHash=repmat("original_config",2,1);
r=struct('ObservationID',"original_PUSCH_capture",'GrantContextID',"original_grant", ...
    'GNBControlObservationID',"original_gNB_control",'ReceivedUCIObservationID',"original_PUSCH_UCI", ...
    'PowerAdmissionObservationID',"original_admission",'LogicalPUCCHGrantIdSet',"g1|g2", ...
    'UEProducerDisposition',"closed_untransmitted_missing_measured_power_reference", ...
    'UEReceivedCodebookDigest',"original_received_book",'PhysicalOccasionID',"original_PUCCH_occasion", ...
    'SelectedGNBTransport',"PUSCH",'UEIndex',1,'RNTI',1,'ScheduledSlot',1, ...
    'BaseStationID',1,'ComponentCarrier',1,'ActiveULBWP',1,'SweepPointIndex',1, ...
    'AdmissionDecisionSample',100,'ClockEpoch',1,'ReceiverClockEpoch',1,'ObservationStartSample',110,'ObservationEndSampleExclusive',200, ...
    'AvailableAtSample',200,'SampleRateHz',30720000,'ReceiverInvocationCompleted',1, ...
    'UETransmissionExecuted',false,'UEDataTransmissionExecuted',false,'UEPUCCHTransmissionExecuted',false, ...
    'TransmittedTBScored',false,'DecodeAttempted',true,'ReceiverUsable',false, ...
    'ReceiverCRCAvailable',true,'ReceiverCRCError',1, ...
    'Source',"stream_owned_gnb_capture_and_scheduled_grant_independent_receiver", ...
    'RunUUID',"original_run",'ConfigHash',"original_config");
end
function reject(f)
try,f();catch ME,assert(strcmp(ME.identifier,'sixgr:truth:RejectedULAuditSchema'));return;end
error('sixgr:test:RejectedULAuditSchemaAccepted','Unexpected historical schema was silently dropped.');
end
