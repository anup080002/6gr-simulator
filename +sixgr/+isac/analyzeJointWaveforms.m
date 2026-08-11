function diagnostics = analyzeJointWaveforms(cfg,bundles)
%ANALYZEJOINTWAVEFORMS Measured spectrum/ACF/cross-profile diagnostics.

ids = string(fieldnames(bundles));
modeCfg=sixgr.util.structGet(cfg,"run.modes."+lower(string(cfg.run.activeMode)),struct());
paprSeeds=double(modeCfg.trialSeeds(:));
spectrumTables = cell(numel(ids),1);
acfTables = cell(numel(ids),1);
paprTables = cell(numel(ids),1);
summaryRows = cell(numel(ids),1);
for i = 1:numel(ids)
    bundle = bundles.(ids(i));
    x = bundle.SensingWaveform(:);
    fs = double(bundle.OFDMInfo.SampleRate);
    nFFT = 2^nextpow2(numel(x));
    spectrum = abs(fftshift(fft(x,nFFT))).^2;
    frequency = ((-nFFT/2):(nFFT/2-1)).'*fs/nFFT;
    pick = unique(round(linspace(1,nFFT,min(1024,nFFT))));
    spectrumTables{i} = table(repmat(ids(i),numel(pick),1),frequency(pick), ...
        spectrum(pick),10*log10(max(spectrum(pick),realmin)/max(spectrum)), ...
        'VariableNames',{'WaveformProfile','FrequencyHz','PowerLinear','PowerRelativeDb'});
    nACF=2^nextpow2(2*numel(x)-1);
    aperiodic=ifft(abs(fft(x,nACF)).^2);
    circular=ifft(abs(fft(x)).^2);
    nLag=min(512,numel(circular));
    aperiodicPower=abs(aperiodic(1:nLag)).^2;
    circularPower=abs(circular(1:nLag)).^2;
    acfTables{i} = table([repmat(ids(i),nLag,1);repmat(ids(i),nLag,1)], ...
        [repmat("aperiodic",nLag,1);repmat("circular",nLag,1)], ...
        [(0:nLag-1).';(0:nLag-1).'],[aperiodicPower;circularPower], ...
        [10*log10(max(aperiodicPower,realmin)/max(aperiodicPower)); ...
        10*log10(max(circularPower,realmin)/max(circularPower))], ...
        'VariableNames',{'WaveformProfile','ACFType','LagSamples','PowerLinear','PowerRelativeDb'});
    symbolPAPR=zeros(bundle.Carrier.SymbolsPerSlot*numel(paprSeeds),1);
    paprIndex=0;
    for seedIndex=1:numel(paprSeeds)
        paprBundle=sixgr.isac.buildJointWaveform(cfg,ids(i),paprSeeds(seedIndex));
        offset=0;
        for symbolIndex=1:paprBundle.Carrier.SymbolsPerSlot
            cp=double(paprBundle.CPLengths(symbolIndex));
            useful=paprBundle.Waveform(offset+cp+(1:paprBundle.OFDMInfo.Nfft));
            paprIndex=paprIndex+1;
            symbolPAPR(paprIndex)=10*log10(max(abs(useful).^2)/mean(abs(useful).^2));
            offset=offset+cp+double(paprBundle.OFDMInfo.Nfft);
        end
    end
    thresholds=(0:.25:ceil(max(symbolPAPR)+.25)).';
    paprTables{i}=table(repmat(ids(i),numel(thresholds),1),thresholds, ...
        arrayfun(@(v) mean(symbolPAPR>v),thresholds), ...
        repmat(numel(paprSeeds),numel(thresholds),1), ...
        repmat(numel(symbolPAPR),numel(thresholds),1), ...
        'VariableNames',{'WaveformProfile','PAPRThresholdDb','EmpiricalCCDF', ...
        'WaveformSeeds','OFDMSymbolSamples'});
    summaryRows{i} = table(ids(i),bundle.PAPRDb,numel(x), ...
        nnz(bundle.ConfiguredMask),string(bundle.WaveformSHA256), ...
        string(bundle.SensingWaveformSHA256), ...
        'VariableNames',{'WaveformProfile','PAPRDb','WaveformSamples', ...
        'ConfiguredSensingRE','WaveformSHA256','SensingWaveformSHA256'});
end
diagnostics.Spectrum = vertcat(spectrumTables{:});
diagnostics.Autocorrelation = vertcat(acfTables{:});
diagnostics.PAPRCCDF = vertcat(paprTables{:});
diagnostics.WaveformSummary = vertcat(summaryRows{:});

pairA = strings(0,1); pairB = strings(0,1); normalizedPeak = zeros(0,1);
for i = 1:numel(ids)
    for j = i+1:numel(ids)
        a = bundles.(ids(i)).SensingWaveform(:);
        b = bundles.(ids(j)).SensingWaveform(:);
        nFFT = 2^nextpow2(numel(a)+numel(b)-1);
        cross = ifft(fft(a,nFFT).*conj(fft(b,nFFT)));
        pairA(end+1,1) = ids(i); %#ok<AGROW>
        pairB(end+1,1) = ids(j); %#ok<AGROW>
        normalizedPeak(end+1,1) = max(abs(cross))/sqrt(sum(abs(a).^2)*sum(abs(b).^2)); %#ok<AGROW>
    end
end
diagnostics.CrossAmbiguity = table(pairA,pairB,normalizedPeak, ...
    'VariableNames',{'WaveformA','WaveformB','MaximumNormalizedCrossCorrelation'});

% W3 absolute-symbol state is exported separately so puncturing invariance is
% directly auditable without reconstructing it from plots.
w3 = bundles.W3;
nSymbols = numel(w3.CumulativeCPState);
configuredPerSymbol = sum(w3.ConfiguredMask,1).';
diagnostics.W3State = table((0:nSymbols-1).',w3.CPLengths(:), ...
    w3.CumulativeCPState(:),configuredPerSymbol, ...
    'VariableNames',{'AbsoluteSymbolIndex','CPLengthSamples', ...
    'CumulativeCPStateQ','ConfiguredSensingRE'});
end
