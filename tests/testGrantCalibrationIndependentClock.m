function ok=testGrantCalibrationIndependentClock()
% Independently seeded retries still have nonzero physical grant clocks.
ok=testSLSWaveformChannelIdentity('DopplerHz',70,'AbsoluteSlot',23, ...
    'RetryCollection',true,'ChannelEvolution','independent_attempt_realizations');
assert(ok);
end
