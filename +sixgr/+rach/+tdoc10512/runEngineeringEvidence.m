function out = runEngineeringEvidence(cfg,campaign,runFolder,runID)
%RUNENGINEERINGEVIDENCE Run bounded production waveform RA evidence.
%
% This runner never substitutes configured values for receiver outcomes.
% Its ENGINEERING_LLS classification is intentionally distinct from the
% statistically qualified CALIBRATED_LLS campaign.

eng = campaign.TDoc.engineering;
scenarioID = campaign.ScenarioID;
classification = "ENGINEERING_LLS";
rawRoot = fullfile(runFolder,"raw","engineering_waveform");
sixgr.util.ensureFolder(rawRoot);

snrs = double(eng.full_ra_snr_db(:));
nTrial = double(eng.full_ra_trials_per_snr);
baseSeed = double(eng.full_ra_seed);
raRows = repmat(localRARow(),numel(snrs)*nTrial,1);
row = 0;
for iSNR = 1:numel(snrs)
    for iTrial = 1:nTrial
        row = row+1;
        seed = baseSeed+1000*iSNR+iTrial;
        cfgTrial = cfg;
        cfgTrial.run.seed = seed;
        rng(seed,"twister");
        trialFolder = fullfile(rawRoot,sprintf("ra_snr_%+05.1f_trial_%03d", ...
            snrs(iSNR),iTrial));
        writeArtifacts = iTrial==1;
        result = sixgr.phy.ra.runFourStepRA(cfgTrial, ...
            "RunFolder",trialFolder, ...
            "RunId",runID+"_ra_"+row, ...
            "ScenarioName",scenarioID, ...
            "UEId",1,"CellId",1,"AttemptId",iTrial, ...
            "WriteArtifacts",writeArtifacts, ...
            "RuntimeIntegrationMode","coupled_truth_runtime", ...
            "RequireRuntimeStageWaveforms",true, ...
            "AllowRuntimeStageWaveformComposition",true, ...
            "UseRuntimeChannel",true, ...
            "RuntimeNoiseSNR_dB",snrs(iSNR), ...
            "RuntimeSlot",10);
        raRows(row)=localRARow(result,snrs(iSNR),iTrial,seed,cfgTrial);
    end
end
raTrials=struct2table(raRows,"AsArray",true);
sixgr.util.csvWriteTable(fullfile(rawRoot,"four_step_ra_trials.csv"),raTrials);

falseRows=repmat(localFalseRARow(),double(eng.negative_false_rar_trials),1);
for k=1:numel(falseRows)
    seed=baseSeed+80000+k; cfgTrial=cfg; cfgTrial.run.seed=seed;
    rng(seed,"twister");
    result=sixgr.phy.ra.runFourStepRA(cfgTrial, ...
        "RunFolder",fullfile(rawRoot,sprintf("false_rar_%03d",k)), ...
        "RunId",runID+"_false_rar_"+k,"ScenarioName",scenarioID, ...
        "UEId",1,"CellId",1,"AttemptId",k,"FaultMode","no_prach_detected", ...
        "WriteArtifacts",false,"RuntimeIntegrationMode","coupled_truth_runtime", ...
        "RequireRuntimeStageWaveforms",true, ...
        "AllowRuntimeStageWaveformComposition",true,"UseRuntimeChannel",true, ...
        "RuntimeNoiseSNR_dB",double(eng.contention_snr_db),"RuntimeSlot",10);
    falseRows(k)=localFalseRARow(result,k,seed);
end
falseRAR=struct2table(falseRows,"AsArray",true);
sixgr.util.csvWriteTable(fullfile(rawRoot,"false_rar_trials.csv"),falseRAR);

contention=sixgr.phy.ra.runFourStepRAContentionGroup(cfg, ...
    "UEIds",[1 2],"PreambleIndices",[7 7], ...
    "RelativePowersdB",[0 -6],"SNRdB",double(eng.contention_snr_db), ...
    "Seed",baseSeed+90001);
