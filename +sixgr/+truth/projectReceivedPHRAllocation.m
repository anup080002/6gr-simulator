function e=projectReceivedPHRAllocation(grant)
% Preserve the original scheduler policy receipt; never recompute from TX PH.
e=struct('ReceivedPHRAllocationApplied',false,'ReceivedPHRAllocationStatus',"not_applicable", ...
    'ReceivedPHRAllocationJSON',"",'ReceivedPHRAllocationSHA256',"");
r=sixgr.util.structGet(grant,'ReceivedPHRAllocation',struct());
if isempty(fieldnames(r)), return; end
e.ReceivedPHRAllocationApplied=logical(r.Applied);
e.ReceivedPHRAllocationStatus=string(r.Status);
e.ReceivedPHRAllocationJSON=string(jsonencode(r));
e.ReceivedPHRAllocationSHA256=string(sixgr.util.sha256Hex(char(e.ReceivedPHRAllocationJSON)));
end
