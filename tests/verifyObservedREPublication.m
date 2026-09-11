function layout=verifyObservedREPublication(T,cfg,root)
% Actual caller-generated TX rows through the production publication entry.
% cfg identity describes this component fixture, not a completed main run.
layout=sixgr.report.resultLayout(root);
[carrier,native]=sixgr.truth.writeObservedREAllocationArtifacts(T,cfg,layout);
assert(height(carrier)+height(native)==height(T));
expected={carrier,native};
names={'observed_re_allocation.csv','observed_prach_native_allocation.csv'};
live={'live_re_allocation_snapshot.csv','live_prach_native_allocation_snapshot.csv'};
for k=1:2
    paths=[string(fullfile(layout.ComponentCSVDirs.frame_grid,names{k})), ...
        string(fullfile(layout.ReportCSVDir,live{k}))];
    if isempty(expected{k}), assert(~any(isfile(paths))); continue; end
    before=cell(1,2);
    for p=1:2
        restored=readtable(paths(p),'TextType','string','VariableNamingRule','preserve');
        assert(height(restored)==height(expected{k}) && ...
            all(restored.ConfigHash==string(cfg.meta.configHash)) && ...
            all(restored.ScenarioID==string(cfg.run.scenarioID)) && ...
            all(restored.ConfigHashContextSource=="CfgMobility.meta.configHash") && ...
            all(restored.ScenarioIDContextSource=="CfgMobility.run.scenarioID"));
        assert(isequal(string(restored.grid_domain),string(expected{k}.grid_domain)) && ...
            isequal(string(restored.authority),string(expected{k}.authority)) && ...
            isequal(string(restored.resolver),string(expected{k}.resolver)));
        before{p}=fileread(paths(p));
    end
    for name=["ScenarioID","ConfigHash"]
        bad=T; bad.(name)=repmat("conflicting_component_identity",height(T),1);
        localReject(@()sixgr.truth.writeObservedREAllocationArtifacts(bad,cfg,layout), ...
            'sixgr:truth:REContextIdentityMismatch');
        for p=1:2, assert(isequal(fileread(paths(p)),before{p})); end
    end
end
% Missing context must stay missing, not become a generated hash or UE ID.
unknownLayout=sixgr.report.resultLayout(fullfile(root,'missing_context'));
[a,b]=sixgr.truth.writeObservedREAllocationArtifacts(T,struct(),unknownLayout);
for piece={a,b}
    if isempty(piece{1}), continue; end
    assert(~any(ismember({'ScenarioID','ConfigHash'},piece{1}.Properties.VariableNames)));
end
% Test stale checkpoint cleanup only inside this fresh component-test tree.
sixgr.truth.writeObservedREAllocationArtifacts(table(),struct(),unknownLayout);
assert(~isfile(fullfile(unknownLayout.ReportCSVDir,live{1})) && ...
    ~isfile(fullfile(unknownLayout.ReportCSVDir,live{2})) && ...
    ~isfile(fullfile(unknownLayout.ComponentCSVDirs.frame_grid,names{1})) && ...
    ~isfile(fullfile(unknownLayout.ComponentCSVDirs.frame_grid,names{2})));
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier); return;
end
error('test:MissingREIdentityRejection','Conflicting RE identity was accepted.');
end
