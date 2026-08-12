function result=run1083Comparative(configPath,options)
%RUN1083COMPARATIVE Execute paired B0/B1/B2/C0 delay/PFA comparison.
arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
[cfg,sourcePath]=sixgr.isac.loadJointConfig(configPath);
class=lower(string(cfg.validation.comparative.activeClass));
campaign=cfg.validation.comparative.(class);
if options.RunId=="", runId="isac_10_8_3_validation_"+ ...
        string(datetime("now","Format","yyyyMMdd_HHmmss")); else, runId=options.RunId; end
if options.OutputRoot=="", root=fullfile(localRepoRoot(),"results"); else, root=options.OutputRoot; end
folder=string(fullfile(root,runId)); localLayout(folder);
profiles=["W0";"W0";"W2";"W3"]; receivers=["B0";"B1";"B2";"C0"];
bundles=struct();
bundles.W0=sixgr.isac.buildJointWaveform(cfg,"W0",double(cfg.run.masterSeed),zeros(0,1),14,"default");
bundles.W2=sixgr.isac.buildJointWaveform(cfg,"W2",double(cfg.run.masterSeed),zeros(0,1),14,"default");
bundles.W3=sixgr.isac.buildJointWaveform(cfg,"W3",double(cfg.run.masterSeed),zeros(0,1),14,"default");
thresholdRows=cell(4,1); thresholds=zeros(4,1);
for p=1:4
    calibration=sixgr.isac.calibrateH0Threshold(cfg,bundles.(profiles(p)),receivers(p), ...
        double(campaign.h0TrialsPerReceiver),double(campaign.probabilityFalseAlarm), ...
        double(cfg.run.masterSeed)+p*100000);
    thresholds(p)=calibration.ThresholdToNoiseFloor;
    thresholdRows{p}=rmfield(calibration,"Statistics");
    writematrix(calibration.Statistics,fullfile(folder,"raw", ...
        "h0_statistics_"+receivers(p)+".csv"));
end
thresholdTable=struct2table(vertcat(thresholdRows{:}));
delays=double(cfg.validation.comparative.delayOverCP(:));
snrs=double(campaign.snrDb(:)); nTrials=double(campaign.targetTrialsPerOperatingPoint);
scenarios=string(cfg.validation.comparative.scenarioClasses(:));
parts=cell(4*numel(delays)*numel(snrs)*nTrials*numel(scenarios),1); index=0;
for snrIndex=1:numel(snrs)
    cfgPoint=cfg; cfgPoint.receiver.snrDb=snrs(snrIndex);
    for delayIndex=1:numel(delays)
        for scenarioIndex=1:numel(scenarios)
        for trialIndex=1:nTrials
            commonSeed=double(cfg.run.masterSeed)+snrIndex*1000000+ ...
                delayIndex*10000+scenarioIndex*1000+trialIndex;
            for p=1:4
                trial=localTrial(sprintf("cmp_%s_s%02d_d%02d_c%02d_t%05d", ...
                    receivers(p),snrIndex,delayIndex,scenarioIndex,trialIndex), ...
                    commonSeed,receivers(p));
                trial.WaveformSeed=double(cfg.run.masterSeed);
                trial.DelayOverCP=delays(delayIndex);
                fraction=double(cfg.validation.comparative.offGridDelayFractionBins( ...
                    mod(trialIndex-1,numel(cfg.validation.comparative.offGridDelayFractionBins))+1));
                cp=min(double(bundles.(profiles(p)).CPLengths));
                trial.ExactDelaySamples=delays(delayIndex)*cp+fraction;
                dopplerFraction=double(cfg.validation.comparative.offGridDopplerFractionBins( ...
                    mod(trialIndex-1,numel(cfg.validation.comparative.offGridDopplerFractionBins))+1));
                trial.ExactDopplerHz=(1+dopplerFraction)* ...
                    double(bundles.(profiles(p)).Carrier.SubcarrierSpacing)*1e3/14;
                trial.FixedDetectionThresholdToNoiseFloor=thresholds(p);
                scenarioClass=scenarios(scenarioIndex);
                if scenarioClass=="two_target_clutter"
                    trial.AdditionalDelaySamples=[trial.ExactDelaySamples+ ...
                        double(cfg.validation.comparative.additionalTargetRelativeDelayCP)*cp; ...
                        trial.ExactDelaySamples+double(cfg.validation.comparative.clutterRelativeDelayCP)*cp];
                    trial.AdditionalDopplerHz=[-.6*trial.ExactDopplerHz;0];
                    trial.AdditionalPathGainDb=double(cfg.channel.targetPathGainDb)+[ ...
                        double(cfg.validation.comparative.additionalTargetRelativeGainDb); ...
                        double(cfg.validation.comparative.clutterRelativeGainDb)];
                end
                index=index+1;
                [row,~]=sixgr.isac.runJointWaveformTrial(cfgPoint,bundles.(profiles(p)),trial);
                row.SNRdB=snrs(snrIndex); row.ComparisonClass=class;
                row.ScenarioClass=scenarioClass;
                row.ComparisonEvidenceClass=string(campaign.evidenceClass);
                parts{index}=row;
            end
        end
        end
    end
