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
    options.RuntimeSlot = NaN
    options.Content = "SSB_MIB_SIB1"
end
rawContent=options.Content;
assert(((ischar(rawContent) && isrow(rawContent)) || ...
    (isstring(rawContent) && isscalar(rawContent))) && ...
    any(string(rawContent)==["SSB_MIB","SSB_MIB_SIB1"]), ...
    'sixgr:phy:broadcast:InvalidBroadcastContent', ...
    'Content must be SSB_MIB or SSB_MIB_SIB1.');
content=string(rawContent);
% The buffer remains capture-local, but its encoded radio clock is not.
% RuntimeSlot is zero based; absence preserves the authored carrier frame.
runtimeSlot=options.RuntimeSlot;
assert(isnumeric(runtimeSlot) && isreal(runtimeSlot) && isscalar(runtimeSlot) && ...
    (isnan(runtimeSlot) || (isfinite(runtimeSlot) && runtimeSlot>=0 && ...
    runtimeSlot==fix(runtimeSlot) && double(runtimeSlot)<flintmax)), ...
    'sixgr:link:BroadcastRuntimeOrigin','Use an exact nonnegative runtime slot or NaN.');
if ~isnan(runtimeSlot)
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,double(runtimeSlot)+1);
end
originCarrier=sixgr.phy.grid.makeCarrier(cfg);
assert(originCarrier.NSlot==0, ...
    'sixgr:link:BroadcastRuntimeFrameAlignment', ...
    'A complete broadcast buffer must start on its encoded radio-frame boundary.');
broadcastSlot=double(originCarrier.NFrame)*double(originCarrier.SlotsPerFrame);
assert(isfinite(broadcastSlot) && broadcastSlot>=0 && broadcastSlot<flintmax && ...
    broadcastSlot==fix(broadcastSlot), 'sixgr:link:BroadcastRuntimeOrigin', ...
    'The unwrapped broadcast origin must be an exact nonnegative slot.');
if content=="SSB_MIB_SIB1"
    cfg = localSanitizeSIB1PrecodingConfig(cfg);
end
[cfg, ~] = sixgr.rf.resolveSSBPowerContract(cfg);
requestedSNR_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", Inf));
generatorSNR_dB = requestedSNR_dB;
if useRuntimeChannel
    generatorSNR_dB = Inf;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
    "SNRdB", generatorSNR_dB, ...
    "Seed", double(sixgr.util.structGet(cfg, "run.seed", 1501)), ...
    "Content",content);
assert(tx.Content==content && ...
    ((content=="SSB_MIB" && tx.WaveformContent=="ssb_mib_only" && ...
    tx.SSBEmissionIncluded && ~tx.SIB1EmissionIncluded && ...
    isstruct(tx.SIB1Transmissions) && isempty(tx.SIB1Transmissions)) || ...
    (content=="SSB_MIB_SIB1" && tx.WaveformContent=="ssb_mib_sib1_composite" && ...
    tx.SSBEmissionIncluded && tx.SIB1EmissionIncluded && ~isempty(tx.SIB1Transmissions))), ...
    'sixgr:link:BroadcastContentMismatch','Retain the original producer content scope.');
