function artifacts=writeStrictMeasuredArtifacts(runFolder,strict,campaign,classification)
%WRITESTRICTMEASUREDARTIFACTS Render R01/R02/R04/R06 from strict trials.

tables=strict.ArtifactTables;
artifacts=table('Size',[0 7], ...
    'VariableTypes',{'string','string','string','string','string','string','string'}, ...
    'VariableNames',{'ArtifactID','RelativePath','SourceCSV','Classification','Status','SHA256','Notes'});

md=tables.prach_missed_detection_sweep;
% Normalize the specialized strict-statistics column names so the generic
% probability renderer cannot silently omit zero-event confidence bounds.
md.CILower=double(md.MissedDetectionCILower);
md.CIUpper=double(md.MissedDetectionCIUpper);
artifacts=[artifacts;localPlot(runFolder,campaign.ScenarioID, ...
    "R01_prach_mdr_vs_snr",md,"SNRdB","MissedDetectionProbability", ...
    "Measured PRACH missed-detection probability","Missed-detection probability", ...
    classification,"probability", ...
    "Strict receiver-only waveform detections with exact binomial intervals")]; %#ok<AGROW>

trials=tables.prach_trials;
timingMask=isfinite(double(trials.TimingErrorSamples)) & ...
    isfinite(double(trials.WaveformSampleRateHz)) & ...
    double(trials.WaveformSampleRateHz)>0 & logical(trials.PreambleIndexMatch);
errorUs=abs(double(trials.TimingErrorSamples(timingMask)))./ ...
    double(trials.WaveformSampleRateHz(timingMask))*1e6;
errorUs=sort(errorUs);
timing=table(errorUs,(1:numel(errorUs))'/max(numel(errorUs),1), ...
    'VariableNames',{'AbsoluteTimingError_us','EmpiricalCDF'});
artifacts=[artifacts;localPlot(runFolder,campaign.ScenarioID, ...
    "R02_prach_timing_error_cdf",timing,"AbsoluteTimingError_us","EmpiricalCDF", ...
    "PRACH timing-estimation error CDF","Empirical CDF", ...
    classification,"cdf", ...
    "Receiver timing estimates converted using each waveform sample rate")]; %#ok<AGROW>

signalMask=isfinite(double(trials.PreambleIndexTx)) & ...
    isfinite(double(trials.PreambleIndexDetected));
signal=trials(signalMask,:);snrs=unique(double(signal.SNRdB));
fdRows=zeros(numel(snrs),7);
for k=1:numel(snrs)
    mask=double(signal.SNRdB)==snrs(k);n=nnz(mask);
    e=nnz(~logical(signal.PreambleIndexMatch(mask)));[lo,hi]=localCI(e,n,.95);
    fdRows(k,:)=[snrs(k) n e e/max(n,1) lo hi double(n>0)];
end
fd=array2table(fdRows,'VariableNames',{'SNRdB','Trials','Type1FalseDetections', ...
    'Type1FalseDetectionProbability','CILower','CIUpper','Measured'});
artifacts=[artifacts;localPlot(runFolder,campaign.ScenarioID, ...
    "R04_prach_type1_fd",fd,"SNRdB","Type1FalseDetectionProbability", ...
    "PRACH Type-1 false-detection probability","Type-1 FD probability", ...
    classification,"probability", ...
    "Detected local preamble differs from the transmitted local preamble")]; %#ok<AGROW>

mapping=tables.prach_restricted_set_mapping;
keys=unique(mapping(:,{'RootSequenceIndex','RestrictedSet'}),'rows','stable');
valid=zeros(height(keys),1);total=zeros(height(keys),1);
for k=1:height(keys)
    mask=double(mapping.RootSequenceIndex)==double(keys.RootSequenceIndex(k)) & ...
        string(mapping.RestrictedSet)==string(keys.RestrictedSet(k));
    valid(k)=nnz(logical(mapping.Valid(mask)));total(k)=nnz(mask);
end
capacity=[keys table(valid,total,valid./max(total,1), ...
    'VariableNames',{'ValidCyclicShifts','CandidateCyclicShifts','ValidFraction'})];
artifacts=[artifacts;localPlot(runFolder,campaign.ScenarioID, ...
    "R06_restricted_set_valid_shifts",capacity,"RootSequenceIndex","ValidCyclicShifts", ...
    "Restricted-set valid cyclic shifts","Valid cyclic shifts", ...
    classification,"bar", ...
    "Exact production restricted-set/root/cyclic-shift mapper output")]; %#ok<AGROW>
end

function artifact=localPlot(root,scenario,id,T,xName,yName,titleText,yLabel,classification,kind,notes)
tableDir=fullfile(root,"tables","figure_sources");figDir=fullfile(root,"figures","measured_prach");
sixgr.util.ensureFolder(tableDir);sixgr.util.ensureFolder(figDir);
source=fullfile(tableDir,id+".csv");sixgr.util.csvWriteTable(source,T);
sourceTable=T;save(fullfile(tableDir,id+".mat"),"sourceTable","-v7");
path=fullfile(figDir,id+".png");fig=figure("Visible","off","Color","w","Position",[100 100 1200 720]);
clean=onCleanup(@()close(fig)); %#ok<NASGU>
if isempty(T)
    axis off;text(.5,.5,"No measured observations","HorizontalAlignment","center","FontSize",16);
else
    x=double(T.(xName));y=double(T.(yName));
    switch kind
        case "probability"
            if all(ismember({'CILower','CIUpper'},T.Properties.VariableNames))
                errorbar(x,y,max(0,y-double(T.CILower)),max(0,double(T.CIUpper)-y), ...
                    "o-","LineWidth",1.5,"MarkerFaceColor",[.1 .45 .8]);
            else,plot(x,y,"o-","LineWidth",1.5);end
            xlabel(strrep(xName,'_',' '));ylabel(yLabel);ylim([0 1]);grid on;
        case "cdf"
            stairs(x,y,"LineWidth",1.8);xlabel(strrep(xName,'_',' '));ylabel(yLabel);ylim([0 1]);grid on;
        otherwise
            labels=string(x);
            if ismember('RestrictedSet',T.Properties.VariableNames)
                labels=labels+" | "+string(T.RestrictedSet);
            end
            if numel(unique(labels))<numel(labels)
                labels=labels+" #"+string((1:numel(labels))');
            end
            bar(categorical(labels),y);xlabel(strrep(xName,'_',' '));ylabel(yLabel);grid on;
    end
end
localStyleAxes();
title(scenario+" | "+classification+" | "+titleText, ...
    "Interpreter","none","Color",[.08 .12 .18]);
sixgr.util.exportFigureArtifact(fig,path,"Resolution",300);
meta=struct("artifact_id",id,"classification",classification,"status","COMPLETE", ...
    "scenario_id",scenario,"source_csv",string(source),"source_csv_sha256",localHash(source), ...
    "statistically_qualified",logical(strictQualified(classification)), ...
    "performance_claim",false,"notes",notes, ...
    "producer","sixgr.rach.tdoc10512.writeStrictMeasuredArtifacts");
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
function tf=strictQualified(classification),tf=classification=="CALIBRATED_LLS";end
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
