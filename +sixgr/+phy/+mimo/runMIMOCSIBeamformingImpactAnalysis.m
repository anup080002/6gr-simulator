function summary = runMIMOCSIBeamformingImpactAnalysis(options)
%RUNMIMOCSIBEAMFORMINGIMPACTANALYSIS Execute the paired Phase-07 matrix.
%
% Passed means the registered component-impact artifact contract passed.
% TruthQualified remains false because this runner intentionally does not
% relabel its correlated sample-domain component channel as CDL/TDL
% PDSCH/PUSCH waveform truth.

arguments
    options.ExperimentMatrix (1,1) string
    options.OutputDir (1,1) string
    options.SeedList (1,:) double {mustBeInteger,mustBeNonnegative} = ...
        [11 23 47 89 131 197]
    options.ConfidenceLevel (1,1) double ...
        {mustBeGreaterThan(options.ConfidenceLevel,0), ...
         mustBeLessThan(options.ConfidenceLevel,1)} = 0.95
    options.Strict (1,1) logical = true
    options.StudyConfig (1,1) string = ""
end

if ~options.Strict
    error("sixgr:mimo:StrictValidationRequired", ...
        "MIMO impact execution requires Strict=true.");
end
if ~isfile(options.ExperimentMatrix)
    error("sixgr:mimo:MissingImpactMatrix", ...
        "ExperimentMatrix does not exist: %s.",options.ExperimentMatrix);
end
repoRoot=fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
if strlength(options.StudyConfig)==0
    options.StudyConfig=fullfile(repoRoot,"simulator","configs", ...
        "validation","mimo_csi_beamforming_impact.yaml");
end
cfg=sixgr.lls6g.config.readConfigFile(options.StudyConfig);
localValidateStudyConfig(cfg);

outputDir=string(java.io.File(char(options.OutputDir)).getCanonicalPath());
if ~isfolder(outputDir)
    [ok,message]=mkdir(outputDir);
    if ~ok
        error("sixgr:mimo:ImpactArtifactWriteFailed", ...
            "Unable to create %s: %s.",outputDir,message);
    end
end
vectorRoot=string(fileparts(options.ExperimentMatrix));
csvContract=localReadStrings(fullfile(vectorRoot, ...
    "desired_mimo_impact_csv_contract.csv"));
imageContract=localReadStrings(fullfile(vectorRoot, ...
    "desired_mimo_impact_image_contract.csv"));
localCleanContracted(outputDir,csvContract,imageContract);

runID="mimo_impact_"+string(datetime("now",TimeZone="UTC", ...
    Format="yyyyMMdd'T'HHmmss'Z'"));
[tables,evidence]=sixgr.phy.mimo.MIMOImpactEvidenceBuilder.build( ...
    options.ExperimentMatrix,vectorRoot,cfg,runID, ...
    options.SeedList,options.ConfidenceLevel);

names=string(fieldnames(tables));
rowCounts=struct();
csvHashes=struct();
for index=1:numel(names)
    fileName=names(index)+".csv";
    sixgr.phy.mimo.MIMOImpactArtifactExporter.writeTable( ...
        outputDir,fileName,tables.(names(index)));
    rowCounts.(names(index))=height(tables.(names(index)));
    csvHashes.(names(index))= ...
        sixgr.phy.mimo.MIMOImpactArtifactExporter.fileHash( ...
        fullfile(outputDir,fileName));
end

auditRows=repmat(localAuditRow(),height(imageContract),1);
for index=1:height(imageContract)
    auditRows(index)= ...
        sixgr.phy.mimo.MIMOImpactArtifactExporter.writeSemanticFigure( ...
        outputDir,table2struct(imageContract(index,:)),runID,cfg);
end
audit=struct2table(auditRows,AsArray=true);
sixgr.phy.mimo.MIMOImpactArtifactExporter.writeTable( ...
    outputDir,"mimo_impact_image_semantic_audit.csv",audit);
