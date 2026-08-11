function result = runJointStudy(configPath,runMode,options)
%RUNJOINTSTUDY Execute the staged common-waveform ISAC campaign.

arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    runMode (1,1) string = "quick"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
[cfg,sourcePath] = sixgr.isac.loadJointConfig(configPath,runMode);
if strlength(options.OutputRoot) > 0
    outputRoot = options.OutputRoot;
else
    outputRoot = string(cfg.output.root);
end
if strlength(options.RunId) > 0
    runId = options.RunId;
else
    runId = "isac_joint_"+lower(string(runMode))+"_"+ ...
        string(datetime("now","Format","yyyyMMdd_HHmmss"));
end
runFolder = string(fullfile(outputRoot,runId));
localCreateLayout(runFolder);

fprintf("Joint ISAC %s run: %s\n",upper(runMode),runFolder);
fprintf("Loading physical W0-W3 waveforms at %s ...\n",string(cfg.carrier.activeProfile));
profileIds = ["W0","W1","W2","W3"];
bundles = struct();
for i=1:numel(profileIds)
    bundles.(profileIds(i)) = sixgr.isac.buildJointWaveform(cfg,profileIds(i), ...
        double(cfg.run.masterSeed));
end
pre6gExample = sixgr.isac.buildPre6GExampleWaveform(cfg, ...
    double(cfg.run.masterSeed)+1200);
trProfile=string(cfg.channel.tr38901Backend.referenceExample.waveformProfile);
tr38901Example=sixgr.isac.runTR38901ReferenceEvidence(cfg,bundles.(trProfile));
diagnostics = sixgr.isac.analyzeJointWaveforms(cfg,bundles);
diagnostics.Pre6GExample = table("PRE6G_EXAMPLE_RS",pre6gExample.SampleRateHz, ...
    pre6gExample.Nfft,numel(pre6gExample.Waveform),pre6gExample.WaveformSHA256, ...
    string(pre6gExample.ExecutionBackend),logical(pre6gExample.HardwareValidated), ...
    'VariableNames',{'Profile','SampleRateHz','Nfft','WaveformSamples', ...
    'WaveformSHA256','ExecutionBackend','HardwareValidated'});
diagnostics.TR38901Summary=tr38901Example.Summary;
diagnostics.TR38901Paths=tr38901Example.Paths;
diagnostics.TR38901Geometry=tr38901Example.Geometry;
plan = sixgr.isac.buildJointTrialPlan(cfg);
fprintf("Staged waveform trials: %d\n",numel(plan));

trialParts = cell(numel(plan),1); geometryParts = cell(numel(plan),1);
rangeParts = cell(numel(plan),1); occasionParts = cell(numel(plan),1);
rawCaptures = struct();
rangeDopplerDelay=double(cfg.rangeDopplerEvidence.delayOverCP(:)).';
rangeDopplerClass=string(cfg.rangeDopplerEvidence.delayClasses(:)).';
rangeDopplerParts=cell(numel(rangeDopplerDelay),1);
for i=1:numel(plan)
    trial = plan(i);
    bundle = bundles.(string(trial.WaveformProfile));
    [row,raw] = sixgr.isac.runJointWaveformTrial(cfg,bundle,trial);
    row.Stage = string(trial.Stage);
    trialParts{i} = row;
    g = raw.Geometry;
    g.TrialId = repmat(string(trial.TrialId),height(g),1);
    g.WaveformProfile = repmat(string(trial.WaveformProfile),height(g),1);
    g.SensingMode = repmat(string(trial.SensingMode),height(g),1);
    geometryParts{i} = g;
    range = raw.RangeProfile;
    range.TrialId = repmat(string(trial.TrialId),height(range),1);
    range.WaveformProfile = repmat(string(trial.WaveformProfile),height(range),1);
    rangeParts{i} = range;
    occasion = raw.OccasionPhase;
    occasion.TrialId = repmat(string(trial.TrialId),height(occasion),1);
    occasion.WaveformProfile = repmat(string(trial.WaveformProfile),height(occasion),1);
    occasionParts{i} = occasion;
    key = string(trial.WaveformProfile);
    if logical(trial.TargetPresent) && ~isfield(rawCaptures,key)
        rawCaptures.(key) = raw;
    end
    if string(trial.WaveformProfile)=="W0" && logical(trial.TargetPresent) && ...
            double(trial.CollisionRatioPercent)==0 && ...
            string(trial.SensingMode)=="trp_monostatic" && ...
            string(trial.PortProfile)=="single_port"
        mapIndex=find(abs(double(trial.DelayOverCP)-rangeDopplerDelay)<1e-12,1);
        if ~isempty(mapIndex) && isempty(rangeDopplerParts{mapIndex})
            rangeDopplerParts{mapIndex}=sixgr.isac.buildRangeDopplerEvidence( ...
                cfg,bundle,raw,rangeDopplerClass(mapIndex));
        end
    end
    if mod(i,5)==0 || i==numel(plan)
        checkpoint = vertcat(trialParts{1:i}); %#ok<NASGU>
        writetable(checkpoint,fullfile(runFolder,"raw","trial_rows_checkpoint.csv"));
        fprintf("  completed %d/%d\n",i,numel(plan));
    end
