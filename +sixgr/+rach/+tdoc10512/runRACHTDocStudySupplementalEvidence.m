function out=runRACHTDocStudySupplementalEvidence(cfg,campaign,runFolder,baseEvidence)
%RUNSUPPLEMENTALEVIDENCE Close measured R03/R05/R09/R11 engineering rows.
eng=campaign.TDoc.engineering; classification="ENGINEERING_LLS";
rawRoot=fullfile(runFolder,"raw","supplemental_engineering");
sixgr.util.ensureFolder(rawRoot);

cfoScenarios=localCFOScenarios(eng);
cfoOut=sixgr.rach.runPRACHLLS(cfg,"WriteOutputs",false, ...
    "ScenarioMatrix",cfoScenarios,"Verbose",false);
sixgr.util.csvWriteTable(fullfile(rawRoot,"prach_cfo_trials.csv"),cfoOut.ROTable);
cfo=localCFOSummary(cfoOut.ROTable);
r03=localPlot(runFolder,campaign.ScenarioID,"R03_prach_cfo_error_cdf", ...
    cfo,"AbsoluteCFOErrorHz","EmpiricalCDF","PRACH CFO-estimation error CDF", ...
    "Absolute CFO error (Hz)",classification,"cdf", ...
    "Receiver-estimated CFO from production PRACH waveform trials");

type2Scenarios=localType2Scenarios(eng);
type2Out=sixgr.rach.runPRACHLLS(cfg,"WriteOutputs",false, ...
    "ScenarioMatrix",type2Scenarios,"Verbose",false);
sixgr.util.csvWriteTable(fullfile(rawRoot,"prach_type2_trials.csv"),type2Out.ROTable);
type2=localType2Summary(type2Out.ROTable,type2Scenarios);
r05=localPlot(runFolder,campaign.ScenarioID,"R05_prach_type2_fd_by_tier", ...
    type2,"Tier","Type2FalseDetectionProbability", ...
    "Inter-cell PRACH Type-2 false detection by reuse tier", ...
    "Type-2 FD probability",classification,"probability", ...
    "Waveform interferer trials at YAML-owned tier-relative receive powers; not a geometry SLS");

mpl=localMPL(baseEvidence.RATrials,cfg,eng);
r09=localPlot(runFolder,campaign.ScenarioID,"R09_msg3_mpl",mpl, ...
    "SNRdB","DemonstratedMPLBound_dB","Msg3 demonstrated coupling-loss bound", ...
    "Coupling-loss bound (dB)",classification,"bar", ...
    "Link-budget mapping of measured Msg3 receiver outcomes; not a 1% BLER crossing");

fit=localCompleteFit(campaign.Resolved,eng);
sixgr.util.csvWriteTable(fullfile(rawRoot,"msg3_complete_fit_trials.csv"),fit.Trials);
r11=localPlot(runFolder,campaign.ScenarioID, ...
    "R11_msg3_fit_substitution_probability",fit.Summary,"Outcome", ...
    "Probability","Msg3 complete-fit and substitution outcome", ...
    "Probability",classification,"bar", ...
    "Deterministic Monte Carlo over exact PRB/symbol complete-fit checks from YAML candidates");

out=struct("Artifacts",[r03;r05;r09;r11],"CFO",cfoOut, ...
    "Type2",type2Out,"MPL",mpl,"CompleteFit",fit, ...
    "StatisticallyQualified",false,"Classification",classification);
end

function rows=localCFOScenarios(eng)
offsets=double(eng.cfo_offsets_hz(:));base=localScenario();
rows=repmat(base,numel(offsets),1);
for k=1:numel(offsets)
    rows(k)=base;
    if offsets(k)<0, signToken="neg"; elseif offsets(k)>0, signToken="pos"; else, signToken="zero"; end
    rows(k).ScenarioName=sprintf("cfo_%s_%g_hz",signToken,abs(offsets(k)));
    rows(k).UEFrequencyOffsetHz=offsets(k);rows(k).TRPFrequencyOffsetHz=0;
    rows(k).NumTrials=double(eng.cfo_trials_per_point);
    rows(k).EnableFrequencyOffset=true;
    rows(k).EnableFrequencyEstimationMetric=true;
