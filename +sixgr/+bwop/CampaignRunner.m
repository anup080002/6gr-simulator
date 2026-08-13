classdef CampaignRunner
    %CAMPAIGNRUNNER RAN1 AI 10.5.1.3 staged campaign orchestrator.

    methods (Static)
        function result=run(configPath,options)
            arguments
                configPath (1,1) string
                options.OutputRoot (1,1) string = ""
                options.RunID (1,1) string = ""
                options.Mode (1,1) string = ""
                options.Resume (1,1) logical = false
            end
            started=tic;startedUTC=sixgr.util.utcNowISO8601();
            campaign=sixgr.bwop.loadCampaignConfig(configPath,options.Mode);
            cfg=campaign.Config;mode=campaign.Mode;
            if mode=="report_only"
                error("sixgr:bwop:ReportOnlyNeedsCompletedSource", ...
                    "report_only must consume an immutable completed campaign and is not an execution mode.");
            end
            if ~isfield(cfg.runtime_modes,char(mode))
                error("sixgr:bwop:MissingRuntimeMode","No runtime profile exists for mode '%s'.",mode);
            end
            modeCfg=cfg.runtime_modes.(char(mode));
            outputRoot=options.OutputRoot;
            if strlength(strtrim(outputRoot))==0,outputRoot=string(cfg.output.root);end
            runID=options.RunID;
            if strlength(strtrim(runID))==0
                runID=string(cfg.campaign_id)+"_"+mode+"_"+ ...
                    string(datetime("now","TimeZone","UTC","Format","yyyyMMdd_HHmmss"));
            end
            runFolder=string(fullfile(outputRoot,runID));
            localPrepareFolder(runFolder,campaign,options.Resume);
            runFolder=string(char(java.io.File(char(runFolder)).getCanonicalPath()));
            validation=sixgr.bwop.validateCampaignConfig(cfg);
            localWriteTable(runFolder,"validation_config",validation,"metadata");
            localWriteProvenance(runFolder,campaign,startedUTC);

            fprintf("BWOP AI 10.5.1.3 %s run: %s\n",upper(mode),runFolder);
            tables=struct();a=cfg.analytical;
            pbch=sixgr.bwop.PBCHPayloadStudy.run(a);
            tables.ANA001=pbch.MinimumRB;
            tables.ANA002=sixgr.bwop.RegionGeometry.enumerate(a);
            tables.ANA003=pbch.PayloadCost;
            tables.ANA004RIV=sixgr.bwop.RIVFDRA.rivTable(a.fdra_reference_bandwidth_rb);
            tables.ANA004CCE=sixgr.bwop.RIVFDRA.cceTable(a.coreset_rb,a.coreset_duration_symbols,a.aggregation_levels);
            tables.ANA005=sixgr.bwop.PowerNormalizer.sourceArithmetic( ...
                a.source_allocation_small_rb,a.source_allocation_large_rb, ...
                a.source_required_snr_delta_db,a.source_distributed_delta_db);
            tables.PowerFixedPSD=sixgr.bwop.PowerNormalizer.accounting( ...
                [a.source_allocation_small_rb a.source_allocation_large_rb], ...
                a.analytical_re_per_rb,a.dmrs_re_per_rb,"fixed_psd");
            tables.PowerFixedTotal=sixgr.bwop.PowerNormalizer.accounting( ...
                [a.source_allocation_small_rb a.source_allocation_large_rb], ...
                a.analytical_re_per_rb,a.dmrs_re_per_rb,"fixed_total_power");
            sixgr.bwop.PowerNormalizer.assertClosure(tables.PowerFixedPSD);
            sixgr.bwop.PowerNormalizer.assertClosure(tables.PowerFixedTotal);
            tables.ANA007=localTransitionClasses(a,cfg.post_ia);
            tables.PDCCHArithmetic=sixgr.bwop.PDCCHStudy.run(a,cfg.downlink);
            tables.PDSCHAllocations=sixgr.bwop.PDSCHStudy.allocationCases(cfg.downlink);
            tables.CAL002=sixgr.bwop.EnergyModel.sourceReproduction(cfg.calibration);

            if logical(modeCfg.procedure)
                trialCap=double(modeCfg.max_trials_per_point);
                rachCfg=cfg.rach;rachCfg.trials=min(double(rachCfg.trials),trialCap);
                postCfg=cfg.post_ia;postCfg.trials=min(double(postCfg.trials),trialCap);
                pagingCfg=cfg.paging;pagingCfg.paging_occasions=min(double(pagingCfg.paging_occasions),trialCap);
                e2eCfg=cfg.end_to_end;e2eCfg.trials=min(double(e2eCfg.trials),trialCap);
                tables.CommonControl=sixgr.bwop.CommonControlScheduler.run(cfg.common_control);
                tables.MonitoringBudget=sixgr.bwop.CommonControlScheduler.monitoringBudget(cfg.post_ia);
                tables.InitialUL=sixgr.bwop.InitialULStudy.run(cfg.initial_ul);
                tables.Energy=sixgr.bwop.EnergyModel.configuredRangeStudy( ...
                    cfg.initial_ul.configured_range_rb,cfg.initial_ul.actual_pusch_rb, ...
                    cfg.initial_ul.ue_tx_power_dbm,cfg.initial_ul.energy_model);
                [tables.RACH,tables.RACHEvents]=sixgr.bwop.RACHBandwidthStateMachine.run( ...
                    rachCfg,cfg.master_seed);
                [tables.PostIA,tables.PostIAEvents]=sixgr.bwop.PostIATransitionStateMachine.run( ...
                    postCfg,cfg.master_seed);
                tables.Paging=sixgr.bwop.PagingBandwidthStudy.run( ...
                    pagingCfg,a,cfg.master_seed);
                tables.SITiming=localSITiming(cfg.downlink);
                tables.Tracking=localTracking(cfg.downlink,a);
                tables.TDDRetune=localTDDRetune(cfg.initial_ul);
                [tables.E2ETrials,tables.E2EFailures]=localE2E(e2eCfg,cfg.master_seed);
            else
                tables=localEmptyProcedureTables(tables);
            end
            if logical(modeCfg.calibrated_lls)
                waveform=sixgr.bwop.CalibratedWaveformRunner.run(cfg,modeCfg,runFolder);
                tables.LLSSummary=waveform.Summary;
                tables.PDSCHSummaryFull=waveform.PDSCHSummary;
                tables.PUSCHSummaryFull=waveform.PUSCHSummary;
                tables.LLSTrials=waveform.Trials;
                tables.PDSCHTrialsFull=waveform.PDSCHTrials;
                tables.PUSCHTrialsFull=waveform.PUSCHTrials;
                tables.LLSRunIndex=waveform.RunIndex;
                tables.LLSQuality=waveform.Quality;
                tables.CALFixedPSD=waveform.CALFixedPSD;
                tables.CALFixedTotal=waveform.CALFixedTotal;
                tables.PDSCHWaveform=waveform.PDSCH;
                tables.PUSCHWaveform=waveform.PUSCH;
                tables.PDCCHWaveform=waveform.PDCCH;
                tables.PDCCHTrials=waveform.PDCCHTrials;
                tables.JointSIB1=waveform.JointSIB1;
            else
                tables=localEmptyCalibratedTables(tables);
            end
            localWriteCoreTables(runFolder,tables);

            figureRows=localConceptualFigures(runFolder,campaign,tables);
            resultRows=localResultFigures(runFolder,campaign,tables,logical(modeCfg.procedure));
            figureRows=[figureRows;resultRows];
            scenarioStatus=localScenarioStatus(logical(modeCfg.procedure), ...
                campaign.SourceAvailable,logical(modeCfg.calibrated_lls),tables);
            verification=localVerifyArtifacts(runFolder,campaign,figureRows);
            sixgr.util.csvWriteTable(fullfile(runFolder,"metadata","artifact_verification.csv"),verification);
            summary=struct("tdoc_ready_measured_figures", ...
                nnz(figureRows.Kind=="result"&figureRows.TDocReady));
            reports=sixgr.bwop.ReportBuilder.write(runFolder,campaign,scenarioStatus, ...
                figureRows,summary,tables);
            audit=sixgr.bwop.RunAuditor.run(runFolder,campaign,figureRows, ...
                scenarioStatus,tables);
            manifest=sixgr.bwop.ResultManifest.write(runFolder,campaign,figureRows, ...
                scenarioStatus,startedUTC,toc(started));
            % Passed denotes execution and artifact integrity. Scientific
            % closure remains represented independently by scenario and
            % figure PASS/WARN/BLOCKED rows (for example, smoke mode must
            % pass integrity while retaining its calibrated blockers).
            qualityPassed=~logical(modeCfg.calibrated_lls)|| ...
                (~isempty(tables.LLSQuality)&&all(tables.LLSQuality.Pass));
            passed=all(verification.Pass)&&qualityPassed;
            result=struct("RunFolder",runFolder,"Campaign",campaign,"Tables",tables, ...
                "Figures",figureRows,"ScenarioStatus",scenarioStatus, ...
                "Verification",verification,"Manifest",manifest,"Reports",reports, ...
                "Audit",audit, ...
                "Passed",passed);
            localPrintSummary(result);
        end
    end
