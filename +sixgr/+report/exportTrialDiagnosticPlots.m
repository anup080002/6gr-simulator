function images=exportTrialDiagnosticPlots(root,raw,saveFigures)
% Same retained-source renderer for normal completion and report recovery.
% Never reexecute PHY, infer missing measurements, or reuse an old image as
% evidence for a newly selected source. Each SNR/UE/layer group stays distinct.
images={};
if ~saveFigures, return; end
sources=sixgr.report.writeTrialDiagnosticPlotSources(root,raw);
layout=sixgr.report.resultLayout(root);
sixgr.util.ensureFolder(layout.AirInterfaceImageDir);
plotIds=strings(0,1); paths=strings(0,1); csvs=strings(0,1);
for direction=["DL","UL"]
    T=sources.(direction);
    prefix=lower(direction);
    metrics=["PostEqSINR_dB","ChannelGain_dB"];
    metricNames=["posteq_sinr","channel_gain"];
    names=["_posteq_sinr_by_trial_scatter","_channel_gain_distribution"];
    summaryNames=["_posteq_sinr_by_trial_summary","_channel_gain_distribution_summary"];
    labels=["Post-equalization SINR (dB)","Channel gain (dB)"];
    for m=1:numel(metrics)
        id=prefix+names(m); path=fullfile(layout.AirInterfaceImageDir,id+".png");
        summaryPath=fullfile(layout.AirInterfaceCSVDir,prefix+summaryNames(m)+".csv");
        % These are derived outputs owned by this producer, not raw evidence.
        localRemoveDerived(path); localRemoveDerived(summaryPath);
        if isempty(T) || ~ismember(metrics(m),string(T.Properties.VariableNames)), continue; end
        y=localNumber(T,metrics(m));
        group=localGroups(T); keys=unique(group(isfinite(y)), 'stable');
        if isempty(keys), continue; end
        rows=table();
        fig=figure('Visible','off','Color','w','Position',[50 50 1100 700]);
        cleanup=onCleanup(@()close(fig));
        ax=axes(fig); hold(ax,'on');
        [x,xLabel]=localTrialAxis(T);
        for k=1:numel(keys)
            mask=group==keys(k) & isfinite(y); values=y(mask);
            selected=find(mask,1);
            if m==1
                plotted=mask & isfinite(x);
                scatter(ax,x(plotted),y(plotted),18,'DisplayName',keys(k));
            else
                histogram(ax,values,'Normalization','probability', ...
                    'DisplayStyle','stairs','LineWidth',1.5,'DisplayName',keys(k));
            end
            row=table(direction,metricNames(m),metrics(m),keys(k), ...
                localFirstNumber(T,selected,["ConfiguredSNR_dB","SNR_dB"]), ...
                localFirstNumber(T,selected,["UEIndex","UEId","UEID"]), ...
                localFirstText(T,selected,["LayerIndex","Layer","NumLayers","Layers","n_layers"]), ...
                localPercentile(values,5),localPercentile(values,50),localPercentile(values,95), ...
                mean(values),std(values),numel(values), ...
                'VariableNames',{'Direction','MetricName','MetricColumn','Group','ConfiguredSNR_dB', ...
                'UEIndex','Layer','p5','p50','p95','mean','std','n_samples'});
            rows=[rows;row]; %#ok<AGROW>
        end
        grid(ax,'on'); title(ax,direction+" "+labels(m)+" — all captured groups",'Interpreter','none');
        if m==1
            xlabel(ax,xLabel); ylabel(ax,labels(m));
        else
            xlabel(ax,labels(m)); ylabel(ax,'Probability within each group');
        end
        legend(ax,'Location','eastoutside','Interpreter','none');
        sixgr.util.csvWriteTable(summaryPath,rows,'PreserveSchema',true,'RoundTripNumericText',true);
        sixgr.util.exportFigureArtifact(fig,path,'Resolution',160);
        clear cleanup;
        plotIds(end+1,1)=id; paths(end+1,1)=path; csvs(end+1,1)=sources.(direction+"Path"); %#ok<AGROW>
    end
    id=prefix+"_constellation_scatter"; path=fullfile(layout.AirInterfaceImageDir,id+".png");
    localRemoveDerived(path);
    if sixgr.report.exportConstellationGroups(sources.(direction+"Constellation"),path)
        plotIds(end+1,1)=id; paths(end+1,1)=path; csvs(end+1,1)=sources.(direction+"ConstellationPath"); %#ok<AGROW>
    end
end
lineage=fullfile(layout.AirInterfaceCSVDir,'runtime_trial_plot_lineage.csv');
localRemoveDerived(lineage);
if ~isempty(paths)
    sixgr.visual.writeComponentPlotLineage(root,lineage,plotIds,paths,csvs, ...
        'sixgr.report.exportTrialDiagnosticPlots','SourcesAlreadyFinalized',true);
    images=cellstr(paths);
end
end

function labels=localGroups(T)
labels=repmat("",height(T),1);
% Missing identity is explicitly unknown, never silently pooled with a UE.
for fields={ ["ConfiguredSNR_dB","SNR_dB"], ["UEIndex","UEId","UEID"], ...
        ["LayerIndex","Layer","NumLayers","Layers","n_layers"] }
    names=fields{1}; chosen=names(ismember(names,string(T.Properties.VariableNames)));
    if isempty(chosen), continue; end
    name=chosen(1); values=string(T.(name));
    values(ismissing(values) | strlength(values)==0)="unknown";
    labels=labels+name+"="+values+" ";
end
labels=strtrim(labels); labels(labels=="")="identity unavailable";
end

function [x,label]=localTrialAxis(T)
for name=["TrialId","TrialID","TrialIndex","TransportBlockID","Slot","SampleIndex"]
    if ismember(name,string(T.Properties.VariableNames))
        x=localNumber(T,name);
        if any(isfinite(x)), label=name+" (scatter; no implied time continuity)"; return; end
    end
end
x=(1:height(T)).'; label="Retained trial row index (not simulation time)";
end

function values=localNumber(T,name)
values=nan(height(T),1);
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name);
if isnumeric(raw) || islogical(raw), values=double(raw); else, values=str2double(string(raw)); end
assert(iscolumn(values) && numel(values)==height(T), ...
    'sixgr:report:InvalidTrialMetricShape','A trial metric must be scalar per row.');
end

function value=localFirstNumber(T,row,names)
value=NaN;
for name=names
    if ismember(name,string(T.Properties.VariableNames))
        values=localNumber(T,name); value=values(row); return;
    end
end
end

function value=localFirstText(T,row,names)
value="unavailable";
for name=names
    if ismember(name,string(T.Properties.VariableNames))
        values=string(T.(name)); value=name+"="+values(row); return;
    end
end
end

function value=localPercentile(samples,pct)
samples=sort(samples); position=1+pct/100*(numel(samples)-1);
lo=floor(position); hi=ceil(position);
value=samples(lo)+(position-lo)*(samples(hi)-samples(lo));
end

function localRemoveDerived(path)
if isfile(path), delete(path); end
end
