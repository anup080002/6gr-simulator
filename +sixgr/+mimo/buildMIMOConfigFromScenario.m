function T = buildMIMOConfigFromScenario(cfg, varargin)
%BUILDMIMOCONFIGFROMSCENARIO Resolve nominal MIMO config without using it as evidence.

ip = inputParser;
ip.addParameter("RunId", "", @(x) ischar(x) || isstring(x) || isnumeric(x));
ip.addParameter("ScenarioName", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});

runId = string(ip.Results.RunId);
scenarioName = string(ip.Results.ScenarioName);
rows = [localRow(cfg, "DL", runId, scenarioName); localRow(cfg, "UL", runId, scenarioName)];
T = struct2table(rows);
end

function row = localRow(cfg, direction, runId, scenarioName)
direction = upper(string(direction));
if direction == "DL"
    txAnt = localFirstFinite(cfg, ["runtime.antenna.gnb.NumPhysicalElements","scenario.bs.nTxAnt","antenna_and_array.bs_num_antenna_elements","mimo.n_tx_ant","channel.nTxAnt","phy.nTxAnt"], NaN);
    rxAnt = localFirstFinite(cfg, ["runtime.antenna.ue.NumPhysicalElements","scenario.ue.nRxAnt","antenna_and_array.ue_num_antenna_elements","mimo.n_rx_ant","channel.nRxAnt","phy.nRxAnt"], NaN);
    txPorts = localFirstFinite(cfg, ["runtime.phy.dl.NumLogicalPorts","phy.pdsch.NumAntennaPorts","phy.pdsch.numAntennaPorts", ...
        "phy.pdsch.numPorts","phy.pdsch.nPorts","phy.pdsch.numLayers","phy.pdsch.nLayers"], NaN);
    rxPorts = localFirstFinite(cfg, ["runtime.phy.dl.NumLayers","phy.pdsch.numLayers","phy.pdsch.nLayers"], NaN);
    layers = localFirstFinite(cfg, ["runtime.phy.dl.NumLayers","phy.pdsch.numLayers","phy.pdsch.nLayers","pdsch6gr.NumLayers","mimo.n_layers"], NaN);
    mcs = localFirstFinite(cfg, ["runtime.phy.dl.MCSIndex","phy.pdsch.mcsIndex","pdsch.mcs_index","modulation.dl_mcs_index"], NaN);
    modulation = localFirstText(cfg, ["runtime.phy.dl.Modulation","phy.pdsch.modulation","pdsch.modulation","modulation_and_mapping.pdsch_modulation"], "");
    pmi = localFirstFinite(cfg, ["phy.pdsch.PMI","pdsch.PMI"], NaN);
    txRFChains = localFirstFinite(cfg, ["rf.bs.numRFChains","antenna.bs.numRFChains", ...
        "scenario.bs.numRFChains","antenna_and_array.bs_num_txrus","mimo.n_txrus"], txPorts);
    rxRFChains = localFirstFinite(cfg, ["rf.ue.numRFChains","antenna.ue.numRFChains", ...
        "scenario.ue.numRFChains","antenna_and_array.ue_num_rxrus","mimo.n_rxrus"], rxPorts);
    mcsSelectionPolicy = localFirstText(cfg, ["runtime.link_adaptation.DLPolicy","phy.linkAdaptation.dlPolicy", ...
        "link_adaptation.pdsch_link_adaptation_policy","mac.linkAdaptation.dlPolicy"], "");
