function out=projectMCSTransitionEvidence(grant)
% Descriptive projection of the original selection receipt, never a decision.
if nargin<1, grant=struct(); end
out=struct('MCSTransitionReceiptJSON',"",'MCSTransitionReceiptSHA256',"", ...
    'MCSTransitionRawTarget',NaN,'MCSTransitionPreviousCommittedMCS',NaN, ...
    'MCSTransitionAppliedMCS',NaN,'MCSTransitionACKCount',NaN, ...
    'MCSTransitionNACKCount',NaN,'MCSTransitionReason',"",'MCSTransitionRawTargetAuthority',"");
receipt=sixgr.util.structGet(grant,'MCSTransition',struct());
if isempty(fieldnames(receipt)), return; end
out.MCSTransitionReceiptJSON=string(jsonencode(receipt));
out.MCSTransitionReceiptSHA256=sixgr.util.sha256Hex(out.MCSTransitionReceiptJSON);
for pair=["RawTarget","RawTargetMCS";"PreviousCommittedMCS","PreviousCommittedMCS"; ...
        "AppliedMCS","AppliedMCS";"ACKCount","ACKCount";"NACKCount","NACKCount"].'
    out.("MCSTransition"+pair(1))=double(receipt.(pair(2)));
end
out.MCSTransitionReason=string(receipt.Reason);
out.MCSTransitionRawTargetAuthority=string(receipt.RawTargetAuthority);
end
