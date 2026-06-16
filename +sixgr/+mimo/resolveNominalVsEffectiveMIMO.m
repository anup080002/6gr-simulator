function out = resolveNominalVsEffectiveMIMO(cfg, rawTrials, varargin)
%RESOLVENOMINALVSEFFECTIVEMIMO Build runtime MIMO evidence from raw trials.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || isnumeric(x));
ip.parse(varargin{:});
runId = string(ip.Results.RunId);
scenarioName = string(ip.Results.ScenarioName);
strictMode = logical(ip.Results.StrictMode);

cfgT = sixgr.mimo.buildMIMOConfigFromScenario(cfg, "RunId", runId, "ScenarioName", scenarioName);
configAudit = sixgr.mimo.validateMIMOConfigStrict(cfgT);
[rankTrials, layerMetrics] = localBuildRankAndLayerTables(cfgT, rawTrials, runId, scenarioName);
configuredEffective = localConfiguredVsEffective(cfgT, rankTrials, runId, scenarioName, strictMode);
rankUtil = localRankUtilization(rankTrials, runId, scenarioName);
antennaArray = localAntennaArrayConfig(cfgT);
portMapping = localAntennaPortMapping(cfgT, rankTrials);
precoderEvidence = localPrecoderEvidence(rankTrials);
beamCodebook = localBeamCodebook(cfgT, rankTrials);
beamSweep = localBeamSweep(rankTrials);
negativeTrials = localNegativeTrials(cfgT, rankTrials, configuredEffective, runId);
oracleGuard = localOracleGuard(rankTrials, runId);
toolbox = localToolboxCapabilities();

out = struct();
out.MIMOConfigStrict = cfgT;
out.ConfigValidation = configAudit;
out.AntennaArrayConfig = antennaArray;
out.AntennaPortMapping = portMapping;
out.RankLayerTrials = rankTrials;
out.LayerMetrics = layerMetrics;
out.ConfiguredVsEffective = configuredEffective;
out.RankUtilization = rankUtil;
out.PrecoderEvidence = precoderEvidence;
out.BeamCodebook = beamCodebook;
out.BeamSweepMeasurements = beamSweep;
out.NegativeTrials = negativeTrials;
out.OracleGuard = oracleGuard;
out.ToolboxCapabilities = toolbox;
out.StrictOk = all(localColumnLogical(configAudit, "Pass", false)) && ...
    all(localColumnLogical(configuredEffective, "ScenarioObjectivePass", false)) && ...
    localAllStatusPass(portMapping) && ...
    localAllStatusPass(precoderEvidence) && ...
    localAllStatusPass(beamCodebook) && ...
    localAllStatusPass(beamSweep) && ...
    all(strcmp(string(oracleGuard.Status), "pass"));
end

