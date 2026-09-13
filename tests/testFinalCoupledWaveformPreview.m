function ok = testFinalCoupledWaveformPreview()
%TESTFINALCOUPLEDWAVEFORMPREVIEW Evidence selection, not an RF qualification.
% Declared table fixtures must survive exactly, including metadata and NaN.
immediate = table([1;2], [0.25;NaN], ["DL";"UL"], ...
    'VariableNames', {'SampleIndex','TxReal','Direction'});
immediate.Properties.Description = 'declared per-grant publication unit fixture';
shared = immediate;
shared.TxReal(1) = -0.75;
shared.Properties.Description = 'declared shared publication unit fixture';
state = struct('WaveformPreviewTable', immediate, ...
    'SharedWaveformPreviewTable', shared);
assert(isequaln(sixgr.truth.finalCoupledWaveformPreview(state), immediate));
localReject(struct(), 'sixgr:truth:MissingFinalGrantWaveformPreview');
localReject(struct('SharedWaveformPreviewTable', shared), ...
    'sixgr:truth:MissingFinalGrantWaveformPreview');
for value = {table(), 1, struct(), []}
    localReject(struct('WaveformPreviewTable', value{1}), ...
        'sixgr:truth:MissingFinalGrantWaveformPreview');
end
% An uninitialized typed owner only selects the shared evidence namespace;
% this test does not assert that the owner has executed a physical sample.
state.SharedWaveformStream = sixgr.truth.CoupledWaveformStream();
assert(isequaln(sixgr.truth.finalCoupledWaveformPreview(state), shared));
state.SharedWaveformPreviewTable = table();
localReject(state, 'sixgr:truth:MissingFinalSharedWaveformPreview');
state = rmfield(state, 'SharedWaveformPreviewTable');
localReject(state, 'sixgr:truth:MissingFinalSharedWaveformPreview');
state.SharedWaveformStream = [];
localReject(state, 'sixgr:truth:InvalidFinalWaveformRuntime');
localReject([], 'sixgr:truth:InvalidFinalWaveformRuntime');
ok = true;
end

function localReject(state, identifier)
caught = false;
try
    sixgr.truth.finalCoupledWaveformPreview(state);
catch ME
    caught = true;
    assert(strcmp(ME.identifier, identifier), ...
        'Expected %s, received %s: %s', identifier, ME.identifier, ME.message);
    assert(~isempty(ME.message));
end
assert(caught, 'Missing waveform evidence must not silently succeed.');
end
