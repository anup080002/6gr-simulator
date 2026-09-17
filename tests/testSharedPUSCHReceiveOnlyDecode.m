function ok=testSharedPUSCHReceiveOnlyDecode()
% Actual shared no-transmission observation -> independent current-RV RX.
% Actual gNB command from retained allocation, no UE DCI decode or missed-DCI-rate claim.
ok=testSharedPUSCHReceiveOnlyCapture(true);
end
