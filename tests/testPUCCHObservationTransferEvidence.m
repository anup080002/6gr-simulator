function ok=testPUCCHObservationTransferEvidence()
% Explicit ledger fixtures only, no transmitted/received PHY claims.
row=struct('ScheduledAbsoluteSlot',9,'FeedbackForDirection',"DL", ...
    'UEIndex',1,'RNTI',1,'ServingCell',1,'ComponentCarrier',0,'ActiveULBWP',0, ...
    'PUCCHGrantId',"declared_feedback_1",'MultiplexedOnPUSCH',true, ...
    'PUSCHGrantContextId',"declared_ul_grant",'RightCensored',false);
rows=struct2table(row); key=sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey(rows);
p=sixgr.truth.validatePUCCHObservationTransfer(rows,key);
assert(p.Key==key && p.FeedbackGrantIDs==row.PUCCHGrantId && ...
    p.Source=="pending_UCI_reservation_not_PUSCH_execution");
localReject(@()sixgr.truth.validatePUCCHObservationTransfer(table(),key),'PUCCHTransferEvidenceMissing');
localReject(@()sixgr.truth.validatePUCCHObservationTransfer(rows,key+"different"),'PUCCHTransferEvidenceMissing');
bad=rows; bad.MultiplexedOnPUSCH(:)=false;
localReject(@()sixgr.truth.validatePUCCHObservationTransfer(bad,key),'PUCCHTransferBindingMissing');
bad=rows; bad.PUSCHGrantContextId(:)="";
localReject(@()sixgr.truth.validatePUCCHObservationTransfer(bad,key),'PUCCHTransferBindingMissing');
localReject(@()sixgr.truth.validatePUCCHObservationTransfer([rows;rows],key),'PUCCHTransferBindingMissing');
bad=rows; bad.RightCensored(:)=true;
localReject(@()sixgr.truth.validatePUCCHObservationTransfer(bad,key),'PUCCHTransferCensored');
ok=true; disp('PUCCH_OBSERVATION_TRANSFER_EVIDENCE_PASS');
end
function localReject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)=="sixgr:truth:"+id,'Unexpected failure: %s',cause.message); return;
end
error('test:MissingRejection','Expected %s',id);
end
