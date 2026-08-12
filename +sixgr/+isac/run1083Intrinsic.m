function result=run1083Intrinsic(configPath,options)
%RUN1083INTRINSIC Execute WFig25-WFig28 intrinsic waveform evidence.
arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
[cfg,sourcePath]=sixgr.isac.loadJointConfig(configPath);
class=lower(string(cfg.validation.intrinsic.activeClass));
study=cfg.validation.intrinsic.(class);
if options.RunId=="", runId="isac_10_8_3_intrinsic_"+ ...
        string(datetime("now","Format","yyyyMMdd_HHmmss")); else, runId=options.RunId; end
if options.OutputRoot=="", root=fullfile(localRepoRoot(),"results"); else, root=options.OutputRoot; end
folder=string(fullfile(root,runId)); localLayout(folder);
profiles=["W0";"W1-A";"W1-B";"W2";"W3"];
waveforms=["W0";"W1";"W1";"W2";"W3"];
variants=["default";"per_occasion";"reset_aligned_interval";"default";"default"];

[papr,paprSummary]=localPAPR(cfg,study,profiles,waveforms,variants);
[spectrum,spectralSummary]=localSpectrum(cfg,profiles,waveforms,variants);
[ambiguity,ambiguitySummary]=localAmbiguity(cfg,study,profiles,waveforms,variants);
[autocorrelation]=localAutocorrelation(cfg,profiles,waveforms,variants);
[crossCorrelation,crossCorrelationSamples]=localCrossCorrelation(cfg,study);
rangeDoppler=localRangeDoppler(cfg);
writetable(papr,fullfile(folder,"raw","papr_samples.csv"));
writetable(paprSummary,fullfile(folder,"tables","papr_ccdf_numeric.csv"));
writetable(spectrum,fullfile(folder,"raw","waveform_spectrum.csv"));
writetable(spectralSummary,fullfile(folder,"tables","psd_aclr_oobe_numeric.csv"));
writetable(ambiguity,fullfile(folder,"raw","ambiguity_2d.csv"));
writetable(ambiguitySummary,fullfile(folder,"tables","ambiguity_metrics.csv"));
writetable(autocorrelation,fullfile(folder,"tables","autocorrelation_profiles.csv"));
writetable(crossCorrelation,fullfile(folder,"tables","cross_correlation_distribution.csv"));
writetable(crossCorrelationSamples,fullfile(folder,"raw","cross_correlation_samples.csv"));
writetable(rangeDoppler,fullfile(folder,"tables","range_doppler_maps_B1_C0.csv"));
save(fullfile(folder,"aggregate","intrinsic_data.mat"), ...
    "cfg","study","papr","paprSummary","spectrum","spectralSummary", ...
    "ambiguity","ambiguitySummary","autocorrelation", ...
    "crossCorrelation","crossCorrelationSamples", ...
    "rangeDoppler","-v7.3");
localFigure25(folder,cfg,rangeDoppler);
localFigure26(folder,cfg,spectrum,spectralSummary);
localFigure27(folder,cfg,ambiguity,ambiguitySummary);
localFigure28(folder,cfg,crossCorrelation);
localPAPRFigure(folder,cfg,papr,paprSummary);
localAutocorrelationFigure(folder,cfg,autocorrelation);
copyfile(sourcePath,fullfile(folder,"config_source.yaml")); save(fullfile(folder,"config_snapshot.mat"),"cfg");
result=struct("RunFolder",folder,"Class",class,"PAPR",paprSummary, ...
    "Spectrum",spectralSummary,"Ambiguity",ambiguitySummary, ...
    "Autocorrelation",autocorrelation, ...
    "CrossCorrelation",crossCorrelation,"CrossCorrelationSamples",crossCorrelationSamples, ...
    "RangeDoppler",rangeDoppler, ...
    "PublicationQualified",class=="publication" && ...
    all(paprSummary.OFDMSymbolSamples>=double(study.paprOFDMSymbolsPerProfile))&& ...
    all(crossCorrelation.PairCount>=double(study.crossCorrelationPairsPerClass))&& ...
    all(ambiguitySummary.DelayBins>=double(study.ambiguityDelayBins))&& ...
    all(ambiguitySummary.DopplerBins>=double(study.ambiguityDopplerBins)));
