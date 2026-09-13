function out = causalMeasurementState(measurements, consumerSlot, varargin)
%CAUSALMEASUREMENTSTATE Select reference-signal measurements causally.
%
% Measurements must carry at least SignalType, ProducerSlot, AvailableSlot
% and Valid fields/columns. A consumer may use only rows with
% AvailableSlot <= KnownAtSlot and age at consumerSlot <= MaxAgeSlots.
% KnownAtSlot defaults to consumerSlot. A future grant can require freshness
% at transmission while using only information available at its decision.
% Sample-clock mode requires a matching receiver clock on every valid row.
% It validates chronology, not RF execution: the publisher must bind these
% coordinates from its actual observation and shared receiver completion.

opt = struct( ...
    "SignalType", "", ...
    "TargetType", "", ...
    "TargetId", NaN, ...
    "MaxAgeSlots", inf, ...
    "KnownAtSlot", [], ...
    "KnownAtSample", [], ...
    "ClockSampleRateHz", [], ...
    "ClockEpoch", [], ...
    "SlotStartSamples", []);
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
            case "knownatslot"
                opt.KnownAtSlot = double(varargin{ii + 1});
            case "knownatsample"
                opt.KnownAtSample = varargin{ii + 1};
            case "clocksampleratehz"
                opt.ClockSampleRateHz = varargin{ii + 1};
            case "clockepoch"
                opt.ClockEpoch = varargin{ii + 1};
            case "slotstartsamples"
                opt.SlotStartSamples = varargin{ii + 1};
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
knownAtSlot = opt.KnownAtSlot;
if isempty(knownAtSlot), knownAtSlot = consumerSlot; end
if ~(isscalar(knownAtSlot) && isreal(knownAtSlot) && isfinite(knownAtSlot) && knownAtSlot<=consumerSlot)
    error("sixgr:phy:refsig:CausalMeasurementBadKnowledgeSlot", ...
        "KnownAtSlot must be finite and no later than the resource-consumer slot.");
end
if ~(isscalar(maxAge) && isfinite(maxAge) && maxAge >= 0)
    maxAge = inf;
end

out = localEmptyResult(consumerSlot, maxAge);
out.KnownAtSlot = double(knownAtSlot);
sampleMode = ~isempty(opt.KnownAtSample) || ~isempty(opt.ClockSampleRateHz) || ...
    ~isempty(opt.ClockEpoch) || ~isempty(opt.SlotStartSamples);
if sampleMode
    localClockScalar(opt.KnownAtSample, true, 'KnownAtSample');
    localClockScalar(opt.ClockSampleRateHz, false, 'ClockSampleRateHz');
    localClockScalar(opt.ClockEpoch, true, 'ClockEpoch');
    boundaries=opt.SlotStartSamples;
    if ~isnumeric(boundaries) || ~isreal(boundaries) || ~isvector(boundaries) || numel(boundaries)<2 || ...
            any(~isfinite(boundaries) | boundaries<0 | boundaries~=fix(boundaries) | boundaries>flintmax) || ...
            boundaries(1)~=0 || any(diff(boundaries)<=0) || ...
            knownAtSlot<1 || knownAtSlot~=fix(knownAtSlot) || knownAtSlot>=numel(boundaries)
        error('sixgr:phy:refsig:InvalidMeasurementKnowledgeClock', ...
            'SlotStartSamples must contain exact increasing OFDM boundaries from the shared clock origin.');
    end
    boundaries=double(boundaries(:));
    if opt.KnownAtSample<boundaries(knownAtSlot) || opt.KnownAtSample>=boundaries(knownAtSlot+1)
        error('sixgr:phy:refsig:InvalidMeasurementKnowledgeClock', ...
            'KnownAtSample must be inside KnownAtSlot on the executed OFDM calendar.');
    end
    out.KnownAtSample = double(opt.KnownAtSample);
    out.ClockSampleRateHz = double(opt.ClockSampleRateHz);
    out.ClockEpoch = double(opt.ClockEpoch);
end
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
if any(valid & isfinite(availableSlot) & isfinite(producerSlot) & availableSlot < producerSlot)
    error("sixgr:phy:refsig:CausalMeasurementInvalidTiming", ...
        "A valid measurement cannot be available before its producer slot.");
end
notFuture = valid & isfinite(availableSlot) & availableSlot <= knownAtSlot;
availableSample = nan(height(candidate),1);
clockFields = ["ObservationStartSample","ObservationEndSampleExclusive", ...
    "ObservationSampleRateHz","ResultAvailableAtSample","MeasurementClockEpoch"];
hasClockFields = ismember(clockFields,string(candidate.Properties.VariableNames));
domain=localStringColumn(candidate,'MeasurementClockDomain','');
if any(valid & (ismissing(domain) | ~ismember(domain,["","slot_only","shared_receiver_sample_clock/v1"])))
    error('sixgr:phy:refsig:InvalidMeasurementClockDomain','Unknown measurement clock domain.');
