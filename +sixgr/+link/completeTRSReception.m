function out = completeTRSReception(prepared,observation,replay,channelState,options)
%COMPLETETRSRECEPTION Run the canonical receiver on already received samples.
% No waveform generation, RF processing, noise injection or channel advance.
arguments
    prepared (1,1) struct
    observation (1,1) sixgr.phy.waveform.WaveformObservationBuffer
    replay (1,1) struct
    channelState (1,1) struct
    options.ScoringChannelReferences cell = {}
    options.DesiredReferenceObservation = []
    options.RecordedReceiverTimingOffset_samples (1,1) double = NaN
end
reception=struct("Prepared",prepared,"Observation",observation, ...
    "Replay",replay,"ChannelState",channelState, ...
    "ScoringChannelReferences",{options.ScoringChannelReferences}, ...
    "DesiredReferenceObservation",options.DesiredReferenceObservation, ...
    "RecordedReceiverTimingOffset_samples",options.RecordedReceiverTimingOffset_samples);
out=sixgr.link.runTRSTracking(prepared.ReceiverConfig,"ReceivedContext",reception);
end