end
trials=vertcat(parts{1:index}); metrics=localMetrics(cfg,campaign,trials);
incremental=localIncremental(metrics);
writetable(thresholdTable,fullfile(folder,"tables","h0_threshold_calibration.csv"));
writetable(trials,fullfile(folder,"raw","comparative_trials.csv"));
writetable(metrics,fullfile(folder,"tables","comparative_metrics.csv"));
writetable(incremental,fullfile(folder,"tables","c0_minus_b1_incremental_benefit.csv"));
save(fullfile(folder,"aggregate","comparative_data.mat"), ...
    "cfg","campaign","thresholdTable","trials","metrics","incremental","-v7.3");
localFigures(folder,cfg,metrics,incremental);
copyfile(sourcePath,fullfile(folder,"config_source.yaml")); save(fullfile(folder,"config_snapshot.mat"),"cfg");
result=struct("RunFolder",folder,"Class",class,"Thresholds",thresholdTable, ...
    "Trials",trials,"Metrics",metrics,"Incremental",incremental, ...
    "PublicationQualified",class=="publication"&& ...
    all(thresholdTable.TrialCount>=double(campaign.h0TrialsPerReceiver))&& ...
    all(metrics.Trials>=double(campaign.targetTrialsPerOperatingPoint)));
fprintf("10.8.3 comparative %s: %d trials, publication-qualified=%d\n", ...
    class,height(trials),result.PublicationQualified);
end

function metrics=localMetrics(cfg,campaign,t)
[g,receiver,waveform,snr,delay,scenario]=findgroups( ...
    t.ReceiverProfile,t.WaveformProfile,t.SNRdB,t.DelayOverCP,t.ScenarioClass);
n=splitapply(@numel,t.Detected,g); detections=splitapply(@sum,double(t.Detected),g);
wrong=splitapply(@sum,double(t.WrongPeak),g);
pd=detections./n; wrongP=wrong./n;
[pdLow,pdHigh]=localWilson(detections,n,double(cfg.metrics.confidenceLevel));
[wrongLow,wrongHigh]=localWilson(wrong,n,double(cfg.metrics.confidenceLevel));
correctDetection=t.Detected&~t.WrongPeak;
range=splitapply(@localConditionalRMSE,t.RangeErrorM,correctDetection,g);
doppler=splitapply(@localConditionalRMSE,t.DopplerErrorHz,correctDetection,g);
estimatorSamples=splitapply(@(x)nnz(x),correctDetection,g);
metrics=table(receiver,waveform,snr,delay,scenario,n,pd,pdLow,pdHigh,wrongP,wrongLow,wrongHigh, ...
    range,doppler,estimatorSamples, ...
    repmat("conditioned_on_correct_detection",numel(n),1), ...
    repmat(double(campaign.probabilityFalseAlarm),numel(n),1), ...
    repmat(string(campaign.evidenceClass),numel(n),1), ...
    'VariableNames',{'ReceiverProfile','WaveformProfile','SNRdB','DelayOverCP','ScenarioClass', ...
    'Trials','DetectionProbability','DetectionCILow','DetectionCIHigh', ...
    'WrongPeakProbability','WrongPeakCILow','WrongPeakCIHigh', ...
    'RangeRMSEM','DopplerRMSEHz','EstimatorSampleCount','EstimatorMetricCondition', ...
    'FixedPFA','EvidenceClass'});
