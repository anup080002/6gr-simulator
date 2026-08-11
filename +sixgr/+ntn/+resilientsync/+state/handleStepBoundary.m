function result = handleStepBoundary(profile, observationTimesS, observationValues)
%HANDLESTEPBOUNDARY Enforce state activation without double compensation.

times = double(observationTimesS(:)); values = double(observationValues);
if size(values,1) ~= numel(times)
    error("sixgr:ntn:resilientsync:StepObservationDimensionMismatch", ...
        "Observation values must have one row per observation time.");
end
activation = double(profile.activation_time_s);
before = times < activation;
after = ~before;
straddles = any(before) && any(after);
rule = string(profile.step_handling_rule);
if straddles && rule == "reject_straddling_window"
    error("sixgr:ntn:resilientsync:ObservationStraddlesStateStep", ...
        "Observation window straddles activation of stateVersion %d.", profile.state_version);
end
segments = ones(numel(times),1);
segments(after) = 2;
result = struct("StraddlesStep", straddles, "SegmentIndex", segments, ...
    "BeforeMask", before, "AfterMask", after, "Values", values, ...
    "AppliedRule", rule, "StateVersion", double(profile.state_version));
end
