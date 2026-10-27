function evidence=commitReceivedMACAdmissions(bridge,reverse,phr,phCandidate,bsr,bsCandidate)
% Validate all decoded control effects before any live protocol owner mutates.
hasReverse=isstruct(reverse)&&~isempty(fieldnames(reverse));
if hasReverse, bridge.validateMACControlAdmission(reverse); end
if ~isempty(phr), phr.validateAdmission(phCandidate); end
if ~isempty(bsr), bsr.validateAdmission(bsCandidate); end
evidence=struct();
if hasReverse, evidence=bridge.commitMACControlAdmission(reverse); end
if ~isempty(phr), phr.commitAdmission(phCandidate); end
if ~isempty(bsr), bsr.commitAdmission(bsCandidate); end
end
