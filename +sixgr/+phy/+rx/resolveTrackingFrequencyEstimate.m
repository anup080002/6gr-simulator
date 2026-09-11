function [value,domain] = resolveTrackingFrequencyEstimate(raw,usingRuntime,allowLegacyCommon)
%RESOLVETRACKINGFREQUENCYESTIMATE Select received evidence, never injected CFO.
% Direction/freshness/availability checks belong to the calling receiver.
common=localNumber(raw,["EstimatedCommonFrequency_Hz","RuntimeTRSEstimatedCommonFrequency_Hz","EstimatedCommonPhaseFrequency_Hz"]);
oscillator=localNumber(raw,["EstimatedOscillatorCFO_Hz","RuntimeTRSEstimatedOscillatorCFO_Hz"]);
legacy=localNumber(raw,["EstimatedCFO_Hz","RuntimeTRSEstimatedCFO_Hz","EstimatedCFO_PreCorrection_Hz"]);
domain=string(sixgr.util.structGet(raw,'FrequencyEstimateDomain', ...
    sixgr.util.structGet(raw,'RuntimeTRSFrequencyEstimateDomain',"legacy_unspecified_frequency")));
if domain=="received_TRS_common_phase_frequency"
    assert(~isfinite(legacy) || ~isfinite(common) || abs(legacy-common)<1e-9, ...
        'sixgr:phy:rx:FrequencyEstimateDomainConflict', ...
        'A common-frequency compatibility field cannot claim a different correction.');
    assert(~isfinite(oscillator),'sixgr:phy:rx:UnseparatedOscillatorClaim', ...
        'TRS common phase does not independently measure oscillator-only CFO.');
    value=common;
elseif isfinite(oscillator)
    value=oscillator;
elseif ~usingRuntime || allowLegacyCommon
    value=legacy;
else
    value=NaN;
end
end

function value=localNumber(s,names)
value=NaN;
for name=names
    if isfield(s,name)
        candidate=double(s.(name));
        assert(isreal(candidate) && isscalar(candidate), ...
            'sixgr:phy:rx:InvalidTrackingFrequency','Frequency evidence must be a real scalar.');
        if isfinite(candidate), value=candidate; return; end
    end
end
end
