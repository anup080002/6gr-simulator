function out = NumericalSanityChecks(runFolder, scfg, cfg, varargin)
%NUMERICALSANITYCHECKS Return numerical sanity and invariant checks.

res = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", false, varargin{:});
out = res.NumericalSanityChecks;
end
