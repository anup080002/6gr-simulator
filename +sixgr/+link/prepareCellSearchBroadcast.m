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
[cfg, ~] = sixgr.rf.resolveSSBPowerContract(cfg);
requestedSNR_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", Inf));
generatorSNR_dB = requestedSNR_dB;
if useRuntimeChannel
    generatorSNR_dB = Inf;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
    "SNRdB", generatorSNR_dB, ...
    "Seed", double(sixgr.util.structGet(cfg, "run.seed", 1501)));
if tx.SSBPowerReferenceContract.FixedSNRNormalizedReference && ...
        tx.SSBPowerReferenceContract.OFDMUnitReference.SampleRateHz~=double(tx.SampleRateHz)
    error('sixgr:rf:SSBUnitReferenceSamplingMismatch', ...
        'Normalized SSB power calibration and emitted waveform must use the same sample clock.');
end
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
            % active-symbol grid is assembled from the retained production
            % transmitter grids and their executed spatial mappings.  Do
            % not demodulate the full 40 ms x 64-element waveform: that
            % creates another multi-gigabyte array solely to measure EPRE.
            % The compact grid contains every and only active absolute
            % symbols and retains those symbol identities for reconciliation
            % with sample-domain activity below.
            [txInfo.PortGrid,txInfo.PortGridAbsoluteSymbolIndices] = ...
                localExactCompositeActivePortGrid(tx);
            txInfo.PowerNormalizationGridSource = ...
                "exact_producer_ssb_pbch_sib1_active_port_grids";
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
                "The exact SS/PBCH/SIB1 composite resource grid " + ...
                "could not be recovered for configured fixed-EPRE " + ...
                "normalization: %s", exception.message);
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

function [grid,absoluteSymbols0] = localExactCompositeActivePortGrid(tx)
carrier=tx.Carrier;
nSubcarriers=12*double(carrier.NSizeGrid);
nPorts=size(tx.Waveform,2);
symbolsPerSlot=double(carrier.SymbolsPerSlot);

ssbGrid=sixgr.util.structGet(tx, ...
    "SSBWaveInfo.SSBComposite.TransmitPortResourceGrid",[]);
if isempty(ssbGrid) || size(ssbGrid,1)~=240 || size(ssbGrid,3)~=nPorts
    error("sixgr:link:MissingBroadcastSSBPortGrid", ...
        "The production SSB transmitter did not retain its exact physical-port grid.");
end
ssbSCS=double(sixgr.util.structGet(tx,"SSBInfo.SSBTiming.SSBSubcarrierSpacingKHz",NaN));
if ~(isscalar(ssbSCS) && isfinite(ssbSCS) && ...
        abs(ssbSCS-double(carrier.SubcarrierSpacing))<1e-12)
    error("sixgr:link:MixedNumerologyBroadcastPowerGridUnsupported", ...
        "Exact compact broadcast power normalization requires equal SSB and initial-BWP numerology.");
end
validation=sixgr.util.structGet(tx,"SSBInfo.SSBGridValidation",struct());
lowHz=double(sixgr.util.structGet(validation,"SSBLowOffsetFromPointAHz",NaN));
carrierLowHz=double(sixgr.util.structGet(validation,"CarrierLowOffsetFromPointAHz",NaN));
start0=(lowHz-carrierLowHz)/(1000*ssbSCS);
if ~(isscalar(start0) && isfinite(start0) && start0>=0 && ...
        abs(start0-round(start0))<1e-9 && round(start0)+240<=nSubcarriers)
    error("sixgr:link:BroadcastSSBPowerGridAlignmentMismatch", ...
        "The retained SSB physical-port grid is not aligned to the initial DL BWP.");
end
start1=round(start0)+1;
ssbActive=find(reshape(any(any(ssbGrid~=0,1),3),[],1));

siGrid=sixgr.util.structGet(tx,"SIB1Grid",[]);
mapping=sixgr.util.structGet(tx,"SIB1SpatialMapping",struct());
row=sixgr.util.structGet(mapping,"PrecoderMatrix",[]);
if isempty(siGrid) || size(siGrid,1)~=nSubcarriers || size(siGrid,3)~=1 || ...
        ~logical(sixgr.util.structGet(mapping,"MatrixAppliedHere",false)) || ...
        ~isrow(row) || numel(row)~=nPorts || any(~isfinite(row))
    error("sixgr:link:MissingBroadcastSIB1PortGrid", ...
        "The production SIB1 transmitter did not retain its exact logical grid and executed spatial map.");
end
siActive=find(reshape(any(any(siGrid~=0,1),3),[],1));
siAbsolute0=double(tx.SIB1AbsoluteSlot)*symbolsPerSlot+(siActive-1);
absoluteSymbols0=unique([double(ssbActive-1);siAbsolute0(:)],"sorted");
if isempty(absoluteSymbols0)
    error("sixgr:link:EmptyBroadcastPowerGrid", ...
        "The retained SS/PBCH/SIB1 producer grids contain no transmitted REs.");
end

grid=complex(zeros(nSubcarriers,numel(absoluteSymbols0),nPorts,"like",ssbGrid));
for ordinal=1:numel(ssbActive)
    destination=find(absoluteSymbols0==ssbActive(ordinal)-1,1);
    grid(start1:start1+239,destination,:)= ...
        grid(start1:start1+239,destination,:)+ssbGrid(:,ssbActive(ordinal),:);
end
for ordinal=1:numel(siActive)
    destination=find(absoluteSymbols0==siAbsolute0(ordinal),1);
    physical=reshape(siGrid(:,siActive(ordinal),1),nSubcarriers,1)* ...
        cast(row,"like",siGrid);
    grid(:,destination,:)=grid(:,destination,:)+reshape(physical,nSubcarriers,1,nPorts);
end
if any(~isfinite(grid),"all") || any(~any(grid~=0,[1 3]))
    error("sixgr:link:InvalidBroadcastPowerGrid", ...
        "Every compact broadcast power-grid symbol must contain finite transmitted REs.");
end
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
