classdef CampaignRunner
    %CAMPAIGNRUNNER Config-driven deterministic/bounded evidence campaign.
    methods (Static)
        function result=run(mode,options)
            arguments
                mode (1,1) string {mustBeMember(mode,["plan","unit","deterministic", ...
                    "smoke","controlled_core","controlled_full","common_evm","sls", ...
                    "figure_replay","audit"])} = "smoke"
                options.ConfigPath (1,1) string = "simulator/configs/scenarios/lls_ran1_10522_td_dmrs_single_slot.yaml"
                options.OutputRoot (1,1) string = "results/ran1_10522_pdsch_dmrs"
                options.RunId (1,1) string = ""
                options.RunFolder (1,1) string = ""
            end
            if any(mode==["figure_replay","audit"])
                if options.RunFolder=="",error("sixgr:ran1ai10522:RunFolderRequired","RunFolder is required for %s.",mode);end
                result=localReplayOrAudit(mode,options.RunFolder); return;
            end
            [cfg,provenance,scfg]=sixgr.studies.ran1ai10522.loadStudyConfig(options.ConfigPath);
            if mode=="common_evm" && ~logical(cfg.study.common_evm_verified)
                error("sixgr:ran1ai10522:CommonEVMUnverified", ...
                    "COMMON_EVM_LLS is blocked because no verified profile/document/hash is configured.");
            end
            if mode=="sls"
                error("sixgr:ran1ai10522:MulticellSLSUnavailable", ...
                    "MULTICELL_SLS is blocked until a genuine traffic/scheduler/interference/PHY-coupled matrix is configured.");
            end
            if options.RunId==""
                runId="ran1_10522_"+mode+"_"+string(datetime("now","Format","yyyyMMdd_HHmmss"));
            else,runId=options.RunId;end
            % Canonicalize once at the boundary. dir() returns absolute folder
            % names on Windows, so retaining a relative output root would make
            % manifest-relative path extraction depend on the launch directory.
            runFolder=localCanonicalPath(fullfile(options.OutputRoot,runId));
            localLayout(runFolder);
            context=localContext(runId,scfg.ConfigHash);
            localConfigManifests(runFolder,cfg,provenance,scfg,context,mode);
            scenario=sixgr.studies.ran1ai10522.ScenarioRegistry.table(mode);
            proposal=sixgr.studies.ran1ai10522.ProposalMatrix.table();
            sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","scenario_matrix.csv"),scenario,context);
            sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","proposal_evidence_matrix.csv"),proposal,context);
            localScenarioManifest(runFolder,context);
            if mode=="plan"
                tasks=localPlan(cfg,scenario); sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","plan_tasks.csv"),tasks,context);
                localLimitations(runFolder,context,false); localRunSummary(runFolder,mode,context,0,0,false,false);
                result=struct("RunFolder",runFolder,"Passed",true,"PublicationQualified",false,"Plan",tasks); return;
            elseif mode=="unit"
                testRAN1AI10522Config; testRAN1AI10522Deterministic; testRAN1AI10522Controlled;
                localLimitations(runFolder,context,false); localRunSummary(runFolder,mode,context,0,0,true,false);
                result=struct("RunFolder",runFolder,"Passed",true,"PublicationQualified",false); return;
            end
            deterministic=sixgr.studies.ran1ai10522.DeterministicSuite.run(cfg);
            localWriteDeterministic(runFolder,deterministic,context);
            controlled=[]; includeResults=any(mode==["smoke","controlled_core","controlled_full"]);
            if includeResults
                controlled=sixgr.studies.ran1ai10522.ControlledSuite.run(cfg,scfg,runFolder);
                localWriteControlled(runFolder,controlled,context);
            else
                localWriteBlockedControlled(runFolder,context);
            end
            localPointStatus(runFolder,context,includeResults,controlled,scenario);
            localLimitations(runFolder,context,includeResults);
            manifest=sixgr.studies.ran1ai10522.FigurePublisher.replay(runFolder,cfg,context,includeResults);
            provisional=manifest(:,["FigureId","PNGPath","WidthPx","HeightPx","NonBlank","Status"]);
            provisional.DecodeOk=true(height(provisional),1); provisional.HashMatch=true(height(provisional),1);
            provisional=provisional(:,["FigureId","PNGPath","DecodeOk","HashMatch","WidthPx","HeightPx","NonBlank","Status"]);
            sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","frame_image_audit.csv"),provisional,context);
            if ~isempty(controlled),save(fullfile(runFolder,"mat","controlled_suite.mat"),"controlled","-v7.3");end
            save(fullfile(runFolder,"mat","deterministic_suite.mat"),"deterministic","-v7.3");
            localRunSummary(runFolder,mode,context,numel(dir(fullfile(runFolder,"**","*.csv"))),height(manifest),true,false);
            localJSONManifest(runFolder,mode,context);
            localArtifactManifest(runFolder,context);
            [~,frameAudit,~,~]=sixgr.studies.ran1ai10522.ArtifactAuditor.run(runFolder);
            sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","frame_image_audit.csv"),frameAudit,context);
            % Final frame audit is itself hash-bound. Refresh the artifact
            % manifest, then evaluate once more so no mutable manifest is
            % accepted with a stale digest.
            localArtifactManifest(runFolder,context);
            [audit,frameAudit,passed,publicationPassed]=sixgr.studies.ran1ai10522.ArtifactAuditor.run(runFolder);
            sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","frame_image_audit.csv"),frameAudit,context);
            % The frame audit is itself bound by the artifact manifest. Bind
            % the final bytes and perform one read-only acceptance pass.
            localArtifactManifest(runFolder,context);
            [audit,frameAudit,passed,publicationPassed]=sixgr.studies.ran1ai10522.ArtifactAuditor.run(runFolder);
            sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(runFolder,"manifests","artifact_audit.csv"),audit,context);
            localRunSummary(runFolder,mode,context,numel(dir(fullfile(runFolder,"**","*.csv"))),height(manifest),passed,publicationPassed);
            result=struct("RunFolder",runFolder,"Passed",passed,"PublicationQualified",publicationPassed, ...
                "Audit",audit,"Figures",manifest,"ScenarioMatrix",scenario,"ProposalMatrix",proposal);
            if ~passed,error("sixgr:ran1ai10522:ArtifactGateFailed","RAN1 10.5.2.2 artifact integrity gate failed.");end
            if any(mode==["controlled_core","controlled_full"])
                error("sixgr:ran1ai10522:MandatoryMatrixBlocked", ...
                    "%s generated bounded baseline evidence, but mandatory candidate waveform families remain blocked.",mode);
            end
            fprintf("RAN1 10.5.2.2 %s artifact PASS: %s (%d CSV, %d PNG; publication gate=%d)\n", ...
                mode,runFolder,numel(dir(fullfile(runFolder,"**","*.csv"))), ...
                numel(dir(fullfile(runFolder,"**","*.png"))),publicationPassed);
        end
    end
