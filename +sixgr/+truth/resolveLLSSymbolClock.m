function [clock,dlSlot0,ulSlot0]=resolveLLSSymbolClock(cfg,dlT,ulT)
% Canonical nominal carrier-grid clock, not receiver timing or execution proof.
% Link trial producers use one-based Slot. Explicit zero-based table inputs
% must declare SlotIndexBase=0; never guess the base from the smallest row.
[~,numerology]=sixgr.time.slotDurationSec(cfg);
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(numerology);
configured=double(sixgr.util.structGet(cfg,'phy.numerology.symbolsPerSlot', ...
    sixgr.util.structGet(cfg,'frame_timing.symbols_per_slot',spec.SymbolsPerSlot)));
assert(isscalar(configured) && configured==spec.SymbolsPerSlot, ...
    'sixgr:truth:SymbolClockNumerologyMismatch','Use the canonical CP-specific symbol count.');
dlSlot0=localSlots(dlT,"DL"); ulSlot0=localSlots(ulT,"UL");
total=double(sixgr.util.structGet(cfg,'run.totalSlots', ...
    sixgr.util.structGet(cfg,'run_control.total_slots', ...
    sixgr.util.structGet(cfg,'simulation.n_slots',0))));
assert(isscalar(total) && isfinite(total) && total>=0 && total==fix(total), ...
    'sixgr:truth:InvalidSymbolClockExtent','The planned slot extent must be a nonnegative integer.');
observed=[dlSlot0;ulSlot0]; observed=observed(isfinite(observed));
if ~isempty(observed), total=max(total,max(observed)+1); end
index=(0:total*spec.SymbolsPerSlot-1).';
symbolsPerFrame=spec.SlotsPerFrame*spec.SymbolsPerSlot;
within=mod(index,symbolsPerFrame)+1;
frame=int64(floor(index/symbolsPerFrame));
offsets=spec.SymbolStartTicks(within);
ticks=frame.*sixgr.phy.frame.AbsoluteTime.TicksPerFrame+offsets(:);
duration=spec.SymbolLengthsTicks(within);
ticks=ticks(:); duration=duration(:);
clock=table(index,floor(index/spec.SymbolsPerSlot),mod(index,spec.SymbolsPerSlot), ...
    double(ticks)/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond), ...
    double(duration)/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond), ...
    zeros(size(index)),repmat("nominal_carrier_grid_CP_OFDM",size(index)), ...
    'VariableNames',{'AbsoluteSymbolIndex','Slot','SymbolInSlot', ...
    'SymbolStartTime_s','SymbolDuration_s','SlotIndexBase','SymbolTimePlane'});
end

function slots=localSlots(T,direction)
slots=nan(height(T),1);
if ~istable(T) || isempty(T), return; end
vars=string(T.Properties.VariableNames);
if ~ismember("Slot",vars), return; end
slot=localNumeric(T.Slot);
base=ones(height(T),1); % Contract of both runDL/UL throughput trial producers.
if ismember("SlotIndexBase",vars)
    base=localNumeric(T.SlotIndexBase);
    assert(all(ismember(base,[0 1])), ...
        'sixgr:truth:InvalidTrialSlotIndexBase','Declare a zero- or one-based trial slot convention.');
end
valid=isfinite(slot);
assert(all(slot(valid)==fix(slot(valid)) & slot(valid)>=base(valid)), ...
    'sixgr:truth:InvalidTrialSlotIndex','Receiver Slot must respect its declared index convention.');
slots(valid)=slot(valid)-base(valid);
if ismember("ScheduledAbsoluteSlot",vars)
    scheduled=localNumeric(T.ScheduledAbsoluteSlot);
    known=isfinite(scheduled) & valid;
    assert(all(scheduled(known)==slots(known)), ...
        'sixgr:truth:TrialSymbolClockMismatch','Trial Slot conflicts with its frozen grant absolute slot.');
end
if ~ismember("DataReceiveTimingEvidenceJSON",vars), return; end
tokens=string(T.DataReceiveTimingEvidenceJSON);
for r=find(~ismissing(tokens) & strlength(strtrim(tokens))>0).'
    try
        e=jsondecode(tokens(r));
    catch
        error('sixgr:truth:InvalidTrialSymbolClock','Malformed received-symbol clock JSON.');
    end
    assert(isstruct(e) && isscalar(e) && ...
        all(isfield(e,{'ContractVersion','Direction','DataAbsoluteSlot','SymbolAllocation'})) && ...
        string(e.ContractVersion)=="received_data_symbol_timing/v1" && ...
        string(e.Direction)==direction && valid(r) && e.DataAbsoluteSlot==slots(r), ...
        'sixgr:truth:TrialSymbolClockMismatch', ...
        'Received data clock must match this directional trial, not a shifted slot label.');
    if all(ismember(["SymbolStart","NumSymbols"],vars))
        allocation=[localNumeric(T.SymbolStart(r)),localNumeric(T.NumSymbols(r))];
        assert(isequal(double(e.SymbolAllocation(:)).',allocation), ...
            'sixgr:truth:TrialSymbolClockMismatch','Received and exported symbol allocations differ.');
    end
end
end

function values=localNumeric(raw)
if isnumeric(raw) || islogical(raw), values=double(raw);
else, values=str2double(string(raw)); end
assert(iscolumn(values),'sixgr:truth:InvalidTrialSymbolClock','One scalar clock value per trial is required.');
end
