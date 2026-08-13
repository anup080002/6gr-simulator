function ok=testRAN1AI10522Artifacts()
%TESTRAN1AI10522ARTIFACTS Deterministic CSV/PNG/hash/replay gate.
setup6GRSimToolkit("Verbose",false);
root=fullfile(tempdir,"sixgr_ran1_10522_artifact_test"); runId="artifact_gate";
r=sixgr.studies.ran1ai10522.runTDocSuite("deterministic", ...
    "OutputRoot",root,"RunId",runId);
assert(r.Passed && ~r.PublicationQualified);
folder=fullfile(root,runId);
F=readtable(fullfile(folder,"manifests","figure_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(height(F)==14 && all(F.Status=="PASS") && all(F.RasterOnly));
assert(isempty(dir(fullfile(folder,"**","*.svg"))) && isempty(dir(fullfile(folder,"**","*.pdf"))));
M=readtable(fullfile(folder,"manifests","artifact_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
relativePaths=string(M.RelativePath);
assert(all(~startsWith(relativePaths,"/") & ~startsWith(relativePaths,"\\") & ...
    ~contains(relativePaths,":") & ~startsWith(relativePaths,"_main/")), ...
    "Artifact manifest paths must be run-root-relative on every launch path.");
hashes=string(F.PNGSHA256);
sourceManifest=readtable(fullfile(folder,"manifests","resolved_config_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
sourceEnvironment=readtable(fullfile(folder,"manifests","environment_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
replay=sixgr.studies.ran1ai10522.runTDocSuite("figure_replay","RunFolder",folder);
F2=readtable(fullfile(folder,"manifests","figure_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(replay.Passed && isequal(hashes,string(F2.PNGSHA256)));
M2=readtable(fullfile(folder,"manifests","artifact_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(all(string(M2.ConfigHash)==string(sourceManifest.ConfigHash(1))));
summary=fileread(fullfile(folder,"run_summary.md"));
assert(contains(summary,"Artifact integrity gate: `1`"));
assert(contains(summary,sprintf("Git worktree dirty observed: `%d`", ...
    logical(sourceEnvironment.GitWorktreeDirtyObserved(1)))));
fprintf("RAN1 10.5.2.2 artifacts: 14/14 PNGs and deterministic replay hashes pass.\n");
ok=true;
end
