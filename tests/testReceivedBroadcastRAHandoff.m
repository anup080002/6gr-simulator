function ok=testReceivedBroadcastRAHandoff()
% Contract-only fixtures; this test makes no physical acquisition claim.
cfg=sixgr.config.defaultConfig();
fs=30720000; n=fs*sixgr.time.slotDurationSec(cfg);
r=struct('Ok',true,'SSBIdentityVerified',true,'SSBIndex',3, ...
    'ObservedSSBOccasionIndex',3,'PBCHHypothesisSSBIndex',3, ...
    'SSBIndexSource',"test_decoded_pbch_identity", ...
    'ObservationSampleRateHz',fs,'ObservationEndSampleExclusive',4*n, ...
    'SIB1',struct('MIBDecoded',true,'BCHCrcPass',true,'DCICrcPass',true, ...
    'DLSCHCrcPass',true,'SIB1ASN1DecodeOk',true,'SIB1SemanticValid',true));
cfg.random_access.associated_ssb_index=0; % A stale configured hint is not authority.
[bound,recovery,slot]=sixgr.truth.bindReceivedBroadcastForRA(cfg,r);
assert(bound.random_access.associated_ssb_index==3 && bound.phy.ssb.runtimeSSBIndex==3);
assert(isequal(recovery,r.SIB1) && slot==5);
r.ObservationEndSampleExclusive=4*n+1;
[~,~,slot]=sixgr.truth.bindReceivedBroadcastForRA(cfg,r);
assert(slot==6,'A partial next slot must not be used before reception completes.');
bad=r; bad.SSBIdentityVerified=false; rejects(cfg,bad,'UnsuccessfulReceivedBroadcast');
bad=r; bad.PBCHHypothesisSSBIndex=2; rejects(cfg,bad,'ReceivedBroadcastIdentityMismatch');
bad=r; bad.SIB1.DLSCHCrcPass=false; rejects(cfg,bad,'UnsuccessfulReceivedBroadcast');
bad=r; bad.ObservationEndSampleExclusive=NaN; rejects(cfg,bad,'ReceivedBroadcastClockMismatch');
bad=r; bad.SSBIndexSource=""; rejects(cfg,bad,'MissingReceivedBroadcast');
ok=true;
end
function rejects(cfg,r,suffix)
try
    sixgr.truth.bindReceivedBroadcastForRA(cfg,r);
catch ex
    assert(string(ex.identifier)=="sixgr:truth:"+suffix,string(ex.identifier));
    return
end
error('Expected rejection: %s',suffix);
end
