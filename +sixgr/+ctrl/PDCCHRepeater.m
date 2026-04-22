function resources = PDCCHRepeater(ctrlCfg, candidateResources)
%PDCCHRepeater Apply intra-slot or inter-slot repetition resource cloning.

resources = candidateResources;
mode = lower(string(ctrlCfg.RepetitionMode));
count = max(1, round(double(ctrlCfg.RepetitionCount)));

resources.RETable.SlotIndex = ones(height(resources.RETable),1);
resources.RETable.CopyIndex = ones(height(resources.RETable),1);

if ~logical(ctrlCfg.EnableRepetition) || count == 1 || mode == "none"
    resources.RepetitionMode = "none";
    resources.RepetitionCount = 1;
    resources.PerCopyResourceTables = {resources.RETable};
    return;
end

perCopy = cell(count,1);
switch mode
    case "inter_slot"
        if count > ctrlCfg.NSlotGrid
            error("sixgr:ctrl:PDCCHRepeater:InsufficientSlots", ...
                "Inter-slot repetition count %d exceeds the configured NumSlots %d.", count, ctrlCfg.NSlotGrid);
        end
        allRows = repmat(resources.RETable(1,:), 0, 1);
        for c = 1:count
            copyT = resources.RETable;
            copyT.SlotIndex = repmat(c, height(copyT), 1);
            copyT.CopyIndex = repmat(c, height(copyT), 1);
            perCopy{c} = copyT;
            allRows = [allRows; copyT]; %#ok<AGROW>
        end
        resources.RETable = allRows;
    case "intra_slot"
        startSym = min(resources.RETable.Symbol);
        duration = numel(unique(resources.RETable.Symbol));
        if startSym + count * duration > 14
            error("sixgr:ctrl:PDCCHRepeater:InsufficientSymbols", ...
                "Intra-slot repetition count %d does not fit in a 14-symbol slot.", count);
        end
        allRows = repmat(resources.RETable(1,:), 0, 1);
        for c = 1:count
            copyT = resources.RETable;
            copyT.Symbol = copyT.Symbol + (c - 1) * duration;
            copyT.SlotIndex = ones(height(copyT), 1);
            copyT.CopyIndex = repmat(c, height(copyT), 1);
            perCopy{c} = copyT;
            allRows = [allRows; copyT]; %#ok<AGROW>
        end
        resources.RETable = allRows;
    otherwise
        error("sixgr:ctrl:PDCCHRepeater:BadMode", ...
            "Unsupported repetition mode '%s'.", mode);
end

resources.RepetitionMode = char(mode);
resources.RepetitionCount = count;
resources.PerCopyResourceTables = perCopy;
end
