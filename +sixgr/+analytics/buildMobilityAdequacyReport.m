function mobReport = buildMobilityAdequacyReport(scenarioCfg, dlTrials, runDir)
%BUILDMOBILITYADEQUACYREPORT Check whether runtime rows support mobility claims.
%
% The report is derived from scenario configuration and observed DL trial
% slots. It labels short or sparse captures as diagnostic instead of treating
% a configured duration as runtime evidence by itself.

arguments
    scenarioCfg = struct()
    dlTrials table = table()
    runDir {mustBeTextScalar} = pwd
end

layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.ReportCSVDir);

speedKmh = localCfgNumber(scenarioCfg, ...
    ["mobility.ue_speed_kmh","channels.mobility_kmph","scenario.mobility.speed_kmh"], 0);
speedMs = speedKmh / 3.6;
fcHz = localCfgNumber(scenarioCfg, ...
    ["frequency.center_frequency_hz","global_radio_scope.carrier_frequency_hz","channels.carrier_frequency_hz"], 4e9);
scsKHz = localCfgNumber(scenarioCfg, ...
    ["frame.scs_khz","bwp.dl.scs_khz","phy.numerology.scs_kHz"], NaN);
scsHz = localCfgNumber(scenarioCfg, "global_radio_scope.scs_hz", NaN);
if ~isfinite(scsKHz) && isfinite(scsHz)
    scsKHz = scsHz / 1e3;
end
slotDurationMs = localCfgNumber(scenarioCfg, "frame_timing.slot_duration_ms", localSlotDurationFromSCS(scsKHz));

[totalSlots, durationStatus] = localObservedSlotSpan(dlTrials, scenarioCfg);
runDurationMs = totalSlots * slotDurationMs;
runDurationS = runDurationMs / 1e3;
travelM = speedMs * runDurationS;
if speedMs > 0 && fcHz > 0
    dopplerHz = speedMs * fcHz / 299792458;
    coherenceMs = 0.423 / max(dopplerHz, eps) * 1e3;
else
    dopplerHz = 0;
    coherenceMs = Inf;
end
coherenceIntervals = runDurationMs / coherenceMs;

trialCount = height(dlTrials);
dlPerUE = localMinDLTrialsPerUE(dlTrials);
failCount = localFailCount(dlTrials);
passCount = localPassCount(dlTrials);
bler = localSafeDivide(failCount, passCount + failCount);
[ciLow, ciHigh] = localWilsonCI(failCount, passCount + failCount);
ciWidth = ciHigh - ciLow;
tpCv = localCoefficientOfVariation(localColumnFirstAvailable(dlTrials, ["Goodput_Mbps","Throughput_Mbps"]));

minCoherence = 200;
minDLPerUE = 200;
maxCIWidth = 0.10;
maxTPCv = 0.15;
coherenceOk = isfinite(coherenceIntervals) && coherenceIntervals >= minCoherence;
trialCountOk = isfinite(dlPerUE) && dlPerUE >= minDLPerUE;
blerCiOk = isfinite(ciWidth) && ciWidth <= maxCIWidth;
tpCvOk = isfinite(tpCv) && tpCv <= maxTPCv;
mobilityAdequate = coherenceOk && trialCountOk;
statAdequate = blerCiOk && tpCvOk;
overallAdequate = mobilityAdequate && statAdequate;

reasons = strings(0, 1);
if ~coherenceOk
    reasons(end+1, 1) = sprintf("coherence_intervals=%.3g_need_%d", coherenceIntervals, minCoherence); %#ok<AGROW>
end
if ~trialCountOk
    reasons(end+1, 1) = sprintf("dl_trials_per_ue=%.3g_need_%d", dlPerUE, minDLPerUE); %#ok<AGROW>
end
if ~blerCiOk
    reasons(end+1, 1) = sprintf("bler_ci95_width=%.3g_limit_%.3g", ciWidth, maxCIWidth); %#ok<AGROW>
end
if ~tpCvOk
    reasons(end+1, 1) = sprintf("throughput_cv=%.3g_limit_%.3g", tpCv, maxTPCv); %#ok<AGROW>
end
if overallAdequate
    honestLabel = "ADEQUATE_MOBILITY_STUDY";
else
    honestLabel = "SHORT_OR_SPARSE_DIAGNOSTIC";
end
if isempty(reasons)
    reasonText = "";
else
    reasonText = strjoin(reasons, ";");
end

r = struct();
r.UESpeed_kmh = speedKmh;
r.CarrierFrequency_Hz = fcHz;
r.SCS_kHz = scsKHz;
r.SlotDuration_ms = slotDurationMs;
r.MaxDoppler_Hz = dopplerHz;
r.CoherenceTime_ms = coherenceMs;
r.TotalSlots = totalSlots;
r.RunDuration_ms = runDurationMs;
r.UETravel_m = travelM;
r.NumCoherenceIntervals = coherenceIntervals;
r.NumDLTrials = trialCount;
r.NumDLTrials_perUE = dlPerUE;
r.DLPassCount = passCount;
r.DLFailCount = failCount;
r.DL_BLER = bler;
r.DL_BLER_CI95_Low = ciLow;
r.DL_BLER_CI95_High = ciHigh;
r.DL_BLER_CI95_Width = ciWidth;
r.DL_Throughput_CV = tpCv;
r.CoherenceOk = coherenceOk;
r.TrialCountOk = trialCountOk;
r.BLERCIOk = blerCiOk;
r.ThroughputCVOk = tpCvOk;
r.MobilityAdequate = mobilityAdequate;
r.StatAdequate = statAdequate;
r.OverallAdequate = overallAdequate;
r.HonestLabel = honestLabel;
r.AdequacyReasons = reasonText;
r.EvidenceClass = "RUNTIME_DERIVED";
r.SourceArtifact = "air_interface/csv/dl_pdsch_trials.csv";
r.Status = durationStatus;