function [rankT, layerT] = localBuildRankAndLayerTables(cfgT, rawTrials, runId, scenarioName)
rows = repmat(localRankTrialRow(), 0, 1);
layerRows = repmat(localLayerRow(), 0, 1);
for direction = ["DL","UL"]
    T = localRawTable(rawTrials, direction);
    cfgRow = cfgT(strcmp(string(cfgT.Direction), direction), :);
    sourceArtifact = localSourceArtifact(direction);
    sourceHash = sixgr.kpi.hashKPISourceRows(T);
    for i = 1:height(T)
        tr = T(i, :);
        row = localRankTrialRow();
        row.RunId = runId;
        row.ScenarioName = scenarioName;
        row.TrialId = localNum(tr, "TrialId", i);
        row.Direction = direction;
        row.CellId = localFirstNum(tr, ["CellId","CellID","ServingCell","BaseStationID"], NaN);
        row.UEId = localFirstNum(tr, ["UEID","UEIndex","UE"], NaN);
        row.Frame = localNum(tr, "Frame", NaN);
        row.Slot = localNum(tr, "Slot", NaN);
        row.ConfiguredRank = double(cfgRow.ConfiguredRank(1));
        row.ConfiguredLayers = double(cfgRow.ConfiguredLayers(1));
        row.ConfiguredModulation = string(cfgRow.ConfiguredModulation(1));
        row.ConfiguredMCS = double(cfgRow.ConfiguredMCS(1));
        row.ScheduledRank = localFirstNum(tr, ["ScheduledRank","RankIndicator","RI","Layers"], NaN);
        row.ScheduledLayers = localFirstNum(tr, ["ScheduledLayers","Layers"], NaN);
        row.ScheduledModulation = localFirstTextTable(tr, ["ScheduledModulation","Modulation"], "");
        row.ScheduledMCS = localFirstNum(tr, ["ScheduledMCS","MCS","MCSIndex"], NaN);
        row.TransmittedRank = localFirstNum(tr, ["TransmittedRank","Layers"], NaN);
        row.TransmittedLayers = localFirstNum(tr, ["TransmittedLayers","Layers"], NaN);
        row.TransmittedModulation = localFirstTextTable(tr, ["TransmittedModulation","Modulation"], "");
        row.TransmittedMCS = localFirstNum(tr, ["TransmittedMCS","MCS","MCSIndex"], NaN);
        row.ReceiverEstimatedRank = localFirstNum(tr, ["ReceiverEstimatedRank","RankEstimate"], NaN);
        perLayer = localParseVector(localFirstTextTable(tr, ["PostEqSINRPerLayer_dB","LayerSINRdB"], ""));
        if ~isfinite(row.ReceiverEstimatedRank) && ~isempty(perLayer)
            row.ReceiverEstimatedRank = numel(perLayer);
        end
        crcPass = localBool(tr, "CRCPass", false);
        decodeUsable = localBool(tr, "DecodeUsable", crcPass);
        receiverUsable = localBool(tr, "ReceiverUsable", decodeUsable);
        if crcPass && decodeUsable && receiverUsable && isfinite(row.TransmittedLayers)
            if isempty(perLayer)
                row.EffectiveDecodedRank = NaN;
                row.EffectiveDecodedLayers = NaN;
            else
                row.EffectiveDecodedRank = min(row.TransmittedRank, numel(perLayer));
                row.EffectiveDecodedLayers = min(row.TransmittedLayers, numel(perLayer));
            end
        else
            row.EffectiveDecodedRank = 0;
            row.EffectiveDecodedLayers = 0;
        end
        row.EffectiveDecodedModulation = row.TransmittedModulation;
        row.EffectiveDecodedMCS = row.TransmittedMCS;
        row.DMRSPorts = string(strjoin(string(0:(max(1, round(row.TransmittedLayers))-1)), "|"));
        row.PrecoderId = localFirstTextTable(tr, ["AppliedPrecoderPMI","PMI","ConfiguredPMI"], "");
        row.BeamId = localFirstTextTable(tr, ["AppliedBeamIndexSet","SelectedBeamIndex"], "");
        row.CSIReportId = localFirstTextTable(tr, ["CSIReportId","CSIPayloadHex"], "");
        row.LayerSINRdB = localVectorToken(perLayer);
        row.DecodeCrcPass = crcPass;
        row.ExactConfiguredMatch = localExactMatch(row);
        row.MismatchCause = localMismatchCause(row);
        row.AdaptiveMode = logical(cfgRow.AdaptiveMode(1));
        row.FixedAnchorMode = logical(cfgRow.FixedAnchorMode(1));
        row.AdaptationEvidenceId = localFirstTextTable(tr, ["CSIReportId","CSIPayloadHex","GrantContextId"], "");
        row.StrictEligible = ~localBool(tr, "IsWarmupFrame", false);
        row.SourceArtifactRef = sourceArtifact;
        row.SourceRowsHash = sourceHash;
        row.StrictOk = row.StrictEligible && row.DecodeCrcPass && row.ExactConfiguredMatch && ...
            isfinite(row.EffectiveDecodedRank) && row.EffectiveDecodedRank == row.ConfiguredRank;
        if row.FixedAnchorMode && row.StrictEligible && ~row.StrictOk
            row.Status = "fail";
            row.FailureReason = "fixed_anchor_configured_effective_mismatch";
        else
            row.Status = string(localTernary(row.StrictOk || ~row.FixedAnchorMode, "pass", "fail"));
            row.FailureReason = string(localTernary(row.Status == "pass", "", "rank_layer_evidence_not_strict_success"));
        end
        rows(end+1, 1) = row; %#ok<AGROW>
        for l = 1:max(1, round(max(row.TransmittedLayers, 1)))
            lr = localLayerRow();
            lr.RunId = runId;
            lr.TrialId = row.TrialId;
            lr.CellId = row.CellId;
            lr.UEId = row.UEId;
            lr.Direction = direction;
            lr.Slot = row.Slot;
            lr.LayerIndex = l;
            lr.CodewordIndex = localTernary(row.TransmittedLayers <= 4, 1, min(2, ceil(l/4)));
            lr.DMRSPort = l - 1;
            if l <= numel(perLayer), lr.PostEqSINRdB = perLayer(l); end
            lr.EVMdB = localEVMdB(localNum(tr, "EVM_rms", NaN));
            lr.ChannelEstimateNMSEdB = localNum(tr, "NMSE_dB", NaN);
            lr.LLRMeanAbs = localNum(tr, "LLRMeanAbs", NaN);
            lr.DecodeCrcPass = crcPass;
            lr.BER = localSafeDivide(localNum(tr, "BitErrors", NaN), localNum(tr, "BitsCompared", NaN));
            lr.BLERContribution = double(~crcPass);
            lr.Status = string(localTernary(l <= numel(perLayer), "pass", "missing_layer_receiver_metric"));
            layerRows(end+1, 1) = lr; %#ok<AGROW>
        end
    end
