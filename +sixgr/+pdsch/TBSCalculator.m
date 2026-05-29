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
nrePerPRB = localResolveDataNREPerPRB(info, nPRB, pdsch.Modulation, pdsch.NumLayers);
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    error("sixgr:pdsch:TBSCalculator:MissingNRE", ...
        "Unable to derive NRE per PRB from the materialized PDSCH allocation.");
end
tbs = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, double(targetCodeRate), double(xOverhead)));
end

function nrePerPRB = localResolveDataNREPerPRB(info, nPRB, modStr, nLayers)
nrePerPRB = NaN;
qm = localQm(modStr);
if isfield(info, "G")
    gBits = double(info.G);
    if isfinite(gBits)
        if gBits <= 0
            nrePerPRB = 0;
            return;
        end
        nrePerPRB = floor(gBits / max(double(qm) * double(nLayers) * max(double(nPRB), 1), 1));
        if isfinite(nrePerPRB) && nrePerPRB > 0
            return;
        end
    end
end
nrePerPRB = double(sixgr.util.structGet(info, "NREPerPRB", NaN));
if ~(isfinite(nrePerPRB) && nrePerPRB > 0)
    nrePerPRB = floor(double(sixgr.util.structGet(info, "NRE", 0)) / max(double(nPRB), 1));
end
end

function qm = localQm(modStr)
switch upper(strrep(char(string(modStr)), "-", ""))
    case "BPSK"
        qm = 1;
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    otherwise
        qm = 2;
end
end
