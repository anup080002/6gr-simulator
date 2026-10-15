function cdmLengths=resolveCDMLengths(srs)
%RESOLVECDMLENGTHS Explicit SRS geometry for reception and independent scoring.
% SRS ports use cyclic shifts of a common base sequence. Joint despreading
% must cover the complete configured port set; correlation between only the
% first two sequences is not an authority for four-port reception. KTC changes
% occupied REs, not this complete port-set despreading length.
% This helper preserves the supported one/two/four-port receiver contract.
nPorts=double(srs.NumSRSPorts);
if ~(isscalar(nPorts) && isfinite(nPorts) && any(nPorts==[1 2 4]))
    error('sixgr:phy:ul:UnsupportedSRSPortCount', ...
        'SRS receiver requires NumSRSPorts to be one of [1 2 4], got %g.',nPorts);
end
comb=double(srs.KTC);
if ~(isscalar(comb) && isfinite(comb) && any(comb==[2 4]))
    error('sixgr:phy:ul:UnsupportedSRSComb', ...
        'SRS receiver requires KTC to be 2 or 4, got %g.',comb);
end
cdmLengths=[nPorts 1];
end
