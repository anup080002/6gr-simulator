function study = runPDCCHStudyLLS(inputCfg, varargin)
%runPDCCHStudyLLS Run the 6GR PDCCH waveform/resource-grid study framework.
%
% This is a study framework for 10.5.2.1 downlink control transmission
% schemes. It keeps FFS items explicit while still building real grid-level
% placement, DMRS-based estimation, blind candidate monitoring, and KPI
% accounting from actual simulated trials.

opts = struct("ScenarioMatrix", [], "WriteOutputs", true, "Verbose", false, ...
    "OutputDir", "", "ScenarioID", "ctrl6gr_pdcch_study");
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

if strlength(string(opts.OutputDir)) == 0
    timestamp = string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    opts.OutputDir = fullfile("results", "ctrl6gr_pdcch_" + timestamp);
end
sixgr.util.ensureFolder(opts.OutputDir);

baseCfg = sixgr.ctrl.ControlChannelConfig(inputCfg, "RunFolder", opts.OutputDir, "ScenarioID", opts.ScenarioID);
scenarioPoints = localBuildScenarioPoints(baseCfg, opts.ScenarioMatrix);

allCand = table();
allSlot = table();
allHash = table();
allDMRS = table();
allMRSS = table();
pointRows = repmat(struct("ScenarioID","", "TrialIndex", NaN, "SNRdB", NaN, "AggregationLevel", NaN, ...
    "CORESETDuration", NaN, "MappingType","", "RepetitionMode","", "FrequencyAllocationMode","", ...
    "MRSSMode","", "DCIErrorRate", NaN, "DetectionProbability", NaN, "MissProbability", NaN, ...
    "FalseAlarmProbability", NaN, "AverageCandidatesMonitored", NaN, "AverageNMSE", NaN, "AverageOps", NaN), 0, 1);

