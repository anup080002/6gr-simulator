function out = PDCCHBlindDetector(rxGrid4D, ctrlCfg, searchSpaces, regTable, reTable, cceMap, truth)
%PDCCHBlindDetector Blind-monitor candidates and classify the outcome.

allCandRows = cell(0,1);
slotRows = cell(0,1);
hashTraceAll = table();
passIdx = [];
targetIdx = NaN;
searchSpaces = localPrioritizeSearchSpaces(searchSpaces);
maxCandPerSlot = localMaxPDCCHCandidatesPerSlot(ctrlCfg);
validCandidatesDecoded = 0;
candidateOverflowCount = 0;

for ssIdx = 1:numel(searchSpaces)
    searchSpace = searchSpaces(ssIdx);
    [candTable, hashTrace] = sixgr.ctrl.PDCCHCandidateGenerator(ctrlCfg, searchSpace, cceMap, truth.BaseSlot);
    if istable(hashTrace) && ~isempty(hashTrace)
        hashTraceAll = [hashTraceAll; hashTrace]; %#ok<AGROW>
    end
    if isempty(candTable)
        continue;
    end
    for r = 1:height(candTable)
        cand = table2struct(candTable(r,:));
        if ~cand.CandidateValid
            row = localEmptyCandidateRow(cand, searchSpace, ctrlCfg);
            row.decoding_metric = -Inf;
            allCandRows{end+1,1} = row; %#ok<AGROW>
            continue;
        end
        if validCandidatesDecoded >= maxCandPerSlot
            candidateOverflowCount = candidateOverflowCount + 1;
            continue;
        end
        validCandidatesDecoded = validCandidatesDecoded + 1;
        resources = localCandidateResources(cand, regTable, reTable, cceMap, ctrlCfg, truth);
        dmrs = sixgr.ctrl.PDCCHDMRS(ctrlCfg, resources.RETable, struct( ...
            "SlotNumber", truth.BaseSlot, ...
            "CandidateIndex", cand.CandidateIndex, ...
            "SearchSpaceID", cand.SearchSpaceID));
        payloadT = resources.RETable(dmrs.PayloadREMask, :);
        basePayloadPerCopy = sum(payloadT.CopyIndex == 1);
        combinedSym = complex(zeros(basePayloadPerCopy, 1));
        combinedCSI = zeros(size(combinedSym));
        copyMetrics = zeros(resources.RepetitionCount, 1);
        nmsePerCopy = NaN(resources.RepetitionCount,1);
        evmPerCopy = NaN(resources.RepetitionCount,1);
        sinrPerCopy = NaN(resources.RepetitionCount,1);
        nVarPerCopy = NaN(resources.RepetitionCount,1);

        for copyIdx = 1:resources.RepetitionCount
            copyPayload = payloadT(payloadT.CopyIndex == copyIdx, :);
            copyRx = localExtractCopySymbols(rxGrid4D, copyPayload);
            est = sixgr.ctrl.PDCCHChannelEstimator(rxGrid4D, dmrs, [], copyIdx, []);
            nVarEst = localEstimateNoiseFromResidual(est.Residual);
            if ~(isfinite(nVarEst) && nVarEst > 0)
                nVarEst = localEstimateNoiseFromUnusedRE(rxGrid4D, resources.RETable, copyIdx);
            end
            if ~(isfinite(nVarEst) && nVarEst > 0)
                nVarEst = localConservativeNoiseFloor(copyRx);
            end
            nVarPerCopy(copyIdx) = nVarEst;
            eq = sixgr.ctrl.PDCCHEqualizer(copyRx, est.HMean, nVarEst, ctrlCfg.EqualizerType);
            nmsePerCopy(copyIdx) = est.NMSE;
            evmPerCopy(copyIdx) = eq.PostEqEVM;
            sinrPerCopy(copyIdx) = eq.EstimatedSINR_dB;
            copyMetrics(copyIdx) = mean(eq.CSI);
            combinedSym = combinedSym + eq.Symbols(:) .* eq.CSI(:);
            combinedCSI = combinedCSI + eq.CSI(:);
        end
        reliableCSI = combinedCSI > 1e-6;
        tmpCombined = complex(zeros(size(combinedSym)));
        tmpCombined(reliableCSI) = combinedSym(reliableCSI) ./ combinedCSI(reliableCSI);
        combinedSym = tmpCombined;
        combinedNoiseVar = mean(nVarPerCopy(isfinite(nVarPerCopy) & nVarPerCopy > 0), "omitnan");
        if ~(isfinite(combinedNoiseVar) && combinedNoiseVar > 0)
            combinedNoiseVar = localConservativeNoiseFloor(combinedSym);
        end
        context = struct("SlotNumber", truth.BaseSlot, "SearchSpaceID", cand.SearchSpaceID);
        dec = sixgr.ctrl.PDCCHDecoder(combinedSym, combinedNoiseVar, truth.PayloadMeta, ctrlCfg, context);
        row = localEmptyCandidateRow(cand, searchSpace, ctrlCfg);
        row.candidate_detected = logical(dec.CRCPass);
        row.crc_pass = logical(dec.CRCPass);
        row.estimated_sinr_db = mean(sinrPerCopy, "omitnan");
        row.post_eq_evm = mean(evmPerCopy, "omitnan");
        row.nmse_channel_est = mean(nmsePerCopy, "omitnan");
        row.decoding_metric = dec.DecodingMetric;
        row.repetition_combined_metric = mean(copyMetrics, "omitnan");
        row.repetition_index = 0;
        row.decoded_payload_match = isequal(dec.DecodedBits(:), truth.PayloadBits(:));
        if row.crc_pass
            passIdx(end+1) = numel(allCandRows) + 1; %#ok<AGROW>
        end
        if cand.StartCCE == truth.TargetCandidate.StartCCE && cand.AggregationLevel == truth.TargetCandidate.AggregationLevel && ...
                cand.SearchSpaceID == truth.TargetCandidate.SearchSpaceID
            targetIdx = numel(allCandRows) + 1;
        end
        allCandRows{end+1,1} = row; %#ok<AGROW>
    end