end
rankT = struct2table(rows);
layerT = struct2table(layerRows);
end

function T = localConfiguredVsEffective(cfgT, rankT, runId, scenarioName, strictMode)
rows = repmat(localConfiguredEffectiveRow(), 0, 1);
for i = 1:height(cfgT)
    direction = string(cfgT.Direction(i));
    subset = rankT(strcmp(string(rankT.Direction), direction) & logical(rankT.StrictEligible), :);
    row = localConfiguredEffectiveRow();
    row.RunId = runId;
    row.ScenarioName = scenarioName;
    row.Direction = direction;
    row.ConfiguredRank = double(cfgT.ConfiguredRank(i));
    row.ConfiguredLayers = double(cfgT.ConfiguredLayers(i));
    row.ConfiguredModulation = string(cfgT.ConfiguredModulation(i));
    row.ConfiguredMCS = double(cfgT.ConfiguredMCS(i));
    row.StrictEligibleRowCount = height(subset);
    if height(subset) > 0
        row.DominantScheduledRank = localMode(subset.ScheduledRank);
        row.DominantTransmittedRank = localMode(subset.TransmittedRank);
        row.DominantEffectiveDecodedRank = localMode(subset.EffectiveDecodedRank);
        row.DominantScheduledLayers = localMode(subset.ScheduledLayers);
        row.DominantTransmittedLayers = localMode(subset.TransmittedLayers);
        row.DominantEffectiveDecodedLayers = localMode(subset.EffectiveDecodedLayers);
        row.DominantEffectiveModulation = localStringMode(subset.EffectiveDecodedModulation);
        row.DominantEffectiveMCS = localMode(subset.EffectiveDecodedMCS);
        row.ExactMatchRowCount = sum(logical(subset.ExactConfiguredMatch));
        row.ExactMatchPercent = row.ExactMatchRowCount / max(row.StrictEligibleRowCount, 1);
    end
    row.RequiredExactMatchPercent = localTernary(logical(cfgT.FixedAnchorMode(i)) || strictMode, 0.999, NaN);
    row.ScenarioObjectivePass = row.StrictEligibleRowCount > 0 && ...
        (~isfinite(row.RequiredExactMatchPercent) || row.ExactMatchPercent + eps >= row.RequiredExactMatchPercent);
    row.Status = string(localTernary(row.ScenarioObjectivePass, "pass", "fail"));
    row.FailureReason = string(localTernary(row.ScenarioObjectivePass, "", "mimo_configured_effective_mismatch_or_missing_rows"));
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows);
end

function T = localRankUtilization(rankT, runId, scenarioName)
rows = repmat(struct("RunId","", "ScenarioName","", "Direction","", "Rank",NaN, "LayerCount",NaN, ...
    "EligibleRows",0, "DecodeSuccessRows",0, "UsagePercent",NaN, "SuccessPercent",NaN, ...
    "MeanLayerSINRdB",NaN, "MeanBER",NaN, "BLER",NaN, "StrictObjectiveRequired",false, ...
    "StrictObjectivePass",false, "Status","", "FailureReason",""), 0, 1);
