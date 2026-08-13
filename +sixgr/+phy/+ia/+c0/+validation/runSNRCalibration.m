function result=runSNRCalibration(bundle,cfg)
%RUNSNRCALIBRATION Verify the active-RE SNR convention across dimensions.
requested=double(cfg.validation.snr_calibration_requested_db(:));
repetitions=double(cfg.validation.snr_calibration_repetitions);
rxCounts=[1 double(cfg.mimo.num_rx_antennas)]; rxCounts=unique(rxCounts);
profiles=["20RB_full_map" "12RB_active_subset"];
rows=cell(numel(requested)*numel(rxCounts)*numel(profiles),1); n=0;
for p=1:numel(profiles)
    probe=bundle;
    if profiles(p)=="12RB_active_subset"
        [subcarrier,~]=ind2sub(size(bundle.SlotGrid),bundle.ActiveIndices);
        keep=subcarrier<=12*12;
        probe.ActiveIndices=bundle.ActiveIndices(keep);
    end
    for rx=rxCounts
        clean=repmat(bundle.Waveform,1,rx);
        signalPower=sixgr.phy.ia.c0.channel.measureActiveREPower(clean,probe,0);
        for s=1:numel(requested)
            noisePower=0;
            for r=1:repetitions
                [~,noise]=sixgr.phy.ia.c0.channel.addNoiseForTargetSNR( ...
                    clean,probe,signalPower,requested(s),970000+10000*p+ ...
                    1000*rx+100*s+r);
                noisePower=noisePower+sixgr.phy.ia.c0.channel.measureActiveREPower( ...
                    noise,probe,0);
            end
            noisePower=noisePower/repetitions;
            measured=10*log10(signalPower/noisePower);
            n=n+1;
            rows{n}=table(profiles(p),rx,requested(s),measured, ...
                measured-requested(s),repetitions, ...
                abs(measured-requested(s))<=double(cfg.validation.snr_calibration_tolerance_db), ...
                'VariableNames',{'ActiveREProfile','ReceiveAntennas', ...
                'RequestedSNRDB','MeasuredSNRDB','ErrorDB','Repetitions','Pass'});
        end
    end
end
result=vertcat(rows{1:n});
end
