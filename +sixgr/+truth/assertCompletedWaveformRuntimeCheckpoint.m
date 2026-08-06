function checkpoint = assertCompletedWaveformRuntimeCheckpoint(runFolder, varargin)
%ASSERTCOMPLETEDWAVEFORMRUNTIMECHECKPOINT Validate a resumable PHY checkpoint.
%
% This guard is intentionally stricter than a file-exists check.  It only
% accepts a slot runtime that reached its configured terminal slot and whose
% persisted live counters agree exactly with the canonical raw trial tables.
% It does not claim that reporting/finalization completed.

p = inputParser;
p.addRequired("runFolder", @(x)ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("ExpectedTotalSlots", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("ExpectedSweepPointCount", NaN, @(x)isnumeric(x) && isscalar(x));
p.addParameter("RequireDL", true, @(x)islogical(x) && isscalar(x));
p.addParameter("RequireUL", true, @(x)islogical(x) && isscalar(x));
p.addParameter("ReconcileFinalizedControlCounters", false, ...
    @(x)islogical(x) && isscalar(x));
p.parse(runFolder, varargin{:});

runFolder = char(string(runFolder));
layout = sixgr.report.resultLayout(runFolder);
statusCandidates = [ ...
    string(fullfile(layout.ReportCSVDir, "live_stage_status.csv")); ...
    string(fullfile(layout.AirInterfaceDir, "reports", "csv", "live_stage_status.csv"))];
statusPath = localFirstExistingFile(statusCandidates);
if strlength(statusPath) == 0
    error("sixgr:truth:resume:MissingRuntimeCheckpoint", ...
        "No live_stage_status.csv checkpoint exists under %s.", runFolder);
end

statusT = localReadTable(statusPath);
if height(statusT) ~= 1
    error("sixgr:truth:resume:InvalidRuntimeCheckpoint", ...
        "Runtime checkpoint %s must contain exactly one row.", statusPath);
end
status = table2struct(statusT(1, :), "ToScalar", true);

runCompletion = localScalar(status, "RunCompletion");
currentSlot = localScalar(status, "CurrentSlot");
totalSlots = localScalar(status, "TotalSlots");
sweepPointCount = localScalar(status, "SweepPointCount");
sweepPointIndex = localScalar(status, "SweepPointIndex");
if runCompletion ~= 1
    error("sixgr:truth:resume:RuntimeNotCompleted", ...
        "Persisted runtime RunCompletion must be 1, observed %.17g.", runCompletion);
end
if ~(isfinite(currentSlot) && isfinite(totalSlots) && currentSlot == totalSlots && totalSlots >= 1)
    error("sixgr:truth:resume:SlotCountMismatch", ...
        "Persisted runtime slot checkpoint is incomplete: current=%.17g total=%.17g.", ...
        currentSlot, totalSlots);
end
expectedSlots = double(p.Results.ExpectedTotalSlots);
if isfinite(expectedSlots) && totalSlots ~= expectedSlots
    error("sixgr:truth:resume:ConfiguredSlotCountMismatch", ...
        "Persisted runtime total slots %.17g do not match configured total %.17g.", ...
        totalSlots, expectedSlots);
end
if ~(isfinite(sweepPointCount) && isfinite(sweepPointIndex) && ...
        sweepPointCount >= 1 && sweepPointIndex == sweepPointCount)
    error("sixgr:truth:resume:SweepCountMismatch", ...
        "Persisted runtime sweep checkpoint is incomplete: index=%.17g count=%.17g.", ...
        sweepPointIndex, sweepPointCount);
end
expectedSweepCount = double(p.Results.ExpectedSweepPointCount);
if isfinite(expectedSweepCount) && sweepPointCount ~= expectedSweepCount
    error("sixgr:truth:resume:ConfiguredSweepCountMismatch", ...
        "Persisted runtime sweep count %.17g does not match configured count %.17g.", ...
        sweepPointCount, expectedSweepCount);
end

failurePaths = [ ...
    string(fullfile(layout.MetaDir, "failure_debug_report.txt")); ...
    string(fullfile(layout.MetaDir, "failure_manifest.json")); ...
    string(fullfile(layout.ReportDir, "failure_manifest.json"))];
existingFailures = failurePaths(arrayfun(@(x)exist(char(x), "file") == 2, failurePaths));
if ~isempty(existingFailures)
    stage = lower(strtrim(string(sixgr.util.structGet(status, "Stage", ""))));
    postRuntimeStages = ["primary_sweep_ready","harq_ready","beam_ready", ...
        "rf_ready","final_bundle_ready","bundle_complete", ...
        "final_bundle_ready_resumed","bundle_complete_resumed"];
    if ~ismember(stage, postRuntimeStages)
        error("sixgr:truth:resume:RecordedRuntimeFailure", ...
            ["A failure artifact exists before a verified post-runtime " + ...
             "stage and prevents completed-runtime recovery: %s"], ...
            strjoin(existingFailures, ", "));
    end
end

dlPath = string(fullfile(layout.AirInterfaceCSVDir, "dl_pdsch_trials.csv"));
ulPath = string(fullfile(layout.AirInterfaceCSVDir, "ul_pusch_trials.csv"));
dlT = localReadRequiredDirection(dlPath, logical(p.Results.RequireDL), "DL");
ulT = localReadRequiredDirection(ulPath, logical(p.Results.RequireUL), "UL");
dlRows = height(dlT);
ulRows = height(ulT);
localAssertExactCounter(status, "DLTrialRows", dlRows);
localAssertExactCounter(status, "ULTrialRows", ulRows);
localAssertReady(status, "DLTrialsReady", logical(p.Results.RequireDL));
localAssertReady(status, "ULTrialsReady", logical(p.Results.RequireUL));

controlSpecs = [ ...
    struct("Signal", "PBCH", "StatusField", "PBCHAttemptCount", ...
        "Path", string(fullfile(layout.AirInterfaceCSVDir, "pbch_trials.csv"))); ...
    struct("Signal", "PRACH", "StatusField", "PRACHAttemptCount", ...
        "Path", string(fullfile(layout.AirInterfaceCSVDir, "prach_trials.csv"))); ...
    struct("Signal", "SRS", "StatusField", "SRSAttemptCount", ...
        "Path", string(fullfile(layout.AirInterfaceCSVDir, "srs_trials.csv"))); ...
    struct("Signal", "TRS", "StatusField", "TRSAttemptCount", ...
        "Path", string(fullfile(layout.AirInterfaceCSVDir, "trs_trials.csv")))];
controlRows = zeros(numel(controlSpecs), 1);
reconciliationRows = repmat(struct( ...
    "Signal", "", "StatusField", "", "PriorCount", NaN, ...
    "CanonicalPersistedCount", NaN, "Action", "", ...
    "EvidenceClass", "", "TimestampUTC", ""), 0, 1);
for i = 1:numel(controlSpecs)
    T = localReadTable(controlSpecs(i).Path);
    controlRows(i) = height(T);
    expectedRows = localScalar(status, controlSpecs(i).StatusField);
    if ~(isfinite(expectedRows) && expectedRows == double(controlRows(i))) && ...
            logical(p.Results.ReconcileFinalizedControlCounters) && ...
            localCanReconcileFinalizedControlCounter(status)
        mirrorPath = string(fullfile(layout.ControlCSVDir, ...
            lower(controlSpecs(i).Signal) + "_trials.csv"));
        if exist(char(mirrorPath), "file") == 2
            mirrorRows = height(localReadTable(mirrorPath));
            if mirrorRows ~= controlRows(i)
                error("sixgr:truth:resume:ControlMirrorRowCountMismatch", ...
                    ["The canonical %s runtime table contains %d rows but " ...
                     "its control mirror contains %d; finalized counter reconciliation is unsafe."], ...
                    controlSpecs(i).Signal, controlRows(i), mirrorRows);
            end
        end
        reconciliationRows(end + 1, 1) = struct( ... %#ok<AGROW>
            "Signal", string(controlSpecs(i).Signal), ...
            "StatusField", string(controlSpecs(i).StatusField), ...
            "PriorCount", double(expectedRows), ...
            "CanonicalPersistedCount", double(controlRows(i)), ...
            "Action", "status_counter_replaced_from_canonical_persisted_runtime_table", ...
            "EvidenceClass", "derived_checkpoint_metadata_reconciliation_not_phy_evidence", ...
            "TimestampUTC", string(sixgr.util.utcNowISO8601()));
        status.(char(controlSpecs(i).StatusField)) = double(controlRows(i));
    else
        localAssertExactCounter(status, controlSpecs(i).StatusField, controlRows(i));
    end
end
if ~isempty(reconciliationRows)
    statusT = struct2table(orderfields(status));
    sixgr.util.csvWriteTable(char(statusPath), statusT);
    sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
        "runtime_checkpoint_counter_reconciliation.csv"), ...
        struct2table(reconciliationRows));
