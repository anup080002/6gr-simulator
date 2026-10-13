function rows=diagnosePDSCHNativeReceiverReplay(capturePaths,outputCSV,iterationLimits)
% Independent native Toolbox estimator/equalizer/demapper/decoder comparison.
% Uses the already aligned received grid; does NOT independently validate sync.
% Same grants, resource exclusions and TB lengths. An explicit iteration sweep
% is diagnostic only; it does not modify the captured scenario or receiver.
arguments
    capturePaths (:,1) string
    outputCSV (1,1) string
    iterationLimits (1,:) double {mustBeInteger,mustBePositive} = zeros(1,0)
end
rows=table();
for file=capturePaths.'
    data=load(file,'ReceiverReplay'); c=data.ReceiverReplay; rx=c.ReceiverResult;
    assert(c.Direction=="DL" && c.Contract=="exact_receiver_replay/v1");
    assert(c.WaveformSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(c.Waveform)));
    carrier=rx.Carrier; pdsch=rx.PDSCH;
    assert(pdsch.NumLayers==1 && numel(rx.TransportBlockSize)==1, ...
        'This first native diagnostic is explicitly single-layer, single-codeword.');
    indices=nrPDSCHDMRSIndices(carrier,pdsch); reference=nrPDSCHDMRS(carrier,pdsch);
    [hest,noiseEstimate]=nrChannelEstimate(carrier,rx.OFDMGrid,indices,reference, ...
        'CDMLengths',pdsch.DMRS.CDMLengths,'AveragingWindow',[0 0]);
    [y,H]=nrExtractResources(rx.PDSCHIndices,rx.OFDMGrid,hest);
    for noiseMode=["executed_receiver_noise","native_pilot_estimated_noise", ...
            "configured_noise_from_receiver_contract"]
        noise=double(rx.PreEqualizationNoiseVar);
        if noiseMode=="native_pilot_estimated_noise", noise=double(noiseEstimate); end
        if noiseMode=="configured_noise_from_receiver_contract"
            noise=double(rx.ReceiverConfig.NoiseVariance);
        end
        [equalized,csi]=nrEqualizeMMSE(y,H,noise);
        [llrs,codewordSymbols]=nrPDSCHDecode(carrier,pdsch,equalized,noise);
        csi=nrLayerDemap(csi);
        for cw=1:numel(llrs)
            qm=numel(llrs{cw})/numel(codewordSymbols{cw});
            scale=repmat(csi{cw}.',qm,1);
            llrs{cw}=llrs{cw}.*scale(:);
        end
        limits=iterationLimits;
        if isempty(limits), limits=double(rx.ReceiverConfig.MaxIterations); end
        for maxIterations=limits
        decoder=nrDLSCHDecoder('TargetCodeRate',rx.CodingPlans{1}.TargetCodeRate, ...
            'TransportBlockLength',rx.TransportBlockSize, ...
            'LDPCDecodingAlgorithm',rx.ReceiverConfig.Algorithm, ...
            'MaximumLDPCIterationCount',maxIterations);
        [bits,crcError]=decoder(llrs,pdsch.Modulation,pdsch.NumLayers,rx.CodingPlans{1}.RV);
        if iscell(bits), bits=bits{1}; end
        % The reference bits are consulted only after native decoding.
        errors=nnz(bits(:)~=c.Context.ScoringOnlyTransmittedBits(:));
        rows=[rows;table(file,c.Context.Slot,noiseMode,logical(rx.TBCRCPass), ...
            ~logical(crcError),errors,numel(bits),noise, ...
            rx.CodingPlans{1}.TargetCodeRate,string(pdsch.Modulation), ...
            maxIterations,double(rx.ReceiverConfig.MaxIterations),false, ...
            'VariableNames',{'CaptureMAT','Slot','NoiseMode','SixGRCRCPass', ...
            'NativeCRCPass','NativeBitErrors','TBSBits','NativeNoiseVariance', ...
            'TargetCodeRate','Modulation','MaximumLDPCIterations', ...
            'CapturedMaximumLDPCIterations','StatisticallyQualified'})]; %#ok<AGROW>
        sixgr.util.csvWriteTable(outputCSV,rows,'PreserveSchema',true,'RoundTripNumericText',true);
        end
    end
end
end
