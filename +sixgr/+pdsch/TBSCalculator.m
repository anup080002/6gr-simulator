function tbs = TBSCalculator(carrier, pdsch, targetCodeRate, xOverhead)
%TBSCalculator Compute TBS from the actual materialized PDSCH allocation.

if nargin < 4 || isempty(xOverhead)
    xOverhead = 0;
end
try
    [~, info] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
catch
    [~, info] = nrPDSCHIndices(carrier, pdsch);
end
nPRB = max(1, numel(pdsch.PRBSet));
nrePerPRB = double(sixgr.util.structGet(info, "NREPerPRB", NaN));
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = floor(double(sixgr.util.structGet(info, "NRE", 0)) / nPRB);
end
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error("sixgr:pdsch:TBSCalculator:MissingNRE", ...
        "Unable to derive NRE per PRB from the materialized PDSCH allocation.");
end
tbs = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, double(targetCodeRate), double(xOverhead)));
end

