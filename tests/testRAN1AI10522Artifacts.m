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
hashes=string(F.PNGSHA256);
replay=sixgr.studies.ran1ai10522.runTDocSuite("figure_replay","RunFolder",folder);
F2=readtable(fullfile(folder,"manifests","figure_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(replay.Passed && isequal(hashes,string(F2.PNGSHA256)));
fprintf("RAN1 10.5.2.2 artifacts: 14/14 PNGs and deterministic replay hashes pass.\n");
ok=true;
end
