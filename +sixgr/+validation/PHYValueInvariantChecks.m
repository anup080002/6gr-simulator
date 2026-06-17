function out = PHYValueInvariantChecks(runFolder, scfg, cfg, varargin)
%PHYVALUEINVARIANTCHECKS Return PHY value invariant checks.

res = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", false, varargin{:});
out = res.PHYValueInvariantChecks;
end