end

function localPrepareFolder(root,campaign,resume)
if isfolder(root)
    manifestPath=fullfile(root,"metadata","manifest.json");
    if resume&&isfile(manifestPath)
        existing=jsondecode(fileread(manifestPath));
        if string(existing.config_hash)==campaign.ConfigHash
            error("sixgr:bwop:ResumeFinalized", ...
                "Run %s is already finalized with the same config hash; use it as immutable evidence.",root);
        end
        error("sixgr:bwop:ResumeConfigMismatch", ...
            "Finalized run config hash does not match requested configuration.");
    elseif ~resume
        error("sixgr:bwop:OutputExists", ...
            "BWOP output exists and will not be overwritten: %s.",root);
    end
else
    mkdir(root);
end
dirs=["config","metadata","logs","raw/analytical","raw/lls","raw/sls", ...
    "tables/csv","tables/mat","figures/conceptual","figures/analytical_screening", ...
    "figures/source_reproduction","figures/calibrated_lls","figures/procedure_sls", ...
    "figures/assumption_only","figures/tdoc_ready","reports","reports/blockers"];
for dir=dirs,sixgr.util.ensureFolder(fullfile(root,dir));end
copyfile(campaign.ConfigPath,fullfile(root,"config","master_input.yaml"));
sixgr.lls6g.config.writeYAML(fullfile(root,"config","resolved_config.yaml"),campaign.Raw);
sixgr.util.jsonWrite(fullfile(root,"config","resolved_config.json"),campaign.Raw);
auditPath=fullfile("docs","bwop_ai10513_repository_audit.md");
if isfile(auditPath)
    copyfile(auditPath,fullfile(root,"metadata","repository_audit.md"));
end
end

function localWriteProvenance(root,campaign,startedUTC)
v=ver;toolboxes=repmat(struct("name","","version",""),numel(v),1);
for i=1:numel(v),toolboxes(i).name=v(i).Name;toolboxes(i).version=v(i).Version;end
environment=struct("started_utc",startedUTC,"matlab",version, ...
    "release",version("-release"),"computer",computer,"toolboxes",toolboxes, ...
    "config_hash",campaign.ConfigHash,"source_available",campaign.SourceAvailable);
