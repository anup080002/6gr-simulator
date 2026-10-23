function contract = waveformChannelOutputContract(object)
%WAVEFORMCHANNELOUTPUTCONTRACT Inspect a waveform backend without consuming it.
% MATLAB_BEHAVIOR: nrTDLChannel/nrCDLChannel filtering and response modes
% have different input/output signatures. A coefficient-only object must not
% be stepped, reset or retried as a waveform filter. This guard belongs at
% waveform consumers, not ChannelFactory.create (which also serves SLS).
contract=struct('Kind',"",'ModelApplied',"",'OutputCount',0);
if isa(object,'sixgr.channel.StaticReciprocalMIMOChannel')
    contract.Kind="static_reciprocal_fir";
    contract.ModelApplied="static_reciprocal_mimo_fir";
    contract.OutputCount=2;
    return;
end
if ~(isa(object,'nrTDLChannel') || isa(object,'nrCDLChannel'))
    error('sixgr:channel:UnsupportedWaveformBackend', ...
        'No waveform output contract is declared for backend %s.',class(object));
end
if ~object.ChannelFiltering
    error('sixgr:channel:WaveformFilteringDisabled', ...
        'Waveform reception requires ChannelFiltering=true; coefficient generation is a separate consumer.');
end
if isprop(object,'ChannelResponseOutput')
    if string(object.ChannelResponseOutput)~="path-gains"
        error('sixgr:channel:WaveformResponseModeMismatch', ...
            'This waveform consumer requires path-gains output, not a carrier-dependent OFDM-response signature.');
    end
    contract.OutputCount=3;
elseif isprop(object,'PathGainsOutputPort')
    contract.OutputCount=1+double(object.PathGainsOutputPort);
else
    error('sixgr:channel:UnknownWaveformOutputContract', ...
        'The installed native channel exposes no supported response-output selector.');
end
contract.Kind="native_filtered_channel";
contract.ModelApplied=string(object.DelayProfile);
end
