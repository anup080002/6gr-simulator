function ok=testRARUsesDetectedPreamble()
% Real alternate received preamble. The gNB must not consult the UE's
% intended TX preamble to suppress reception or manufacture the RAR RAPID.
setup6GRSimToolkit('Verbose',false);
cfg=raStrictAnchorConfig(); cfg.phy.duplex.mode='TDD';
[prepared,k]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','provided_observation_unit_channel_test', ...
    'RequireRuntimeStageWaveforms',true,'UseRuntimeChannel',false, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage');
requested=k.RAConfig.PreambleIndex; observed=mod(requested+1,64);
prachCfg=k.Msg1Tx.PRACHRuntimeConfig;
alternate=sixgr.rach.generatePRACHWaveform(prachCfg,'Occasion',k.PreparedContext.Occasion, ...
    'PreambleIndex',observed);
t=prepared.PreparedTransmission; first=round(t.StartTime_s*t.SampleRate_Hz);
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(alternate.Waveform,1), ...
    t.SampleRate_Hz,size(alternate.Waveform,2));
b.append(sixgr.phy.waveform.WaveformChunk(alternate.Waveform,first),t.SampleRate_Hz);
[received,k]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',k, ...
    'RuntimeStageWaveforms',struct('Msg1RxWaveform',b),'StopAfterStage','Msg1');
assert(received.PreambleDetected && received.PreambleIndexDetected==observed && ...
    received.PreambleIndexTx==requested && ~received.RACompleted);
[~,k]=sixgr.phy.ra.runFourStepRA(cfg,'Continuation',k,'StageAction','prepare_next_stage');
rar=sixgr.mac.ra.decodeMACRAR(k.Msg2Tx.RAR.Bytes,k.RAConfig);
assert(rar.RAPID==observed && rar.RAPID~=requested);
disp('RAR_DETECTED_PREAMBLE_PASS: actual detector identity controls gNB RAR; no TX-identity oracle.');
ok=true;
end
