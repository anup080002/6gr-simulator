function first = candidateFirstCCE(carrier,pdcch,aggregation,index0,blind)
%CANDIDATEFIRSTCCE Installed-search-space location, not a decoded/TX oracle.
if nargin<5, blind=true; end
if ~blind && ~isempty(pdcch.CCEOffset)
    first=double(pdcch.CCEOffset);
    return;
end
context=sixgr.phy.pdcch.resolveCandidateContext(carrier,pdcch,aggregation,index0);
first=context.FirstCCE;
end