for direction = ["DL","UL"]
    subset = rankT(strcmp(string(rankT.Direction), direction) & logical(rankT.StrictEligible), :);
    if isempty(subset), continue; end
    ranks = unique(double(subset.TransmittedRank(isfinite(double(subset.TransmittedRank)))));
    for r = ranks(:).'
        mask = double(subset.TransmittedRank) == r;
        row = rowsTemplate(runId, scenarioName, direction);
        row.Rank = r;
        row.LayerCount = localMode(subset.TransmittedLayers(mask));
        row.EligibleRows = sum(mask);
        row.DecodeSuccessRows = sum(mask & logical(subset.DecodeCrcPass));
        row.UsagePercent = row.EligibleRows / height(subset);
        row.SuccessPercent = row.DecodeSuccessRows / max(row.EligibleRows, 1);
        row.BLER = 1 - row.SuccessPercent;
        row.StrictObjectiveRequired = any(logical(subset.FixedAnchorMode));
        row.StrictObjectivePass = all(logical(subset.StrictOk(mask))) || ~row.StrictObjectiveRequired;
        row.Status = string(localTernary(row.StrictObjectivePass, "pass", "fail"));
        row.FailureReason = string(localTernary(row.StrictObjectivePass, "", "rank_utilization_not_strict_success"));
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows);
end

function row = rowsTemplate(runId, scenarioName, direction)
row = struct("RunId",string(runId), "ScenarioName",string(scenarioName), "Direction",string(direction), ...
    "Rank",NaN, "LayerCount",NaN, "EligibleRows",0, "DecodeSuccessRows",0, "UsagePercent",NaN, ...
    "SuccessPercent",NaN, "MeanLayerSINRdB",NaN, "MeanBER",NaN, "BLER",NaN, ...
    "StrictObjectiveRequired",false, "StrictObjectivePass",false, "Status","not_evaluated", "FailureReason","");
end

function T = localAntennaArrayConfig(cfgT)
rows = repmat(struct("RunId","", "ScenarioName","", "Direction","", "ArrayGeometryId","", ...
    "PhysicalTxAntennaCount",NaN, "PhysicalRxAntennaCount",NaN, "TxRFChainCount",NaN, ...
    "RxRFChainCount",NaN, "TxAntennaPortCount",NaN, "RxAntennaPortCount",NaN, ...
    "NominalCapabilityOnly",true, "SourceHash","", "Status","pass", "FailureReason",""), height(cfgT), 1);
for i = 1:height(cfgT)
    rows(i).RunId = string(cfgT.RunId(i));
    rows(i).ScenarioName = string(cfgT.ScenarioName(i));
    rows(i).Direction = string(cfgT.Direction(i));
    rows(i).ArrayGeometryId = "scenario_config_array_counts";
    rows(i).PhysicalTxAntennaCount = double(cfgT.PhysicalTxAntennaCount(i));
    rows(i).PhysicalRxAntennaCount = double(cfgT.PhysicalRxAntennaCount(i));
    rows(i).TxRFChainCount = double(cfgT.TxRFChainCount(i));
    rows(i).RxRFChainCount = double(cfgT.RxRFChainCount(i));
    rows(i).TxAntennaPortCount = double(cfgT.TxAntennaPortCount(i));
    rows(i).RxAntennaPortCount = double(cfgT.RxAntennaPortCount(i));
    rows(i).SourceHash = string(cfgT.ConfigHash(i));
end
T = struct2table(rows);
end

function T = localAntennaPortMapping(cfgT, rankT)
rows = repmat(struct("RunId","", "ScenarioName","", "Direction","", "TxAntennaPortCount",NaN, ...
    "RxAntennaPortCount",NaN, "DMRSPorts","", "DMRSPortCount",NaN, "ConfiguredLayers",NaN, ...
    "ObservedTransmittedLayers",NaN, "ObservedEffectiveDecodedLayers",NaN, "MappingEvidenceSource","", ...
    "SourceRowsHash","", "Status","", "FailureReason",""), height(cfgT), 1);