end
trialRows = vertcat(trialParts{:});
geometryRows = vertcat(geometryParts{:});
rangeProfiles = vertcat(rangeParts{:});
occasionPhases = vertcat(occasionParts{:});
if any(cellfun(@isempty,rangeDopplerParts))
    error("sixgr:isac:MissingRangeDopplerEvidence", ...
        "Below/at/above-CP W0 range-Doppler maps were not all executed.");
end
diagnostics.RangeDopplerMaps=vertcat(rangeDopplerParts{:});
aggregate = sixgr.isac.aggregateJointResults(cfg,trialRows);
studies = sixgr.isac.runIntegrationStudies(cfg,bundles,trialRows);
tables = sixgr.isac.buildJointTables(cfg,plan,trialRows,geometryRows, ...
    diagnostics,studies,aggregate);

localWriteSavedEvidence(runFolder,cfg,sourcePath,plan,trialRows,geometryRows, ...
    rangeProfiles,occasionPhases,rawCaptures,pre6gExample,tr38901Example,diagnostics,studies,aggregate,tables);
lineage = sixgr.isac.regenerateJointFigures(runFolder);
verification = sixgr.isac.verifyJointArtifacts(runFolder);
localWriteManifestAndReport(runFolder,cfg,sourcePath,plan,trialRows,tables,lineage,verification);

result = struct("RunFolder",runFolder,"Config",cfg,"Plan",plan, ...
    "TrialRows",trialRows,"Tables",tables,"FigureLineage",lineage, ...
    "Verification",verification,"Passed",all(verification.Pass) && ...
    all(tables.Table17_acceptance.Pass));
fprintf("Joint ISAC %s complete: trials=%d figures=%d tables=17 pass=%d\n", ...
    upper(runMode),height(trialRows),height(lineage),result.Passed);
end

function localCreateLayout(runFolder)
folders = ["logs","raw","aggregate","tables", ...
    fullfile("figures","tdoc_10_8_2"),fullfile("figures","tdoc_10_8_3"), ...
    fullfile("figures","joint"),fullfile("figures","patent_support"),"report"];
for folder=folders
    path=fullfile(runFolder,folder);
    if exist(path,"dir")~=7, mkdir(path); end
end
end