end
end

function rows=localType2Scenarios(eng)
tiers=localRecords(eng.type2_tiers);base=localScenario();
rows=repmat(base,numel(tiers),1);
for k=1:numel(tiers)
    tier=tiers{k};rows(k)=base;
    rows(k).ScenarioName="type2_tier_"+string(tier.tier);
    rows(k).NumTrials=double(eng.type2_trials_per_tier);
    rows(k).ActivePreamblePattern=false;
    rows(k).InterfererActivePreamblePattern=true;
    rows(k).InterfererPreambleIndex=7;
    rows(k).EnableInterCellInterference=true;
    rows(k).InterCellRelativePower_dB=double(tier.inter_cell_relative_power_db);
    rows(k).EnableFrequencyOffset=false;
    rows(k).EnableFrequencyEstimationMetric=false;
end
end

function s=localScenario()
s=struct("ScenarioName","", ...
    "CarrierFrequencyHz",7e9,"FrequencyRange","FR1", ...
    "DuplexMode","TDD","CarrierSCSkHz",30,"NSizeGrid",273, ...
    "NCellID",42,"PRACHConfigurationIndex",157,"PRACHFormat","B4", ...
    "PRACHSubcarrierSpacing",30,"SequenceIndex",1, ...
    "LogicalRootSequenceIndex",1,"PreambleIndex",7, ...
    "RestrictedSet","UnrestrictedSet","ZeroCorrelationZone",8, ...
    "FrequencyStart",0,"NumPRACHOccasions",1,"NumSlots",80, ...
    "NumSubframes",10,"NumTrials",1,"ActivePreamblePattern",true, ...
    "InterfererActivePreamblePattern",true,"InterfererPreambleIndex",14, ...
    "NumRxAntennas",4,"NumTxAntennas",1,"NumUEsPerRO",1, ...
    "EnableCollisionMode",false,"EnableInterCellInterference",false, ...
    "EnableFrequencyOffset",false,"EnablePhaseNoise",false, ...
    "EnableTimingUncertainty",false,"EnableFrequencyEstimationMetric",false, ...
    "DetectionThresholdMode","fixed","DetectionThreshold",0.35, ...
    "SNRSweep_dB",20,"ThresholdSweep",0.35,"ChannelModel","TDL-C", ...
    "DelaySpread_ns",300,"Speed_kmh",3,"CellRadius_m",1155, ...
    "TimingUncertaintyMin_us",0,"TimingUncertaintyMax_us",0, ...
    "UEFrequencyOffsetHz",0,"TRPFrequencyOffsetHz",0, ...
    "PhaseNoiseStdRad",0,"InterCellRelativePower_dB",-6, ...
    "TargetFalseAlarmProbability",1e-3,"TimingTolerance_us",0.25, ...
    "Seed",10512301);
end

function T=localCFOSummary(ro)
err=abs(double(ro.frequency_error_hz));valid=isfinite(err);
err=sort(err(valid));
T=table(err,(1:numel(err))'/max(numel(err),1), ...
    'VariableNames',{'AbsoluteCFOErrorHz','EmpiricalCDF'});
end

function T=localType2Summary(ro,scenarios)
n=numel(scenarios);rows=zeros(n,8);
for k=1:n
    mask=string(ro.scenario_id)==lower(string(scenarios(k).ScenarioName));
    count=nnz(mask);events=nnz(logical(ro.type2_false_detection(mask)));
    [lo,hi]=localCI(events,count,.95);
    token=regexp(char(scenarios(k).ScenarioName),'(\d+)$','tokens','once');
    tier=str2double(token{1});
    rows(k,:)=[tier scenarios(k).InterCellRelativePower_dB count events ...
        events/max(count,1) lo hi double(count>0)];
