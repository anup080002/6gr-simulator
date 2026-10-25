function tf = coupledSRSResourceOpportunity(cfg, slotIdx, ueIdx, numUsers, periodSlots, schedulingPolicy, maxUEsPerSlot)
%COUPLEDSRSRESOURCEOPPORTUNITY Resolve whether a coupled-runtime SRS resource is active.
% The opportunity gate must honor configured SRS slots; multiplexing controls
% how many due UEs share an occasion, not whether the occasion itself exists.

validateattributes(slotIdx,{'numeric'},{'real','scalar','finite','integer','positive','<=',flintmax});
validateattributes(ueIdx,{'numeric'},{'real','scalar','finite','integer','positive'});
validateattributes(numUsers,{'numeric'},{'real','scalar','finite','integer','positive'});
periodSlots = sixgr.phy.srs.validateSRSPeriodOffset(periodSlots,0);
assert(strcmpi(string(sixgr.util.structGet(cfg,'phy.srs.resourceType','periodic')),'periodic'), ...
    'sixgr:truth:NonPeriodicSRSCalendar', ...
    'Periodic opportunity selection cannot authorize aperiodic or semi-persistent SRS without its control procedure.');
[configuredPeriod,offset]=sixgr.phy.srs.validateSRSPeriodOffset( ...
    sixgr.util.structGet(cfg,'phy.srs.period_slots',NaN), ...
    sixgr.util.structGet(cfg,'phy.srs.period_offset',NaN));
assert(isequal(configuredPeriod,periodSlots),'sixgr:truth:SRSCalendarMismatch', ...
    'The runtime SRS period must match the configured resource period.');
slotIdx = double(slotIdx); ueIdx = double(ueIdx); numUsers = double(numUsers);
schedulingPolicy = lower(strtrim(string(schedulingPolicy)));
maxUEsPerSlot = max(1, round(double(maxUEsPerSlot)));

[absoluteSlots0,slotWithinPeriod1]=sixgr.phy.srs.validateSRSOccasionCoordinates(periodSlots,offset, ...
    sixgr.util.structGet(cfg,"phy.srs.slotNumbers",[]), ...
    sixgr.util.structGet(cfg,"phy.srs.slotWithinPeriod1Based",[]));
% Explicit absolute selection is a subset of the native calendar, with the
% same precedence used by strict waveform generation.
if ~isempty(absoluteSlots0)
    tf=ismember(slotIdx-1,absoluteSlots0);
    return;
end
if isempty(slotWithinPeriod1), slotWithinPeriod1=offset+1; end
if ~isempty(slotWithinPeriod1)
    slotInPeriod = mod(slotIdx - 1, periodSlots) + 1;
    matchIdx = find(slotWithinPeriod1 == slotInPeriod, 1, "first");
    if isempty(matchIdx)
        tf = false;
        return;
    end
    if schedulingPolicy == "multiplex_due_users" || maxUEsPerSlot >= numUsers
        tf = true;
        return;
    end
    % Rotate by the absolute occasion ordinal. Using only matchIdx selects
    % UE 1 forever when a period contains one occasion and leaves every
    % other UE without causal SRS authority for codebook PUSCH.
    periodIndex = floor((slotIdx - 1) / periodSlots);
    occasionOrdinal0 = periodIndex * numel(slotWithinPeriod1) + ...
        (double(matchIdx) - 1);
    firstUE0 = mod(occasionOrdinal0 * maxUEsPerSlot, numUsers);
    scheduledUEs = mod(firstUE0 + (0:(maxUEsPerSlot - 1)), numUsers) + 1;
    tf = any(ueIdx == scheduledUEs);
    return;
end
end
