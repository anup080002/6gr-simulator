function alloc = TDRAAllocator(tdraCfg, varargin)
%TDRAAllocator Materialize truthful time-domain allocations.

opts = struct("RepetitionMode", "none", "RepetitionCount", 1);
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

startSymbol = round(double(tdraCfg.StartSymbol));
numSymbols = round(double(tdraCfg.NumSymbols));
if startSymbol < 0 || numSymbols < 1
    error("sixgr:pdsch:TDRAAllocator:BadSymbolAllocation", ...
        "StartSymbol must be >=0 and NumSymbols must be >=1.");
end

copyTable = table();
repMode = lower(string(opts.RepetitionMode));
repCount = max(1, round(double(opts.RepetitionCount)));
switch repMode
    case "none"
        copyTable = array2table([0, startSymbol, numSymbols], ...
            'VariableNames', {'SlotOffset','StartSymbol','NumSymbols'});
    case "intra_slot"
        rows = zeros(repCount, 3);
        for i = 1:repCount
            sym0 = startSymbol + (i - 1) * numSymbols;
            if sym0 + numSymbols > 14
                error("sixgr:pdsch:TDRAAllocator:IntraSlotOverflow", ...
                    "Intra-slot repetition exceeds the 14-symbol slot boundary.");
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
        error("sixgr:pdsch:TDRAAllocator:BadRepetitionMode", ...
            "Unsupported repetition mode '%s'.", repMode);
end

alloc = struct();
alloc.MappingType = char(lower(string(tdraCfg.MappingType)));
alloc.StartSymbol = double(startSymbol);
alloc.NumSymbols = double(numSymbols);
alloc.SymbolAllocation = [double(startSymbol) double(numSymbols)];
alloc.CopyTable = copyTable;
alloc.SchedulingOffsetSymbols = double(tdraCfg.SchedulingOffsetSymbols);
alloc.SchedulingOffsetSlots = double(tdraCfg.SchedulingOffsetSlots);
alloc.CrossSlotMaterializationStatus = "disabled";
end
