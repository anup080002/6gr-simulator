function T = finalCoupledWaveformPreview(state,dataTrials)
%FINALCOUPLEDWAVEFORMPREVIEW Select retained samples from the executed path.
% This selects evidence; it does not generate samples or infer a backend
% from a scenario name. Broadcast evidence cannot replace missing data evidence.
if nargin<2, dataTrials=table(); end
assert(istable(dataTrials),'sixgr:truth:InvalidFinalWaveformRuntime', ...
    'Final data-trial evidence must be a table.');
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
    if isfield(state,'SharedWaveformStream') && isempty(dataTrials) && ...
            isempty(state.SharedWaveformStream.DataTransmissions) && ...
            isfield(state,'SharedBroadcastWaveformPreviewTable')
        broadcast=state.SharedBroadcastWaveformPreviewTable;
        if istable(broadcast) && ~isempty(broadcast) && ...
                all(ismember({'ObservationKind','EvidenceScope','Source'},broadcast.Properties.VariableNames)) && ...
                all(broadcast.ObservationKind=="broadcast_window") && ...
                all(broadcast.EvidenceScope=="shared_broadcast_observation_not_data_constellation") && ...
                all(broadcast.Source=="completed_shared_waveform_observation_buffers")
            T=broadcast;
            return;
        end
    end
    error(id, 'Coupled truth execution is missing the retained %s waveform preview required for final artifact publication.', description);
end
T = state.(field);
end