fprintf("10.8.3 intrinsic %s: PAPR symbols/profile=%d, cross pairs/class=%d\n", ...
    class,min(paprSummary.OFDMSymbolSamples),double(study.crossCorrelationPairsPerClass));
end

function out=localAutocorrelation(cfg,profiles,waveforms,variants)
parts=cell(numel(profiles)*2,1); index=0;
for p=1:numel(profiles)
    b=sixgr.isac.buildJointWaveform(cfg,waveforms(p),double(cfg.run.masterSeed)+p, ...
        zeros(0,1),14,variants(p));
    x=b.SensingGrid(b.ConfiguredMask); x=x(:); n=numel(x);
    fftLength=2^nextpow2(2*n-1); raw=ifft(abs(fft(x,fftLength)).^2);
    aperiodic=[raw(fftLength-n+2:fftLength);raw(1:n)];
    aperiodic=abs(aperiodic)/max(abs(aperiodic)); lagA=(-n+1:n-1).';
    circular=abs(ifft(abs(fft(x)).^2)); circular=circular/max(circular);
    lagC=(0:n-1).';
    index=index+1; parts{index}=table(repmat(profiles(p),numel(lagA),1), ...
        repmat("aperiodic",numel(lagA),1),lagA,aperiodic, ...
        'VariableNames',{'WaveformProfile','CorrelationType','LagSamples','MagnitudeNormalized'});
    index=index+1; parts{index}=table(repmat(profiles(p),numel(lagC),1), ...
        repmat("circular",numel(lagC),1),lagC,circular, ...
        'VariableNames',{'WaveformProfile','CorrelationType','LagSamples','MagnitudeNormalized'});
end
out=vertcat(parts{1:index});
end

function [samples,summary]=localPAPR(cfg,study,profiles,waveforms,variants)
nRequested=double(study.paprOFDMSymbolsPerProfile); parts=cell(numel(profiles),1);
summaries=cell(numel(profiles),1); symbolsPerWaveform=14;
for p=1:numel(profiles)
    values=zeros(nRequested,1); index=0; seed=double(cfg.run.masterSeed)+p*10000;
    while index<nRequested
        bundle=sixgr.isac.buildJointWaveform(cfg,waveforms(p),seed,zeros(0,1),14,variants(p));
        offset=0;
        for symbol=1:symbolsPerWaveform
            cp=double(bundle.CPLengths(symbol));
            useful=bundle.Waveform(offset+cp+(1:bundle.OFDMInfo.Nfft));
            index=index+1; values(index)=10*log10(max(abs(useful).^2)/mean(abs(useful).^2));
            offset=offset+cp+double(bundle.OFDMInfo.Nfft);
            if index==nRequested, break; end
        end
        seed=seed+1;
    end
    sorted=sort(values,"ascend");
    at1=localUpperQuantile(sorted,.99); at01=localUpperQuantile(sorted,.999);
    parts{p}=table(repmat(profiles(p),nRequested,1),(1:nRequested).',values, ...
        'VariableNames',{'WaveformProfile','SampleIndex','PAPRDb'});
    summaries{p}=table(profiles(p),nRequested,at1,at01,mean(values),std(values), ...
        string(study.evidenceClass), ...
        'VariableNames',{'WaveformProfile','OFDMSymbolSamples','PAPRAtCCDF1e2Db', ...
        'PAPRAtCCDF1e3Db','MeanPAPRDb','StdPAPRDb','EvidenceClass'});
end
samples=vertcat(parts{:}); summary=vertcat(summaries{:});
end

function value=localUpperQuantile(sorted,probability)
index=max(1,min(numel(sorted),ceil(probability*numel(sorted)))); value=sorted(index);
end

