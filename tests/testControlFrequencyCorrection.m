function ok=testControlFrequencyCorrection()
% Native OFDM samples; configured sparse symbols, original clocks and no oracle.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(92812,'twister');
checked=0;
for scs=[15 30 60]
    carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',scs,'NSlot',1);
    grid=nrResourceGrid(carrier,2);
    grid(:)=nrSymbolModulate(randi([0 1],2*numel(grid),1),'QPSK');
    [wave,info]=sixgr.phy.waveform.ofdmModulate(carrier,grid,'Windowing',0);
    sampling=info.OFDMSamplingResolution;
    lens=sampling.CyclicPrefixLengthsPerSlot+sampling.Nfft;
    starts=[0 cumsum(lens)];
    selected=[1 3];
    fs=info.SampleRate;
    for policy=["full_prefix","received_coherence_window"]
        cfg.phy.rx.cfoCorrectionEnabled=true;
        cfg.phy.impairments.cfoEstimationMethod='cyclic_prefix';
        cfg.phy.impairments.cfoCPObservation=struct('Policy',policy, ...
            'WindowFraction',0.5,'FalseAlarmProbability',0.001);
        for hz=[-430 430]
            input=wave.*exp(2i*pi*2100/fs*(0:size(wave,1)-1).');
            % Unselected symbols have another oscillator: including them
            % would produce a wrong estimate despite using the right Fs.
            for symbol=selected
                at=(starts(symbol+1)+1):starts(symbol+2);
                input(at,:)=wave(at,:).*exp(2i*pi*hz/fs*(at(:)-1));
            end
            [corrected,e]=sixgr.phy.rx.applyControlFrequencyCorrection(input,carrier,cfg,selected);
            assert(e.CFOCorrectionApplied && abs(e.EstimatedCFO_Hz-hz)<1e-8);
            assert(e.CFOObservation.NumSymbolsUsed==numel(selected) && ...
                isequal(e.CFOObservation.SymbolIndices0Based,selected));
            expected=input.*exp(-2i*pi*hz/fs*(0:size(input,1)-1).');
            assert(max(abs(corrected(:)-expected(:)))<1e-10);
            assert(abs(e.ResidualCFOEstimatorConsistency_Hz)<1e-8 && ...
                e.ResidualCFOReusesAcquisitionObservation && ...
                contains(e.ResidualCFOEstimateRole,'not_independent'));
            % Injection audit labels must not alter measured reception.
            cfg.phy.impairments.cfoHz=9000; cfg.phy.impairments.timingOffsetSamples=321;
            [again,receipt]=sixgr.phy.rx.applyControlFrequencyCorrection(input,carrier,cfg,selected);
            assert(isequaln(again,corrected)&&isequaln(receipt,e));
            cfg.phy.rx.cfoCorrectionEnabled=false;
            [same,disabled]=sixgr.phy.rx.applyControlFrequencyCorrection(input,carrier,cfg,selected);
            assert(isequal(same,input)&&~disabled.CFOCorrectionApplied);
            cfg.phy.rx.cfoCorrectionEnabled=true;
            checked=checked+1;
        end
        [silent,e]=sixgr.phy.rx.applyControlFrequencyCorrection(zeros(size(wave)),carrier,cfg,selected);
        assert(~e.CFOEstimateAvailable&&~e.CFOCorrectionApplied&&~any(silent(:)));
        % A partial actual capture must not invent unreceived CP pairs.
        cut=starts(4); % selected symbol3 not yet received
        [~,partial]=sixgr.phy.rx.applyControlFrequencyCorrection(wave(1:cut,:),carrier,cfg,selected);
        assert(partial.CFOObservation.NumSymbolsUsed==1);
    end
end
cfg.phy.impairments.cfoEstimationMethod='dmrs_two_symbol';
localError(@()sixgr.phy.rx.applyControlFrequencyCorrection(wave,carrier,cfg,selected), ...
    'sixgr:phy:rx:UnsupportedControlFrequencyMethod');
cfg.phy.impairments.cfoEstimationMethod='cyclic_prefix';
localError(@()sixgr.phy.rx.applyControlFrequencyCorrection(wave,carrier,cfg,[1 1]), ...
    'sixgr:phy:rx:CFOCPObservationSymbols');
fprintf('CONTROL_FREQUENCY_CORRECTION_PASS native_cases=%d no_decoder_or_RF_claim=1\n',checked);
ok=true;
end
function localError(f,id)
try, f(); catch e, assert(strcmp(e.identifier,id),'Expected %s got %s',id,e.identifier); return; end
error('TEST:MissingError','Expected %s',id);
end
