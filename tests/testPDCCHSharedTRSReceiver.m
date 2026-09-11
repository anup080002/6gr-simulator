function ok = testPDCCHSharedTRSReceiver()
% PDCCH and TRS share physical samples; SSB uses the same retained RX stream.
% This does not claim main-scheduler or enabled nonlinear RF qualification.
ok = testBroadcastTRSNoisyStream([],true);
end
