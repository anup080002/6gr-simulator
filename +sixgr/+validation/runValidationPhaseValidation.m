function summary=runValidationPhaseValidation(varargin)
%RUNVALIDATIONPHASEVALIDATION Execute Phase-14 gates without fabricated evidence.

parser=inputParser;
parser.addParameter("VectorRoot",fullfile(pwd,"tests","vectors","validation"));
parser.addParameter("OutputDir",fullfile(pwd,"artifacts","validation_phase"));
parser.addParameter("ConfidenceLevels",[0.90 0.95 0.99]);
parser.addParameter("SeedList",[11 23 47 89]);
parser.addParameter("Strict",true,@(x)islogical(x)&&isscalar(x));
parser.parse(varargin{:});
vectorRoot=char(string(parser.Results.VectorRoot));
outputDir=char(string(parser.Results.OutputDir));
sixgr.util.ensureFolder(outputDir);

gateName=["IndependentVectorPack";"CanonicalMATLABTests"; ...
    "IndependentOracleArtifacts";"FreshCanonicalScenarios"; ...
    "ContractedArtifacts";"PublicationGate"];
required=true(6,1); status=repmat("FAIL",6,1);
failureReason=repmat("",6,1); evidenceArtifact=repmat("",6,1);

verifier=fullfile(vectorRoot,"verify_validation_vector_pack.py");
command=sprintf('python "%s" "%s"',verifier,vectorRoot);
[vectorExit,vectorOutput]=system(command);
evidenceArtifact(1)=string(verifier);
if vectorExit==0, status(1)="PASS";
else, failureReason(1)="independent_vector_verifier_exit_"+string(vectorExit);
end

results=runtests(fullfile(pwd,"tests","testValidationPhase14.m"));
evidenceArtifact(2)="tests/testValidationPhase14.m";
if ~isempty(results)&&all([results.Passed])
    status(2)="PASS";
else
    failureReason(2)="required_phase14_matlab_tests_failed";
end

oracle=readtable(fullfile(vectorRoot,"validation_oracle_registry_vectors.csv"), ...
    "TextType","string","Delimiter",",");
sixgr.validation.IndependentOracleRegistry.validate(oracle);
qualifying=lower(oracle.ExpectedQualifiesForMandatoryGate)=="true";
exists=false(height(oracle),1);
for index=1:height(oracle)
    exists(index)=isfile(fullfile(vectorRoot,oracle.ArtifactPath(index)));
end
evidenceArtifact(3)="validation_oracle_registry_vectors.csv";
if all(exists(qualifying))
    status(3)="PASS";
else
    failureReason(3)="missing_independent_oracle_artifacts="+ ...
        string(nnz(~exists&qualifying));
end

failureReason(4)="fresh_canonical_runtime_scenarios_not_supplied";
failureReason(5)="contracted_artifacts_with_runtime_lineage_not_generated";
failureReason(6)="publication_gate_requires_all_prior_runtime_gates";

gateTable=table(gateName,required,status,failureReason,evidenceArtifact, ...
    'VariableNames',["GateName","Required","Status","FailureReason", ...
    "EvidenceArtifact"]);
gatePath=fullfile(outputDir,"validation_phase14_gate_report.csv");
sixgr.util.csvWriteTable(gatePath,gateTable);
logPath=fullfile(outputDir,"validation_vector_verifier.log");
fid=fopen(logPath,"w","n","UTF-8");
if fid>=0, fprintf(fid,"%s",vectorOutput); fclose(fid); end

summary=struct("Passed",all(status=="PASS"), ...
    "VectorVerifierExitCode",double(vectorExit), ...
    "MATLABTestCount",numel(results), ...
    "MATLABPassedCount",nnz([results.Passed]), ...
    "MissingQualifyingOracleArtifacts",nnz(~exists&qualifying), ...
    "GateTable",gateTable,"GateReport",string(gatePath), ...
    "OutputDir",string(outputDir));
if parser.Results.Strict && ~summary.Passed
    warning("sixgr:validation:PhaseIncomplete", ...
        "Phase-14 remains fail-closed; inspect %s.",gatePath);
end
end