sixgr.util.csvWriteTable(fullfile(rawRoot,"contention_groups.csv"),contention.Groups);
sixgr.util.csvWriteTable(fullfile(rawRoot,"contention_ues.csv"),contention.UEs);

pucchRows=localRunPUCCH(cfg,eng,baseSeed);
pucchTrials=struct2table(pucchRows,"AsArray",true);
sixgr.util.csvWriteTable(fullfile(rawRoot,"pucch_ack_trials.csv"),pucchTrials);

artifacts=table('Size',[0 7], ...
    'VariableTypes',{'string','string','string','string','string','string','string'}, ...
    'VariableNames',{'ArtifactID','RelativePath','SourceCSV','Classification','Status','SHA256','Notes'});

msg2=localAggregateRate(raTrials,"Msg2PDSCHCrcPass","BLER");
artifacts=[artifacts;localProbabilityArtifact(runFolder,scenarioID, ...
    "R07_msg2_bler_vs_snr",msg2,"SNRdB","BLER", ...
    "Msg2 PDSCH BLER","BLER",classification, ...
    "Production four-step RA Msg2 PDCCH/PDSCH receiver outcomes")]; %#ok<AGROW>

msg3=localAggregateRate(raTrials,"Msg3PUSCHCrcPass","BLER");
artifacts=[artifacts;localProbabilityArtifact(runFolder,scenarioID, ...
    "R08_msg3_bler_vs_snr",msg3,"SNRdB","BLER", ...
    "Msg3 PUSCH BLER","BLER",classification, ...
    "Production four-step RA Msg3 PUSCH/UL-SCH receiver outcomes")]; %#ok<AGROW>

energy=localEnergySummary(raTrials);
artifacts=[artifacts;localBarArtifact(runFolder,scenarioID, ...
    "R10_msg3_energy_per_success",energy,"SNRdB","EnergyPerSuccess", ...
    "Msg3 waveform energy per successful decode","Normalized waveform energy", ...
    classification,"Measured transmitted Msg3 waveform sample energy")]; %#ok<AGROW>

pucch=localAggregatePUCCH(pucchTrials);
artifacts=[artifacts;localProbabilityArtifact(runFolder,scenarioID, ...
    "R12_pucch_ack_error_vs_snr",pucch,"SNRdB","ErrorRate", ...
    "PUCCH HARQ-ACK error rate","ACK error rate",classification, ...
    "Production PUCCH transmitter, runtime channel, and receiver outcomes")]; %#ok<AGROW>

e2e=localAggregateRate(raTrials,"RACompleted","FailureRate");
e2e.SuccessProbability=1-e2e.FailureRate;
e2e.CILower=1-e2e.CIUpper; e2e.CIUpper=1-e2e.CILower_original;
e2e.CILower_original=[];
artifacts=[artifacts;localProbabilityArtifact(runFolder,scenarioID, ...
    "R13_end_to_end_ra_success",e2e,"SNRdB","SuccessProbability", ...
    "End-to-end four-step RA success","Success probability",classification, ...
    "Msg1 through Msg4 and RRCSetupComplete production waveform chain")]; %#ok<AGROW>

latency=sort(raTrials(raTrials.RACompleted,:).LatencySlots);
if isempty(latency)
    latencyTable=table();
else
    latencyTable=table(latency,(1:numel(latency))'/numel(latency), ...
        'VariableNames',{'LatencySlots','EmpiricalCDF'});
end
artifacts=[artifacts;localCDFArtifact(runFolder,scenarioID, ...
    "R14_ra_latency_cdf",latencyTable,"LatencySlots","EmpiricalCDF", ...
    "Four-step RA completion latency CDF","Latency (slots)",classification, ...
    "Slot distance from PRACH occasion to decoded RRCSetupComplete")]; %#ok<AGROW>

resource=localResourceSummary(raTrials);
artifacts=[artifacts;localBarArtifact(runFolder,scenarioID, ...
    "R15_resources_per_success",resource,"SNRdB","REPerSuccess", ...
    "Scheduled resource elements per successful RA","RE per success", ...
    classification,"Actual configured Msg2/Msg3/Msg4 allocations for completed attempts")]; %#ok<AGROW>

