function ok = testRAReceivedObservationBoundary()
% Real coded TDD RA over an explicit short FIR tests buffer ownership,
% not fading, RF qualification or the combined production scheduler.
setup6GRSimToolkit('Verbose',false);
cfg = raStrictAnchorConfig();
cfg.phy.duplex.mode = "TDD";
root = fullfile(pwd,'results','sls','ra_received_access_identity', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
fprintf('RA_RECEIVED_ACCESS_EVIDENCE_ROOT=%s\n',root);
rng(78132,'twister');
[prepared, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'RunFolder',root,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false, ...
    'StageAction','prepare_next_stage','ReceiveThroughTime_s',0);
stages = ["Msg1","Msg2","Msg3","Msg4","RRCSetupComplete"];
scaleFields = ["PreambleTxAmplitudeScale","Msg2TxAmplitudeScale", ...
    "Msg3TxAmplitudeScale","Msg4TxAmplitudeScale","SetupCompleteTxAmplitudeScale"];
executedScales = nan(size(stages));
for index = 1:numel(stages)
    tx = prepared.PreparedTransmission;
    if index==4
        % The waveform is already prepared with the actual network identity.
        % Poison a non-receiver intended value; it cannot replace decoded
        % Msg4 identity or determine the UE's subsequent PUSCH scrambling.
        checkpoint.RAConfig.FinalCRNTI=cfg.random_access.final_crnti+1;
        issuedSetup=checkpoint.PreparedContext.Msg4Payload.RRCSetup;
        checkpoint.RAConfig.RRCTransactionID=mod(issuedSetup.TransactionID+1,4);
        checkpoint.RAConfig.SRB1LCID=mod(issuedSetup.SRB1LCID,32)+1;
    elseif index==5
        assert(checkpoint.PreparedContext.PUSCH.RNTI==cfg.random_access.final_crnti, ...
            'RRCSetupComplete must use the received Msg4 identity, not a configured oracle.');
        assert(checkpoint.PreparedContext.Payload.TransactionID==issuedSetup.TransactionID && ...
            checkpoint.PreparedContext.Payload.SRB1LCID==issuedSetup.SRB1LCID, ...
            'UE reply must echo the received Setup transaction/bearer, not the poisoned configuration.');
    end
    assert(tx.StageName == stages(index) && height(prepared.RuntimeStageRows) == index-1);
    executedScales(index) = prepared.(scaleFields(index));
    assert(isfinite(executedScales(index)) && executedScales(index) > 0, ...
        'A prepared real transmission must retain its applied amplitude scale.');
    fs = tx.SampleRate_Hz;
    first = round(tx.StartTime_s*fs);
    tailSamples = 7;
    last = first+tx.SampleCount+tailSamples;
    % Actual causal FIR output, including the response to real subsequent
    % transmitter silence. Not copied TX samples with a fabricated RX tail.
    taps = [1 zeros(1,tailSamples-1) 0.025];
    input = [tx.Waveform; zeros(tailSamples,size(tx.Waveform,2),'like',tx.Waveform)];
    received = filter(taps,1,input);
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
        wrong = sixgr.phy.waveform.WaveformObservationBuffer(first,first+tx.SampleCount-1,fs,size(received,2));
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
        'StopAfterStage',stages(index),'ReceiveThroughTime_s',tx.EndTimeExclusive_s);
    assert(height(held.RuntimeStageRows) == index-1 && held.RuntimeExecutionState == "pending_stage_receive", ...
        'The nominal TX end must not release a later-ending received channel tail.');
    [held, heldCheckpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
        'Continuation',heldCheckpoint, ...
        'StopAfterStage',stages(index),'ReceiveThroughTime_s',(last-1)/fs);
    assert(height(held.RuntimeStageRows)==index-1 && ...
        held.RuntimeExecutionState=="pending_stage_receive", ...
        'Resuming without re-supplying the buffer must retain its actual receive-completion boundary.');
    [decoded, checkpoint] = localComplete(cfg,heldCheckpoint,observation,tx);
    if index>=2
        assert(isfield(decoded,'DecodedRAR') && ...
            decoded.DecodedRAR.TimingAdvanceCommand==decoded.TimingAdvanceCommand && ...
            decoded.DecodedRAR.TemporaryCRNTI==decoded.TemporaryCRNTI && ...
            decoded.RARBytesHex==decoded.DecodedRAR.Hex, ...
            'Retain the actual decoded RAR for later connected TAG/SRS consumers.');
    end
    if index>=4
        assert(decoded.FinalCRNTI==cfg.random_access.final_crnti && ...
            decoded.DecodedMsg4.FinalCRNTI==decoded.FinalCRNTI && ...
            decoded.FinalCRNTISource=="decoded_msg4_payload_after_contention_match" && ...
            decoded.FinalCRNTIEncodingProfile=="legacy_bounded_not_NR_MAC_RRC", ...
            'RA result must retain identity and encoding provenance from the independent decoder.');
    end
    for prior = 1:index
        assert(isequal(decoded.(scaleFields(prior)),executedScales(prior)), ...
            'Later received RAR power commands must not erase or alter earlier TX scaling evidence.');
    end
    rows = decoded.RuntimeStageRows;
    row = rows(end,:);
    assert(height(rows) == index && row.StageName == stages(index));
    assert(row.ObservationStartSample == first && row.ObservationEndSampleExclusive == last && ...
        row.ObservationSampleRateHz == fs && row.ObservationCompletionTime_s == last/fs);
    assert(row.RxSampleCount==tx.SampleCount+tailSamples && row.TxSampleCount==tx.SampleCount);
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
msg4Rows=decoded.ArtifactTables.msg4_contention_resolution;
setupRows=decoded.ArtifactTables.rrc_setup_complete;
assert(setupRows.ReceivedRRCSetupTransactionID==issuedSetup.TransactionID && ...
    setupRows.ReceivedSRB1LCID==issuedSetup.SRB1LCID && ...
    setupRows.RRCSetupConfigurationSource=="decoded_msg4_rrc_setup_after_contention_match" && ...
    setupRows.DecodedTransactionID==setupRows.ReceivedRRCSetupTransactionID && ...
    setupRows.DecodedSRB1LCID==setupRows.ReceivedSRB1LCID, ...
    'Export received UE configuration separately from network expectations and UL decoding.');