firstPointArtifacts = struct();
haveArtifacts = false;
trialCounter = 0;
for p = 1:numel(scenarioPoints)
    point = scenarioPoints(p);
    if opts.Verbose
        fprintf("[PDCCH6GR] Scenario %d/%d: SNR=%.2f AL=%d dur=%d map=%s rep=%s\n", ...
            p, numel(scenarioPoints), point.SNRdB, point.AggregationLevel, ...
            point.CORESETDuration, point.MappingType, point.RepetitionMode);
    end
    [pointCfg, overlapT] = localApplyScenarioPoint(baseCfg, point);
    [regTable, reTable] = sixgr.ctrl.REGIndexer(pointCfg);
    bundleT = sixgr.ctrl.REGBundleMapper(regTable, pointCfg.CORESET);
    cceMap = sixgr.ctrl.CCEToREGMapper(pointCfg, regTable, bundleT);
    searchSpaceMap = localSearchSpaceTable(pointCfg.SearchSpaces);
    if ~haveArtifacts
        firstPointArtifacts.CORESETMap = localCORESETMap(pointCfg, regTable);
        firstPointArtifacts.SearchSpaceMap = searchSpaceMap;
        firstPointArtifacts.REGIndexMap = regTable;
        firstPointArtifacts.CCERegMap = cceMap;
        haveArtifacts = true;
    end
    if ~isempty(overlapT)
        allMRSS = [allMRSS; overlapT]; %#ok<AGROW>
    end

    for trialIdx = 1:point.NumTrials
        trialCounter = trialCounter + 1;
        trialSeed = double(baseCfg.Seed + 1000 * (p - 1) + trialIdx);
        payload = sixgr.ctrl.ControlPayloadBuilder(pointCfg, "Seed", trialSeed);

        [targetCandidate, hashTrace, candidateTrace, truthPayloadMeta, txGrid4D, txRuntime] = ...
            localRunSingleTransmit(pointCfg, regTable, reTable, cceMap, payload, trialSeed);
        rxGrid4D = localPassChannel(pointCfg, txGrid4D, txRuntime);
        rxTruth = struct();
        rxTruth.TargetCandidate = targetCandidate;
        rxTruth.BaseSlot = 1;
        rxTruth.PayloadBits = payload.InformationBits;
        rxTruth.PayloadMeta = truthPayloadMeta;
        rxTruth.NoiseVar = txRuntime.NoiseVar;
        rxTruth.RepetitionCount = txRuntime.RepetitionCount;
        rxOut = sixgr.ctrl.PDCCHStudyReceiver(rxGrid4D, pointCfg, regTable, reTable, cceMap, rxTruth);

        candT = rxOut.PerCandidateResults;
        slotT = rxOut.PerSlotResults;
        if ~isempty(candT)
            candT.ScenarioID = repmat(string(point.ScenarioID), height(candT), 1);
            candT.TrialIndex = repmat(trialCounter, height(candT), 1);
            candT.SNRdB = repmat(point.SNRdB, height(candT), 1);
            candT.CORESETDuration = repmat(point.CORESETDuration, height(candT), 1);
            candT.MappingType = repmat(string(point.MappingType), height(candT), 1);
            candT.RepetitionMode = repmat(string(point.RepetitionMode), height(candT), 1);
            candT.FrequencyAllocationMode = repmat(string(point.FrequencyAllocationMode), height(candT), 1);
            candT.MRSSMode = repmat(string(point.MRSSMode), height(candT), 1);
            allCand = [allCand; candT]; %#ok<AGROW>
        end
        if ~isempty(slotT)
            slotT.ScenarioID = repmat(string(point.ScenarioID), height(slotT), 1);
            slotT.TrialIndex = repmat(trialCounter, height(slotT), 1);
            slotT.SNRdB = repmat(point.SNRdB, height(slotT), 1);
            slotT.AggregationLevel = repmat(point.AggregationLevel, height(slotT), 1);
            slotT.CORESETDuration = repmat(point.CORESETDuration, height(slotT), 1);
            slotT.MappingType = repmat(string(point.MappingType), height(slotT), 1);
            slotT.RepetitionMode = repmat(string(point.RepetitionMode), height(slotT), 1);
            slotT.FrequencyAllocationMode = repmat(string(point.FrequencyAllocationMode), height(slotT), 1);
            slotT.MRSSMode = repmat(string(point.MRSSMode), height(slotT), 1);
            allSlot = [allSlot; slotT]; %#ok<AGROW>
        end
        if istable(hashTrace) && ~isempty(hashTrace)
            hashTrace.ScenarioID = repmat(string(point.ScenarioID), height(hashTrace), 1);
            hashTrace.TrialIndex = repmat(trialCounter, height(hashTrace), 1);
            allHash = [allHash; hashTrace]; %#ok<AGROW>
        end
        if istable(candidateTrace) && ~isempty(candidateTrace)
            candidateTrace.ScenarioID = repmat(string(point.ScenarioID), height(candidateTrace), 1);
            candidateTrace.TrialIndex = repmat(trialCounter, height(candidateTrace), 1);
            allDMRS = [allDMRS; candidateTrace]; %#ok<AGROW>
        end
    end

    if ~isempty(allCand) && ismember("ScenarioID", allCand.Properties.VariableNames)
        pointCand = allCand(allCand.ScenarioID == string(point.ScenarioID), :);
    else
        pointCand = table();
    end
    if ~isempty(allSlot) && ismember("ScenarioID", allSlot.Properties.VariableNames)
        pointSlot = allSlot(allSlot.ScenarioID == string(point.ScenarioID), :);
    else
        pointSlot = table();
    end
    pointMetrics = sixgr.ctrl.PDCCHMetrics(pointCand, pointSlot);
    pointRows(end+1,1) = struct( ... %#ok<AGROW>
        "ScenarioID", char(string(point.ScenarioID)), ...
        "TrialIndex", p, ...
        "SNRdB", point.SNRdB, ...
        "AggregationLevel", point.AggregationLevel, ...
        "CORESETDuration", point.CORESETDuration, ...
        "MappingType", char(string(point.MappingType)), ...
        "RepetitionMode", char(string(point.RepetitionMode)), ...
        "FrequencyAllocationMode", char(string(point.FrequencyAllocationMode)), ...
        "MRSSMode", char(string(point.MRSSMode)), ...
        "DCIErrorRate", pointMetrics.DCIBLER, ...
        "DetectionProbability", localScalar(pointMetrics.Summary, "DetectionProbability"), ...
        "MissProbability", localScalar(pointMetrics.Summary, "MissProbability"), ...
        "FalseAlarmProbability", localScalar(pointMetrics.Summary, "FalseAlarmProbability"), ...
        "AverageCandidatesMonitored", localScalar(pointMetrics.Summary, "AverageCandidatesMonitored"), ...
        "AverageNMSE", localScalar(pointMetrics.ComplexitySummary, "AverageNMSE"), ...
        "AverageOps", localScalar(pointMetrics.Summary, "AverageOps"));
end

summaryByScenario = struct2table(pointRows);
summaryBySNR = localAggregate(summaryByScenario, "SNRdB");
summaryByAL = localAggregate(summaryByScenario, "AggregationLevel");
summaryByMapping = localAggregate(summaryByScenario, "MappingType");
summaryByRepetition = localAggregate(summaryByScenario, "RepetitionMode");
summaryByDuration = localAggregate(summaryByScenario, "CORESETDuration");
summaryByFreqAlloc = localAggregate(summaryByScenario, "FrequencyAllocationMode");
summaryByMRSS = localAggregate(summaryByScenario, "MRSSMode");
complexitySummary = localComplexitySummary(allCand, allSlot);