falseSummary=table(height(falseRAR),nnz(falseRAR.FalseRAR), ...
    nnz(falseRAR.WastedGrant),mean(falseRAR.FalseRAR), ...
    'VariableNames',{'Trials','FalseRARCount','WastedGrantCount','FalseRARProbability'});
artifacts=[artifacts;localBarArtifact(runFolder,scenarioID, ...
    "R16_false_rar_and_wasted_grants",falseSummary,"Trials","FalseRARProbability", ...
    "False RAR and wasted-grant negative trials","Observed rate",classification, ...
    "Receiver-driven no-preamble negative path; no RAR is created without detection")]; %#ok<AGROW>

pool=contention.Groups(:,intersect(["PreambleIndex","UECount", ...
    "SamePreambleCollision","Msg3CRC","CaptureDetected","Status"], ...
    string(contention.Groups.Properties.VariableNames),'stable'));
pool.Resolved=pool.Status=="PASS";
artifacts=[artifacts;localBarArtifact(runFolder,scenarioID, ...
    "R17_two_four_step_common_pool",pool,"UECount","Resolved", ...
    "Common-pool same-preamble contention outcome","Resolved",classification, ...
    "Production composite PRACH and PUSCH contention evidence; four-step branch")]; %#ok<AGROW>

out=struct("Artifacts",artifacts,"RATrials",raTrials, ...
    "FalseRARTrials",falseRAR,"PUCCHTrials",pucchTrials, ...
    "Contention",contention,"Classification",classification, ...
    "StatisticallyQualified",false,"ExecutionBackend", ...
    "production_PRACH_PDCCH_PDSCH_PUSCH_PUCCH_waveforms");
end

function row=localRARow(r,snr,trial,seed,cfg)
row=struct("SNRdB",NaN,"Trial",NaN,"Seed",NaN, ...
    "PreambleDetected",false,"Msg2PDSCHCrcPass",false, ...
    "Msg3PUSCHCrcPass",false,"Msg4PDSCHCrcPass",false, ...
    "RRCSetupCompleteDecoded",false,"RRCConnected",false, ...
    "RACompleted",false,"StrictOk",false,"FailureReason","", ...
    "ProxyUsed",false,"RuntimeStageWaveformsUsed",false, ...
    "LatencySlots",NaN,"Msg2RE",NaN,"Msg3RE",NaN,"Msg4RE",NaN, ...
    "Msg1WaveformEnergy",NaN,"Msg2WaveformEnergy",NaN, ...
    "Msg3WaveformEnergy",NaN,"Msg4WaveformEnergy",NaN);
if nargin==0, return; end
row.SNRdB=snr; row.Trial=trial; row.Seed=seed;
names=["PreambleDetected","Msg2PDSCHCrcPass","Msg3PUSCHCrcPass", ...
    "Msg4PDSCHCrcPass","RRCSetupCompleteDecoded","RRCConnected", ...
    "RACompleted","StrictOk","ProxyUsed","RuntimeStageWaveformsUsed"];
for name=names, row.(name)=logical(sixgr.util.structGet(r,name,false)); end
row.FailureReason=string(sixgr.util.structGet(r,"FailureReason",""));
row.LatencySlots=double(sixgr.util.structGet(r,"SetupCompleteScheduledSlot", ...
    sixgr.util.structGet(r,"Msg4ScheduledSlot",NaN)))- ...
    double(sixgr.util.structGet(r,"PRACHOccasionSlot",0));
row.Msg2RE=localConfiguredRE(cfg,"random_access.msg2_pdsch");
row.Msg3RE=localRE(r,"Msg3PUSCHNumPRB","Msg3PUSCHNumSymbols");
row.Msg4RE=localConfiguredRE(cfg,"random_access.msg4_pdsch");
row.Msg1WaveformEnergy=localWaveformEnergy(r,"Msg1Tx");
row.Msg2WaveformEnergy=localWaveformEnergy(r,"Msg2Tx");
row.Msg3WaveformEnergy=localWaveformEnergy(r,"Msg3Tx");
row.Msg4WaveformEnergy=localWaveformEnergy(r,"Msg4Tx");
end

