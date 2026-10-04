function ok=testE2EReceivedAccessMultiUE()
% Actual independent coded access, followed by two-UE DL waveform replay.
% Serial access warm-up is not simultaneous common-channel interference.
ok=testNoProxyTruthContract(2);
end
