function out = resolveNominalVsEffectiveMIMO(varargin)
%RESOLVENOMINALVSEFFECTIVEMIMO Resolve runtime MIMO rank or build evidence.
%
%   OUT = sixgr.mimo.resolveNominalVsEffectiveMIMO(CFG, RAWTRIALS, ...)
%   preserves the artifact/evidence builder API used by LLS exports.
%
%   OUT = sixgr.mimo.resolveNominalVsEffectiveMIMO(CARRIER, PDSCH, H, ...
%   NOISEVAR, NOMINALRANK, CFG) returns one SVD/codebook rank decision for
%   a measured channel matrix H. This Prompt 5 call form is intentionally
%   separate from the export path so nominal config is never promoted to
%   effective runtime evidence.

if nargin >= 6 && (isnumeric(varargin{3}) || islogical(varargin{3}))
    out = localResolveRuntimeRank(varargin{1}, varargin{2}, varargin{3}, ...
        varargin{4}, varargin{5}, varargin{6});
    return;
end

if nargin < 2
    error("sixgr:mimo:resolveNominalVsEffectiveMIMO:BadInput", ...
        "Provide either (cfg, rawTrials, ...) or (carrier, pdsch, H, noiseVar, nominalRank, cfg).");
end

cfg = varargin{1};
rawTrials = varargin{2};
extraArgs = varargin(3:end);

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.addParameter("StrictMode", false, @(x) islogical(x) || isnumeric(x));
ip.parse(extraArgs{:});
runId = string(ip.Results.RunId);
scenarioName = string(ip.Results.ScenarioName);
strictMode = logical(ip.Results.StrictMode);

cfgT = sixgr.mimo.buildMIMOConfigFromScenario(cfg, "RunId", runId, "ScenarioName", scenarioName);
[rankTrials, layerMetrics] = localBuildRankAndLayerTables(cfgT, rawTrials, runId, scenarioName);
cfgT = localAttachRuntimeEvidenceSummary(cfgT, rankTrials);
configAudit = sixgr.mimo.validateMIMOConfigStrict(cfgT);
configuredEffective = localConfiguredVsEffective(cfgT, rankTrials, runId, scenarioName, strictMode);
cfgT = localAttachRuntimeValidationStatus(cfgT, configuredEffective, configAudit);
rankUtil = localRankUtilization(rankTrials, runId, scenarioName);
antennaArray = localAntennaArrayConfig(cfgT, rankTrials);
portMapping = localAntennaPortMapping(cfgT, rankTrials);
precoderEvidence = localPrecoderEvidence(rankTrials);
beamCodebook = localBeamCodebook(cfgT, rankTrials);
beamSweep = localBeamSweep(rankTrials);
negativeTrials = localNegativeTrials();
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
out.StrictGateSummary = localStrictGateSummary(configAudit, configuredEffective, ...
    antennaArray, portMapping, precoderEvidence, beamCodebook, beamSweep, oracleGuard);
out.StrictOk = height(out.StrictGateSummary) > 0 && all(logical(out.StrictGateSummary.Pass));
failed = out.StrictGateSummary(~logical(out.StrictGateSummary.Pass), :);
if isempty(failed)
    out.FailureReason = "";
else
    out.FailureReason = strjoin(string(failed.Gate) + ":" + ...
        string(failed.FailureReason), ";");
end
end

function T = localStrictGateSummary(configAudit, configuredEffective, antennaArray, ...
        portMapping, precoderEvidence, beamCodebook, beamSweep, oracleGuard)
gateNames = [ ...
    "configuration_validation"; ...
    "configured_vs_effective"; ...
    "antenna_runtime_domain"; ...
    "antenna_port_mapping"; ...
    "applied_precoder"; ...
    "beam_codebook"; ...
    "beam_sweep_measurement"; ...
    "receiver_oracle_guard"];
tables = {configAudit; configuredEffective; antennaArray; portMapping; ...
    precoderEvidence; beamCodebook; beamSweep; oracleGuard};
passFields = ["Pass"; "ScenarioObjectivePass"; repmat("Status", 6, 1)];
n = numel(gateNames);
rowCount = zeros(n, 1);
pass = false(n, 1);
failureReason = strings(n, 1);
for i = 1:n
    Ti = tables{i};
    rowCount(i) = localTableHeight(Ti);
    [pass(i), failureReason(i)] = localGateStatus(Ti, passFields(i));
end
T = table(gateNames, rowCount, pass, failureReason, ...
    'VariableNames', {'Gate','EvidenceRowCount','Pass','FailureReason'});
end

function [pass, reason] = localGateStatus(T, passField)
pass = false;
reason = "missing_evidence_rows";
if ~istable(T) || height(T) == 0
    return;
end
passField = string(passField);
if passField == "Status"
    if ~ismember("Status", string(T.Properties.VariableNames))
        reason = "missing_status_field";
        return;
    end
    rowPass = lower(strtrim(string(T.Status))) == "pass";
else
    if ~ismember(passField, string(T.Properties.VariableNames))
        reason = "missing_" + lower(passField) + "_field";
        return;
    end
    rowPass = logical(T.(char(passField)));
end
pass = all(rowPass);
if pass
    reason = "";
    return;
end
failed = find(~rowPass);
reasonParts = strings(0, 1);
if ismember("Direction", string(T.Properties.VariableNames))
    reasonParts(end+1, 1) = "directions=" + ...
        strjoin(unique(upper(strtrim(string(T.Direction(failed))))), "|"); %#ok<AGROW>
end
if ismember("FailureReason", string(T.Properties.VariableNames))
    details = unique(strtrim(string(T.FailureReason(failed))));
    details = details(strlength(details) > 0);
    if ~isempty(details)
        reasonParts(end+1, 1) = "details=" + strjoin(details, "|"); %#ok<AGROW>
    end
