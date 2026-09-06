function [samples,source]=resolveTimingSearchGuard(cfg,sampleRateHz)
%RESOLVETIMINGSEARCHGUARD Convert the declared receiver uncertainty budget.
% This bounds a search, never supplies a measured timing offset.
validateattributes(sampleRateHz,{'numeric'},{'real','scalar','finite','positive'});
count=sixgr.util.structGet(cfg,"phy.synchronization.maxTimingUncertaintySamples",[]);
duration=sixgr.util.structGet(cfg,"phy.synchronization.maxTimingUncertainty_us",[]);
if ~isempty(count) && ~isempty(duration)
    error("sixgr:phy:sync:AmbiguousTimingSearchBudget", ...
        "Declare max_timing_uncertainty_samples or max_timing_uncertainty_us, not both.");
end
if ~isempty(duration)
    validateattributes(duration,{'numeric'},{'real','scalar','finite','nonnegative'});
    samples=ceil(double(duration)*1e-6*double(sampleRateHz));
    source="configured_receiver_timing_uncertainty_us_at_actual_sample_rate";
elseif ~isempty(count)
    validateattributes(count,{'numeric'}, ...
        {'real','scalar','finite','integer','nonnegative'});
    samples=double(count);
    source="configured_receiver_timing_uncertainty_samples";
else
    samples=0;
    source="legacy_exact_occasion_timing_no_search_budget";
end
if ~isfinite(samples) || samples>flintmax
    error("sixgr:phy:sync:InvalidTimingSearchBudget", ...
        "The receiver timing-search budget exceeds the exact sample-index range.");
end
end
