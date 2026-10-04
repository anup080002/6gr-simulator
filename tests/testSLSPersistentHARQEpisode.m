function ok=testSLSPersistentHARQEpisode()
% A real first-attempt failure, not a forced retry after successful decoding.
ok=testSLSWaveformChannelIdentity('DopplerHz',70,'AbsoluteSlot',23,'RetryCollection',true);
end
