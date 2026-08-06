function report = validateNoiseDomainEvidence(T, varargin)
%VALIDATENOISEDOMAINEVIDENCE Enforce explicit, non-mixed PHY noise planes.
%   REPORT = VALIDATENOISEDOMAINEVIDENCE(T) validates the trial-level
%   relationship between injected sample noise, OFDM grid noise,
%   pre-equalization noise, post-equalization noise and LLR noise.  It never
%   converts post-equalization variance back into a configured SNR.

p = inputParser;
p.addParameter("ThrowOnFailure", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("RequireRows", true, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
p.addParameter("Tolerance_dB", 1e-6, @(x)isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0);
p.parse(varargin{:});
opt = p.Results;

checks = strings(0,1);
status = strings(0,1);
maxError = zeros(0,1);
reason = strings(0,1);

    function add(name, ok, err, why)
        checks(end+1,1) = string(name); %#ok<AGROW>
        if logical(ok)
            status(end+1,1) = "PASS"; %#ok<AGROW>
        else
            status(end+1,1) = "FAIL"; %#ok<AGROW>
        end
        maxError(end+1,1) = double(err); %#ok<AGROW>
        reason(end+1,1) = string(why); %#ok<AGROW>
    end

if ~istable(T)
    add("input_is_table", false, NaN, "noise evidence input is not a table");
    report = localFinish();
    return;
end
add("input_is_table", true, 0, "");

if height(T) == 0
    add("evidence_rows_present", ~logical(opt.RequireRows), NaN, ...
        "noise-domain evidence contains no executed trial rows");
    report = localFinish();
    return;
end
add("evidence_rows_present", true, 0, "");

required = [ ...
    "Direction","NoiseVariance","ReplaySampleNoiseVariance", ...
    "ReplayGridNoiseVariance","ReceiverInputSampleNoiseVariance", ...
    "PreEqualizationNoiseVariance","PostEqualizationNoiseVariance", ...
    "LLRNoiseVariance","SampleToGridNoiseVarianceGain", ...
    "ReplaySampleNoiseVarianceDomain","ReplayGridNoiseVarianceDomain", ...
    "ReceiverInputSampleNoiseVarianceDomain", ...
    "PreEqualizationNoiseVarianceDomain","PostEqualizationNoiseVarianceDomain", ...
    "LLRNoiseVarianceDomain","NoiseVarianceAliasOf", ...
    "ReplaySampleNoiseVarianceSource","ReplayGridNoiseVarianceSource", ...
    "ReceiverInputSampleNoiseVarianceSource", ...
    "PreEqualizationNoiseVarianceSource","PostEqualizationNoiseVarianceSource", ...
    "LLRNoiseVarianceSource","SNRReferencePlane", ...
    "AppliedNoiseSNR_dB","AppliedNoiseSNRSource", ...
    "DesiredSignalPowerBeforeNoise","DesiredSignalPowerBeforeNoiseDomain", ...
    "SignalEnergyPerOccupiedRE"];
missing = required(~ismember(required, string(T.Properties.VariableNames)));
add("required_columns", isempty(missing), double(numel(missing)), ...
    localJoinReason("missing columns", missing));
if ~isempty(missing)
    report = localFinish();
    return;
end

domainColumns = [ ...
    "ReplaySampleNoiseVarianceDomain","ReplayGridNoiseVarianceDomain", ...
    "ReceiverInputSampleNoiseVarianceDomain", ...
    "PreEqualizationNoiseVarianceDomain","PostEqualizationNoiseVarianceDomain", ...
    "LLRNoiseVarianceDomain","DesiredSignalPowerBeforeNoiseDomain"];
sourceColumns = [ ...
    "ReplaySampleNoiseVarianceSource","ReplayGridNoiseVarianceSource", ...
    "ReceiverInputSampleNoiseVarianceSource", ...
    "PreEqualizationNoiseVarianceSource","PostEqualizationNoiseVarianceSource", ...
    "LLRNoiseVarianceSource","AppliedNoiseSNRSource"];
blankDomains = false(height(T),1);
for name = domainColumns
    blankDomains = blankDomains | strlength(strtrim(string(T.(name)))) == 0;
end
add("domains_are_explicit", ~any(blankDomains), double(nnz(blankDomains)), ...
    "one or more executed rows omit a noise or signal domain");
blankSources = false(height(T),1);
for name = sourceColumns
    blankSources = blankSources | strlength(strtrim(string(T.(name)))) == 0;
end
add("sources_are_explicit", ~any(blankSources), double(nnz(blankSources)), ...
    "one or more executed rows omit noise provenance");

preSampleDomain = string(T.ReplaySampleNoiseVarianceDomain) == ...
    "receiver_sample_waveform_pre_composite_front_end";
signalDomain = string(T.DesiredSignalPowerBeforeNoiseDomain) == ...
    "receiver_sample_waveform_pre_noise_pre_composite_front_end";
receiverInputDomain = string(T.ReceiverInputSampleNoiseVarianceDomain) == ...
    "receiver_sample_waveform_post_composite_front_end";
add("sample_planes_are_separated", all(preSampleDomain & signalDomain & receiverInputDomain), ...
    double(nnz(~(preSampleDomain & signalDomain & receiverInputDomain))), ...
    "pre-front-end signal/noise and receiver-input noise were not kept on distinct declared planes");

sampleN = double(T.ReplaySampleNoiseVariance);
gridN = double(T.ReplayGridNoiseVariance);
gain = double(T.SampleToGridNoiseVarianceGain);
validTransform = isfinite(sampleN) & sampleN >= 0 & isfinite(gridN) & gridN >= 0 & ...
    isfinite(gain) & gain > 0;
transformError = NaN(height(T),1);
transformError(validTransform) = abs(gridN(validTransform) - ...
    sampleN(validTransform) .* gain(validTransform)) ./ ...
    max(abs(gridN(validTransform)), realmin);
transformOk = validTransform & transformError <= 1e-9;
add("sample_to_grid_transform", all(transformOk), localFiniteMax(transformError), ...
    "replay grid variance is not the calibrated OFDM transform of the same pre-front-end sample variance");

applied = double(T.AppliedNoiseSNR_dB);
referencePlane = string(T.SNRReferencePlane);
sampleRows = referencePlane == "receiver_sample_waveform_pre_composite_front_end";
gridRows = referencePlane == "occupied_resource_grid_re_after_ofdm_demodulation";
expected = NaN(height(T),1);
signalPower = double(T.DesiredSignalPowerBeforeNoise);
signalEnergy = double(T.SignalEnergyPerOccupiedRE);
okSample = sampleRows & isfinite(signalPower) & signalPower > 0 & sampleN > 0;
expected(okSample) = 10 .* log10(signalPower(okSample) ./ sampleN(okSample));
okGrid = gridRows & isfinite(signalEnergy) & signalEnergy > 0 & gridN > 0;
expected(okGrid) = 10 .* log10(signalEnergy(okGrid) ./ gridN(okGrid));
snrError = abs(applied - expected);
snrRows = sampleRows | gridRows;
snrOk = snrRows & isfinite(applied) & isfinite(expected) & ...
    snrError <= double(opt.Tolerance_dB);
add("applied_snr_same_plane_identity", all(snrOk), localFiniteMax(snrError), ...
    "AppliedNoiseSNR_dB does not equal signal/noise evidence from its declared reference plane");

direction = upper(strtrim(string(T.Direction)));
alias = string(T.NoiseVarianceAliasOf);
legacy = double(T.NoiseVariance);
expectedLegacy = NaN(height(T),1);
dl = direction == "DL";
ul = direction == "UL";
expectedLegacy(dl) = double(T.PostEqualizationNoiseVariance(dl));
expectedLegacy(ul) = double(T.PreEqualizationNoiseVariance(ul));
expectedAlias = strings(height(T),1);
expectedAlias(dl) = "PostEqualizationNoiseVariance";
expectedAlias(ul) = "PreEqualizationNoiseVariance";
aliasError = abs(legacy - expectedLegacy);
aliasOk = (dl | ul) & alias == expectedAlias & isfinite(aliasError) & ...
    aliasError <= max(1e-12, 1e-10 .* abs(expectedLegacy));
add("legacy_noise_variance_alias", all(aliasOk), localFiniteMax(aliasError), ...
    "legacy NoiseVariance is not an exact, explicitly named DL/UL compatibility alias");

if all(ismember(["PostEqSINRAvailable","PostEqSINR_dB", ...
        "PostEqSINRValueStatus"], string(T.Properties.VariableNames)))
    available = logical(T.PostEqSINRAvailable);
    sinr = double(T.PostEqSINR_dB);
    valueStatus = upper(strtrim(string(T.PostEqSINRValueStatus)));
    % Receiver-derived SINR may be conservatively bounded by qualified
    % DM-RS or decision-directed residual evidence.  Those successful
    % values retain an explicit OK_* status; use the same success-token
    % contract as validatePUSCHReceiverEvidence instead of rejecting the
    % additional provenance suffix.
    valueStatusOk = valueStatus == "OK" | startsWith(valueStatus, "OK_");
    availabilityOk = (available & isfinite(sinr) & valueStatusOk) | ...
        (~available & ~isfinite(sinr) & ~valueStatusOk);
    add("post_equalization_sinr_availability", all(availabilityOk), ...
        double(nnz(~availabilityOk)), ...
        "post-equalization SINR availability, value and status disagree");
end

report = localFinish();

    function out = localFinish()
        out = table(checks, status, maxError, reason, ...
            'VariableNames', {'Check','Status','MaxError','Reason'});
        if logical(opt.ThrowOnFailure) && any(out.Status == "FAIL")
            failed = out(out.Status == "FAIL",:);
            error("sixgr:phy:rx:NoiseDomainEvidenceInvalid", ...
                "Noise-domain evidence failed: %s", ...
                char(strjoin(failed.Check + "=" + failed.Reason, "; ")));
        end
    end
end

function value = localFiniteMax(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = max(x);
end
end

function value = localJoinReason(prefix, values)
if isempty(values)
    value = "";
else
    value = string(prefix) + ": " + strjoin(string(values), ", ");
end
end