sixgr.util.jsonWrite(fullfile(root,"metadata","environment.json"),environment);
seeds=struct("master_seed",double(campaign.Config.master_seed), ...
    "mapping","deterministic hash of master seed and scenario coordinates");
sixgr.util.jsonWrite(fullfile(root,"metadata","seeds.json"),seeds);
end

function localWriteCoreTables(root,tables)
map={"ANA001","ANA-001_minimum_rb";"ANA002","ANA-002_region_geometry"; ...
    "ANA003","ANA-003_pbch_payload_cost";"ANA004RIV","ANA-004_riv"; ...
    "ANA004CCE","ANA-004_cce";"ANA005","ANA-005_power_arithmetic"; ...
    "PowerFixedPSD","ANA-005_fixed_psd_closure";"PowerFixedTotal","ANA-005_fixed_total_closure"; ...
    "ANA007","ANA-007_transition_classes";"PDCCHArithmetic","DL-002_pdcch_arithmetic"; ...
    "PDSCHAllocations","DL-001_pdsch_allocation_cases";"CAL002","CAL-002_source_energy"; ...
    "CommonControl","CTRL-001_common_control";"MonitoringBudget","POSTIA-004_monitoring_budget"; ...
    "InitialUL","UL-001_initial_ul_subsets";"Energy","UL-003_energy"; ...
    "RACH","RACH-002_early_indication";"RACHEvents","RACH-001_event_trace"; ...
    "PostIA","POSTIA_transition_summary";"PostIAEvents","POSTIA_event_trace"; ...
    "Paging","IDLE-001_paging";"SITiming","DL-005_si_timing"; ...
    "Tracking","DL-006_tracking_overhead";"TDDRetune","UL-004_tdd_retune"; ...
    "E2ETrials","E2E-001_trials";"E2EFailures","E2E-001_failure_causes"; ...
    "LLSSummary","LLS_waveform_summary"; ...
    "PDSCHSummaryFull","DL-001_pdsch_waveform_summary"; ...
    "PUSCHSummaryFull","UL-002_pusch_waveform_summary"; ...
    "LLSTrials","LLS_common_transport_block_trials"; ...
    "PDSCHTrialsFull","DL-001_pdsch_transport_block_trials"; ...
    "PUSCHTrialsFull","UL-002_pusch_transport_block_trials"; ...
    "LLSRunIndex","LLS_run_index";"LLSQuality","LLS_quality_gate"; ...
    "CALFixedPSD","CAL-001_fixed_psd_waveform"; ...
    "CALFixedTotal","CAL-001_fixed_total_waveform"; ...
    "PDSCHWaveform","DL-001_pdsch_waveform"; ...
    "PUSCHWaveform","UL-002_pusch_waveform"; ...
    "PDCCHWaveform","DL-002_pdcch_waveform"; ...
    "PDCCHTrials","DL-002_pdcch_trials"; ...
    "JointSIB1","DL-003_joint_sib1_waveform"};
for i=1:size(map,1)
    if isfield(tables,map{i,1})&&istable(tables.(map{i,1}))&&~isempty(tables.(map{i,1}))
        localWriteTable(root,map{i,2},tables.(map{i,1}),"tables");
    end
end
end

function localWriteTable(root,name,T,kind)
if kind=="metadata"
    csvPath=fullfile(root,"metadata",name+".csv");matPath=fullfile(root,"metadata",name+".mat");
else
    csvPath=fullfile(root,"tables","csv",name+".csv");matPath=fullfile(root,"tables","mat",name+".mat");
end
sixgr.util.csvWriteTable(csvPath,T);tableData=T; %#ok<NASGU>
save(matPath,"tableData","-v7");
end

function T=localTransitionClasses(a,post)
commonStart=double(post.transition_geometry_common_start_rb);
commonSize=double(post.transition_geometry_common_size_rb);
targetStarts=double(post.transition_geometry_target_start_rb(:)).';
targetSizes=double(post.transition_geometry_target_size_rb(:)).';
if numel(targetStarts)~=numel(targetSizes)
    error("sixgr:bwop:TransitionGeometryLengthMismatch", ...
        "Post-IA target start/size arrays must have equal length.");
end
rows=cell(numel(targetStarts)*numel(post.k_act_slots),1);r=0;
for i=1:numel(targetStarts)
    classId=sixgr.bwop.RegionGeometry.transitionClass(commonStart,commonSize,targetStarts(i),targetSizes(i));
    for k=double(post.k_act_slots(:)).'
        r=r+1;rows{r}=table(commonStart,commonSize,targetStarts(i),targetSizes(i), ...
            classId,k,k,"ANALYTICAL_EXACT","ASSUMPTION_ONLY", ...
            'VariableNames',{'CommonStartRB','CommonSizeRB','TargetStartRB','TargetSizeRB', ...
            'TransitionClass','KActSlots','ActivationOffsetSlots', ...
            'ClassEvidence','OffsetEvidence'});
    end
end
T=vertcat(rows{:}); %#ok<NASGU> a
end

function T=localSITiming(dl)
beams=double(dl.beam_counts(:));window=double(dl.si_window_slots);period=double(dl.si_periodicity_slots);gap=double(dl.inter_occasion_gap_slots);
occasionSlots=double(dl.si_occasion_duration_slots);required=beams.*(occasionSlots+gap)-gap;windows=ceil(required/window);
completion=min(required,windows*window);expiry=required>windows*window;
activeSlots=beams*occasionSlots;
T=table(beams,repmat(window,numel(beams),1),repmat(period,numel(beams),1), ...
    required,windows,completion,activeSlots,expiry, ...
    repmat("PROCEDURE_SLS",numel(beams),1), ...
    'VariableNames',{'BeamCount','SIWindowSlots','SIPeriodicitySlots', ...
    'RequiredTimelineSlots','SIWindowsRequired','CompletionSlots','GNBActiveSlots', ...
    'SIWindowExpiry','EvidenceClass'});
