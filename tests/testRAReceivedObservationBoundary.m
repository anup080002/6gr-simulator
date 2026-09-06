function ok = testRAReceivedObservationBoundary()
% Real coded TDD RA over an external unit channel tests buffer ownership,
% not fading, RF qualification or the combined production scheduler.
setup6GRSimToolkit('Verbose',false);
cfg = raStrictAnchorConfig();
cfg.phy.duplex.mode = "TDD";
root = tempname;
mkdir(root);
cleanup = onCleanup(@() rmdir(root,'s')); %#ok<NASGU>
rng(78132,'twister');
[prepared, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'RunFolder',root,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false, ...
    'StageAction','prepare_next_stage','ReceiveThroughTime_s',0);
stages = ["Msg1","Msg2","Msg3","Msg4","RRCSetupComplete"];
for index = 1:numel(stages)
    tx = prepared.PreparedTransmission;
    assert(tx.StageName == stages(index) && height(prepared.RuntimeStageRows) == index-1);
    fs = tx.SampleRate_Hz;
    first = round(tx.StartTime_s*fs);
    last = first+tx.SampleCount;
    % This test's external propagation is an explicit noiseless unit channel.
    received = tx.Waveform;
    observation = sixgr.phy.waveform.WaveformObservationBuffer(first,last,fs,size(received,2));
    cut = max(1,floor(tx.SampleCount/3));
    observation.append(sixgr.phy.waveform.WaveformChunk(received(1:cut,:),first),fs);
    beforeRuntime = checkpoint.Runtime;
    if index == 1
        localReject(@() localComplete(cfg,checkpoint,observation,tx), 'WAVEFORM:IncompleteObservation');
        wrong = sixgr.phy.waveform.WaveformObservationBuffer(first+1,last+1,fs,size(received,2));
        localReject(@() localComplete(cfg,checkpoint,wrong,tx), 'sixgr:phy:ra:RAObservationOriginMismatch');
        wrong = sixgr.phy.waveform.WaveformObservationBuffer(first,last,2*fs,size(received,2));
        localReject(@() localComplete(cfg,checkpoint,wrong,tx), 'sixgr:phy:ra:RAObservationLayoutMismatch');
        wrong = sixgr.phy.waveform.WaveformObservationBuffer(first,last+1,fs,size(received,2));
        localReject(@() localComplete(cfg,checkpoint,wrong,tx), 'sixgr:phy:ra:RAObservationLayoutMismatch');
        badSamples = received;
        badSamples(1) = NaN;
        localReject(@() localComplete(cfg,checkpoint,badSamples,tx), 'sixgr:phy:ra:BadRuntimeStageWaveform');
        localReject(@() localComplete(cfg,checkpoint,struct('not_samples',true),tx), ...
            'sixgr:phy:ra:BadRuntimeStageWaveform');
        stale = checkpoint;
        stale.ContractVersion = "ra_stage_continuation_v2";
        localReject(@() localComplete(cfg,stale,observation,tx), 'sixgr:phy:ra:InvalidRAContinuation');
    end
    observation.append(sixgr.phy.waveform.WaveformChunk(received(cut+1:end,:),first+cut),fs);
    streams = struct();
    streams.(stages(index)+"RxWaveform") = observation;
    [held, heldCheckpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
        'Continuation',checkpoint,'RuntimeStageWaveforms',streams, ...
        'StopAfterStage',stages(index),'ReceiveThroughTime_s',tx.EndTimeExclusive_s-1/fs);
    assert(height(held.RuntimeStageRows) == index-1 && held.RuntimeExecutionState == "pending_stage_receive", ...
        'Having a complete buffer must not release decode before the scheduler receive clock is due.');
    [decoded, checkpoint] = localComplete(cfg,heldCheckpoint,observation,tx);
    rows = decoded.RuntimeStageRows;
    row = rows(end,:);
    assert(height(rows) == index && row.StageName == stages(index));
    assert(row.ObservationStartSample == first && row.ObservationEndSampleExclusive == last && ...
        row.ObservationSampleRateHz == fs && row.ObservationCompletionTime_s == last/fs);
    assert(row.ObservationCoverageSource == "complete_contiguous_received_sample_buffer" && ...
        row.WaveformSource == "provided_contiguous_received_sample_buffer" && ...
        row.RuntimeStageWaveformUsed && ~row.SelfLoopWaveformUsed);
    assert(~row.RuntimeChannelStateUsed && ~row.NoiseApplied && isnan(row.NoiseVariance), ...
        'Observation coverage must not manufacture channel/noise provenance.');
    assert(isequaln(decoded.RuntimeDLChannelState,beforeRuntime.DLChannelState) && ...
        isequaln(decoded.RuntimeULChannelState,beforeRuntime.ULChannelState), ...
        'Completing already received samples must not advance either channel state.');
    assert(isequaln(rows(1:index-1,:),prepared.RuntimeStageRows), ...
        'Earlier stage evidence must not change during a later decode.');
    if index < numel(stages)
        [prepared, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
            'Continuation',checkpoint,'StageAction','prepare_next_stage');
    end
end
assert(decoded.StrictOk && decoded.RRCConnected && isempty(fieldnames(checkpoint)), ...
    'All actual coded RA receivers must complete using only the supplied samples.');
ok = true;
fprintf('RAReceivedObservationBoundary PASS: five coded TDD stages; coverage, origin, rate and causal decode guards.\n');
end

function [result, checkpoint] = localComplete(cfg,checkpoint,observation,tx)
streams = struct();
streams.(tx.StageName+"RxWaveform") = observation;
[result, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'Continuation',checkpoint,'RuntimeStageWaveforms',streams, ...
    'StopAfterStage',tx.StageName,'ReceiveThroughTime_s',tx.EndTimeExclusive_s);
end

function localReject(action,identifier)
try
    action();
catch ME
    assert(string(ME.identifier) == string(identifier), ...
        'Expected %s; got %s: %s',identifier,ME.identifier,ME.message);
    return;
end
error('testRAReceivedObservationBoundary:MissingError','Expected rejection %s.',identifier);
end
