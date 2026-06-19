function out = exportStrictControlChannelEvidence(runFolder, cfg, varargin)
%EXPORTSTRICTCONTROLCHANNELEVIDENCE Run waveform-backed PDCCH/PUCCH evidence.
% Keep this file ASCII-only.

p = inputParser;
p.FunctionName = "sixgr.truth.exportStrictControlChannelEvidence";
addRequired(p, "runFolder", @(x) ischar(x) || isstring(x));
addRequired(p, "cfg", @(x) isstruct(x) || isobject(x));
addParameter(p, "RunId", "strict_control_channel_evidence", @(x) ischar(x) || isstring(x));
addParameter(p, "ScenarioName", "strict_control_channel_evidence", @(x) ischar(x) || isstring(x));
addParameter(p, "EnablePDCCH", true, @(x) islogical(x) || isnumeric(x));
addParameter(p, "EnablePUCCH", true, @(x) islogical(x) || isnumeric(x));
parse(p, runFolder, cfg, varargin{:});
opt = p.Results;

runFolder = char(string(runFolder));
runId = string(opt.RunId);
scenarioName = string(opt.ScenarioName);

rows = repmat(localSummaryRow(), 0, 1);
pdcch = struct();
pucch = struct();

if logical(opt.EnablePDCCH)
    try
        pdcch = sixgr.phy.pdcch.runStrictPDCCHValidation(cfg, ...
            "RunFolder", runFolder, ...
            "RunId", runId + "_pdcch", ...
            "ScenarioName", scenarioName, ...
            "WriteArtifacts", true);
        rows(end+1, 1) = localSummaryRow("PDCCH", logical(pdcch.StrictOk), ...
            height(sixgr.util.structGet(pdcch.ArtifactTables, "pdcch_trials", table())), ...
            string(sixgr.util.structGet(pdcch, "FailureReason", ""))); %#ok<AGROW>
    catch ME
        pdcch = struct("StrictOk", false, "Ok", false, "FailureReason", string(ME.identifier) + ":" + string(ME.message));
        rows(end+1, 1) = localSummaryRow("PDCCH", false, 0, string(pdcch.FailureReason)); %#ok<AGROW>
    end
end

if logical(opt.EnablePUCCH)
    try
        pucch = sixgr.phy.pucch.runStrictPUCCHValidation(cfg, ...
            "RunFolder", runFolder, ...
            "RunId", runId + "_pucch", ...
            "ScenarioName", scenarioName, ...
            "WriteArtifacts", true);
        rows(end+1, 1) = localSummaryRow("PUCCH", logical(pucch.StrictOk), ...
            height(sixgr.util.structGet(pucch.ArtifactTables, "pucch_trials", table())), ...
            string(sixgr.util.structGet(pucch, "FailureReason", ""))); %#ok<AGROW>
    catch ME
        pucch = struct("StrictOk", false, "Ok", false, "FailureReason", string(ME.identifier) + ":" + string(ME.message));
        rows(end+1, 1) = localSummaryRow("PUCCH", false, 0, string(pucch.FailureReason)); %#ok<AGROW>
    end
end

summaryT = struct2table(rows, "AsArray", true);
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);
sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "strict_control_channel_evidence_summary.csv"), summaryT);

out = struct();
out.Ok = ~isempty(rows) && all(logical(summaryT.StrictOk));
out.StrictOk = out.Ok;
out.PDCCH = pdcch;
out.PUCCH = pucch;
out.SummaryTable = summaryT;
out.FailureReason = "";
if ~logical(out.Ok)
    bad = summaryT(~logical(summaryT.StrictOk), :);
    out.FailureReason = strjoin(string(bad.SignalFamily) + ":" + string(bad.FailureReason), "; ");
end
end

function row = localSummaryRow(signalFamily, strictOk, rowCount, failureReason)
if nargin < 1
    signalFamily = "";
end
if nargin < 2
    strictOk = false;
end
if nargin < 3
    rowCount = NaN;
end
if nargin < 4
    failureReason = "";
end
row = struct( ...
    "SignalFamily", string(signalFamily), ...
    "StrictOk", logical(strictOk), ...
    "TrialRows", double(rowCount), ...
    "FailureReason", string(failureReason));
end
