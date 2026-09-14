function ok=testSharedRejectedULControlPreflight()
% Declared negative contracts only: no physical rejection or decoder claim.
state=struct('SharedWaveformStream',sixgr.truth.CoupledWaveformStream());
control=struct('Key',"declared_negative_contract",'Allowed',false);
state.SharedReceivedGrantControls={control};
reject(@()sixgr.truth.validateSharedRejectedULControl(state,control), ...
    'sixgr:truth:MissingSharedULRejectedControlEvidence');
bad=control; bad.Allowed=true;
reject(@()sixgr.truth.validateSharedRejectedULControl(state,bad), ...
    'sixgr:truth:InvalidSharedULRejectedControl');
bad=control; bad.Key="unretained";
reject(@()sixgr.truth.validateSharedRejectedULControl(state,bad), ...
    'sixgr:truth:UnretainedSharedULRejectedControl');
control.ReceiverTrial=struct('Crash',false,'DecodeAttempted',true,'PDCCHCausalGrantDecodeOk',false);
control.RejectedControlObservation=[]; control.ReceivedAssignment=struct();
control.Grant=struct(); control.AvailableAtSample=0;
state.SharedReceivedGrantControls={control};
reject(@()sixgr.truth.queueSharedPUSCHAfterRejectedControl(state,struct(),control), ...
    'sixgr:truth:InvalidSharedULRejectedControlClock');
for name=["Crash","DecodeAttempted","PDCCHCausalGrantDecodeOk"]
    bad=control; bad.ReceiverTrial.(name)=~bad.ReceiverTrial.(name);
    broken=state; broken.SharedReceivedGrantControls={bad};
    reject(@()sixgr.truth.queueSharedPUSCHAfterRejectedControl(broken,struct(),bad), ...
        'sixgr:truth:InvalidSharedULRejectedControlEvidence');
end
assert(isempty(state.SharedWaveformStream.Pending) && ...
    isempty(state.SharedWaveformStream.PUSCHReceiveOnlyRegistrations));
fprintf('SHARED_REJECTED_UL_PREFLIGHT_PASS negative_contract_only RF_executions=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
