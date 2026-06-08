function timing = resolveTimingApplication(rawEstimate, varargin)
%RESOLVETIMINGAPPLICATION Preserve raw timing truth and applied correction policy.
%
%   TIMING = sixgr.phy.sync.resolveTimingApplication(RAWESTIMATE, ...)
%   normalizes a raw timing estimate into explicit raw-vs-applied metadata.
%
%   Name-value options:
%     "EstimateUsed"    : true when the estimate is considered active
%     "ApplicationMode" : "signed_waveform_shift" or "positive_crop_only"
%     "SkipRequested"   : true when timing estimation was intentionally bypassed
%     "Source"          : optional provenance token
%
%   Returned fields:
%     RawEstimate_samples
%     AppliedCorrection_samples
%     EstimateAvailable
%     EstimateUsed
%     WasClipped
%     ApplicationPolicy
%     Status
%     Source

ip = inputParser;
ip.addParameter("EstimateUsed", [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("ApplicationMode", "signed_waveform_shift", @(x) ischar(x) || isstring(x));
ip.addParameter("SkipRequested", false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("Source", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;

raw = localScalarDouble(rawEstimate);
estimateAvailable = isfinite(raw);
estimateUsed = logical(opt.SkipRequested) == false && estimateAvailable;
if ~isempty(opt.EstimateUsed)
    estimateUsed = logical(opt.EstimateUsed) && estimateAvailable;
end

mode = lower(strtrim(string(opt.ApplicationMode)));
policy = "";
status = "";
applied = 0;
wasClipped = false;

if estimateUsed
    switch mode
        case "positive_crop_only"
            applied = max(0, double(raw));
            wasClipped = (applied ~= double(raw));
            policy = "positive_crop_only_negative_offsets_preserved_but_not_applied";
            if wasClipped
                status = "available_raw_negative_not_applied";
            else
                status = "available_applied_positive_crop_only";
            end
        otherwise
            applied = double(raw);
            policy = "signed_waveform_shift_fractional_phase_ramp_supported";
            status = "available_applied_signed_correction";
    end
elseif logical(opt.SkipRequested)
    policy = "timing_estimation_bypassed_no_runtime_correction";
    status = "bypassed";
else
    policy = "timing_estimate_unavailable_no_runtime_correction";
    status = "unavailable";
end

timing = struct( ...
    "RawEstimate_samples", double(raw), ...
    "AppliedCorrection_samples", double(applied), ...
    "EstimateAvailable", logical(estimateAvailable), ...
    "EstimateUsed", logical(estimateUsed), ...
    "WasClipped", logical(wasClipped), ...
    "ApplicationPolicy", char(string(policy)), ...
    "Status", char(string(status)), ...
    "Source", char(string(opt.Source)));
end

function value = localScalarDouble(raw)
value = NaN;
if isempty(raw)
    return;
end
raw = double(raw);
if isempty(raw)
    return;
end
value = raw(1);
end
