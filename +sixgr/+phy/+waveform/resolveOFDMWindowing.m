function [windowingSamples, info] = resolveOFDMWindowing(cfg, carrier)
%RESOLVEOFDMWINDOWING Resolve explicit OFDM windowing in samples.
%
% The standard waveform default is exactly zero samples.  A nonzero value
% must be explicitly configured and accepted by nrOFDMModulate; values are
% never clipped.  Explicit legacy percentage settings remain supported as
% implementation settings and are resolved to an exact sample count.

if nargin < 1 || isempty(cfg)
    cfg = struct();
end

sampleValues = localConfiguredValues(cfg, [ ...
    "phy.ofdm.windowingSamples", ...
    "phy.waveform.ofdmWindowingSamples", ...
    "phy.waveform.windowingSamples"]);
percentValues = localConfiguredValues(cfg, [ ...
    "phy.ofdm.windowingPercent", ...
    "phy.waveform.ofdmWindowingPercent", ...
    "phy.waveform.windowingPercent"]);

explicitSamples = localUniqueValue(sampleValues, "windowing sample");
explicitPercent = localUniqueValue(percentValues, "windowing percent");
source = "standard_default_zero";
if ~isempty(explicitSamples)
    windowingSamples = localSampleCount(explicitSamples);
    source = "configured_windowing_samples";
    if ~isempty(explicitPercent)
        percentSamples = localPercentSamples(explicitPercent, carrier);
        if percentSamples ~= windowingSamples
            error("sixgr:phy:frame:ConflictingWindowingConfiguration", ...
                "Configured windowingSamples=%d conflicts with the configured " + ...
                "windowingPercent resolution of %d samples.", ...
                windowingSamples, percentSamples);
        end
        source = "configured_windowing_samples_and_percent";
    end
elseif ~isempty(explicitPercent)
    windowingSamples = localPercentSamples(explicitPercent, carrier);
    source = "configured_windowing_percent";
else
    windowingSamples = 0;
end

validation = sixgr.phy.frame.OFDMSamplingResolver.validateWindowing( ...
    carrier, windowingSamples);
info = struct( ...
    "OFDMWindowingSamples", double(windowingSamples), ...
    "OFDMWindowingSource", char(source), ...
    "OFDMWindowingEnabled", logical(windowingSamples > 0), ...
    "OFDMWindowingValidation", validation);
end

function nfft = localNfft(carrier)
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
nfft = double(sampling.Nfft);
end

function values = localConfiguredValues(cfg, paths)
values = [];
for i = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(raw)
        continue;
    end
    if ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw) || ...
            ~isfinite(double(raw))
        error("sixgr:phy:frame:InvalidWindowingConfiguration", ...
            "Configured field %s must be a finite numeric scalar.", char(paths(i)));
    end
    values(end + 1) = double(raw); %#ok<AGROW>
end
end

function value = localUniqueValue(values, label)
if isempty(values)
    value = [];
    return;
end
value = values(1);
if any(values ~= value)
    error("sixgr:phy:frame:ConflictingWindowingConfiguration", ...
        "Conflicting %s aliases were configured: %s.", label, mat2str(values));
end
end

function samples = localSampleCount(value)
if value < 0 || value ~= round(value)
    error("sixgr:phy:frame:InvalidWindowingSamples", ...
        "Configured windowingSamples must be a nonnegative integer; got %.15g.", ...
        value);
end
samples = round(value);
end

function samples = localPercentSamples(value, carrier)
if value < 0 || value > 1
    error("sixgr:phy:frame:InvalidWindowingPercent", ...
        "Configured windowingPercent must lie in [0,1]; got %.15g.", value);
end
if value == 0
    samples = 0;
    return;
end
samples = round(value * localNfft(carrier));
end