end

if candidateOverflowCount > 0
    warning("sixgr:ctrl:PDCCHBlindDetector:CandidateOverflow", ...
        "%d PDCCH candidates exceeded the max %d for this slot and were not decoded.", ...
        candidateOverflowCount, maxCandPerSlot);
end
if isempty(allCandRows)
    candidateTable = table();
else
    candidateTable = struct2table(vertcat(allCandRows{:}));
end
hashTraceTable = hashTraceAll;

slotResult = struct();
slotResult.true_detection = false;
slotResult.miss_detection = false;
slotResult.false_alarm = false;
slotResult.false_positive_wrong_candidate = false;
slotResult.ambiguous_multiple_pass = false;
slotResult.monitored_candidates_count = height(candidateTable);
if isempty(candidateTable)
    slotResult.monitored_ALs = "";
else
    slotResult.monitored_ALs = string(join(string(unique(candidateTable.AL(~isnan(candidateTable.AL)))), " "));
end
slotResult.total_blind_decodes = height(candidateTable);
if isempty(candidateTable)
    slotResult.decode_latency_proxy_ops = 0;
else
    slotResult.decode_latency_proxy_ops = sum(candidateTable.AL .* 6, "omitnan");
end

if isempty(candidateTable) || isempty(passIdx)
    slotResult.miss_detection = true;
elseif numel(passIdx) == 1 && ~isnan(targetIdx) && passIdx(1) == targetIdx && candidateTable.decoded_payload_match(targetIdx)
    slotResult.true_detection = true;
elseif numel(passIdx) >= 1 && ~isnan(targetIdx) && any(passIdx == targetIdx)
    slotResult.ambiguous_multiple_pass = true;
else
    slotResult.false_positive_wrong_candidate = true;
    slotResult.false_alarm = true;
end

slotRows{1,1} = slotResult;
out = struct();
out.PerCandidateResults = candidateTable;
out.PerSlotResults = struct2table(vertcat(slotRows{:}));
out.HashTrace = hashTraceTable;
end

function row = localEmptyCandidateRow(cand, searchSpace, ctrlCfg)
row = struct( ...
    "candidate_detected", false, ...
    "crc_pass", false, ...
    "estimated_sinr_db", NaN, ...
    "post_eq_evm", NaN, ...
    "nmse_channel_est", NaN, ...
    "decoding_metric", NaN, ...
    "start_cce", cand.StartCCE, ...
    "AL", cand.AggregationLevel, ...
    "repetition_index", NaN, ...
    "repetition_combined_metric", NaN, ...
    "candidate_index", cand.CandidateIndex, ...
    "coreset_id", ctrlCfg.CORESET.CORESETID, ...
    "search_space_id", searchSpace.SearchSpaceID, ...
    "search_space_type", string(searchSpace.SearchSpaceType), ...
    "slot_number", cand.SlotNumber, ...
    "decoded_payload_match", false);