end

checkpoint = struct();
checkpoint.Ok = true;
checkpoint.EvidenceClass = "persisted_completed_waveform_runtime_checkpoint_v1";
checkpoint.StatusPath = statusPath;
checkpoint.Status = status;
checkpoint.TotalSlots = totalSlots;
checkpoint.SweepPointCount = sweepPointCount;
checkpoint.DLPath = dlPath;
checkpoint.ULPath = ulPath;
checkpoint.DLTrialRows = dlRows;
checkpoint.ULTrialRows = ulRows;
checkpoint.ControlSignals = string({controlSpecs.Signal}).';
checkpoint.ControlTrialRows = controlRows;
checkpoint.ControlCounterReconciliation = struct2table(reconciliationRows);
checkpoint.FinalBundleReady = localScalar(status, "FinalBundleReady") == 1;
checkpoint.RequiresFinalizationResume = ~checkpoint.FinalBundleReady;
checkpoint.HistoricalFailureArtifacts = existingFailures(:);
if isempty(existingFailures)
    checkpoint.HistoricalFailureClassification = "none";
else
    checkpoint.HistoricalFailureClassification = ...
        "post_waveform_finalization_failure_preserved_not_runtime_blocker";
end
end

function tf = localCanReconcileFinalizedControlCounter(status)
stage = lower(strtrim(string(sixgr.util.structGet(status, "Stage", ""))));
tf = localScalar(status, "RunCompletion") == 1 && ...
    localScalar(status, "FinalBundleReady") == 1 && ...
    ismember(stage, ["final_bundle_ready","bundle_complete", ...
    "final_bundle_ready_resumed","bundle_complete_resumed"]);
