function ok=testSharedDLNoDecodePreflight()
% Negative contract tests only; no initialized radio, samples or RF claim.
state=struct('SharedWaveformStream',sixgr.truth.CoupledWaveformStream());
control=struct('Key',"declared_negative_contract",'Allowed',false);
state.SharedReceivedGrantControls={control};
item=struct('Kind',"PDSCH");
reject(@()sixgr.truth.completeSharedDLWithoutAcceptedControl(state,item,control), ...
    'sixgr:truth:MissingSharedDLRejectedControlEvidence');
accepted=control; accepted.Allowed=true;
reject(@()sixgr.truth.completeSharedDLWithoutAcceptedControl(state,item,accepted), ...
    'sixgr:truth:InvalidSharedDLNoDecodeControl');
other=control; other.Key="unretained";
reject(@()sixgr.truth.completeSharedDLWithoutAcceptedControl(state,item,other), ...
    'sixgr:truth:UnretainedSharedDLNoDecodeControl');
control.ReceiverTrial=struct('Crash',false,'DecodeAttempted',true,'PDCCHCausalGrantDecodeOk',false);
control.RejectedControlObservation=[];
state.SharedReceivedGrantControls={control};
reject(@()sixgr.truth.completeSharedDLWithoutAcceptedControl(state,item,control), ...
    'sixgr:truth:InvalidSharedDLRejectedControlClock');
for field=["Crash","DecodeAttempted","PDCCHCausalGrantDecodeOk"]
    bad=control; bad.ReceiverTrial.(field)=~bad.ReceiverTrial.(field);
    broken=state; broken.SharedReceivedGrantControls={bad};
    reject(@()sixgr.truth.completeSharedDLWithoutAcceptedControl(broken,item,bad), ...
        'sixgr:truth:InvalidSharedDLRejectedControlEvidence');
end
assert(~isfield(state,'SharedDLNoDecodeDispositionTable') && ...
    ~isfield(state,'SharedDataNoDecodeCommittedIDs'));
fprintf('SHARED_DL_NO_DECODE_PREFLIGHT_PASS negative_contract_only RF_executions=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
