function ok=testSharedPRACHReceiveOrigin(suffixes)
% Actual coded PRACH, analytic known delay. Not a shared fading-run claim.
% The receiver is told only its capture pre-guard and implementation delay;
% it still searches all 64 preambles and estimates the unknown radio delay.
if nargin<1, suffixes=["_tdd", ""]; end
suffixes=string(suffixes);
assert(~isempty(suffixes) && all(ismember(suffixes,["_tdd", ""])));
for suffix=suffixes
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
            trace=det.CorrelationTrace;
            assert(trace.DetectorBackend==det.DetectorBackend && ...
                trace.TraceStatus=="native_useful_repetition_auxiliary_correlation" && ...
                trace.DecisionTimingReference==det.DetectorTimingReference && ...
                trace.LagReference=="cyclic_delay_relative_to_native_PRACH_useful_symbol_origin" && ...
                isnan(trace.Threshold) && trace.DecisionThreshold==det.Threshold && ...
                trace.DetectorInputStartOffsetSamples==guard && ...
                trace.RawTimingOffsetSamples==det.RawTimingOffsetSamples && ...
                trace.PropagationTimingOffsetSamples==det.PropagationTimingOffsetSamples && ...
                trace.ImplementationFilterDelay_samples==filterDelay, ...
                'Actual trace timing metadata must retain the detector''s own capture-origin correction.');
            advance=sixgr.phy.ra.estimateTimingAdvanceFromPRACH(det,tx.SampleRate_Hz,ra.CarrierSCSkHz);
            step=sixgr.phy.ra.resolveRARTimingAdvance(0,ra.CarrierSCSkHz,tx.SampleRate_Hz);
            assert(advance.Valid && advance.TimingAdvanceCommand==round(radioDelay/step.StepSamples));
        end
    end
end
ok=true; fprintf('SHARED_PRACH_RECEIVE_ORIGIN_PASS: measured TA invariant to capture pre-guard; scenario suffixes=%s (empty suffix is FDD).\n',jsonencode(suffixes));
end