end

function T=localTracking(dl,a)
cases=string(dl.tracking_cases(:));contained=double(dl.tracking_ssb_contained(:));
retunes=double(dl.tracking_retune_required(:));overhead=double(dl.tracking_overhead_slots(:));
if numel(unique([numel(cases),numel(contained),numel(retunes),numel(overhead)]))~=1
    error("sixgr:bwop:TrackingConfigLengthMismatch", ...
        "Tracking case, containment, retune and overhead arrays must have equal length.");
end
T=table(cases,contained,retunes,overhead, ...
    repmat(double(a.ssb_size_rb),4,1),repmat("PROCEDURE_SLS",4,1), ...
    'VariableNames',{'CaseID','SSBContained','RetuneRequired','TrackingOverheadSlots', ...
    'SSBSizeRB','EvidenceClass'}); %#ok<NASGU> dl
end

function T=localTDDRetune(ul)
gaps=double(ul.retune_gap_slots(:));architectures=string(ul.rf_architectures(:));rows=cell(numel(gaps)*numel(architectures),1);r=0;
for architecture=architectures(:).'
    for gap=gaps(:).'
        r=r+1;required=double(architecture=="single_lo")* ...
            double(ul.single_lo_required_gap_slots);
        miss=max(0,(required-gap)/max(required,1));latency=gap+required;
        rows{r}=table(architecture,gap,required,miss,latency,"PROCEDURE_SLS", ...
            'VariableNames',{'RFArchitecture','ConfiguredGapSlots','RequiredGapSlots', ...
            'MissedTransmissionProbability','TransitionLatencySlots','EvidenceClass'});
    end
end
T=vertcat(rows{:});
end

function [trials,causes]=localE2E(cfg,masterSeed)
n=double(cfg.trials);prob=double(cfg.access_stage_success(:));lat=double(cfg.stage_latency_slots(:));
stage=string(cfg.failure_causes(:));
if numel(stage)~=numel(prob)||numel(lat)~=numel(prob)
    error("sixgr:bwop:E2EStageLengthMismatch", ...
        "E2E failure causes, success probabilities and latencies must have equal length.");
end
stream=RandStream("Threefry","Seed",mod(double(masterSeed)+510013,2^31-2)+1);
success=false(n,1);latency=zeros(n,1);failure=repmat("SUCCESS",n,1);
for i=1:n
    for j=1:numel(prob)
        latency(i)=latency(i)+lat(j);
        if rand(stream)>=prob(j),failure(i)=stage(j);break;end
        if j==numel(prob),success(i)=true;end
    end
end
trials=table((1:n)',success,latency,failure,repmat("PROCEDURE_SLS",n,1), ...
    repmat("configured_assumption_not_calibrated_lookup",n,1), ...
    'VariableNames',{'Trial','AccessSuccess','LatencySlots','FailureCause', ...
    'EvidenceClass','PHYLookupSource'});
uniqueCauses=[stage;"SUCCESS"];
count=zeros(numel(uniqueCauses),1);for i=1:numel(uniqueCauses),count(i)=nnz(failure==uniqueCauses(i));end
causes=table(uniqueCauses,count,count/n,repmat("PROCEDURE_SLS",numel(count),1), ...
    'VariableNames',{'FailureCause','Count','Probability','EvidenceClass'});
end

function tables=localEmptyProcedureTables(tables)
names=["CommonControl","MonitoringBudget","InitialUL","Energy","RACH", ...
    "RACHEvents","PostIA","PostIAEvents","Paging","SITiming","Tracking", ...
    "TDDRetune","E2ETrials","E2EFailures"];
for name=names,tables.(name)=table();end
end

function tables=localEmptyCalibratedTables(tables)
names=["LLSSummary","PDSCHSummaryFull","PUSCHSummaryFull", ...
    "LLSTrials","PDSCHTrialsFull","PUSCHTrialsFull", ...
    "LLSRunIndex","LLSQuality", ...
    "CALFixedPSD","CALFixedTotal","PDSCHWaveform","PUSCHWaveform", ...
    "PDCCHWaveform","PDCCHTrials","JointSIB1"];
for name=names,tables.(name)=table();end
end

function rows=localConceptualFigures(root,campaign,t)
cfg=campaign.Config;hash=campaign.ConfigHash;dpi=double(cfg.output.png_dpi);rows=cell(9,1);
flowLabels=["SS/PBCH","SIB1 PDCCH/PDSCH","Msg1/MsgA","Msg2/MsgB","Msg3", ...
    "Msg4/RRCSetup","Confirming UL","Target activation","Bounded overlap","Target data"]';
flow=table((1:numel(flowLabels))',zeros(numel(flowLabels),1),flowLabels, ...
    'VariableNames',{'X','Y','Label'});
rows{1}=sixgr.bwop.FigureFactory.publish(root,"F01_scope",flow,"PROCEDURE_SCHEMATIC",hash, ...
    "Kind","conceptual","Render","flow","Title","Initial access to target bandwidth", ...
    "ScenarioID","E2E-001","DPI",dpi);
referenceNC=double(campaign.Config.analytical.conceptual_reference_coreset_rb);
g=t.ANA002(t.ANA002.NC_RB==referenceNC&t.ANA002.NS_RB>=referenceNC,:); ...
    [~,idx]=unique(g.CaseID,"stable");g=g(idx,:);
