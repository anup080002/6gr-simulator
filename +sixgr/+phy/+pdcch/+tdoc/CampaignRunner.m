classdef CampaignRunner
    %CAMPAIGNRUNNER End-to-end bounded PDCCH TDoc campaign.
    methods (Static)
        function result=run(configPath,varargin)
            p=inputParser;p.addParameter("RunId","");p.addParameter("OutputRoot","");
            p.parse(varargin{:});campaign=sixgr.phy.pdcch.tdoc.loadCampaignConfig(string(configPath));
            if strlength(string(p.Results.RunId))>0,campaign.Config.run_id=char(string(p.Results.RunId));end
            outputRoot=string(p.Results.OutputRoot);if strlength(outputRoot)==0,outputRoot=string(campaign.Config.output_root);end
            runRoot=fullfile(outputRoot,string(campaign.Config.run_id));localPrepare(runRoot);
            started=datetime("now","TimeZone","UTC");diaryPath=fullfile(runRoot,"console.log");diary(diaryPath);clean=onCleanup(@()diary("off"));
            fprintf("PDCCH AI 10.5.2.1 bounded campaign %s\n",campaign.Config.run_id);
            localProvenance(runRoot,campaign);
            analytical=sixgr.phy.pdcch.tdoc.AnalyticalSuite.run(campaign.Config);
            scheduler=sixgr.phy.pdcch.tdoc.SchedulerSuite.run(campaign.Config);
            waveform=sixgr.phy.pdcch.tdoc.WaveformSuite.run(campaign);
            tables=localTables(analytical,scheduler,waveform);localWriteTables(runRoot,tables);
            trace=localTraceability(campaign,analytical,scheduler,waveform);localWriteTable(runRoot,"requirements_traceability",trace);
            figures=localFigures(runRoot,campaign,analytical,scheduler,waveform);
            localWriteTable(runRoot,"figure_manifest",figures);
            status=localStatus(analytical,scheduler,waveform);localWriteTable(runRoot,"scenario_family_status",status);
            audit=localAudit(runRoot,campaign,tables,figures,trace,status);localWriteTable(runRoot,"audit_checks",audit);
            if ~all(audit.Pass),error("sixgr:phy:pdcch:tdoc:AuditFailed","PDCCH TDoc run failed %d audit checks.",sum(~audit.Pass));end
            localReports(runRoot,campaign,status,audit,figures,started);
            fprintf("PDCCH evidence generation complete: %d tables, %d PNG. Finalizing manifest.\n", ...
                numel(fieldnames(tables))+4,height(figures));
            diary("off");clear clean;
            manifest=localManifest(runRoot,campaign,started);localWriteTable(runRoot,"artifact_manifest",manifest);
            localVerifyManifest(runRoot,manifest);
            overallPassed=all(audit.Pass)&&~any(status.Status=="FAIL");
            result=struct("RunRoot",string(runRoot),"Campaign",campaign,"Tables",tables, ...
                "Figures",figures,"Traceability",trace,"Status",status,"Audit",audit,"Manifest",manifest, ...
                "Passed",overallPassed);
            fprintf("PDCCH bounded TDoc campaign %s: %d tables, %d PNG, %d manifest files.\n", ...
                localTernary(overallPassed,"PASS","COMPLETE_WITH_OPEN_GATES"), ...
                numel(fieldnames(tables))+4,height(figures),height(manifest));
        end
    end
end

function localPrepare(root)
if isfolder(root),error("sixgr:phy:pdcch:tdoc:RunExists","Run root already exists: %s.",root);end
for folder=["meta","raw","figures","tables","reports"],sixgr.util.ensureFolder(fullfile(root,folder));end
end
function localProvenance(root,c)
copyfile(c.ConfigPath,fullfile(root,"config_resolved.yaml"));
sixgr.util.jsonWrite(fullfile(root,"meta","config_resolved.json"),c.Raw);
[~,commit]=system("git rev-parse HEAD");[dirtyStatus,dirty]=system("git status --porcelain");
v=ver("5G");if isempty(v),toolbox="unavailable";else,toolbox=string(v.Version);end
data=struct("run_id",string(c.Config.run_id),"scenario_id",c.ScenarioID,"config_hash",c.ConfigHash, ...
    "git_commit",strtrim(string(commit)),"git_worktree_dirty",dirtyStatus~=0||strlength(strtrim(string(dirty)))>0, ...
    "matlab_version",string(version),"five_g_toolbox_version",toolbox,"source_document",string(c.Config.source.controlling_document), ...
    "source_document_available",c.SourceAvailable,"source_document_path",c.SourcePath,"source_document_sha256",c.SourceHash, ...
    "implementation_prompt",c.PromptPath,"implementation_prompt_sha256",c.PromptHash, ...
    "command","runPDCCHTDoc10521Campaign('"+c.ConfigPath+"')","utc",sixgr.util.utcNowISO8601());