end

function resources = localCandidateResources(cand, regTable, reTable, cceMap, ctrlCfg, truth)
regList = [];
for cce = cand.StartCCE:(cand.StartCCE + cand.AggregationLevel - 1)
    row = cceMap(cceMap.CCEIndex == cce, :);
    if isempty(row)
        continue;
    end
    regList = [regList sscanf(char(row.REGIndices{1}), "%d").']; %#ok<AGROW>
end
regList = unique(regList, "stable");
ret = reTable(ismember(reTable.REGIndex, regList), :);
ret = sortrows(ret, {'Symbol','Subcarrier'});
ret.SlotIndex = ones(height(ret),1);
ret.CopyIndex = ones(height(ret),1);
resources = struct();
resources.RETable = ret;
resources.REGTable = regTable(ismember(regTable.REGIndex, regList), :);
resources.RepetitionCount = max(1, truth.RepetitionCount);
resources = sixgr.ctrl.PDCCHRepeater(ctrlCfg, resources);
end

function rx = localExtractCopySymbols(rxGrid4D, copyPayload)
rx = complex(zeros(height(copyPayload), size(rxGrid4D, 3)));
for i = 1:height(copyPayload)
    rx(i,:) = squeeze(rxGrid4D(copyPayload.Subcarrier(i)+1, copyPayload.Symbol(i)+1, :, copyPayload.SlotIndex(i))).';
end
end

function nVar = localEstimateNoiseFromResidual(residual)
nVar = NaN;
if isempty(residual)
    return;
end
vals = abs(double(residual(:))).^2;
vals = vals(isfinite(vals));
if isempty(vals)
    return;
end
nVar = mean(vals, "omitnan");
end

function nVar = localEstimateNoiseFromUnusedRE(rxGrid4D, reTable, copyIdx)
nVar = NaN;
if isempty(rxGrid4D) || ~(istable(reTable) && ~isempty(reTable))
    return;
end
mask = true(size(rxGrid4D, 1), size(rxGrid4D, 2), size(rxGrid4D, 4));
copyRows = reTable(reTable.CopyIndex == copyIdx, :);
for i = 1:height(copyRows)
    mask(copyRows.Subcarrier(i)+1, copyRows.Symbol(i)+1, copyRows.SlotIndex(i)) = false;
end
vals = [];
for rxIdx = 1:size(rxGrid4D, 3)
    slice = rxGrid4D(:, :, rxIdx, :);
    slice = reshape(slice, size(rxGrid4D, 1), size(rxGrid4D, 2), size(rxGrid4D, 4));
    vals = [vals; slice(mask)]; %#ok<AGROW>
end
if isempty(vals)
    return;
end
p = mean(abs(double(vals(:))).^2, "omitnan");
if isfinite(p) && p > 0
    nVar = p;
end
end

function nVar = localConservativeNoiseFloor(x)
vals = abs(double(x(:))).^2;
vals = vals(isfinite(vals));
if isempty(vals)
    nVar = 1;
else
    nVar = max(1e-6, 0.25 * mean(vals, "omitnan"));
end
end

function ordered = localPrioritizeSearchSpaces(searchSpaces)
ordered = searchSpaces;
if numel(searchSpaces) < 2
    return;
end
types = strings(numel(searchSpaces), 1);
for i = 1:numel(searchSpaces)
    types(i) = upper(string(sixgr.util.structGet(searchSpaces(i), "SearchSpaceType", "")));
end
priority = ones(numel(searchSpaces), 1);
priority(types == "USS") = 0;
[~, idx] = sort(priority, "ascend");
ordered = searchSpaces(idx);
end

function maxCand = localMaxPDCCHCandidatesPerSlot(ctrlCfg)
scs = double(sixgr.util.structGet(ctrlCfg, "SubcarrierSpacing_kHz", ...
    sixgr.util.structGet(ctrlCfg, "SubcarrierSpacing", NaN)));
if ~isfinite(scs)
    mu = double(sixgr.util.structGet(ctrlCfg, "Numerology", 1));
    scs = 15 * 2^max(0, round(mu));
end
switch round(scs)
    case 15
        maxCand = 44;
    case 30
        maxCand = 36;
    case 60
        maxCand = 22;
    case 120
        maxCand = 20;
    otherwise
        maxCand = 44;
end
end
