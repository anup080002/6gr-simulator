function out = publishConfigApplicationEvidence(action, varargin)
%PUBLISHCONFIGAPPLICATIONEVIDENCE Collect real runtime config-consumer evidence.
%
% Supported actions:
%   sixgr.config.publishConfigApplicationEvidence("reset", metaStruct)
%   sixgr.config.publishConfigApplicationEvidence("record", parameterId, featureFamily, ...
%       internalCfgPath, consumerFunction, appliedValue, Name, Value, ...)
%   T = sixgr.config.publishConfigApplicationEvidence("snapshot")
%   S = sixgr.config.publishConfigApplicationEvidence("context")
%   sixgr.config.publishConfigApplicationEvidence("clear")

persistent state
if isempty(state)
    state = localEmptyState();
end

if nargin < 1
    out = localRowsToTable(state.Rows);
    return;
end

cmd = lower(string(action));
switch cmd
    case "reset"
        meta = struct();
        if ~isempty(varargin) && isstruct(varargin{1})
            meta = varargin{1};
        end
        state = localEmptyState();
        state.Context = localNormalizeContext(meta);
        out = state.Context;
    case "record"
        row = localBuildRow(state.Context, state.NextSequence, varargin{:});
        state.Rows = [state.Rows; row]; %#ok<AGROW>
        state.NextSequence = state.NextSequence + 1;
        out = row;
    case "snapshot"
        out = localRowsToTable(state.Rows);
    case "context"
        out = state.Context;
    case "clear"
        state = localEmptyState();
        out = localRowsToTable(state.Rows);
    otherwise
        error("sixgr:config:publishConfigApplicationEvidence:UnknownAction", ...
            "Unsupported config application evidence action '%s'.", string(action));
end
end

function state = localEmptyState()
state = struct( ...
    "Context", localNormalizeContext(struct()), ...
    "Rows", localEmptyRows(), ...
    "NextSequence", 1);
end

function ctx = localNormalizeContext(meta)
ctx = struct( ...
    "RunId", string(sixgr.util.structGet(meta, "RunId", "")), ...
    "ScenarioID", string(sixgr.util.structGet(meta, "ScenarioID", "")), ...
    "RunTag", string(sixgr.util.structGet(meta, "RunTag", "")));
end

function rows = localEmptyRows()
rows = repmat(struct( ...
    "RunId", "", ...
    "ScenarioID", "", ...
    "RunTag", "", ...
    "TrialId", NaN, ...
    "Slot", NaN, ...
    "UEId", NaN, ...
    "ApplicationEventSequence", NaN, ...
    "ApplicationEventID", "", ...
    "ParameterId", "", ...
    "FeatureFamily", "", ...
    "InternalCfgPath", "", ...
    "ConsumerFunction", "", ...
    "RuntimeObjectType", "", ...
    "RuntimeObjectPath", "", ...
    "AppliedValue", "", ...
    "AppliedValueClass", "", ...
    "ApplicationScope", "", ...
    "EvidenceSource", "", ...
    "EvidenceStatus", "", ...
    "NotApplicableReason", "", ...
    "TimestampUTC", ""), 0, 1);
end

function row = localBuildRow(ctx, eventSequence, parameterId, featureFamily, internalCfgPath, consumerFunction, appliedValue, varargin)
p = inputParser;
p.FunctionName = "sixgr.config.publishConfigApplicationEvidence";
addRequired(p, "parameterId", @(x) strlength(string(x)) > 0);
addRequired(p, "featureFamily", @(x) strlength(string(x)) > 0);
addRequired(p, "internalCfgPath", @(x) ischar(x) || isstring(x));
addRequired(p, "consumerFunction", @(x) ischar(x) || isstring(x));
addRequired(p, "appliedValue");
addParameter(p, "TrialId", NaN, @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
addParameter(p, "Slot", NaN, @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
addParameter(p, "UEId", NaN, @(x) isempty(x) || (isscalar(x) && isnumeric(x)));
addParameter(p, "RuntimeObjectType", "", @(x) ischar(x) || isstring(x));
addParameter(p, "RuntimeObjectPath", "", @(x) ischar(x) || isstring(x));
addParameter(p, "ApplicationScope", "run", @(x) ischar(x) || isstring(x));
addParameter(p, "EvidenceSource", "runtime_consumer_call", @(x) ischar(x) || isstring(x));
addParameter(p, "EvidenceStatus", "applied_to_runtime_object", @(x) ischar(x) || isstring(x));
addParameter(p, "NotApplicableReason", "", @(x) ischar(x) || isstring(x));
parse(p, parameterId, featureFamily, internalCfgPath, consumerFunction, appliedValue, varargin{:});
opts = p.Results;

row = struct( ...
    "RunId", char(ctx.RunId), ...
    "ScenarioID", char(ctx.ScenarioID), ...
    "RunTag", char(ctx.RunTag), ...
    "TrialId", double(localScalarOrNaN(opts.TrialId)), ...
    "Slot", double(localScalarOrNaN(opts.Slot)), ...
    "UEId", double(localScalarOrNaN(opts.UEId)), ...
    "ApplicationEventSequence", double(eventSequence), ...
    "ApplicationEventID", char("config_apply_" + compose("%08d", eventSequence)), ...
    "ParameterId", char(string(opts.parameterId)), ...
    "FeatureFamily", char(string(opts.featureFamily)), ...
    "InternalCfgPath", char(string(opts.internalCfgPath)), ...
    "ConsumerFunction", char(string(opts.consumerFunction)), ...
    "RuntimeObjectType", char(string(opts.RuntimeObjectType)), ...
    "RuntimeObjectPath", char(string(opts.RuntimeObjectPath)), ...
    "AppliedValue", char(localValueToString(appliedValue)), ...
    "AppliedValueClass", char(string(class(appliedValue))), ...
    "ApplicationScope", char(string(opts.ApplicationScope)), ...
    "EvidenceSource", char(string(opts.EvidenceSource)), ...
    "EvidenceStatus", char(string(opts.EvidenceStatus)), ...
    "NotApplicableReason", char(string(opts.NotApplicableReason)), ...
    "TimestampUTC", char(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'")));
end

function value = localScalarOrNaN(value)
if isempty(value)
    value = NaN;
elseif islogical(value)
    value = double(value);
elseif ~isscalar(value)
    value = NaN;
else
    value = double(value);
end
end

function text = localValueToString(value)
if isempty(value)
    text = "";
    return;
end
if isstring(value) && isscalar(value)
    text = value;
    return;
end
if ischar(value)
    text = string(value);
    return;
end
if isnumeric(value) || islogical(value)
    if isscalar(value)
        text = string(value);
    else
        try
            text = string(jsonencode(value));
        catch
            text = "[" + strjoin(string(value(:).'), ",") + "]";
        end
    end
    return;
end
if iscellstr(value)
    text = "[" + strjoin(string(value(:).'), ",") + "]";
    return;
end
try
    text = string(jsonencode(value));
catch
    text = string(value);
end
end

function T = localRowsToTable(rows)
if isempty(rows)
    rows = localEmptyRows();
end
T = struct2table(rows, "AsArray", true);
end
