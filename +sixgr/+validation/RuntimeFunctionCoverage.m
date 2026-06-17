function out = RuntimeFunctionCoverage(runFolder, scfg, cfg, varargin)
%RUNTIMEFUNCTIONCOVERAGE Return runtime function-coverage rows.

res = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", false, varargin{:});
out = res.RuntimeFunctionCoverage;
end
