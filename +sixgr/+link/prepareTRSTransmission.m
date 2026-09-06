function prepared = prepareTRSTransmission(cfg, snr_dB, options)
%PREPARETRSTRANSMISSION Prepare real TRS samples without RF/channel/RX execution.
% The slot scheduler owns waveform composition and physical transmission.
arguments
    cfg (1,1) struct
    snr_dB (1,1) double
    options.RuntimeSlot = []
end
runId = string(sixgr.util.structGet(cfg, "run.id", ...
    sixgr.util.structGet(cfg, "meta.scenario_id", "trs_runtime_tracking")));
scenarioName = string(sixgr.util.structGet(cfg, "scenario.name", ...
    sixgr.util.structGet(cfg, "meta.scenario_id", "trs_runtime_tracking")));
strictCfg = sixgr.phy.trs.buildTRSConfigFromScenario(cfg, ...
    "RunId", runId, "ScenarioName", scenarioName,"RuntimeSlot",options.RuntimeSlot);
if isfield(strictCfg, "StrictValidation") && ...
        isfield(strictCfg.StrictValidation, "StrictValid") && ...
        ~logical(strictCfg.StrictValidation.StrictValid)
    reason = string(sixgr.util.structGet(strictCfg.StrictValidation, "StrictUnsupportedReason", ...
        "strict_trs_config_invalid"));
    error("sixgr:link:TRSStrictConfigInvalid", ...
        "Strict TRS runtime config is invalid: %s", char(reason));
end

tx = sixgr.phy.trs.generateTRSWaveform(strictCfg);

receiverCfg = localPrepareTRSReceiverObservationConfig(cfg, snr_dB);
txInfo = localTRSTxInfo(tx, strictCfg);
[transmitSamples, powerContext] = sixgr.rf.applyPowerContext( ...
    tx.Waveform, receiverCfg, "DL", txInfo);
receiverCfg = sixgr.util.structSet(receiverCfg, ...
    "lls6g.runtimePowerContext", powerContext);
prepared = struct("ExecutionStage", "trs_waveform_prepared_not_received", ...
    "StrictConfig", strictCfg, "Tx", tx, "TxInfo", txInfo, ...
    "ReceiverConfig", receiverCfg, "PowerContext", powerContext, ...
    "TransmitSamples", transmitSamples, "SampleRateHz", double(tx.SampleRateHz), ...
    "NumSamples", size(transmitSamples,1), "RequestedSNR_dB", snr_dB, ...
    "RFExecutionDeferred", true, "ChannelExecutionDeferred", true);
end

function cfgOut = localPrepareTRSReceiverObservationConfig(cfg, snr_dB)
cfgOut = cfg;
resolved = sixgr.util.structGet(cfgOut,"lls6g.resolvedConfig",struct());
hasYAMLAuthority = isstruct(resolved) && ~isempty(fieldnames(resolved));
noiseMode = strtrim(string(sixgr.util.structGet( ...
    cfgOut,"run.noiseOperatingMode","")));
if ~hasYAMLAuthority && strlength(noiseMode) == 0
    cfgOut = sixgr.util.structSet(cfgOut,"run.noiseOperatingMode", ...
        "standalone_awgn_snr_argument");
end
cfgOut = sixgr.util.structSet(cfgOut, "channel.snr_dB", double(snr_dB));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeSignalFamily", "TRS");
cfgOut = sixgr.util.structSet(cfgOut, "phy.runtimeSignalFamily", "TRS");
cfgOut = sixgr.util.structSet(cfgOut, ...
    "lls6g.userContext.RuntimeCurrentDirection","DL");
cfgOut = sixgr.util.structSet(cfgOut, ...
    "lls6g.userContext.Direction","DL");
cfgOut = sixgr.util.structSet(cfgOut,"channel.linkDirection","DL");
end

function txInfo = localTRSTxInfo(tx,strictCfg)
if isfield(tx,"PortGrid") && isfield(tx,"OFDM")
    txInfo = struct("OFDM",tx.OFDM,"PortGrid",tx.PortGrid, ...
        "PowerNormalizationGridSource","exact_trs_multislot_port_grids");
    return;
end
ofdm = struct("SampleRate",double(sixgr.util.structGet( ...
    tx,"SampleRateHz",NaN)));
carrier = sixgr.util.structGet(strictCfg,"ToolboxCarrier",[]);
if ~isempty(carrier)
    try
        ofdm = nrOFDMInfo(carrier);
    catch
    end
end
txInfo = struct("OFDM",ofdm);
slots = sixgr.util.structGet(tx,"GridSlots",struct([]));
if ~isempty(slots)
    exactGrids = arrayfun(@(slot) {sixgr.util.structGet( ...
        slot,"Grid",[])},slots);
    if any(cellfun(@isempty,exactGrids))
        error("sixgr:link:TRSExactPowerGridUnavailable", ...
            "Every TRS waveform slot must retain its exact transmitted " + ...
            "port-domain resource grid for physical power normalization.");
    end
    referenceSubcarriers = size(exactGrids{1},1);
    referencePorts = size(exactGrids{1},3);
    compatible = cellfun(@(grid) ...
        size(grid,1) == referenceSubcarriers && ...
        size(grid,3) == referencePorts,exactGrids);
    if ~all(compatible)
        error("sixgr:link:TRSPowerGridDimensionMismatch", ...
            "TRS slot grids have incompatible subcarrier or port dimensions.");
    end
    txInfo.PortGrid = cat(2,exactGrids{:});
    txInfo.PowerNormalizationGridSource = ...
        "exact_trs_multislot_port_grids";
end
end
