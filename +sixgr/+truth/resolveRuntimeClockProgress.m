function progress = resolveRuntimeClockProgress(state)
%RESOLVERUNTIMECLOCKPROGRESS Radio-clock progress, not data-trial coverage.
% CompletedCanonicalSlots is advanced only by the sequential slot owner after
% control/data receive processing. It is not a successful CRC count, a saved
% checkpoint, drained receive-tail assertion, or final scenario acceptance.
% Missing legacy counters remain unknown; never infer them from DL/UL rows.
arguments
    state (1,1) struct
end
slot = localCount(state, 'CurrentSlot', 0);
total = localCount(state, 'CanonicalSlotsPerSweepPoint', 1);
done = localCount(state, 'CompletedCanonicalSlots', 0);
spf = localCount(state, 'SlotsPerFrame', 1);
sps = localCount(state, 'SymbolsPerSlot', 1);
assert(~(isfinite(done) && isfinite(slot) && done > slot) && ...
    ~(isfinite(done) && isfinite(total) && done > total) && ...
    ~(isfinite(slot) && isfinite(total) && slot > total), ...
    'sixgr:truth:InvalidRuntimeClockProgress', ...
    'Completed slots cannot exceed the current slot or scheduling horizon.');
progress = struct('CurrentSlot',slot,'TotalSlots',total, ...
    'CompletedSlots',done,'CurrentFrame',NaN,'CompletedFrames',NaN, ...
    'TotalFrames',NaN,'CompletedSymbols',NaN,'TotalSymbols',NaN, ...
    'SlotsPerFrame',spf,'SymbolsPerSlot',sps,'RunCompletion',NaN, ...
    'ClockScope',"campaign_contiguous_radio_slots_1based", ...
    'ProgressSource',"unavailable_no_completed_radio_slot_counter", ...
    'ProgressMeaning',"processed_radio_slots_not_CRC_success_checkpoint_or_final_acceptance");
if isfinite(spf)
    if isfinite(slot) && slot > 0
        progress.CurrentFrame = 1 + floor((slot-1)/spf);
    end
    if isfinite(done), progress.CompletedFrames = floor(done/spf); end
    if isfinite(total), progress.TotalFrames = ceil(total/spf); end
end
if isfinite(sps)
    if isfinite(done), progress.CompletedSymbols = done*sps; end
    if isfinite(total), progress.TotalSymbols = total*sps; end
end
if isfinite(done)
    progress.ProgressSource = "sequential_slot_owner_completed_radio_processing";
    if isfinite(total), progress.RunCompletion = done/total; end
end
end

function value = localCount(state, field, minimum)
value = sixgr.util.structGet(state, field, NaN);
assert(isnumeric(value) && isreal(value) && isscalar(value) && ...
    (isnan(value) || (isfinite(value) && value >= minimum && value == fix(value))), ...
    'sixgr:truth:InvalidRuntimeClockProgress', ...
    '%s must be a scalar integer clock count or unavailable (NaN).', field);
value = double(value);
end