end
if isempty(reasonParts)
    reason = "failed_rows=" + strjoin(string(failed(:).'), "|");
else
    reason = strjoin(reasonParts, ",");
end
end

function n = localTableHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function decision = localResolveRuntimeRank(carrier, pdsch, H, noiseVar, nominalRank, cfg)
% Receiver-aware measured-channel rank/codebook decision.
if nargin < 6 || ~isstruct(cfg)
    cfg = struct();
end
Hwb = localWidebandRuntimeChannel(H);
if isempty(Hwb)
    error("sixgr:mimo:RuntimeRank:EmptyChannel", ...
        "Runtime MIMO rank selection requires a non-empty measured channel matrix.");
end
nRx = size(Hwb, 1);
nTx = size(Hwb, 2);
nominalRank = double(nominalRank);
if ~(isscalar(nominalRank) && isfinite(nominalRank) && nominalRank >= 1 && ...
        nominalRank == round(nominalRank))
    error("sixgr:mimo:InvalidRI","Nominal rank must be a positive integer.");
end
maxRank = double(localFirstFiniteStruct(cfg, ...
    ["MaxRank","maxRank","mimo.maxRank","phy.mimo.maxRank"], nominalRank));
if ~(isscalar(maxRank) && isfinite(maxRank) && maxRank >= 1 && maxRank == round(maxRank))
    error("sixgr:mimo:InvalidRI","Maximum rank must be a positive integer.");
end
rankLimit = min([maxRank,nominalRank,nRx,nTx]);
strict = logical(sixgr.util.structGet(cfg,"Strict", ...
    sixgr.util.structGet(cfg,"mimo.strict",false)));
if strict && (rankLimit ~= maxRank || nominalRank > rankLimit)
    error("sixgr:mimo:UnsupportedRank", ...
        "Requested rank domain exceeds measured antenna capability.");
end
if ~(isscalar(noiseVar) && isnumeric(noiseVar) && isfinite(noiseVar) && noiseVar > 0)
    error("sixgr:mimo:MissingMeasurementState", ...
        "Runtime rank selection requires measured positive noise variance.");
end

rates = NaN(max(rankLimit,2),1);
precoders = cell(rankLimit,1);
pmiValues = cell(rankLimit,1);
pmi2Values = NaN(rankLimit,1);
selectionInfo = cell(rankLimit,1);
for nu = 1:rankLimit
    rankCfg = cfg;
    rankCfg.NoiseVariance = double(noiseVar);
    if isfield(cfg,"CandidateMatricesByRank")
        rankCfg.CandidateMatrices = cfg.CandidateMatricesByRank{nu};
    end
    [precoders{nu},pmiValues{nu},pmi2Values(nu),selectionInfo{nu}] = ...
        sixgr.mimo.selectPMI(Hwb,nu,nTx,nRx,rankCfg);
    rates(nu) = selectionInfo{nu}.SelectedMetric;
end
[~,effectiveRank] = max(rates(1:rankLimit));
Wcb = precoders{effectiveRank};
pmi1 = pmiValues{effectiveRank};
pmi2 = pmi2Values(effectiveRank);
reason = "rank"+string(effectiveRank)+"_selected_by_posteq_mutual_information";

% Singular values are diagnostic only and do not participate in selection.
sv = svd(double(Hwb));
layerEquivalentSNR = NaN(max(rankLimit,2),1);
for nu = 1:rankLimit
    layerEquivalentSNR(nu) = max(2^(rates(nu)/nu)-1,0);
end
conditionDB = localConditionNumberForRank(sv,max(1,min(effectiveRank,numel(sv))));

decision = struct();
decision.EffectiveRank = double(effectiveRank);
decision.NominalRank = double(nominalRank);
decision.ExactMatch = logical(effectiveRank == nominalRank);
decision.Precoder_W = Wcb;
decision.Precoder_W_SVD = [];
decision.PMI_i1 = pmi1;
decision.PMI_i2 = pmi2;
decision.ConditionNumber_dB = conditionDB;
decision.SingularValues = sv;
decision.Rate_rank1_bps = rates(1);
decision.Rate_rank2_bps = localVectorValueOrNaN(rates, 2);
decision.SNR_layer1_dB = 10*log10(max(localVectorValueOrNaN(layerEquivalentSNR,1),realmin));
decision.SNR_layer2_dB = 10*log10(max(localVectorValueOrNaN(layerEquivalentSNR,2),realmin));
decision.RankDecisionReason = char(reason);
decision.ConditionNumberOk = isfinite(conditionDB);
decision.LayerSNROk = isfinite(layerEquivalentSNR(effectiveRank));
decision.RateGainOk = logical(numel(rates) >= 2 && isfinite(rates(2)) && rates(2) > rates(1));
decision.RuntimeEvidenceSource = "measured_channel_posteq_mutual_information";
decision.ConfiguredSNRUsed = false;
decision.SVDThresholdUsed = false;
decision.SelectedMatrixSHA256 = sixgr.phy.mimo.MatrixContract.digest(Wcb);
decision.SelectionInfo = selectionInfo{effectiveRank};
decision.NumRxAntennas = double(nRx);
decision.NumTxPorts = double(nTx);
decision.CodebookType = string(localFirstTextStruct(cfg, ["CodebookType","codebookType","phy.csi.codebookType"], "type1"));
decision.CarrierClass = string(class(carrier));
decision.PDSCHClass = string(class(pdsch));
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
        row.ConfiguredInitialMCS = double(cfgRow.ConfiguredInitialMCS(1));
        row.ConfiguredMaximumMCS = double(cfgRow.ConfiguredMaximumMCS(1));
        row.ConfiguredMCSSelectionPolicy = string(cfgRow.ConfiguredMCSSelectionPolicy(1));
        row.ScheduledRank = localFirstNum(tr, ["ScheduledRank","ScheduledLayers","PrecodingNumLayers","RankIndicator","RI","Layers"], NaN);
        row.ScheduledLayers = localFirstNum(tr, ["ScheduledLayers","PrecodingNumLayers","Layers"], NaN);
        row.ScheduledModulation = localFirstTextTable(tr, ["ScheduledModulation","Modulation"], "");
        row.ScheduledMCS = localFirstNum(tr, ["ScheduledMCS","MCS","MCSIndex"], NaN);
        row.TransmittedRank = localFirstNum(tr, ["TransmittedRank","TransmittedLayers","PrecodingNumLayers","Layers"], NaN);
        row.TransmittedLayers = localFirstNum(tr, ["TransmittedLayers","PrecodingNumLayers","Layers"], NaN);
        row.TransmittedModulation = localFirstTextTable(tr, ["TransmittedModulation","Modulation"], "");
        row.TransmittedMCS = localFirstNum(tr, ["TransmittedMCS","MCS","MCSIndex"], NaN);
        row.ActualMCSSelectionMode = localFirstTextTable(tr, ["ActualMCSSelectionMode"], "");
        row.MCSSelectionSource = localFirstTextTable(tr, ["MCSSelectionSource"], "");
        row.MCSAuthority = localFirstTextTable(tr, ["MCSAuthority","GrantOperatingPointSource"], "");
        row.ModulationAuthority = localFirstTextTable(tr, ["ModulationAuthority","GrantOperatingPointSource"], "");
        row.AppliedOperatingPointSource = localFirstTextTable(tr, ["AppliedOperatingPointSource","GrantOperatingPointSource"], "");
        row.LinkAdaptationScheduled = localBool(tr, "LinkAdaptationScheduled", false);
        row.LinkAdaptationApplied = localBool(tr, "LinkAdaptationApplied", false);
        row.WidebandCQI = localFirstNum(tr, ["WidebandCQI","CQI"], NaN);
        row.CQIDerivedMCS = localFirstNum(tr, ["CQIDerivedMCS","RawCQIDerivedMCS"], NaN);
        row.MCSValueStatus = localFirstTextTable(tr, ["MCSValueStatus"], "");
        % ReceiverEstimatedRank is the rank of the data observation that was
        % actually equalized/decoded.  RankEstimate in the primary DL row
        % may instead describe a wider CSI-RS channel (for example two CSI
        % ports while PDSCH is scheduled rank one), so retain that distinct
        % measurement under an explicit spatial-channel contract.
        row.ReceiverEstimatedRank = localFirstNum(tr, ["ReceiverEstimatedRank"], NaN);
        row.SpatialChannelRankEstimate = localFirstNum(tr, ...
            ["SpatialChannelRankEstimate","RankEstimate"], NaN);
        row.NumRxAntennas = localFirstNum(tr, ["NumRxAntennas","NumRxAnt","RxAntennaCount"], NaN);
        row.NumTxPorts = localFirstNum(tr, ["NumTxPorts","PrecodingNumPorts","TxAntennaPortCount"], NaN);
        row.TxWaveformColumns = localFirstNum(tr, ...
            ["TxWaveformColumns","PhysicalTxAntennas"], NaN);
        row.PhysicalTxAntennas = localFirstNum(tr, ...
            ["PhysicalTxAntennas","TxWaveformColumns"], NaN);
        row.RxWaveformBranches = localFirstNum(tr, ...
            ["RxWaveformBranches","PhysicalRxAntennas"], NaN);
        row.PhysicalRxAntennas = localFirstNum(tr, ...
            ["PhysicalRxAntennas","RxWaveformBranches"], NaN);
        row.LogicalTxPortCount = localFirstNum(tr, ...
            ["NumLogicalTxPorts","PrecodingNumLogicalPorts","PrecodingNumLayers","Layers"],NaN);
        row.LogicalRxBranchCount = localFirstNum(tr, ...
            ["NumLogicalRxBranches","EffectiveDecodedLayers","PrecodingNumLayers","Layers"],NaN);
        row.BSAntennaNumPorts = localFirstNum(tr, ...
            ["BSAntennaNumPorts","ConfiguredBSAntennaCount"],NaN);
        row.UEAntennaNumPorts = localFirstNum(tr, ...
            ["UEAntennaNumPorts","ConfiguredUEAntennaCount"],NaN);
        row.BSAntennaElements = localFirstNum(tr, ...
            ["BSAntennaElements","ConfiguredBSAntennaCount"],NaN);
        row.UEAntennaElements = localFirstNum(tr, ...
            ["UEAntennaElements","ConfiguredUEAntennaCount"],NaN);
        csiMeasurementId = localFirstTextTable(tr, ...
            ["CSIMeasurementID","CSIReportId"], "");
        if direction == "DL" && strlength(strtrim(csiMeasurementId)) > 0
            row.SpatialChannelRankDomain = "csi_rs_reference_port_channel";
            row.SpatialChannelRankSource = localFirstTextTable(tr, ...
                ["CSIMeasurementProvenance","CSIChannelEstimateSource", ...
                "RankSelectionSource"], "runtime_measured_csi_rs_channel");
            row.SpatialChannelTxPorts = row.BSAntennaNumPorts;
        elseif direction == "UL" && localBool(tr, ...
                "SRSChannelEstimateAvailable", false)
            row.SpatialChannelRankDomain = "srs_reference_port_channel";
            row.SpatialChannelRankSource = localFirstTextTable(tr, ...
                ["SRSChannelEstimateSource","RankSelectionSource"], ...
                "runtime_measured_srs_channel");
            row.SpatialChannelTxPorts = row.UEAntennaNumPorts;
        else
            row.SpatialChannelRankDomain = lower(direction) + ...
                "_scheduled_data_port_channel";
            row.SpatialChannelRankSource = localFirstTextTable(tr, ...
                ["RankSelectionSource","ChannelEstimateSource"], ...
                "runtime_scheduled_data_channel");
            row.SpatialChannelTxPorts = row.NumTxPorts;
        end
        row.SpatialChannelRxAntennas = row.NumRxAntennas;
        row.AntennaRuntimeObjectCreated = localBool( ...
            tr,"AntennaRuntimeObjectCreated",false);
        row.ChannelUsesSameRuntimeAntennaAssumptions = localBool( ...
            tr,"ChannelUsesSameRuntimeAntennaAssumptions",false);
        row.ConditionNumber_dB = localFirstNum(tr, ["ConditionNumber_dB","ConditionNumber"], NaN);
        row.RuntimeRI = localFirstNum(tr, ["RuntimeRI","RankIndicator","RI"], NaN);
        row.RuntimePMI = localFirstNum(tr, ["RuntimePMI","AppliedPrecoderPMI","PMI","ConfiguredPMI"], NaN);
        row.RuntimeRankSelectionSource = localFirstTextTable(tr, ...
            ["RuntimeRankSelectionSource","RankSelectionSource","EffectiveRankSource","CSIReportMode","CQISource"], "");
        row.EffectiveRankDecisionReason = localFirstTextTable(tr, ...
            ["EffectiveRankDecisionReason","RankDecisionReason","MIMORankDecisionReason"], "");
        row.RateRank1_bpsHz = localFirstNum(tr, ["Rate_rank1_bps","RateRank1_bpsHz","RateRank1"], NaN);
        row.RateRank2_bpsHz = localFirstNum(tr, ["Rate_rank2_bps","RateRank2_bpsHz","RateRank2"], NaN);
        perLayer = localParseVector(localFirstTextTable(tr, ["PostEqSINRPerLayer_dB","LayerSINRdB"], ""));
        if ~isfinite(row.ReceiverEstimatedRank) && ~isempty(perLayer)
            row.ReceiverEstimatedRank = numel(perLayer);
        end
        if ~isfinite(row.ReceiverEstimatedRank) && ...
                isfinite(row.SpatialChannelRankEstimate) && ...
                isfinite(row.NumTxPorts) && isfinite(row.NumRxAntennas) && ...
                row.SpatialChannelRankEstimate <= ...
                min(row.NumTxPorts, row.NumRxAntennas)
            row.ReceiverEstimatedRank = row.SpatialChannelRankEstimate;
        end
        % Receiver-estimated rank is a receiver observation.  Never fill it
        % from the transmitted/configured rank when the trial has no
        % receiver-side per-layer or explicit rank evidence.
        crcPass = localBool(tr, "CRCPass", false);
        decodeUsable = localBool(tr, "DecodeUsable", crcPass);
        receiverUsable = localBool(tr, "ReceiverUsable", decodeUsable);
        if crcPass && decodeUsable && receiverUsable && isfinite(row.TransmittedLayers)
            rawEffectiveRank = localFirstNum(tr, ["EffectiveDecodedRank","EffectiveRank"], NaN);
            rawEffectiveLayers = localFirstNum(tr, ["EffectiveDecodedLayers","EffectiveLayers"], NaN);
            rawEffectiveSource = localFirstTextTable(tr, ...
                ["EffectiveRankSource","EffectiveDecodedRankSource","RuntimeRankSelectionSource"], "");
            if isfinite(rawEffectiveRank) && isfinite(rawEffectiveLayers) && ...
                    localRuntimeRankEvidenceAllowed(rawEffectiveSource, perLayer)
                row.EffectiveDecodedRank = rawEffectiveRank;
                row.EffectiveDecodedLayers = rawEffectiveLayers;
            elseif isempty(perLayer)
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
        row.AdaptiveMode = logical(cfgRow.AdaptiveMode(1));
        row.FixedAnchorMode = logical(cfgRow.FixedAnchorMode(1));
        row.AdaptiveFeedbackDecisionObserved = ...
            localAdaptiveFeedbackDecisionObserved(row);
        row.MUExecutionRequired = logical(cfgRow.ConfiguredMUMIMOEnabled(1));
        row.RequiredMUUserCount = double(cfgRow.ConfiguredMUUsersPerPRB(1));
        row.RequiredMULeakageThreshold_dB = double(cfgRow.ConfiguredMUMIMOLeakageThreshold_dB(1));
        row.RequiredMUExecutionMode = string(cfgRow.ConfiguredMUMIMOExecutionMode(1));
        row.MUMIMOEnabled = localBool(tr, "MUMIMOEnabled", false);
        row.MUMIMOGroupSize = localFirstNum(tr, ["MUMIMOGroupSize","MUGroupSize"], NaN);
        row.MUMIMOGroupId = localFirstNum(tr, ["MUMIMOGroupId","MUGroupId"], NaN);
        row.MUMIMOPairingStatus = localFirstTextTable(tr, ["MUMIMOPairingStatus","MUPairingStatus"], "");
        row.MUMIMOPairingMetricSource = localFirstTextTable(tr, ["MUMIMOPairingMetricSource","MUPairingMetricSource"], "");
        row.MUMIMOPairingMetricValue_dB = localFirstNum(tr, ["MUMIMOPairingMetricValue_dB","MUPairingMetricValue_dB"], NaN);
        row.MUMIMOPairingEvidenceSource = localFirstTextTable(tr, ["MUMIMOPairingEvidenceSource","MUPairingEvidenceSource"], "");
        row.MUMIMOSpatialDesignContractVersion = localFirstTextTable(tr, ...
            ["MUMIMOSpatialDesignContractVersion"], "");
        row.MUMIMOSpatialSignatureSubspaceMode = localFirstTextTable(tr, ...
            ["MUMIMOSpatialSignatureSubspaceMode"], "");
        row.MUMIMOSpatialDesignEvidenceSource = localFirstTextTable(tr, ...
            ["MUMIMOSpatialDesignEvidenceSource"], "");
        row.MUMIMOTransmitArchitecture = localFirstTextTable(tr, ...
            ["MUMIMOTransmitArchitecture"], "");
        row.MUMIMOSpatialFilterMatrixSHA256 = localFirstTextTable(tr, ...
            ["MUMIMOSpatialFilterMatrixSHA256","MUMIMOReceiveCombiningMatrixSHA256"], "");
        row.MUMIMOAdmissionReceiveCombiningMatrixSHA256 = localFirstTextTable(tr, ...
            ["MUMIMOAdmissionReceiveCombiningMatrixSHA256"], "");
        row.MUMIMOReceiveProcessingMode = localFirstTextTable(tr, ...
            ["MUMIMOReceiveProcessingMode"], "");
        row.AppliedPrecoderMatrixSHA256 = localFirstTextTable(tr, ...
            ["AppliedPrecoderMatrixSHA256"], "");
        row.MUMIMOReceiveCombinerApplied = localBool(tr, ...
            "MUMIMOReceiveCombinerApplied", false);
        row.MUMIMOReceiveCombinerStatus = localFirstTextTable(tr, ...
            ["MUMIMOReceiveCombinerStatus"], "");
        row.MUMIMOReceiveCombinerMatrixSHA256 = localFirstTextTable(tr, ...
            ["MUMIMOReceiveCombinerMatrixSHA256"], "");
        row.MUMIMOReceiveCombinerInputBranches = localFirstNum(tr, ...
            ["MUMIMOReceiveCombinerInputBranches"], NaN);
        row.MUMIMOReceiveCombinerOutputBranches = localFirstNum(tr, ...
            ["MUMIMOReceiveCombinerOutputBranches"], NaN);
        row.MUMIMOReceiveCombinerInterferenceProjected = localBool(tr, ...
            "MUMIMOReceiveCombinerInterferenceProjected", false);
        row.MUMIMOReceiveCombinerFullObservationPreserved = localBool(tr, ...
            "MUMIMOReceiveCombinerFullObservationPreserved", false);
        row.MUMIMOReceiveCombinerIdentityResidual = localFirstNum(tr, ...
            ["MUMIMOReceiveCombinerIdentityResidual"], NaN);
        row.MUMIMOReceiverAlgorithm = localFirstTextTable(tr, ...
            ["MUMIMOReceiverAlgorithmApplied","MUMIMOReceiverAlgorithm", ...
             "EqualizerType","EqualizerRequestedType","EqualizerEngine", ...
             "EqualizerAlgorithm","EqualizerAlgorithmUsed","MUMIMOReceiverAlgorithm"], "");
        row.InterferenceCovarianceSource = localFirstTextTable(tr, ...
            ["InterferenceCovarianceSource","EqualizerCovarianceSource"], "");
        row.InterferenceCovarianceAvailable = localBool(tr, ...
            "InterferenceCovarianceAvailable", false);
        row.InterferenceMode = localFirstTextTable(tr, ["InterferenceMode"], "");
        row.InterferenceContributorCount = localFirstNum(tr, ["InterferenceContributorCount"], 0);
        row.PRBStart = localFirstNum(tr, ["PRBStart"], NaN);
        row.PRBCount = localFirstNum(tr, ["PRBCount","AllocatedPRBCount"], NaN);
        row.SymbolStart = localFirstNum(tr, ["SymbolStart"], NaN);
        row.NumSymbols = localFirstNum(tr, ["NumSymbols"], NaN);
        row.DecodeCrcPass = crcPass;
        row.AdaptationEvidenceId = localFirstTextTable(tr, ["CSIReportId","CSIPayloadHex","GrantContextId"], "");
        row.ExactSpatialMatch = localExactSpatialMatch(row);
        row.SpatialContractMatch = row.ExactSpatialMatch;
        row.ExactOperatingPointMatch = localExactOperatingPointMatch(row);
        row.FixedOperatingPointMatch = row.ExactOperatingPointMatch;
        row.AdaptivePolicyRequired = row.AdaptiveMode;
        [row.AdaptivePolicyMatch, row.AdaptivePolicyFailureReason] = localAdaptivePolicyMatch(row);
        row.AdaptivePolicyConformance = row.AdaptivePolicyMatch;
        row.OperatingPointContractMatch = (~row.AdaptiveMode && row.ExactOperatingPointMatch) || ...
            (row.AdaptiveMode && row.AdaptivePolicyMatch);
        row.MUExecutionMatch = localMURowExecutionMatch(row);
        row.ExactConfiguredMatch = row.ExactSpatialMatch && row.ExactOperatingPointMatch;
        row.ExecutionContractMatch = row.ExactSpatialMatch && row.OperatingPointContractMatch;
        row.MismatchCause = localMismatchCause(row);
        row.StrictEligible = ~localBool(tr, "IsWarmupFrame", false);
        row.SourceArtifactRef = sourceArtifact;
        row.SourceRowsHash = sourceHash;
        % This table proves what spatial/operating-point contract actually
        % reached the waveform.  CRC success is a separate reliability
        % observation: a deliberately low-SNR block error must not be
        % relabelled as rank/layer or MCS configuration drift.
        receiverLayerEvidenceOk = row.TransmittedLayers <= 1 || ...
            numel(perLayer) >= row.TransmittedLayers;
        row.ExecutionContractOk = row.StrictEligible && ...
            row.ExecutionContractMatch && row.MUExecutionMatch && ...
            receiverLayerEvidenceOk;
        row.DecodeReliabilityOk = row.StrictEligible && row.DecodeCrcPass;
        row.DecodeReliabilityStatus = string(localTernary(~row.StrictEligible, ...
            "not_evaluated", localTernary(row.DecodeCrcPass, "crc_pass", "crc_fail")));
        row.StrictOk = row.ExecutionContractOk;
        if ~row.StrictEligible
            row.Status = "not_evaluated";
            row.FailureReason = "warmup_row_excluded_from_strict_mimo_evidence";
        elseif row.ExecutionContractOk
            row.Status = "pass";
            row.FailureReason = "";
        elseif ~receiverLayerEvidenceOk
            row.Status = "fail";
            row.FailureReason = "receiver_per_layer_evidence_missing_for_multilayer_trial";
        elseif row.MUExecutionRequired && ~row.MUExecutionMatch
            row.Status = "fail";
            row.FailureReason = "mu_execution_contract_failed";
        elseif row.FixedAnchorMode
            row.Status = "fail";
            row.FailureReason = "fixed_anchor_execution_contract_mismatch:" + ...
                string(localNonemptyReason(row.MismatchCause));
        else
            row.Status = "fail";
            row.FailureReason = "adaptive_execution_contract_mismatch:" + ...
                string(localNonemptyReason(row.MismatchCause));
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
    row.ConfiguredInitialMCS = double(cfgT.ConfiguredInitialMCS(i));
    row.ConfiguredMaximumMCS = double(cfgT.ConfiguredMaximumMCS(i));
    row.AdaptiveMode = logical(cfgT.AdaptiveMode(i));
    % Rank/layer equality is mandatory only when YAML fixes the spatial
    % contract.  A measured-RI policy is allowed to select a lower rank,
    % but the configured and effective values remain separately exported.
    row.SpatialContractRequired = logical(cfgT.FixedAnchorMode(i));
    row.FixedOperatingPointRequired = ~row.AdaptiveMode;
    row.AdaptivePolicyRequired = row.AdaptiveMode;
    row.MUExecutionRequired = logical(cfgT.ConfiguredMUMIMOEnabled(i));
    row.RequiredMUUserCount = double(cfgT.ConfiguredMUUsersPerPRB(i));
    row.RequiredMULeakageThreshold_dB = double(cfgT.ConfiguredMUMIMOLeakageThreshold_dB(i));
    row.RequiredMUExecutionMode = string(cfgT.ConfiguredMUMIMOExecutionMode(i));
    row.StrictEligibleRowCount = height(subset);
    if height(subset) > 0
        % A failed transport block has EffectiveDecodedRank=0 by design.
        % Do not let a majority of deliberately low-SNR CRC failures turn
        % the aggregate *decoded-rank* observation into rank zero when
        % successful receiver rows provide direct per-layer evidence.  The
        % reliability failure remains in DecodeCrcPass/BLER; this summary
        % reports the spatial rank that the receiver actually decoded.
        decodedSubset = subset(logical(subset.DecodeCrcPass) & ...
            double(subset.EffectiveDecodedRank) > 0 & ...
            double(subset.EffectiveDecodedLayers) > 0, :);
        row.DominantScheduledRank = localMode(subset.ScheduledRank);
        row.DominantTransmittedRank = localMode(subset.TransmittedRank);
        row.DominantScheduledLayers = localMode(subset.ScheduledLayers);
        row.DominantTransmittedLayers = localMode(subset.TransmittedLayers);
        if height(decodedSubset) > 0
            row.DominantEffectiveDecodedRank = ...
                localMode(decodedSubset.EffectiveDecodedRank);
            row.DominantEffectiveDecodedLayers = ...
                localMode(decodedSubset.EffectiveDecodedLayers);
        else
            row.DominantEffectiveDecodedRank = 0;
            row.DominantEffectiveDecodedLayers = 0;
        end
        row.DominantEffectiveModulation = localStringMode(subset.EffectiveDecodedModulation);
        row.DominantEffectiveMCS = localMode(subset.EffectiveDecodedMCS);
        row.ExactMatchRowCount = sum(logical(subset.ExactConfiguredMatch));
        row.ExactMatchPercent = row.ExactMatchRowCount / max(row.StrictEligibleRowCount, 1);
        row.ExactSpatialMatchRowCount = sum(logical(subset.ExactSpatialMatch));
        row.ExactSpatialMatchPercent = row.ExactSpatialMatchRowCount / max(row.StrictEligibleRowCount, 1);
        row.ExactOperatingPointMatchRowCount = sum(logical(subset.ExactOperatingPointMatch));
        row.ExactOperatingPointMatchPercent = row.ExactOperatingPointMatchRowCount / max(row.StrictEligibleRowCount, 1);
        row.AdaptivePolicyMatchRowCount = sum(logical(subset.AdaptivePolicyMatch));
        row.AdaptivePolicyMatchPercent = row.AdaptivePolicyMatchRowCount / max(row.StrictEligibleRowCount, 1);
        row.AdaptiveFeedbackDecisionRowCount = sum(logical(subset.AdaptiveFeedbackDecisionObserved));
        row.ExecutionContractMatchRowCount = sum(logical(subset.ExecutionContractMatch));
        row.ExecutionContractMatchPercent = row.ExecutionContractMatchRowCount / max(row.StrictEligibleRowCount, 1);
        row.SpatialContractMatch = all(logical(subset.SpatialContractMatch));
        row.FixedOperatingPointMatch = all(logical(subset.FixedOperatingPointMatch));
        row.AdaptivePolicyConformance = all(logical(subset.AdaptivePolicyConformance)) && ...
            (~row.AdaptivePolicyRequired || row.AdaptiveFeedbackDecisionRowCount > 0);
        [row.MUExecutionMatch, row.MUExecutedTrialRowCount, ...
            row.MUExecutedDistinctGroupCount, row.MUExecutionFailureReason] = ...
            localMUSummaryExecutionMatch(subset, row);
        row.RuntimePopulated = true;
        row.RuntimeTrialCount = height(subset);
        row.RuntimeRank2Fraction = mean(double(subset.TransmittedRank) == 2 | double(subset.EffectiveDecodedRank) == 2, "omitnan");
        row.RuntimeExactMatchFraction = row.ExactMatchPercent;
        row.RuntimeMeanConditionNumber_dB = mean(double(subset.ConditionNumber_dB), "omitnan");
        row.RuntimeMeanRateRank1_bpsHz = mean(double(subset.RateRank1_bpsHz), "omitnan");
        row.RuntimeMeanRateRank2_bpsHz = mean(double(subset.RateRank2_bpsHz), "omitnan");
        row.RuntimeEvidenceSource = "rank_layer_trials_from_air_interface_raw_trials";
        row.EvidenceClass = "DIRECT_RUNTIME_EVIDENCE";
    end
    row.RequiredExactMatchPercent = localTernary(~row.AdaptiveMode && ...
        (logical(cfgT.FixedAnchorMode(i)) || strictMode), 0.999, NaN);
    row.RequiredExecutionContractMatchPercent = localTernary( ...
        row.SpatialContractRequired, 0.999, NaN);
    row.ScenarioObjectivePass = row.StrictEligibleRowCount > 0 && ...
        (~isfinite(row.RequiredExactMatchPercent) || row.ExactMatchPercent + eps >= row.RequiredExactMatchPercent) && ...
        (~isfinite(row.RequiredExecutionContractMatchPercent) || ...
        row.ExecutionContractMatchPercent + eps >= row.RequiredExecutionContractMatchPercent) && ...
        (~row.SpatialContractRequired || row.SpatialContractMatch) && ...
        (~row.FixedOperatingPointRequired || row.FixedOperatingPointMatch) && ...
        (~row.AdaptivePolicyRequired || row.AdaptivePolicyConformance) && ...
        row.MUExecutionMatch;
    row.Status = string(localTernary(row.ScenarioObjectivePass, "pass", "fail"));
    if row.ScenarioObjectivePass
        row.FailureReason = "";
    elseif row.MUExecutionRequired && ~row.MUExecutionMatch
        row.FailureReason = "mu_execution_contract_failed:" + string(row.MUExecutionFailureReason);
    elseif row.AdaptivePolicyRequired && row.AdaptiveFeedbackDecisionRowCount == 0
        row.FailureReason = "adaptive_policy_only_bootstrap_rows_no_runtime_feedback_decision";
    else
        row.FailureReason = "mimo_configured_effective_mismatch_or_missing_rows";
    end
    rows(end+1, 1) = row; %#ok<AGROW>
end
T = struct2table(rows);
end

function cfgT = localAttachRuntimeEvidenceSummary(cfgT, rankT)
n = height(cfgT);
cfgT.RuntimePopulated = false(n, 1);
cfgT.RuntimeTrialCount = zeros(n, 1);
cfgT.RuntimeRank2Fraction = NaN(n, 1);
cfgT.RuntimeExactMatchFraction = NaN(n, 1);
cfgT.RuntimeMeanConditionNumber_dB = NaN(n, 1);
cfgT.RuntimeMeanRateRank1_bpsHz = NaN(n, 1);
cfgT.RuntimeMeanRateRank2_bpsHz = NaN(n, 1);
cfgT.RuntimeEvidenceSource = repmat("no_runtime_trials", n, 1);
cfgT.EvidenceClass = repmat("CONFIGURATION_WITH_RUNTIME_LINKAGE_PENDING", n, 1);
for i = 1:n
    direction = string(cfgT.Direction(i));
    subset = rankT(strcmp(string(rankT.Direction), direction) & logical(rankT.StrictEligible), :);
    if height(subset) == 0
        continue;
    end
    cfgT.RuntimePopulated(i) = true;
    cfgT.RuntimeTrialCount(i) = height(subset);
    cfgT.RuntimeRank2Fraction(i) = mean(double(subset.TransmittedRank) == 2 | double(subset.EffectiveDecodedRank) == 2, "omitnan");
    cfgT.RuntimeExactMatchFraction(i) = mean(logical(subset.ExactConfiguredMatch), "omitnan");
    cfgT.RuntimeMeanConditionNumber_dB(i) = mean(double(subset.ConditionNumber_dB), "omitnan");
    cfgT.RuntimeMeanRateRank1_bpsHz(i) = mean(double(subset.RateRank1_bpsHz), "omitnan");
    cfgT.RuntimeMeanRateRank2_bpsHz(i) = mean(double(subset.RateRank2_bpsHz), "omitnan");
    cfgT.RuntimeEvidenceSource(i) = "rank_layer_trials_from_air_interface_raw_trials";
    cfgT.EvidenceClass(i) = "CONFIGURATION_WITH_DIRECT_RUNTIME_TRIAL_EVIDENCE";
end
end

function cfgT = localAttachRuntimeValidationStatus(cfgT, configuredEffective, configAudit)
cfgT.RuntimeValidationFailureReason = repmat("", height(cfgT), 1);
for i = 1:height(cfgT)
    if ~logical(cfgT.RuntimePopulated(i))
        cfgT.Status(i) = "not_validated";
        cfgT.RuntimeValidationFailureReason(i) = "no_strict_eligible_runtime_trials";
        continue;
    end
    direction = upper(strtrim(string(cfgT.Direction(i))));
    summaryMask = upper(strtrim(string(configuredEffective.Direction))) == direction;
    auditMask = upper(strtrim(string(configAudit.Direction))) == direction;
    summaryOk = any(summaryMask) && ...
        all(logical(configuredEffective.ScenarioObjectivePass(summaryMask)));
    auditOk = any(auditMask) && all(logical(configAudit.Pass(auditMask)));
    if summaryOk && auditOk
        cfgT.Status(i) = "pass";
    elseif ~auditOk
        cfgT.Status(i) = "fail";
        cfgT.RuntimeValidationFailureReason(i) = "mimo_configuration_validation_failed";
    else
        cfgT.Status(i) = "fail";
        cfgT.RuntimeValidationFailureReason(i) = ...
            "runtime_mimo_execution_policy_or_objective_failed";
    end
end
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

function T = localAntennaArrayConfig(cfgT, rankT)
rows = repmat(struct("RunId","", "ScenarioName","", "Direction","", "ArrayGeometryId","", ...
    "PhysicalTxAntennaCount",NaN, "PhysicalRxAntennaCount",NaN, "TxRFChainCount",NaN, ...
    "RxRFChainCount",NaN, "TxAntennaPortCount",NaN, "RxAntennaPortCount",NaN, ...
    "ObservedTxPortCount",NaN, "ObservedRxAntennaCount",NaN, "RuntimePopulated",false, ...
    "FullElementDomainRequired",false, "ExpectedRuntimeTxCount",NaN, ...
    "ExpectedRuntimeRxCount",NaN, "ExactRuntimeAntennaMatch",false, ...
    "ObservedPhysicalTxAntennaCount",NaN, ...
    "ObservedPhysicalRxAntennaCount",NaN, ...
    "ObservedLogicalTxPortCount",NaN, ...
    "ObservedLogicalRxBranchCount",NaN, ...
    "LogicalPortLayerMatch",false, "RuntimeAntennaObjectCreated",false, ...
    "ChannelUsesSameRuntimeAntennaAssumptions",false, ...
    "NominalCapabilityOnly",true, "EvidenceClass","CONFIGURATION_ONLY", ...
    "RuntimeEvidenceSource","", "SourceHash","", "Status","pass", "FailureReason",""), height(cfgT), 1);
for i = 1:height(cfgT)
    sub = rankT(strcmp(string(rankT.Direction), string(cfgT.Direction(i))), :);
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
    rows(i).FullElementDomainRequired = logical(cfgT.FullElementDomainRequired(i));
    rows(i).ObservedTxPortCount = localMode(localColumn(sub, "NumTxPorts"));
    rows(i).ObservedRxAntennaCount = localMode(localColumn(sub, "NumRxAntennas"));
    if ~isfinite(rows(i).ObservedTxPortCount)
        rows(i).ObservedTxPortCount = localMode(localColumn(sub, "TransmittedLayers"));
    end
    if ~isfinite(rows(i).ObservedRxAntennaCount)
        rows(i).ObservedRxAntennaCount = localMode(localColumn(sub, "EffectiveDecodedLayers"));
    end
    rows(i).ObservedLogicalTxPortCount = localMode( ...
        localColumn(sub,"LogicalTxPortCount"));
    rows(i).ObservedLogicalRxBranchCount = localMode( ...
        localColumn(sub,"LogicalRxBranchCount"));
    if ~isfinite(rows(i).ObservedLogicalTxPortCount)
        rows(i).ObservedLogicalTxPortCount = localMode( ...
            localColumn(sub,"TransmittedLayers"));
    end
    if ~isfinite(rows(i).ObservedLogicalRxBranchCount)
        rows(i).ObservedLogicalRxBranchCount = localMode( ...
            localColumn(sub,"EffectiveDecodedLayers"));
    end
    if upper(string(cfgT.Direction(i))) == "UL"
        rows(i).ObservedPhysicalTxAntennaCount = localMode( ...
            localFirstAvailableColumn(sub, ...
            ["TxWaveformColumns","PhysicalTxAntennas","UEAntennaElements","UEAntennaNumPorts"]));
        rows(i).ObservedPhysicalRxAntennaCount = localMode( ...
            localFirstAvailableColumn(sub, ...
            ["RxWaveformBranches","PhysicalRxAntennas","BSAntennaElements","BSAntennaNumPorts"]));
    else
        rows(i).ObservedPhysicalTxAntennaCount = localMode( ...
            localFirstAvailableColumn(sub, ...
            ["TxWaveformColumns","PhysicalTxAntennas","BSAntennaElements","BSAntennaNumPorts"]));
        rows(i).ObservedPhysicalRxAntennaCount = localMode( ...
            localFirstAvailableColumn(sub, ...
            ["RxWaveformBranches","PhysicalRxAntennas","NumRxAntennas","UEAntennaElements","UEAntennaNumPorts"]));
    end
    rows(i).RuntimePopulated = height(sub) > 0;
    if rows(i).RuntimePopulated
        rows(i).NominalCapabilityOnly = false;
        rows(i).EvidenceClass = "CONFIGURATION_WITH_DIRECT_RUNTIME_TRIAL_EVIDENCE";
        rows(i).RuntimeEvidenceSource = "rank_layer_trials_from_air_interface_raw_trials";
    end
    if rows(i).FullElementDomainRequired
        rows(i).ExpectedRuntimeTxCount = rows(i).PhysicalTxAntennaCount;
        rows(i).ExpectedRuntimeRxCount = rows(i).PhysicalRxAntennaCount;
    else
        rows(i).ExpectedRuntimeTxCount = rows(i).TxAntennaPortCount;
        rows(i).ExpectedRuntimeRxCount = rows(i).RxAntennaPortCount;
    end
    rows(i).ChannelUsesSameRuntimeAntennaAssumptions = rows(i).RuntimePopulated && ...
        all(localColumnLogical(sub,"ChannelUsesSameRuntimeAntennaAssumptions",false));
    rows(i).RuntimeAntennaObjectCreated = rows(i).RuntimePopulated && ...
        all(localColumnLogical(sub,"AntennaRuntimeObjectCreated",false));
    configuredLayers = double(cfgT.ConfiguredLayers(i));
    rows(i).LogicalPortLayerMatch = rows(i).RuntimePopulated && ...
        rows(i).ObservedLogicalTxPortCount == configuredLayers && ...
        rows(i).ObservedLogicalRxBranchCount >= configuredLayers;
    if rows(i).FullElementDomainRequired
        rows(i).ExactRuntimeAntennaMatch = rows(i).RuntimePopulated && ...
            rows(i).ObservedPhysicalTxAntennaCount == rows(i).ExpectedRuntimeTxCount && ...
            rows(i).ObservedPhysicalRxAntennaCount == rows(i).ExpectedRuntimeRxCount && ...
            rows(i).LogicalPortLayerMatch && ...
            rows(i).RuntimeAntennaObjectCreated && ...
            rows(i).ChannelUsesSameRuntimeAntennaAssumptions;
    else
        rows(i).ExactRuntimeAntennaMatch = rows(i).LogicalPortLayerMatch;
    end
    rows(i).Status = string(localTernary(rows(i).ExactRuntimeAntennaMatch, ...
        "pass","fail"));
    rows(i).FailureReason = string(localTernary(rows(i).ExactRuntimeAntennaMatch, ...
        "","runtime_antenna_domain_does_not_match_configured_execution_contract"));
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
    "PMI","", "AppliedPrecoderMatrixSHA256","", "EvidenceType","", ...
    "PrecoderSource","", "PrecodingActive",false, "SourceRowsHash","", ...
    "Status","", "FailureReason",""), height(rankT), 1);
