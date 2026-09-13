function T = finalCoupledWaveformPreview(state)
%FINALCOUPLEDWAVEFORMPREVIEW Select retained samples from the executed path.
% This selects evidence; it does not generate samples or infer a backend
% from a scenario name. A missing authoritative table always fails closed.
if ~(isstruct(state) && isscalar(state))
    error('sixgr:truth:InvalidFinalWaveformRuntime', ...
        'Final waveform publication requires a scalar coupled runtime state.');
end
if isfield(state, 'SharedWaveformStream')
    if ~isa(state.SharedWaveformStream, 'sixgr.truth.CoupledWaveformStream')
        error('sixgr:truth:InvalidFinalWaveformRuntime', ...
            'A shared waveform runtime must retain its typed physical owner.');
    end
    field = 'SharedWaveformPreviewTable';
    id = 'sixgr:truth:MissingFinalSharedWaveformPreview';
    description = 'shared-stream';
else
    field = 'WaveformPreviewTable';
    id = 'sixgr:truth:MissingFinalGrantWaveformPreview';
    description = 'per-grant';
end
if ~isfield(state, field) || ~istable(state.(field)) || isempty(state.(field))
    error(id, 'Coupled truth execution is missing the retained %s waveform preview required for final artifact publication.', description);
end
T = state.(field);
end