study = struct();
study.Config = baseCfg;
study.OutputDir = string(opts.OutputDir);
study.CORESETMap = firstPointArtifacts.CORESETMap;
study.SearchSpaceMap = firstPointArtifacts.SearchSpaceMap;
study.REGIndexMap = firstPointArtifacts.REGIndexMap;
study.CCERegMap = firstPointArtifacts.CCERegMap;
study.CandidateHashTrace = allHash;
study.DMRSLocations = allDMRS;
study.PerCandidateResults = allCand;
study.PerSlotResults = allSlot;
study.SummaryBySNR = summaryBySNR;
study.SummaryByAL = summaryByAL;
study.SummaryByMapping = summaryByMapping;
study.SummaryByRepetition = summaryByRepetition;
study.SummaryByCORESETDuration = summaryByDuration;
study.SummaryByFrequencyAllocation = summaryByFreqAlloc;
study.SummaryByMRSSMode = summaryByMRSS;
study.SummaryByScenario = summaryByScenario;
study.ComplexitySummary = complexitySummary;
study.PDCCHTrials = localBuildPDCCHTrialTable(allCand, allSlot, baseCfg);
study.MRSSOverlapEvents = allMRSS;

if logical(opts.WriteOutputs)
    localWriteOutputs(study);
    localWritePlots(study);
end
end

function points = localBuildScenarioPoints(cfg, scenarioMatrix)
if ~isempty(scenarioMatrix)
    points = scenarioMatrix;
    return;
end

s = cfg.StudySweep;
[A,B,C,D,E,F,G,H,I,J,K,L] = ndgrid(s.AggregationLevels, s.CORESETDurations, 1:numel(s.MappingTypes), ...
    1:numel(s.FrequencyAllocationModes), 1:numel(s.RepetitionModes), s.SNRdB, 1:numel(s.ChannelModels), ...
    1:numel(s.SearchSpaceTypes), 1:numel(s.DMRSVariants), 1:numel(s.REGBundleSizes), ...
    1:numel(s.NumREGPerCCE), 1:numel(s.MRSSModes));
numPoints = numel(A);
points = repmat(struct("ScenarioID","", "AggregationLevel", NaN, "CORESETDuration", NaN, ...
    "MappingType","", "FrequencyAllocationMode","", "RepetitionMode","", "SNRdB", NaN, ...
    "ChannelModel","", "SearchSpaceType","", "DMRSVariant","", "REGBundleSize", NaN, ...
    "NumREGPerCCE", NaN, "MRSSMode","", "NumTrials", 1), numPoints, 1);
for i = 1:numPoints
    points(i).ScenarioID = sprintf("pdcch6gr_%03d", i);
    points(i).AggregationLevel = A(i);
    points(i).CORESETDuration = B(i);
    points(i).MappingType = s.MappingTypes(C(i));
    points(i).FrequencyAllocationMode = s.FrequencyAllocationModes(D(i));
    points(i).RepetitionMode = s.RepetitionModes(E(i));
    points(i).SNRdB = F(i);
    points(i).ChannelModel = s.ChannelModels(G(i));
    points(i).SearchSpaceType = s.SearchSpaceTypes(H(i));
    points(i).DMRSVariant = s.DMRSVariants(I(i));
    points(i).REGBundleSize = s.REGBundleSizes(J(i));
    points(i).NumREGPerCCE = s.NumREGPerCCE(K(i));
    points(i).MRSSMode = s.MRSSModes(L(i));
    points(i).NumTrials = 1;
end
end

function [cfg, overlapT] = localApplyScenarioPoint(baseCfg, point)
cfg = baseCfg;
cfg.SNRdB = point.SNRdB;
cfg.ChannelModel = char(string(point.ChannelModel));
cfg.RepetitionMode = char(string(point.RepetitionMode));
cfg.EnableRepetition = ~strcmpi(point.RepetitionMode, "none");
cfg.CORESET.DurationSymbols = point.CORESETDuration;
cfg.CORESET.MappingType = char(string(point.MappingType));
cfg.CORESET.FrequencyAllocationMode = char(string(point.FrequencyAllocationMode));
cfg.CORESET.REGBundleSize = point.REGBundleSize;
cfg.CORESET.NumREGPerCCE = point.NumREGPerCCE;
for i = 1:numel(cfg.SearchSpaces)
    originalCounts = cfg.SearchSpaces(i).CandidateCountPerAL;
    cfg.SearchSpaces(i).AggregationLevels = point.AggregationLevel;
    fields = fieldnames(cfg.SearchSpaces(i).CandidateCountPerAL);
    for k = 1:numel(fields)
        cfg.SearchSpaces(i).CandidateCountPerAL.(fields{k}) = 0;
    end
    fieldName = sprintf("AL%d", point.AggregationLevel);
    cfg.SearchSpaces(i).CandidateCountPerAL.(fieldName) = max(1, round(double(sixgr.util.structGet(originalCounts, fieldName, 1))));
