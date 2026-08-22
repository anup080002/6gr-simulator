function ok=testUL10523QuickArtifacts()
%TESTUL10523QUICKARTIFACTS One actual PUSCH TB plus complete honest manifests.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
runId="focused_"+string(datetime("now","Format","yyyyMMdd_HHmmss_SSS"));
relRoot="results/tdoc_ul_10523/focused_tests";
root=fileparts(fileparts(mfilename("fullpath")));
folder=fullfile(root,relRoot,runId);
cleanup=onCleanup(@()localCleanup(folder)); %#ok<NASGU>
out=runRAN1UL10523TDocStudy("quick","OutputRoot",relRoot,"RunId",runId);
assert(out.Passed && ~out.PublicationQualified);
assert(out.ActualWaveform.TrialCount==1 && out.ActualWaveform.SNRPointCount==1);
assert(height(out.FigureManifest)==22 && all(out.FigureManifest.Status=="PASS"));
assert(numel(dir(fullfile(out.RunFolder,"**","*.png")))>=25, ...
    "Expected 22 TFIG PNGs plus actual PUSCH diagnostic plots.");
assert(isempty(dir(fullfile(out.RunFolder,"**","*.svg"))) && ...
    isempty(dir(fullfile(out.RunFolder,"**","*.pdf"))));
status=readtable(fullfile(out.RunFolder,"manifests","figure_contract_status.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(height(status)==86 && nnz(status.Status=="PASS")==22 && nnz(status.Status=="BLOCKED")==64);
trials=readtable(fullfile(out.RunFolder,replace(out.ActualWaveform.RelativeRunFolder,"/",filesep), ...
    "transport_block_trials.csv"),"Delimiter",",","VariableNamingRule","preserve");
truth=readtable(fullfile(out.RunFolder,replace(out.ActualWaveform.RelativeRunFolder,"/",filesep), ...
    "truth_contract.csv"),"Delimiter",",","VariableNamingRule","preserve");
assert(height(trials)==1 && all(trials.CRCSource=="decoded_transport_block_crc") && ...
    ~any(truth{1,["UsesBLERLookupTable","UsesSyntheticBLER", ...
    "UsesRandomPassFailModel","UsesGeometryAsLLS"]}));
localAssertError(@()runRAN1UL10523TDocStudy("sls"),"sixgr:tdoc:ul10523:GenuineSLSUnavailable");
ok=true; fprintf("UL10523QuickArtifacts: 1 actual TB, 22 source-backed TFIG PNGs, 64 blocked RFIG rows PASS.\n");
end
function localAssertError(f,id)
try,f();catch ME,assert(strcmp(ME.identifier,id),"Expected %s, got %s",id,ME.identifier);return;end
error("testUL10523QuickArtifacts:MissingError","Expected typed error %s.",id);
end
function localCleanup(path),if isfolder(path),rmdir(path,"s");end,end