end

function localLayout(root)
dirs=["manifests","csv/deterministic","csv/controlled","figures/conceptual", ...
    "figures/diagnostic","mat","json"];
for d=dirs, path=fullfile(root,replace(d,"/",filesep));if ~isfolder(path),mkdir(path);end,end
end

function context=localContext(runId,configHash)
[~,commit]=system("git rev-parse HEAD"); [~,statusText]=system("git status --porcelain --untracked-files=normal");
context=struct("RunId",string(runId),"ConfigHash",string(configHash), ...
    "GitCommit",strtrim(string(commit)),"GitWorktreeDirty",strlength(strtrim(string(statusText)))>0);
end

function localConfigManifests(root,cfg,p,scfg,context,mode)
sixgr.lls6g.config.writeYAML(fullfile(root,"manifests","resolved_config.yaml"),cfg);
copyfile(scfg.ConfigPath,fullfile(root,"manifests","input_config.yaml"));
T=table(string(scfg.ConfigPath),strjoin(string(scfg.SourceFiles),"|"),string(scfg.ConfigHash), ...
    string(p.ParameterContractPath),string(p.ParameterContractSHA256),string(p.PromptSHA256), ...
    string(mode),"PASS",'VariableNames',{'ConfigPath','SourceFiles','ResolvedConfigSHA256', ...
    'ParameterContractPath','ParameterContractSHA256','PromptSHA256','Mode','Status'});
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","resolved_config_manifest.csv"),T,context);
v=ver; five=find(string({v.Name})=="5G Toolbox",1); if isempty(five),fiveVersion="missing";else,fiveVersion=string(v(five).Version);end
E=table(string(version),fiveVersion,string(computer),string(system_dependent("getos")), ...
    context.GitCommit,context.GitWorktreeDirty,datetime("now","TimeZone","UTC"), ...
    'VariableNames',{'MATLABVersion','FiveGToolboxVersion','Computer','OperatingSystem', ...
    'GitCommitObserved','GitWorktreeDirtyObserved','GeneratedUTC'});
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","environment_manifest.csv"),E,context);
end

