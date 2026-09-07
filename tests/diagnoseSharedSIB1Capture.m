function diagnoseSharedSIB1Capture()
% Offline diagnostic of retained ACTUAL received IQ, never a primary trial.
setup6GRSimToolkit('Verbose',false);
d=load(fullfile('logs','coupled_stream_failure_capture.mat'));
p=d.p; cfg=p.ReceiverConfig; carrier=p.Tx.Carrier; fs=p.SampleRateHz;
first=p.Tx.SIB1WaveformStartSample; count=size(p.Tx.SIB1Waveform,1);
fprintf('CORESET start=%g duration=%g TRS symbols=%s\n', ...
    p.Tx.PDCCH.SearchSpace.StartSymbolWithinSlot,p.Tx.PDCCH.CORESET.Duration,mat2str(d.trs.StrictConfig.SymbolLocation));
for source=["actualTX","actualPre","actualPost"]
    samples=d.(source);
    [~,sync]=sixgr.phy.dl.SSB_Rx(samples,cfg,'SampleRate_Hz',fs,'CandidateSSBIndex',0);
    sym=sync.SelectedCandidateStartSymbol;
    expected=floor(sym/14)*1e-3*(15/sync.SCS_SSB_kHz)*fs + ...
        sum(sync.CyclicPrefixLengthsPerSlot(1:mod(sym,14))+sync.Nfft);
    residual=sync.TimingOffset-expected;
    fprintf('%s PSS offset=%g expected=%g residual=%g CFO=%g\n', ...
        source,sync.TimingOffset,expected,residual,sync.FreqOffset_Hz);
    for shift=unique([0 residual])
        x=samples(first+shift+(1:count),:);
        for correct=[false true]
            y=x;
            if correct, y=y.*exp(-1j*2*pi*sync.FreqOffset_Hz*(first+shift+(0:count-1).')/fs); end
            [rx,info]=sixgr.phy.dl.PDCCH_Rx(y,cfg,'Carrier',carrier,'PDCCH',p.Tx.PDCCH, ...
                'K',numel(p.Tx.DCI.Bits),'RNTI',65535,'PDCCHScramblingRNTI',0,'SampleRate_Hz',fs);
            fprintf('shift=%g CFOcorrect=%d decode=%d noise=%g\n',shift,correct,rx.Ok,rx.NoiseVar);
            if ~rx.Ok, disp(sixgr.util.structGet(info,'CandidateResults',table())); end
        end
    end
end
end