region=table(g.NSStartRB,g.NS_RB,g.CaseID,'VariableNames',{'StartRB','SizeRB','Label'});
rows{2}=sixgr.bwop.FigureFactory.publish(root,"F02_sib1_option_decomposition",region,"ANALYTICAL_EXACT",hash, ...
    "Kind","conceptual","Render","region","Title","SIB1 bandwidth/location option decomposition", ...
    "ScenarioID","ANA-002","DPI",dpi);
rows{3}=sixgr.bwop.FigureFactory.publish(root,"F03_pbch_payload_cost",t.ANA003,"ANALYTICAL_EXACT",hash, ...
    "Kind","conceptual","XField","AddedBits","YField","ClosedFormDeltaEsN0Db", ...
    "Title","PBCH added-bit arithmetic and capacity screening","XLabel","Added PBCH bits", ...
    "YLabel","Delta Es/N0 (dB)","ScenarioID","ANA-003","DPI",dpi);
rows{4}=sixgr.bwop.FigureFactory.publish(root,"F04_wider_coreset_vs_wider_s",t.ANA004RIV,"ANALYTICAL_EXACT",hash, ...
    "Kind","conceptual","XField","NS_RB","YField","FDRABits", ...
    "Title","Wider CORESET versus wider schedulable data reference", ...
    "XLabel","N_S (RB)","YLabel","FDRA bits","ScenarioID","CTRL-001","DPI",dpi);
p=t.ANA005;powerFig=table((1:4)',[p.SourceReportedFixedPSDDeltaDb;p.OccupiedEnergyRatioDb; ...
    p.ArithmeticFixedTotalDeltaDb;p.SourceReportedDistributedDeltaDb], ...
    ["source fixed PSD";"occupied-energy ratio";"arithmetic fixed total";"source distributed"], ...
    'VariableNames',{'MetricIndex','ValueDb','Metric'});
rows{5}=sixgr.bwop.FigureFactory.publish(root,"F05_source_power_normalization",powerFig,"ANALYTICAL_EXACT",hash, ...
    "Kind","conceptual","Render","bar","XField","MetricIndex","YField","ValueDb", ...
    "Title","Source power-normalization arithmetic","XLabel","Metric index", ...
    "YLabel","dB","ScenarioID","ANA-005","DPI",dpi);
rows{6}=sixgr.bwop.FigureFactory.publish(root,"F06_rf_span_feasibility",region,"ANALYTICAL_EXACT",hash, ...
    "Kind","conceptual","Render","region","Title","RF-span feasibility geometry", ...
    "ScenarioID","ANA-006","DPI",dpi);
rachLabels=["Common CORESET","Msg2/MsgB PDSCH in S","Msg3 retransmission control", ...
    "Msg4 control","Msg4 PDSCH in S"]';rachFlow=table((1:5)',zeros(5,1),rachLabels, ...
    'VariableNames',{'X','Y','Label'});
rows{7}=sixgr.bwop.FigureFactory.publish(root,"F07_rach_inheritance",rachFlow,"PROCEDURE_SCHEMATIC",hash, ...
    "Kind","conceptual","Render","flow","Title","RACH bandwidth inheritance", ...
    "ScenarioID","RACH-001","DPI",dpi);
ulSource=table([0;4;12;20],[12;24;24;2],["PRACH";"MsgA PUSCH";"Msg3 PUSCH";"Msg4 HARQ-ACK"], ...
    'VariableNames',{'StartRB','SizeRB','Label'});
rows{8}=sixgr.bwop.FigureFactory.publish(root,"F08_initial_ul_applicability",ulSource,"PROCEDURE_SCHEMATIC",hash, ...
    "Kind","conceptual","Render","region","Title","Configured common UL range and actual subsets", ...
    "ScenarioID","UL-001","DPI",dpi);
postLabels=["Msg4/RRCSetup","Confirming UL","K_act","Target activation", ...
    "Bounded dual monitoring","Early cease or expiry"]';postFlow=table((1:6)',zeros(6,1),postLabels, ...
    'VariableNames',{'X','Y','Label'});
rows{9}=sixgr.bwop.FigureFactory.publish(root,"F09_postia_timeline",postFlow,"PROCEDURE_SCHEMATIC",hash, ...
    "Kind","conceptual","Render","flow","Title","Post-initial-access activation timeline", ...
    "ScenarioID","POSTIA-002","DPI",dpi);
rows=vertcat(rows{:});
end

function rows=localResultFigures(root,campaign,t,procedureEnabled)
cfg=campaign.Config;hash=campaign.ConfigHash;dpi=double(cfg.output.png_dpi);registry=sixgr.bwop.ScenarioRegistry.figureTraceability();
rows=cell(25,1);ids="R"+compose("%02d",1:25);
blocked=containers.Map("R04", ...
    "A standards-conformant PBCH has a fixed payload contract; the nonstandard added-bit waveform extension is not implemented and is not fabricated.");
