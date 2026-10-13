function ok=testNestedComponentArtifactAudit()
% Numerical raster fixtures only; component ownership must survive nesting.
root=fullfile(pwd,'results','lls','component_lineage_audit', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
for name=["srs","trs"]
    owner=fullfile(root,'component_anchors',name);
    csvDir=fullfile(owner,'reference_signals','csv');
    imageDir=fullfile(owner,'reports','figures');
    mkdir(csvDir); mkdir(imageDir);
    source=fullfile(csvDir,'measured_values.csv');
    writetable(table((1:3).',[1;3;2],'VariableNames',{'Trial','Metric'}),source);
    path=fullfile(imageDir,'measurement.png');
    [x,y]=meshgrid(1:128,1:128);
    imwrite(uint8(mod(x+3*y,256)),path);
    sixgr.visual.writeComponentPlotLineage(owner, ...
        fullfile(csvDir,'component_plot_lineage.csv'),name,path,source, ...
        'testNestedComponentArtifactAudit_numerical_fixture');
end
a=sixgr.validation.auditRunArtifacts(root,'WriteOutputs',false);
assert(a.ImageCount==2 && a.ImageFailureCount==0);
for name=["srs","trs"]
    row=a.ImageAuditTable(contains(a.ImageAuditTable.relative_path, ...
        "component_anchors/"+name+"/"),:);
    assert(height(row)==1 && row.source_csv_exists && ...
        contains(row.source_csv,"component_anchors/"+name+"/"), ...
        'Component source paths were rebound to the parent run or another component.');
end
v=sixgr.visual.verifyVisualArtifacts(root);
assert(height(v)==2 && all(v.IntegrityOk));
% A real, readable raster without a source binding must still fail.
orphan=fullfile(root,'orphan.png');
imwrite(uint8(mod(2*x+y,256)),orphan);
a=sixgr.validation.auditRunArtifacts(root,'WriteOutputs',false);
assert(a.ImageFailureCount==1 && ...
    any(a.ImageAuditTable.failure_code=="unmanifested_visual_artifact"));
fprintf('NUMERICAL_COMPONENT_LINEAGE_FIXTURE=%s\n',root);
ok=true;
end
