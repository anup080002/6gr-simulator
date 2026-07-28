function summary = runWaveformImpactAnalysis(varargin)
%RUNWAVEFORMIMPACTANALYSIS Execute 768 paired waveform impact rows.

ip=inputParser;
ip.FunctionName="sixgr.phy.waveform.runWaveformImpactAnalysis";
ip.addParameter("ExperimentMatrix","",@(x)ischar(x)||isstring(x));
ip.addParameter("OutputDir","",@(x)ischar(x)||isstring(x));
ip.addParameter("VectorRoot","",@(x)ischar(x)||isstring(x));
ip.addParameter("BaseArtifactDir","",@(x)ischar(x)||isstring(x));
ip.addParameter("SeedList",[11 23 47 89 131 197],@isnumeric);
ip.addParameter("ConfidenceLevel",.95,@(x)isnumeric(x)&&isscalar(x));
ip.addParameter("Strict",true,@(x)islogical(x)&&isscalar(x));
ip.parse(varargin{:});
opt=ip.Results;
if ~opt.Strict
    error("WAVEFORM:StrictProfileRequired", ...
        "Waveform impact evidence requires Strict=true.");
end
matrixPath=string(opt.ExperimentMatrix);
if strlength(matrixPath)==0||~isfile(matrixPath)
    error("WAVEFORM:ImpactExperimentIncomplete", ...
        "ExperimentMatrix must identify the 768-row matrix.");
end
vectorRoot=string(opt.VectorRoot);
if strlength(vectorRoot)==0,vectorRoot=string(fileparts(matrixPath));end
outputDir=string(opt.OutputDir);
if strlength(outputDir)==0
    error("WAVEFORM:MissingArtifactEvidence","OutputDir is mandatory.");
end
baseDir=string(opt.BaseArtifactDir);
if strlength(baseDir)==0
    baseDir=fullfile(fileparts(outputDir),"waveform_generation_phase");
end
if ~isfolder(baseDir)
    error("WAVEFORM:MissingArtifactEvidence", ...
        "Base waveform evidence must pass before impact execution.");
end
if ~isfolder(outputDir),mkdir(outputDir);end
contract=localRead(fullfile(vectorRoot,"desired_waveform_impact_csv_contract.csv"));
images=localRead(fullfile(vectorRoot,"desired_waveform_impact_image_contract.csv"));
localRemoveTargets(outputDir,[contract.FileName;images.ImageFile]);
tables=sixgr.phy.waveform.WaveformImpactEvidenceBuilder.build( ...
    matrixPath,vectorRoot,baseDir,double(opt.SeedList), ...
    double(opt.ConfidenceLevel));
auditName="waveform_impact_image_semantic_audit.csv";
hashes=sixgr.phy.waveform.WaveformArtifactExporter.writeTables( ...
    outputDir,tables,contract(contract.FileName~=auditName,:));
tables.waveform_impact_image_semantic_audit= ...
    sixgr.phy.waveform.WaveformArtifactExporter.writeFigures( ...
    outputDir,images);
auditHash=sixgr.phy.waveform.WaveformArtifactExporter.writeTables( ...
    outputDir,tables,contract(contract.FileName==auditName,:));
hashes.waveform_impact_image_semantic_audit= ...
    auditHash.waveform_impact_image_semantic_audit;
csvPresent=isfile(fullfile(outputDir,contract.FileName));
pngPresent=isfile(fullfile(outputDir,images.ImageFile));
raw=tables.waveform_impact_raw_trials;
rules=tables.waveform_impact_rule_evaluation;
passed=all(csvPresent)&&all(pngPresent)&&height(raw)==768&& ...
    numel(unique(raw.PairID))==384&&all(raw.Status=="PASS")&& ...
    height(rules)==96&&all(rules.Result=="PASS");
versions=sixgr.phy.waveform.WaveformSpecificationProfile.environment();
summary=struct("Passed",logical(passed),"Strict",true, ...
    "RunID","WAVEFORM_IMPACT_PHASE13","OutputDir",outputDir, ...
    "CSVCount",sum(csvPresent),"PNGCount",sum(pngPresent), ...
    "ExperimentCount",height(raw),"PairCount",numel(unique(raw.PairID)), ...
    "RuleCount",height(rules),"CSVHashes",hashes, ...
    "MATLABVersion",versions.MATLABVersion, ...
    "ToolboxVersion",versions.ToolboxVersion, ...
    "ExecutionBackend","paired_canonical_waveform_experiments", ...
    "ApproximationMode","none","Status",localStatus(passed));
if opt.Strict&&~passed
    error("WAVEFORM:ImpactValidationFailed", ...
        "Waveform impact evidence did not pass every strict gate.");
end
end

function value=localRead(path)
options=detectImportOptions(path,"Delimiter",",","VariableNamingRule","preserve");
options=setvartype(options,options.VariableNames,"string");
value=readtable(path,options);
end

function localRemoveTargets(outputDir,names)
for name=reshape(string(names),1,[])
    path=fullfile(outputDir,name);
    if isfile(path),delete(path);end
end
end

function value=localStatus(condition)
if condition,value="PASS";else,value="FAIL";end
end