mobReport = struct2table(r, "AsArray", true);
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "mobility_adequacy_report.csv"), mobReport);
end

function [nSlots, status] = localObservedSlotSpan(T, cfg)
status = "observed_dl_trial_slot_span";
nSlots = NaN;
if istable(T) && height(T) > 0 && any(string(T.Properties.VariableNames) == "Slot")
    slots = localToDouble(T.Slot);
    slots = slots(isfinite(slots));
    if ~isempty(slots)
        nSlots = max(slots) - min(slots) + 1;
        return;
    end
end
nSlots = localCfgNumber(cfg, ["run_control.total_slots","simulation.n_slots","run.slot_steps"], NaN);
if isfinite(nSlots)
    status = "configured_slot_count_no_dl_slot_span";
else
    nSlots = 0;
    status = "no_runtime_or_configured_slot_count";
end
end

function n = localMinDLTrialsPerUE(T)
n = NaN;
if ~(istable(T) && height(T) > 0)
    return;
end
if any(string(T.Properties.VariableNames) == "UEIndex")
    ue = localToDouble(T.UEIndex);
elseif any(string(T.Properties.VariableNames) == "UEID")
    ue = localToDouble(T.UEID);
else
    n = height(T);
    return;
end
ue = ue(isfinite(ue));
ids = unique(ue);
if isempty(ids)
    return;
end
counts = zeros(numel(ids), 1);
for i = 1:numel(ids)
    counts(i) = sum(ue == ids(i));
end
n = min(counts);
end

function dt = localSlotDurationFromSCS(scsKHz)
if ~isfinite(scsKHz) || scsKHz <= 0
    dt = 0.5;
    return;
end
mu = round(log2(scsKHz / 15));
if ~isfinite(mu)
    dt = 0.5;
else
    dt = 1 / (2 ^ mu);
end
end

function value = localCfgNumber(cfg, paths, defaultValue)
value = defaultValue;
for p = string(paths)
    v = localCfgRaw(cfg, p, []);
    if isnumeric(v) || islogical(v)
        if isscalar(v) && isfinite(double(v))
            value = double(v);
            return;
        end
    elseif ischar(v) || isstring(v)
        x = str2double(string(v));
        if isfinite(x)
            value = x;
            return;
        end
    end
end
end

function v = localCfgRaw(cfg, path, defaultValue)
v = defaultValue;
try
    if isa(cfg, "sixgr.lls6g.config.ScenarioConfig")
        v = cfg.get(path, defaultValue);
        return;
    end
catch
end
try
    v = sixgr.util.structGet(cfg, path, defaultValue);
catch
    v = defaultValue;
end
end

function x = localColumnFirstAvailable(T, names)
x = NaN(height(T), 1);
if ~(istable(T) && height(T) > 0)
    return;
end
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        xi = localToDouble(T.(name));
        mask = ~isfinite(x) & isfinite(xi);
        x(mask) = xi(mask);
    end
end
end

function n = localPassCount(T)
n = 0;
if ~(istable(T) && height(T) > 0 && any(string(T.Properties.VariableNames) == "CRCPass"))
    return;
end
s = lower(strtrim(string(T.CRCPass)));
n = sum(s == "1" | s == "true" | s == "pass");
end

function n = localFailCount(T)
n = 0;
if ~(istable(T) && height(T) > 0 && any(string(T.Properties.VariableNames) == "CRCPass"))
    return;
end
s = lower(strtrim(string(T.CRCPass)));
n = sum(s == "0" | s == "false" | s == "fail");
end

function [lo, hi] = localWilsonCI(fails, total)
if ~isfinite(total) || total <= 0
    lo = NaN;
    hi = NaN;
    return;
end
z = 1.96;
p = localSafeDivide(fails, total);
den = 1 + z^2 / total;
center = (p + z^2 / (2 * total)) / den;
half = z * sqrt((p * (1 - p) / total) + (z^2 / (4 * total^2))) / den;
lo = max(0, center - half);
hi = min(1, center + half);
end

function cv = localCoefficientOfVariation(x)
x = x(isfinite(x));
if isempty(x)
    cv = NaN;
    return;
end
m = mean(x);
if abs(m) < eps
    cv = NaN;
else
    cv = std(x) / abs(m);
end
end

function y = localSafeDivide(a, b)
if ~isfinite(a) || ~isfinite(b) || b == 0
    y = NaN;
else
    y = a ./ b;
end
end

function x = localToDouble(v)
if isnumeric(v) || islogical(v)
    x = double(v);
elseif iscell(v)
    x = str2double(string(v));
else
    x = str2double(string(v));
end
x = x(:);
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:analytics:buildMobilityAdequacyReport:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