rowCounts.mimo_impact_image_semantic_audit=height(audit);
csvHashes.mimo_impact_image_semantic_audit= ...
    sixgr.phy.mimo.MIMOImpactArtifactExporter.fileHash(fullfile( ...
    outputDir,"mimo_impact_image_semantic_audit.csv"));

expectedCSV=string(csvContract.FileName);
expectedPNG=string(imageContract.ImageFile);
csvPresent=arrayfun(@(name)isfile(fullfile(outputDir,name)),expectedCSV);
pngPresent=arrayfun(@(name)isfile(fullfile(outputDir,name)),expectedPNG);
passed=all(csvPresent)&&all(pngPresent)&& ...
    evidence.ExperimentCount==768&&evidence.PairCount==384&& ...
    evidence.RuleCount==96&&evidence.IncompleteCount==0;

summary=struct( ...
    "Passed",logical(passed),"Status",localStatus(passed), ...
    "Strict",true,"RunID",runID,"OutputDir",outputDir, ...
    "StudyConfig",options.StudyConfig, ...
    "ExperimentCount",evidence.ExperimentCount, ...
    "PairCount",evidence.PairCount,"RuleCount",evidence.RuleCount, ...
    "IncompleteCount",evidence.IncompleteCount, ...
    "CSVCount",sum(csvPresent),"PNGCount",sum(pngPresent), ...
    "RowCounts",rowCounts,"CSVHashes",csvHashes, ...
    "ExecutionBackend",evidence.ExecutionBackend, ...
    "ApproximationMode",evidence.ApproximationMode, ...
    "TruthQualified",false);
if ~summary.Passed
    error("sixgr:mimo:IncompleteImpactCampaign", ...
        "MIMO impact campaign did not satisfy its registered component contract.");
end
end

function localValidateStudyConfig(cfg)
required=["evidence.execution_backend","evidence.approximation_mode", ...
    "evidence.truth_qualified","monte_carlo.symbols_per_trial", ...
    "monte_carlo.block_duration_ms","monte_carlo.channel_model", ...
    "statistics.bootstrap_replicates", ...
    "statistics.practical_margin_goodput_mbps", ...
    "covariance.minimum_samples","hybrid.antenna_count", ...
    "hybrid.center_frequency_hz","images.width_pixels", ...
    "images.height_pixels","images.resolution_dpi"];
for field=required
    if isempty(sixgr.util.structGet(cfg,field,[]))
        error("sixgr:mimo:ImpactStudyConfigInvalid", ...
            "StudyConfig requires field %s.",field);
    end
end
if logical(cfg.evidence.truth_qualified)
    error("sixgr:mimo:ImpactTruthRelabelForbidden", ...
        "The component campaign cannot set truth_qualified=true.");
end
if contains(lower(string(cfg.evidence.approximation_mode)),"truth")
    % "not_nr_waveform_truth" is an explicit negative provenance label.
    if ~contains(lower(string(cfg.evidence.approximation_mode)),["not_","not "])
        error("sixgr:mimo:ImpactTruthRelabelForbidden", ...
            "ApproximationMode must not claim waveform truth.");
    end
end
end

function localCleanContracted(outputDir,csvContract,imageContract)
targets=[string(csvContract.FileName);string(imageContract.ImageFile)];
for target=targets.'
    path=fullfile(outputDir,target);
    if isfile(path)
        delete(path);
    end
end
end

function value=localReadStrings(path)
opts=detectImportOptions(path,FileType="text",Delimiter=",", ...
    VariableNamingRule="preserve");
opts=setvartype(opts,opts.VariableNames,"string");
value=readtable(path,opts);
end

function row=localAuditRow()
row=struct("RunID","","ImageFile","","SourceCSV","", ...
    "SourceCSV_SHA256","","PNG_SHA256","","Width",NaN,"Height",NaN, ...
    "AxesCount",NaN,"SeriesCount",NaN,"FinitePointCount",NaN, ...
    "ActualTitle","","ActualXLabel","","ActualYLabel","","Status","");
end

function value=localStatus(tf)
if tf, value="PASS"; else, value="FAIL"; end
end
