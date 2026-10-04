function ok=testSystemGrantUEIdentity()
% Protocol identifiers are scoped to a cell, not MATLAB array indices.
states=struct('RNTI',{4660,4661},'UEIndex',{1,2});
grants=struct('RNTI',{4661,4660},'PHYGrant',{struct('Digest',"second"),struct('Digest',"first")});
bound=sixgr.system.bindGrantUEIdentity(grants,states,3);
assert(isequal([bound.UEIndex],[2 1]) && all([bound.SystemServingCellID]==3));
assert(isequal([bound.RNTI],[4661 4660]) && isequal({bound.PHYGrant},{grants.PHYGrant}));
assert(sixgr.system.resolveGrantUEIndex(bound(1),2)==2);
% Reusing an RNTI in another cell is legal and must not alias its UE.
other=sixgr.system.bindGrantUEIdentity(grants(2),struct('RNTI',4660,'UEIndex',3),4);
assert(other.UEIndex==3 && other.RNTI==bound(2).RNTI);
bad=states; bad(2).RNTI=4660;
reject(@()sixgr.system.bindGrantUEIdentity(grants,bad,3),'sixgr:system:AmbiguousUEIdentity');
bad=bound; bad(1).UEIndex=1;
reject(@()sixgr.system.bindGrantUEIdentity(bad,states,3),'sixgr:system:GrantUEIdentityMismatch');
bad=grants; bad(1).RNTI=65500;
reject(@()sixgr.system.bindGrantUEIdentity(bad,states,3),'sixgr:system:UnknownGrantUE');
reject(@()sixgr.system.resolveGrantUEIndex(grants(1),2),'sixgr:system:MissingGrantUEIndex');
reject(@()sixgr.system.resolveGrantUEIndex(other,2),'sixgr:system:MissingGrantUEIndex');
fprintf('SYSTEM_GRANT_UE_IDENTITY_PASS protocol_RNTI=4660 internal_UE=1 no_clamping=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s',id,ME.identifier); return; end
error('test:MissingRejection','Expected %s',id);
end
