function ok=testSLSHARQChannelTime()
% Native waveform/model equivalence at nonzero absolute time with mobility.
% Retain the ordinary zero-time regression; this specifically exercises the
% persistent-link channel clock and sealed fit/validation reader.
assert(testSLSWaveformChannelIdentity('DopplerHz',70,'AbsoluteSlot',23));
assert(testSLSWaveformChannelIdentity('DopplerHz',70,'AbsoluteSlot',39));
s=struct('Bits',1,'Noise',[2 3],'Channel',[4 4], ...
    'ControlNoise',[5 6],'RF',[7 8],'ChannelEvolution','persistent_link_absolute_slot');
[streams,mode]=sixgr.system.waveform.validateGrantCalibrationSeeds(s,2);
assert(numel(streams)==8 && mode=="persistent_link_absolute_slot");
bad=s; bad.Channel(2)=9; localReject(bad);
bad=s; bad.Noise(2)=bad.Noise(1); localReject(bad);
bad=s; bad.ChannelEvolution='independent_attempt_realizations'; localReject(bad);
ok=true;
fprintf('SLS_HARQ_CHANNEL_TIME_PASS native_tdla_cdlc_dl_ul=1 qualification=0\n');
end
function localReject(seeds)
caught=false;
try
    sixgr.system.waveform.validateGrantCalibrationSeeds(seeds,2);
catch err
    caught=strcmp(err.identifier,'sixgr:calibration:GrantEpisodeSeeds');
    if ~caught, rethrow(err); end
end
assert(caught,'Malformed independence policy was accepted.');
end
