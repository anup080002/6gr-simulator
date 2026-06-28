function T = buildDeterministicTaskPlan(baseSeed, pointValues, linkTokens, varargin)
%BUILDDETERMINISTICTASKPLAN Build coarse worker-order-invariant task rows.
% Rows are campaign point/drop/link units. They can be executed serially or
% dispatched to workers because every row carries its complete immutable seed.

if nargin < 2 || isempty(pointValues)
    pointValues = [];
end
if nargin < 3 || isempty(linkTokens)
    linkTokens = "TASK";
end

p = inputParser;
p.addParameter("MaxTrials", 1, @(x) isnumeric(x) && isscalar(x));
p.addParameter("TrialsPerDrop", 1, @(x) isnumeric(x) && isscalar(x));
p.addParameter("IncludePointTasks", true, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("ExecutionGranularity", "campaign_point_drop_link", @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

pointValues = double(pointValues(:));
linkTokens = unique(upper(string(linkTokens(:))), "stable");
linkTokens(strlength(strtrim(linkTokens)) == 0) = [];
if isempty(linkTokens)
    linkTokens = "TASK";
end

maxTrials = max(0, round(double(opt.MaxTrials)));
trialsPerDrop = max(1, round(double(opt.TrialsPerDrop)));
dropCount = max(0, ceil(maxTrials / trialsPerDrop));

rows = repmat(localEmptyTaskRow(), 0, 1);
taskIndex = 0;
for pidx = 1:numel(pointValues)
    pointSeed = sixgr.util.hierarchicalSeed(baseSeed, pidx, 0, 0, "POINT");
    if logical(opt.IncludePointTasks)
        taskIndex = taskIndex + 1;
        rows(end+1, 1) = localTaskRow(taskIndex, baseSeed, pointValues(pidx), pidx, ...
            0, 0, 0, "POINT", pointSeed, pointSeed, "point_metadata", opt.ExecutionGranularity); %#ok<AGROW>
    end

    runTokens = linkTokens(linkTokens ~= "POINT");
    for dropIdx = 1:dropCount
        startTrial = (dropIdx - 1) * trialsPerDrop + 1;
        trialCount = min(trialsPerDrop, maxTrials - startTrial + 1);
        if trialCount <= 0
            continue;
        end
        for li = 1:numel(runTokens)
            token = runTokens(li);
            taskSeed = sixgr.util.hierarchicalSeed(baseSeed, pidx, dropIdx, 0, token);
            taskIndex = taskIndex + 1;
            rows(end+1, 1) = localTaskRow(taskIndex, baseSeed, pointValues(pidx), pidx, ...
                dropIdx, startTrial, trialCount, token, pointSeed, taskSeed, "point_drop_link", opt.ExecutionGranularity); %#ok<AGROW>
        end
    end
end

T = struct2table(rows, "AsArray", true);
end

function row = localTaskRow(taskIndex, baseSeed, pointValue, pointIndex, dropIndex, trialStart, trialCount, linkToken, pointSeed, taskSeed, taskKind, granularity)
row = localEmptyTaskRow();
row.TaskIndex = double(taskIndex);
row.TaskKey = "point=" + string(pointIndex) + "|drop=" + string(dropIndex) + "|link=" + upper(string(linkToken));
row.TaskKind = string(taskKind);
row.BaseSeed = double(baseSeed);
row.PointIndex = double(pointIndex);
row.PointValue = double(pointValue);
row.DropIndex = double(dropIndex);
row.TrialStartIndex = double(trialStart);
row.TrialCount = double(trialCount);
row.LinkToken = upper(string(linkToken));
row.PointSeed = double(pointSeed);
row.TaskSeed = double(taskSeed);
row.ExecutionGranularity = string(granularity);
row.SchedulingInvariant = "worker_order_independent_seed_per_task";
row.PersistencePhase = "post_run_or_disabled";
end

function row = localEmptyTaskRow()
row = struct( ...
    "TaskIndex", NaN, ...
    "TaskKey", "", ...
    "TaskKind", "", ...
    "BaseSeed", NaN, ...
    "PointIndex", NaN, ...
    "PointValue", NaN, ...
    "DropIndex", NaN, ...
    "TrialStartIndex", NaN, ...
    "TrialCount", NaN, ...
    "LinkToken", "", ...
    "PointSeed", NaN, ...
    "TaskSeed", NaN, ...
    "ExecutionGranularity", "", ...
    "SchedulingInvariant", "", ...
    "PersistencePhase", "");
end
