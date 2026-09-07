function ok=testSharedPRACHReceiveOrigin()
% Actual coded PRACH, analytic known delay. Not a shared fading-run claim.
% The receiver is told only its capture pre-guard and implementation delay;
% it still searches all 64 preambles and estimates the unknown radio delay.
for suffix=["_tdd", ""]
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
        'lls_causal_access_to_data_wiring'+suffix+'.yaml'));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    ra=sixgr.mac.ra.RAConfig(cfg,'RuntimeSlot',15);
    [tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
    for guard=[0 16 77]
        for radioDelay=[0 4]
            filterDelay=7;
            x=[zeros(guard+filterDelay+radioDelay,size(tx.Waveform,2),'like',tx.Waveform); tx.Waveform];
            receiver=cfg;
            receiver.lls6g.receiverSync.ReceivedWaveformTimingPlane='untrimmed_shared_physical_receive_stream';
            receiver.lls6g.receiverSync.ChannelFilterDelay_samples=filterDelay;
            receiver.lls6g.receiverSync.ULObservationSearchGuard_samples=guard;
            det=sixgr.phy.ra.detectMsg1PRACH(x,receiver,ra,occasion);
            assert(det.Detected && det.DetectedPreambleIndex==ra.PreambleIndex);
            % nrPRACHDetect can return fractional correlation-peak offsets.
            assert(abs(det.PropagationTimingOffsetSamples-radioDelay)<1 && ...
                abs(det.RawTimingOffsetSamples-(guard+filterDelay+radioDelay))<1);
            assert(det.DetectorInputStartOffsetSamples==guard);
            advance=sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det,tx.SampleRate_Hz,ra.CarrierSCSkHz);
            step=sixgr.phy.ra.resolveRARTimingAdvance(0,ra.CarrierSCSkHz,tx.SampleRate_Hz);
            assert(advance.Valid && advance.TimingAdvanceCommand==round(radioDelay/step.StepSamples));
        end
    end
end
ok=true; disp('SHARED_PRACH_RECEIVE_ORIGIN_PASS: identity and measured TA invariant to known capture pre-guard, TDD/FDD.');
end
