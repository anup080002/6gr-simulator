function ok=testPUCCHBaselineSignalClock(outputRoot)
% Actual baseline UL, separate explicitly authored isolated DL source.
% Not full access/QCL/TA qualification or a multi-trial ACK-miss result.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
v=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/pucch_baseline_signal.yaml');
ok=testSharedPUCCHFeedbackClock(v.include_late_feedback,v.duplex_mode, ...
    v.physical_scenario,outputRoot,v.feedback_source_scenario);
end
