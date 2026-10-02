function ok=testSystemNetworkSpatialDelivery()
% Actual network channel/SRS/scheduler integration; TEST-ONLY BLER curve.
% Not statistical calibration or accepted study throughput.
ok=testSystemFTP3CalibratedDelivery('UL','network');
end