for i = 1:height(rankT)
    rows(i).RunId = string(rankT.RunId(i));
    rows(i).TrialId = double(rankT.TrialId(i));
    rows(i).Direction = string(rankT.Direction(i));
    pmi = strtrim(string(rankT.PrecoderId(i)));
    matrixHash = lower(strtrim(string(rankT.AppliedPrecoderMatrixSHA256(i))));
    pmiAvailable = localUsableText(pmi);
    matrixAvailable = ~ismissing(matrixHash) && ...
        ~isempty(regexp(char(matrixHash), '^[0-9a-f]{64}$', 'once')); %#ok<RGXP1>
    rows(i).PMI = string(localTernary(pmiAvailable, pmi, ""));
    rows(i).AppliedPrecoderMatrixSHA256 = ...
        string(localTernary(matrixAvailable, matrixHash, ""));
    if matrixAvailable
        rows(i).PrecoderId = "matrix_sha256:" + matrixHash;
        rows(i).EvidenceType = string(localTernary(pmiAvailable, ...
            "pmi_and_applied_matrix", "applied_matrix"));
        rows(i).PrecoderSource = ...
            "air_interface_trial_applied_precoder_matrix_sha256";
    elseif pmiAvailable
        rows(i).PrecoderId = "pmi:" + pmi;
        rows(i).EvidenceType = "pmi";
        rows(i).PrecoderSource = "air_interface_trial_applied_pmi";
    else
        rows(i).PrecoderId = "";
        rows(i).EvidenceType = "missing";
        rows(i).PrecoderSource = "air_interface_trial_precoder_fields";
    end
    rows(i).PrecodingActive = pmiAvailable || matrixAvailable;
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
    usable = arrayfun(@localUsableText, beamIds);
    beamIds = beamIds(usable);
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
    selectedBeam = string(rankT.BeamId(i));
    selectedBeamAvailable = localUsableText(selectedBeam);
    if ~selectedBeamAvailable
        selectedBeam = "not_selected";
    end
    rows(i).SelectedBeamId = selectedBeam;
    rows(i).CSIReportId = string(rankT.CSIReportId(i));
    rows(i).MeasurementSource = string(localTernary(strlength(strtrim(rows(i).CSIReportId)) > 0, "csi_or_grant_runtime_evidence", "air_interface_trial_row"));
    rows(i).SourceRowsHash = string(rankT.SourceRowsHash(i));
    ok = selectedBeamAvailable || double(rankT.ConfiguredLayers(i)) <= 1;
    rows(i).Status = string(localTernary(ok, "pass", "fail"));
    rows(i).FailureReason = string(localTernary(ok, "", "beam_selection_evidence_missing_for_mimo_row"));
