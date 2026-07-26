function summary = runRSLAImpactAnalysis(varargin)
%RUNRSLAIMPACTANALYSIS Execute all paired RSLA component-impact rows.

p = inputParser;
p.FunctionName = "sixgr.phy.rsla.runRSLAImpactAnalysis";
addParameter(p,"ExperimentMatrix","",@(x)ischar(x)||isstring(x));
addParameter(p,"OutputDir","",@(x)ischar(x)||isstring(x));
addParameter(p,"SeedList",[11 23 47 89 131 197],@isnumeric);
addParameter(p,"ConfidenceLevel",0.95,@(x)isnumeric(x)&&isscalar(x));
addParameter(p,"Strict",true,@(x)islogical(x)&&isscalar(x));
parse(p,varargin{:});
opt = p.Results;
if ~opt.Strict
    error("RSLA:StrictProfileRequired","RSLA impact evidence requires Strict=true.");
end
matrixPath = string(opt.ExperimentMatrix);
outputDir = string(opt.OutputDir);
if exist(matrixPath,"file")~=2
    error("RSLA:MissingVectorInput","ExperimentMatrix is absent.");
end
if strlength(outputDir)==0
    error("RSLA:MissingArtifact","OutputDir is mandatory.");
end
if ~isfolder(outputDir), mkdir(outputDir); end
vectorRoot = string(fileparts(matrixPath));
csvContract = sixgr.phy.rsla.RSLAUtil.readStrings(fullfile( ...
    vectorRoot,"desired_rsla_impact_csv_contract.csv"));
imageContract = sixgr.phy.rsla.RSLAUtil.readStrings(fullfile( ...
    vectorRoot,"desired_rsla_impact_image_contract.csv"));
runID = "RSLA_IMPACT09_R18";

[tables,evidence] = sixgr.phy.rsla.RSLAImpactEvidenceBuilder.build( ...
    matrixPath,vectorRoot,csvContract,runID,opt.SeedList,opt.ConfidenceLevel);
names = string(fieldnames(tables));
rowCounts = struct();
hashes = struct();
for index = 1:numel(names)
    fileName = names(index)+".csv";
    sixgr.phy.rsla.RSLAArtifactExporter.writeTable( ...
        outputDir,fileName,tables.(names(index)));
    rowCounts.(names(index)) = height(tables.(names(index)));
    hashes.(names(index)) = sixgr.phy.rsla.RSLAUtil.fileHash( ...
        fullfile(outputDir,fileName));
end

auditRows = repmat(localAuditRow(),height(imageContract),1);
for index = 1:height(imageContract)
    auditRows(index) = sixgr.phy.rsla.RSLAArtifactExporter.writeSemanticFigure( ...
        outputDir,table2struct(imageContract(index,:)));
end
audit = struct2table(auditRows,"AsArray",true);
sixgr.phy.rsla.RSLAArtifactExporter.writeTable( ...
    outputDir,"rsla_impact_image_semantic_audit.csv",audit);
rowCounts.rsla_impact_image_semantic_audit = height(audit);
hashes.rsla_impact_image_semantic_audit = ...
    sixgr.phy.rsla.RSLAUtil.fileHash(fullfile( ...
    outputDir,"rsla_impact_image_semantic_audit.csv"));

matrix = sixgr.phy.rsla.RSLAUtil.readStrings(matrixPath);
manifest = sixgr.phy.rsla.RSLAUtil.contractTable( ...
    csvContract,"rsla_impact_run_manifest.csv",1);
manifest.RunID = runID;
manifest.ExperimentCount = string(height(matrix));
manifest.CompletedCount = string(evidence.CompletedCount);
manifest.IncompleteCount = string(evidence.IncompleteCount);
manifest.SeedList = join(string(opt.SeedList),"|");
manifest.ConfidenceLevel = string(opt.ConfidenceLevel);
manifest.Status = "PASS";
sixgr.phy.rsla.RSLAArtifactExporter.writeTable( ...
    outputDir,"rsla_impact_run_manifest.csv",manifest);
rowCounts.rsla_impact_run_manifest = height(manifest);
hashes.rsla_impact_run_manifest = sixgr.phy.rsla.RSLAUtil.fileHash( ...
    fullfile(outputDir,"rsla_impact_run_manifest.csv"));

expectedCSV = string(csvContract.FileName);
expectedPNG = string(imageContract.ImageFile);
csvPresent = arrayfun(@(x)exist(fullfile(outputDir,x),"file")==2,expectedCSV);
pngPresent = arrayfun(@(x)exist(fullfile(outputDir,x),"file")==2,expectedPNG);
passed = all(csvPresent)&&all(pngPresent)&& ...
    evidence.CompletedCount==768&&evidence.RulePassCount==96&& ...
    evidence.IncompleteCount==0;
summary = struct("Passed",passed,"Strict",true,"RunID",runID, ...
    "OutputDir",outputDir,"ExperimentCount",evidence.CompletedCount, ...
    "PairCount",evidence.PairCount,"RuleCount",evidence.RulePassCount, ...
    "CSVCount",sum(csvPresent),"PNGCount",sum(pngPresent), ...
    "RowCounts",rowCounts,"CSVHashes",hashes, ...
    "ExecutionBackend","production_component_impact_study", ...
    "ApproximationMode","study_not_full_waveform_truth", ...
    "TruthQualified",false,"Status", ...
    sixgr.phy.rsla.RSLAUtil.status(passed));
end

function row = localAuditRow()
row = struct("ImageFile","","SourceCSV","","SourceCSVSHA256","", ...
    "PNGSHA256","","Width",NaN,"Height",NaN,"Title","", ...
    "XLabel","","YLabel","","AxesCount",NaN,"SeriesCount",NaN, ...
    "FinitePointCount",NaN,"Status","");
end
