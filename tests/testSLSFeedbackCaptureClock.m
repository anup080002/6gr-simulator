function ok=testSLSFeedbackCaptureClock()
% Numerical BLER/SRS fixture tests runtime phase separation, not RF quality.
ok=testSystemFTP3CalibratedDelivery('UL','fixture');
end
