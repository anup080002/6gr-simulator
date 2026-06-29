function harqGain = measureHARQCombiningGain(dlTrials, runDir)
%MEASUREHARQCOMBININGGAIN Summarize observed HARQ IR soft-combining evidence.
%
% This function measures the combining path that is already produced by the
% waveform/truth runtime. If no HARQ retransmission evidence exists, it writes
% an explicit not_exercised analysis row rather than fabricating a gain.

arguments
    dlTrials table = table()
    runDir {mustBeTextScalar} = pwd
end

layout = sixgr.report.resultLayout(runDir);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);

[src, sourceArtifact] = localSelectHARQSource(dlTrials, layout);

attempts = height(src);
retxMask = localRetransmissionMask(src);
combiningMask = localCombiningMask(src);
gainVals = localColumnFirstAvailable(src, ["LLRCombiningGain_dB","HARQLLRCombiningGain_dB","CombiningGain_dB"]);
gainVals = gainVals(isfinite(gainVals));
currentOk = localBoolColumnFirstAvailable(src, ["CurrentDecodeOK","HARQCurrentDecodeOK","CurrentCRCPass"]);
combinedOk = localBoolColumnFirstAvailable(src, ["CombinedDecodeOK","HARQCombinedDecodeOK","CRCPass"]);
recoveryMask = ~currentOk & combinedOk & combiningMask;

rvVals = localColumnFirstAvailable(src, ["RV","HARQ_RV","RedundancyVersion"]);
rv0 = rvVals == 0;
rv2 = rvVals == 2;
rv3 = rvVals == 3;
rv1 = rvVals == 1;

availability = "not_exercised";
if attempts == 0
    availability = "no_runtime_harq_rows";
elseif any(combiningMask) || any(retxMask)
    availability = "runtime_harq_combining_observed";
end

r = struct();
r.TotalAttempts = attempts;
r.RetransmissionAttempts = sum(retxMask);
r.CombiningAppliedCount = sum(combiningMask);
r.CombinedRecoveryCount = sum(recoveryMask);
r.RV0Attempts = sum(rv0);
r.RV2Attempts = sum(rv2);
r.RV3Attempts = sum(rv3);
r.RV1Attempts = sum(rv1);
r.MeanLLRCombiningGain_dB = localMean(gainVals);
r.MaxLLRCombiningGain_dB = localMax(gainVals);
r.CombiningGain_dB = r.MeanLLRCombiningGain_dB;
r.Exercised = any(combiningMask) || any(retxMask);
r.EvidenceClass = "RUNTIME_DERIVED";
r.SourceArtifact = sourceArtifact;
r.Availability = availability;
r.Status = availability;

harqGain = struct2table(r, "AsArray", true);
sixgr.analytics.writeAnalysisTable(fullfile(layout.AirInterfaceCSVDir, "harq_combining_gain.csv"), harqGain);
end

function [T, sourceArtifact] = localSelectHARQSource(dlTrials, layout)
candidates = {
    fullfile(layout.HARQCSVDir, "probe_harq_packets.csv"), "harq/csv/probe_harq_packets.csv";
    fullfile(layout.HARQCSVDir, "harq_process_timeline.csv"), "harq/csv/harq_process_timeline.csv";
    fullfile(layout.HARQCSVDir, "live_harq_observation_timeline.csv"), "harq/csv/live_harq_observation_timeline.csv";
    fullfile(layout.ReportCSVDir, "live_harq_timeline.csv"), "reports/csv/live_harq_timeline.csv";
    fullfile(layout.SystemCSVDir, "system_harq_processes.csv"), "system/csv/system_harq_processes.csv"};
bestT = table();
bestArtifact = "";
bestScore = -Inf;
for i = 1:size(candidates, 1)
    T = localReadOptionalTable(candidates{i, 1});
    if height(T) > 0
        score = localHARQEvidenceScore(T);
        if score > bestScore
            bestT = T;
            bestArtifact = string(candidates{i, 2});
            bestScore = score;
        end
    end
end
if height(bestT) > 0
    T = bestT;
    sourceArtifact = bestArtifact;
    return;