function localScenarioManifest(root,context)
files=dir(fullfile("simulator","configs","scenarios","*ran1_10522*.yaml"));
rows=repmat(struct("ScenarioId","","ConfigPath","","ResolvedConfigSHA256","", ...
    "Family","","Launchable",false,"Status","PASS"),numel(files),1);
for k=1:numel(files)
    path=fullfile(files(k).folder,files(k).name); c=sixgr.lls6g.config.loadScenarioConfig(path); s=c.toStruct();
    rows(k)=struct("ScenarioId",string(c.ScenarioID),"ConfigPath",string(path), ...
        "ResolvedConfigSHA256",string(c.ConfigHash),"Family",string(s.study.family), ...
        "Launchable",true,"Status","PASS");
end
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","scenario_manifest.csv"), ...
    struct2table(rows,"AsArray",true),context);
end

function T=localPlan(cfg,scenario)
detTasks=height(scenario); waveformPoints=height(scenario)*numel(cfg.study.execution.snr_points_db);
T=table(["deterministic";"controlled_lls";"multicell_sls"],[detTasks;waveformPoints;1], ...
    [0;waveformPoints*double(cfg.study.execution.transport_blocks_per_point);0], ...
    ["READY";"RESOURCE_ESTIMATE_ONLY";"BLOCKED"], ...
    ["Exact tables";"Full candidate runtime matrix not launched";"No genuine multi-cell campaign configured"], ...
    'VariableNames',{'TaskClass','ExpandedTaskCount','EstimatedTransportBlocks','Status','Notes'});
end

function localWriteDeterministic(root,d,context)
names={"dmrs_time_profile",d.TimeProfile;"dmrs_group_positions",d.GroupPositions; ...
"dmrs_re_accounting",d.REAccounting;"td_occ_despreading_audit",d.TDOCCAudit; ...
"nested_family",d.NestedFamily;"nested_receiver_classification",d.NestedReceiver; ...
"covariance_metrics",d.Covariance;"fd_pattern_manifest",d.FDPattern; ...
"fd_occ_cdm_validity",d.FDValidity;"dmrs_sequence_metrics",d.Sequence; ...
"port_count_metrics",d.PortCount;"bundle_map",d.BundleMap; ...
"rbg_bundle_compatibility",d.RBGCompatibility;"interleaver_map",d.Interleaver; ...
"ptrs_phase_metrics",d.PTRSPhase;"tb_mapping_metrics",d.TBMapping; ...
"mcs_segmentation_metrics",d.MCSSegmentation;"cw_layer_mapping_metrics",d.CWLayerMapping; ...
"multitrp_profile_audit",d.MultiTRP;"mrss_validity_metrics",d.MRSSValidity; ...
"tdoc_table_2_1_topic_mapping",d.Tables.TopicMapping; ...
"tdoc_table_3_1_container_alternatives",d.Tables.ContainerAlternatives; ...
"tdoc_table_3_2_implicit_L_examples",d.Tables.ImplicitExamples; ...
"tdoc_table_3_3_floor_remainder_examples",d.Tables.FloorExamples; ...
"tdoc_table_4_1_company_port_positions_external_reference",d.Tables.CompanyPorts; ...
"tdoc_table_7_1_reporting_fields",d.Tables.ReportingFields; ...
"tdoc_table_C_1_nested_family",d.Tables.NestedFamily};
for k=1:size(names,1),sixgr.studies.ran1ai10522.ResultWriter.write( ...
        fullfile(root,"csv","deterministic",names{k,1}+".csv"),names{k,2},context);end
end

function localWriteControlled(root,c,context)
names={"pdsch_baseline_trials",c.Trials;"bler_points",c.BLER;"goodput_points",c.Goodput; ...
    "ce_nmse_points",c.CENMSE;"posteq_sinr_points",c.PostEqSINR;"runtime_metrics",c.Runtime};
for k=1:size(names,1),sixgr.studies.ran1ai10522.ResultWriter.write( ...
        fullfile(root,"csv","controlled",names{k,1}+".csv"),names{k,2},context);end
end

function localWriteBlockedControlled(root,context)
for name=["bler_points","goodput_points","ce_nmse_points","posteq_sinr_points","runtime_metrics"]
    sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"csv","controlled",name+".csv"), ...
        sixgr.studies.ran1ai10522.ResultWriter.blocked(name,"Waveform execution not requested in deterministic mode."),context);