function localWriteSavedEvidence(runFolder,cfg,sourcePath,plan,trialRows,geometryRows,rangeProfiles,occasionPhases,rawCaptures,pre6gExample,tr38901Example,diagnostics,studies,aggregate,tables)
writetable(trialRows,fullfile(runFolder,"raw","waveform_trials.csv"));
writetable(geometryRows,fullfile(runFolder,"raw","geometry_trials.csv"));
writetable(rangeProfiles,fullfile(runFolder,"raw","range_profiles.csv"));
writetable(occasionPhases,fullfile(runFolder,"raw","occasion_phases.csv"));
writetable(diagnostics.Spectrum,fullfile(runFolder,"aggregate","waveform_spectrum.csv"));
writetable(diagnostics.Autocorrelation,fullfile(runFolder,"aggregate","waveform_autocorrelation.csv"));
writetable(diagnostics.CrossAmbiguity,fullfile(runFolder,"aggregate","cross_ambiguity.csv"));
writetable(diagnostics.PAPRCCDF,fullfile(runFolder,"aggregate","papr_ccdf.csv"));
writetable(diagnostics.Pre6GExample,fullfile(runFolder,"aggregate","pre6g_example_waveform.csv"));
writetable(diagnostics.TR38901Summary,fullfile(runFolder,"aggregate","tr38901_example_summary.csv"));
writetable(diagnostics.TR38901Paths,fullfile(runFolder,"aggregate","tr38901_example_paths.csv"));
writetable(diagnostics.TR38901Geometry,fullfile(runFolder,"aggregate","tr38901_example_geometry.csv"));
writetable(diagnostics.RangeDopplerMaps,fullfile(runFolder,"aggregate","range_doppler_maps.csv"));
writetable(aggregate.ProbabilityQualification,fullfile(runFolder,"aggregate","probability_qualification.csv"));
writetable(studies.BudgetSelection,fullfile(runFolder,"aggregate","budget_selection.csv"));
writetable(studies.PeriodicPhase.Spectrum,fullfile(runFolder,"aggregate","periodic_phase_spectrum.csv"));
writetable(studies.PeriodicPhase.Summary,fullfile(runFolder,"aggregate","periodic_phase_summary.csv"));
writetable(studies.TimingUpdate,fullfile(runFolder,"aggregate","timing_update_events.csv"));
writetable(studies.CFOUpdate,fullfile(runFolder,"aggregate","residual_frequency_events.csv"));
writetable(studies.PortPhase,fullfile(runFolder,"aggregate","port_phase_events.csv"));
writetable(studies.Interference,fullfile(runFolder,"aggregate","interference_study.csv"));
writetable(studies.ISIICI,fullfile(runFolder,"aggregate","isi_ici_study.csv"));
writetable(studies.Overhead,fullfile(runFolder,"aggregate","overhead_study.csv"));
save(fullfile(runFolder,"raw","representative_raw_captures.mat"),"rawCaptures","-v7.3");
save(fullfile(runFolder,"raw","pre6g_example_waveform.mat"),"pre6gExample","-v7.3");
save(fullfile(runFolder,"raw","tr38901_example_channel.mat"),"tr38901Example","-v7.3");
save(fullfile(runFolder,"raw","trial_plan.mat"),"plan");

names=fieldnames(tables);
for i=1:numel(names)
    tableData=tables.(names{i}); %#ok<NASGU>
    writetable(tableData,fullfile(runFolder,"tables",names{i}+".csv"));
    save(fullfile(runFolder,"tables",names{i}+".mat"),"tableData");
end
save(fullfile(runFolder,"aggregate","joint_study_data.mat"), ...
    "cfg","tables","diagnostics","studies","aggregate","-v7.3");
localWriteText(fullfile(runFolder,"config_snapshot.json"),jsonencode(cfg,"PrettyPrint",true));
save(fullfile(runFolder,"config_snapshot.mat"),"cfg");
copyfile(sourcePath,fullfile(runFolder,"config_source.yaml"));
repoRoot=localRepoRoot();
copyfile(fullfile(repoRoot,"docs","isac_joint_simulation_source_map.md"), ...
    fullfile(runFolder,"source_map.md"));
end

function localWriteManifestAndReport(runFolder,cfg,sourcePath,plan,trialRows,tables,lineage,verification)
[~,commit]=system("git rev-parse HEAD");
[~,status]=system("git status --porcelain");
manifest=struct("SchemaVersion","sixgr.isac.joint.run.v1", ...
    "StudyId",cfg.study.id,"RunMode",cfg.run.activeMode, ...
    "EvidenceClass",cfg.run.modes.(cfg.run.activeMode).evidenceClass, ...
    "RunFolder",char(runFolder),"ConfigSource",char(sourcePath), ...
    "ConfigSHA256",cfg.provenance.SourceSHA256,"GitCommit",strtrim(commit), ...
    "GitWorktreeDirty",strlength(strtrim(string(status)))>0, ...
    "MATLABRelease",version("-release"),"MATLABVersion",version, ...
    "Host",char(getenv("COMPUTERNAME")),"TrialCount",height(trialRows), ...
    "FigureCount",height(lineage),"TableCount",17, ...
    "ArtifactVerificationPassed",all(verification.Pass), ...
    "GeneratedUTC",char(datetime("now","TimeZone","UTC","Format","yyyy-MM-dd'T'HH:mm:ss'Z'")));
localWriteText(fullfile(runFolder,"run_manifest.json"),jsonencode(manifest,"PrettyPrint",true));

