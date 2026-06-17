function out = NoBypassImplementationGate(runFolder, scfg, cfg, varargin)
%NOBYPASSIMPLEMENTATIONGATE Return no-bypass gate rows.

res = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", false, varargin{:});
out = res.NoBypassGate;
end