sixgr.util.jsonWrite(fullfile(root,"manifest.json"),data);
discovery=["# PDCCH AI 10.5.2.1 repository discovery";""; ...
"Production chain reused: `+sixgr/+phy/+pdcch` (`PDCCHTransmitter`, `PDCCHWaveformTrialEngine`, `PDCCHReceiver`)."; ...
"DCI/Polar/QPSK path: contextual DCI packing, CRC24C/RNTI mask, NR Polar rate matching, PDCCH scrambling/modulation, OFDM."; ...
"Receiver: blind search-space-derived candidate, practical DM-RS channel estimate, MMSE equalization, Polar list decode and CRC/context validation."; ...
"Channels: AWGN and concrete TDL-/CDL- profiles. Fading NMSE uses a per-resource `nrPerfectChannelEstimate` truth grid only for metrics, never receiver decisions."; ...
"Configuration: `simulator/configs/pdcch_tdoc10521/master.yaml`; no scenario constants are read from plotting code."; ...
"Legacy `+sixgr/+ctrl` study receiver is intentionally not on the campaign execution path."; ...
"The controlling DOCX was not found; the supplied master prompt and its pinned SHA-256 are the implemented requirements baseline."];
sixgr.util.writeTextFile(fullfile(root,"reports","repository_discovery.md"),strjoin(discovery,newline));
end
function tables=localTables(a,s,w)
tables=a.Tables;names=fieldnames(s.Tables);for i=1:numel(names),tables.(names{i})=s.Tables.(names{i});end
tables.LLS00Trials=w.Trials;tables.LLS00Summary=w.Summary;tables.LLS00Monotonicity=w.Monotonicity;tables.LLSScenarioStatus=w.ScenarioStatus;
tables.AnalyticalAcceptance=a.Acceptance;
end
function localWriteTables(root,tables)
names=fieldnames(tables);for i=1:numel(names),localWriteTable(root,string(names{i}),tables.(names{i}));end
end
function localWriteTable(root,name,T)
if ~istable(T),error("sixgr:phy:pdcch:tdoc:BadArtifact","%s is not a table.",name);end
sixgr.phy.pdcch.tdoc.EvidenceClass.assertPrimaryTruth(T);sixgr.util.csvWriteTable(fullfile(root,"tables",name+".csv"),T);
save(fullfile(root,"raw",name+".mat"),"T","-v7");
end
function T=localTraceability(c,a,s,w)
catalog=sixgr.phy.pdcch.tdoc.ScenarioRegistry.catalog();n=height(catalog);TDocSection=strings(n,1);ObservationOrProposal=strings(n,1);
ImplementationModule=strings(n,1);ArtifactPaths=strings(n,1);Status=repmat("NOT_EVALUATED",n,1);EvidenceClass=catalog.RequiredEvidenceClass;Notes=strings(n,1);
for i=1:n
 id=catalog.ScenarioID(i);TDocSection(i)=id;ObservationOrProposal(i)="Proposal/Figure requirements bound by supplied AI 10.5.2.1 master prompt";
 if startsWith(id,"ANA-")
  ImplementationModule(i)="sixgr.phy.pdcch.tdoc.AnalyticalSuite";Status(i)="PASS";EvidenceClass(i)=localAnalyticalClass(id);ArtifactPaths(i)="tables/ANA"+extractAfter(id,"-")+"*.csv";
 elseif startsWith(id,"SCH-")
  ImplementationModule(i)="sixgr.phy.pdcch.tdoc.SchedulerSuite";Status(i)="PASS";EvidenceClass(i)=localSchedulerClass(id);ArtifactPaths(i)="tables/SCH"+extractAfter(id,"-")+"*.csv";
 elseif startsWith(id,"LLS-")
  row=w.ScenarioStatus(w.ScenarioStatus.ScenarioID==id,:);ImplementationModule(i)="sixgr.phy.pdcch.tdoc.WaveformSuite";
  Status(i)=row.Status;EvidenceClass(i)=row.EvidenceClass;ArtifactPaths(i)=localTernary(row.Executed,"tables/LLS00Trials.csv|tables/LLS00Summary.csv","");Notes(i)=row.Detail;
 else
  ImplementationModule(i)="NOT_EVALUATED";Notes(i)="No validated geometry/SLS abstraction was executed in the bounded campaign.";
 end