if isempty(t.CALFixedPSD),blocked("R01")="CAL-001 fixed-PSD waveform sweep was not selected.";end
if isempty(t.CALFixedTotal),blocked("R02")="CAL-001 fixed-total-power waveform sweep was not selected.";end
if isempty(t.PDCCHWaveform),blocked("R05")="Strict PDCCH waveform sweep was not selected.";end
if isempty(t.PDSCHWaveform),blocked("R06")="Controlled-allocation PDSCH waveform sweep was not selected.";end
if isempty(t.JointSIB1),blocked("R07")="Joint measured PDCCH/PDSCH evidence is unavailable.";end
if isempty(t.PUSCHWaveform),blocked("R15")="Msg3/MsgA PUSCH waveform sweep was not selected.";end
for index=1:25
    id=ids(index);scenario=registry.ScenarioID(registry.FigureID==id);
    if isKey(blocked,char(id))
        rows{index}=sixgr.bwop.FigureFactory.block(root,id,scenario, ...
            localRequiredClass(id),string(blocked(char(id))),hash);continue;
    end
    if ~procedureEnabled&&~ismember(id,["R03","R08","R14"])
        rows{index}=sixgr.bwop.FigureFactory.block(root,id,scenario,"PROCEDURE_SLS", ...
            "Procedure execution is disabled in the selected analytical mode.",hash);continue;
    end
    [source,evidence,x,y,group,render,tickLabels,title,xlabelText,ylabelText]=localResultSource(id,t);
    rows{index}=sixgr.bwop.FigureFactory.publish(root,id,source,evidence,hash, ...
        "XField",x,"YField",y,"GroupField",group,"Render",render, ...
        "XTickLabelField",tickLabels,"Title",title, ...
        "XLabel",xlabelText,"YLabel",ylabelText,"ScenarioID",scenario, ...
        "StatisticsQualified",false,"DPI",dpi);
end
rows=vertcat(rows{:});
end

function value=localRequiredClass(id)
switch id
    case {"R01","R02"},value="SOURCE_REPRODUCTION";
    otherwise,value="CALIBRATED_LLS";
end
end

