function prepared = prepareCellSearchBroadcast(cfg, useRuntimeChannel, options)
%PREPARECELLSEARCHBROADCAST Prepare broadcast waveform and power context.
% The runtime may enqueue TransmitSamples without consuming future samples
% or asserting acquisition. All resource/coding/power policy remains in cfg.
% Runtime mode generates noiseless TX; standalone mode preserves the
% existing generator's configured AWGN behavior. Neither executes a decoder.
% Shared-stream preparation defers PA; the immediate legacy caller may
% explicitly apply it while preparing its single complete waveform.
arguments
    cfg (1,1) struct
    useRuntimeChannel (1,1) logical
    options.ApplyPA (1,1) logical = false
end
cfg = localSanitizeSIB1PrecodingConfig(cfg);
requestedSNR_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", Inf));
generatorSNR_dB = requestedSNR_dB;
if useRuntimeChannel
    generatorSNR_dB = Inf;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
    "SNRdB", generatorSNR_dB, ...
    "Seed", double(sixgr.util.structGet(cfg, "run.seed", 1501)));
receiverCfg = cfg;
runtimeTx = tx;
runtimeTxWaveform = tx.Waveform;
powerContext = struct();
txInfo = struct("OFDM", struct("SampleRate", double(tx.SampleRateHz)));
if useRuntimeChannel
    try
        if isfield(tx, "Carrier") && ~isempty(tx.Carrier)
            txInfo.OFDM = nrOFDMInfo(tx.Carrier);
            % Bind fixed-EPRE normalization to the exact composite
            % waveform that carries SS/PBCH and SI-RNTI SIB1.  The
            % grid is recovered from the unscaled generated
            % waveform on the same carrier; it is not regenerated
            % from YAML or inferred from planned allocations.
            txInfo.PortGrid = nrOFDMDemodulate( ...
                tx.Carrier, tx.Waveform);
            txInfo.PowerNormalizationGridSource = ...
                "exact_composite_ssb_pbch_sib1_waveform_demodulation";
        end
    catch exception
        policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
            "lls6g.resolvedConfig.power_and_rf_frontend.downlink_power_normalization_policy", ...
            sixgr.util.structGet(cfg, ...
            "powerAndRF.downlinkPowerNormalizationPolicy", "")))));
        if any(policy == ["fixed_epre_over_configured_bwp", ...
                "full_bwp_reference_epre", "fixed_full_bwp_epre"])
            wrapped = MException( ...
                "sixgr:link:BroadcastPowerNormalizationGridUnavailable", ...
                ["The exact SS/PBCH/SIB1 composite resource grid " ...
                 "could not be recovered for configured fixed-EPRE " ...
                 "normalization: %s"], exception.message);
            wrapped = addCause(wrapped, exception);
            throwAsCaller(wrapped);
        end
    end
    [runtimeTxWaveform, powerContext] = sixgr.rf.applyPowerContext( ...
        tx.Waveform, cfg, "DL", txInfo,"ApplyPA",options.ApplyPA);
    receiverCfg = sixgr.util.structSet( ...
        receiverCfg, "lls6g.runtimePowerContext", powerContext);
    runtimeTx = tx;
    runtimeTx.Waveform = runtimeTxWaveform;
    runtimeTx.PowerContext = powerContext;
    txInfo.PowerContext = powerContext;
end
prepared = struct("ExecutionStage", "broadcast_waveform_prepared_not_decoded", ...
    "Config", cfg, "ReceiverConfig", receiverCfg, "Tx", tx, ...
    "RuntimeTx", runtimeTx, "TxInfo", txInfo, ...
    "TransmitSamples", runtimeTxWaveform, "PowerContext", powerContext, ...
    "RequestedSNR_dB", requestedSNR_dB, "SampleRateHz", double(tx.SampleRateHz), ...
    "NumSamples", size(runtimeTxWaveform,1), ...
    "RuntimeChannelDeferred", useRuntimeChannel, ...
    "RFExecutionDeferred", ~logical(sixgr.util.structGet(powerContext,"PAApplied",false)), ...
    "PAExecutionDeferred", logical(sixgr.util.structGet(powerContext,"PAExecutionDeferred",false)));
end

function cfgOut = localSanitizeSIB1PrecodingConfig(cfgIn)
cfgOut = cfgIn;
% SI-RNTI SIB1 is a common, single-layer broadcast allocation.  The
% scenario data-PDSCH rank and immutable UE-specific precoder are not part
% of that allocation's context.  Establish the broadcast context before
% Type-0/PDSCH materialization so a rank-2 data matrix cannot become a
% stale explicit matrix after deriveType0PDCCHFromMIB sets NumLayers=1.
nLayers = 1;
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", nLayers);
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
for i = 1:numel(paths)
    cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
end
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.enabled", false);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.mode", ...
    "broadcast_single_port");
end
