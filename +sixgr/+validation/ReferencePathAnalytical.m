function out = ReferencePathAnalytical(kind, varargin)
%REFERENCEPATHANALYTICAL Trusted analytical reference calculations.

if nargin < 1
    error("sixgr:validation:MissingReferenceKind", ...
        "ReferencePathAnalytical requires a reference kind.");
end

kind = lower(strtrim(string(kind)));
const = sixgr.validation.GoldenVectorFactory("constants");

switch kind
    case "doppler_hz"
        [fcHz, speedValue, speedUnit] = localThree(varargin, NaN, NaN, "mps");
        speedMps = localSpeedMps(speedValue, speedUnit);
        out = double(fcHz) .* double(speedMps) ./ double(const.SpeedOfLight_mps);
    case "propagation_delay_s"
        distanceM = localOne(varargin, NaN);
        out = double(distanceM) ./ double(const.SpeedOfLight_mps);
    case "distance_m"
        delayS = localOne(varargin, NaN);
        out = double(delayS) .* double(const.SpeedOfLight_mps);
    case "thermal_noise_dbm"
        [bandwidthHz, noiseFigureDb] = localTwo(varargin, NaN, 0);
        out = -174.0 + 10.0 .* log10(double(bandwidthHz)) + double(noiseFigureDb);
    case "speed_mps"
        [speedValue, speedUnit] = localTwo(varargin, NaN, "kmh");
        out = localSpeedMps(speedValue, speedUnit);
    case "residual_cfo_hz"
        [injectedHz, estimatedHz] = localTwo(varargin, NaN, NaN);
        out = double(injectedHz) - double(estimatedHz);
    otherwise
        error("sixgr:validation:UnknownAnalyticalReference", ...
            "Unsupported analytical reference '%s'.", kind);
end
end

function out = localSpeedMps(speedValue, speedUnit)
speedUnit = lower(strtrim(string(speedUnit)));
switch speedUnit
    case {"kmh", "km/h", "kph"}
        out = double(speedValue) ./ 3.6;
    otherwise
        out = double(speedValue);
end
end

function out = localOne(args, defaultA)
out = defaultA;
if numel(args) >= 1
    out = args{1};
end
end

function [outA, outB] = localTwo(args, defaultA, defaultB)
outA = defaultA;
outB = defaultB;
if numel(args) >= 1
    outA = args{1};
end
if numel(args) >= 2
    outB = args{2};
end
end

function [outA, outB, outC] = localThree(args, defaultA, defaultB, defaultC)
outA = defaultA;
outB = defaultB;
outC = defaultC;
if numel(args) >= 1
    outA = args{1};
end
if numel(args) >= 2
    outB = args{2};
end
if numel(args) >= 3
    outC = args{3};
end
end
