function ok = test6GScenarioMatrixRunnerNoSummary()
%TEST6GSCENARIOMATRIXRUNNERNOSUMMARY Bounded no-summary matrix task.

setup6GRSimToolkit("Verbose",false);
previousScratch=string(getenv("SIXGR_REGRESSION_SCRATCH_ROOT"));
scratchRoot=previousScratch;
ownsScratchRoot=strlength(strtrim(scratchRoot))==0;
if ownsScratchRoot
    scratchRoot=string(tempname);
    mkdir(scratchRoot);
    setenv("SIXGR_REGRESSION_SCRATCH_ROOT",scratchRoot);
elseif ~isfolder(scratchRoot)
    mkdir(scratchRoot);
end
scratchCleanup=onCleanup(@()localRestoreScratch(previousScratch,scratchRoot,ownsScratchRoot)); %#ok<NASGU>
tmp=localScratchChild(scratchRoot,"n",ownsScratchRoot);
mkdir(tmp);
cleanup=onCleanup(@()localRemoveFolder(tmp)); %#ok<NASGU>

scenario=fullfile(tmp,"scenario_no_summary.json");
payload=struct( ...
    "inherits",{{fullfile(pwd,"simulator","configs","scenarios", ...
        "prach_detection.yaml")}}, ...
    "meta",struct("scenario_id","matrix_prach_no_summary", ...
        "description","bounded no-summary matrix task","version","1", ...
        "owner","test","maturity_tag","smoke"), ...
    "simulation",struct("monte_carlo_iterations",1,"random_seed",7), ...
    "run_control",struct("num_workers",1), ...
    "output",struct("save_figures",false));
sixgr.integration.qualification.QualificationAtomicWriter. ...
    writeText(scenario,string(jsonencode(payload)));

matrixPath=fullfile(tmp,"matrix_no_summary.yaml");
lines=["meta:";"  matrix_id: smoke_matrix_nosummary"; ...
    "  description: bounded no-summary matrix task";"execution:"; ...
    "  stop_on_failure: false";"  max_parallel_jobs: 1"; ...
    "  repeat_count: 1";"  save_combined_summary: false"; ...
    "scenarios:";"  - "+replace(string(scenario),"\","/")];
sixgr.integration.qualification.QualificationAtomicWriter. ...
    writeText(matrixPath,strjoin(lines,newline)+newline);

out=run_6g_phy_lls_matrix(matrixPath,tmp,"nosummary");
assert(out.Ok,"No-summary matrix task must complete.");
if strlength(strtrim(scratchRoot))>0
    assert(localPathStartsWith(out.RunFolder,tmp), ...
        "Regression matrix output must remain inside its configured task scratch root.");
end
assert(strlength(string(out.SummaryCSV))==0, ...
    "Matrix runner must omit SummaryCSV when save_combined_summary=false.");
assert(isfile(out.ScenarioSummaryCSV), ...
    "No-summary matrix task must retain its scenario evidence.");
ok=true;
end

function tf=localPathStartsWith(pathValue,rootValue)
pathValue=replace(string(pathValue),"/",filesep);
rootValue=replace(string(rootValue),"/",filesep);
if ispc
    pathValue=lower(pathValue);
    rootValue=lower(rootValue);
end
tf=pathValue==rootValue || startsWith(pathValue,rootValue+filesep);
end

function localRestoreScratch(previousScratch,scratchRoot,ownsScratchRoot)
setenv("SIXGR_REGRESSION_SCRATCH_ROOT",previousScratch);
if ownsScratchRoot
    localRemoveFolder(scratchRoot);
end
end

function pathValue=localScratchChild(scratchRoot,prefix,ownsScratchRoot)
if ownsScratchRoot
    pathValue=fullfile(scratchRoot,prefix);
else
    token=char(java.util.UUID.randomUUID());
    pathValue=fullfile(scratchRoot,prefix+string(token(1:8)));
end
end

function localRemoveFolder(pathValue)
if isfolder(pathValue)
    rmdir(pathValue,"s");
end
end