for i = 1:height(cfgT)
    direction = string(cfgT.Direction(i));
    sub = rankT(strcmp(string(rankT.Direction), direction), :);
    rows(i).RunId = string(cfgT.RunId(i));
    rows(i).ScenarioName = string(cfgT.ScenarioName(i));
    rows(i).Direction = direction;
    rows(i).TxAntennaPortCount = double(cfgT.TxAntennaPortCount(i));
    rows(i).RxAntennaPortCount = double(cfgT.RxAntennaPortCount(i));
    rows(i).DMRSPorts = string(cfgT.DMRSPorts(i));
    rows(i).DMRSPortCount = double(cfgT.DMRSPortCount(i));
    rows(i).ConfiguredLayers = double(cfgT.ConfiguredLayers(i));
    rows(i).ObservedTransmittedLayers = localMode(localColumn(sub, "TransmittedLayers"));
    rows(i).ObservedEffectiveDecodedLayers = localMode(localColumn(sub, "EffectiveDecodedLayers"));
    rows(i).MappingEvidenceSource = localSourceArtifact(direction);
    if height(sub) > 0
        rows(i).SourceRowsHash = string(sub.SourceRowsHash(1));
    else
        rows(i).SourceRowsHash = "empty";
    end
    ok = height(sub) > 0 && isfinite(rows(i).ObservedTransmittedLayers) && rows(i).ObservedTransmittedLayers <= rows(i).DMRSPortCount;
    rows(i).Status = string(localTernary(ok, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(ok, "", "missing_or_invalid_port_layer_mapping_evidence"));
end
T = struct2table(rows);
end

function T = localPrecoderEvidence(rankT)
rows = repmat(struct("RunId","", "TrialId",NaN, "Direction","", "PrecoderId","", ...
    "PMI","", "PrecoderSource","", "PrecodingActive",false, "SourceRowsHash","", ...
    "Status","", "FailureReason",""), height(rankT), 1);
for i = 1:height(rankT)
    rows(i).RunId = string(rankT.RunId(i));
    rows(i).TrialId = double(rankT.TrialId(i));
    rows(i).Direction = string(rankT.Direction(i));
    rows(i).PrecoderId = string(rankT.PrecoderId(i));
    rows(i).PMI = string(rankT.PrecoderId(i));
    rows(i).PrecoderSource = "air_interface_trial_precoder_fields";
    rows(i).PrecodingActive = strlength(strtrim(string(rankT.PrecoderId(i)))) > 0;
    rows(i).SourceRowsHash = string(rankT.SourceRowsHash(i));
    rows(i).Status = string(localTernary(rows(i).PrecodingActive || double(rankT.ConfiguredLayers(i)) <= 1, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(rows(i).Status == "pass", "", "multi_layer_precoder_evidence_missing"));
end
T = struct2table(rows);
end

function T = localBeamCodebook(cfgT, rankT)
rows = repmat(struct("RunId","", "Direction","", "BeamId","", "AzimuthDeg",NaN, ...
    "ElevationDeg",NaN, "WeightVectorHash","", "BeamGain_dB",NaN, "SourceRowsHash","", ...
    "Status","pass", "FailureReason",""), 0, 1);
for direction = ["DL","UL"]
    sub = rankT(strcmp(string(rankT.Direction), direction), :);
    if isempty(sub), continue; end
    beamIds = unique(string(sub.BeamId));
    beamIds = beamIds(strlength(strtrim(beamIds)) > 0);
    if isempty(beamIds), beamIds = "not_selected"; end
    for i = 1:numel(beamIds)
        isMissingBeamCodebook = beamIds(i) == "not_selected" && any(double(sub.ConfiguredLayers) > 1);
        row = struct("RunId",string(cfgT.RunId(1)), "Direction",direction, "BeamId",beamIds(i), ...
            "AzimuthDeg",NaN, "ElevationDeg",NaN, ...
            "WeightVectorHash",sixgr.mimo.hashMIMOConfig(struct("direction",direction,"beam",beamIds(i))), ...
            "BeamGain_dB",NaN, "SourceRowsHash",string(sub.SourceRowsHash(1)), ...
            "Status",string(localTernary(~isMissingBeamCodebook, "pass", "fail")), ...
            "FailureReason",string(localTernary(~isMissingBeamCodebook, "", "beam_codebook_missing_for_mimo_rows")));
        rows(end+1, 1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows);
end

function T = localBeamSweep(rankT)
rows = repmat(struct("RunId","", "TrialId",NaN, "Direction","", "SelectedBeamId","", ...
    "CSIReportId","", "MeasurementSource","", "SourceRowsHash","", "Status","", "FailureReason",""), height(rankT), 1);
for i = 1:height(rankT)
    rows(i).RunId = string(rankT.RunId(i));
    rows(i).TrialId = double(rankT.TrialId(i));
    rows(i).Direction = string(rankT.Direction(i));
    rows(i).SelectedBeamId = string(rankT.BeamId(i));
    rows(i).CSIReportId = string(rankT.CSIReportId(i));
    rows(i).MeasurementSource = string(localTernary(strlength(strtrim(rows(i).CSIReportId)) > 0, "csi_or_grant_runtime_evidence", "air_interface_trial_row"));
    rows(i).SourceRowsHash = string(rankT.SourceRowsHash(i));
    ok = strlength(strtrim(rows(i).SelectedBeamId)) > 0 || double(rankT.ConfiguredLayers(i)) <= 1;
    rows(i).Status = string(localTernary(ok, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(ok, "", "beam_selection_evidence_missing_for_mimo_row"));
end
T = struct2table(rows);
end

function T = localNegativeTrials(cfgT, rankT, configuredEffective, runId)
rows = repmat(struct("RunId","", "NegativeTrialType","", "InjectedFault","", ...
    "ExpectedFailureStage","", "ObservedFailureStage","", "ExactConfiguredMatch",false, ...
    "DecodeCrcPass",false, "StrictOk",false, "NegativeExpectedOk",false, "FailureReason",""), 0, 1);
for i = 1:height(configuredEffective)
    if logical(configuredEffective.ScenarioObjectivePass(i)), continue; end
    row = struct("RunId",string(runId), "NegativeTrialType","configured_effective_collapse", ...
        "InjectedFault","observed_runtime_rank_layer_or_mcs_mismatch", ...
        "ExpectedFailureStage","configured_vs_effective_gate", ...
        "ObservedFailureStage","configured_vs_effective_gate", ...
        "ExactConfiguredMatch",false, "DecodeCrcPass",false, "StrictOk",false, ...
        "NegativeExpectedOk",true, "FailureReason",string(configuredEffective.FailureReason(i)));
    rows(end+1, 1) = row; %#ok<AGROW>
end
if isempty(rows)
    row = struct("RunId",string(runId), "NegativeTrialType","no_negative_runtime_case_observed", ...
        "InjectedFault","none", "ExpectedFailureStage","not_applicable", ...
        "ObservedFailureStage","not_applicable", "ExactConfiguredMatch",true, ...
        "DecodeCrcPass",true, "StrictOk",false, "NegativeExpectedOk",true, "FailureReason","");
    rows(end+1, 1) = row;
end
T = struct2table(rows);
end

function T = localOracleGuard(rankT, runId)
violation = false(height(rankT), 1);
for i = 1:height(rankT)
    violation(i) = isfinite(double(rankT.EffectiveDecodedRank(i))) && ...
        double(rankT.EffectiveDecodedRank(i)) == double(rankT.ConfiguredRank(i)) && ...
        strlength(strtrim(string(rankT.LayerSINRdB(i)))) == 0 && logical(rankT.DecodeCrcPass(i));
end
rows = repmat(struct("RunId","", "TrialId",NaN, "Stage","effective_rank_derivation", ...
    "OracleFieldName","ConfiguredRank", "WasAccessed",false, "Allowed",false, ...
    "Violation",false, "Status","", "FailureReason",""), max(height(rankT),1), 1);
if height(rankT) == 0
    rows(1).RunId = string(runId);
    rows(1).TrialId = NaN;
    rows(1).Status = "fail";
    rows(1).FailureReason = "no_rank_layer_trial_rows";
else
    for i = 1:height(rankT)
        rows(i).RunId = string(runId);
        rows(i).TrialId = double(rankT.TrialId(i));
        rows(i).Violation = violation(i);
        rows(i).Status = string(localTernary(~violation(i), "pass", "fail"));
        rows(i).FailureReason = string(localTernary(~violation(i), "", "effective_rank_matches_config_without_receiver_layer_metric"));
    end
end
T = struct2table(rows);
end

function caps = localToolboxCapabilities()
caps = struct();
caps.MATLABVersion = string(version);
caps.ToolboxVersion = "";
caps.nrPDSCHConfigAvailable = exist("nrPDSCHConfig", "file") == 2;
caps.nrPUSCHConfigAvailable = exist("nrPUSCHConfig", "file") == 2;
caps.nrPDSCHAvailable = exist("nrPDSCH", "file") == 2;
caps.nrPDSCHDecodeAvailable = exist("nrPDSCHDecode", "file") == 2;
caps.nrPUSCHAvailable = exist("nrPUSCH", "file") == 2;
caps.nrPUSCHDecodeAvailable = exist("nrPUSCHDecode", "file") == 2;
caps.nrCDLChannelAvailable = exist("nrCDLChannel", "file") == 2;
caps.nrTDLChannelAvailable = exist("nrTDLChannel", "file") == 2;
caps.nrChannelEstimateAvailable = exist("nrChannelEstimate", "file") == 2;
caps.nrEqualizeMMSEAvailable = exist("nrEqualizeMMSE", "file") == 2;
caps.nrCSIRSAvailable = exist("nrCSIRS", "file") == 2;
caps.nrSRSAvailable = exist("nrSRS", "file") == 2;
caps.PhasedArrayToolboxAvailable = exist("phased.URA", "class") == 8 || exist("phased.URA", "file") == 2;
caps.StrictModeToolboxFallbackAllowed = false;
caps.GeneratedAt = string(datetime("now", "TimeZone", "UTC", "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
caps.ProducerModule = "sixgr.mimo.resolveNominalVsEffectiveMIMO";
end

function T = localRawTable(rawTrials, direction)
T = table();
if isstruct(rawTrials) && isfield(rawTrials, char(direction)) && istable(rawTrials.(char(direction)))
    T = rawTrials.(char(direction));
end
end

function out = localColumn(T, name)
out = [];
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    out = double(T.(string(name)));
end
end

function v = localNum(T, name, defaultValue)
v = defaultValue;
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    try
        v = double(T.(string(name))(1));
    catch
        v = str2double(string(T.(string(name))(1)));
    end
end
end

function v = localFirstNum(T, names, defaultValue)
v = defaultValue;
for name = string(names)
    v = localNum(T, name, NaN);
    if isfinite(v), return; end
end
v = defaultValue;
end

function s = localFirstTextTable(T, names, defaultValue)
s = string(defaultValue);
for name = string(names)
    if istable(T) && ismember(name, string(T.Properties.VariableNames))
        raw = string(T.(name)(1));
        raw = strtrim(raw);
        if localUsableText(raw)
            s = raw;
            return;
        end
    end
end
end

function tf = localBool(T, name, defaultValue)
tf = logical(defaultValue);
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(string(name))(1);
    if islogical(raw)
        tf = logical(raw);
    elseif isnumeric(raw)
        tf = double(raw) ~= 0;
    else
        tf = ismember(lower(strtrim(string(raw))), ["true","1","yes","pass","ok"]);
    end
end
end

function vec = localParseVector(token)
s = strtrim(string(token));
if strlength(s) == 0
    vec = [];
    return;
end
parts = split(regexprep(s, "[,; ]+", "|"), "|");
vec = str2double(parts);
vec = vec(isfinite(vec));
end

function token = localVectorToken(vec)
if isempty(vec)
    token = "";
else
    token = strjoin(compose("%.9g", double(vec(:)).'), "|");
end
end

function tf = localExactMatch(row)
tf = isfinite(row.EffectiveDecodedRank) && isfinite(row.EffectiveDecodedLayers) && ...
    row.EffectiveDecodedRank == row.ConfiguredRank && ...
    row.EffectiveDecodedLayers == row.ConfiguredLayers && ...
    (strlength(row.ConfiguredModulation) == 0 || row.EffectiveDecodedModulation == row.ConfiguredModulation) && ...
    (~isfinite(row.ConfiguredMCS) || row.EffectiveDecodedMCS == row.ConfiguredMCS);
end

function reason = localMismatchCause(row)
parts = strings(0,1);
if ~(isfinite(row.EffectiveDecodedRank) && row.EffectiveDecodedRank == row.ConfiguredRank)
    parts(end+1,1) = "effective_rank_mismatch"; %#ok<AGROW>
end
if ~(isfinite(row.EffectiveDecodedLayers) && row.EffectiveDecodedLayers == row.ConfiguredLayers)
    parts(end+1,1) = "effective_layers_mismatch"; %#ok<AGROW>
end
if strlength(row.ConfiguredModulation) > 0 && row.EffectiveDecodedModulation ~= row.ConfiguredModulation
    parts(end+1,1) = "modulation_mismatch"; %#ok<AGROW>
end
if isfinite(row.ConfiguredMCS) && row.EffectiveDecodedMCS ~= row.ConfiguredMCS
    parts(end+1,1) = "mcs_mismatch"; %#ok<AGROW>
end
if isempty(parts)
    reason = "";
else
    reason = strjoin(parts, "|");
end
end

function v = localMode(vals)
vals = double(vals(:));
vals = vals(isfinite(vals));
if isempty(vals)
    v = NaN;
    return;
end
[u, ~, idx] = unique(vals);
counts = accumarray(idx, 1);
[~, imax] = max(counts);
v = u(imax);
end

function v = localStringMode(vals)
vals = strtrim(string(vals(:)));
vals = vals(strlength(vals) > 0);
if isempty(vals)
    v = "";
    return;
end
[u, ~, idx] = unique(vals);
counts = accumarray(idx, 1);
[~, imax] = max(counts);
v = u(imax);
end

function y = localSafeDivide(a, b)
if isfinite(a) && isfinite(b) && b > 0
    y = a / b;
else
    y = NaN;
end
end

function y = localEVMdB(evm)
if isfinite(evm) && evm > 0
    y = 20 * log10(evm);
else
    y = NaN;
end
end

function artifact = localSourceArtifact(direction)
if direction == "UL"
    artifact = "air_interface/csv/ul_pusch_trials.csv";
else
    artifact = "air_interface/csv/dl_pdsch_trials.csv";
end
end

function b = localColumnLogical(T, name, defaultValue)
b = repmat(logical(defaultValue), height(T), 1);
if istable(T) && ismember(string(name), string(T.Properties.VariableNames))
    raw = T.(string(name));
    if islogical(raw)
        b = raw(:);
    elseif isnumeric(raw)
        b = double(raw(:)) ~= 0;
    else
        b = ismember(lower(strtrim(string(raw(:)))), ["true","1","yes","pass","ok"]);
    end
end
end

function row = localRankTrialRow()
row = struct("RunId","", "ScenarioName","", "TrialId",NaN, "Direction","", ...
    "CellId",NaN, "UEId",NaN, "Frame",NaN, "Slot",NaN, ...
    "ConfiguredRank",NaN, "ConfiguredLayers",NaN, "ScheduledRank",NaN, ...
    "ScheduledLayers",NaN, "TransmittedRank",NaN, "TransmittedLayers",NaN, ...
    "ReceiverEstimatedRank",NaN, "EffectiveDecodedRank",NaN, "EffectiveDecodedLayers",NaN, ...
    "ConfiguredModulation","", "ScheduledModulation","", "TransmittedModulation","", ...
    "EffectiveDecodedModulation","", "ConfiguredMCS",NaN, "ScheduledMCS",NaN, ...
    "TransmittedMCS",NaN, "EffectiveDecodedMCS",NaN, "DMRSPorts","", ...
    "PrecoderId","", "BeamId","", "CSIReportId","", "LayerSINRdB","", ...
    "DecodeCrcPass",false, "ExactConfiguredMatch",false, "MismatchCause","", ...
    "AdaptiveMode",false, "AdaptationEvidenceId","", "FixedAnchorMode",false, ...
    "StrictEligible",false, "StrictOk",false, "SourceArtifactRef","", "SourceRowsHash","", ...
    "Status","not_evaluated", "FailureReason","");
end

function row = localLayerRow()
row = struct("RunId","", "TrialId",NaN, "CellId",NaN, "UEId",NaN, "Direction","", ...
    "Slot",NaN, "LayerIndex",NaN, "CodewordIndex",NaN, "DMRSPort",NaN, ...
    "PostEqSINRdB",NaN, "EVMdB",NaN, "ChannelEstimateNMSEdB",NaN, ...
    "LLRMeanAbs",NaN, "DecodeCrcPass",false, "BER",NaN, "BLERContribution",NaN, ...
    "Status","not_evaluated");
end

function row = localConfiguredEffectiveRow()
row = struct("RunId","", "ScenarioName","", "Direction","", ...
    "ConfiguredRank",NaN, "DominantScheduledRank",NaN, "DominantTransmittedRank",NaN, ...
    "DominantEffectiveDecodedRank",NaN, "ConfiguredLayers",NaN, "DominantScheduledLayers",NaN, ...
    "DominantTransmittedLayers",NaN, "DominantEffectiveDecodedLayers",NaN, ...
    "ConfiguredModulation","", "DominantEffectiveModulation","", "ConfiguredMCS",NaN, ...
    "DominantEffectiveMCS",NaN, "StrictEligibleRowCount",0, "ExactMatchRowCount",0, ...
    "ExactMatchPercent",NaN, "RequiredExactMatchPercent",NaN, "ScenarioObjectivePass",false, ...
    "Status","not_evaluated", "FailureReason","");
end

function tf = localAllStatusPass(T)
tf = istable(T) && height(T) > 0 && ismember("Status", string(T.Properties.VariableNames)) && ...
    all(strcmp(string(T.Status), "pass"));
end

function tf = localUsableText(s)
s = lower(strtrim(string(s)));
tf = ~ismissing(s) && strlength(s) > 0 && ~ismember(s, ["nan","<missing>","missing","none","unavailable"]);
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
