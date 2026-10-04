function ok=testSystemNonoverlappingPUCCHPUSCH()
% Actual SLS runner/scheduler with labelled test-only calibration and ideal UCI.
ok=testSystemFTP3CalibratedDelivery("UL","network","nonoverlapping");
end
