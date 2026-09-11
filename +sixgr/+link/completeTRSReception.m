function out = completeTRSReception(prepared,observation,replay,channelState,options)
%COMPLETETRSRECEPTION Run the canonical receiver on already received samples.
% No waveform generation, RF processing, noise injection or channel advance.
arguments
    prepared (1,1) struct
    observation (1,1) sixgr.phy.waveform.WaveformObservationBuffer
    replay (1,1) struct
    channelState (1,1) struct
    options.ScoringChannelReferences cell = {}
end
reception=struct("Prepared",prepared,"Observation",observation, ...
    "Replay",replay,"ChannelState",channelState, ...
    "ScoringChannelReferences",{options.ScoringChannelReferences});
out=sixgr.link.runTRSTracking(prepared.ReceiverConfig,"ReceivedContext",reception);
end