end
clockValuesPresent=false(height(candidate),1);
for field=clockFields(hasClockFields)
    raw=candidate.(field);
    if ~isnumeric(raw) || ~isreal(raw) || ~iscolumn(raw) || numel(raw)~=height(candidate)
        if any(valid)
            error('sixgr:phy:refsig:InvalidMeasurementSampleClock','Receiver clock fields must be real numeric scalar columns.');
        end
    else
        clockValuesPresent=clockValuesPresent | ~isnan(raw);
    end
end
if any(valid & domain=="slot_only" & clockValuesPresent)
    error('sixgr:phy:refsig:InvalidMeasurementClockDomain', ...
        'A slot-only label cannot suppress retained sample-clock evidence.');
end
clocked=domain=="shared_receiver_sample_clock/v1" | (domain=="" & clockValuesPresent);
if sampleMode && any(valid)
    if ~all(hasClockFields)
        error('sixgr:phy:refsig:MissingMeasurementSampleClock', ...
            'Sample-clock consumers require complete receiver clock fields on valid measurements.');
    end
    values = zeros(nnz(valid),numel(clockFields));
    for k = 1:numel(clockFields)
        raw = candidate.(clockFields(k));
        if ~isnumeric(raw) || ~isreal(raw) || ~iscolumn(raw) || numel(raw)~=height(candidate)
            error('sixgr:phy:refsig:InvalidMeasurementSampleClock', ...
                'Receiver clock fields must be real numeric scalar columns.');
        end
        values(:,k)=double(raw(valid));
    end
    samples=values(:,[1 2 4]);
    if any(~isfinite(values),'all') || any(samples<0 | samples~=fix(samples) | samples>flintmax,'all') || ...
            any(values(:,2)<=values(:,1) | values(:,4)<values(:,2)) || ...
            any(values(:,3)~=double(opt.ClockSampleRateHz)) || ...
            any(values(:,5)~=double(opt.ClockEpoch))
        error('sixgr:phy:refsig:InvalidMeasurementSampleClock', ...
            'Measurement availability must follow its complete capture on the consumer sample clock.');
    end
    slots=availableSlot(valid);
    if any(~isfinite(slots) | slots<1 | slots~=fix(slots) | slots>=numel(boundaries)) || ...
            any(values(:,4)<boundaries(slots) | values(:,4)>=boundaries(slots+1))
        error('sixgr:phy:refsig:InvalidMeasurementSampleClock', ...
            'AvailableSlot must contain the result sample on the executed OFDM calendar.');
    end
    availableSample(valid)=values(:,4);
    notFuture=notFuture & availableSample<=double(opt.KnownAtSample);
elseif ~sampleMode && any(valid & clocked)
    % Clocked rows cannot silently fall back to a slot-only chronology.
    % Slot-start callers must pass that boundary's actual sample index.
    error('sixgr:phy:refsig:MeasurementSampleKnowledgeRequired', ...
        'Clocked measurements require KnownAtSample and ClockSampleRateHz.');
end
if ~any(notFuture)
    out.Status = "future_measurement_not_available";
    out.Blocker = "reference_signal_measurement_available_after_consumer_slot";
    if knownAtSlot < consumerSlot
        out.Blocker = "reference_signal_measurement_available_after_knowledge_slot";
    end
    if sampleMode
        out.Blocker = "reference_signal_measurement_not_available_at_sample_clock";
        futureSamples=availableSample(valid & isfinite(availableSample));
        if ~isempty(futureSamples), out.NextAvailableSample=min(futureSamples); end
    end
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
if sampleMode
    % Several results can arrive in one slot. Select by actual availability,
    % then source age, rather than whichever row was appended first.
    [~, order]=sortrows([availableSample(freshIdx),producerSlot(freshIdx)],[-1 -2]);
    bestIdx=freshIdx(order(1));
end
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
out.ResultAvailableAtSample=availableSample(bestIdx);
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
    "KnownAtSample", NaN, ...
    "ClockSampleRateHz", NaN, ...
    "ClockEpoch", NaN, ...
    "ResultAvailableAtSample", NaN, ...
    "NextAvailableSample", NaN, ...
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
    raw = T.(char(name));
    if ~(islogical(raw) || isnumeric(raw)) || ~isreal(raw) || ...
            ~iscolumn(raw) || numel(raw)~=height(T) || ...
            any(~isfinite(double(raw)) | (raw~=0 & raw~=1))
        error('sixgr:phy:refsig:InvalidMeasurementValidity', ...
            'Measurement Valid flags must be explicit binary scalar values, never NaN.');
    end
    values = logical(raw);
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

function localClockScalar(value,isSample,name)
if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ~isfinite(value) || ...
        (isSample && (value<0 || value~=fix(value) || value>flintmax)) || ...
        (~isSample && value<=0)
    error('sixgr:phy:refsig:InvalidMeasurementKnowledgeClock', ...
        '%s must identify an exact nonnegative sample or a positive sample rate.',name);
end
end