end

function value=localConditionalRMSE(error,correctDetection)
values=double(error(logical(correctDetection)));
if isempty(values), value=NaN; else, value=sqrt(mean(values.^2,"omitnan")); end
end

function out=localIncremental(m)
m=m(m.ScenarioClass=="single_target_off_grid",:);
b1=m(m.ReceiverProfile=="B1",{'SNRdB','DelayOverCP','Trials', ...
    'DetectionProbability','RangeRMSEM','DopplerRMSEHz'});
c0=m(m.ReceiverProfile=="C0",{'SNRdB','DelayOverCP','Trials', ...
    'DetectionProbability','RangeRMSEM','DopplerRMSEHz'});
b1.Properties.VariableNames(3:end)= ...
    {'Trials_B1','DetectionProbability_B1','RangeRMSEM_B1','DopplerRMSEHz_B1'};
c0.Properties.VariableNames(3:end)= ...
    {'Trials_C0','DetectionProbability_C0','RangeRMSEM_C0','DopplerRMSEHz_C0'};
joined=innerjoin(b1,c0,"Keys",{'SNRdB','DelayOverCP'});
out=table(joined.SNRdB,joined.DelayOverCP, ...
    joined.RangeRMSEM_B1-joined.RangeRMSEM_C0, ...
    joined.DopplerRMSEHz_B1-joined.DopplerRMSEHz_C0, ...
    joined.DetectionProbability_C0-joined.DetectionProbability_B1, ...
    'VariableNames',{'SNRdB','DelayOverCP','DeltaRangeRMSEM_B1MinusC0', ...
    'DeltaDopplerRMSEHz_B1MinusC0','DeltaDetectionProbability_C0MinusB1'});
end

function [low,high]=localWilson(success,n,confidence)
z=norminv(1-(1-confidence)/2); p=success./n; denominator=1+z^2./n;
center=(p+z^2./(2*n))./denominator;
radius=z*sqrt(p.*(1-p)./n+z^2./(4*n.^2))./denominator;
low=max(0,center-radius); high=min(1,center+radius);
end

function localFigures(folder,cfg,m,incremental)
localMetricFigure(folder,cfg,"WFig20_pd_fixed_pfa_vs_delay_cp",m,"DetectionProbability");
localMetricFigure(folder,cfg,"WFig21_range_rmse_vs_delay_cp",m,"RangeRMSEM");
localMetricFigure(folder,cfg,"WFig22_doppler_rmse_vs_delay_cp",m,"DopplerRMSEHz");
localMetricFigure(folder,cfg,"WFig23_wrong_peak_vs_delay_cp",m,"WrongPeakProbability");
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
fields=["DeltaRangeRMSEM_B1MinusC0","DeltaDopplerRMSEHz_B1MinusC0", ...
    "DeltaDetectionProbability_C0MinusB1"];
for i=1:3
    nexttile(layout); hold on;
    for snr=unique(incremental.SNRdB).'
        rows=incremental.SNRdB==snr;
        plot(incremental.DelayOverCP(rows),incremental.(fields(i))(rows),"-o", ...
            "DisplayName",sprintf("%g dB",snr));
    end
    yline(0,"--"); xlabel("Delay / CP"); ylabel(strrep(fields(i),"_"," ")); grid on;
end
legend("Location","best"); title(layout,"Incremental C0 benefit relative to capable B1");
localExport(folder,cfg,fig,"WFig24_C0_minus_B1_incremental_benefit",incremental);
end