function row=localFalseRARow(r,trial,seed)
row=struct("Trial",NaN,"Seed",NaN,"PreambleDetected",false, ...
    "Msg2RARNTIDetected",false,"FalseRAR",false,"WastedGrant",false, ...
    "RACompleted",false,"StrictOk",false,"FailureReason","");
if nargin==0,return;end
row.Trial=trial;row.Seed=seed;
row.PreambleDetected=logical(sixgr.util.structGet(r,"PreambleDetected",false));
row.Msg2RARNTIDetected=logical(sixgr.util.structGet(r,"Msg2RARNTIDetected",false));
row.FalseRAR=~row.PreambleDetected&&row.Msg2RARNTIDetected;
row.WastedGrant=~row.PreambleDetected&&logical(sixgr.util.structGet(r,"RARULGrantValid",false));
row.RACompleted=logical(sixgr.util.structGet(r,"RACompleted",false));
row.StrictOk=logical(sixgr.util.structGet(r,"StrictOk",false));
row.FailureReason=string(sixgr.util.structGet(r,"FailureReason",""));
end

function rows=localRunPUCCH(cfg,eng,baseSeed)
formats=double(eng.pucch_formats(:));snrs=double(eng.pucch_ack_snr_db(:));
n=double(eng.pucch_trials_per_point);
rows=repmat(struct("Format",NaN,"SNRdB",NaN,"Trial",NaN,"Seed",NaN, ...
    "WaveformGenerated",false,"ReceiverUsable",false,"ReceiverDTX",false, ...
    "BitErrors",NaN,"BitsCompared",NaN,"AckError",true,"Ok",false, ...
    "MeasuredSINR_dB",NaN,"ProxyUsed",false,"FailureReason",""), ...
    numel(formats)*numel(snrs)*n,1);
idx=0;
for f=formats.'
    fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(f,[]);
    for s=snrs.'
        for k=1:n
            idx=idx+1;seed=baseSeed+200000+10000*f+100*round(s+50)+k;
            cfgTrial=cfg;cfgTrial.run.seed=seed;
            t=sixgr.link.runPUCCHWaveformTrial(cfgTrial, ...
                "Carrier",fixture.Carrier,"Assignment",fixture.Assignment, ...
                "Report",fixture.Report,"ReceiverContext",fixture.Context, ...
                "ChannelProfile","TDL-C","SNR_dB",s,"SignalPresent",true, ...
                "Seed",seed,"DopplerHz",19.46,"DelaySpreadSeconds",300e-9);
            rows(idx)=struct("Format",f,"SNRdB",s,"Trial",k,"Seed",seed, ...
                "WaveformGenerated",logical(t.WaveformGenerated), ...
                "ReceiverUsable",logical(t.ReceiverUsable), ...
                "ReceiverDTX",logical(t.ReceiverDTX), ...
                "BitErrors",double(t.BitErrors),"BitsCompared",double(t.BitsCompared), ...
                "AckError",logical(~t.Ok),"Ok",logical(t.Ok), ...
                "MeasuredSINR_dB",double(t.MeasuredSINR_dB), ...
                "ProxyUsed",false,"FailureReason",string(t.FailureReason));
        end
    end
end
end

function T=localAggregateRate(trials,passField,rateName)
snrs=unique(double(trials.SNRdB)); rows=zeros(numel(snrs),7);
for k=1:numel(snrs)
    mask=trials.SNRdB==snrs(k); n=nnz(mask); failures=nnz(~trials.(passField)(mask));
    [lo,hi]=localBinomialCI(failures,n,.95);
    rows(k,:)=[snrs(k) n failures failures/n lo hi double(n>=1)];
