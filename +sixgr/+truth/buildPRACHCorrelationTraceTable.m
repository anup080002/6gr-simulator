function T = buildPRACHCorrelationTraceTable(sourceT, varargin)
%BUILDPRACHCORRELATIONTRACETABLE Build the primary runtime PRACH trace.
%
% The primary table contains only finite lag/correlation samples carrying
% explicit real_lls_evidence provenance.  Applicability, pruning and
% unavailable reasons belong in their dedicated registry artifacts and are
% never represented by synthetic or all-NaN rows in this scientific table.

p = inputParser;
p.FunctionName = "sixgr.truth.buildPRACHCorrelationTraceTable";
addParameter(p, "TruthCasePruned", false, ...
    @(x) (islogical(x) || isnumeric(x)) && isscalar(x) && ...
    isfinite(double(x)) && any(double(x) == [0 1]));
parse(p, varargin{:});

names = localVariableNames();
if logical(p.Results.TruthCasePruned) || ...
        ~(istable(sourceT) && ~isempty(sourceT))
    T = localEmptyTable(names);
    return;
end

adapted = sixgr.visual.normalizePRACHCorrelationTrace(sourceT);
if isempty(adapted) || ...
        ~all(ismember(["lag_samples","correlation_abs","truth_status"], ...
        string(adapted.Properties.VariableNames)))
    T = localEmptyTable(names);
    return;
end

valid = isfinite(double(adapted.lag_samples)) & ...
    isfinite(double(adapted.correlation_abs)) & ...
    string(adapted.truth_status) == "real_lls_evidence";
if ~any(valid)
    T = localEmptyTable(names);
    return;
end
T = adapted(valid, names);
end

function names = localVariableNames()
names = {'trial_id','preamble_index','root_sequence_index','restricted_set_type','n_cs', ...
    'zero_correlation_zone_config','lag_samples','lag_us','correlation_abs','threshold', ...
    'noise_floor','peak_lag_samples','timing_advance_samples','detection_result', ...
    'false_alarm','missed_detection','snr_db','cfo_hz','seed','truth_status'};
end

function T = localEmptyTable(names)
T = table(zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), false(0,1), ...
    false(0,1), zeros(0,1), zeros(0,1), zeros(0,1), strings(0,1), ...
    'VariableNames', names);
end
