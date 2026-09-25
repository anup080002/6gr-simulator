function evidence=measureDMRSSequenceCorrelation(context,actual)
%MEASUREDMRSSEQUENCECORRELATION Independent digital-sequence comparison.
% This is not a received waveform, channel estimate or detection campaign.
if nargin<2, actual=sixgr.phy.pdcch.PDCCHDMRS.generate(context); end
reference=localReference(context);
x=double(actual.SequenceSymbols(:));
if isempty(x) || numel(x)~=numel(reference) || any(~isfinite(x)) || norm(x)==0
    error('sixgr:phy:pdcch:invalid_dmrs_evidence','Invalid actual DM-RS samples.');
end
other=context; other.NID=mod(double(context.NID)+1,65536);
wrongNID=localReference(other);
other=context; other.Symbol=mod(double(context.Symbol)+1,14);
wrongSymbol=localReference(other);
evidence=struct('MatchedReferenceCorrelation',localCorrelation(x,reference), ...
    'WrongNIDCorrelation',localCorrelation(x,wrongNID), ...
    'WrongSymbolCorrelation',localCorrelation(x,wrongSymbol), ...
    'IndependentMismatchCount',sum(abs(x-reference)>1e-12), ...
    'EvidenceClass',"digital_sequence_component_not_receiver", ...
    'ReferenceImplementation',"MathWorks_nrPRBS_nrSymbolModulate");
end
function ref=localReference(c)
cinit=mod(2^17*(14*double(c.Slot)+double(c.Symbol)+1)*(2*double(c.NID)+1)+2*double(c.NID),2^31);
ref=double(nrSymbolModulate(nrPRBS(cinit,6*double(c.CORESETRBs)),'QPSK'));
ref=ref(:);
end
function v=localCorrelation(a,b)
v=abs(a'*b)/(norm(a)*norm(b));
end
