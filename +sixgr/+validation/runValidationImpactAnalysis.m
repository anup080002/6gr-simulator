function summary=runValidationImpactAnalysis(varargin)
%RUNVALIDATIONIMPACTANALYSIS Validate the impact design and fail closed.

parser=inputParser;
parser.addParameter("ExperimentMatrix",fullfile(pwd,"tests","vectors", ...
    "validation","validation_impact_experiment_matrix.csv"));
parser.addParameter("OutputDir",fullfile(pwd,"artifacts","validation_impact"));
parser.addParameter("SeedList",[11 23 47 89 131 197]);
parser.addParameter("ConfidenceLevel",0.95);
parser.addParameter("Strict",true,@(x)islogical(x)&&isscalar(x));
parser.parse(varargin{:});
outputDir=char(string(parser.Results.OutputDir));
sixgr.util.ensureFolder(outputDir);
matrix=readtable(parser.Results.ExperimentMatrix,"TextType","string", ...
    "Delimiter",",");
families=unique(string(matrix.FamilyID));
pairs=unique(string(matrix.PairID));
designOK=height(matrix)==768&&numel(families)==64&&numel(pairs)==384;
pairingOK=true;
for pair=reshape(pairs,1,[])
    rows=matrix(string(matrix.PairID)==pair,:);
    pairingOK=pairingOK&&height(rows)==2&& ...
        numel(unique(string(rows.Arm)))==2&& ...
        numel(unique(double(rows.Seed)))==1;
end
vectorRoot=fileparts(char(string(parser.Results.ExperimentMatrix)));
rules=readtable(fullfile(vectorRoot,"validation_impact_acceptance_rules.csv"), ...
    "TextType","string","Delimiter",",");
ruleCount=height(rules);
baseGate=fullfile(pwd,"artifacts","validation_phase", ...
    "validation_phase14_gate_report.csv");
basePassed=false;
if isfile(baseGate)
    base=readtable(baseGate,"TextType","string");
    basePassed=all(string(base.Status)=="PASS");
end
gate=["ExperimentMatrix";"PairingContract";"AcceptanceRules"; ...
    "BasePhase";"ImpactExecution";"ImpactArtifacts"];
status=["FAIL";"FAIL";"FAIL";"FAIL";"FAIL";"FAIL"];
reason=["";"";"";"";"";""];
if designOK, status(1)="PASS"; else, reason(1)="expected_768_experiments_64_families_384_pairs"; end
if pairingOK, status(2)="PASS"; else, reason(2)="baseline_treatment_pairing_mismatch"; end
if ruleCount==96, status(3)="PASS"; else, reason(3)="expected_96_acceptance_rules"; end
if basePassed, status(4)="PASS"; else, reason(4)="base_validation_phase_not_passed"; end
reason(5)="impact_experiments_not_executed";
reason(6)="contracted_impact_artifacts_not_generated";
gateTable=table(gate,true(6,1),status,reason, ...
    'VariableNames',["GateName","Required","Status","FailureReason"]);
gatePath=fullfile(outputDir,"validation_impact_gate_report.csv");
sixgr.util.csvWriteTable(gatePath,gateTable);
summary=struct("Passed",all(status=="PASS"), ...
    "ExperimentCount",height(matrix),"FamilyCount",numel(families), ...
    "PairCount",numel(pairs),"RuleCount",ruleCount, ...
    "GateTable",gateTable,"GateReport",string(gatePath), ...
    "OutputDir",string(outputDir));
if parser.Results.Strict&&~summary.Passed
    warning("sixgr:validation:ImpactIncomplete", ...
        "Validation impact remains fail-closed; inspect %s.",gatePath);
end
end
