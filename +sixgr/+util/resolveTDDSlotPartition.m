function partition = resolveTDDSlotPartition(cfg, canonicalSlot)
%RESOLVETDDSLOTPARTITION Resolve symbol-level DL/guard/UL ownership for one slot.

if nargin < 2 || ~(isnumeric(canonicalSlot) && isscalar(canonicalSlot) && isfinite(canonicalSlot))
    canonicalSlot = 1;
end

try
    fs = sixgr.phy.FrameStructureEngine(cfg);
    partition = fs.SlotPartition(canonicalSlot);
    return;
catch
    % Keep the legacy minimal resolver available for tests/utilities that
    % only provide TDD fields and no bandwidth/grid metadata.
end

symbolsPerSlot = double(sixgr.util.structGet(cfg, "phy.numerology.symbolsPerSlot", ...
    sixgr.util.structGet(cfg, "frame.symbols_per_slot", ...
    sixgr.util.structGet(cfg, "frame_timing.symbols_per_slot", 14))));
symbolsPerSlot = max(1, round(double(symbolsPerSlot)));

duplex = upper(string(sixgr.util.structGet(cfg, "frequency.duplex_mode", ...
    sixgr.util.structGet(cfg, "global_radio_scope.duplex_mode", ...
    sixgr.util.structGet(cfg, "phy.duplex.mode", ...
    sixgr.util.structGet(cfg, "scenario.duplexMode", "TDD"))))));
pattern = sixgr.util.structGet(cfg, "frame_timing.tdd_pattern", ...
    sixgr.util.structGet(cfg, "frame.tdd_pattern", ...
    sixgr.util.structGet(cfg, "phy.duplex.tddPattern", ...
    sixgr.util.structGet(cfg, "scenario.tddPattern", "DDDSU"))));
tokens = localExpandTDDPattern(pattern);
if isempty(tokens)
    tokens = 'DDDSU';
end
slotIdx = mod(max(0, round(double(canonicalSlot)) - 1), numel(tokens)) + 1;
token = upper(tokens(slotIdx));

partition = struct( ...
    "DuplexMode", char(duplex), ...
    "CanonicalSlot", double(round(double(canonicalSlot))), ...
    "SlotToken", char(token), ...
    "SlotLabel", "", ...
    "SymbolsPerSlot", double(symbolsPerSlot), ...
    "AllowDL", false, ...
    "AllowUL", false, ...
    "IsSpecialSlot", false, ...
    "DLSymbolAllocation", zeros(1, 2), ...
    "GuardSymbolAllocation", zeros(1, 2), ...
    "ULSymbolAllocation", zeros(1, 2), ...
    "SpecialSlotDLSymbols", 0, ...
    "SpecialSlotGuardSymbols", 0, ...
    "SpecialSlotULSymbols", 0);

if duplex == "FDD"
    partition.SlotLabel = "FDD_DLUL";
    partition.AllowDL = true;
    partition.AllowUL = true;
    partition.DLSymbolAllocation = [0 double(symbolsPerSlot)];
    partition.ULSymbolAllocation = [0 double(symbolsPerSlot)];
    return;
end

switch token
    case 'D'
        partition.SlotLabel = "DL";
        partition.AllowDL = true;
        partition.DLSymbolAllocation = [0 double(symbolsPerSlot)];
    case 'U'
        partition.SlotLabel = "UL";
        partition.AllowUL = true;
        partition.ULSymbolAllocation = [0 double(symbolsPerSlot)];
    otherwise
        [dlSym, guardSym, ulSym] = localResolveSpecialSlotCounts(cfg, symbolsPerSlot);
        partition.SlotLabel = "S";
        partition.IsSpecialSlot = true;
        partition.AllowDL = dlSym > 0;
        partition.AllowUL = ulSym > 0;
        partition.DLSymbolAllocation = [0 double(dlSym)];
        partition.GuardSymbolAllocation = [double(dlSym) double(guardSym)];
        partition.ULSymbolAllocation = [double(dlSym + guardSym) double(ulSym)];
        partition.SpecialSlotDLSymbols = double(dlSym);
        partition.SpecialSlotGuardSymbols = double(guardSym);
        partition.SpecialSlotULSymbols = double(ulSym);
end
end

function [dlSym, guardSym, ulSym] = localResolveSpecialSlotCounts(cfg, symbolsPerSlot)
dlSym = double(sixgr.util.structGet(cfg, "phy.duplex.specialSlot.numDLSymbols", ...
    sixgr.util.structGet(cfg, "frame.special_slot_downlink_symbols", ...
    sixgr.util.structGet(cfg, "frame_timing.special_slot_downlink_symbols", NaN))));
guardSym = double(sixgr.util.structGet(cfg, "phy.duplex.specialSlot.numGuardSymbols", ...
    sixgr.util.structGet(cfg, "frame.ul_dl_guard_symbols", ...
    sixgr.util.structGet(cfg, "frame_timing.ul_dl_guard_symbols", NaN))));
ulSym = double(sixgr.util.structGet(cfg, "phy.duplex.specialSlot.numULSymbols", ...
    sixgr.util.structGet(cfg, "frame.special_slot_uplink_symbols", ...
    sixgr.util.structGet(cfg, "frame_timing.special_slot_uplink_symbols", NaN))));

vals = [dlSym, guardSym, ulSym];
if ~all(isfinite(vals)) || any(vals < 0) || any(abs(vals - round(vals)) > eps(max(abs(vals), 1)))
    error("sixgr:util:resolveTDDSlotPartition:BadSpecialSlotConfig", ...
        "Special-slot DL/guard/UL symbol counts must be finite non-negative integers.");
end

dlSym = round(double(dlSym));
guardSym = round(double(guardSym));
ulSym = round(double(ulSym));
if (dlSym + guardSym + ulSym) ~= round(double(symbolsPerSlot))
    error("sixgr:util:resolveTDDSlotPartition:BadSpecialSlotConfig", ...
        "Special-slot DL/guard/UL symbols must sum to SymbolsPerSlot=%d, but got [%d %d %d].", ...
        round(double(symbolsPerSlot)), dlSym, guardSym, ulSym);
end
end

function tokens = localExpandTDDPattern(pattern)
if isstruct(pattern)
    dl = max(0, round(double(sixgr.util.structGet(pattern, "dlSlots", 4))));
    ul = max(0, round(double(sixgr.util.structGet(pattern, "ulSlots", 1))));
    sp = max(0, round(double(sixgr.util.structGet(pattern, "specialSlots", 0))));
    tokens = [repmat('D', 1, dl), repmat('S', 1, sp), repmat('U', 1, ul)];
    return;
end
if isstring(pattern) || ischar(pattern)
    tokens = regexprep(upper(char(string(pattern))), "[^DUS]", "");
    if isempty(tokens)
        tokens = 'DDDSU';
    end
    return;
end
if isnumeric(pattern)
    p = double(pattern(:).');
    tokens = repmat('S', 1, numel(p));
    tokens(p > 0) = 'D';
    tokens(p < 0) = 'U';
    return;
end
tokens = 'DDDSU';
end
