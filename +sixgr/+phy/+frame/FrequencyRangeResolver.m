classdef FrequencyRangeResolver
%FREQUENCYRANGERESOLVER Resolve standard Release-18 NR frequency subranges.
%
% The standard carrier path recognizes FR1, FR2-1, and FR2-2 only.  The
% 7.125--24.25 GHz gap and frequencies outside the NR ranges are not
% silently relabeled as an NR "FR3" carrier.

    methods (Static)
        function result = resolve(varargin)
            [centerFrequencyHz, explicitRange] = localInputs(varargin{:});

            hasCenter = ~isempty(centerFrequencyHz);
            hasRange = localHasExplicitRange(explicitRange);
            if ~hasCenter && ~hasRange
                error("sixgr:phy:frame:MissingFrequencyRange", ...
                    "Provide CenterFrequencyHz or an explicit standard FrequencyRange.");
            end

            if hasCenter
                if ~(isnumeric(centerFrequencyHz) || islogical(centerFrequencyHz)) || ...
                        ~isscalar(centerFrequencyHz) || ...
                        ~isfinite(double(centerFrequencyHz)) || ...
                        double(centerFrequencyHz) <= 0
                    error("sixgr:phy:frame:InvalidCenterFrequency", ...
                        "CenterFrequencyHz must be a positive finite numeric scalar.");
                end
                centerFrequencyHz = double(centerFrequencyHz);
                derivedRange = localRangeFromFrequency(centerFrequencyHz);
            else
                centerFrequencyHz = NaN;
                derivedRange = "";
            end

            if hasRange
                explicitRange = localNormalizeRange(explicitRange);
                if hasCenter && explicitRange ~= derivedRange
                    error("sixgr:phy:frame:FrequencyRangeMismatch", ...
                        "Center frequency %.15g Hz resolves to %s, not configured %s.", ...
                        centerFrequencyHz, char(derivedRange), char(explicitRange));
                end
                name = explicitRange;
                source = "explicit_standard_frequency_range";
            else
                name = derivedRange;
                source = "center_frequency_resolved";
            end

            [lowerHz, upperHz, upperInclusive] = localBounds(name);
            result = struct( ...
                "Name", char(name), ...
                "FrequencyRange", char(name), ...
                "FrequencyRangeSubtype", char(name), ...
                "CenterFrequencyHz", double(centerFrequencyHz), ...
                "LowerBoundHz", double(lowerHz), ...
                "UpperBoundHz", double(upperHz), ...
                "UpperBoundInclusive", logical(upperInclusive), ...
                "Source", char(source), ...
                "StandardNR", true);
        end
    end
end

function tf = localHasExplicitRange(value)
if isempty(value)
    tf = false;
elseif ischar(value)
    tf = ~isempty(strtrim(value));
elseif isstring(value) && isscalar(value)
    tf = strlength(strtrim(value)) > 0;
else
    tf = true;
end
end

function [centerFrequencyHz, explicitRange] = localInputs(varargin)
centerFrequencyHz = [];
explicitRange = "";
if isempty(varargin)
    return;
end
if numel(varargin) == 1
    value = varargin{1};
    if isnumeric(value) || islogical(value)
        centerFrequencyHz = value;
    else
        explicitRange = value;
    end
    return;
end
if mod(numel(varargin), 2) ~= 0
    error("sixgr:phy:frame:InvalidFrequencyRangeArguments", ...
        "FrequencyRangeResolver arguments must occur in name-value pairs.");
end
for i = 1:2:numel(varargin)
    name = lower(strtrim(string(varargin{i})));
    value = varargin{i + 1};
    switch name
        case {"centerfrequencyhz", "frequencyhz", "fchz"}
            centerFrequencyHz = value;
        case {"frequencyrange", "range"}
            explicitRange = value;
        otherwise
            error("sixgr:phy:frame:InvalidFrequencyRangeArguments", ...
                "Unknown FrequencyRangeResolver option '%s'.", char(name));
    end
end
end

function range = localRangeFromFrequency(centerFrequencyHz)
if centerFrequencyHz >= 410e6 && centerFrequencyHz <= 7.125e9
    range = "FR1";
elseif centerFrequencyHz >= 24.25e9 && centerFrequencyHz < 52.6e9
    range = "FR2-1";
elseif centerFrequencyHz >= 52.6e9 && centerFrequencyHz <= 71e9
    range = "FR2-2";
else
    error("sixgr:phy:frame:UnsupportedCenterFrequency", ...
        "Center frequency %.15g Hz is outside the supported standard NR " + ...
        "FR1, FR2-1, and FR2-2 ranges. Use the explicit custom-carrier API " + ...
        "for research frequencies.", centerFrequencyHz);
end
end

function range = localNormalizeRange(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:phy:frame:InvalidFrequencyRange", ...
        "FrequencyRange must be scalar text.");
end
range = upper(strtrim(string(value)));
if ~any(range == ["FR1", "FR2-1", "FR2-2"])
    error("sixgr:phy:frame:InvalidFrequencyRange", ...
        "Standard NR frequency range must be FR1, FR2-1, or FR2-2; got '%s'.", ...
        char(range));
end
end

function [lowerHz, upperHz, upperInclusive] = localBounds(range)
switch range
    case "FR1"
        lowerHz = 410e6;
        upperHz = 7.125e9;
        upperInclusive = true;
    case "FR2-1"
        lowerHz = 24.25e9;
        upperHz = 52.6e9;
        upperInclusive = false;
    case "FR2-2"
        lowerHz = 52.6e9;
        upperHz = 71e9;
        upperInclusive = true;
    otherwise
        error("sixgr:phy:frame:InvalidFrequencyRange", ...
            "Unsupported standard NR frequency range '%s'.", char(range));
end
end