function [T,evidence,x,y,group,render,tickLabels,title,xlabelText,ylabelText]=localResultSource(id,t)
group="";render="line";tickLabels="";
switch id
    case "R01"
        T=t.CALFixedPSD;evidence="CALIBRATED_LLS";x="ReferenceSNRdB";y="BLER";group="ActualAllocationRB"; ...
            title="Measured Msg4 PDSCH BLER under fixed PSD";xlabelText="Reference Es/N0 (dB)";ylabelText="BLER";
    case "R02"
        T=t.CALFixedTotal;evidence="CALIBRATED_LLS";x="ReferenceSNRdB";y="BLER";group="ActualAllocationRB"; ...
            title="Measured Msg4 PDSCH BLER under fixed total power";xlabelText="Reference total-power SNR (dB)";ylabelText="BLER";
    case "R03"
        p=t.ANA005;T=table((1:4)',["Source fixed PSD";"Occupied-energy ratio"; ...
            "Fixed-total arithmetic";"Distributed allocation"], ...
            [p.SourceReportedFixedPSDDeltaDb;p.OccupiedEnergyRatioDb; ...
            p.ArithmeticFixedTotalDeltaDb;p.SourceReportedDistributedDeltaDb], ...
            'VariableNames',{'CaseIndex','Case','DeltaDb'});evidence="ANALYTICAL_EXACT";x="CaseIndex";y="DeltaDb"; ...
            render="bar";tickLabels="Case";title="Contiguous/distributed source power arithmetic";xlabelText="Comparison";ylabelText="Delta (dB)";
    case "R05"
        T=t.PDCCHWaveform;evidence="CALIBRATED_LLS";x="SNRdB";y="BLER"; ...
            title="Strict PDCCH waveform BLER";xlabelText="SNR (dB)";ylabelText="BLER";
    case "R06"
        T=t.PDSCHWaveform;evidence="CALIBRATED_LLS";x="ReferenceSNRdB";y="BLER";group="ActualAllocationRB"; ...
            title="Controlled-allocation PDSCH waveform BLER";xlabelText="Es/N0 (dB)";ylabelText="BLER";
    case "R07"
        T=t.JointSIB1;evidence="CALIBRATED_LLS";x="SNRdB";y="JointAcquisitionBLER"; ...
            title="Joint PDCCH/PDSCH SIB1 acquisition BLER";xlabelText="SNR (dB)";ylabelText="Joint BLER";
    case "R08"
        T=t.ANA001;evidence="ANALYTICAL_EXACT";x="PayloadBits";y="MinimumRB";group="EffectiveCodeRate"; ...
            title="SIB1 payload and minimum bandwidth";xlabelText="Payload bits";ylabelText="Minimum RB";
    case "R09"
        T=t.CommonControl;T.Series="N_C="+string(T.NC_RB)+", beams="+string(T.BeamCount);evidence="PROCEDURE_SLS";x="OfferedCCELoad";y="BlockingProbability";group="Series"; ...
            title="Common-control blocking versus CORESET bandwidth";xlabelText="Offered CCE load";ylabelText="Blocking probability";
    case "R10"
        [v,order]=sort(t.CommonControl.MeanSchedulingDelaySlots);T=t.CommonControl(order,:);T.EmpiricalCDF=(1:height(T))'/height(T); ...
            evidence="PROCEDURE_SLS";x="MeanSchedulingDelaySlots";y="EmpiricalCDF";title="Common-message scheduling-delay CDF";xlabelText="Delay (slots)";ylabelText="CDF";
    case "R11"
        T=t.ANA007;evidence="PROCEDURE_SLS";x="KActSlots";y="ActivationOffsetSlots";group="TransitionClass"; ...
            title="Receiver preparation offset tradeoff";xlabelText="K_act (slots)";ylabelText="Activation offset (slots)";
    case "R12"
        T=t.SITiming;evidence="PROCEDURE_SLS";x="BeamCount";y="CompletionSlots";title="SIB1 completion latency versus beams";xlabelText="Beam count";ylabelText="Completion slots";
    case "R13"
        T=t.Tracking;T.CaseIndex=(1:height(T))';evidence="PROCEDURE_SLS";x="CaseIndex";y="TrackingOverheadSlots";render="bar";tickLabels="CaseID";title="SSB containment tracking overhead";xlabelText="Containment case";ylabelText="Overhead (slots)";
    case "R14"
        T=t.ANA002;T.FeasibleNumeric=double(T.Feasible);evidence="ANALYTICAL_EXACT";x="NSStartRB";y="FeasibleNumeric";group="CaseID";render="scatter";title="RF-span feasibility map";xlabelText="SIB1 region start (RB)";ylabelText="Feasible (1/0)";
    case "R15"
        T=t.PUSCHWaveform;evidence="CALIBRATED_LLS";x="ReferenceSNRdB";y="BLER";group="ActualAllocationRB"; ...
            title="Measured Msg3/MsgA PUSCH BLER";xlabelText="Es/N0 (dB)";ylabelText="BLER";
    case "R16"
        T=t.Energy(t.Energy.UETxPowerDbm==max(t.Energy.UETxPowerDbm),:);evidence="ASSUMPTION_ONLY";x="ConfiguredRangeRB";y="TotalEnergy";group="ActualAllocationRB";title="UL energy versus configured range width at configured Pmax";xlabelText="Configured range (RB)";ylabelText="Normalized energy";
    case "R17"
        T=t.TDDRetune;evidence="PROCEDURE_SLS";x="ConfiguredGapSlots";y="MissedTransmissionProbability";group="RFArchitecture";title="Aligned versus non-aligned TDD gap";xlabelText="Gap (slots)";ylabelText="Miss probability";
    case "R18"
        T=t.RACH(t.RACH.IndicationState=="correct",:);evidence="PROCEDURE_SLS";x="IndicationErrorRate";y="AccessSuccessProbability";group="Policy";title="Early-capability RACH success for a correct indication";xlabelText="Indication error rate";ylabelText="Access success probability";
    case "R19"
        T=groupsummary(t.PostIA,["TransitionClass","KActSlots"],"mean","StateMismatchProbability"); ...
            T.StateMismatchProbability=T.mean_StateMismatchProbability;evidence="PROCEDURE_SLS";x="KActSlots";y="StateMismatchProbability";group="TransitionClass";title="Post-IA activation latency/mismatch";xlabelText="K_act (slots)";ylabelText="Mean mismatch probability";
    case "R20"
        T=groupsummary(t.PostIA,["EarlyCeaseRule","KFallbackSlots"],"mean","RecoverySuccessProbability"); ...
            T.RecoverySuccessProbability=T.mean_RecoverySuccessProbability;evidence="PROCEDURE_SLS";x="KFallbackSlots";y="RecoverySuccessProbability";group="EarlyCeaseRule";title="Overlap-window recovery/overhead";xlabelText="K_fallback (slots)";ylabelText="Mean recovery probability";
    case "R21"
        T=t.MonitoringBudget;evidence="PROCEDURE_SLS";x="TargetBD";y="TargetCCE";group="Policy";title="Blind-decode/CCE split tradeoff";xlabelText="Target blind decodes";ylabelText="Target CCE budget";
    case "R22"
        T=t.RACH(t.RACH.IndicationState=="unsupported_profile",:);evidence="PROCEDURE_SLS";x="IndicationErrorRate";y="CommonRecoveryProbability";group="Policy";title="Unsupported-profile recovery";xlabelText="Indication error rate";ylabelText="Common recovery probability";
    case "R23"
        T=t.Paging;T.LocationIndex=(1:height(T))';evidence="PROCEDURE_SLS";x="LocationIndex";y="EnergyPerCycle";render="bar";tickLabels="Location";title="Paging energy and latency";xlabelText="Paging location";ylabelText="Energy per cycle";
    case "R24"
        [lat,order]=sort(t.E2ETrials.LatencySlots);T=t.E2ETrials(order,:);T.EmpiricalCDF=(1:height(T))'/height(T);T.LatencySlots=lat; ...
            evidence="PROCEDURE_SLS";x="LatencySlots";y="EmpiricalCDF";title="End-to-end access latency CDF";xlabelText="Latency (slots)";ylabelText="CDF";
    case "R25"
        T=t.E2EFailures;T.CauseIndex=(1:height(T))';evidence="PROCEDURE_SLS";x="CauseIndex";y="Probability";render="bar";tickLabels="FailureCause";title="End-to-end failure-cause breakdown";xlabelText="Failure cause";ylabelText="Probability";
    otherwise,error("sixgr:bwop:UnknownResultFigure","No source mapping for %s.",id);
end
end

function T=localScenarioStatus(procedureEnabled,sourceAvailable,calibratedEnabled,tables)
T=sixgr.bwop.ScenarioRegistry.catalog();T.Status=repmat("BLOCKED",height(T),1);T.Detail=repmat("not_executed",height(T),1);
ana=startsWith(T.ScenarioID,"ANA-");T.Status(ana)="PASS";T.Detail(ana)="exact analytical implementation executed";
T.Status(T.ScenarioID=="CAL-002")="WARN";T.Detail(T.ScenarioID=="CAL-002")="source arithmetic executed; controlling DOCX unavailable="+string(~sourceAvailable);
T.Detail(T.ScenarioID=="CAL-001")="calibrated source-reproduction waveform campaign not selected in smoke mode";
if procedureEnabled
    passIds=["DL-004","DL-005","DL-006","CTRL-001","CTRL-002","RACH-001","RACH-002","RACH-003", ...
        "UL-001","UL-003","UL-004","POSTIA-001","POSTIA-002","POSTIA-003", ...
        "POSTIA-004","POSTIA-005","POSTIA-006","POSTIA-007","IDLE-001","IDLE-002","E2E-001"];
    for id=passIds,T.Status(T.ScenarioID==id)="PASS";T.Detail(T.ScenarioID==id)="bounded procedure/geometry model executed; calibrated lookup provenance not claimed";end
