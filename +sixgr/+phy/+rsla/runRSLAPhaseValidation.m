function summary = runRSLAPhaseValidation(varargin)
%RUNRSLAPHASEVALIDATION Execute bounded strict RSLA component/waveform evidence.

p = inputParser;
p.FunctionName = "sixgr.phy.rsla.runRSLAPhaseValidation";
addParameter(p,"VectorRoot","",@(x)ischar(x)||isstring(x));
addParameter(p,"OutputDir","",@(x)ischar(x)||isstring(x));
addParameter(p,"SeedList",[11 23 47 89],@isnumeric);
addParameter(p,"ConfidenceLevel",0.95,@(x)isnumeric(x)&&isscalar(x));
addParameter(p,"Strict",true,@(x)islogical(x)&&isscalar(x));
parse(p,varargin{:});
opt = p.Results;
if ~opt.Strict
    error("RSLA:StrictProfileRequired","RSLA evidence requires Strict=true.");
end
vectorRoot = string(opt.VectorRoot);
outputDir = string(opt.OutputDir);
if strlength(vectorRoot)==0 || ~isfolder(vectorRoot)
    error("RSLA:MissingVectorInput","VectorRoot must identify the RSLA pack.");
end
if strlength(outputDir)==0
    error("RSLA:MissingArtifact","OutputDir is mandatory.");
end
if ~isfolder(outputDir), mkdir(outputDir); end

runID = "RSLA_PHASE09_R18";
csvContract = sixgr.phy.rsla.RSLAUtil.readStrings(fullfile( ...
    vectorRoot,"desired_rsla_csv_contract.csv"));
imageContract = sixgr.phy.rsla.RSLAUtil.readStrings(fullfile( ...
    vectorRoot,"desired_rsla_image_contract.csv"));

[tables,evidence] = sixgr.phy.rsla.RSLABaseEvidenceBuilder.build( ...
    vectorRoot,csvContract,runID,opt.SeedList,opt.ConfidenceLevel);
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
    outputDir,"rsla_image_semantic_audit.csv",audit);
rowCounts.rsla_image_semantic_audit = height(audit);
hashes.rsla_image_semantic_audit = sixgr.phy.rsla.RSLAUtil.fileHash( ...
    fullfile(outputDir,"rsla_image_semantic_audit.csv"));

profile = sixgr.phy.rsla.RSLASpecificationProfile.strictR18();
matlabVersion = string(version);
toolbox = ver("5g");
if isempty(toolbox)
    error("RSLA:Missing5GToolbox","5G Toolbox is required.");
end
gitCommit = localGitCommit();
manifest = sixgr.phy.rsla.RSLAUtil.contractTable( ...
    csvContract,"rsla_run_manifest.csv",1);
manifest.RunID = runID;
manifest.ProfileID = profile.ProfileID;
manifest.MATLABVersion = matlabVersion;
manifest.ToolboxVersion = string(toolbox.Version);
manifest.GitCommit = gitCommit;
manifest.VectorManifestSHA256 = sixgr.phy.rsla.RSLAUtil.fileHash( ...
    fullfile(vectorRoot,"independent_vector_manifest.json"));
manifest.ConfigurationSHA256 = sixgr.phy.rsla.RSLAUtil.hash(profile);
manifest.SeedList = join(string(opt.SeedList),"|");
manifest.StartTime = evidence.StartTime;
manifest.EndTime = string(datetime("now","TimeZone","UTC"));
manifest.Status = "PASS";
sixgr.phy.rsla.RSLAArtifactExporter.writeTable( ...
    outputDir,"rsla_run_manifest.csv",manifest);
rowCounts.rsla_run_manifest = height(manifest);
hashes.rsla_run_manifest = sixgr.phy.rsla.RSLAUtil.fileHash( ...
    fullfile(outputDir,"rsla_run_manifest.csv"));

expectedCSV = string(csvContract.FileName);
expectedPNG = string(imageContract.ImageFile);
csvPresent = arrayfun(@(x)exist(fullfile(outputDir,x),"file")==2,expectedCSV);
pngPresent = arrayfun(@(x)exist(fullfile(outputDir,x),"file")==2,expectedPNG);
passed = all(csvPresent)&&all(pngPresent)&& ...
    evidence.IndependentMismatchCount==0&&evidence.Failures==0;
summary = struct("Passed",passed,"Strict",true,"RunID",runID, ...
    "OutputDir",outputDir,"CSVCount",sum(csvPresent), ...
    "PNGCount",sum(pngPresent),"RowCounts",rowCounts, ...
    "CSVHashes",hashes, ...
    "CapabilityExecuteCount",evidence.CapabilityExecuteCount, ...
    "CapabilityRejectCount",evidence.CapabilityRejectCount, ...
    "IndependentMismatchCount",evidence.IndependentMismatchCount, ...
    "ComponentTrials",evidence.ComponentTrials, ...
    "ComponentFailures",evidence.Failures, ...
    "ExecutionBackend","production_components_with_bounded_waveform_kernels", ...
    "ApproximationMode","calibration_and_impact_study_not_full_waveform_truth", ...
    "TruthQualified",false,"Status", ...
    sixgr.phy.rsla.RSLAUtil.status(passed));
end

function value = localGitCommit()
[status,output] = system("git rev-parse HEAD");
if status==0, value = strtrim(string(output)); else, value = "unknown"; end
end

function row = localAuditRow()
row = struct("ImageFile","","SourceCSV","","SourceCSVSHA256","", ...
    "PNGSHA256","","Width",NaN,"Height",NaN,"Title","", ...
    "XLabel","","YLabel","","AxesCount",NaN,"SeriesCount",NaN, ...
    "FinitePointCount",NaN,"Status","");
end
