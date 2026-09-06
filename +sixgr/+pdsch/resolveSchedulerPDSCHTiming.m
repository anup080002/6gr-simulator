function timing = resolveSchedulerPDSCHTiming(grant, dataSlot)
%RESOLVESCHEDULERPDSCHTIMING Preserve actual control/data slot authority.
% dataSlot and canonical *AbsoluteSlot fields are zero based. The coupled
% runtime's explicit ControlSlot alias is one based. The generic grant Slot
% field is deliberately not interpreted as a control-slot declaration.
validateattributes(dataSlot, {'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'});
control = localValue(grant, 'ControlAbsoluteSlot');
k0 = localValue(grant, 'K0');
scheduled = localValue(grant, 'ScheduledAbsoluteSlot');
decision = sixgr.util.structGet(grant,'TimingDecision',struct());
if ~isstruct(decision) || ~isscalar(decision)
    error('sixgr:pdsch:InvalidSchedulerTiming', 'TimingDecision must be a scalar struct.');
end
if ~isempty(fieldnames(decision))
    if ~isequal(sixgr.util.structGet(decision,'Valid',false),true) || ...
            string(sixgr.util.structGet(decision,'IndexConvention',"")) ~= "zero_based"
        error('sixgr:pdsch:InvalidSchedulerTiming', ...
            'PDSCH requires a valid, explicitly zero-based TimingDecision.');
    end
    control = localMerge(control, localValue(decision,'ControlAbsoluteSlot'), 'control slot');
    scheduled = localMerge(scheduled, localValue(decision,'DataAbsoluteSlot'), 'data slot');
    k0 = localMerge(k0, localValue(decision,'K0'), 'K0');
end
controlOneBased = localValue(grant,'ControlSlot');
if isfinite(controlOneBased)
    if controlOneBased < 1
        error('sixgr:pdsch:InvalidSchedulerTiming', 'ControlSlot must be one based.');
    end
    control = localMerge(control, controlOneBased - 1, 'control-slot alias');
end
if isfinite(scheduled) && scheduled ~= dataSlot
    error('sixgr:pdsch:SchedulerTimingMismatch', ...
        'Carrier data slot %d differs from scheduled data slot %d.',dataSlot,scheduled);
end
if ~isfinite(control) && isfinite(k0)
    control = dataSlot - k0;
elseif isfinite(control) && ~isfinite(k0)
    k0 = dataSlot - control;
end
if ~isfinite(control) || ~isfinite(k0)
    error('sixgr:pdsch:MissingSchedulerControlTiming', ...
        'A scheduler PDSCH requires explicit control-slot or K0 authority; do not assume K0=0.');
end
if control < 0 || k0 < 0 || control + k0 ~= dataSlot
    error('sixgr:pdsch:SchedulerTimingMismatch', ...
        'Control slot %g plus K0=%g must equal carrier data slot %g.',control,k0,dataSlot);
end
timing = struct('PDCCHAbsoluteSlot',control,'PDSCHAbsoluteSlot',double(dataSlot), ...
    'K0',k0,'IndexConvention',"zero_based", ...
    'Source',"validated_scheduler_control_data_timeline");
end

function value = localValue(input, name)
value = sixgr.util.structGet(input,name,NaN);
if isempty(value), value = NaN; end
if ~(isnumeric(value) && isscalar(value) && isreal(value) && ...
        (isnan(value) || (isfinite(value) && value >= 0 && value == fix(value))))
    error('sixgr:pdsch:InvalidSchedulerTiming', ...
        '%s must be a nonnegative integer slot value or an unset NaN.',name);
end
value = double(value);
end

function value = localMerge(value, other, name)
if isfinite(value) && isfinite(other) && value ~= other
    error('sixgr:pdsch:SchedulerTimingMismatch', ...
        'Conflicting %s declarations: %g and %g.',name,value,other);
end
if isfinite(other), value = other; end
end
