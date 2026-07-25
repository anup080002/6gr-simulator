function alloc = TDRAAllocator(tdraCfg, varargin)
%TDRAAllocator Materialize truthful time-domain allocations.

opts = struct( ...
    "RepetitionMode", "none", ...
    "RepetitionCount", 1, ...
    "SymbolsPerSlot", [], ...
    "SlotDirection", "DL", ...
    "DLAllowedSymbols", [], ...
    "ExecutionProfile", "study_calibration");
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

required = ["StartSymbol","NumSymbols","MappingType"];
missing = required(~isfield(tdraCfg, required));
if ~isempty(missing)
    error("sixgr:pdsch:InvalidTDRA", ...
        "PDSCH TDRA is missing: %s.", strjoin(cellstr(missing), ", "));
end
startSymbol = double(tdraCfg.StartSymbol);
numSymbols = double(tdraCfg.NumSymbols);
if ~isscalar(startSymbol) || ~isscalar(numSymbols) || ...
        any(~isfinite([startSymbol numSymbols])) || ...
        startSymbol ~= fix(startSymbol) || numSymbols ~= fix(numSymbols) || ...
        startSymbol < 0 || numSymbols < 1
    error("sixgr:pdsch:InvalidTDRA", ...
        "StartSymbol and NumSymbols must be exact nonnegative/positive integers.");
end
symbolsPerSlot = double(opts.SymbolsPerSlot);
if isempty(symbolsPerSlot)
    error("sixgr:pdsch:MissingFrameSymbolCount", ...
        "TDRA requires SymbolsPerSlot from the canonical frame/numerology state.");
end
if ~isscalar(symbolsPerSlot) || ~isfinite(symbolsPerSlot) || ...
        symbolsPerSlot ~= fix(symbolsPerSlot) || symbolsPerSlot < 1
    error("sixgr:pdsch:MissingFrameSymbolCount", ...
        "SymbolsPerSlot must be a positive integer.");
end
if startSymbol + numSymbols > symbolsPerSlot
    error("sixgr:pdsch:InvalidTDRA", ...
        "PDSCH symbols [%d,%d) exceed the %d-symbol slot.", ...
        startSymbol, startSymbol + numSymbols, symbolsPerSlot);
end
slotDirection = upper(strtrim(string(opts.SlotDirection)));
if slotDirection == "UL"
    error("sixgr:pdsch:InvalidSlotDirection", ...
        "A PDSCH allocation cannot be materialized in an uplink-only slot.");
end
if ~any(slotDirection == ["DL","FLEXIBLE"])
    error("sixgr:pdsch:InvalidSlotDirection", ...
        "Unknown slot direction '%s'.", slotDirection);
end
if ~isempty(opts.DLAllowedSymbols)
    mask = logical(opts.DLAllowedSymbols(:).');
    if numel(mask) ~= symbolsPerSlot
        error("sixgr:pdsch:InvalidSlotDirection", ...
            "DLAllowedSymbols must contain one entry per OFDM symbol.");
    end
    scheduled = startSymbol + (1:numSymbols);
    if any(~mask(scheduled))
        error("sixgr:pdsch:InvalidSlotDirection", ...
            "PDSCH TDRA includes an OFDM symbol that is not DL-capable.");
    end
end
mappingType = upper(strtrim(string(tdraCfg.MappingType)));
if ~any(mappingType == ["A","B"])
    error("sixgr:pdsch:InvalidMappingType", ...
        "PDSCH MappingType must be A or B.");
end

copyTable = table();
repMode = lower(string(opts.RepetitionMode));
repCount = double(opts.RepetitionCount);
if ~isscalar(repCount) || ~isfinite(repCount) || ...
        repCount ~= fix(repCount) || repCount < 1
    error("sixgr:pdsch:InvalidRepetitionCount", ...
        "RepetitionCount must be a positive integer.");
end
switch repMode
    case "none"
        copyTable = array2table([0, startSymbol, numSymbols], ...
            'VariableNames', {'SlotOffset','StartSymbol','NumSymbols'});
    case "intra_slot"
        rows = zeros(repCount, 3);
        for i = 1:repCount
            sym0 = startSymbol + (i - 1) * numSymbols;
            if sym0 + numSymbols > symbolsPerSlot
                error("sixgr:pdsch:IntraSlotOverflow", ...
                    "Intra-slot repetition exceeds the %d-symbol slot boundary.", ...
                    symbolsPerSlot);
            end
            rows(i, :) = [0, sym0, numSymbols];
        end
        copyTable = array2table(rows, 'VariableNames', {'SlotOffset','StartSymbol','NumSymbols'});
    case "inter_slot"
        rows = zeros(repCount, 3);
        for i = 1:repCount
            rows(i, :) = [i - 1, startSymbol, numSymbols];
        end
        copyTable = array2table(rows, 'VariableNames', {'SlotOffset','StartSymbol','NumSymbols'});
    otherwise
        error("sixgr:pdsch:UnsupportedRepetitionMode", ...
            "Unsupported repetition mode '%s'.", repMode);
end

alloc = struct();
alloc.MappingType = char(mappingType);
alloc.StartSymbol = double(startSymbol);
alloc.NumSymbols = double(numSymbols);
alloc.SymbolAllocation = [double(startSymbol) double(numSymbols)];
alloc.CopyTable = copyTable;
alloc.SchedulingOffsetSymbols = double(sixgr.util.structGet( ...
    tdraCfg, "SchedulingOffsetSymbols", 0));
alloc.SchedulingOffsetSlots = double(sixgr.util.structGet( ...
    tdraCfg, "SchedulingOffsetSlots", 0));
if repMode == "inter_slot"
    alloc.CrossSlotMaterializationStatus = "materialized_from_absolute_slot_offsets";
else
    alloc.CrossSlotMaterializationStatus = "not_requested";
end
alloc.SymbolsPerSlot = symbolsPerSlot;
end