end
T=array2table(rows,'VariableNames',{'SNRdB','Trials','Errors',char(rateName), ...
    'CILower','CIUpper','Measured'});
T.CILower_original=T.CILower;
end

function T=localAggregatePUCCH(trials)
keys=unique(trials(:,{'Format','SNRdB'}),'rows','stable');
rows=zeros(height(keys),8);
for k=1:height(keys)
    mask=trials.Format==keys.Format(k)&trials.SNRdB==keys.SNRdB(k);
    n=nnz(mask);e=nnz(trials.AckError(mask));[lo,hi]=localBinomialCI(e,n,.95);
    rows(k,:)=[keys.Format(k) keys.SNRdB(k) n e e/n lo hi mean(trials.MeasuredSINR_dB(mask),'omitnan')];
end
T=array2table(rows,'VariableNames',{'Format','SNRdB','Trials','Errors','ErrorRate','CILower','CIUpper','MeanMeasuredSINR_dB'});
end

function T=localEnergySummary(trials)
snrs=unique(trials.SNRdB); rows=zeros(numel(snrs),4);
for k=1:numel(snrs)
    mask=trials.SNRdB==snrs(k); success=nnz(trials.Msg3PUSCHCrcPass(mask));
    energy=sum(trials.Msg3WaveformEnergy(mask),'omitnan');
    rows(k,:)=[snrs(k) nnz(mask) success energy/max(success,1)];
end
T=array2table(rows,'VariableNames',{'SNRdB','Trials','Successes','EnergyPerSuccess'});
end

function T=localResourceSummary(trials)
snrs=unique(trials.SNRdB); rows=zeros(numel(snrs),4);
for k=1:numel(snrs)
    mask=trials.SNRdB==snrs(k); success=nnz(trials.RACompleted(mask));
    re=sum(trials.Msg2RE(mask)+trials.Msg3RE(mask)+trials.Msg4RE(mask),'omitnan');
    rows(k,:)=[snrs(k) nnz(mask) success re/max(success,1)];
end
T=array2table(rows,'VariableNames',{'SNRdB','Trials','Successes','REPerSuccess'});
end

function artifact=localProbabilityArtifact(root,scenario,id,T,xName,yName,titleText,yLabel,classification,notes)
artifact=localPlotArtifact(root,scenario,id,T,xName,yName,titleText,yLabel,classification,notes,"probability");
end
function artifact=localBarArtifact(root,scenario,id,T,xName,yName,titleText,yLabel,classification,notes)
artifact=localPlotArtifact(root,scenario,id,T,xName,yName,titleText,yLabel,classification,notes,"bar");
end
function artifact=localCDFArtifact(root,scenario,id,T,xName,yName,titleText,xLabel,classification,notes)
artifact=localPlotArtifact(root,scenario,id,T,xName,yName,titleText,xLabel,classification,notes,"cdf");
end

function artifact=localPlotArtifact(root,scenario,id,T,xName,yName,titleText,axisLabel,classification,notes,kind)
tableDir=fullfile(root,"tables","figure_sources");figDir=fullfile(root,"figures","engineering_lls");
sixgr.util.ensureFolder(tableDir);sixgr.util.ensureFolder(figDir);
source=fullfile(tableDir,id+".csv");sixgr.util.csvWriteTable(source,T);
sourceTable=T;save(fullfile(tableDir,id+".mat"),"sourceTable","-v7");
path=fullfile(figDir,id+".png");
fig=figure("Visible","off","Color","w","Position",[100 100 1200 720]);
clean=onCleanup(@()close(fig)); %#ok<NASGU>
if isempty(T)
    axis off;text(.5,.5,"No successful waveform observations", ...
        "HorizontalAlignment","center","FontSize",16);