end
T = dlTrials;
if isempty(T)
    T = table();
end
sourceArtifact = "air_interface/csv/dl_pdsch_trials.csv";
end

function score = localHARQEvidenceScore(T)
if ~(istable(T) && height(T) > 0)
    score = -Inf;
    return;
end
retxMask = localRetransmissionMask(T);
combiningMask = localCombiningMask(T);
currentOk = localBoolColumnFirstAvailable(T, ["CurrentDecodeOK","HARQCurrentDecodeOK","CurrentCRCPass"]);
combinedOk = localBoolColumnFirstAvailable(T, ["CombinedDecodeOK","HARQCombinedDecodeOK","CRCPass"]);
recoveryMask = ~currentOk & combinedOk & combiningMask;
gainVals = localColumnFirstAvailable(T, ["LLRCombiningGain_dB","HARQLLRCombiningGain_dB","CombiningGain_dB"]);
finiteGain = isfinite(gainVals);
score = double(height(T)) * 1e-6 + ...
    100 * double(any(recoveryMask)) + ...
    40 * double(any(combiningMask)) + ...
    20 * double(any(retxMask)) + ...
    10 * double(any(finiteGain)) + ...
    2 * double(any(combinedOk));
end

function mask = localRetransmissionMask(T)
mask = false(height(T), 1);
if height(T) == 0
    return;
end
mask = mask | localBoolColumnFirstAvailable(T, ["IsRetransmission","Retransmission","Retx"]);
rounds = localColumnFirstAvailable(T, ["HARQRound","Round","TransmissionRound"]);
mask = mask | (isfinite(rounds) & rounds > 1);
rv = localColumnFirstAvailable(T, ["RV","HARQ_RV","RedundancyVersion"]);
mask = mask | (isfinite(rv) & rv ~= 0);
prevCount = localColumnFirstAvailable(T, ["PreviousLLRCount","HARQPreviousLLRCount"]);
mask = mask | (isfinite(prevCount) & prevCount > 0);
end

function mask = localCombiningMask(T)
mask = false(height(T), 1);
if height(T) == 0
    return;
end
mask = mask | localBoolColumnFirstAvailable(T, ["HARQCombiningApplied","CombiningApplied","CombiningEnabled"]);
prevCount = localColumnFirstAvailable(T, ["PreviousLLRCount","HARQPreviousLLRCount"]);
combinedCount = localColumnFirstAvailable(T, ["CombinedLLRCount","HARQCombinedLLRCount"]);
currentCount = localColumnFirstAvailable(T, ["CurrentLLRCount","HARQCurrentLLRCount"]);
mask = mask | (isfinite(prevCount) & prevCount > 0 & isfinite(combinedCount) & combinedCount >= currentCount);
gain = localColumnFirstAvailable(T, ["LLRCombiningGain_dB","HARQLLRCombiningGain_dB","CombiningGain_dB"]);
mask = mask | isfinite(gain);
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

function x = localBoolColumnFirstAvailable(T, names)
x = false(height(T), 1);
seen = false(height(T), 1);
if ~(istable(T) && height(T) > 0)
    return;
end
for name = string(names)
    if any(string(T.Properties.VariableNames) == name)
        xi = localToBool(T.(name));
        fill = ~seen;
        x(fill) = xi(fill);
        seen(fill) = true;
    end
end
end

function T = localReadOptionalTable(pathStr)
pathStr = char(string(pathStr));
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(pathStr, "VariableNamingRule", "preserve", "TextType", "string");
catch
    try
        T = readtable(pathStr, "VariableNamingRule", "preserve");
    catch
        T = table();
    end
end
end

function y = localMean(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = mean(x);
end
end

function y = localMax(x)
x = x(isfinite(x));
if isempty(x)
    y = NaN;
else
    y = max(x);
end
end

function x = localToBool(v)
s = lower(strtrim(string(v)));
x = s == "1" | s == "true" | s == "yes" | s == "pass" | s == "ok";
x = x(:);
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
    error("sixgr:analytics:measureHARQCombiningGain:BadRunDir", "runDir must be a char vector or string scalar.");
end
end
