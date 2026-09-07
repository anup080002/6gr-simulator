function tbs = TBSCalculator(carrier, pdsch, targetCodeRate, xOverhead, tbScaling)
%TBSCalculator Compute TBS from the actual materialized PDSCH allocation.

if nargin < 4 || isempty(xOverhead)
    xOverhead = 0;
end
if nargin < 5, tbScaling = 1; end
if ~isnumeric(tbScaling) || any(~ismember(tbScaling,[1 .5 .25]))
    error("sixgr:pdsch:TBSCalculator:InvalidScaling","TB scaling must be 1, 1/2 or 1/4.");
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
tbs = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, double(targetCodeRate), double(xOverhead),double(tbScaling)));
end