end
cfg.SearchSpaces = cfg.SearchSpaces(string({cfg.SearchSpaces.SearchSpaceType}) == string(point.SearchSpaceType));
if isempty(cfg.SearchSpaces)
    error("sixgr:ctrl:runPDCCHStudyLLS:MissingSearchSpaceType", ...
        "No configured search space matches '%s'.", point.SearchSpaceType);
end
if strcmpi(cfg.CORESET.FrequencyAllocationMode, "contiguous")
    cfg.CORESET.RBList = cfg.CORESET.RBStart + (0:cfg.CORESET.NumRB-1);
end
[cfg.CORESET, overlapT] = sixgr.ctrl.MRSSResourceCoordinator(cfg, cfg.CORESET, point.MRSSMode);
end

function [targetCandidate, hashTrace, dmrsTrace, payloadMeta, txGrid4D, runtime] = localRunSingleTransmit(cfg, regTable, reTable, cceMap, payload, trialSeed)
searchSpace = cfg.SearchSpaces(1);
[candTable, hashTrace] = sixgr.ctrl.PDCCHCandidateGenerator(cfg, searchSpace, cceMap, 1);
candTable = candTable(candTable.CandidateValid & candTable.AggregationLevel == searchSpace.AggregationLevels(1), :);
if isempty(candTable)
    error("sixgr:ctrl:runPDCCHStudyLLS:NoValidCandidate", ...
        "No valid PDCCH candidate exists for AL=%d.", searchSpace.AggregationLevels(1));
end
targetCandidate = table2struct(candTable(1,:));

resources = localCandidateResources(targetCandidate, regTable, reTable, cceMap, cfg);
dmrs = sixgr.ctrl.PDCCHStudyDMRS(cfg, resources.RETable, struct("SlotNumber", 1, "CandidateIndex", targetCandidate.CandidateIndex, "SearchSpaceID", searchSpace.SearchSpaceID));
payloadT = resources.RETable(dmrs.PayloadREMask, :);

crcOut = sixgr.ctrl.CRCAttachAndScramble(payload.InformationBits, cfg);
Kcrc = numel(crcOut.BitsWithCRC);
E = 2 * height(payloadT);
[codedRaw, ~] = sixgr.phy.phycode.polarEncode(crcOut.BitsWithCRC, E, "RAW", 9, false);
if numel(codedRaw) ~= E
    [codedBits, ~] = sixgr.phy.phycode.rateMatchPolar(codedRaw, Kcrc, E, false, "NMax", 9);
else
    codedBits = codedRaw;
end
scr = sixgr.ctrl.PayloadScrambler(codedBits, cfg, struct("SlotNumber", 1, "SearchSpaceID", searchSpace.SearchSpaceID));
modOut = sixgr.ctrl.PDCCHModulator(scr.Bits, cfg);
mapOut = sixgr.ctrl.PDCCHGridMapper(cfg, resources, modOut.Symbols, dmrs, "NumSlots", cfg.NSlotGrid);

txGrid4D = localApplyTransmitDiversity(mapOut.Grid, cfg, trialSeed, bundleFromRET(resources.RETable));
dmrsTrace = dmrs.Locations;
payloadMeta = struct("KWithCRC", Kcrc, "ListLength", 8, ...
    "PolarEncodedLength", numel(codedRaw), ...
    "RateMatchedLength", E, ...
    "AggregationLevel", targetCandidate.AggregationLevel, ...
    "PayloadRECount", height(payloadT));
runtime = struct("NoiseVar", localNoiseVariance(cfg.SNRdB), "RepetitionCount", resources.RepetitionCount);
end

function outGrid = localApplyTransmitDiversity(inGrid, cfg, trialSeed, bundleIndex)
outGrid = inGrid;
if ~logical(cfg.EnableTransmitDiversity) || cfg.NTx <= 1
    return;
end
if strcmpi(cfg.DiversityMode, "nontransparent_stub")
    error("sixgr:ctrl:runPDCCHStudyLLS:NonTransparentStub", ...
        "nontransparent_stub is declared as a future-study hook and is not decodable yet.");
end

[nSC, nSym, ~, nSlots] = size(inGrid);
outGrid = complex(zeros(nSC, nSym, cfg.NTx, nSlots));
if strcmpi(cfg.PrecoderGranularity, "reg_bundle")
    s = rng;
    cleanup = onCleanup(@() rng(s)); %#ok<NASGU>
    rng(trialSeed, "twister");
    phases = exp(1j * (pi/2) * randi([0 3], max(bundleIndex), cfg.NTx));
    for sl = 1:nSlots
        for sc = 1:nSC
            for sy = 1:nSym
                if inGrid(sc, sy, 1, sl) ~= 0
                    b = max(1, bundleIndex(sc, sy));
                    outGrid(sc, sy, :, sl) = inGrid(sc, sy, 1, sl) .* reshape(phases(b,:), 1, 1, []);
                end
            end
        end
    end