else
    txAnt = localFirstFinite(cfg, ["runtime.antenna.ue.NumPhysicalElements","scenario.ue.nTxAnt","antenna_and_array.ue_num_txrus","mimo.ue_n_tx_ant","channel.nTxAntUL","phy.pusch.numAntennaPorts"], ...
        localFirstFinite(cfg, ["scenario.ue.nTxAnt","phy.pusch.numLayers","phy.pusch.nLayers"], 1));
    rxAnt = localFirstFinite(cfg, ["runtime.antenna.gnb.NumPhysicalElements","scenario.bs.nRxAnt","antenna_and_array.bs_num_rxrus","mimo.bs_n_rx_ant","channel.nRxAntUL","channel.nRxAnt"], NaN);
    txPorts = localFirstFinite(cfg, ["runtime.phy.ul.NumLogicalPorts","phy.pusch.NumAntennaPorts","phy.pusch.numAntennaPorts","phy.pusch.numLayers","phy.pusch.nLayers"], txAnt);
    rxPorts = localFirstFinite(cfg, ["runtime.phy.ul.NumLayers","phy.pusch.numLayers","phy.pusch.nLayers"], NaN);
    layers = localFirstFinite(cfg, ["runtime.phy.ul.NumLayers","phy.pusch.numLayers","phy.pusch.nLayers","pusch6gr.NumLayers","mimo.ul_n_layers","mimo.n_layers"], NaN);
    mcs = localFirstFinite(cfg, ["runtime.phy.ul.MCSIndex","phy.pusch.mcsIndex","pusch.mcs_index","modulation.ul_mcs_index"], NaN);
    modulation = localFirstText(cfg, ["runtime.phy.ul.Modulation","phy.pusch.modulation","pusch.modulation","modulation_and_mapping.pusch_modulation"], "");
    pmi = localFirstFinite(cfg, ["phy.pusch.PMI","phy.pusch.TPMI","pusch.PMI"], NaN);
    txRFChains = localFirstFinite(cfg, ["rf.ue.numRFChains","antenna.ue.numRFChains", ...
        "scenario.ue.numRFChains","antenna_and_array.ue_num_txrus"], txPorts);
    rxRFChains = localFirstFinite(cfg, ["rf.bs.numRFChains","antenna.bs.numRFChains", ...
        "scenario.bs.numRFChains","antenna_and_array.bs_num_rxrus"], rxPorts);
    mcsSelectionPolicy = localFirstText(cfg, ["runtime.link_adaptation.ULPolicy","phy.linkAdaptation.ulPolicy", ...
        "link_adaptation.pusch_link_adaptation_policy","mac.linkAdaptation.ulPolicy"], "");
end
if strlength(strtrim(modulation)) == 0
    modulation = localModulationFromMCS(mcs);
end
layers = max(1, round(double(layers)));
rank = layers;
txAnt = localPositiveIntegerOrNaN(txAnt);
rxAnt = localPositiveIntegerOrNaN(rxAnt);
txPorts = localPositiveIntegerOrNaN(txPorts);
rxPorts = localPositiveIntegerOrNaN(rxPorts);
dmrsPorts = 0:(max(1, layers)-1);

fixedAnchor = localIsFixedAnchor(cfg);
% Rank anchoring and MCS/modulation adaptation are independent controls.
% A fixed-rank MU-MIMO campaign may still run AMC; do not classify its
% receiver-selected MCS/modulation as a MIMO configuration mismatch.
adaptiveMode = localIsAdaptiveLinkMode(cfg, fixedAnchor);
if strlength(strtrim(mcsSelectionPolicy)) == 0
    mcsSelectionPolicy = string(localTernary(adaptiveMode, "adaptive", "configured_fixed"));
end
if direction == "DL"
    muMIMOEnabled = logical(sixgr.util.structGet(cfg, "mac.scheduler.muMimoEnabled", ...
        sixgr.util.structGet(cfg, "phy.mimo.muMimoEnabled", ...
        sixgr.util.structGet(cfg, "mimo.mu_mimo_enable", false))));
else
    muMIMOEnabled = logical(sixgr.util.structGet(cfg, "mac.scheduler.ulMuMimoEnabled", ...
        sixgr.util.structGet(cfg, "phy.mimo.ulMuMimoEnabled", ...
        sixgr.util.structGet(cfg, "mimo.ul_mu_mimo_enable", false))));
end
muMIMOUsersPerPRB = localFirstFinite(cfg, ...
    ["mac.scheduler.muMimoMaxUsersPerPRB", ...
    "phy.mimo.muMimoMaxUsersPerPRB", ...
    "mimo.mu_mimo_max_users_per_prb"], 2);
muMIMOUsersPerPRB = max(2, round(double(muMIMOUsersPerPRB)));
muMIMOLeakageThreshold_dB = localFirstFinite(cfg, ...
    ["mac.scheduler.muMimoPrecoderLeakageThreshold_dB", ...
    "phy.mimo.muMimoPrecoderLeakageThreshold_dB", ...
    "mimo.mu_mimo_precoder_leakage_threshold_db"], -15);
muMIMOExecutionMode = string(localFirstText(cfg, ...
    ["run.intraCellInterferenceExecutionMode", ...
    "execution.intra_cell_interference_execution_mode"], "none"));
rankSource = string(localTernary(fixedAnchor, "fixed_anchor", "scheduler_or_csi_runtime"));
fullElementDomainRequired = logical(sixgr.util.structGet(cfg, ...
    "phy.beamManagement.hybridBeamformingEnabled", ...
    sixgr.util.structGet(cfg,"mimo.hybrid_beamforming_flag",false)));
