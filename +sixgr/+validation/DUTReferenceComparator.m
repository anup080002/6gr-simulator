function out = DUTReferenceComparator(runFolder, scfg, cfg, varargin)
%DUTREFERENCECOMPARATOR Return DUT-vs-reference comparison rows.

res = sixgr.validation.LLSValidationHarness(runFolder, scfg, cfg, "WriteArtifacts", false, varargin{:});
out = res.DUTReferenceComparison;
end