else
    w = ones(1, cfg.NTx) / sqrt(cfg.NTx);
    for tx = 1:cfg.NTx
        outGrid(:,:,tx,:) = inGrid(:,:,1,:) * w(tx);
    end
end
end

function bundleIndex = bundleFromRET(reTable)
bundleIndex = ones(max(reTable.Subcarrier)+1, max(reTable.Symbol)+1);
end

function resources = localCandidateResources(cand, regTable, reTable, cceMap, ctrlCfg)
regList = [];
for cce = cand.StartCCE:(cand.StartCCE + cand.AggregationLevel - 1)
    row = cceMap(cceMap.CCEIndex == cce, :);
    regList = [regList sscanf(char(row.REGIndices{1}), "%d").']; %#ok<AGROW>
end
regList = unique(regList, "stable");
ret = reTable(ismember(reTable.REGIndex, regList), :);
    ret = sortrows(ret, {'Symbol','Subcarrier'});
resources = struct("RETable", ret, "REGTable", regTable(ismember(regTable.REGIndex, regList), :), "RepetitionCount", ctrlCfg.RepetitionCount);
resources = sixgr.ctrl.PDCCHRepeater(ctrlCfg, resources);
end

function rxGrid4D = localPassChannel(cfg, txGrid4D, txRuntime)
noiseVar = txRuntime.NoiseVar;
if strcmpi(cfg.WaveformMode, "full_ofdm") && strcmpi(cfg.ChannelModel, "AWGN")
    rxGrid4D = localAddGridNoise(txGrid4D, noiseVar, cfg.NRx);
    return;
end

% Honest study approximation for current fading support inside the control
% study runner: apply an equivalent channel directly on the occupied grid.
% This preserves DMRS-based estimation and blind monitoring while avoiding
% silently pretending to have full time-domain fading support in this path.
rxGrid4D = localEquivalentChannel(txGrid4D, cfg, noiseVar);
end

function rxGrid4D = localAddGridNoise(txGrid4D, noiseVar, nRx)
[nSC, nSym, ~, nSlots] = size(txGrid4D);
rxGrid4D = complex(zeros(nSC, nSym, nRx, nSlots));
txCombined = sum(txGrid4D, 3);
for rx = 1:nRx
    rxGrid4D(:,:,rx,:) = txCombined + sqrt(noiseVar/2) * (randn(nSC, nSym, 1, nSlots) + 1j * randn(nSC, nSym, 1, nSlots));
end
end

function rxGrid4D = localEquivalentChannel(txGrid4D, cfg, noiseVar)
[nSC, nSym, ~, nSlots] = size(txGrid4D);
rxGrid4D = complex(zeros(nSC, nSym, cfg.NRx, nSlots));
txCombined = sum(txGrid4D, 3);
for sl = 1:nSlots
    for rx = 1:cfg.NRx
        switch upper(string(cfg.ChannelModel))
            case {"TDL-A","TDL-C","CDL-C","TDL","CDL"}
                h = (randn(1,1) + 1j * randn(1,1)) / sqrt(2);
            otherwise
                h = 1;
        end
        rxGrid4D(:,:,rx,sl) = txCombined(:,:,1,sl) * h + sqrt(noiseVar/2) * ...
            (randn(nSC, nSym) + 1j * randn(nSC, nSym));
    end
end
end

function noiseVar = localNoiseVariance(snr_dB)
noiseVar = 10.^(-double(snr_dB) / 10);
end

function T = localCORESETMap(cfg, regTable)
if isempty(regTable)
    T = table();
    return;
end
T = regTable;
T.CORESETID = repmat(cfg.CORESET.CORESETID, height(T), 1);
T.FrequencyAllocationMode = repmat(string(cfg.CORESET.FrequencyAllocationMode), height(T), 1);
T.MappingType = repmat(string(cfg.CORESET.MappingType), height(T), 1);
end

function T = localSearchSpaceTable(searchSpaces)
rows = repmat(struct("SearchSpaceID", NaN, "SearchSpaceType", "", "AssociatedCORESETID", NaN, ...
    "MonitoringSlotsPeriodicity", NaN, "MonitoringSlotOffset", NaN, "AggregationLevels", ""), 0, 1);
for i = 1:numel(searchSpaces)
    rows(end+1,1) = struct( ... %#ok<AGROW>
        "SearchSpaceID", searchSpaces(i).SearchSpaceID, ...
        "SearchSpaceType", string(searchSpaces(i).SearchSpaceType), ...
        "AssociatedCORESETID", searchSpaces(i).AssociatedCORESETID, ...
        "MonitoringSlotsPeriodicity", searchSpaces(i).MonitoringSlotsPeriodicity, ...
        "MonitoringSlotOffset", searchSpaces(i).MonitoringSlotOffset, ...
        "AggregationLevels", join(string(searchSpaces(i).AggregationLevels), " "));
end
T = struct2table(rows);
end

function val = localScalar(T, fieldName)
if istable(T) && ~isempty(T) && ismember(fieldName, T.Properties.VariableNames)
    val = double(T.(fieldName)(1));
else
    val = NaN;
end
end

function T = localAggregate(summaryByScenario, groupField)
if isempty(summaryByScenario)
    T = table();
    return;
end

metricFields = ["DCIErrorRate","DetectionProbability","MissProbability", ...
    "FalseAlarmProbability","AverageCandidatesMonitored","AverageNMSE","AverageOps"];
groupData = summaryByScenario.(groupField);
[groupKeys, groupLabels, isTextGroup] = localGroupingKeys(groupData);

groupCounts = zeros(numel(groupLabels), 1);
metricMeans = nan(numel(groupLabels), numel(metricFields));
for idx = 1:numel(groupLabels)
    mask = groupKeys == idx;
    groupCounts(idx) = sum(mask);
    for metricIdx = 1:numel(metricFields)
        fieldName = metricFields(metricIdx);
        values = double(summaryByScenario.(fieldName)(mask));
        metricMeans(idx, metricIdx) = mean(values, "omitnan");
    end
end

T = table();
if isTextGroup
    T.(groupField) = string(groupLabels(:));
else
    T.(groupField) = groupLabels(:);
end
T.GroupCount = groupCounts;
for metricIdx = 1:numel(metricFields)
    fieldName = metricFields(metricIdx);
    T.("mean_" + fieldName) = metricMeans(:, metricIdx);
end
end

function T = localComplexitySummary(perCand, perSlot)
if isempty(perCand)
    T = table();
    return;
end
T = groupsummary(perCand, "AL", "mean", ["decoding_metric","nmse_channel_est","post_eq_evm"]);
if ~isempty(perSlot)
    slotG = groupsummary(perSlot, "AggregationLevel", "mean", "decode_latency_proxy_ops");
    T = outerjoin(T, slotG, "LeftKeys", "AL", "RightKeys", "AggregationLevel", "MergeKeys", true);
end
end

function [groupKeys, groupLabels, isTextGroup] = localGroupingKeys(groupData)
if ischar(groupData)
    labels = string(cellstr(groupData));
    groupLabels = unique(labels, "stable");
    groupKeys = zeros(numel(labels), 1);
    for idx = 1:numel(groupLabels)
        groupKeys(labels == groupLabels(idx)) = idx;
    end
    isTextGroup = true;
    return;
end

if iscellstr(groupData) || isstring(groupData) || iscategorical(groupData)
    labels = string(groupData(:));
    groupLabels = unique(labels, "stable");
    groupKeys = zeros(numel(labels), 1);
    for idx = 1:numel(groupLabels)
        groupKeys(labels == groupLabels(idx)) = idx;
    end
    isTextGroup = true;
    return;
end

if islogical(groupData)
    labels = logical(groupData(:));
    groupLabels = unique(labels, "stable");
    groupKeys = zeros(numel(labels), 1);
    for idx = 1:numel(groupLabels)
        groupKeys(labels == groupLabels(idx)) = idx;
    end
    isTextGroup = false;
    return;
end

labels = double(groupData(:));
groupLabels = unique(labels, "stable");
groupKeys = zeros(numel(labels), 1);
for idx = 1:numel(groupLabels)
    groupKeys(labels == groupLabels(idx)) = idx;
end
isTextGroup = false;
end

function trialT = localBuildPDCCHTrialTable(perCand, perSlot, cfg)
if isempty(perSlot)
    trialT = table();
    return;
end

n = height(perSlot);
trialT = table();
resultLabels = localResultLabel(perSlot);
passMask = resultLabels == "TRUE_DETECTION";
trialT.Status = repmat("FAIL", n, 1);
trialT.Status(passMask) = "PASS";
trialT.Frame = ones(n,1);
trialT.Slot = (1:n).';
trialT.UE = ones(n,1);
trialT.CORESETID = repmat(cfg.CORESET.CORESETID, n, 1);
trialT.SearchSpaceID = ones(n,1);
trialT.AggregationLevel = double(perSlot.AggregationLevel);
trialT.BlindDecodeCount = double(perSlot.total_blind_decodes);
trialT.CRCPass = double(passMask);
trialT.DCICrcPass = logical(passMask);
trialT.PDCCHPayloadMatch = logical(passMask);
trialT.FalseAlarmFlag = logical(perSlot.false_alarm);
trialT.BlockingFlag = logical(perSlot.ambiguous_multiple_pass);
trialT.DCISize_bits = repmat(cfg.PayloadLengthBits, n, 1);
availableCCECount = localAvailableCCECount(cfg);
trialT.AvailableCCECount = repmat(availableCCECount, n, 1);
trialT.UsedCCECount = double(perSlot.AggregationLevel);
trialT.NonOverlappedCCEUsage = min(1, trialT.UsedCCECount ./ max(trialT.AvailableCCECount, 1));
trialT.ControlCapacityUtilization = trialT.NonOverlappedCCEUsage;
trialT.CORESETUtilization = trialT.NonOverlappedCCEUsage;
trialT.ControlLatency_ms = max(0.01, double(perSlot.decode_latency_proxy_ops) * 1e-3);
trialT.ComputeLatency_ms = trialT.ControlLatency_ms;
trialT.AirInterfaceTTI_ms = repmat(0.5, n, 1);
trialT.ProcedureDelay_ms = trialT.ControlLatency_ms;
trialT.MappingType = string(perSlot.MappingType);
trialT.FrequencyAllocationMode = string(perSlot.FrequencyAllocationMode);
trialT.RepetitionMode = string(perSlot.RepetitionMode);
trialT.RepetitionCount = repmat(cfg.RepetitionCount, n, 1);
trialT.Result = string(resultLabels);
trialT.Notes = repmat("6GR PDCCH study framework", n, 1);

if ~isempty(perCand)
    trialT.EstimatedSINR_dB = repmat(mean(double(perCand.estimated_sinr_db), "omitnan"), n, 1);
    trialT.PostEqEVM = repmat(mean(double(perCand.post_eq_evm), "omitnan"), n, 1);
    trialT.NMSEChannelEst = repmat(mean(double(perCand.nmse_channel_est), "omitnan"), n, 1);
    trialT.DecodingMetric = repmat(mean(double(perCand.decoding_metric), "omitnan"), n, 1);
else
    trialT.EstimatedSINR_dB = NaN(n,1);
    trialT.PostEqEVM = NaN(n,1);
    trialT.NMSEChannelEst = NaN(n,1);
    trialT.DecodingMetric = NaN(n,1);
end
end

function labels = localResultLabel(slotT)
n = height(slotT);
labels = repmat("MISS", n, 1);
labels(logical(slotT.true_detection)) = "TRUE_DETECTION";
labels(logical(slotT.false_positive_wrong_candidate)) = "FALSE_POSITIVE_WRONG_CANDIDATE";
labels(logical(slotT.ambiguous_multiple_pass)) = "AMBIGUOUS";
end

function nCCE = localAvailableCCECount(cfg)
try
    rbCount = numel(cfg.CORESET.RBList);
catch
    rbCount = 1;
end
if ~(isfinite(double(rbCount)) && rbCount > 0)
    rbCount = 1;
end
durationSymbols = double(cfg.CORESET.DurationSymbols);
if ~(isfinite(durationSymbols) && durationSymbols > 0)
    durationSymbols = 1;
end
nCCE = max(1, floor(double(rbCount) * durationSymbols / 6));
end

function localWriteOutputs(study)
outDir = char(string(study.OutputDir));
sixgr.util.jsonWrite(fullfile(outDir, "scenario_config.json"), study.Config);
sixgr.util.csvWriteTable(fullfile(outDir, "coreset_map.csv"), study.CORESETMap);
sixgr.util.csvWriteTable(fullfile(outDir, "search_space_map.csv"), study.SearchSpaceMap);
sixgr.util.csvWriteTable(fullfile(outDir, "reg_index_map.csv"), study.REGIndexMap);
sixgr.util.csvWriteTable(fullfile(outDir, "cce_reg_map.csv"), study.CCERegMap);
sixgr.util.csvWriteTable(fullfile(outDir, "candidate_hash_trace.csv"), study.CandidateHashTrace);
sixgr.util.csvWriteTable(fullfile(outDir, "dmrs_locations.csv"), study.DMRSLocations);
sixgr.util.csvWriteTable(fullfile(outDir, "per_candidate_results.csv"), study.PerCandidateResults);
sixgr.util.csvWriteTable(fullfile(outDir, "per_slot_results.csv"), study.PerSlotResults);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_snr.csv"), study.SummaryBySNR);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_al.csv"), study.SummaryByAL);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_mapping.csv"), study.SummaryByMapping);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_repetition.csv"), study.SummaryByRepetition);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_coreset_duration.csv"), study.SummaryByCORESETDuration);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_frequency_allocation.csv"), study.SummaryByFrequencyAllocation);
sixgr.util.csvWriteTable(fullfile(outDir, "summary_by_mrss_mode.csv"), study.SummaryByMRSSMode);
sixgr.util.csvWriteTable(fullfile(outDir, "complexity_summary.csv"), study.ComplexitySummary);
if ~isempty(study.MRSSOverlapEvents)
    sixgr.util.csvWriteTable(fullfile(outDir, "mrss_overlap_events.csv"), study.MRSSOverlapEvents);
