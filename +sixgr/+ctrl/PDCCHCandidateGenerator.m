function [candidateTable, hashTrace] = PDCCHCandidateGenerator(ctrlCfg, searchSpace, cceMap, slotNumber)
%PDCCHCandidateGenerator Enumerate monitored blind-decode candidates.

slotsPerFrame = localRequireSlotsPerFrame(ctrlCfg);
nSlotFrame = mod(round(double(slotNumber)), slotsPerFrame);
periodSlots = max(1, round(double(searchSpace.MonitoringSlotsPeriodicity)));
slotOffset = max(0, round(double(searchSpace.MonitoringSlotOffset)));
if mod(nSlotFrame - slotOffset, periodSlots) ~= 0
    candidateTable = table();
    hashTrace = table();
    return;
end

monitoringSymbols = double(sixgr.util.structGet(searchSpace, "MonitoringSymbolsWithinSlot", []));
coresetSymbols = double(sixgr.util.structGet(ctrlCfg, "CORESET.StartSymbol", 0)) + ...
    (0:max(0, round(double(sixgr.util.structGet(ctrlCfg, "CORESET.DurationSymbols", 1))) - 1));
if ~isempty(monitoringSymbols) && isempty(intersect(monitoringSymbols(:).', coresetSymbols(:).'))
    candidateTable = table();
    hashTrace = table();
    return;
end

capacityCCE = height(cceMap);
candRows = repmat(struct("SearchSpaceID", NaN, "SearchSpaceType", "", "SlotNumber", NaN, ...
    "AggregationLevel", NaN, "CandidateIndex", NaN, "StartCCE", NaN, "EndCCE", NaN, ...
    "CandidateValid", false, "HashValue", NaN), 0, 1);
hashRows = repmat(struct("SearchSpaceID", NaN, "SlotNumber", NaN, "AggregationLevel", NaN, ...
    "CandidateIndex", NaN, "HashValue", NaN), 0, 1);

for al = reshape(double(searchSpace.AggregationLevels), 1, [])
    fieldName = sprintf("AL%d", al);
    if ~isfield(searchSpace.CandidateCountPerAL, fieldName)
        continue;
    end
    numCandidates = double(searchSpace.CandidateCountPerAL.(fieldName));
    if numCandidates <= 0
        continue;
    end
    maxStartCount = max(0, capacityCCE - al + 1);
    for candIdx = 0:numCandidates-1
        [hashValue, trace] = sixgr.ctrl.HashFunction6GR(searchSpace.HashFunctionMode, ctrlCfg, searchSpace, slotNumber, al, candIdx);
        if maxStartCount <= 0
            startCCE = NaN;
            valid = false;
        else
            startCCE = mod(hashValue, maxStartCount);
            valid = (startCCE + al) <= capacityCCE;
        end
        candRows(end+1,1) = struct( ... %#ok<AGROW>
            "SearchSpaceID", searchSpace.SearchSpaceID, ...
            "SearchSpaceType", string(searchSpace.SearchSpaceType), ...
            "SlotNumber", slotNumber, ...
            "AggregationLevel", al, ...
            "CandidateIndex", candIdx, ...
            "StartCCE", startCCE, ...
            "EndCCE", startCCE + al - 1, ...
            "CandidateValid", valid, ...
            "HashValue", hashValue);
        hashRows(end+1,1) = struct( ... %#ok<AGROW>
            "SearchSpaceID", trace.SearchSpaceID, ...
            "SlotNumber", trace.SlotNumber, ...
            "AggregationLevel", trace.AggregationLevel, ...
            "CandidateIndex", trace.CandidateIndex, ...
            "HashValue", trace.HashValue);
    end
end

candidateTable = struct2table(candRows);
hashTrace = struct2table(hashRows);
end

function slotsPerFrame = localRequireSlotsPerFrame(ctrlCfg)
slotsPerFrame = double(sixgr.util.structGet(ctrlCfg, "SlotsPerFrame", NaN));
if ~(isscalar(slotsPerFrame) && isfinite(slotsPerFrame) && ...
        slotsPerFrame >= 1 && slotsPerFrame == fix(slotsPerFrame))
    error("sixgr:ctrl:PDCCHCandidateGenerator:MissingCanonicalNumerology", ...
        "ctrlCfg.SlotsPerFrame must come from ControlChannelConfig's canonical numerology resolution.");
end
end
