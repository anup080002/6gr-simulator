function nrePerPRB = nominalPDSCHNREPerPRB(carrier, cfg, varargin)
%NOMINALPDSCHNREPERPRB Exact nominal TBS input (TS 38.214 5.1.3.2).
% A cached count/TDRA probe has no scheduled PRB or slot authority. Return
% only nominal N_RE per PRB, never G, measured rows, or feasibility. Actual
% grants MUST separately use allocREsPDSCH on their scheduled occasion.
pdsch = sixgr.phy.grid.pdschConfigFromConfig(carrier,cfg,varargin{:});
[~,info] = nrPDSCHIndices(carrier,pdsch);
dmrs = nrPDSCHDMRSIndices(carrier,pdsch);
assert(~isempty(dmrs),'sixgr:pdsch:NoDMRSResources', ...
    'The nominal PDSCH TDRA must contain valid DM-RS resources.');
nrePerPRB = double(info.NREPerPRB);
validateattributes(nrePerPRB,{'numeric'}, ...
    {'scalar','finite','integer','positive'});
end