end
end

function localWritePlots(study)
outDir = char(string(study.OutputDir));
localSaveLinePlot(study.SummaryBySNR, "SNRdB", "mean_DCIErrorRate", "dci_error_rate_vs_snr.png", outDir, "DCI error rate vs SNR");
localSaveLinePlot(study.SummaryBySNR, "SNRdB", "mean_MissProbability", "miss_probability_vs_snr.png", outDir, "Miss probability vs SNR");
localSaveLinePlot(study.SummaryBySNR, "SNRdB", "mean_FalseAlarmProbability", "false_alarm_vs_snr.png", outDir, "False alarm vs SNR");
localSaveLinePlot(study.SummaryByAL, "AggregationLevel", "mean_DetectionProbability", "performance_vs_al.png", outDir, "Detection probability vs AL");
localSaveLinePlot(study.SummaryByCORESETDuration, "CORESETDuration", "mean_DetectionProbability", "performance_vs_coreset_duration.png", outDir, "Detection probability vs CORESET duration");
localSaveCategoryPlot(study.SummaryByRepetition, "RepetitionMode", "mean_DetectionProbability", "performance_vs_repetition.png", outDir, "Detection probability vs repetition");
localSaveCategoryPlot(study.SummaryByMapping, "MappingType", "mean_DetectionProbability", "performance_interleaved_vs_noninterleaved.png", outDir, "Interleaved vs noninterleaved");
localSaveCategoryPlot(study.SummaryByFrequencyAllocation, "FrequencyAllocationMode", "mean_DetectionProbability", "performance_contiguous_vs_noncontiguous.png", outDir, "Contiguous vs noncontiguous");
localSaveLinePlot(study.SummaryBySNR, "SNRdB", "mean_AverageNMSE", "channel_estimation_nmse_vs_snr.png", outDir, "Channel estimation NMSE vs SNR");
localSaveLinePlot(study.SummaryByAL, "AggregationLevel", "mean_AverageCandidatesMonitored", "average_candidates_monitored_vs_al.png", outDir, "Average monitored candidates vs AL");
localSaveLinePlot(study.SummaryByAL, "AggregationLevel", "mean_AverageOps", "complexity_proxy_vs_al.png", outDir, "Complexity proxy vs AL");
localSaveHeatmap(study.SummaryByScenario, "AggregationLevel", "CORESETDuration", "DetectionProbability", "heatmap_al_vs_coreset_duration.png", outDir, "AL vs CORESET duration");
localSaveHeatmap(study.SummaryByScenario, "AggregationLevel", "RepetitionMode", "DetectionProbability", "heatmap_al_vs_repetition.png", outDir, "AL vs repetition");
if ~isempty(study.MRSSOverlapEvents)
    localSaveCategoryPlot(study.SummaryByMRSSMode, "MRSSMode", "mean_DetectionProbability", "mrss_resource_utilization.png", outDir, "MRSS mode utilization");
