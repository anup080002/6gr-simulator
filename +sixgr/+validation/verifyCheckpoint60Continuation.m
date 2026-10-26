function receipt=verifyCheckpoint60Continuation(referenceFolder,diagnosticFolder,varargin)
% Compatibility entry point; window is selected by current acceptance criteria.
receipt=sixgr.validation.verifyN40CheckpointContinuation(referenceFolder,diagnosticFolder,varargin{:});
end