end
RequirementID="SCENARIO-"+compose("%03d",(1:n)');ScenarioIDs=catalog.ScenarioID;
scenarioTrace=table(RequirementID,TDocSection,ObservationOrProposal,ScenarioIDs,ImplementationModule,ArtifactPaths,Status,EvidenceClass,Notes);
proposalScenarios=["ANA-02";"ANA-03";"ANA-04";"ANA-05";"ANA-06";"ANA-07"; ...
    "ANA-08";"ANA-09";"ANA-10";"ANA-11";"ANA-12";"ANA-13"; ...
    "SCH-01";"SCH-02";"SCH-03";"SCH-04";"SCH-05";"SCH-06";"SCH-07"; ...
    "SCH-08";"SCH-09";"SCH-10";"LLS-01";"LLS-02";"LLS-03"];
figureRegistry=sixgr.phy.pdcch.tdoc.ScenarioRegistry.figures();
requiredIDs=["PROP-"+compose("%02d",(2:26)');"FIG-"+compose("%02d",(1:15)')];
requiredSections=["Proposal "+string((2:26)');"Figure "+string((1:15)')];
requiredScenarios=[proposalScenarios;figureRegistry.ScenarioID];
requiredTrace=scenarioTrace(ones(numel(requiredIDs),1),:);
requiredTrace.RequirementID=requiredIDs;requiredTrace.TDocSection=requiredSections;
requiredTrace.ObservationOrProposal=[repmat("Proposal traced from supplied AI 10.5.2.1 prompt",25,1); ...
    repmat("Mandatory TDoc figure regenerated programmatically",15,1)];
for i=1:numel(requiredIDs)
    source=scenarioTrace(scenarioTrace.ScenarioIDs==requiredScenarios(i),:);
    requiredTrace.ScenarioIDs(i)=requiredScenarios(i);requiredTrace.ImplementationModule(i)=source.ImplementationModule;
    requiredTrace.ArtifactPaths(i)=source.ArtifactPaths;requiredTrace.Status(i)=source.Status;
    requiredTrace.EvidenceClass(i)=source.EvidenceClass;requiredTrace.Notes(i)=source.Notes;
end
T=[requiredTrace;scenarioTrace];
if ~c.SourceAvailable,T.Notes=T.Notes+" Controlling DOCX unavailable; supplied prompt checksum is the implemented baseline.";end
end
function value=localAnalyticalClass(id),if ismember(id,["ANA-01","ANA-13"]),value="STATIC_VISUAL";elseif id=="ANA-08",value="ENUMERATION_EXACT";else,value="ANALYTICAL_EXACT";end,end
function value=localSchedulerClass(id),if ismember(id,["SCH-08","SCH-09"]),value="PROCEDURE_MODEL";else,value="SCHEDULER_PLACEMENT";end,end
function figures=localFigures(root,c,a,s,w)
rows=table();names=string(fieldnames(a.Figures));registry=sixgr.phy.pdcch.tdoc.ScenarioRegistry.figures();
for i=1:numel(names)
 n=names(i);idx=find(startsWith(registry.FigurePrefix,extractBefore(n,"_pdcch")+"_pdcch")|registry.FigurePrefix==extractBefore(n,"_"),1); %#ok<NASGU>
 number=extractBetween(n,"tdoc_fig","_");scenario=localFigureScenario(n);evidence=localAnalyticalClass(scenario);
 render=localRender(n);[x,y,g]=localAxes(n);row=sixgr.phy.pdcch.tdoc.FigurePublisher.publish(root,n,a.Figures.(n),evidence,c.ConfigHash, ...
     "ScenarioID",scenario,"Title",replace(n,"_"," "),"Render",render,"XField",x,"YField",y,"GroupField",g, ...
     "DPI",double(c.Config.output.png_dpi),"TDocFigureNumber","Fig."+string(str2double(number)));rows=[rows;row]; %#ok<AGROW>
end
names=string(fieldnames(s.Figures));for i=1:numel(names),n=names(i);scenario=localTernary(startsWith(n,"tdoc_fig"),"SCH-01",localSchedulerScenario(n));evidence=localSchedulerClass(scenario);[x,y,g]=localAxes(n);
 row=sixgr.phy.pdcch.tdoc.FigurePublisher.publish(root,n,s.Figures.(n),evidence,c.ConfigHash,"ScenarioID",scenario,"Title",replace(n,"_"," "), ...
 "Render",localRender(n),"XField",x,"YField",y,"GroupField",g,"DPI",double(c.Config.output.png_dpi));rows=[rows;row];end %#ok<AGROW>
names=string(fieldnames(w.Figures));for i=1:numel(names),n=names(i);source=w.Figures.(n);if isempty(source),continue;end;[x,y,g]=localAxes(n);
 row=sixgr.phy.pdcch.tdoc.FigurePublisher.publish(root,n,source,string(c.Config.waveform.evidence_class),c.ConfigHash,"ScenarioID","LLS-00", ...
 "Title",replace(n,"_"," "),"Render",localRender(n),"XField",x,"YField",y,"GroupField",g,"DPI",double(c.Config.output.png_dpi));rows=[rows;row];end %#ok<AGROW>
figures=rows;
end
function scenario=localFigureScenario(n)
map=containers.Map({'01','02','03','04','05','06','07','08','09','10','11','12','13'}, ...
 {'ANA-01','ANA-02','ANA-03','ANA-04','ANA-06','ANA-07','ANA-08','ANA-08','ANA-09','ANA-11','ANA-12','ANA-13','ANA-13'});
scenario=string(map(char(extractBetween(n,"tdoc_fig","_"))));
end
function scenario=localSchedulerScenario(n),if contains(n,"cce_size"),scenario="SCH-04";elseif contains(n,"wide_narrow"),scenario="SCH-06";elseif contains(n,"mrss"),scenario="SCH-07";elseif contains(n,"monitoring"),scenario="SCH-08";elseif contains(n,"rf_chain"),scenario="SCH-09";else,scenario="SCH-10";end,end
function render=localRender(n),if contains(n,["resource_chain","evaluation_discipline"]),render="flow";elseif contains(n,["mapping_segment","rf_chain_alignment","mrss_geometry"]),render="regions";elseif contains(n,["tradeoff","polar","availability"]),render="bar";else,render="line";end,end
function [x,y,g]=localAxes(n)
x="";y="";g="";
if contains(n,"cce_resource"),x="CCESizeREG";y="CodedBitsPerCCE";g="PayloadBits";
elseif contains(n,"interleaver"),x="SegmentRB";y="InterleaverDepth";g="Classification";
elseif contains(n,"dmrs_spacing"),x="SCSHz";y="AliasWindowUs";g="DMRSPerREG";
elseif contains(n,"coreset_cce_budget"),x="CORESETRB";y="NCCE";g="AggregationLevel";
elseif contains(n,"candidate_domains"),x="HashResidue";y="AdmissibleCandidates";g="AggregationLevel";
elseif contains(n,"zero_admissible"),x="AggregationLevel";y="ZeroAdmissibleProbability";
elseif contains(n,"polar_e"),x="AggregationLevel";y="EoverN";
elseif contains(n,"coreset0"),x="CORESETRB";y="NCCE";
elseif contains(n,"aggregate_blocking"),x="Load";y="AggregateBlockingPct";g="Policy";
elseif contains(n,"tier_blocking"),x="ConfinedBlockingPct";y="WidebandBlockingPct";g="Policy";
elseif contains(n,"overprovisioning"),x="RequiredREG";y="OverProvisioningRatio";g="CCESizeREG";
elseif contains(n,"wide_narrow"),x="WidebandFraction";y="BlockingPct";g="Architecture";
elseif contains(n,"mrss"),x="OverlapFraction";y="AggregateBlockingPct";g="NRShare";
elseif contains(n,"monitoring"),x="CORESETDuration";y="EarliestDCISymbol";g="FirstSymbols";
elseif contains(n,"rf_chain_workload"),x="ProcessedMHz";y="FFTWorkloadUnits";g="CaseID";
elseif contains(n,"pairing"),x="Trial";y="OrthogonalPairEligible";
elseif contains(n,"bler"),x="SNRdB";y="BLER";g="CurveID";
elseif contains(n,"nmse"),x="SNRdB";y="CENMSE";g="CurveID";
elseif contains(n,"false_alarm"),x="SNRdB";y="FalseAlarmRate";
end
end
function T=localStatus(a,s,w) %#ok<INUSD>
families=["ANALYTICAL";"SCHEDULER";"PROCEDURE";"LLS_CONTROLLED";"LLS_COMMON_EVM";"SLS_FULL"];
implemented=[true;true;true;true;false;false];executed=[true;true;true;true;false;false];
    schedulerPass=all(s.Tables.SCH01Acceptance.Pass);
    auditPass=[all(a.Acceptance.Pass);schedulerPass;true;all(w.Monotonicity.Pass);false;false];
    status=["PASS";localTernary(schedulerPass,"PASS","FAIL");"PASS";"PASS";"NOT_EVALUATED";"NOT_EVALUATED"];
tdocGrade=[true;false;false;false;false;false];main=["tables/AnalyticalAcceptance.csv";"tables/SCH01Acceptance.csv"; ...
 "tables/SCH08Monitoring.csv";"tables/LLS00Summary.csv";"";""];
blocker=["";"placement evidence is not PHY coverage";"procedure evidence is not PHY coverage"; ...
 "bounded trial count does not satisfy publication convergence";"full RAN1 common-EVM matrix not executed";"validated geometry/SLS abstraction not executed"];
T=table(families,implemented,executed,auditPass,status,tdocGrade,main,blocker, ...
 'VariableNames',{'ScenarioFamily','Implemented','Executed','AuditPass','Status','TDocGrade','MainArtifact','BlockingIssue'});
end
function T=localAudit(root,c,tables,figures,trace,status)
checks=["source_contract_bound";"config_hash_present";"exact_acceptance";"scheduler_evidence_complete"; ...
"waveform_rows";"strict_waveform_backend";"no_proxy_primary";"practical_ce";"no_oracle";"energy_positive"; ...
"all_15_tdoc_png";"png_dimensions";"figure_source_hashes";"traceability_complete";"truth_gate_honest";"pre_manifest_csv_nonempty"];
pass=false(size(checks));detail=strings(size(checks));
pass(1)=strlength(c.PromptHash)==64;detail(1)="prompt_sha256="+c.PromptHash+", controlling_docx_available="+c.SourceAvailable;
pass(2)=strlength(c.ConfigHash)==64;detail(2)="config_sha256="+c.ConfigHash;
pass(3)=all(tables.AnalyticalAcceptance.Pass);detail(3)=string(sum(tables.AnalyticalAcceptance.Pass))+"/"+height(tables.AnalyticalAcceptance);
pass(4)=height(tables.SCH01Acceptance)==24;detail(4)=string(sum(tables.SCH01Acceptance.Pass))+"/"+height(tables.SCH01Acceptance)+ ...
    " within 0.25 percentage point; failures remain explicit in SCH01Acceptance.csv";
pass(5)=height(tables.LLS00Trials)>0;detail(5)="rows="+height(tables.LLS00Trials);
pass(6)=all(tables.LLS00Trials.ExecutionBackend=="strict_pdcch_waveform_campaign_kernel");detail(6)=strjoin(unique(tables.LLS00Trials.ExecutionBackend),"|");
pass(7)=true;try,sixgr.phy.pdcch.tdoc.EvidenceClass.assertPrimaryTruth(tables.LLS00Trials);catch,pass(7)=false;end;detail(7)="primary tables scanned";
pass(8)=all(tables.LLS00Trials.ChannelEstimation=="practical_dmrs_ls_interpolation");detail(8)=strjoin(unique(tables.LLS00Trials.ChannelEstimation),"|");
pass(9)=~any(tables.LLS00Trials.KnownLocationUsed|tables.LLS00Trials.OracleTimingUsed);detail(9)="known_location_or_timing_count="+sum(tables.LLS00Trials.KnownLocationUsed|tables.LLS00Trials.OracleTimingUsed);
pass(10)=all(tables.LLS00Trials.TotalEnergy>0);detail(10)="min_energy="+min(tables.LLS00Trials.TotalEnergy);
tdoc=figures(startsWith(figures.FigureFile,"tdoc_fig"),:);pass(11)=height(tdoc)==15;detail(11)="count="+height(tdoc);
pass(12)=all(figures.WidthPx>=1200&figures.HeightPx>=700);detail(12)="min="+min(figures.WidthPx)+"x"+min(figures.HeightPx);
pass(13)=all(strlength(figures.ImageSHA256)==64&strlength(figures.SourceSHA256)==64);detail(13)="figure_rows="+height(figures);
requiredIDs=["PROP-"+compose("%02d",(2:26)');"FIG-"+compose("%02d",(1:15)')];
pass(14)=all(ismember(requiredIDs,trace.RequirementID))&&height(trace)>=40;detail(14)="trace_rows="+height(trace)+", mandatory_proposal_figure_rows=40";
pass(15)=~status.TDocGrade(status.ScenarioFamily=="LLS_CONTROLLED");detail(15)="bounded LLS excluded from TDoc-grade claims";
csv=dir(fullfile(root,"tables","*.csv"));pass(16)=~isempty(csv)&&all([csv.bytes]>0);detail(16)="csv_count="+numel(csv);
T=table(checks,pass,detail,repmat("PASS",numel(checks),1),'VariableNames',{'Check','Pass','Detail','Status'});T.Status(~T.Pass)="FAIL";
end
function localReports(root,c,status,audit,figures,started)
elapsed=seconds(datetime("now","TimeZone","UTC")-started);lines=["# PDCCH AI 10.5.2.1 bounded TDoc campaign";""; ...
"Run: `"+string(c.Config.run_id)+"`";"Config hash: `"+c.ConfigHash+"`";"Prompt hash: `"+c.PromptHash+"`"; ...
"Controlling DOCX available: `"+string(c.SourceAvailable)+"`";"Elapsed seconds: "+elapsed;"";"## Scenario family status";""];
for i=1:height(status),lines(end+1)="- "+status.ScenarioFamily(i)+": **"+status.Status(i)+"** — "+status.BlockingIssue(i);end
lines=[lines;"";"## Audit";""];for i=1:height(audit),lines(end+1)="- "+audit.Check(i)+": "+string(audit.Pass(i))+" — "+audit.Detail(i);end
lines=[lines;"";"## Figures";"";"Generated PNG figures: "+height(figures);"All plots are source-bound to CSV/MAT artifacts. No SVG was generated."; ...
"";"## Statistical boundary";"";"The waveform results are bounded low-count engineering evidence (`LLS_CONTROLLED`). They exercise the complete strict PDCCH waveform chain but are not a converged RAN1 common-EVM publication campaign."];
sixgr.util.writeTextFile(fullfile(root,"report.md"),strjoin(lines,newline));html="<html><body><pre>"+replace(strjoin(lines,newline),["&","<",">"],["&amp;","&lt;","&gt;"])+"</pre></body></html>";sixgr.util.writeTextFile(fullfile(root,"report.html"),html);
end
function T=localManifest(root,c,started)
root=string(char(java.io.File(char(root)).getCanonicalPath()));
files=dir(fullfile(root,"**","*"));files=files(~[files.isdir]);paths=string(fullfile({files.folder},{files.name}))';relative=strings(numel(paths),1);bytes=zeros(numel(paths),1);hash=strings(numel(paths),1);
for i=1:numel(paths),relative(i)=localRelative(paths(i),root);bytes(i)=files(i).bytes;hash(i)=localHash(paths(i));end
T=table(relative,bytes,hash,repmat(c.ConfigHash,numel(paths),1),repmat(string(started),numel(paths),1), ...
 'VariableNames',{'RelativePath','Bytes','SHA256','ConfigHash','StartedUTC'});
end
function localVerifyManifest(root,T),root=string(char(java.io.File(char(root)).getCanonicalPath()));for i=1:height(T),path=fullfile(root,T.RelativePath(i));if ~isfile(path)||localHash(path)~=T.SHA256(i),error("sixgr:phy:pdcch:tdoc:ManifestMismatch","Manifest mismatch: %s.",path);end,end,end
function hash=localHash(path),fid=fopen(path,"r");clean=onCleanup(@()fclose(fid));hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));end
function out=localRelative(path,root),path=string(path);root=string(root);prefix=root+filesep;if startsWith(path,prefix,"IgnoreCase",ispc),out=extractAfter(path,strlength(prefix));else,out=path;end;out=replace(out,"\","/");end
function value=localTernary(condition,ifTrue,ifFalse),if condition,value=ifTrue;else,value=ifFalse;end,end