broadcastSample=sixgr.phy.frame.slotStartSample(originCarrier,broadcastSlot,double(tx.SampleRateHz));
assert(isfield(tx,'BroadcastStartAbsoluteSlot') && isfield(tx,'BroadcastStartSample') && ...
    isequal(tx.BroadcastStartAbsoluteSlot,broadcastSlot) && ...
    isequal(tx.BroadcastStartSample,broadcastSample), ...
    'sixgr:link:BroadcastRuntimeOriginMismatch', ...
    'The original generator must retain the same encoded radio-frame and local-buffer origin.');
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s', ...
    broadcastSample/double(tx.SampleRateHz));
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
            ssbSCS = double(sixgr.util.structGet(tx, ...
                "SSBInfo.SSBTiming.SSBSubcarrierSpacingKHz", NaN));
            validateattributes(ssbSCS, {'numeric'}, ...
                {'scalar','real','finite','positive'});
            mixedNumerology = ssbSCS ~= double(tx.Carrier.SubcarrierSpacing);
            normalizedReference = sixgr.rf.isNormalizedFixedSNRPowerReference(cfg);
            if mixedNumerology && normalizedReference
                % The normalized fixed-Es authority in applyPowerContext
                % preserves the emitted samples; it does not use the
                % absolute-device full-BWP scaler. A common-SCS complex grid
                % cannot represent both native numerologies. Retain the
                % exact SSB and SI grids in tx, rather than resampling them
                % into fictitious REs merely to satisfy an unused scaler.
                % resolveSSBPowerContract already calibrates native SSB RE
                % sample power to the declared common-carrier reference.
                txInfo.PowerNormalizationGridSource = ...
                    "native_ssb_and_sib1_producer_grids_normalized_no_composite_grid";
                if content=="SSB_MIB"
                    txInfo.PowerNormalizationGridSource = ...
                        "native_ssb_producer_grid_normalized_no_common_grid";
                end
                txInfo.SSBSubcarrierSpacingKHz = ssbSCS;
                txInfo.CommonSubcarrierSpacingKHz = double(tx.Carrier.SubcarrierSpacing);
            else
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
            % Samples start at local zero while grid identities retain the
            % original radio epoch. The scaler must join these domains
            % using this TX-owned origin, not a receiver/runtime timestamp.
            txInfo.WaveformStartAbsoluteSymbolIndex0 = ...
                broadcastSlot*double(originCarrier.SymbolsPerSlot);
            txInfo.PowerNormalizationGridSource = ...
                "exact_producer_ssb_pbch_sib1_active_port_grids";
            if content=="SSB_MIB"
                txInfo.PowerNormalizationGridSource = ...
                    "exact_producer_ssb_pbch_active_port_grid";
            end
            end
        end
    catch exception
        if content=="SSB_MIB"
            % This new producer contract must not hide absent/corrupt grid
            % authority even when normalized samples would be unchanged.
            rethrow(exception);
        end
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
    "Content",content,"WaveformContent",tx.WaveformContent, ...
    "Config", cfg, "ReceiverConfig", receiverCfg, "Tx", tx, ...
    "RuntimeTx", runtimeTx, "TxInfo", txInfo, ...
    "TransmitSamples", runtimeTxWaveform, "PowerContext", powerContext, ...
    "RequestedSNR_dB", requestedSNR_dB, "SampleRateHz", double(tx.SampleRateHz), ...
    "BroadcastStartAbsoluteSlot",broadcastSlot,"BroadcastStartSample",broadcastSample, ...
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
        "The production SSB transmitter did not retain its exact waveform-port grid.");
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

% Use the same emitted domain as the SSB grid and waveform. A logical
% waveform has no locally applied physical matrix; its measured port grid
% is still exact and must not be rejected or expanded into element ports.
if isfield(tx,'Content') && tx.Content=="SSB_MIB"
    assert(tx.WaveformContent=="ssb_mib_only" && tx.SSBEmissionIncluded && ...
        ~tx.SIB1EmissionIncluded && isstruct(tx.SIB1Transmissions) && ...
        isempty(tx.SIB1Transmissions), ...
        'sixgr:link:BroadcastContentMismatch','SSB-only power uses no SI allocation.');
    transmissions=tx.SIB1Transmissions;
else
    transmissions=sixgr.phy.broadcast.retainedSIB1Transmissions(tx);
end
siGrids=cell(1,numel(transmissions));
siActive=cell(size(siGrids)); siAbsolute0=cell(size(siGrids));
absoluteSymbols0=double(ssbActive-1);
ssbAbsolute0=double(tx.BroadcastStartAbsoluteSlot)*symbolsPerSlot+absoluteSymbols0;
absoluteSymbols0=ssbAbsolute0;
for occasion=1:numel(transmissions)
    siGrids{occasion}=sixgr.link.broadcastSIB1WaveformPortGrid(transmissions(occasion));
    siActive{occasion}=find(reshape(any(any(siGrids{occasion}~=0,1),3),[],1));
    siAbsolute0{occasion}=double(transmissions(occasion).SIB1AbsoluteSlot)*symbolsPerSlot+ ...
        (siActive{occasion}-1);
    absoluteSymbols0=union(absoluteSymbols0,siAbsolute0{occasion});
end
if isempty(absoluteSymbols0)
    error("sixgr:link:EmptyBroadcastPowerGrid", ...
        "The retained SS/PBCH/SIB1 producer grids contain no transmitted REs.");
end

grid=complex(zeros(nSubcarriers,numel(absoluteSymbols0),nPorts,"like",ssbGrid));
for ordinal=1:numel(ssbActive)
    destination=find(absoluteSymbols0==ssbAbsolute0(ordinal),1);
    grid(start1:start1+239,destination,:)= ...
        grid(start1:start1+239,destination,:)+ssbGrid(:,ssbActive(ordinal),:);
end
for occasion=1:numel(transmissions)
    for ordinal=1:numel(siActive{occasion})
        destination=find(absoluteSymbols0==siAbsolute0{occasion}(ordinal),1);
        grid(:,destination,:)=grid(:,destination,:)+ ...
            siGrids{occasion}(:,siActive{occasion}(ordinal),:);
    end
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
