function ok=testRachTdoc10512Analytical()
%TESTRACHTDOC10512ANALYTICAL Exact arithmetic and artifact lineage guard.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp=string(tempname); mkdir(tmp); cleanup=onCleanup(@()localCleanup(tmp)); %#ok<NASGU>
result=runRACHTDocStudyAnalytical( ...
    fullfile("simulator","configs","rach_tdoc10512","campaign_analytical.yaml"), ...
    "OutputRoot",tmp,"RunID","analytical_unit");
assert(result.Passed);
assert(height(result.AnalyticalArtifacts)==24,"Expected 11 tables and 13 figures.");
assert(nnz(endsWith(result.AnalyticalArtifacts.RelativePath,".png"))==13);
assert(all(result.TaskStatus.Status(1:13)=="COMPLETE"));
assert(all(result.TaskStatus.Status(14:end)=="NOT_EXECUTED"));

timing=result.AnalyticalData.PreambleTiming;
b4=timing(timing.FormatID=="NR_B4",:);
assert(abs(b4.TotalDurationUs-(15.2+400+12.9))<1e-12);
collision=result.AnalyticalData.Collision;
r=collision(collision.PreambleCount==64&collision.AttemptsPerRO==2,:);
assert(abs(r.TaggedCollisionProbability-1/64)<1e-12);
sbfd=result.AnalyticalData.SBFDFit;
r=sbfd(sbfd.ULSubbandMHz==20&sbfd.EdgeGuardPRBs==1,:);
assert(r.MaximumFDMROs==floor((20-2*.36)/4.32));
assert(isfile(fullfile(result.RunFolder,"manifest.json")));
assert(isfile(fullfile(result.RunFolder,"manifest.csv")));
ok=true;
fprintf('testRachTdoc10512Analytical: PASS\n');
end

function localCleanup(path)
if isfolder(path), rmdir(path,"s"); end
end