else
    x=double(T.(xName));y=double(T.(yName));
    switch kind
        case "probability"
            if ismember('Format',T.Properties.VariableNames)
                groups=unique(string(T.Format),'stable');colors=lines(numel(groups));hold on;
                for iGroup=1:numel(groups)
                    mask=string(T.Format)==groups(iGroup);[xg,order]=sort(x(mask));yg=y(mask);yg=yg(order);
                    if all(ismember({'CILower','CIUpper'},T.Properties.VariableNames))
                        lo=double(T.CILower(mask));hi=double(T.CIUpper(mask));lo=lo(order);hi=hi(order);
                        errorbar(xg,yg,max(0,yg-lo),max(0,hi-yg),"o-", ...
                            "LineWidth",1.5,"Color",colors(iGroup,:), ...
                            "MarkerFaceColor",colors(iGroup,:), ...
                            "DisplayName","PUCCH Format "+groups(iGroup));
                    else
                        plot(xg,yg,"o-","LineWidth",1.5,"Color",colors(iGroup,:), ...
                            "DisplayName","PUCCH Format "+groups(iGroup));
                    end
                end
                hold off;legend("Location","best");
            elseif all(ismember({'CILower','CIUpper'},T.Properties.VariableNames))
                errorbar(x,y,max(0,y-double(T.CILower)),max(0,double(T.CIUpper)-y), ...
                    "o-","LineWidth",1.5,"MarkerFaceColor",[.1 .45 .8]);
            else, plot(x,y,"o-","LineWidth",1.5); end
            xlabel(strrep(xName,'_',' '));ylabel(axisLabel);ylim([0 1]);grid on;
        case "cdf"
            stairs(x,y,"LineWidth",1.8);xlabel(axisLabel);ylabel("Empirical CDF");ylim([0 1]);grid on;
        otherwise
            labels=string(x);
            if numel(unique(labels))<numel(labels)
                labels=labels+" #"+string((1:numel(labels))');
            end
            bar(categorical(labels),y);xlabel(strrep(xName,'_',' '));ylabel(axisLabel);grid on;
    end
end
localStyleAxes();
title(scenario+" | "+classification+" | "+titleText, ...
    "Interpreter","none","Color",[.08 .12 .18]);
sixgr.util.exportFigureArtifact(fig,path,"Resolution",300);
meta=struct("artifact_id",id,"classification",classification,"status","COMPLETE", ...
    "scenario_id",scenario,"source_csv",string(source), ...
    "source_csv_sha256",localHash(source),"statistically_qualified",false, ...
    "performance_claim",false,"notes",notes, ...
    "producer","sixgr.rach.tdoc10512.runEngineeringEvidence");
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

function [lo,hi]=localBinomialCI(x,n,confidence)
if n<=0,lo=NaN;hi=NaN;return;end
alpha=1-confidence;
if x==0,lo=0;else,lo=betaincinv(alpha/2,x,n-x+1);end
if x==n,hi=1;else,hi=betaincinv(1-alpha/2,x+1,n-x);end
end
function v=localRE(r,prbField,symbolField)
prb=double(sixgr.util.structGet(r,prbField,NaN));sym=double(sixgr.util.structGet(r,symbolField,NaN));v=12*prb*sym;
end
function v=localConfiguredRE(cfg,path)
node=sixgr.util.structGet(cfg,path,struct());
prb=double(sixgr.util.structGet(node,"num_prb",NaN));
sym=double(sixgr.util.structGet(node,"num_symbols",NaN));
v=12*prb*sym;
end
function v=localWaveformEnergy(r,field)
tx=sixgr.util.structGet(r,field,struct());w=sixgr.util.structGet(tx,"Waveform",[]);
if isempty(w),v=NaN;else,v=sum(abs(w(:)).^2,'omitnan');end
end
function value=localRelative(path,root)
p=string(char(java.io.File(char(string(path))).getCanonicalPath()));r=string(char(java.io.File(char(string(root))).getCanonicalPath()));value=erase(p,r+filesep);
end
function value=localHash(path)
fid=fopen(path,'r');if fid<0,error("sixgr:rach:tdoc10512:ArtifactRead","Cannot read %s.",path);end
clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=sixgr.util.sha256Hex(fread(fid,Inf,'*uint8'));
end
