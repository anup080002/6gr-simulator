function ok = kpiReproducibilityAcceptance()
%KPIREPRODUCIBILITYACCEPTANCE Causal KPI arithmetic and deterministic cache anchors.

raw = struct();
raw.UL = localRows("UL");
raw.DL = localRows("DL");
out = sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw, ...
    "StrictMode", true, "MeasurementWindowSec", 0.004, "EffectiveBandwidthHz", 1e6);
summary = out.ReconstructionSummary;
goodput = localMetric(summary, "UL_TB_Delivery_Goodput_Mbps");
latency = localMetric(summary, "UL_TB_Delivery_Latency_ms");
assert(abs(double(goodput.ReconstructionValue) - 0.5) < 1e-12, ...
    "Scenario goodput must be first-success delivered bits divided by full measurement window.");
assert(abs(double(latency.ReconstructionValue) - 1.5) < 1e-12, ...
    "Radio latency must be reconstructed from event timestamps, not wall-clock time.");

clear sixgr.phy.dl.pmiCodebookCandidates;
cfg = sixgr.config.defaultConfig();
cfg.phy.beamManagement.beamCount = 8;
cfg.phy.csi.codebookType = "type1";
[c1, i1] = sixgr.phy.dl.pmiCodebookCandidates(cfg, 2, 4, "Mode", "type1_su_mimo", "MaxCandidates", 8);
[c2, i2] = sixgr.phy.dl.pmiCodebookCandidates(cfg, 2, 4, "Mode", "type1_su_mimo", "MaxCandidates", 8);
assert(~logical(i1.CacheHit) && logical(i2.CacheHit) && strcmp(string(i1.CacheKey), string(i2.CacheKey)), ...
    "PMI cache must be deterministic by immutable input key.");
assert(numel(c1) == numel(c2) && max(abs(c1(1).W(:) - c2(1).W(:))) < 1e-15, ...
    "Cached PMI codebook output must be numerically identical.");
ok = true;
end

function T = localRows(direction)
direction = string(direction);
T = table( ...
    repmat(direction, 3, 1), [0; 0; 0], [false; true; true], [10; 0; 0], ...
    [1000; 1000; 1000], [1000; 1000; 1000], [0; 1000; 1000], ...
    [1; 1; 1], [1; 2; 3], [0; 0; 0], [1; 1; 1], [0; 2; 0], ...
    [true; false; true], [false; true; false], [1; 1; 1], [1; 2; 3], ...
    [0.001; 0.001; 0.001], ...
    'VariableNames', {'Direction','Goodput_Mbps','CRCPass','BitErrors','BitsCompared', ...
    'TBSize_bits','GoodBits','Frame','Slot','HARQProcessId','NDI','RV', ...
    'NewDataFlag','RetransmissionFlag','AirInterfaceObservation_ms','TrialId','SlotDuration_s'});
end

function row = localMetric(T, name)
row = T(strcmp(string(T.KPIName), string(name)), :);
assert(height(row) == 1, "Expected exactly one KPI reconstruction row for %s.", name);
end
