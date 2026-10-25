function p=pbchStagePopulations(T)
% Original receiver decisions and separately declared TX population membership.
% This validates retained operands, not independent physical authentication.
[attempted,known]=flag(T,"DetectionAttempted");
[p.PSSDetected,p.PSSEligible]=detector(T,"PSS");
[p.SSSDetected,p.SSSEligible]=detector(T,"SSS");
p.PSSEligible=p.PSSEligible & known & attempted;
p.SSSEligible=p.SSSEligible & p.PSSEligible & p.PSSDetected;
p.DetectionEligible=p.PSSEligible & (~p.PSSDetected | p.SSSEligible);
p.Detected=p.PSSDetected & p.SSSDetected;
[p.CellRecovered,cellKnown]=flag(T,"NCellIDRecovered");
p.CellEligible=p.DetectionEligible & cellKnown & (~p.CellRecovered | p.Detected);
[decoded,decodeKnown]=flag(T,"DecodeAttempted");
[p.CRCValid,crcKnown]=flag(T,"BCHCRCValid");
bits=number(T,"BCHTransportBlockNumBits");
hashes=textColumn(T,"BCHTransportBlockHash");
hasHash=~cellfun('isempty',regexp(cellstr(hashes),'^[0-9a-fA-F]{64}$','once'));
p.DecodeEligible=decodeKnown & decoded & crcKnown & isfinite(bits) & bits>0 & bits==fix(bits) & hasHash;
p.MIBAccepted=sixgr.truth.pbchAcquisitionAccepted(T);
p.MIBEligible=p.DecodeEligible;
for name=["MIBDecoded","CandidateIdentityConsistent","SSBIdentityVerified"]
    [~,identityKnown]=flag(T,name); p.MIBEligible=p.MIBEligible & identityKnown;
end
[transmitted,membershipKnown]=flag(T,"SSBRequestedCandidateTransmitted");
requested=number(T,"RequestedSSBOccasionIndex");
% A bare false/default flag is not an original quiet-candidate declaration.
scope=textColumn(T,"SSBReceiverSearchScope");
window=textColumn(T,"SSBAcquisitionWindowSHA256");
hasWindow=~cellfun('isempty',regexp(cellstr(window),'^[0-9a-fA-F]{64}$','once'));
p.PopulationKnown=membershipKnown & isfinite(requested) & requested>=0 & requested==fix(requested) & ...
    strlength(scope)>0 & hasWindow;
p.Transmitted=p.PopulationKnown & transmitted;
p.Quiet=p.PopulationKnown & ~transmitted;
[block,blockKnown]=flag(T,"BCHTransmittedBlockPopulationEligible");
p.TransmittedDecodeEligible=p.DecodeEligible & p.Transmitted & blockKnown & block;
% The explicit TX-block flag must be false for a quiet decoder attempt.
p.QuietDecodeEligible=p.DecodeEligible & p.Quiet & blockKnown & ~block;
end

function [detected,known]=detector(T,stage)
[detected,decisionKnown]=flag(T,stage+"Detected");
[available,availableKnown]=flag(T,stage+"DetectionDecisionAvailable");
[valid,validKnown]=flag(T,stage+"DetectionMetricValid");
metric=number(T,stage+"NormalizedMetric"); threshold=number(T,stage+"DetectionThreshold");
hypotheses=number(T,stage+"DetectionHypothesisCount");
known=decisionKnown & availableKnown & available & validKnown & valid & ...
    isfinite(metric) & metric>=0 & metric<=1+64*eps & isfinite(threshold) & threshold>=0 & ...
    isfinite(hypotheses) & hypotheses>=1 & hypotheses==fix(hypotheses) & detected==(metric>threshold);
end

function [value,known]=flag(T,name)
raw=number(T,name); known=isfinite(raw) & (raw==0 | raw==1); value=known & raw==1;
end

function value=number(T,name)
value=nan(height(T),1);
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name);
if (isnumeric(raw)||islogical(raw)) && isreal(raw) && isequal(size(raw),[height(T),1])
    value=double(raw);
end
end

function value=textColumn(T,name)
value=strings(height(T),1);
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name);
if (isstring(raw)||iscellstr(raw)) && isequal(size(raw),[height(T),1])
    value=string(raw); value(ismissing(value))="";
end
end
