function ok=testRARCellIdentityAllocation()
% Cell allocator boundary checks; detections here are declared test inputs.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.lls6g.userContext.RuntimeServingCell=1;
ra=sixgr.mac.ra.RAConfig(cfg);
assert(ra.CellId==17 && ra.NCellID==17 && ra.ServingCell==1);
det=struct('Detected',true,'DetectedPreambleIndex',3);
allocator=sixgr.mac.ra.RARIdentityAllocator([6200 6202]);
[allocator,a,fresh]=allocator.reserve(ra,det,6200);
assert(fresh && a.TemporaryCRNTI==6201);
otherUE=ra; otherUE.UEId=999; otherUE.PreambleIndex=17;
[same,b,fresh]=allocator.reserve(otherUE,det,6200);
assert(~fresh && isequal(a,b) && isequal(same.Allocations,allocator.Allocations), ...
    'Repeated gNB reception must not allocate by UE or intended TX preamble.');
later=ra; later.PRACHAbsoluteSlot=ra.PRACHAbsoluteSlot+10;
[allocator,c,fresh]=allocator.reserve(later,det,6200);
assert(fresh && c.TemporaryCRNTI==6202);
later.PRACHAbsoluteSlot=later.PRACHAbsoluteSlot+10;
localReject(@()allocator.reserve(later,det,6200),'sixgr:mac:ra:TemporaryCRNTIPoolExhausted');
otherCell=ra; otherCell.ServingCell=2; % A different gNB may reuse the same PCI.
[~,d,fresh]=allocator.reserve(otherCell,det,[]);
assert(fresh && d.TemporaryCRNTI==6200,'Identity uniqueness is cell scoped.');
miss=det; miss.Detected=false;
localReject(@()allocator.reserve(ra,miss,[]),'sixgr:mac:ra:UndetectedTemporaryCRNTI');
localReject(@()sixgr.mac.ra.RARIdentityAllocator.bind(otherCell,det,a), ...
    'sixgr:mac:ra:TemporaryCRNTIAssignmentMismatch');
bound=sixgr.mac.ra.RARIdentityAllocator.bind(ra,det,a);
assert(bound.TempCRNTI==6201 && bound.FinalCRNTI==6201);
for pool={[0 5],[3 2],[1 65523],[1 2.5],[1 2 3],[NaN 2]}
    localReject(@()sixgr.mac.ra.RARIdentityAllocator(pool{1}), ...
        'sixgr:mac:ra:InvalidTemporaryCRNTIPool');
end
ok=true; disp('RAR_CELL_IDENTITY_ALLOCATION_PASS: independent occasion ownership, collision avoidance, no wrap/reuse.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('test:MissingExpectedRejection','Expected %s.',id);
end