initialMCS = localFirstFinite(cfg, ...
    ["runtime.link_adaptation.InitialMCSIndex", ...
    "phy.linkAdaptation.initialMCSIndex", ...
    "link_adaptation.initial_mcs", ...
    "link_adaptation.bootstrap_mcs_index"], NaN);
maximumMCS = localFirstFinite(cfg, ...
    ["runtime.link_adaptation.MaximumMCSIndex", ...
    "phy.linkAdaptation.maximumMCSIndex", ...
    "link_adaptation.maximum_mcs"], NaN);
configHash = sixgr.mimo.hashMIMOConfig(struct( ...
    "Direction", direction, "TxAnt", txAnt, "RxAnt", rxAnt, "TxPorts", txPorts, ...
    "RxPorts", rxPorts, "Layers", layers, "MCS", mcs, "Modulation", modulation));

row = struct( ...
    "RunId", runId, "ScenarioName", scenarioName, "Direction", direction, ...
    "CellId", NaN, "SectorId", NaN, "UEId", NaN, ...
    "CarrierFrequencyHz", localFirstFinite(cfg, ["frequency.carrier_hz","carrier_frequency_hz","carrierFrequencyHz"], NaN), ...
    "FrequencyRange", string(localFirstText(cfg, ["frequency.frequency_range","phy.carrier.FrequencyRange"], "")), ...
    "NCellID", localFirstFinite(cfg, ["phy.carrier.NCellID","NCellID"], NaN), ...
    "NSizeGrid", localFirstFinite(cfg, ["phy.carrier.NSizeGrid","frequency.n_size_grid"], NaN), ...
    "SubcarrierSpacingKHz", localFirstFinite(cfg, ["phy.carrier.SubcarrierSpacing","frequency.subcarrier_spacing_khz"], NaN), ...
    "PhysicalTxAntennaCount", txAnt, "PhysicalRxAntennaCount", rxAnt, ...
    "TxRFChainCount", txRFChains, ...
    "RxRFChainCount", rxRFChains, ...
    "TxAntennaPortCount", txPorts, "RxAntennaPortCount", rxPorts, ...
    "FullElementDomainRequired", fullElementDomainRequired, ...
    "DMRSPorts", string(strjoin(string(dmrsPorts), "|")), "DMRSPortCount", double(numel(dmrsPorts)), ...
    "ConfiguredRank", rank, "ConfiguredLayers", layers, "ConfiguredCodewords", localCodewords(layers), ...
    "ConfiguredModulation", string(modulation), "ConfiguredMCS", double(mcs), ...
    "ConfiguredInitialMCS", double(initialMCS), ...
    "ConfiguredMaximumMCS", double(maximumMCS), ...
    "ConfiguredMCSSelectionPolicy", string(mcsSelectionPolicy), ...
    "ConfiguredMUMIMOEnabled", logical(muMIMOEnabled), ...
    "ConfiguredMUUsersPerPRB", double(muMIMOUsersPerPRB), ...
    "ConfiguredMUMIMOLeakageThreshold_dB", double(muMIMOLeakageThreshold_dB), ...
    "ConfiguredMUMIMOExecutionMode", string(muMIMOExecutionMode), ...
    "ConfiguredMCSTable", string(localFirstText(cfg, ["phy.pdsch.mcsTable","phy.pusch.mcsTable","link_adaptation.mcs_table"], "")), ...
    "ConfiguredTransmissionScheme", string(localFirstText(cfg, ["mimo.transmission_scheme","phy.pdsch.transmissionScheme","phy.pusch.transmissionScheme"], "")), ...
    "CodebookType", string(localFirstText(cfg, ["phy.csi.codebookType","mimo.codebook_type"], "")), ...
    "CodebookMode", string(localFirstText(cfg, ["phy.csi.codebookMode","mimo.codebook_mode"], "")), ...
    "PrecodingMode", string(localFirstText(cfg, ["mimo.precoding_mode","phy.pdsch.precodingMode","phy.pusch.precodingMode"], "")), ...
    "BeamformingMode", string(localFirstText(cfg, ["mimo.beamforming_mode","system.beam.mode","phy.beamManagement.mode"], "")), ...
    "ConfiguredPMI", double(pmi), "FixedAnchorMode", logical(fixedAnchor), "AdaptiveMode", logical(adaptiveMode), ...
    "RankSelectionSource", rankSource, "PrecoderSelectionSource", string(localTernary(isfinite(pmi), "configured_pmi", "runtime_or_unavailable")), ...
    "BeamSelectionSource", string(localFirstText(cfg, ["users.beam_selection_strategy","lls6g.users.beam_selection_strategy","lls6g.userContext.BeamSelectionStrategy"], "")), ...
    "StrictUnsupportedReason", "", "ConfigHash", configHash, "Status", "not_validated");
