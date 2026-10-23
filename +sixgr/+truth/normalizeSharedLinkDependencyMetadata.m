function links=normalizeSharedLinkDependencyMetadata(links)
% Schema migration only for pre-registration snapshots predating dependency
% receipts. Never reconstruct original channel history from current state.
assert(isstruct(links),'WAVEFORM:InvalidSharedLinkInventory', ...
    'The retained physical-link inventory must be a struct array.');
if isfield(links,'SignalDependency'), return; end
if isempty(links)
    % Preserve every existing field and the shape of an empty inventory.
    names=[fieldnames(links); {'SignalDependency'}];
    links=cell2struct(cell([numel(names),size(links)]),names,1);
else
    [links.SignalDependency]=deal(struct());
end
end
