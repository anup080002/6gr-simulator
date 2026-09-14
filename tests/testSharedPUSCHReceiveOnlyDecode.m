function ok=testSharedPUSCHReceiveOnlyDecode()
% Actual shared no-transmission observation -> independent current-RV RX.
% Retained scheduled grant, not a newly executed missed-DCI procedure.
ok=testSharedPUSCHReceiveOnlyCapture(true);
end