end

function path = localFirstExistingFile(paths)
path = "";
for i = 1:numel(paths)
    if exist(char(paths(i)), "file") == 2
        path = paths(i);
        return;
    end
end
end

function T = localReadRequiredDirection(path, required, direction)
T = localReadTable(path);
if required && isempty(T)
    error("sixgr:truth:resume:MissingDirectionEvidence", ...
        "%s runtime recovery requires nonempty canonical trials at %s.", ...
        direction, path);
end
end

function T = localReadTable(path)
T = table();
if exist(char(path), "file") ~= 2
    return;
end
try
    T = readtable(char(path), "FileType", "text", "Delimiter", ",", ...
        "ReadVariableNames", true, "VariableNamingRule", "preserve");
catch ME
    error("sixgr:truth:resume:UnreadableEvidence", ...
        "Unable to read persisted evidence %s: %s", path, ME.message);
end
end

function value = localScalar(status, fieldName)
value = NaN;
if ~isfield(status, char(fieldName))
    return;
end
raw = status.(char(fieldName));
if islogical(raw) || isnumeric(raw)
    raw = double(raw(:));
else
    raw = str2double(string(raw(:)));
end
raw = raw(isfinite(raw));
if ~isempty(raw)
    value = raw(1);
end
end

function localAssertExactCounter(status, fieldName, observedRows)
expectedRows = localScalar(status, fieldName);
if ~(isfinite(expectedRows) && expectedRows == double(observedRows))
    error("sixgr:truth:resume:PersistedRowCountMismatch", ...
        "%s reports %.17g rows but the canonical persisted table contains %d.", ...
        fieldName, expectedRows, observedRows);
end
end

function localAssertReady(status, fieldName, required)
if ~required
    return;
end
ready = localScalar(status, fieldName);
if ready ~= 1
    error("sixgr:truth:resume:DirectionNotReady", ...
        "%s must be 1 for completed-runtime recovery; observed %.17g.", ...
        fieldName, ready);
end
end
