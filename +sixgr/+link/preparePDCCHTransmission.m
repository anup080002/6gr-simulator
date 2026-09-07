function prepared = preparePDCCHTransmission(cfg, varargin)
%PREPAREPDCCHTRANSMISSION Materialize DCI/grid/samples, without RF/channel/RX.
% Callers resolve the grant's control slot and aggregation policy first.
% Samples retain the Toolbox logical-port normalization. Power allocation,
% physical antenna projection and node RF execution belong to the stream
% owner; this stage does not apply a PA independently to each contributor.
[tx,txInfo] = sixgr.phy.dl.PDCCH_Tx(cfg,varargin{:});
if isempty(tx.Waveform)
    error('sixgr:link:PDCCHWaveformRequired','PDCCH preparation requires actual OFDM samples.');
end
fs = sixgr.util.structGet(txInfo,'OFDM.SampleRate',NaN);
validateattributes(fs,{'numeric'},{'real','scalar','finite','positive'});
startSample = NaN;
startTime = sixgr.util.structGet(cfg,'lls6g.userContext.RuntimeSlotStartTime_s',[]);
if ~isempty(startTime)
    validateattributes(startTime,{'numeric'},{'real','scalar','finite','nonnegative'});
    if abs(double(startTime)*double(fs)-round(double(startTime)*double(fs)))>1e-6
        error('sixgr:link:PDCCHPreparationClockMismatch', ...
            'The scheduled PDCCH origin must lie on the actual sample clock.');
    end
    startSample = round(double(startTime)*double(fs));
end
resources={tx.PDCCHInd,tx.DMRSInd};
if logical(sixgr.util.structGet(cfg,'phy.pdcch.blindSearch',false))
    [candidateIndices,~,candidateDMRS]=nrPDCCHSpace(tx.Carrier,tx.PDCCH);
    resources={candidateIndices,candidateDMRS};
end
extent=sixgr.phy.dl.pdcchObservationExtent(tx.Carrier,resources,txInfo.OFDM);
prepared = struct('ExecutionStage',"pdcch_waveform_prepared_not_received", ...
    'Tx',tx,'TxInfo',txInfo,'ReceiverConfig',cfg, ...
    'TransmitSamples',tx.Waveform,'SampleRateHz',double(fs),'NumSamples',size(tx.Waveform,1), ...
    'RuntimeStartSample',startSample, ...
    'ReceiveExtent',extent,'MinimumReceiveSamples',extent.MinimumReceiveSamples, ...
    'SampleDomain',"toolbox_normalized_logical_ports",'PowerExecutionDeferred',true, ...
    'RFExecutionDeferred',true,'ChannelExecutionDeferred',true);
end