end
end

function localPointStatus(root,context,includeResults,c,scenario)
items="deterministic_exhaustive"; evidence="ANALYTICAL_DERIVATION"; status="PASS"; stop="NONE"; ready=false;
if includeResults
    for k=1:height(c.Points)
        items(end+1,1)="canonical_pdsch_"+string(c.Points.SNR_dB(k))+"dB"; %#ok<AGROW>
        evidence(end+1,1)="CONTROLLED_LLS";status(end+1,1)="INCOMPLETE"; %#ok<AGROW>
        stop(end+1,1)="bounded_short_run_below_statistical_minimum";ready(end+1,1)=false; %#ok<AGROW>
    end
end
for k=1:height(scenario)
    if scenario.ExecutionStatus(k)=="PASS",continue;end
    items(end+1,1)="family_"+scenario.Family(k);evidence(end+1,1)="BLOCKED"; %#ok<AGROW>
    status(end+1,1)=scenario.ExecutionStatus(k);stop(end+1,1)=scenario.StopReason(k);ready(end+1,1)=false; %#ok<AGROW>
end
T=table(items,evidence,status,stop,ready,'VariableNames',{'PointId','EvidenceClass','Status','StopReason','TDocReady'});
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","point_status.csv"),T,context);
end

function localLimitations(root,context,includeResults)
items=["controlling_docx";"candidate_td_occ_waveform";"nested_mu_mimo";"cross_slot"; ...
    "extended_fd_occ";"high_port_waveform";"wideband_200_400mhz";"region_ptrs"; ...
    "multiple_tb";"segment_mcs";"enhanced_cw_mapping";"multicell_sls";"common_evm"];
reason=["Named controlling DOCX was not supplied";"Not integrated into canonical PDSCH Tx/Rx"; ...
    "No canonical co-scheduled waveform/covariance run";"No continuous cross-slot waveform run"; ...
    "Candidate mapper not in canonical waveform";"24/32/48/64/96 mappings unavailable"; ...
    "Memory-planned full waveform matrix not launched";"Per-region CPE correction unavailable"; ...
    "Independent DL-SCH/HARQ chains unavailable";"Aligned independently coded segments unavailable"; ...
    "Only NR rank 1-8 mapping is verified";"No genuine multi-cell scheduler/traffic/PHY run"; ...
    "No verified common-EVM document/profile/hash"];
status=repmat("BLOCKED",numel(items),1); if includeResults,status(2)="INCOMPLETE";end
T=table(items,repmat("BLOCKED",numel(items),1),status,reason, ...
    'VariableNames',{'Item','EvidenceClass','Status','Limitation'});
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","limitations.csv"),T,context);
end

function localRunSummary(root,mode,context,csvCount,figCount,auditPass,pubPass)
path=fullfile(root,"run_summary.md");fid=fopen(path,"w");if fid<0,error("sixgr:ran1ai10522:SummaryWriteFailed","Cannot write run summary.");end
cleanup=onCleanup(@()fclose(fid));
fprintf(fid,"# RAN1 AI 10.5.2.2 PDSCH/DM-RS wideband run summary\n\n");
fprintf(fid,"- Run ID: `%s`\n- Mode: `%s`\n- Config SHA-256: `%s`\n- Git commit observed: `%s`\n- Git worktree dirty observed: `%d`\n",context.RunId,mode,context.ConfigHash,context.GitCommit,context.GitWorktreeDirty);
fprintf(fid,"- CSV artifacts observed: %d\n- PNG figures observed: %d\n- Artifact integrity gate: `%d`\n- Publication gate: `%d`\n\n",csvCount,figCount,auditPass,pubPass);
fprintf(fid,"## Truth statement\n\nDeterministic PDSCH DMRS placement, nesting, sequence-index and PRB-bundle results are exact derivations under the stated configuration. Link-level results are produced by the identified SixGR MATLAB/5G Toolbox waveform, channel, receiver, coding and CRC path. They are not claimed to be 3GPP-conformance-calibrated unless a separate common-EVM calibration record is explicitly identified. Simplified Jakes, coherence-bandwidth or phase-only sanity models are diagnostic and shall not be used as TDoc-grade or filing-grade performance evidence. System-level claims require an actual multi-cell traffic, scheduler, interference and PHY-coupled run; a single-link or abstract-load proxy is not sufficient.\n\nNo smoke or incomplete artifact is copied to `tdoc_ready`.\n");
end

