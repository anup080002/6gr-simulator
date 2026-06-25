function tbs = TBSCalculator(carrier, pdsch, targetCodeRate, xOverhead)
%TBSCalculator Compute TBS from the actual materialized PDSCH allocation.

if nargin < 4 || isempty(xOverhead)
    xOverhead = 0;
end
try
    [pdschInd, info] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
catch
    [pdschInd, info] = nrPDSCHIndices(carrier, pdsch);
end
nPRB = max(1, numel(pdsch.PRBSet));
acct = sixgr.phy.resource.computeResourceAccounting("PDSCH", carrier, pdsch, ...
    "ChannelIndices", pdschInd, ...
    "AllocationInfo", info, ...
    "IndexBase", "1based", ...
    "TargetCodeRate", targetCodeRate, ...
    "XOverhead", xOverhead);
nrePerPRB = acct.NREPerPRBForTBS;
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error("sixgr:pdsch:TBSCalculator:MissingNRE", ...
        "Unable to derive NRE per PRB from the materialized PDSCH allocation.");
end
tbs = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, double(targetCodeRate), double(xOverhead)));
end
