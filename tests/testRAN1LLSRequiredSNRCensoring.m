function ok = testRAN1LLSRequiredSNRCensoring()
%TESTRAN1LLSREQUIREDSNRCENSORING Guard zero-error confidence crossings.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
[cfg,~] = sixgr.lls.loadConfig("configs/lls/pusch_awgn_qpsk_publication.yaml");
summary = table([-2;-1],[0.556;0],[0.525049162509908;0], ...
    [0.586522240539710;3.84131125830396e-05], ...
    'VariableNames',{'SNRdB','BLER','BLERLowerCI','BLERUpperCI'});
required = sixgr.lls.requiredSNRTable(cfg,summary);
assert(all(required.Valid));
assert(all(required.LowerBracketSNRdB == -2) && ...
    all(required.UpperBracketSNRdB == -1));
assert(all(required.RequiredSNRdB > -2 & required.RequiredSNRdB < -1));
assert(all(required.EstimationBasis == ...
    "zero_error_wilson_upper_bound_conservative_log_interpolation"));
assert(all(required.Status == ...
    "confidence_bracketed_using_zero_error_wilson_upper_bound"));
fprintf("RAN1LLSRequiredSNRCensoring: required SNR estimates %s dB.\n", ...
    mat2str(required.RequiredSNRdB.',6));
ok = true;
end