function [rows,summary]=localSpectrum(cfg,profiles,waveforms,variants)
nFFT=double(cfg.validation.intrinsic.spectralOversampledNfft); parts=cell(numel(profiles),1);
summaries=cell(numel(profiles),1); bw=double(cfg.carrier.profiles.(cfg.carrier.activeProfile).channelBandwidthHz);
lower=double(cfg.validation.intrinsic.adjacentChannelIntegration.lowerBandwidthOffsets(:))*bw;
upper=double(cfg.validation.intrinsic.adjacentChannelIntegration.upperBandwidthOffsets(:))*bw;
for p=1:numel(profiles)
    bundle=sixgr.isac.buildJointWaveform(cfg,waveforms(p),double(cfg.run.masterSeed)+p, ...
        zeros(0,1),14,variants(p),nFFT);
    x=bundle.Waveform(:); analysisNFFT=2^nextpow2(numel(x));
    power=abs(fftshift(fft(x,analysisNFFT))).^2/analysisNFFT;
    frequency=((-analysisNFFT/2):(analysisNFFT/2-1)).'*bundle.OFDMInfo.SampleRate/analysisNFFT;
    in=frequency>=-bw/2&frequency<=bw/2;
    lo=frequency>=lower(1)&frequency<lower(2);
    hi=frequency>upper(1)&frequency<=upper(2);
    pIn=sum(power(in)); pLo=sum(power(lo)); pHi=sum(power(hi)); pTotal=sum(power);
    aclrLo=10*log10(pIn/max(pLo,realmin)); aclrHi=10*log10(pIn/max(pHi,realmin));
    pick=unique(round(linspace(1,analysisNFFT,min(4096,analysisNFFT))));
    parts{p}=table(repmat(profiles(p),numel(pick),1),frequency(pick),power(pick), ...
        10*log10(max(power(pick),realmin)/max(power)), ...
        'VariableNames',{'WaveformProfile','FrequencyHz','PowerLinear','PowerRelativeDb'});
    summaries{p}=table(profiles(p),pIn,pLo,pHi,aclrLo,aclrHi, ...
        (pTotal-pIn)/pTotal,bundle.OFDMInfo.SampleRate,nFFT, ...
        'VariableNames',{'WaveformProfile','InBandPower','LowerAdjacentPower', ...
        'UpperAdjacentPower','ACLRLowerDb','ACLRUpperDb','OOBEPowerRatio', ...
        'SampleRateHz','OFDMIFFTSize'});
end
rows=vertcat(parts{:}); summary=vertcat(summaries{:});
end

