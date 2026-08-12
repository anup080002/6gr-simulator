function ok=testISAC1083ArtifactVerifier()
%TESTISAC1083ARTIFACTVERIFIER Contract names and fail-closed verification.
contract=sixgr.isac.validationFigureContract();
assert(height(contract)==20);
assert(contract.FigureStem(1)=="WFig17_linear_convolution_validation");
assert(contract.FigureStem(end)=="WFig36_buffer_latency_complexity");
root=string(tempname); mkdir(root); cleanup=onCleanup(@()rmdir(root,"s")); %#ok<NASGU>
mkdir(fullfile(root,"figures")); mkdir(fullfile(root,"aggregate"));
try
    sixgr.isac.verify1083Artifacts(root);
    error("testISAC1083ArtifactVerifier:ExpectedFailure","Verifier accepted missing artifacts.");
catch err
    assert(err.identifier=="sixgr:isac:Missing1083Artifact");
end
report=readtable(fullfile(root,"aggregate","validation_figure_lineage.csv"),"TextType","string");
assert(height(report)==100&&nnz(report.Pass)==0);
fprintf("testISAC1083ArtifactVerifier: PASS (100 fail-closed checks)\n");
ok=true;
end