end

function value = localFirstFinite(cfg, paths, defaultValue)
value = defaultValue;
for p = string(paths)
    raw = sixgr.util.structGet(cfg, p, []);
    if isempty(raw), continue; end
    v = str2double(string(raw));
    if isnumeric(raw), v = double(raw); end
    v = v(:);
    idx = find(isfinite(v), 1);
    if ~isempty(idx)
        value = double(v(idx));
        return;
    end
end
end

function value = localFirstText(cfg, paths, defaultValue)
value = string(defaultValue);
for p = string(paths)
    raw = sixgr.util.structGet(cfg, p, []);
    if isempty(raw), continue; end
    s = strtrim(string(raw));
    s = s(:);
    s = s(arrayfun(@localUsableText, s));
    if ~isempty(s)
        value = s(1);
        return;
    end
end
end

function n = localPositiveIntegerOrNaN(v)
n = double(v);
if ~(isfinite(n) && n >= 1)
    n = NaN;
else
    n = max(1, round(n));
end
end

function n = localCodewords(layers)
if layers <= 4
    n = 1;
else
    n = 2;
end
end

function tf = localIsFixedAnchor(cfg)
rankTokens = lower(strtrim([ ...
    string(sixgr.util.structGet(cfg, "runtime.link_adaptation.RankPolicy", "")); ...
    string(sixgr.util.structGet(cfg, "mimo.rank_adaptation_policy", "")); ...
    string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", ""))]));
rankTokens = replace(rankTokens,"-","_");
rankTokens = rankTokens(strlength(rankTokens) > 0);
fixedTokens = ["fixed","fixed_rank","configured_fixed","disabled","off", ...
    "none","false","fixed_anchor","fixed_rank_anchor","no_adaptation"];
adaptiveTokens = ["adaptive","ri","measured_ri","runtime","runtime_ri", ...
    "csi_feedback","ri_pmi_cqi"];
if ~isempty(rankTokens)
    tf = any(ismember(rankTokens,fixedTokens)) && ...
        ~any(ismember(rankTokens,adaptiveTokens));
    return;
end
modeTokens = lower(strtrim([ ...
    string(sixgr.util.structGet(cfg,"link_adaptation.fixed_or_amc","")); ...
    string(sixgr.util.structGet(cfg,"phy.linkAdaptation.mode",""))]));
modeTokens = replace(modeTokens,"-","_");
modeTokens = modeTokens(strlength(modeTokens) > 0);
tf = any(ismember(modeTokens,["fixed","fixed_mcs","configured_fixed"]));
end

function tf = localIsAdaptiveLinkMode(cfg, fixedRankAnchor)
modeTokens = lower(strtrim([ ...
    string(sixgr.util.structGet(cfg,"runtime.link_adaptation.Mode","")); ...
    string(sixgr.util.structGet(cfg,"link_adaptation.fixed_or_amc","")); ...
    string(sixgr.util.structGet(cfg,"phy.linkAdaptation.mode","")); ...
    string(sixgr.util.structGet(cfg,"mac.linkAdaptation.mode",""))]));
modeTokens = replace(modeTokens,"-","_");
modeTokens = modeTokens(strlength(modeTokens) > 0);
adaptiveTokens = ["amc","adaptive","cqi_driven","olla","outer_loop", ...
    "runtime","scheduler","csi_feedback"];
fixedTokens = ["fixed","fixed_mcs","configured_fixed","off","disabled"];
if any(ismember(modeTokens,adaptiveTokens))
    tf = true;
elseif any(ismember(modeTokens,fixedTokens))
    tf = false;
else
    % Preserve legacy behavior when no independent link-adaptation mode is
    % available, without coupling explicit AMC to the rank policy.
    tf = ~logical(fixedRankAnchor);
end
end

function mod = localModulationFromMCS(mcs)
if ~(isfinite(double(mcs)) && double(mcs) >= 0)
    mod = "";
elseif mcs <= 9
    mod = "QPSK";
elseif mcs <= 16
    mod = "16QAM";
elseif mcs <= 27
    mod = "64QAM";
else
    mod = "256QAM";
end
end

function y = localTernary(cond, a, b)
if cond
    y = a;
else
    y = b;
end
end

function tf = localUsableText(s)
s = lower(strtrim(string(s)));
tf = ~ismissing(s) && strlength(s) > 0 && ~ismember(s, ["nan","<missing>","missing","none","unavailable"]);
end
