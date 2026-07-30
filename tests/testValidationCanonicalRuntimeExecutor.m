function tests = testValidationCanonicalRuntimeExecutor
%TESTVALIDATIONCANONICALRUNTIMEEXECUTOR Canonical Phase-14 workload guards.
tests = functiontests(localfunctions);
end

function testDLAndULFixedLinkWorkloadsReturnTruthEvidence(testCase)
setup6GRSimToolkit("Verbose",false);
root = string(tempname);
mkdir(root);
cleanup = onCleanup(@()localCleanup(root)); %#ok<NASGU>
repositoryRoot = fileparts(fileparts(mfilename("fullpath")));
vectorRoot = fullfile(repositoryRoot,"tests","vectors","validation");
result = sixgr.validation.ValidationCanonicalRuntimeExecutor.run( ...
    vectorRoot,root);
verifyTrue(testCase,result.Passed);
verifyEqual(testCase,height(result.Scenarios),5);
verifyEqual(testCase,result.Scenarios.Status,repmat("PASS",5,1));
fixed = ismember(result.MeasuredSINR.TaskID, ...
    ["DL_FIXED_LINK-"+string(1:12), ...
     "UL_FIXED_LINK-"+string(1:12)]);
verifyEqual(testCase,nnz(fixed),20);
verifyTrue(testCase,all(isfinite(result.MeasuredSINR.MeasuredSINR_dB)));
verifyEqual(testCase,unique(result.MeasuredSINR.ProvenanceClass), ...
    "DECODED_RECEIVER_STATE");
end

function localCleanup(root)
if isfolder(root)
    rmdir(root,"s");
end
end
