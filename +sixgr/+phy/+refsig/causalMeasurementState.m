function out = causalMeasurementState(measurements, consumerSlot, varargin)
%CAUSALMEASUREMENTSTATE Select reference-signal measurements causally.
%
% Measurements must carry at least SignalType, ProducerSlot, AvailableSlot
% and Valid fields/columns. A consumer may use only rows with
% AvailableSlot <= consumerSlot and age <= MaxAgeSlots.

opt = struct( ...
    "SignalType", "", ...
    "TargetType", "", ...
    "TargetId", NaN, ...
    "MaxAgeSlots", inf);
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:phy:refsig:CausalMeasurementBadNV", ...
            "Name-value arguments must come in pairs.");
    end
    for ii = 1:2:numel(varargin)
        key = lower(strtrim(string(varargin{ii})));
        switch key
            case "signaltype"
                opt.SignalType = string(varargin{ii + 1});
            case "targettype"
                opt.TargetType = string(varargin{ii + 1});
            case "targetid"
                opt.TargetId = double(varargin{ii + 1});
            case "maxageslots"
                opt.MaxAgeSlots = double(varargin{ii + 1});
            otherwise
                error("sixgr:phy:refsig:CausalMeasurementUnknownOption", ...
                    "Unknown causal measurement option '%s'.", key);
        end
    end
end

T = localToTable(measurements);
consumerSlot = double(consumerSlot);
if ~(isscalar(consumerSlot) && isfinite(consumerSlot))
    error("sixgr:phy:refsig:CausalMeasurementBadConsumerSlot", ...
        "consumerSlot must be a finite scalar.");
end
maxAge = double(opt.MaxAgeSlots);
if ~(isscalar(maxAge) && isfinite(maxAge) && maxAge >= 0)
    maxAge = inf;
end

out = localEmptyResult(consumerSlot, maxAge);
if isempty(T) || height(T) == 0
    out.Status = "no_measurements";
    out.Blocker = "no_reference_signal_measurements_available";
    return;
end

mask = true(height(T), 1);
if strlength(strtrim(opt.SignalType)) > 0
    mask = mask & upper(strtrim(localStringColumn(T, "SignalType", ""))) == upper(strtrim(opt.SignalType));
end
if strlength(strtrim(opt.TargetType)) > 0
    mask = mask & upper(strtrim(localStringColumn(T, "TargetType", ""))) == upper(strtrim(opt.TargetType));
end
if isfinite(opt.TargetId)
    mask = mask & abs(localNumericColumn(T, "TargetId", NaN) - double(opt.TargetId)) < 1e-9;
end
if ~any(mask)
    out.Status = "no_matching_measurement";
    out.Blocker = "no_reference_signal_measurement_for_signal_or_target";
    return;
end

candidate = T(mask, :);
valid = localLogicalColumn(candidate, "Valid", false);
availableSlot = localNumericColumn(candidate, "AvailableSlot", NaN);
producerSlot = localNumericColumn(candidate, "ProducerSlot", NaN);
notFuture = valid & isfinite(availableSlot) & availableSlot <= consumerSlot;
if ~any(notFuture)
    out.Status = "future_measurement_not_available";
    out.Blocker = "reference_signal_measurement_available_after_consumer_slot";
    futureSlots = availableSlot(valid & isfinite(availableSlot));
    if ~isempty(futureSlots)
        out.NextAvailableSlot = min(futureSlots);
    end
    return;
end

age = consumerSlot - producerSlot;
fresh = notFuture & isfinite(age) & age >= 0 & age <= maxAge;
if ~any(fresh)
    out.Status = "stale";
    out.Blocker = "reference_signal_measurement_age_exceeds_limit";
    ageVals = age(notFuture & isfinite(age));
    if ~isempty(ageVals)
        out.MinAgeSlots = min(ageVals);
    end
    return;
end

freshIdx = find(fresh);
[~, bestRel] = max(availableSlot(freshIdx));
bestIdx = freshIdx(bestRel);
selected = candidate(bestIdx, :);
out.Usable = true;
out.Status = "usable";
out.Blocker = "";
out.SignalType = string(localScalarTableValue(selected, "SignalType", ""));
out.TargetType = string(localScalarTableValue(selected, "TargetType", ""));
out.TargetId = double(localScalarTableValue(selected, "TargetId", NaN));
out.ProducerSlot = double(localScalarTableValue(selected, "ProducerSlot", NaN));
out.AvailableSlot = double(localScalarTableValue(selected, "AvailableSlot", NaN));
out.AgeSlots = double(consumerSlot - out.ProducerSlot);
out.MeasurementId = string(localScalarTableValue(selected, "MeasurementId", ""));
out.SourceSignal = string(localScalarTableValue(selected, "SourceSignal", out.SignalType));
out.MeasurementSource = string(localScalarTableValue(selected, "MeasurementSource", ""));
out.SelectedRow = selected;
end

function out = localEmptyResult(consumerSlot, maxAge)
out = struct( ...
    "Usable", false, ...
    "Status", "unresolved", ...
    "Blocker", "", ...
    "SignalType", "", ...
    "TargetType", "", ...
    "TargetId", NaN, ...
    "ProducerSlot", NaN, ...
    "AvailableSlot", NaN, ...
    "ConsumerSlot", double(consumerSlot), ...
    "AgeSlots", NaN, ...
    "MaxAgeSlots", double(maxAge), ...
    "MeasurementId", "", ...
    "SourceSignal", "", ...
    "MeasurementSource", "", ...
    "NextAvailableSlot", NaN, ...
    "MinAgeSlots", NaN, ...
    "SelectedRow", table());
end

function T = localToTable(x)
if istable(x)
    T = x;
elseif isstruct(x)
    if isempty(x)
        T = table();
    else
        T = struct2table(x(:), "AsArray", true);
    end
else
    T = table();
end
end

function values = localStringColumn(T, name, defaultValue)
if ismember(string(name), string(T.Properties.VariableNames))
    values = string(T.(char(name)));
else
    values = repmat(string(defaultValue), height(T), 1);
end
values = values(:);
end

function values = localNumericColumn(T, name, defaultValue)
if ismember(string(name), string(T.Properties.VariableNames))
    values = double(T.(char(name)));
else
    values = repmat(double(defaultValue), height(T), 1);
end
values = values(:);
end

function values = localLogicalColumn(T, name, defaultValue)
if ismember(string(name), string(T.Properties.VariableNames))
    values = logical(T.(char(name)));
else
    values = repmat(logical(defaultValue), height(T), 1);
end
values = values(:);
end

function value = localScalarTableValue(T, name, defaultValue)
value = defaultValue;
if ~(istable(T) && height(T) >= 1 && ismember(string(name), string(T.Properties.VariableNames)))
    return;
end
raw = T.(char(name));
if isempty(raw)
    return;
end
value = raw(1);
end