function localJSONManifest(root,mode,context)
payload=struct("SchemaVersion","sixgr.ran1.10_5_2_2.run/v1","RunId",char(context.RunId), ...
    "Mode",char(mode),"ConfigSHA256",char(context.ConfigHash),"GitCommit",char(context.GitCommit), ...
    "GitWorktreeDirty",context.GitWorktreeDirty,"PublicationQualified",false, ...
    "GeneratedUTC",char(datetime("now","TimeZone","UTC")));
sixgr.util.jsonWrite(fullfile(root,"json","run_manifest.json"),payload);
end

function localArtifactManifest(root,context)
root=localCanonicalPath(root);
files=dir(fullfile(root,"**","*"));files=files(~[files.isdir]); rows=repmat(struct( ...
    "RelativePath","","ArtifactType","","SHA256","","Bytes",0,"EvidenceClass","", ...
    "TDocReady",false,"Status","PASS"),0,1);
for k=1:numel(files)
    full=string(fullfile(files(k).folder,files(k).name)); rel=extractAfter(full,strlength(string(root))+1); rel=replace(rel,"\","/");
    if any(rel==["manifests/artifact_manifest.csv","manifests/artifact_audit.csv","run_summary.md"]),continue;end
    [~,~,ext]=fileparts(full); ext=lower(string(ext)); cls="ANALYTICAL_DERIVATION";
    if contains(rel,"controlled")||contains(rel,"figures/diagnostic"),cls="CONTROLLED_LLS";elseif ext==".png",cls="CONCEPTUAL_DIAGRAM";end
    rows(end+1,1)=struct("RelativePath",rel,"ArtifactType",erase(ext,"."), ... %#ok<AGROW>
        "SHA256",sixgr.csi.fileSHA256(full),"Bytes",files(k).bytes, ...
        "EvidenceClass",cls,"TDocReady",false,"Status","PASS");
end
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","artifact_manifest.csv"), ...
    struct2table(rows,"AsArray",true),context);
end

function result=localReplayOrAudit(mode,root)
root=localCanonicalPath(root); config=fullfile(root,"manifests","resolved_config.yaml");
[cfg,~,~]=sixgr.studies.ran1ai10522.loadStudyConfig(config);
sourceManifest=readtable(fullfile(root,"manifests","resolved_config_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
% Recovery must preserve source-run provenance. Rehashing the copied
% resolved YAML would identify the recovery invocation rather than the
% immutable configuration that generated the physical trials.
context=localContext(string(sourceManifest.RunId(1)),string(sourceManifest.ConfigHash(1)));
context.GitCommit=string(sourceManifest.GitCommit(1));
environment=readtable(fullfile(root,"manifests","environment_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
context.GitWorktreeDirty=logical(environment.GitWorktreeDirtyObserved(1));
if mode=="figure_replay"
    include=exist(fullfile(root,"csv","controlled","pdsch_baseline_trials.csv"),"file")==2;
    figures=sixgr.studies.ran1ai10522.FigurePublisher.replay(root,cfg,context,include);
else
    figures=readtable(fullfile(root,"manifests","figure_manifest.csv"), ...
        "Delimiter",",","VariableNamingRule","preserve");
end
[~,frame,~,~]=sixgr.studies.ran1ai10522.ArtifactAuditor.run(root);
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","frame_image_audit.csv"),frame,context);
localArtifactManifest(root,context);
[audit,frame,passed,pub]=sixgr.studies.ran1ai10522.ArtifactAuditor.run(root);
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","frame_image_audit.csv"),frame,context);
localArtifactManifest(root,context);
[audit,frame,passed,pub]=sixgr.studies.ran1ai10522.ArtifactAuditor.run(root);
sixgr.studies.ran1ai10522.ResultWriter.write(fullfile(root,"manifests","artifact_audit.csv"),audit,context);
localRunSummary(root,string(sourceManifest.Mode(1)),context, ...
    numel(dir(fullfile(root,"**","*.csv"))),height(figures),passed,pub);
result=struct("RunFolder",root,"Figures",figures,"Audit",audit,"Passed",passed,"PublicationQualified",pub);
if ~passed,error("sixgr:ran1ai10522:ArtifactGateFailed","Replay/audit failed.");end
end

function path=localCanonicalPath(path)
path=string(char(java.io.File(char(string(path))).getCanonicalPath()));
end