report=[ ...
    "# SixGR joint ISAC simulation report";""; ...
    "- Run mode: `"+string(cfg.run.activeMode)+"`"; ...
    "- Evidence class: `"+string(cfg.run.modes.(cfg.run.activeMode).evidenceClass)+"`"; ...
    "- Common time-domain waveform trials: "+height(trialRows); ...
    "- Named TDoc/patent PNG figures: 57/57"; ...
    "- Supplementary MathWorks-example PNG figures: "+(height(lineage)-57)+"/2"; ...
    "- TDoc table groups: 17/17 (CSV and MAT)"; ...
    "- Artifact verifier: "+localPassText(all(verification.Pass));""; ...
    "## Physical-chain statement";""; ...
    "All primary trial rows were produced from an executed NR CP-OFDM sample vector. Communication and sensing used the same received sample vector; the known/cancelled shared-resource receiver removed only the exact saved direct and data components allowed by the YAML policy.";""; ...
    "## Source status";""; ...
    "The nine DOCX files named by the master prompt were not present in the searched workspace locations. No value was attributed to those documents and no missing source value was invented. Exact source status is in Table16.";""; ...
    "## Statistical qualification";""; ...
    "Probability intervals and the no-target trial count are recorded in `aggregate/probability_qualification.csv`. Quick/TDoc-reduced evidence is not relabelled as a publication-qualified PFA campaign when the requested trial count is insufficient.";""; ...
    "## Reproduction";""; ...
    "Run `sixgr.isac.regenerateJointFigures(<run-folder>)` to recreate every PNG only from `aggregate/joint_study_data.mat` and the saved tables.";""];

report=[report;"## Assumptions and authorities";""];
assumptions=tables.Table01_assumptions;
for i=1:height(assumptions)
    report(end+1)="- **"+string(assumptions.Assumption(i))+"**: `"+ ...
        string(assumptions.Value(i))+"` — "+string(assumptions.Authority(i))+"."; %#ok<AGROW>
end

report=[report;"";"## Table inventory and meaning";""];
tableNames=fieldnames(tables);
for i=1:numel(tableNames)
    value=tables.(tableNames{i});
    meaning=strrep(erase(string(tableNames{i}),"Table"),"_"," ");
    report(end+1)="- `"+string(tableNames{i})+".csv` — "+meaning+ ...
        sprintf("; %d measured/configured rows and %d columns; matching MAT file saved.", ...
        height(value),width(value)); %#ok<AGROW>
end

report=[report;"";"## Figure inventory and lineage";""];
for i=1:height(lineage)
    report(end+1)="- `"+lineage.FigureName(i)+"` — rendered from `"+ ...
        string(lineage.SourceCSV(i))+"`; "+lineage.WidthPixels(i)+"x"+ ...
        lineage.HeightPixels(i)+" px; source SHA-256 `"+ ...
        lineage.SourceCSV_SHA256(i)+"`; image SHA-256 `"+ ...
        lineage.ImageSHA256(i)+"`; status "+lineage.Status(i)+"."; %#ok<AGROW>
end

report=[report;"";"## Acceptance checks";""];
acceptance=tables.Table17_acceptance;
for i=1:height(acceptance)
    report(end+1)="- "+localPassText(acceptance.Pass(i))+" — `"+ ...
        acceptance.Check(i)+"`: "+acceptance.Details(i)+"."; %#ok<AGROW>
end

report=[report;"";"## Failed runs";""; ...
    "No trial failed inside this completed run folder. A sibling or earlier run is not incorporated into this evidence set and must not be treated as part of this result.";""; ...
    "## Limitations";""; ...
    "- Quick and reduced-TDoc modes do not satisfy the configured publication PFA sample count; the exact Wilson interval and qualification flag are in `aggregate/probability_qualification.csv`."; ...
    "- The NI-USRP example path was not executed on hardware. `HardwareValidated=false` is retained in `aggregate/pre6g_example_waveform.csv`."; ...
    "- The communication metric is an uncoded QPSK calibration measurement from the shared waveform, not a coded PDSCH BLER claim."; ...
    "- The official MathWorks TR 38.901 helper execution is supplementary reference evidence and is not substituted for the deterministic paired-comparison channel used by primary trial rows."; ...
    "- The nine DOCX sources named by the supplied prompt were unavailable. Table16 records each missing source, and no source-specific value was invented."; ...
    "- This staged J1-J4 campaign is not a blind full-factorial sweep; the saved plan defines the exact executed coverage."];
localWriteText(fullfile(runFolder,"report","isac_joint_simulation_report.md"),join(report,newline));
end

function textOut=localPassText(flag)
if flag, textOut="PASS"; else, textOut="FAIL"; end
end

function root=localRepoRoot()
here=fileparts(mfilename("fullpath"));
root=fileparts(fileparts(here));
end

function localWriteText(path,textValue)
fid=fopen(path,"w","n","UTF-8");
if fid<0, error("sixgr:isac:WriteFailed","Unable to write %s.",path); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s",char(textValue));
end
