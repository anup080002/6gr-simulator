function ok=testRetainedSSBPUCCHWithheldRecovery()
% Explicit physical receiver-only/no-TX arm; the default test runs positive.
ok=testRetainedSSBPUCCHRecovery('withheld');
end
