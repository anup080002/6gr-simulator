function value = buildPUCCHImpactManifest( ...
        runID,matrixPath,seedList,confidence)
%BUILDPUCCHIMPACTMANIFEST Build the hash-bound impact run manifest.

[status,commit]=system("git rev-parse HEAD");
if status~=0||strlength(strtrim(string(commit)))==0
    commit="unknown_worktree";
end
toolbox=ver("5g");
if isempty(toolbox)
    toolboxVersion="unavailable";
else
    toolboxVersion=string(toolbox(1).Version);
end
value=table(string(runID),strtrim(string(commit)),string(version), ...
    toolboxVersion,join(string(seedList),"|"),double(confidence), ...
    sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(matrixPath), ...
    "PASS",'VariableNames',{'RunID','GitCommit','MATLABVersion', ...
    'ToolboxVersion','SeedList','ConfidenceLevel', ...
    'ExperimentMatrixSHA256','Status'});
end