function localMetricFigure(folder,cfg,stem,m,field)
m=m(m.ScenarioClass=="single_target_off_grid",:);
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
receivers=unique(m.ReceiverProfile,"stable"); snrs=unique(m.SNRdB);
layout=tiledlayout(fig,1,numel(snrs),"TileSpacing","compact","Padding","compact");
for s=1:numel(snrs)
    nexttile(layout); hold on;
    for r=1:numel(receivers)
        rows=m.SNRdB==snrs(s)&m.ReceiverProfile==receivers(r);
        if field=="DetectionProbability"
            lower=m.(field)(rows)-m.DetectionCILow(rows);
            upper=m.DetectionCIHigh(rows)-m.(field)(rows);
            errorbar(m.DelayOverCP(rows),m.(field)(rows),lower,upper,"-o", ...
                "DisplayName",receivers(r),"CapSize",4);
        elseif field=="WrongPeakProbability"
            lower=m.(field)(rows)-m.WrongPeakCILow(rows);
            upper=m.WrongPeakCIHigh(rows)-m.(field)(rows);
            errorbar(m.DelayOverCP(rows),m.(field)(rows),lower,upper,"-o", ...
                "DisplayName",receivers(r),"CapSize",4);
        else
            plot(m.DelayOverCP(rows),m.(field)(rows),"-o","DisplayName",receivers(r));
        end
    end
    xline(1,"--","HandleVisibility","off"); xlabel("Delay / CP"); ylabel(strrep(field,"_"," "));
    if field=="DetectionProbability" || field=="WrongPeakProbability", ylim([0 1]); end
    title(sprintf("SNR %g dB",snrs(s))); grid on;
end
legend("Location","best"); title(layout,strrep(stem,"_"," "));
localExport(folder,cfg,fig,stem,m);
end

function fig=localFigure(cfg)
pixels=double(cfg.output.imageSizePixels(:).'); dpi=double(cfg.output.imageResolutionDPI);
fig=figure("Visible","off","Color","white","Units","inches", ...
    "Position",[1 1 pixels(1)/dpi pixels(2)/dpi]);
end

function localExport(folder,cfg,fig,stem,data)
localPublicationStyle(fig);
save(fullfile(folder,"figures",stem+".mat"),"data"); savefig(fig,fullfile(folder,"figures",stem+".fig"));
writetable(data,fullfile(folder,"figures",stem+".csv"));
exportgraphics(fig,fullfile(folder,"figures",stem+".png"),"Resolution",double(cfg.output.imageResolutionDPI));
exportgraphics(fig,fullfile(folder,"figures",stem+".pdf"),"ContentType","vector");
end

function localPublicationStyle(fig)
axesHandles=findall(fig,"Type","axes");
for ax=reshape(axesHandles,1,[])
    set(ax,"Color","white","XColor",[.12 .12 .12],"YColor",[.12 .12 .12], ...
        "GridColor",[.68 .68 .68],"MinorGridColor",[.82 .82 .82], ...
        "GridAlpha",.35,"FontName","Arial","FontSize",9);
end
textHandles=findall(fig,"Type","text");
for h=reshape(textHandles,1,[]), set(h,"Color",[.08 .08 .08]); end
layoutHandles=findall(fig,"Type","tiledlayout");
for h=reshape(layoutHandles,1,[])
    h.Title.Color=[.08 .08 .08]; h.Title.FontWeight="bold";
end
legendHandles=findall(fig,"Type","legend");
for h=reshape(legendHandles,1,[])
    set(h,"Color","white","TextColor",[.08 .08 .08],"EdgeColor",[.55 .55 .55]);
end
end

function trial=localTrial(id,seed,receiver)
trial=struct("TrialId",char(id),"Seed",double(seed),"WaveformSeed",double(seed), ...
    "DelayOverCP",1,"NormalizedDoppler",.01,"SensingMode","trp_monostatic", ...
    "CollisionRatioPercent",0,"CollisionResponse","share_reuse", ...
    "TDDPattern","all_dl","TargetPresent",true,"UseGeometryDelay",false, ...
    "PortProfile","single_port","ReceiverProfile",char(receiver),"CoherentSymbols",14, ...
    "CollisionMaskProfile","random_isolated","SequenceVariant","default");
end

function localLayout(folder)
for name=["audit","logs","raw","aggregate","tables","figures","report"]
    p=fullfile(folder,name); if exist(p,"dir")~=7, mkdir(p); end
end
end

function root=localRepoRoot()
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
