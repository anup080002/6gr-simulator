function ok=testContentionResolutionState()
% Exact UE timer and received-MAC decisions, not a gNB decode oracle.
setup6GRSimToolkit('Verbose',false);
state=sixgr.mac.ra.ContentionResolutionState("123456ABCDEF",4353,int64(100),int64(1000));
reject(@()state.start(int64(99)),'sixgr:mac:ra:InvalidContentionTimerStart');
state=state.start(int64(100));
reject(@()state.start(int64(100)),'sixgr:mac:ra:InvalidContentionTimerStart');
waiting=state.receive(int64(200),4353,false,false,"");
waiting=waiting.receive(int64(300),4353,true,false,"");
waiting=waiting.receive(int64(400),4354,true,true,"123456ABCDEF");
assert(waiting.Status=="waiting" && ~waiting.Msg3HARQFlushRequired);
reject(@()waiting.receive(int64(400),4353,true,true,"123456ABCDEF"), ...
    'sixgr:mac:ra:InvalidContentionObservation');
reject(@()waiting.expire(int64(1099)),'sixgr:mac:ra:InvalidContentionTimerExpiry');
expired=waiting.expire(int64(1100));
assert(expired.Status=="expired" && expired.Msg3HARQFlushRequired && ...
    expired.TemporaryCRNTIDiscardRequired && expired.ResolutionTicks==1100);
reject(@()expired.receive(int64(1101),4353,true,true,"123456ABCDEF"), ...
    'sixgr:mac:ra:InvalidContentionObservation');
matched=waiting.receive(int64(500),4353,true,true,"123456ABCDEF");
assert(matched.Status=="succeeded" && matched.IdentityMatches);
reject(@()matched.expire(int64(1100)),'sixgr:mac:ra:InvalidContentionTimerExpiry');
wrong=waiting.receive(int64(500),4353,true,true,"FFFFFFFFFFFF");
assert(wrong.Status=="identity_mismatch" && wrong.ResolutionTicks==500 && ...
    wrong.Msg3HARQFlushRequired && wrong.TemporaryCRNTIDiscardRequired);
absent=waiting.receive(int64(500),4353,true,true,"");
assert(absent.Status=="identity_mismatch");
disp('CONTENTION_RESOLUTION_STATE_PASS: missed control/TB waits; decoded mismatch fails; exact expiry and duplicate guards.');
ok=true;
end
function reject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testContentionResolutionState:MissingRejection','Expected %s.',id);
end
