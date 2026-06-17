function out = BlockEvidenceRegistry(runFolder, scfg, cfg, varargin)
%BLOCKEVIDENCEREGISTRY Return the Actual-LLS block registry.

res = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", false, varargin{:});
out = res.Registry;
end