end
T=array2table(rows,'VariableNames',{'Tier','InterCellRelativePower_dB', ...
    'Trials','Type2FalseDetections','Type2FalseDetectionProbability', ...
    'CILower','CIUpper','Measured'});
end

function T=localMPL(ra,cfg,eng)
lb=eng.msg3_link_budget;snrs=unique(double(ra.SNRdB));rows=zeros(numel(snrs),10);
prb=double(sixgr.util.structGet(cfg,"random_access.msg3_pusch.num_prb",24));
scs=double(sixgr.util.structGet(cfg,"frame.scs_khz",30))*1e3;
bw=prb*12*scs;
noise=double(lb.receiver_noise_density_dbm_hz)+10*log10(bw)+ ...
    double(lb.gnb_noise_figure_db)+double(lb.implementation_loss_db);
for k=1:numel(snrs)
    mask=ra.SNRdB==snrs(k);n=nnz(mask);ok=nnz(ra.Msg3PUSCHCrcPass(mask));
    mpl=double(lb.ue_pcmax_dbm)-(noise+snrs(k));
    rows(k,:)=[snrs(k) n ok ok/max(n,1) bw noise double(lb.ue_pcmax_dbm) ...
        mpl double(ok==n) double(ok>0)];
end
T=array2table(rows,'VariableNames',{'SNRdB','Trials','Msg3Successes', ...
    'Msg3SuccessProbability','AllocationBandwidthHz','ReceiverNoisePower_dBm', ...
    'UEPCMAX_dBm','DemonstratedMPLBound_dB','AllTrialsPassed','AnyTrialPassed'});
end

function out=localCompleteFit(cfg,eng)
shapes=localRecords(cfg.tdoc10512.msg3_shapes);sbfd=cfg.tdoc10512.sbfd;
widths=double(sbfd.ul_subband_widths_mhz(:));guards=double(sbfd.edge_guard_prbs(:));
n=double(eng.complete_fit_trials);rng(double(eng.complete_fit_seed),'twister');
rows=repmat(struct("Trial",NaN,"SubbandMHz",NaN,"GuardPRB",NaN, ...
    "AvailablePRB",NaN,"AvailableSymbols",NaN,"PreferredShape","S1", ...
    "SelectedShape","","PreferredFits",false,"SubstitutionUsed",false, ...
    "NoFit",false,"Outcome",""),n,1);
for k=1:n
    width=widths(randi(numel(widths)));guard=guards(randi(numel(guards)));
    availablePRB=max(0,floor(width/double(sbfd.prb_bandwidth_mhz))-2*guard);
    availableSymbols=14*(1+(rand>.5));
    [selected,preferredFits]=localSelectShape(shapes,availablePRB,availableSymbols);
    substitution=strlength(selected)>0&&selected~="S1";
    noFit=strlength(selected)==0;
    if noFit,outcome="NO_FIT";elseif substitution,outcome="SUBSTITUTED";else,outcome="PREFERRED_FIT";end
    rows(k)=struct("Trial",k,"SubbandMHz",width,"GuardPRB",guard, ...
        "AvailablePRB",availablePRB,"AvailableSymbols",availableSymbols, ...
        "PreferredShape","S1","SelectedShape",selected, ...
        "PreferredFits",preferredFits,"SubstitutionUsed",substitution, ...
        "NoFit",noFit,"Outcome",outcome);
end
trials=struct2table(rows,"AsArray",true);cats=["PREFERRED_FIT";"SUBSTITUTED";"NO_FIT"];
count=arrayfun(@(x)nnz(trials.Outcome==x),cats);
summary=table(cats,count,count/n,'VariableNames',{'Outcome','Count','Probability'});
out=struct("Trials",trials,"Summary",summary,"Seed",double(eng.complete_fit_seed));
end

