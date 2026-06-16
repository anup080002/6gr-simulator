function result = validateDLPDSCHRawEvidence(trialTable, cfg, varargin)
%VALIDATEDLPDSCHRAWEVIDENCE Validate DL PDSCH raw trial evidence contract.
%   Thin public wrapper around the strict objective evaluator for tests and
%   reporting code that only need row-evidence validation outputs.

if nargin < 2
    cfg = struct();
end
result = sixgr.truth.evaluatePDSCHObjectiveStrict(trialTable, cfg, varargin{:});
end
