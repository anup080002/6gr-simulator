function ok=testSharedTRSReceiverTimingScoring()
% Same shared-stream reception, with an independently reconciled RX clock.
% This bounded TRS regression is not an access or full H4 qualification.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
% TX delay is already in the executed desired-link reference. Only the
% subsequent RX delay belongs in the scoring-clock reconciliation. Include
% a TX-only case and a mixed case to reject the tempting TX+RX replay sum.
delays=[0 0; 0 1; 0 7; 3 0; 3 1];
records=zeros(size(delays,1),5);
for caseIndex=1:size(delays,1)
    cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
    % Isolate timing in the existing physical RF stream, not by replacing
    % the practical timing estimator or supplying an injected estimate.
    cfg.rf.tx.timingOffsetSamples=delays(caseIndex,1);
    cfg.rf.rx.timingOffsetSamples=delays(caseIndex,2);
    cfg.rf.tx.cfo_Hz=0; cfg.rf.rx.cfo_Hz=0;
    cfg.rf.tx.phaseNoise.enable=false; cfg.rf.rx.phaseNoise.enable=false;
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1, ...
        'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),9);
    state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
    [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
    prepared=sixgr.link.prepareTRSTransmission(dl,30,'RuntimeSlot',8);
    owner.queueDownlink("TRS",1,prepared,struct('Config',dl,'Slot',8));
    seen=false;
    for slot=1:9
        state.CurrentSlot=slot;
        current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
        [state,items]=owner.advanceSlot(state,current);
        for item=items
            if item.Kind~="TRS", continue; end
            assert(~seen); seen=true;
            p=item.Context.Prepared;
            [~,~,~,replay,received]=sixgr.truth.sharedObservationEvidence(item.Planes);
            replay.PowerContext=p.PowerContext;
            [reference,scoringSource,captures]=sixgr.truth.sharedLinkScoringObservation( ...
                item.Planes,p,item.Context.DesiredReferencePlane);
            assert(isempty(captures),'Do not rerun the fading model for scoring.');
            % Read the actual RX endpoint execution, not the YAML value or
            % the combined TX+RX injected-delay diagnostic.
            executedDelays=zeros(numel(replay.ReceiveStreamExecutionSegments),1);
            executedTXDelays=executedDelays;
            for segmentIndex=1:numel(executedDelays)
                segment=replay.ReceiveStreamExecutionSegments{segmentIndex};
                endpoints=segment.Execution.RX;
                endpoint=endpoints(string({endpoints.ID})==string(replay.ReceiverID));
                assert(isscalar(endpoint));
                executedDelays(segmentIndex)=endpoint.Replay.InjectedTimingOffset_samples;
                transmitters=segment.Execution.TX;
                transmitter=transmitters(string({transmitters.ID})==string(replay.TransmitterID));
                assert(isscalar(transmitter));
                executedTXDelays(segmentIndex)=transmitter.Replay.InjectedTimingOffset_samples;
            end
            assert(all(executedDelays==delays(caseIndex,2)) && ...
                all(executedTXDelays==delays(caseIndex,1)), ...
                'The isolated delay must actually execute on every observed RX segment.');
            assert(replay.InjectedTimingOffset_samples==sum(delays(caseIndex,:)), ...
                'Retain the combined injection diagnostic without using it as the RX clock.');
            delay=executedDelays(1);
            wave=reference.readComplete();
            [retained,clockEvidence]=sixgr.truth.sharedReceiverClockScoringWindow( ...
                reference,scoringSource,replay,reference.StartSample+delay, ...
                size(wave,1)-delay);
            assert(isequal(retained,wave(1:end-delay,:)) && ...
                clockEvidence.RecordedReceiverTimingOffset_samples==delay && ...
                ~clockEvidence.TXTimingReapplied, ...
                'The generic clock bridge must select exact retained samples from actual endpoint execution.');
            % Only TRS was queued. Its first useful symbol occurs after the
            % leading guard, so this reference shift needs no unobserved
            % preceding samples. Never generalize zero-padding to data.
            assert(all(wave(1:max(1,delay),:)==0,'all'));
            aligned=localObservation(reference, ...
                sixgr.util.applyFractionalSampleDelay(wave,delay));
            ch=owner.directionalChannelState(1,"DL");
            clockBefore=owner.Events.NextSampleIndex;
            actual=sixgr.link.completeTRSReception(p,received,replay,ch, ...
                'DesiredReferenceObservation',reference);
            canonical=struct('Prepared',p,'Observation',received, ...
                'Replay',replay,'ChannelState',ch, ...
                'DesiredReferenceObservation',aligned, ...
                'RecordedReceiverTimingOffset_samples',delay);
            expected=sixgr.link.runTRSTracking(p.ReceiverConfig,'ReceivedContext',canonical);
            assert(~actual.Crash && ~expected.Crash && ...
                actual.NMSEScoringAvailable && expected.NMSEScoringAvailable);
            assert(isequaln(actual.DetectionTable,expected.DetectionTable) && ...
                actual.EstimatedTimingOffset_samples==expected.EstimatedTimingOffset_samples && ...
                actual.EstimatedCFO_Hz==expected.EstimatedCFO_Hz, ...
                'Independent scoring must not alter practical receiver decisions.');
            % A wrong reference gain must remain an error, with identical
            % practical detection. No fitted amplitude/phase normalization.
            canonical.DesiredReferenceObservation=localObservation(aligned,2*aligned.readComplete());
            badGain=sixgr.link.runTRSTracking(p.ReceiverConfig,'ReceivedContext',canonical);
            assert(~badGain.Crash && badGain.NMSE_dB>p.StrictConfig.ChannelNMSEThresholddB && ...
                isequaln(badGain.DetectionTable,expected.DetectionTable));
            assert(owner.Events.NextSampleIndex==clockBefore, ...
                'Post-reception scoring must not advance or repeat physical execution.');
            records(caseIndex,:)=[executedTXDelays(1) delay actual.NMSE_dB expected.NMSE_dB badGain.NMSE_dB];
            assert(expected.Ok && expected.NMSE_dB<=p.StrictConfig.ChannelNMSEThresholddB, ...
                'Same-clock physical TRS reference failed independently: %.3f dB.',expected.NMSE_dB);
        end
    end
    assert(seen && ~owner.hasPending("TRS",1));
end
disp(array2table(records,'VariableNames', ...
    {'ExecutedTXDelay','ExecutedRXDelay','SharedNMSE_dB','SameClockNMSE_dB','WrongGainNMSE_dB'}));
assert(all(abs(records(:,3)-records(:,4))<1e-8), ...
    'sixgr:test:SharedTRSScoringClockMismatch', ...
    'Shared TRS must score on the executed RX timing clock, without changing reception.');
ok=true;
end

function observation=localObservation(source,waveform)
observation=sixgr.phy.waveform.WaveformObservationBuffer(source.StartSample, ...
    source.EndSampleExclusive,source.SampleRateHz,source.NumReceiveAntennas);
observation.append(sixgr.phy.waveform.WaveformChunk(waveform,source.StartSample),source.SampleRateHz);
end