end
end

function localSaveLinePlot(T, xName, yName, fileName, outDir, ttl)
if isempty(T) || ~localHasVars(T, [string(xName), string(yName)])
    return;
end
f = figure("Visible", "off");
plot(T.(xName), T.(yName), "-o", "LineWidth", 1.5);
grid on;
xlabel(xName, "Interpreter", "none");
ylabel(yName, "Interpreter", "none");
title(ttl, "Interpreter", "none");
exportgraphics(gca, fullfile(outDir, fileName));
close(f);
end

function localSaveCategoryPlot(T, xName, yName, fileName, outDir, ttl)
if isempty(T) || ~localHasVars(T, [string(xName), string(yName)])
    return;
end
f = figure("Visible", "off");
bar(categorical(string(T.(xName))), T.(yName));
grid on;
xlabel(xName, "Interpreter", "none");
ylabel(yName, "Interpreter", "none");
title(ttl, "Interpreter", "none");
exportgraphics(gca, fullfile(outDir, fileName));
close(f);
end

function localSaveHeatmap(T, xName, yName, zName, fileName, outDir, ttl)
if isempty(T) || ~localHasVars(T, [string(xName), string(yName), string(zName)])
    return;
end
ux = unique(string(T.(xName)));
uy = unique(string(T.(yName)));
Z = NaN(numel(uy), numel(ux));
for ix = 1:numel(ux)
    for iy = 1:numel(uy)
        mask = string(T.(xName)) == ux(ix) & string(T.(yName)) == uy(iy);
        if any(mask)
            Z(iy, ix) = mean(double(T.(zName)(mask)), "omitnan");
        end
    end
end
f = figure("Visible", "off");
imagesc(Z);
colorbar;
set(gca, "XTick", 1:numel(ux), "XTickLabel", cellstr(ux), ...
    "YTick", 1:numel(uy), "YTickLabel", cellstr(uy));
xlabel(xName, "Interpreter", "none");
ylabel(yName, "Interpreter", "none");
title(ttl, "Interpreter", "none");
exportgraphics(gca, fullfile(outDir, fileName));
close(f);
end

function tf = localHasVars(T, requiredVars)
present = string(T.Properties.VariableNames);
required = string(requiredVars(:));
tf = all(ismember(required, present));
end
