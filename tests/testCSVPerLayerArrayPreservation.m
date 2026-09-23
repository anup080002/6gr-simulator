function ok = testCSVPerLayerArrayPreservation()
% Declared serialization fixtures, not measured PHY samples.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
sixgr.db.deactivateArtifactStore();
T = table([1;2],[NaN 20;NaN 21],nan(2,2),false(2,2), ...
    ["" "measured";"" ""],nan(2,2),["unavailable";"unavailable"], ...
    'VariableNames',{'Slot','LayerSINRdB','UnrelatedBlankLayers', ...
    'LayerCRCFlags','LayerEvidence','Pilot_dB','PilotStatus'});
kept = sixgr.util.pruneStructurallyBlankTableColumns(T);
assert(isequal(kept.Properties.VariableNames, ...
    {'Slot','LayerSINRdB','LayerCRCFlags','LayerEvidence','Pilot_dB','PilotStatus'}));
for name = string(kept.Properties.VariableNames)
    assert(isequaln(kept.(name),T.(name)), ...
        'Pruning must not flatten, fill or average per-layer evidence.');
end
empty = T([],:);
assert(isequaln(sixgr.util.pruneStructurallyBlankTableColumns(empty),empty));
root = tempname; mkdir(root);
cleanup = onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
path = fullfile(root,'per_layer.csv');
sixgr.util.csvWriteTable(path,T);
persisted = readtable(path,'TextType','string','VariableNamingRule','preserve');
layerColumns = startsWith(string(persisted.Properties.VariableNames),"LayerSINRdB");
assert(nnz(layerColumns)==2 && isequaln(persisted{:,layerColumns},T.LayerSINRdB));
assert(~any(startsWith(string(persisted.Properties.VariableNames),"UnrelatedBlankLayers")));
assert(all(isnan(kept.Pilot_dB),'all') && ~any(kept.LayerCRCFlags,'all'));
fprintf('CSV_PER_LAYER_ARRAY_PRESERVATION_PASS\n');
ok = true;
end
