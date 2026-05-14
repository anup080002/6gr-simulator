function [nVar, status] = resolveULNoiseVariance(candidate, cfg, varargin)
%RESOLVEULNOISEVARIANCE Validate or explicitly derive UL receiver noise variance.
%
% Missing noise variance is a receiver-truth failure, not a low-noise
% condition. This helper centralizes the UL policy used by PUSCH, PUCCH,
% and SRS receive paths:
%   1. use a valid runtime estimate or explicit runtime metadata value
%   2. else use an explicitly provided configured derivation
%   3. else fail closed or return unavailable status

ip = inputParser;
ip.addParameter("ChannelType", "UL", @(x) ischar(x) || isstring(x));
ip.addParameter("OriginalSource", "runtime_metadata", @(x) ischar(x) || isstring(x));
ip.addParameter("StrictRequired", [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("ConfiguredNoiseVariance", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ConfiguredNoiseVarianceSource", "configured_awgn_derivation", @(x) ischar(x) || isstring(x));
ip.addParameter("ConfiguredSNR_dB", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("SignalPowerReference", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("AllowConfiguredDerivation", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

channelType = upper(strtrim(string(opt.ChannelType)));
if strlength(channelType) == 0
    channelType = "UL";
end

strictRequired = localResolveStrictRequirement(cfg, opt.StrictRequired);

status = struct( ...
    "IsValid", false, ...
    "Status", "NOT_AVAILABLE", ...
    "Source", "unavailable_missing", ...
    "Reason", "noise_variance_missing", ...
    "UsedFallback", false, ...
    "DerivedFromConfig", false, ...
    "StrictFailure", false, ...
    "ChannelType", char(channelType), ...
    "OriginalValue", [], ...
    "ReductionMethod", "", ...
    "ConfiguredDerivationAttempted", false, ...
    "ConfiguredDerivationSource", "");
nVar = NaN;

[nVarCandidate, candidateStatus] = localValidateCandidate(candidate, string(opt.OriginalSource), channelType);
status = localMergeStatus(status, candidateStatus);
if candidateStatus.IsValid
    nVar = nVarCandidate;
    return;
end

configuredSource = string(opt.ConfiguredNoiseVarianceSource);
configuredSource = strtrim(configuredSource);
if strlength(configuredSource) == 0
    configuredSource = "configured_awgn_derivation";
end

[nVarConfigured, configuredStatus] = localValidateConfiguredNoiseVariance(opt.ConfiguredNoiseVariance, configuredSource, channelType);
if configuredStatus.IsValid
    nVar = nVarConfigured;
    status = localMergeStatus(status, configuredStatus);
    return;
end

if logical(opt.AllowConfiguredDerivation)
    status.ConfiguredDerivationAttempted = true;
    status.ConfiguredDerivationSource = char(configuredSource);
    [nVarDerived, derivedStatus] = localDeriveConfiguredNoiseVariance( ...
        double(localScalarOrNaN(opt.ConfiguredSNR_dB)), ...
        double(localScalarOrNaN(opt.SignalPowerReference)), ...
        channelType);
    if derivedStatus.IsValid
        nVar = nVarDerived;
        status = localMergeStatus(status, derivedStatus);
        return;
    end
    status = localPreferUnavailableStatus(status, derivedStatus);
end

if strictRequired
    status.StrictFailure = true;
    error("sixgr:phy:ul:NoiseVarianceUnavailable", ...
        "%s RX requires a valid noise variance. Reason: %s.", char(channelType), char(string(status.Reason)));
end
end

function strictRequired = localResolveStrictRequirement(cfg, explicitValue)
if ~isempty(explicitValue)
    strictRequired = logical(explicitValue);
    return;
end
strictRequired = logical(sixgr.util.structGet(cfg, "run.strictNoiseVarianceRequired", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false));
end

function [nVar, status] = localValidateCandidate(candidate, originalSource, channelType)
source = strtrim(string(originalSource));
if strlength(source) == 0
    source = "runtime_metadata";
end
allowZero = strcmpi(source, "runtime_channel_estimate") || contains(lower(source), "perfect");
[nVar, status] = localValidateNoiseVarianceCore(candidate, source, channelType, allowZero);
end

function [nVar, status] = localValidateConfiguredNoiseVariance(candidate, configuredSource, channelType)
source = strtrim(string(configuredSource));
if strlength(source) == 0
    source = "configured_awgn_derivation";
end
allowZero = contains(lower(source), "perfect");
[nVar, status] = localValidateNoiseVarianceCore(candidate, source, channelType, allowZero);
if status.IsValid
    status.Source = "configured_awgn_derivation";
    status.DerivedFromConfig = true;
    status.ConfiguredDerivationSource = char(source);
end
end

function [nVar, status] = localDeriveConfiguredNoiseVariance(configuredSNR_dB, signalPowerReference, channelType)
status = localUnavailableStatus("unavailable_missing", "configured_noise_variance_inputs_missing", channelType);
nVar = NaN;
if ~(isfinite(configuredSNR_dB) && isfinite(signalPowerReference) && signalPowerReference > 0)
    return;
end
snrLin = 10.^(configuredSNR_dB / 10);
if ~(isfinite(snrLin) && snrLin > 0)
    status = localUnavailableStatus("unavailable_invalid_nonpositive", ...
        "configured_noise_variance_derivation_snr_nonpositive", channelType);
    return;
end
nVar = signalPowerReference / snrLin;
if ~(isfinite(nVar) && nVar > 0)
    status = localUnavailableStatus("unavailable_invalid_nonpositive", ...
        "configured_noise_variance_derivation_nonpositive", channelType);
    nVar = NaN;
    return;
end
status = localValidStatus("configured_awgn_derivation", ...
    "configured_awgn_derivation_from_signal_power_and_snr", channelType);
status.DerivedFromConfig = true;
status.ConfiguredDerivationSource = "configured_awgn_derivation";
status.OriginalValue = double(nVar);
end

function [nVar, status] = localValidateNoiseVarianceCore(candidate, source, channelType, allowZero)
nVar = NaN;
if isempty(candidate)
    status = localUnavailableStatus("unavailable_missing", "noise_variance_missing", channelType);
    return;
end
if ~isnumeric(candidate)
    status = localUnavailableStatus("unavailable_invalid_nonfinite", "noise_variance_not_numeric", channelType);
    return;
end

raw = candidate(:);
status = localUnavailableStatus("unavailable_missing", "noise_variance_missing", channelType);
status.OriginalValue = double(raw(:).');

if ~isreal(raw)
    imagPart = abs(imag(raw));
    if any(imagPart > sqrt(eps))
        status = localUnavailableStatus("unavailable_invalid_nonfinite", "noise_variance_complex_not_supported", channelType);
        status.OriginalValue = double(raw(:).');
        return;
    end
    raw = real(raw);
end

values = double(raw(:));
status.OriginalValue = values(:).';
if isempty(values)
    status = localUnavailableStatus("unavailable_missing", "noise_variance_missing", channelType);
    return;
end
if any(isnan(values))
    status = localUnavailableStatus("unavailable_invalid_nan", "noise_variance_contains_nan", channelType);
    return;
end
if any(~isfinite(values))
    status = localUnavailableStatus("unavailable_invalid_nonfinite", "noise_variance_contains_nonfinite", channelType);
    return;
end
if any(values < 0)
    status = localUnavailableStatus("unavailable_invalid_nonpositive", "noise_variance_negative", channelType);
    return;
end

positiveValues = values(values > 0);
if isempty(positiveValues)
    if allowZero && all(values == 0)
        nVar = 0;
        status = localValidStatus(source, "noise_variance_zero_with_explicit_provenance", channelType);
        status.OriginalValue = values(:).';
        if numel(values) > 1
            status.ReductionMethod = "all_zero_entries";
        end
        return;
    end
    status = localUnavailableStatus("unavailable_invalid_nonpositive", "noise_variance_nonpositive", channelType);
    status.OriginalValue = values(:).';
    return;
end

if numel(positiveValues) == 1
    nVar = positiveValues(1);
    reductionMethod = "";
else
    nVar = median(positiveValues, "omitnan");
    reductionMethod = "median_positive_entries";
end
if ~(isfinite(nVar) && nVar > 0)
    status = localUnavailableStatus("unavailable_invalid_nonpositive", "noise_variance_nonpositive_after_reduction", channelType);
    status.OriginalValue = values(:).';
    return;
end

status = localValidStatus(source, "noise_variance_valid", channelType);
status.OriginalValue = values(:).';
status.ReductionMethod = reductionMethod;
end

function status = localUnavailableStatus(source, reason, channelType)
status = struct( ...
    "IsValid", false, ...
    "Status", "NOT_AVAILABLE", ...
    "Source", char(string(source)), ...
    "Reason", char(string(reason)), ...
    "UsedFallback", false, ...
    "DerivedFromConfig", false, ...
    "StrictFailure", false, ...
    "ChannelType", char(string(channelType)), ...
    "OriginalValue", [], ...
    "ReductionMethod", "", ...
    "ConfiguredDerivationAttempted", false, ...
    "ConfiguredDerivationSource", "");
end

function status = localValidStatus(source, reason, channelType)
status = struct( ...
    "IsValid", true, ...
    "Status", "OK", ...
    "Source", char(string(source)), ...
    "Reason", char(string(reason)), ...
    "UsedFallback", false, ...
    "DerivedFromConfig", false, ...
    "StrictFailure", false, ...
    "ChannelType", char(string(channelType)), ...
    "OriginalValue", [], ...
    "ReductionMethod", "", ...
    "ConfiguredDerivationAttempted", false, ...
    "ConfiguredDerivationSource", "");
end

function status = localMergeStatus(base, override)
status = base;
fields = fieldnames(override);
for i = 1:numel(fields)
    status.(fields{i}) = override.(fields{i});
end
end

function status = localPreferUnavailableStatus(base, override)
status = base;
if logical(base.IsValid)
    return;
end
preferOverride = strcmpi(string(base.Source), "unavailable_missing");
if preferOverride || strlength(strtrim(string(base.Reason))) == 0
    status = localMergeStatus(base, override);
end
end

function value = localScalarOrNaN(raw)
if isempty(raw)
    value = NaN;
    return;
end
raw = double(raw);
raw = raw(isfinite(raw));
if isempty(raw)
    value = NaN;
else
    value = raw(1);
end
end
