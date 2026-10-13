function ok=testMsg3DistinctContentionIdentity()
% Identity separation and actual UE-side mismatch guards, not ASN.1 coverage.
setup6GRSimToolkit('Verbose',false);
before=rng; ids=strings(100,1);
for ue=1:100
    m=sixgr.mac.ra.buildMsg3Payload('UEId',ue);
    ids(ue)=m.ContentionIdentity;
    again=sixgr.mac.ra.buildMsg3Payload('UEId',ue);
    assert(isequal(m.PayloadBits,again.PayloadBits));
end
assert(numel(unique(ids))==100 && isequaln(rng,before));
assert(ids(1)=="000000000001" && ids(2)=="000000000002");
m=sixgr.mac.ra.buildMsg3Payload('UEId',2^48-1); assert(m.ContentionIdentity=="FFFFFFFFFFFF");
explicit=uint8([0 1 2 253 254 255]);
m=sixgr.mac.ra.buildMsg3Payload('UEId',1,'ContentionIdentity',explicit);
assert(isequal(m.ContentionIdentityBytes,explicit(:)) && m.ContentionIdentity=="000102FDFEFF");
for invalid={0,-1,1.5,NaN,Inf,2^48}
    reject(@()sixgr.mac.ra.buildMsg3Payload('UEId',invalid{1}));
end
for invalid={ones(1,5),ones(1,7),[0 0 0 0 0 256],[0 0 0 0 0 -1]}
    reject(@()sixgr.mac.ra.buildMsg3Payload('ContentionIdentity',invalid{1}));
end
% Two UEs sharing a temporary C-RNTI must not accept each other's identity.
ue1=sixgr.mac.ra.ContentionResolutionState(ids(1),4660,int64(0),int64(100));
ue2=sixgr.mac.ra.ContentionResolutionState(ids(2),4660,int64(0),int64(100));
ue1=ue1.start(int64(0)); ue2=ue2.start(int64(0));
ue1=ue1.receive(int64(1),4660,true,true,ids(1));
ue2=ue2.receive(int64(1),4660,true,true,ids(1));
assert(ue1.Status=="succeeded" && ue2.Status=="identity_mismatch" && ...
    ~ue2.IdentityMatches && ue2.TemporaryCRNTIDiscardRequired);
fprintf('MSG3_DISTINCT_CONTENTION_IDENTITY_PASS unique_UEs=100 shared_rnti_wrong_identity_rejected=1\n');
ok=true;
end
function reject(f)
failed=false; try, f(); catch, failed=true; end
assert(failed,'Malformed local identity must not be silently rounded, padded or truncated.');
end