assert(height(msg4Rows)==1 && msg4Rows.FinalCRNTI==decoded.FinalCRNTI && ...
    msg4Rows.FinalCRNTISource==decoded.FinalCRNTISource && ...
    msg4Rows.FinalCRNTIEncodingProfile==decoded.FinalCRNTIEncodingProfile, ...
    'The primary Msg4 export must preserve decoded identity and codec scope.');
save(fullfile(root,'received_access_result.mat'),'cfg','decoded');
sixgr.util.csvWriteTable(fullfile(root,'msg4_contention_resolution.csv'),msg4Rows);
sixgr.util.csvWriteTable(fullfile(root,'msg2_rar_trials.csv'),decoded.ArtifactTables.msg2_rar_trials);
sixgr.util.csvWriteTable(fullfile(root,'rrc_setup_complete.csv'),setupRows);
sixgr.util.csvWriteTable(fullfile(root,'received_stage_windows.csv'),decoded.RuntimeStageRows);
ok = true;
fprintf('RAReceivedObservationBoundary PASS: five coded TDD stages; coverage, origin, rate and causal decode guards.\n');
end

function [result, checkpoint] = localComplete(cfg,checkpoint,observation,tx)
streams = struct();
streams.(tx.StageName+"RxWaveform") = observation;
through=tx.EndTimeExclusive_s;
if isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer')
    through=max(through,observation.EndSampleExclusive/observation.SampleRateHz);
end
[result, checkpoint] = sixgr.phy.ra.runFourStepRA(cfg, ...
    'Continuation',checkpoint,'RuntimeStageWaveforms',streams, ...
    'StopAfterStage',tx.StageName,'ReceiveThroughTime_s',through);
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