function [rows,summary]=localAmbiguity(cfg,study,profiles,waveforms,variants)
nDelay=double(study.ambiguityDelayBins); nDoppler=double(study.ambiguityDopplerBins);
parts=cell(numel(profiles),1); summaries=cell(numel(profiles),1);
for p=1:numel(profiles)
    b=sixgr.isac.buildJointWaveform(cfg,waveforms(p),double(cfg.run.masterSeed)+p, ...
        zeros(0,1),14,variants(p));
    symbols=find(any(b.ConfiguredMask,1)); nSC=size(b.Grid,1);
    physicalAll=(-floor(nSC/2):ceil(nSC/2)-1).'+12*double(b.Carrier.NStartGrid);
    delay=linspace(-double(cfg.validation.intrinsic.ambiguity.maximumDelaySamples), ...
        double(cfg.validation.intrinsic.ambiguity.maximumDelaySamples),nDelay).';
    starts=[0;cumsum(double(b.CPLengths(:))+double(b.OFDMInfo.Nfft))];
    times=(starts(symbols)+double(b.CPLengths(symbols)))/double(b.OFDMInfo.SampleRate);
    maxDoppler=double(cfg.validation.intrinsic.ambiguity.maximumNormalizedDoppler)* ...
        double(b.Carrier.SubcarrierSpacing)*1e3;
    doppler=linspace(-maxDoppler,maxDoppler,nDoppler).';
    response=zeros(nDelay,nDoppler);
    for s=1:numel(symbols)
        symbol=symbols(s); active=b.ConfiguredMask(:,symbol); k=physicalAll(active);
        energy=abs(b.SensingGrid(active,symbol)).^2;
        delayResponse=transpose(energy.'*exp(1i*2*pi*(k/b.OFDMInfo.Nfft)*delay.'));
        response=response+delayResponse*exp(1i*2*pi*times(s)*doppler.');
    end
    power=abs(response).^2; power=power/max(power,[],'all');
    [delayGrid,dopplerGrid]=ndgrid(delay,doppler);
    parts{p}=table(repmat(profiles(p),numel(power),1),delayGrid(:),dopplerGrid(:), ...
        power(:),10*log10(max(power(:),realmin)), ...
        'VariableNames',{'WaveformProfile','DelaySamples','DopplerHz','PowerNormalized','PowerDb'});
    [~,peakLinear]=max(power,[],'all'); [peakDelay,peakDoppler]=ind2sub(size(power),peakLinear);
    exclusion=false(size(power)); hd=double(cfg.validation.intrinsic.ambiguity.mainlobeDelayExclusionBins);
    hv=double(cfg.validation.intrinsic.ambiguity.mainlobeDopplerExclusionBins);
    exclusion(max(1,peakDelay-hd):min(nDelay,peakDelay+hd), ...
        max(1,peakDoppler-hv):min(nDoppler,peakDoppler+hv))=true;
    sidelobe=power(~exclusion); pslr=10*log10(max(sidelobe));
    islr=10*log10(sum(sidelobe)/sum(power(exclusion)));
    delayCut=power(:,peakDoppler); dopplerCut=power(peakDelay,:).';
    delayWidth=localMainlobeWidth(delay,delayCut,peakDelay);
    dopplerWidth=localMainlobeWidth(doppler,dopplerCut,peakDoppler);
    sidelobeMap=power; sidelobeMap(exclusion)=0;
    [~,ghostLinear]=max(sidelobeMap,[],'all');
    [ghostDelayIndex,ghostDopplerIndex]=ind2sub(size(power),ghostLinear);
    summaries{p}=table(profiles(p),pslr,islr,delay(peakDelay),doppler(peakDoppler), ...
        delayWidth,dopplerWidth,delay(ghostDelayIndex),doppler(ghostDopplerIndex), ...
        nDelay,nDoppler,string(study.evidenceClass), ...
        'VariableNames',{'WaveformProfile','PSLRDb','ISLRDb','StrongestPeakDelaySamples', ...
        'StrongestPeakDopplerHz','MainlobeDelayWidthSamples','MainlobeDopplerWidthHz', ...
        'StrongestGhostDelaySamples','StrongestGhostDopplerHz', ...
        'DelayBins','DopplerBins','EvidenceClass'});
end
rows=vertcat(parts{:}); summary=vertcat(summaries{:});
end

function width=localMainlobeWidth(axisValues,cut,peakIndex)
threshold=max(cut)/2; left=peakIndex; right=peakIndex;
while left>1&&cut(left-1)>=threshold, left=left-1; end
while right<numel(cut)&&cut(right+1)>=threshold, right=right+1; end
width=abs(axisValues(right)-axisValues(left));
end

function [out,samples]=localCrossCorrelation(cfg,study)
classes=["W0_W0";"W1A_W1A";"W1B_W1B";"W2_W2";"W3_W3";"W2_W3"];
n=double(study.crossCorrelationPairsPerClass); rows=cell(numel(classes),1);
sampleRows=cell(numel(classes)*n,1); sampleIndex=0;
for c=1:numel(classes)
    values=zeros(n,1);
    for i=1:n
        seedA=double(cfg.run.masterSeed)+c*100000+i*2;
        seedB=seedA+1;
        [aId,aVariant,bId,bVariant]=localPair(classes(c));
        cfgA=cfg; cfgB=cfg;
        profileName=char(string(cfg.carrier.activeProfile));
        cellA=mod(double(cfg.carrier.profiles.(profileName).nCellID)+2*i-1,1008);
        cellB=mod(double(cfg.carrier.profiles.(profileName).nCellID)+2*i,1008);
        cfgA.carrier.profiles.(profileName).nCellID=cellA;
        cfgB.carrier.profiles.(profileName).nCellID=cellB;
        resetA=2+mod(i-1,2); resetB=2+mod(i,2);
        cfgA.waveform.w1ResetAlignedIntervalOccasions=resetA;
        cfgB.waveform.w1ResetAlignedIntervalOccasions=resetB;
        a=sixgr.isac.buildJointWaveform(cfgA,aId,seedA,zeros(0,1),14,aVariant);
        b=sixgr.isac.buildJointWaveform(cfgB,bId,seedB,zeros(0,1),14,bVariant);
        x=a.SensingGrid(a.ConfiguredMask); y=b.SensingGrid(b.ConfiguredMask);
        values(i)=abs(x'*y)/(norm(x)*norm(y));
        sampleIndex=sampleIndex+1;
        sampleRows{sampleIndex}=table(classes(c),i,aId,bId,seedA,seedB,cellA,cellB, ...
            resetA,resetB,values(i),string(study.evidenceClass), ...
            'VariableNames',{'PairClass','PairIndex','WaveformA','WaveformB','SequenceSeedA', ...
            'SequenceSeedB','CellIDA','CellIDB','ResetIntervalOccasionsA', ...
            'ResetIntervalOccasionsB','CrossCorrelation','EvidenceClass'});
    end
    rows{c}=table(classes(c),n,mean(values),median(values),prctile(values,90), ...
        prctile(values,99),max(values),string(study.evidenceClass), ...
        'VariableNames',{'PairClass','PairCount','Mean','Median','P90','P99','Maximum','EvidenceClass'});
end
out=vertcat(rows{:});
samples=vertcat(sampleRows{1:sampleIndex});
end

function [a,av,b,bv]=localPair(class)
switch class
    case "W0_W0", a="W0"; av="default"; b="W0"; bv="default";
    case "W1A_W1A", a="W1"; av="per_occasion"; b="W1"; bv="per_occasion";
    case "W1B_W1B", a="W1"; av="reset_aligned_interval"; b="W1"; bv="reset_aligned_interval";
    case "W2_W2", a="W2"; av="default"; b="W2"; bv="default";
    case "W3_W3", a="W3"; av="default"; b="W3"; bv="default";
    otherwise, a="W2"; av="default"; b="W3"; bv="default";
end
end

function out=localRangeDoppler(cfg)
delays=[.5;1;1.5]; labels=["below_cp";"at_cp";"above_cp"];
profiles=["W0";"W3"]; receivers=["B1";"C0"]; rows=cell(6,1); index=0;
for d=1:numel(delays)
    for p=1:2
        b=sixgr.isac.buildJointWaveform(cfg,profiles(p),double(cfg.run.masterSeed),zeros(0,1),14,"default");
        t=localTrial("map_"+receivers(p)+"_"+labels(d),double(cfg.run.masterSeed)+d,receivers(p));
        t.DelayOverCP=delays(d); t.ExactDelaySamples=delays(d)*min(b.CPLengths)+.33;
        t.ExactDopplerHz=.031*b.Carrier.SubcarrierSpacing*1e3;
        cp=min(double(b.CPLengths));
        t.AdditionalDelaySamples=[t.ExactDelaySamples+.35*cp;t.ExactDelaySamples+.15*cp];
        t.AdditionalDopplerHz=[-.6*t.ExactDopplerHz;0];
        t.AdditionalPathGainDb=double(cfg.channel.targetPathGainDb)+[-6;-12];
        [~,raw]=sixgr.isac.runJointWaveformTrial(cfg,b,t);
        index=index+1; rows{index}=sixgr.isac.buildRangeDopplerEvidence(cfg,b,raw,labels(d));
        rows{index}.ScenarioClass=repmat("two_target_clutter",height(rows{index}),1);
        rows{index}.AdditionalPathCount=repmat(2,height(rows{index}),1);
    end
end
out=vertcat(rows{:});
end

function trial=localTrial(id,seed,receiver)
trial=struct("TrialId",char(id),"Seed",double(seed),"WaveformSeed",double(seed), ...
    "DelayOverCP",1,"NormalizedDoppler",.01,"SensingMode","trp_monostatic", ...
    "CollisionRatioPercent",0,"CollisionResponse","share_reuse", ...
    "TDDPattern","all_dl","TargetPresent",true,"UseGeometryDelay",false, ...
    "PortProfile","single_port","ReceiverProfile",char(receiver),"CoherentSymbols",14, ...
    "CollisionMaskProfile","random_isolated","SequenceVariant","default");
end

function localFigure25(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
classes=unique(t.DelayClass,"stable"); receivers=["B1";"C0"];
globalLimits=[min(t.PowerRelativeDb) 0]; globalLimits(1)=max(globalLimits(1),-50);
layout=tiledlayout(fig,numel(classes),2,"TileSpacing","compact","Padding","compact");
for d=1:numel(classes), for r=1:2
    rows=t.DelayClass==classes(d)&t.ReceiverProfile==receivers(r); slice=t(rows,:);
    range=unique(slice.RangeM); doppler=unique(slice.DopplerHz);
    power=reshape(slice.PowerRelativeDb,numel(range),numel(doppler));
    nexttile(layout); imagesc(doppler,range,power); axis xy; clim(globalLimits);
    xlabel("Doppler (Hz)"); ylabel("Range (m)"); title(classes(d)+" "+receivers(r)); colorbar;
end, end
title(layout,"Paired W0/B1 and W3/C0 range-Doppler maps — common color scale");
localExport(folder,cfg,fig,"WFig25_range_doppler_maps_B1_C0",t);
end

function localFigure26(folder,cfg,spectrum,summary)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
nexttile(layout); hold on; for profile=unique(spectrum.WaveformProfile,"stable").'
    rows=spectrum.WaveformProfile==profile; plot(spectrum.FrequencyHz(rows)/1e6, ...
        spectrum.PowerRelativeDb(rows),"DisplayName",profile); end
xlabel("Frequency (MHz)"); ylabel("Relative PSD (dB)"); ylim([-100 5]); legend; grid on;
nexttile(layout); bar(categorical(summary.WaveformProfile), ...
    [summary.ACLRLowerDb summary.ACLRUpperDb]); ylabel("ACLR (dB)"); legend("lower","upper"); grid on;
title(layout,"PSD plus numeric lower/upper adjacent-channel integration");
localExport(folder,cfg,fig,"WFig26_psd_aclr_oobe_numeric",struct("Spectrum",spectrum,"Summary",summary));
end

function localFigure27(folder,cfg,t,summary)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
profiles=unique(t.WaveformProfile,"stable"); layout=tiledlayout(fig,3,numel(profiles), ...
    "TileSpacing","compact","Padding","compact");
for p=1:numel(profiles)
    rows=t.WaveformProfile==profiles(p); slice=t(rows,:); delay=unique(slice.DelaySamples); doppler=unique(slice.DopplerHz);
    z=reshape(slice.PowerDb,numel(delay),numel(doppler));
    nexttile(layout); imagesc(doppler,delay,z); axis xy; clim([-50 0]); title(profiles(p));
    xlabel("Doppler (Hz)"); ylabel("Delay (samples)");
    [~,delayZero]=min(abs(delay)); [~,dopplerZero]=min(abs(doppler));
    nexttile(layout,numel(profiles)+p); plot(delay,z(:,dopplerZero)); xlabel("Delay (samples)");
    ylabel("Zero-Doppler cut (dB)"); ylim([-60 2]); grid on;
    nexttile(layout,2*numel(profiles)+p); plot(doppler,z(delayZero,:)); xlabel("Doppler (Hz)");
    ylabel("Zero-delay cut (dB)"); ylim([-60 2]); grid on;
end
title(layout,"Two-dimensional ambiguity maps and delay cuts");
localExport(folder,cfg,fig,"WFig27_2D_ambiguity_profiles",struct("Map",t,"Summary",summary));
end

function localFigure28(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
bar(categorical(t.PairClass),[t.Mean t.Median t.P90 t.P99 t.Maximum]);
ylabel("Normalized cross-correlation"); legend("mean","median","p90","p99","maximum");
xtickangle(35); grid on; title("Cross-cell and cross-profile sequence distribution");
localExport(folder,cfg,fig,"WFig28_cross_correlation_distribution",t);
end

function localPAPRFigure(folder,cfg,samples,summary)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
nexttile(layout); hold on;
for profile=unique(samples.WaveformProfile,"stable").'
    values=sort(samples.PAPRDb(samples.WaveformProfile==profile),"ascend");
    ccdf=(numel(values):-1:1).'/numel(values);
    semilogy(values,ccdf,"DisplayName",profile);
end
xlabel("PAPR (dB)"); ylabel("CCDF"); ylim([1e-4 1]); legend; grid on;
nexttile(layout); bar(categorical(summary.WaveformProfile), ...
    [summary.PAPRAtCCDF1e2Db summary.PAPRAtCCDF1e3Db]);
ylabel("PAPR (dB)"); legend("CCDF 10^{-2}","CCDF 10^{-3}"); grid on;
title(layout,"PAPR empirical CCDF and configured-tail quantiles");
localExport(folder,cfg,fig,"Supplemental_PAPR_CCDF", ...
    struct("Samples",samples,"Summary",summary));
end

function localAutocorrelationFigure(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,2,"TileSpacing","compact","Padding","compact");
types=["aperiodic","circular"];
for typeIndex=1:2
    nexttile(layout); hold on;
    for profile=unique(t.WaveformProfile,"stable").'
        rows=t.CorrelationType==types(typeIndex)&t.WaveformProfile==profile;
        plot(t.LagSamples(rows),20*log10(max(t.MagnitudeNormalized(rows),realmin)), ...
            "DisplayName",profile);
    end
    xlabel("Lag"); ylabel("Magnitude (dB)"); ylim([-80 2]);
    title(types(typeIndex)); legend; grid on;
end
title(layout,"Aperiodic and circular sensing-sequence autocorrelation");
localExport(folder,cfg,fig,"Supplemental_autocorrelation_profiles",t);
end

function fig=localFigure(cfg)
pixels=double(cfg.output.imageSizePixels(:).'); dpi=double(cfg.output.imageResolutionDPI);
fig=figure("Visible","off","Color","white","Units","inches", ...
    "Position",[1 1 pixels(1)/dpi pixels(2)/dpi]);
end

function localExport(folder,cfg,fig,stem,data)
localPublicationStyle(fig);
save(fullfile(folder,"figures",stem+".mat"),"data"); savefig(fig,fullfile(folder,"figures",stem+".fig"));
if istable(data), writetable(data,fullfile(folder,"figures",stem+".csv"));
else
    names=string(fieldnames(data)); paths=strings(numel(names),1); hashes=strings(numel(names),1);
    for i=1:numel(names)
        value=data.(names(i)); path=fullfile(folder,"figures",stem+"_"+names(i)+".csv");
        writetable(value,path); paths(i)=path; hashes(i)=localHash(path);
    end
    writetable(table(names,paths,hashes,'VariableNames',{'Dataset','CSVPath','SHA256'}), ...
        fullfile(folder,"figures",stem+".csv"));
end
exportgraphics(fig,fullfile(folder,"figures",stem+".png"),"Resolution",double(cfg.output.imageResolutionDPI));
exportgraphics(fig,fullfile(folder,"figures",stem+".pdf"),"ContentType","vector");
end

function localPublicationStyle(fig)
axesHandles=findall(fig,"Type","axes");
for ax=reshape(axesHandles,1,[])
    set(ax,"Color","white","XColor",[.12 .12 .12],"YColor",[.12 .12 .12], ...
        "GridColor",[.68 .68 .68],"MinorGridColor",[.82 .82 .82], ...
        "GridAlpha",.35,"FontName","Arial","FontSize",9);
end
textHandles=findall(fig,"Type","text");
for h=reshape(textHandles,1,[]), set(h,"Color",[.08 .08 .08]); end
layoutHandles=findall(fig,"Type","tiledlayout");
for h=reshape(layoutHandles,1,[])
    h.Title.Color=[.08 .08 .08]; h.Title.FontWeight="bold";
end
legendHandles=findall(fig,"Type","legend");
for h=reshape(legendHandles,1,[])
    set(h,"Color","white","TextColor",[.08 .08 .08],"EdgeColor",[.55 .55 .55]);
end
end

function hash=localHash(path)
fid=fopen(path,"rb"); c=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function localLayout(folder)
for name=["raw","aggregate","tables","figures"]
    p=fullfile(folder,name); if exist(p,"dir")~=7, mkdir(p); end
end
end

function root=localRepoRoot()
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
