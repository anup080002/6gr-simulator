function T=applyTrialMeasurementPhase(T,cfg)
% Separate configured measurement warm-up from delayed adaptive feedback.
% A bootstrap grant is a real PHY attempt, including when its CRC fails.
% Missing CQI/RI must not make low-SNR trials disappear from BLER statistics.
assert(istable(T),'sixgr:analytics:InvalidTrialPhaseInput','Expected a trial table.');
n=height(T);
names=string(T.Properties.VariableNames);
bootstrap=false(n,1);
if all(ismember(["AdaptiveMode","LinkAdaptationScheduled","LinkAdaptationApplied"],names))
    bootstrap=logical(T.AdaptiveMode) & logical(T.LinkAdaptationScheduled) & ...
        ~logical(T.LinkAdaptationApplied);
end
T.LinkAdaptationBootstrap=bootstrap;
warmupSlots=sixgr.util.structGet(cfg,'run.warmupSlots',[]);
if ~isempty(warmupSlots)
    validateattributes(warmupSlots,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
    warm=false(n,1);
    if warmupSlots>0 && n>0
        assert(ismember('Slot',names),'sixgr:analytics:MissingTrialSlot', ...
            'Configured slot warm-up requires the one-based runtime trial slot.');
        slots=double(T.Slot);
        validateattributes(slots,{'numeric'},{'column','real','finite','integer','positive'});
        warm=slots<=warmupSlots;
    end
    T.IsWarmupFrame=warm;
    T.MeasurementPhaseSource=repmat("configured_run_warmup_slots_one_based_trial_slot",n,1);
elseif ismember('IsWarmupFrame',names)
    % Standalone producers may already own an explicit measurement phase.
    % Preserve that observation when no run-level warm-up was supplied.
    T.MeasurementPhaseSource=repmat("provided_trial_warmup_flag",n,1);
else
    T.IsWarmupFrame=false(n,1);
    T.MeasurementPhaseSource=repmat("no_warmup_exclusion_requested",n,1);
end
end