end
T = struct2table(rows);
end

function T = localNegativeTrials()
% This evidence builder does not execute injected-fault waveform trials.
% Observed configuration/runtime mismatches remain failed objectives in
% ConfiguredVsEffective and StrictGateSummary, not passed negative tests.
rows = repmat(struct("RunId","", "NegativeTrialType","", "InjectedFault","", ...
    "ExpectedFailureStage","", "ObservedFailureStage","", "ExactConfiguredMatch",false, ...
    "DecodeCrcPass",false, "StrictOk",false, "NegativeExpectedOk",false, "FailureReason",""), 0, 1);
T = struct2table(rows);
end

function T = localOracleGuard(rankT, runId)
violation = false(height(rankT), 1);
for i = 1:height(rankT)
    violation(i) = isfinite(double(rankT.EffectiveDecodedRank(i))) && ...
        double(rankT.EffectiveDecodedRank(i)) == double(rankT.ConfiguredRank(i)) && ...
        strlength(strtrim(string(rankT.LayerSINRdB(i)))) == 0 && logical(rankT.DecodeCrcPass(i));
end
rows = repmat(struct("RunId","", "Direction","", "TrialId",NaN, ...
    "CellId",NaN, "UEId",NaN, "Stage","effective_rank_derivation", ...
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
        rows(i).Direction = string(rankT.Direction(i));
        rows(i).TrialId = double(rankT.TrialId(i));
        rows(i).CellId = double(rankT.CellId(i));
        rows(i).UEId = double(rankT.UEId(i));
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

function out = localFirstAvailableColumn(T, names)
out = [];
for name = string(names)
    candidate = localColumn(T, name);
    if ~isempty(candidate) && any(isfinite(candidate))
        out = candidate;
        return;
    end
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

function tf = localExactSpatialMatch(row)
% Configured-vs-effective MIMO execution is a transmitted waveform
% contract. A CRC failure at a deliberately low-SNR sweep point does not
% turn a physically transmitted rank-two allocation into rank zero. Keep
% decode success and effective decoded rank as separate reliability
% evidence while comparing configuration to the waveform that actually ran.
tf = isfinite(row.TransmittedRank) && isfinite(row.TransmittedLayers) && ...
    row.TransmittedRank == row.ConfiguredRank && ...
    row.TransmittedLayers == row.ConfiguredLayers;
end

function tf = localExactOperatingPointMatch(row)
configuredModulation = upper(strtrim(string(row.ConfiguredModulation)));
transmittedModulation = upper(strtrim(string(row.TransmittedModulation)));
tf = (strlength(configuredModulation) == 0 || transmittedModulation == configuredModulation) && ...
    (~isfinite(row.ConfiguredMCS) || ...
    (isfinite(row.TransmittedMCS) && row.TransmittedMCS == row.ConfiguredMCS));
end

function tf = localMURowExecutionMatch(row)
% This is physical execution evidence, not a scheduler-intent test. A row
% passes only when a causally measured MU pair was transmitted on the same
% opportunity and the receiver saw the peer waveform contribution.
if ~logical(row.MUExecutionRequired)
    tf = true;
    return;
end
requiredUsers = max(2, round(double(row.RequiredMUUserCount)));
requiredMode = lower(strtrim(string(row.RequiredMUExecutionMode)));
tf = logical(row.MUMIMOEnabled) && ...
    isfinite(row.MUMIMOGroupSize) && row.MUMIMOGroupSize >= requiredUsers && ...
    isfinite(row.MUMIMOGroupId) && ...
    lower(strtrim(string(row.MUMIMOPairingStatus))) == "paired_shared_prb_spatial_multiplexing" && ...
    localVerifiedMUSpatialExecution(row) && ...
    isfinite(row.MUMIMOPairingMetricValue_dB) && ...
    isfinite(row.RequiredMULeakageThreshold_dB) && ...
    row.MUMIMOPairingMetricValue_dB <= row.RequiredMULeakageThreshold_dB && ...
    lower(strtrim(string(row.InterferenceMode))) == "shared_slot_waveform_superposition" && ...
    row.InterferenceContributorCount >= requiredUsers - 1;
if strlength(requiredMode) > 0 && requiredMode ~= "none"
    tf = tf && lower(strtrim(string(row.InterferenceMode))) == requiredMode;
end
end

function tf = localVerifiedMUSpatialExecution(row)
direction = upper(strtrim(string(row.Direction)));
metricSource = lower(strtrim(string(row.MUMIMOPairingMetricSource)));
evidenceSource = lower(strtrim(string(row.MUMIMOPairingEvidenceSource)));
designEvidenceSource = lower(strtrim(string(row.MUMIMOSpatialDesignEvidenceSource)));
contractVersion = strtrim(string(row.MUMIMOSpatialDesignContractVersion));
subspaceMode = lower(strtrim(string(row.MUMIMOSpatialSignatureSubspaceMode)));
if contractVersion ~= "MeasuredMUMIMOPairDesign/v13" || ...
        ~ismember(subspaceMode, ["complete_detectable_subspace", ...
        "dominant_scheduled_rank"]) || ...
        evidenceSource ~= designEvidenceSource
    tf = false;
    return;
end
if subspaceMode == "complete_detectable_subspace"
    subspaceLabel = "complete_peer_subspace";
else
    subspaceLabel = "scheduled_rank_peer_subspace";
end
matrixDigestPresent = strlength(strtrim(string(row.MUMIMOSpatialFilterMatrixSHA256))) == 64;
if direction == "DL"
    appliedDigest = lower(strtrim(string(row.AppliedPrecoderMatrixSHA256)));
    architecture = lower(strtrim(string(row.MUMIMOTransmitArchitecture)));
    if architecture == "hybrid_rf_baseband"
        architectureMetric = "hybrid_block_diagonalized_precoder_leakage";
        tddEvidence = "causal_measured_srs_" + subspaceLabel + ...
            "_reciprocity_phase_only_hybrid_and_frozen_baseband";
        fddEvidence = "causal_measured_csirs_direct_transmit_" + subspaceLabel + ...
            "_phase_only_hybrid_and_frozen_baseband";
    elseif architecture == "fully_digital_element_control"
        architectureMetric = "fully_digital_block_diagonalized_precoder_leakage";
        tddEvidence = "causal_measured_srs_" + subspaceLabel + ...
            "_reciprocity_fully_digital_and_frozen_baseband";
        fddEvidence = "causal_measured_csirs_direct_transmit_" + subspaceLabel + ...
            "_fully_digital_and_frozen_baseband";
    else
        tf = false;
        return;
    end
    tddAuthority = metricSource == "measured_tdd_srs_reciprocal_" + ...
        subspaceLabel + "_" + architectureMetric && evidenceSource == tddEvidence;
    fddAuthority = metricSource == "measured_fdd_csirs_direct_transmit_" + ...
        subspaceLabel + "_" + architectureMetric && evidenceSource == fddEvidence;
    tf = (tddAuthority || fddAuthority) && ...
        matrixDigestPresent && strlength(appliedDigest) == 64 && ...
        appliedDigest == lower(strtrim(string(row.MUMIMOSpatialFilterMatrixSHA256))) && ...
        logical(row.InterferenceCovarianceAvailable) && ...
        lower(strtrim(string(row.InterferenceCovarianceSource))) == ...
            "oracle_separated_shared_slot_per_prb_symbol_contribution_grid_covariance";
elseif direction == "UL"
    receiver = lower(strtrim(string(row.MUMIMOReceiverAlgorithm)));
    covarianceSource = lower(strtrim(string(row.InterferenceCovarianceSource)));
    appliedDigest = lower(strtrim(string(row.MUMIMOReceiveCombinerMatrixSHA256)));
    admissionDigest = lower(strtrim(string(row.MUMIMOAdmissionReceiveCombiningMatrixSHA256)));
    tf = metricSource == "measured_srs_" + subspaceLabel + ...
        "_admission_projection_leakage_full_dimensional_per_re_irc" && ...
        evidenceSource == "causal_measured_srs_" + subspaceLabel + ...
        "_pairing_with_full_receiver_observation_and_runtime_per_re_irc_covariance" && ...
        lower(strtrim(string(row.MUMIMOReceiveProcessingMode))) == ...
            "full_dimensional_per_re_irc" && ...
        matrixDigestPresent && logical(row.MUMIMOReceiveCombinerApplied) && ...
        lower(strtrim(string(row.MUMIMOReceiveCombinerStatus))) == ...
            "applied_full_dimensional_identity_preprocessor_for_per_re_irc" && ...
        strlength(appliedDigest) == 64 && strlength(admissionDigest) == 64 && ...
        appliedDigest == lower(strtrim(string(row.MUMIMOSpatialFilterMatrixSHA256))) && ...
        logical(row.MUMIMOReceiveCombinerInterferenceProjected) && ...
        logical(row.MUMIMOReceiveCombinerFullObservationPreserved) && ...
        isfinite(row.MUMIMOReceiveCombinerIdentityResidual) && ...
        row.MUMIMOReceiveCombinerIdentityResidual <= 1e-12 && ...
        isfinite(row.MUMIMOReceiveCombinerInputBranches) && ...
        row.MUMIMOReceiveCombinerInputBranches == row.PhysicalRxAntennas && ...
        isfinite(row.MUMIMOReceiveCombinerOutputBranches) && ...
        row.MUMIMOReceiveCombinerOutputBranches == row.PhysicalRxAntennas && ...
        receiver == "full_dimensional_per_re_irc" && ...
        logical(row.InterferenceCovarianceAvailable) && ...
        covarianceSource == ...
            "oracle_separated_shared_slot_per_prb_symbol_contribution_grid_covariance";
else
    tf = false;
end
end

function [tf, executedRows, passedGroups, reason] = localMUSummaryExecutionMatch(subset, summaryRow)
executedRows = 0;
passedGroups = 0;
reason = "";
if ~logical(summaryRow.MUExecutionRequired)
    tf = true;
    reason = "not_applicable_mu_disabled";
    return;
end
requiredUsers = max(2, round(double(summaryRow.RequiredMUUserCount)));
if lower(strtrim(string(summaryRow.RequiredMUExecutionMode))) ~= "shared_slot_waveform_superposition"
    tf = false;
    reason = "configured_mu_execution_mode_is_not_shared_waveform_superposition";
    return;
end
candidate = logical(subset.MUMIMOEnabled) & ...
    isfinite(double(subset.MUMIMOGroupSize)) & double(subset.MUMIMOGroupSize) >= requiredUsers & ...
    isfinite(double(subset.MUMIMOGroupId));
if ~any(candidate)
    tf = false;
    reason = "no_shared_prb_mu_trial_rows";
    return;
end
candidateT = subset(candidate, :);
groupIds = unique(double(candidateT.MUMIMOGroupId));
invalidGroups = 0;
for gi = 1:numel(groupIds)
    groupT = candidateT(double(candidateT.MUMIMOGroupId) == groupIds(gi), :);
    uniqueUE = unique(double(groupT.UEId(isfinite(double(groupT.UEId)))));
    groupOk = height(groupT) >= requiredUsers && numel(uniqueUE) >= requiredUsers && ...
        all(logical(groupT.MUExecutionMatch)) && ...
        localAllSameFinite(groupT.PRBStart) && localAllSameFinite(groupT.PRBCount) && ...
        localAllSameFinite(groupT.SymbolStart) && localAllSameFinite(groupT.NumSymbols);
    if groupOk
        passedGroups = passedGroups + 1;
        executedRows = executedRows + height(groupT);
    else
        invalidGroups = invalidGroups + 1;
    end
end
tf = passedGroups > 0 && invalidGroups == 0;
if ~tf
    if passedGroups == 0
        reason = "no_complete_physical_mu_group";
    else
        reason = "one_or_more_labeled_mu_groups_failed_shared_resource_or_waveform_contract";
    end
end
end

function tf = localAllSameFinite(values)
values = double(values(:));
tf = ~isempty(values) && all(isfinite(values)) && all(values == values(1));
end

function [tf, reason] = localAdaptivePolicyMatch(row)
if ~row.AdaptiveMode
    tf = true;
    reason = "not_applicable_fixed_operating_point";
    return;
end

parts = strings(0,1);
policy = lower(strtrim(string(row.ConfiguredMCSSelectionPolicy)));
selectionMode = lower(strtrim(string(row.ActualMCSSelectionMode)));
selectionSource = lower(strtrim(string(row.MCSSelectionSource)));
mcsAuthority = lower(strtrim(string(row.MCSAuthority)));
modulationAuthority = lower(strtrim(string(row.ModulationAuthority)));
appliedSource = lower(strtrim(string(row.AppliedOperatingPointSource)));
lineage = [selectionMode; selectionSource; mcsAuthority; modulationAuthority; appliedSource];
forbidden = ["proxy","fallback","configured_fixed","legacy_mcs","missing","unavailable","error","rejected"];
if strlength(policy) == 0 || ismember(policy, ["fixed","configured_fixed","disabled","off","none"])
    parts(end+1,1) = "adaptive_policy_not_configured"; %#ok<AGROW>
end
if ~(row.LinkAdaptationScheduled && row.LinkAdaptationApplied)
    parts(end+1,1) = "adaptive_schedule_or_apply_evidence_missing"; %#ok<AGROW>
end
if ~(isfinite(row.ScheduledMCS) && isfinite(row.TransmittedMCS) && row.ScheduledMCS == row.TransmittedMCS)
    parts(end+1,1) = "scheduled_transmitted_mcs_mismatch"; %#ok<AGROW>
end
if ~isfinite(row.ConfiguredMaximumMCS)
    parts(end+1,1) = "adaptive_maximum_mcs_not_configured"; %#ok<AGROW>
elseif (isfinite(row.ScheduledMCS) && row.ScheduledMCS > row.ConfiguredMaximumMCS) || ...
        (isfinite(row.TransmittedMCS) && row.TransmittedMCS > row.ConfiguredMaximumMCS)
    parts(end+1,1) = "adaptive_maximum_mcs_exceeded"; %#ok<AGROW>
end
if ~isfinite(row.ConfiguredInitialMCS)
    parts(end+1,1) = "adaptive_initial_mcs_not_configured"; %#ok<AGROW>
end
if strlength(strtrim(string(row.ScheduledModulation))) == 0 || ...
        upper(strtrim(string(row.ScheduledModulation))) ~= upper(strtrim(string(row.TransmittedModulation)))
    parts(end+1,1) = "scheduled_transmitted_modulation_mismatch"; %#ok<AGROW>
end
if strlength(strtrim(string(row.AdaptationEvidenceId))) == 0 || all(strlength(lineage) == 0)
    parts(end+1,1) = "adaptive_decision_lineage_missing"; %#ok<AGROW>
end
lineageForbidden = false;
for i = 1:numel(forbidden)
    lineageForbidden = lineageForbidden || any(contains(lineage, forbidden(i)));
end
if lineageForbidden
    parts(end+1,1) = "adaptive_decision_lineage_not_truth_eligible"; %#ok<AGROW>
end
cqiPolicy = contains(policy, "cqi") || policy == "amc" || policy == "adaptive";
if cqiPolicy && ~(isfinite(row.WidebandCQI) && isfinite(row.CQIDerivedMCS) && ...
        any(contains(lineage, "cqi")))
    parts(end+1,1) = "cqi_policy_runtime_measurement_lineage_missing"; %#ok<AGROW>
end
effectiveSINRPolicy = contains(policy, "effective_sinr");
if effectiveSINRPolicy && ~any(contains(lineage, "effective_sinr"))
    parts(end+1,1) = "effective_sinr_policy_lineage_missing"; %#ok<AGROW>
end
parts = unique(parts, "stable");
tf = isempty(parts);
reason = strjoin(parts, "|");
end

function tf = localAdaptiveFeedbackDecisionObserved(row)
tf = false;
if ~logical(row.AdaptiveMode)
    return;
end
status = lower(strtrim(string(row.MCSValueStatus)));
invalid = strlength(status) == 0 || contains(status, "bootstrap") || ...
    contains(status, "pending_data_feedback") || contains(status, "missing") || ...
    contains(status, "unavailable") || contains(status, "rejected") || ...
    contains(status, "error");
tf = ~invalid && isfinite(row.WidebandCQI) && isfinite(row.CQIDerivedMCS) && ...
    logical(row.LinkAdaptationScheduled) && logical(row.LinkAdaptationApplied);
end

function reason = localMismatchCause(row)
parts = strings(0,1);
if ~(isfinite(row.TransmittedRank) && row.TransmittedRank == row.ConfiguredRank)
    parts(end+1,1) = "transmitted_rank_mismatch"; %#ok<AGROW>
end

if ~(isfinite(row.TransmittedLayers) && row.TransmittedLayers == row.ConfiguredLayers)
    parts(end+1,1) = "transmitted_layers_mismatch"; %#ok<AGROW>
end
if strlength(row.ConfiguredModulation) > 0 && ...
        upper(strtrim(string(row.TransmittedModulation))) ~= upper(strtrim(string(row.ConfiguredModulation)))
    parts(end+1,1) = "modulation_mismatch"; %#ok<AGROW>
end
if isfinite(row.ConfiguredMCS) && ...
        row.TransmittedMCS ~= row.ConfiguredMCS
    parts(end+1,1) = "mcs_mismatch"; %#ok<AGROW>
end
if row.AdaptiveMode && ~row.AdaptivePolicyMatch
    parts(end+1,1) = "adaptive_policy_mismatch:" + string(row.AdaptivePolicyFailureReason); %#ok<AGROW>
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
    "ReceiverEstimatedRank",NaN, ...
    "SpatialChannelRankEstimate",NaN, "SpatialChannelTxPorts",NaN, ...
    "SpatialChannelRxAntennas",NaN, "SpatialChannelRankDomain","", ...
    "SpatialChannelRankSource","", ...
    "EffectiveDecodedRank",NaN, "EffectiveDecodedLayers",NaN, ...
    "NumRxAntennas",NaN, "NumTxPorts",NaN, ...
    "TxWaveformColumns",NaN, "PhysicalTxAntennas",NaN, ...
    "RxWaveformBranches",NaN, "PhysicalRxAntennas",NaN, ...
    "LogicalTxPortCount",NaN, "LogicalRxBranchCount",NaN, ...
    "BSAntennaNumPorts",NaN, "UEAntennaNumPorts",NaN, ...
    "BSAntennaElements",NaN, "UEAntennaElements",NaN, ...
    "AntennaRuntimeObjectCreated",false, ...
    "ChannelUsesSameRuntimeAntennaAssumptions",false, "ConditionNumber_dB",NaN, ...
    "ConfiguredModulation","", "ScheduledModulation","", "TransmittedModulation","", ...
    "EffectiveDecodedModulation","", "ConfiguredMCS",NaN, ...
    "ConfiguredInitialMCS",NaN, "ConfiguredMaximumMCS",NaN, "ScheduledMCS",NaN, ...
    "TransmittedMCS",NaN, "EffectiveDecodedMCS",NaN, "DMRSPorts","", ...
    "ConfiguredMCSSelectionPolicy","", "ActualMCSSelectionMode","", ...
    "MCSSelectionSource","", "MCSAuthority","", "ModulationAuthority","", ...
    "AppliedOperatingPointSource","", "LinkAdaptationScheduled",false, ...
    "LinkAdaptationApplied",false, "WidebandCQI",NaN, "CQIDerivedMCS",NaN, ...
    "MCSValueStatus","", "AdaptiveFeedbackDecisionObserved",false, ...
    "PrecoderId","", "BeamId","", "CSIReportId","", "LayerSINRdB","", ...
    "RuntimeRI",NaN, "RuntimePMI",NaN, "RuntimeRankSelectionSource","", ...
    "EffectiveRankDecisionReason","", "RateRank1_bpsHz",NaN, "RateRank2_bpsHz",NaN, ...
    "DecodeCrcPass",false, "ExactSpatialMatch",false, "SpatialContractMatch",false, ...
    "ExactOperatingPointMatch",false, "FixedOperatingPointMatch",false, ...
    "AdaptivePolicyRequired",false, "AdaptivePolicyMatch",false, ...
    "AdaptivePolicyConformance",false, "AdaptivePolicyFailureReason","", ...
    "OperatingPointContractMatch",false, ...
    "MUExecutionRequired",false, "RequiredMUUserCount",NaN, ...
    "RequiredMULeakageThreshold_dB",NaN, "RequiredMUExecutionMode","", ...
    "MUMIMOEnabled",false, "MUMIMOGroupSize",NaN, "MUMIMOGroupId",NaN, ...
    "MUMIMOPairingStatus","", "MUMIMOPairingMetricSource","", ...
    "MUMIMOPairingMetricValue_dB",NaN, "MUMIMOPairingEvidenceSource","", ...
    "MUMIMOSpatialDesignContractVersion","", ...
    "MUMIMOSpatialSignatureSubspaceMode","", ...
    "MUMIMOSpatialDesignEvidenceSource","", "MUMIMOTransmitArchitecture","", ...
    "MUMIMOSpatialFilterMatrixSHA256","", ...
    "MUMIMOAdmissionReceiveCombiningMatrixSHA256","", ...
    "MUMIMOReceiveProcessingMode","", "AppliedPrecoderMatrixSHA256","", ...
    "MUMIMOReceiveCombinerApplied",false, "MUMIMOReceiveCombinerStatus","", ...
    "MUMIMOReceiveCombinerMatrixSHA256","", ...
    "MUMIMOReceiveCombinerInputBranches",NaN, ...
    "MUMIMOReceiveCombinerOutputBranches",NaN, ...
    "MUMIMOReceiveCombinerInterferenceProjected",false, ...
    "MUMIMOReceiveCombinerFullObservationPreserved",false, ...
    "MUMIMOReceiveCombinerIdentityResidual",NaN, ...
    "MUMIMOReceiverAlgorithm","", ...
    "InterferenceCovarianceSource","", "InterferenceCovarianceAvailable",false, ...
    "InterferenceMode","", "InterferenceContributorCount",0, ...
    "PRBStart",NaN, "PRBCount",NaN, "SymbolStart",NaN, "NumSymbols",NaN, ...
    "MUExecutionMatch",false, ...
    "ExactConfiguredMatch",false, "ExecutionContractMatch",false, "MismatchCause","", ...
    "AdaptiveMode",false, "AdaptationEvidenceId","", "FixedAnchorMode",false, ...
    "StrictEligible",false, "ExecutionContractOk",false, ...
    "DecodeReliabilityOk",false, "DecodeReliabilityStatus","not_evaluated", ...
    "StrictOk",false, "SourceArtifactRef","", "SourceRowsHash","", ...
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
    "ConfiguredInitialMCS",NaN, "ConfiguredMaximumMCS",NaN, ...
    "DominantEffectiveMCS",NaN, "AdaptiveMode",false, "StrictEligibleRowCount",0, ...
    "ExactMatchRowCount",0, "ExactMatchPercent",NaN, ...
    "ExactSpatialMatchRowCount",0, "ExactSpatialMatchPercent",NaN, ...
    "ExactOperatingPointMatchRowCount",0, "ExactOperatingPointMatchPercent",NaN, ...
    "AdaptivePolicyMatchRowCount",0, "AdaptivePolicyMatchPercent",NaN, ...
    "AdaptiveFeedbackDecisionRowCount",0, ...
    "ExecutionContractMatchRowCount",0, "ExecutionContractMatchPercent",NaN, ...
    "SpatialContractRequired",true, "SpatialContractMatch",false, ...
    "FixedOperatingPointRequired",false, "FixedOperatingPointMatch",false, ...
    "AdaptivePolicyRequired",false, "AdaptivePolicyConformance",false, ...
    "MUExecutionRequired",false, "RequiredMUUserCount",NaN, ...
    "RequiredMULeakageThreshold_dB",NaN, "RequiredMUExecutionMode","", ...
    "MUExecutedTrialRowCount",0, "MUExecutedDistinctGroupCount",0, ...
    "MUExecutionMatch",false, "MUExecutionFailureReason","", ...
    "RequiredExactMatchPercent",NaN, "RequiredExecutionContractMatchPercent",NaN, ...
    "ScenarioObjectivePass",false, ...
    "RuntimePopulated",false, "RuntimeTrialCount",0, "RuntimeRank2Fraction",NaN, ...
    "RuntimeExactMatchFraction",NaN, "RuntimeMeanConditionNumber_dB",NaN, ...
    "RuntimeMeanRateRank1_bpsHz",NaN, "RuntimeMeanRateRank2_bpsHz",NaN, ...
    "RuntimeEvidenceSource","", "EvidenceClass","CONFIGURATION_WITH_RUNTIME_LINKAGE_PENDING", ...
    "Status","not_evaluated", "FailureReason","");
end

function tf = localAllStatusPass(T)
tf = istable(T) && height(T) > 0 && ismember("Status", string(T.Properties.VariableNames)) && ...
    all(strcmp(string(T.Status), "pass"));
end

function tf = localUsableText(s)
s = lower(strtrim(string(s)));
tf = ~ismissing(s) && strlength(s) > 0 && ...
    ~ismember(s, ["nan","<missing>","missing","none","unavailable","not_available"]) && ...
    ~startsWith(s, ["not_recorded_by_active_","not_emitted_by_active_", ...
        "field_not_emitted_by_active_"]);
end

function Hwb = localWidebandRuntimeChannel(H)
Hwb = [];
if isempty(H)
    return;
end
H = double(H);
nd = ndims(H);
if ismatrix(H)
    Hwb = H;
elseif nd == 3
    Hwb = mean(H, 3, "omitnan");
elseif nd >= 4
    try
        Havg = mean(mean(H, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(H, 1), 2);
    end
    Hwb = squeeze(Havg);
end
if isempty(Hwb)
    return;
end
if isvector(Hwb)
    Hwb = reshape(Hwb(:), numel(Hwb), 1);
end
if ~ismatrix(Hwb)
    Hwb = [];
end
end

function reason = localNonemptyReason(reason)
reason = strtrim(string(reason));
if strlength(reason) == 0
    reason = "unspecified_execution_contract_mismatch";
end
end

function value = localFirstFiniteStruct(cfg, paths, defaultValue)
value = defaultValue;
for p = string(paths)
    raw = sixgr.util.structGet(cfg, p, []);
    if isempty(raw)
        continue;
    end
    if isnumeric(raw) || islogical(raw)
        vals = double(raw(:));
    else
        vals = str2double(string(raw(:)));
    end
    idx = find(isfinite(vals), 1);
    if ~isempty(idx)
        value = double(vals(idx));
        return;
    end
end
end

function value = localFirstTextStruct(cfg, paths, defaultValue)
value = string(defaultValue);
for p = string(paths)
    raw = sixgr.util.structGet(cfg, p, []);
    if isempty(raw)
        continue;
    end
    vals = strtrim(string(raw(:)));
    vals = vals(arrayfun(@localUsableText, vals));
    if ~isempty(vals)
        value = vals(1);
        return;
    end
end
end

function kappa = localConditionNumberForRank(sv, rankValue)
rankValue = max(1, min(round(double(rankValue)), numel(sv)));
if isempty(sv) || rankValue < 1
    kappa = NaN;
    return;
end
den = max(double(sv(rankValue)), realmin);
kappa = 20 * log10(max(double(sv(1)), realmin) / den);
end

function value = localVectorValueOrNaN(values, idx)
value = NaN;
if numel(values) >= idx
    value = double(values(idx));
end
end

function tf = localRuntimeRankEvidenceAllowed(source, perLayer)
if ~isempty(perLayer)
    tf = true;
    return;
end
source = lower(strtrim(string(source)));
if strlength(source) == 0
    tf = false;
    return;
end
good = contains(source, ["runtime","measured","receiver","svd","post_equalization"]);
bad = contains(source, ["configured","oracle","proxy","fallback","synthetic"]);
tf = any(good) && ~any(bad);
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end