end
T.Detail(T.ScenarioID=="DL-001")="controlled PRB cases constructed; calibrated PDSCH sweep not selected";
T.Detail(T.ScenarioID=="DL-002")="DCI/CCE arithmetic executed; calibrated PDCCH sweep not selected";
T.Detail(T.ScenarioID=="DL-003")="requires passing measured DL-001 and DL-002 evidence";
T.Detail(T.ScenarioID=="UL-002")="calibrated PUSCH allocation sweep not selected";
if calibratedEnabled
    ids=["CAL-001","DL-001","DL-002","DL-003","UL-002"];
    for id=ids
        T.Status(T.ScenarioID==id)="PASS";
        T.Detail(T.ScenarioID==id)="bounded waveform-truth execution passed; low-sample engineering evidence, not publication statistics";
    end
    if isempty(tables.LLSQuality)||any(~tables.LLSQuality.Pass)
        error("sixgr:bwop:CalibratedQualityGateFailed", ...
            "Calibrated scenario status cannot pass without a complete quality gate.");
    end
end
end

function T=localVerifyArtifacts(root,campaign,rows)
checks={};pass=[];detail={};
checks{end+1}="figure_contract_rows";pass(end+1)=height(rows)==34;detail{end+1}=sprintf("rows=%d",height(rows));
checks{end+1}="conceptual_count";pass(end+1)=nnz(rows.Kind=="conceptual"&rows.Status=="PASS")==9;detail{end+1}=sprintf("pass=%d",nnz(rows.Kind=="conceptual"&rows.Status=="PASS"));
checks{end+1}="result_pass_or_blocked";pass(end+1)=all(rows(rows.Kind=="result",:).Status=="PASS"|rows(rows.Kind=="result",:).Status=="BLOCKED");detail{end+1}="every result has evidence or explicit blocker";
for i=1:height(rows)
    if rows.Status(i)=="PASS"
        required=[rows.ImagePath(i),rows.SourceCSV(i),rows.SourceMAT(i),rows.MetadataPath(i),rows.CaptionPath(i)];
        ok=all(arrayfun(@(p)isfile(fullfile(root,p)),required));
        checks{end+1}=char("artifact_"+rows.FigureID(i));pass(end+1)=ok;detail{end+1}=char(strjoin(required,"|")); %#ok<AGROW>
    else
        ok=isfile(fullfile(root,rows.MetadataPath(i)))&&isfile(fullfile(root,rows.CaptionPath(i)));
        checks{end+1}=char("blocker_"+rows.FigureID(i));pass(end+1)=ok;detail{end+1}=char(rows.BlockerReason(i)); %#ok<AGROW>
    end
end
svg=dir(fullfile(root,"**","*.svg"));checks{end+1}="no_svg";pass(end+1)=isempty(svg);detail{end+1}=sprintf("svg=%d",numel(svg));
badTDoc=rows.TDocReady&ismember(rows.EvidenceClass,["ANALYTICAL_SCREENING","ASSUMPTION_ONLY"]);
checks{end+1}="tdoc_evidence_gate";pass(end+1)=~any(badTDoc);detail{end+1}=sprintf("invalid=%d",nnz(badTDoc));
checks{end+1}="resolved_config";pass(end+1)=isfile(fullfile(root,"config","resolved_config.yaml"));detail{end+1}=char(campaign.ConfigHash);
T=table(string(checks(:)),logical(pass(:)),string(detail(:)), ...
    'VariableNames',{'Check','Pass','Detail'});
if any(~T.Pass)
    error("sixgr:bwop:ArtifactCompletenessFailed", ...
        "BWOP artifact validation failed: %s.",strjoin(T.Check(~T.Pass),", "));
end
end

function localPrintSummary(result)
status=result.ScenarioStatus;fig=result.Figures;
sourceStatus=localFamilyStatus(status,"CAL-");llsStatus=localLLSStatus(status);
procedureStatus=localProcedureStatus(status);
fprintf("BWOP AI 10.5.1.3 campaign\n");
fprintf("Analytical: %s\n",localFamilyStatus(status,"ANA-"));
fprintf("Source calibration: %s\n",sourceStatus);
fprintf("Calibrated LLS: %s\n",llsStatus);
fprintf("Procedure SLS: %s\n",procedureStatus);
fprintf("Figures complete: %d/34\n",nnz(fig.Status=="PASS"));
fprintf("TDoc-ready measured figures: %d\n",nnz(fig.Kind=="result"&fig.TDocReady));
fprintf("Blocked figures: %s\n",strjoin(fig.FigureID(fig.Status=="BLOCKED"),", "));
fprintf("Manifest: %s\n",fullfile(result.RunFolder,"metadata","manifest.json"));
fprintf("Report: %s\n",result.Reports.Markdown);
end

function value=localFamilyStatus(T,prefix)
rows=startsWith(T.ScenarioID,prefix);if all(T.Status(rows)=="PASS"),value="PASS";elseif any(T.Status(rows)=="BLOCKED"),value="FAIL";else,value="WARN";end
end

function value=localLLSStatus(T)
rows=ismember(T.PrimaryEvidenceClass,"CALIBRATED_LLS");if all(T.Status(rows)=="PASS"),value="PASS";elseif any(T.Status(rows)=="BLOCKED"),value="FAIL";else,value="WARN";end
end

function value=localProcedureStatus(T)
rows=T.PrimaryEvidenceClass=="PROCEDURE_SLS";if all(T.Status(rows)=="PASS"),value="PASS";elseif any(T.Status(rows)=="BLOCKED"),value="FAIL";else,value="WARN";end
end
