function rows=diagnosePDSCHReceiverReplay(capturePaths,outputCSV,cpWindows)
%DIAGNOSEPDSCHRECEIVERREPLAY Same-sample RCA, not receiver qualification.
% Windows are explicit exploratory inputs, never installed receiver policy.
% No injected CFO, channel truth or transmitted bits enters synchronization.
% Retained TB bits regenerate only the post-decode modulation reference.
arguments
    capturePaths (:,1) string
    outputCSV (1,1) string
    cpWindows (:,2) double
end
assert(all(cpWindows(:,1)>=0 & cpWindows(:,2)<=1 & ...
    cpWindows(:,1)<cpWindows(:,2)));
rows=table();
for file=capturePaths.'
    data=load(file,'ReceiverReplay'); c=data.ReceiverReplay;
    assert(c.Direction=="DL" && c.Contract=="exact_receiver_replay/v1");
    assert(c.WaveformSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(c.Waveform)));
    old=c.ReceiverResult;
    ref=sixgr.phy.dl.PDSCH_Tx(c.Config,'ExecutionProfile','phy_calibration', ...
        'Carrier',old.Carrier,'PDSCH',old.PDSCH, ...
        'TransportBlockBits',c.Context.ScoringOnlyTransmittedBits, ...
        'NumTxAnt',c.Config.channel.nTxAnt);
    [baselineMetrics,~]=sixgr.link.deriveModulationTrackingMetrics(ref,old,c.Config,"DL");
    fs=double(old.OFDMInfo.SampleRate); fft=double(old.OFDMInfo.Nfft);
    cp=double(old.OFDMInfo.OFDMSamplingResolution.CyclicPrefixLengthsPerSlot(:));
    aligned=sixgr.util.applyFractionalSampleDelay(c.Waveform,-old.AppliedTimingCorrection_samples);
    for variant=0:size(cpWindows,1)+1
        cfg=c.Config; wave=c.Waveform; applied=NaN; coherence=NaN;
        if variant==0
            label="baseline_replay";
        else
            cfg.phy.rx.cfoCorrectionEnabled=false;
            cfg.phy.impairments.cfoCorrectionEnabled=false;
            % This is a separately declared receiver-policy diagnostic.
            % Reinstall its resolved authority; never bypass the production
            % YAML/consumer mismatch guard or mutate the saved baseline.
            source=cfg.lls6g.resolvedConfig;
            source.impairments.cfo_correction_enable=false;
            cfg.lls6g.resolvedConfig=source;
            cfg.lls6g.impairments.cfo_correction_enable=false;
            cfg.meta.configHash=char(sixgr.lls6g.config.hashResolvedScenario(source));
            cfg=sixgr.config.installRuntimeOperatingAuthority(cfg,source);
            label="frequency_correction_disabled_diagnostic"; applied=0;
            if variant>1
                interval=cpWindows(variant-1,:); total=complex(0); aEnergy=0; bEnergy=0; pos=0;
                for n=cp.'
                    indices=pos+(floor(n*interval(1))+1:floor(n*interval(2)));
                    a=aligned(indices,:); b=aligned(indices+fft,:);
                    total=total+sum(conj(a).*b,'all');
                    aEnergy=aEnergy+sum(abs(a).^2,'all'); bEnergy=bEnergy+sum(abs(b).^2,'all');
                    pos=pos+n+fft;
                end
                applied=angle(total)*fs/(2*pi*fft);
                coherence=abs(total)/sqrt(aEnergy*bEnergy);
                wave=wave.*exp(-2i*pi*applied*(0:size(wave,1)-1)'/fs);
                label="exploratory_cp_window_"+interval(1)+"_"+interval(2);
            end
        end
        rx=sixgr.phy.dl.PDSCH_Rx(wave,cfg,c.ReceiverArguments{:});
        [metrics,~]=sixgr.link.deriveModulationTrackingMetrics(ref,rx,cfg,"DL");
        if variant==0
            assert(isequal(rx.TransportBlock,old.TransportBlock) && ...
                rx.TBCRCPass==old.TBCRCPass && abs(metrics.EVM_rms-baselineMetrics.EVM_rms)<1e-12, ...
                'Exact baseline replay must reproduce stored reception.');
            applied=rx.CFOCorrectionApplied_Hz;
        end
        row=table(file,c.Context.ConfiguredSNR_dB,c.Context.Slot,label, ...
            applied,coherence,rx.AppliedTimingCorrection_samples,logical(rx.TBCRCPass), ...
            metrics.EVM_rms,metrics.EVMSymbolCount,false, ...
            'VariableNames',{'CaptureMAT','ConfiguredSNR_dB','Slot','Variant', ...
            'AppliedCFO_Hz','CPCoherence','AppliedTiming_samples','CRCPass', ...
            'EVM_rms','EVMSymbolCount','ProductionReceiverQualified'});
        rows=[rows;row]; %#ok<AGROW>
        sixgr.util.csvWriteTable(outputCSV,rows,'PreserveSchema',true,'RoundTripNumericText',true);
    end
end
end
