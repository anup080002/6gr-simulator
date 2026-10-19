function evidence=replayRetainedRAReceiverMeasurements(runFolder)
% Bounded read-only replay of the retained H4 access captures. No new channel,
% RF, TX or noise execution; never rewrites the original run's measurements.
root=fullfile(runFolder,'air_interface','mat');
files=dir(fullfile(root,'ra_received_observations','*Msg1*.mat'));
assert(isscalar(files),'test:CaptureSelection','Select one run with one retained Msg1.');
saved=load(fullfile(files.folder,files.name),'capture'); a=saved.capture;
ref=arrival(a);
% ReceiverContinuation is the pre-reception restart state. Completed
% measurements belong to ReceivedResult, not that earlier continuation.
measured=a.ReceivedResult.PRACHPropagationTimingEstimate_samples;
expected=ref.ExpectedArrivalOffset_samples-a.Prepared.PhysicalTiming.ReceiveSearchGuardSamples- ...
    ref.ChannelFilterDelay_samples;
evidence=struct('Scope',"retained_IQ_repair_replay_not_new_scenario_or_statistical_qualification", ...
    'PRACHReference',ref,'PRACHExpectedCalibratedArrival_samples',expected, ...
    'PRACHMeasuredCalibratedArrival_samples',measured, ...
    'PRACHError_samples',measured-expected, ...
    'PRACHTAUnchanged',a.ReceivedResult.EstimatedTimingAdvanceCommand);
clear a saved;
files=dir(fullfile(root,'ra_received_observations','*Msg3*.mat'));
assert(isscalar(files),'test:CaptureSelection','Select one run with one retained Msg3.');
saved=load(fullfile(files.folder,files.name),'capture'); a=saved.capture;
ref=arrival(a);
evidence.Msg3Reference=ref;
evidence.Msg3AppliedTimingCorrection_samples=a.ReceivedResult.Msg3AppliedTimingCorrection_samples;
evidence.Msg3ResidualToFirstPath_samples=ref.ExpectedArrivalOffset_samples-evidence.Msg3AppliedTimingCorrection_samples;
cfg=a.ReceiverContinuation.Config;
ra=a.ReceiverContinuation.RAConfig;
original=a.ReceiverContinuation.PDSCHRx2.TransportBlock;
clear a saved;
files=dir(fullfile(root,'rar_monitoring_observations','*_RAR_30.mat'));
assert(isscalar(files),'test:CaptureSelection','This retained replay explicitly selects absolute RAR slot 30.');
saved=load(fullfile(files.folder,files.name),'capture'); a=saved.capture;
assert(ra.Msg2Slot==a.Context.AbsoluteSlot,'test:CaptureSelection','Use the received RAR slot identity.');
cfg.lls6g.receiverSync.RuntimeWaveformSampleAligned=false;
% Only the recorded AGC compensation precedes this front end. The capture
% has not been frequency derotated; acquisition consumes its actual IQ.
[rx,rar]=sixgr.phy.ra.recoverMsg2RAR(a.RXAfterDigitalGainCompensation,cfg,ra,struct(),struct());
assert(rx.Ok && rx.PDCCHReceiver.CausalGrantDecodeOk && isequal(rx.TransportBlock,original));
assert(rx.CFOCorrectionApplied && isfinite(rx.EstimatedCFO_Hz) && ...
    rx.TimingEstimateUsed && ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
evidence.RAR=sixgr.phy.ra.receiverDiagnostics(rx);
evidence.RARTimingAdvanceCommand=rar.TimingAdvanceCommand;
evidence.RARPayloadUnchanged=true;
fprintf('RETAINED_RA_REPAIR_PASS PRACH_reference=%g measured=%g error=%g Msg3_reference=%g applied=%g residual=%g RAR_CFO=%g timing=%g CRC=%d\n', ...
    expected,evidence.PRACHMeasuredCalibratedArrival_samples,evidence.PRACHError_samples, ...
    ref.ExpectedArrivalOffset_samples,evidence.Msg3AppliedTimingCorrection_samples, ...
    evidence.Msg3ResidualToFirstPath_samples,rx.EstimatedCFO_Hz,rx.AppliedTimingCorrection_samples,rx.Ok);
disp(evidence);
end

function ref=arrival(capture)
post=sixgr.phy.waveform.WaveformObservationBuffer(capture.StartSample,capture.EndSampleExclusive, ...
    capture.SampleRateHz,size(capture.RXAfterRF,2));
post.append(sixgr.phy.waveform.WaveformChunk(capture.RXAfterRF,capture.StartSample),capture.SampleRateHz);
replay=capture.ExecutionReplay;
planes=struct('ReceiverID',{string(replay.ReceiverID)+":post_rf",string(replay.TransmitterID)+":tx"}, ...
    'Observation',{post,post},'Segments',{replay.ReceiveStreamExecutionSegments,replay.ReceiveStreamExecutionSegments});
ref=sixgr.truth.sharedArrivalTimingReference(planes,capture.Prepared.PhysicalTiming.TransmitStartSample);
end
