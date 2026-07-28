function summary = runWaveformPhaseValidation(varargin)
%RUNWAVEFORMPHASEVALIDATION Execute strict Phase-13 production evidence.

ip=inputParser;
ip.FunctionName="sixgr.phy.waveform.runWaveformPhaseValidation";
ip.addParameter("VectorRoot","",@(x)ischar(x)||isstring(x));
ip.addParameter("OutputDir","",@(x)ischar(x)||isstring(x));
ip.addParameter("SeedList",[11 23 47 89],@isnumeric);
ip.addParameter("ConfidenceLevel",.95,@(x)isnumeric(x)&&isscalar(x));
ip.addParameter("Strict",true,@(x)islogical(x)&&isscalar(x));
ip.parse(varargin{:});
opt=ip.Results;
if ~opt.Strict
    error("WAVEFORM:StrictProfileRequired", ...
        "Phase-13 evidence requires Strict=true.");
end
vectorRoot=string(opt.VectorRoot);outputDir=string(opt.OutputDir);
if strlength(vectorRoot)==0||~isfolder(vectorRoot)
    error("WAVEFORM:IndependentVectorMissing", ...
        "VectorRoot must identify the verified waveform vector pack.");
end
if strlength(outputDir)==0
    error("WAVEFORM:MissingArtifactEvidence", ...
        "OutputDir is mandatory.");
end
if ~isfolder(outputDir),mkdir(outputDir);end
contract=localRead(fullfile(vectorRoot,"desired_waveform_csv_contract.csv"));
imageContract=localRead(fullfile(vectorRoot,"desired_waveform_image_contract.csv"));
localRemoveTargets(outputDir,[contract.FileName;imageContract.ImageFile]);

tables=sixgr.phy.waveform.WaveformPhaseEvidenceBuilder.build( ...
    vectorRoot,double(opt.SeedList),double(opt.ConfidenceLevel));
auditName="waveform_image_semantic_audit.csv";
nonAudit=contract(contract.FileName~=auditName,:);
hashes=sixgr.phy.waveform.WaveformArtifactExporter.writeTables( ...
    outputDir,tables,nonAudit);
tables.waveform_image_semantic_audit= ...
    sixgr.phy.waveform.WaveformArtifactExporter.writeFigures( ...
    outputDir,imageContract);
auditContract=contract(contract.FileName==auditName,:);
auditHash=sixgr.phy.waveform.WaveformArtifactExporter.writeTables( ...
    outputDir,tables,auditContract);
hashes.waveform_image_semantic_audit= ...
    auditHash.waveform_image_semantic_audit;

csvPresent=isfile(fullfile(outputDir,string(contract.FileName)));
pngPresent=isfile(fullfile(outputDir,string(imageContract.ImageFile)));
tableNames=string(fieldnames(tables));
allRowsPass=true;
rowCounts=struct();
for index=1:numel(tableNames)
    value=tables.(tableNames(index));
    rowCounts.(tableNames(index))=height(value);
    if ismember("Status",string(value.Properties.VariableNames))
        allRowsPass=allRowsPass&&all(upper(string(value.Status))=="PASS");
    end
end
capability=tables.waveform_capability_results;
executeCount=sum(capability.ActualOutcome=="EXECUTE");
rejectCount=sum(capability.ActualOutcome=="REJECT");
mismatches=sum(tables.waveform_independent_vector_results.MismatchCount);
versions=sixgr.phy.waveform.WaveformSpecificationProfile.environment();
passed=all(csvPresent)&&all(pngPresent)&&allRowsPass&& ...
    mismatches==0&&height(capability)==180;
summary=struct( ...
    "Passed",logical(passed), ...
    "Strict",true, ...
    "RunID","WAVEFORM_PHASE13_REL19", ...
    "OutputDir",outputDir, ...
    "CSVCount",sum(csvPresent), ...
    "PNGCount",sum(pngPresent), ...
    "RowCounts",rowCounts, ...
    "CSVHashes",hashes, ...
    "CapabilityExecuteCount",executeCount, ...
    "CapabilityRejectCount",rejectCount, ...
    "IndependentMismatchCount",mismatches, ...
    "MATLABVersion",versions.MATLABVersion, ...
    "MATLABRelease",versions.MATLABRelease, ...
    "ToolboxVersion",versions.ToolboxVersion, ...
    "ExecutionBackend","canonical_waveform_and_independent_math", ...
    "ApproximationMode","none", ...
    "Status",localStatus(passed));
if opt.Strict&&~passed
    error("WAVEFORM:PhaseValidationFailed", ...
        "Waveform Phase-13 evidence did not pass every strict gate.");
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