function [selected,preferredFits]=localSelectShape(shapes,availablePRB,availableSymbols)
order=["S1","S2","S0"];selected="";preferredFits=false;
for k=1:numel(order)
    idx=find(cellfun(@(x)string(x.id)==order(k),shapes),1);
    if isempty(idx),continue;end
    s=shapes{idx};symbolNeed=min(double(s.symbols(:)));
    fits=double(s.prbs)<=availablePRB&&symbolNeed<=availableSymbols;
    if k==1,preferredFits=fits;end
    if fits,selected=order(k);return;end
end
end

function artifact=localPlot(root,scenario,id,T,xName,yName,titleText,axisLabel,classification,kind,notes)
tableDir=fullfile(root,"tables","figure_sources");figDir=fullfile(root,"figures","engineering_lls");
sixgr.util.ensureFolder(tableDir);sixgr.util.ensureFolder(figDir);
source=fullfile(tableDir,id+".csv");sixgr.util.csvWriteTable(source,T);
sourceTable=T;save(fullfile(tableDir,id+".mat"),"sourceTable","-v7");
path=fullfile(figDir,id+".png");fig=figure("Visible","off","Color","w","Position",[100 100 1200 720]);
clean=onCleanup(@()close(fig)); %#ok<NASGU>
x=T.(xName);y=double(T.(yName));
switch kind
    case "probability"
        xd=double(x);errorbar(xd,y,max(0,y-double(T.CILower)), ...
            max(0,double(T.CIUpper)-y),"o-","LineWidth",1.5, ...
            "MarkerFaceColor",[.1 .45 .8]);ylim([0 1]);grid on;
    case "cdf"
        stairs(double(x),y,"LineWidth",1.8);ylim([0 1]);grid on;
    otherwise
        bar(categorical(string(x)),y);grid on;
end
if kind=="cdf"
    xlabel("Absolute CFO error (Hz)");ylabel("Empirical CDF");
else
    xlabel(strrep(xName,'_',' '));ylabel(axisLabel);
end
localStyleAxes();
title(scenario+" | "+classification+" | "+titleText, ...
    "Interpreter","none","Color",[.08 .12 .18]);
sixgr.util.exportFigureArtifact(fig,path,"Resolution",300);
meta=struct("artifact_id",id,"classification",classification,"status","COMPLETE", ...
    "scenario_id",scenario,"source_csv",string(source),"source_csv_sha256",localHash(source), ...
    "statistically_qualified",false,"performance_claim",false,"notes",notes, ...
    "producer","sixgr.rach.tdoc10512.runRACHTDocStudySupplementalEvidence");
sixgr.util.jsonWrite(fullfile(figDir,id+".json"),meta);
artifact=table(id,string(localRelative(path,root)),string(localRelative(source,root)), ...
    classification,"COMPLETE",localHash(path),notes, ...
    'VariableNames',{'ArtifactID','RelativePath','SourceCSV','Classification','Status','SHA256','Notes'});
end

function localStyleAxes
ax=gca;set(ax,"Color","w","XColor",[.12 .15 .20], ...
    "YColor",[.12 .15 .20],"GridColor",[.65 .69 .74], ...
    "MinorGridColor",[.78 .81 .85],"LineWidth",.8,"FontSize",10);
end

function rows=localRecords(value)
if iscell(value),rows=value(:);else,rows=arrayfun(@(x)x,value(:),'UniformOutput',false);end
end
function [lo,hi]=localCI(x,n,c)
if n<=0,lo=NaN;hi=NaN;return;end;a=1-c;
if x==0,lo=0;else,lo=betaincinv(a/2,x,n-x+1);end
if x==n,hi=1;else,hi=betaincinv(1-a/2,x+1,n-x);end
end
function value=localRelative(path,root)
p=string(char(java.io.File(char(string(path))).getCanonicalPath()));r=string(char(java.io.File(char(string(root))).getCanonicalPath()));value=erase(p,r+filesep);
end
function value=localHash(path)
fid=fopen(path,'r');if fid<0,error("sixgr:rach:tdoc10512:ArtifactRead","Cannot read %s.",path);end
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=sixgr.util.sha256Hex(fread(fid,Inf,'*uint8'));
end
