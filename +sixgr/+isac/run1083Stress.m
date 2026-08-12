function result=run1083Stress(configPath,options)
%RUN1083STRESS Execute WFig29-WFig36 common-waveform integration stress.
arguments
    configPath (1,1) string = "configs/isac/joint_isac_tdoc_master.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunId (1,1) string = ""
end
[cfg,sourcePath]=sixgr.isac.loadJointConfig(configPath);
class=lower(string(cfg.validation.stress.activeClass)); stress=cfg.validation.stress.(class);
if options.RunId=="", runId="isac_10_8_3_stress_"+ ...
        string(datetime("now","Format","yyyyMMdd_HHmmss")); else, runId=options.RunId; end
if options.OutputRoot=="", root=fullfile(localRepoRoot(),"results"); else, root=options.OutputRoot; end
folder=string(fullfile(root,runId)); localLayout(folder);
[intercell,selfInterference,intercellTrials,selfInterferenceTrials, ...
    interferenceCalibration,interferenceH0]=localInterference(cfg,stress);
[pdsch,pdschTrials]=sixgr.isac.runPDSCHProfileSweep(cfg,stress);
pdschComparison=localPDSCHComparison(pdschTrials);
puncture=localPuncture(cfg,stress); relocation=localRelocation(cfg,stress);
[randomization,randomizationTrials]=localRandomization(cfg,stress); complexity=localComplexity(cfg);
datasets=struct("Intercell",intercell,"SelfInterference",selfInterference, ...
    "IntercellTrials",intercellTrials,"SelfInterferenceTrials",selfInterferenceTrials, ...
    "InterferenceCalibration",interferenceCalibration, ...
    "InterferenceH0Statistics",interferenceH0, ...
    "PDSCH",pdsch,"PDSCHTrials",pdschTrials,"PDSCHComparison",pdschComparison, ...
    "Puncture",puncture, ...
    "Relocation",relocation,"Randomization",randomization, ...
    "RandomizationTrials",randomizationTrials,"Complexity",complexity);
for name=string(fieldnames(datasets)).'
    value=datasets.(name); writetable(value,fullfile(folder,"tables",name+".csv"));
end
save(fullfile(folder,"aggregate","stress_data.mat"),"cfg","stress","datasets","-v7.3");
localFigures(folder,cfg,datasets);
copyfile(sourcePath,fullfile(folder,"config_source.yaml")); save(fullfile(folder,"config_snapshot.mat"),"cfg");
publicationQualified=class=="publication"&&all(pdsch.PublicationStoppingRuleSatisfied)&& ...
    all(interferenceCalibration.PublicationQualified)&& ...
    all(intercell.Trials>=double(stress.targetTrialsPerPoint))&& ...
    all(selfInterference.Trials>=double(stress.targetTrialsPerPoint));
result=struct("RunFolder",folder,"Class",class,"Data",datasets, ...
    "PublicationQualified",publicationQualified);
fprintf("10.8.3 stress %s: intercell=%d SI=%d PDSCH TB=%d\n", ...
    class,height(intercell),height(selfInterference),height(pdschTrials));
end

function [intercell,si,intercellTrials,siTrials,calibrationTable,h0Table]=localInterference(cfg,stress)
w0=sixgr.isac.buildJointWaveform(cfg,"W0",double(cfg.run.masterSeed),zeros(0,1),14,"default");
w1=sixgr.isac.buildJointWaveform(cfg,"W1",double(cfg.run.masterSeed),zeros(0,1),14,"reset_aligned_interval");
interfererBundle=sixgr.isac.buildJointWaveform(cfg,"W1",double(cfg.run.masterSeed)+99, ...
    zeros(0,1),14,"reset_aligned_interval");
profiles=["W0";"W1-B"]; bundles={w0;w1}; receivers=["B1";"B1"];
n=double(stress.targetTrialsPerPoint); powers=double(cfg.validation.stress.intercellRelativePowerDb(:));
parts=cell(numel(powers)*2*n,1); index=0;
calibration=cell(numel(powers)*2+numel(cfg.validation.stress.selfInterferenceResidualDb),1);
h0Rows=cell(size(calibration));
calibrationIndex=0;
for p=1:2, for powerIndex=1:numel(powers)
    interference=sixgr.isac.applyLinearDelay(interfererBundle.Waveform, ...
        double(cfg.validation.stress.intercellDelayOverCP)*min(interfererBundle.CPLengths));
    time=(0:numel(interference)-1)'/interfererBundle.OFDMInfo.SampleRate;
    interference=interference.*exp(1i*2*pi*double( ...
        cfg.validation.stress.intercellFrequencyOffsetHz)*time);
    overrides=struct("ExternalInterferenceWaveform",interference, ...
        "ExternalInterferenceRelativePowerDb",powers(powerIndex));
    h=sixgr.isac.calibrateH0Threshold(cfg,bundles{p},receivers(p), ...
        double(stress.h0TrialsPerReceiver),double(stress.probabilityFalseAlarm), ...
        double(cfg.run.masterSeed)+50000*p+powerIndex*1000,"TrialOverrides",overrides);
    calibrationIndex=calibrationIndex+1;
    calibration{calibrationIndex}=localCalibrationRow(h,"intercell",profiles(p),powers(powerIndex));
    calibration{calibrationIndex}.H0StatisticsSHA256=localVectorHash(h.Statistics);
    h0Rows{calibrationIndex}=localH0Rows(h,"intercell",profiles(p),powers(powerIndex));
for trialIndex=1:n
    seed=double(cfg.run.masterSeed)+powerIndex*1000+trialIndex;
    t=localTrial("intercell",seed,receivers(p));
    t.FixedDetectionThresholdToNoiseFloor=h.ThresholdToNoiseFloor;
    t.ExternalInterferenceWaveform=interference;
    t.ExternalInterferenceRelativePowerDb=powers(powerIndex);
    [row,~]=sixgr.isac.runJointWaveformTrial(cfg,bundles{p},t);
    row.InterferenceProfile=profiles(p); row.RelativeInterfererPowerDb=powers(powerIndex);
    index=index+1; parts{index}=row;
end, end, end
intercellTrials=vertcat(parts{1:index});
intercell=localAggregateInterference(intercellTrials, ...
    "RelativeInterfererPowerDb","InterferenceProfile");
siParts=cell(numel(cfg.validation.stress.selfInterferenceResidualDb)*n,1); index=0;
for power=double(cfg.validation.stress.selfInterferenceResidualDb(:)).'
    overrides=struct("ResidualSelfInterferenceDb",power);
    h=sixgr.isac.calibrateH0Threshold(cfg,w0,"B1", ...
        double(stress.h0TrialsPerReceiver),double(stress.probabilityFalseAlarm), ...
        double(cfg.run.masterSeed)+650000+calibrationIndex*1000,"TrialOverrides",overrides);
    calibrationIndex=calibrationIndex+1;
    calibration{calibrationIndex}=localCalibrationRow(h,"self_interference","W0",power);
    calibration{calibrationIndex}.H0StatisticsSHA256=localVectorHash(h.Statistics);
    h0Rows{calibrationIndex}=localH0Rows(h,"self_interference","W0",power);
    for trialIndex=1:n
        t=localTrial("si",double(cfg.run.masterSeed)+600000+index+1,"B1");
        t.FixedDetectionThresholdToNoiseFloor=h.ThresholdToNoiseFloor; t.ResidualSelfInterferenceDb=power;
        [row,~]=sixgr.isac.runJointWaveformTrial(cfg,w0,t); row.ResidualSelfInterferenceDb=power;
        index=index+1; siParts{index}=row;
    end
end
siTrials=vertcat(siParts{1:index});
si=localAggregateInterference(siTrials, ...
    "ResidualSelfInterferenceDb","ReceiverProfile");
calibrationTable=vertcat(calibration{1:calibrationIndex});
h0Table=vertcat(h0Rows{1:calibrationIndex});
end

function rows=localH0Rows(h,condition,profile,level)
n=numel(h.Statistics);
rows=table(repmat(string(condition),n,1),repmat(string(profile),n,1), ...
    repmat(level,n,1),(1:n).',double(h.Statistics(:)), ...
    repmat(h.ThresholdToNoiseFloor,n,1),double(h.Statistics(:))>h.ThresholdToNoiseFloor, ...
    'VariableNames',{'Condition','WaveformProfile','ConditionLevelDb','H0TrialIndex', ...
    'NormalizedMaximumStatistic','ThresholdToNoiseFloor','FalseAlarm'});
end

function row=localCalibrationRow(h,condition,profile,level)
row=table(string(condition),string(profile),level,h.TrialCount,h.RequestedPFA, ...
    h.ThresholdToNoiseFloor,h.EmpiricalPFA,h.PFACILow,h.PFACIHigh,h.PublicationQualified, ...
    string(h.EvidenceClass),'VariableNames',{'Condition','WaveformProfile','ConditionLevelDb', ...
    'H0Trials','RequestedPFA','ThresholdToNoiseFloor','EmpiricalPFA','PFACILow', ...
    'PFACIHigh','PublicationQualified','EvidenceClass'});
end

function out=localAggregateInterference(t,xName,className)
[g,x,class]=findgroups(t.(xName),t.(className)); n=splitapply(@numel,t.Detected,g);
success=splitapply(@sum,double(t.Detected),g);
[pdLow,pdHigh]=localWilson(success,n,.95);
wrongCount=splitapply(@sum,double(t.WrongPeak),g);
[wrongLow,wrongHigh]=localWilson(wrongCount,n,.95);
correctDetection=t.Detected&~t.WrongPeak;
out=table(x,class,n,splitapply(@mean,double(t.Detected),g), ...
    pdLow,pdHigh, ...
    splitapply(@localConditionalRMSE,t.RangeErrorM,correctDetection,g), ...
    splitapply(@localConditionalRMSE,t.DopplerErrorHz,correctDetection,g), ...
    splitapply(@(v)nnz(v),correctDetection,g), ...
    repmat("conditioned_on_correct_detection",numel(n),1), ...
    splitapply(@mean,double(t.WrongPeak),g),wrongLow,wrongHigh, ...
    splitapply(@mean,t.CommunicationEVMRMS,g), ...
    splitapply(@mean,t.InterferenceToTargetEchoRatioDb,g), ...
    'VariableNames',[xName,className,"Trials","DetectionProbability", ...
    "DetectionCILow","DetectionCIHigh","RangeRMSEM","DopplerRMSEHz", ...
    "EstimatorSampleCount","EstimatorMetricCondition","WrongPeakProbability", ...
    "WrongPeakCILow","WrongPeakCIHigh","CommunicationEVMRMS", ...
    "InterferenceToTargetEchoRatioDb"]);
end


function value=localConditionalRMSE(error,correctDetection)
values=double(error(logical(correctDetection)));
if isempty(values), value=NaN; else, value=sqrt(mean(values.^2,"omitnan")); end
end

function [low,high]=localWilson(success,n,confidence)
z=norminv(1-(1-confidence)/2); p=success./n; denominator=1+z^2./n;
center=(p+z^2./(2*n))./denominator;
radius=z*sqrt(p.*(1-p)./n+z^2./(4*n.^2))./denominator;
low=max(0,center-radius); high=min(1,center+radius);
end

function hash=localVectorHash(values)
hash=string(sixgr.util.sha256Hex(typecast(double(values(:)),"uint8")));
end

function out=localPDSCHComparison(trials)
snrs=unique(trials.TargetSNRdB,"stable"); profiles=setdiff(unique(trials.WaveformProfile,"stable"),"W0","stable");
rows=cell(numel(snrs)*numel(profiles),1); index=0;
for snr=snrs.'
    baseline=sortrows(trials(trials.TargetSNRdB==snr&trials.WaveformProfile=="W0",:),"TrialIndex");
    for profile=profiles.'
        candidate=sortrows(trials(trials.TargetSNRdB==snr&trials.WaveformProfile==profile,:),"TrialIndex");
        n=min(height(baseline),height(candidate));
        baseError=double(baseline.CRCError(1:n)); candidateError=double(candidate.CRCError(1:n));
        worse=nnz(candidateError>baseError); better=nnz(candidateError<baseError); discordant=worse+better;
        if discordant==0, pValue=1;
        else, pValue=min(1,2*binocdf(min(worse,better),discordant,.5)); end
        difference=mean(candidateError-baseError);
        evmDifference=mean(candidate.EqualizedSymbolEVMRMS(1:n)- ...
            baseline.EqualizedSymbolEVMRMS(1:n),"omitnan");
        index=index+1;
        rows{index}=table(profile,snr,n,difference,worse,better,pValue,evmDifference, ...
            pValue<.05&&difference>0, ...
            'VariableNames',{'WaveformProfile','SNRdB','PairedTransportBlocks', ...
            'BLERDifferenceVsW0','DiscordantWorse','DiscordantBetter','McNemarPValue', ...
            'MeanEVMDifferenceVsW0','CommunicationDegradationStatisticallySignificant'});
    end
end
out=vertcat(rows{1:index});
end

function out=localPuncture(cfg,stress)
b=sixgr.isac.buildJointWaveform(cfg,"W3",double(cfg.run.masterSeed),zeros(0,1),14,"default");
rates=double(cfg.validation.stress.punctureRatesPercent(:)); patterns=string(cfg.validation.stress.puncturePatterns(:));
trials=double(stress.targetTrialsPerPoint);
parts=cell(numel(rates)*numel(patterns)*2*trials,1); index=0;
for rateIndex=1:numel(rates), rate=rates(rateIndex);
for patternIndex=1:numel(patterns), pattern=patterns(patternIndex);
for rule=["absolute_physical_symbol","transmitted_sensing_counter"]
for trialIndex=1:trials
    seed=double(cfg.run.masterSeed)+700000+rateIndex*10000+patternIndex*100+trialIndex;
    t=localTrial("puncture",seed,"C0");
    t.CollisionRatioPercent=rate; t.CollisionResponse="sensing_puncture";
    t.CollisionMaskProfile=pattern; t.ReceiverW3StateRule=rule;
    if pattern=="tdd_driven_missing_occasions", t.TDDPattern="configured_tdd_gap"; end
    [row,raw]=sixgr.isac.runJointWaveformTrial(cfg,b,t);
    row.ResidualPhaseRMSDeg=localW3ResidualPhaseRMS(b,raw.PatternState.EffectiveMask,rule);
    row.DopplerRMSEHz=abs(row.DopplerErrorHz);
    row.WrongPeakProbability=double(row.WrongPeak);
    row.PunctureProfile=pattern;
    row.PunctureCase=pattern+"|"+rule;
    index=index+1; parts{index}=row;
end, end, end, end
out=vertcat(parts{1:index});
end

function out=localRelocation(cfg,stress)
b=sixgr.isac.buildJointWaveform(cfg,"W3",double(cfg.run.masterSeed),zeros(0,1),4,"default");
phase=double(cfg.validation.stress.relocationResidualPhaseDeg(:));
n=double(stress.targetTrialsPerPoint); parts=cell((numel(phase)+1)*n,1); index=0;
for trialIndex=1:n
commonSeed=double(cfg.run.masterSeed)+800000+trialIndex;
t=localTrial("relocation_unknown",commonSeed,"C0");
t.CollisionRatioPercent=20; t.CollisionResponse="time_relocation"; t.RelationClass="unknown_unavailable";
t.ReceiverRelocatedReferenceUnavailable=true;
t.ReceiverW3StateRule="transmitted_sensing_counter"; [row,~]=sixgr.isac.runJointWaveformTrial(cfg,b,t);
row.RelocationClass="R0_unknown"; row.ResidualPhaseDeg=-1; index=index+1; parts{index}=row;
for i=1:numel(phase)
    t=localTrial("relocation_"+i,commonSeed,"C0");
    t.CollisionRatioPercent=20; t.CollisionResponse="time_relocation"; t.RelationClass="known_transform";
    t.ReceiverW3ResidualPhaseDeg=phase(i); [row,~]=sixgr.isac.runJointWaveformTrial(cfg,b,t);
    if phase(i)==0, label="R1_exact"; else, label="R2_bounded"; end
    row.RelocationClass=label; row.ResidualPhaseDeg=phase(i); index=index+1; parts{index}=row;
end
end
out=vertcat(parts{1:index});
end

function [out,raw]=localRandomization(cfg,stress)
w1a=sixgr.isac.buildJointWaveform(cfg,"W1",double(cfg.run.masterSeed),zeros(0,1),14,"per_occasion");
w1b=sixgr.isac.buildJointWaveform(cfg,"W1",double(cfg.run.masterSeed),zeros(0,1),14,"reset_aligned_interval");
profiles=["W1-A";"W1-B"]; bundles={w1a;w1b};
n=double(stress.targetTrialsPerPoint); parts=cell(2*n,1); index=0;
for p=1:2
    interferer=sixgr.isac.buildJointWaveform(cfg,"W1",double(cfg.run.masterSeed)+99,zeros(0,1),14, ...
        string(bundles{p}.SequenceVariant));
    overrides=struct("ExternalInterferenceWaveform",interferer.Waveform, ...
        "ExternalInterferenceRelativePowerDb",-10);
    h=sixgr.isac.calibrateH0Threshold(cfg,bundles{p},"B0", ...
        double(stress.h0TrialsPerReceiver),double(stress.probabilityFalseAlarm), ...
        double(cfg.run.masterSeed)+910000+p*1000,"TrialOverrides",overrides);
for trialIndex=1:n
    t=localTrial("randomization",double(cfg.run.masterSeed)+900000+trialIndex,"B0");
    t.ExternalInterferenceWaveform=interferer.Waveform; t.ExternalInterferenceRelativePowerDb=-10;
    t.FixedDetectionThresholdToNoiseFloor=h.ThresholdToNoiseFloor;
    [row,~]=sixgr.isac.runJointWaveformTrial(cfg,bundles{p},t);
    active=bundles{p}.ConfiguredMask; x=bundles{p}.SensingGrid(active); y=interferer.SensingGrid(active);
    row.RandomizationProfile=profiles(p); row.CrossCorrelation=abs(x'*y)/(norm(x)*norm(y));
    row.DetectionProbability=double(row.Detected);
    row.DopplerRMSEHz=abs(row.DopplerErrorHz);
    row.WrongPeakProbability=double(row.WrongPeak);
    row.CoherentGain=localCrossSymbolCoherence(bundles{p});
    index=index+1; parts{index}=row;
end
end
raw=vertcat(parts{1:index});
[g,profile]=findgroups(raw.RandomizationProfile);
out=table(profile,splitapply(@numel,raw.Detected,g), ...
    splitapply(@mean,raw.CrossCorrelation,g),splitapply(@mean,raw.DetectionProbability,g), ...
    splitapply(@mean,raw.CoherentGain,g),splitapply(@(x)sqrt(mean(x.^2)),raw.DopplerErrorHz,g), ...
    splitapply(@mean,raw.WrongPeakProbability,g), ...
    'VariableNames',{'RandomizationProfile','Trials','CrossCorrelation', ...
    'DetectionProbability','CoherentGain','DopplerRMSEHz','WrongPeakProbability'});
end

function gain=localCrossSymbolCoherence(bundle)
symbols=find(any(bundle.ConfiguredMask,1)); values=zeros(max(0,numel(symbols)-1),1);
for i=2:numel(symbols)
    a=bundle.SensingGrid(bundle.ConfiguredMask(:,symbols(i-1)),symbols(i-1));
    b=bundle.SensingGrid(bundle.ConfiguredMask(:,symbols(i)),symbols(i));
    values(i-1)=abs(a'*b)/(norm(a)*norm(b));
end
gain=mean(values,"omitnan");
end

function rmsDeg=localW3ResidualPhaseRMS(bundle,effectiveMask,rule)
qAbs=double(bundle.CumulativeCPState(:));
if string(rule)=="absolute_physical_symbol", qRx=qAbs;
else
    qRx=zeros(size(qAbs)); accumulator=0;
    for symbol=1:numel(qRx)
        if any(effectiveMask(:,symbol))
            accumulator=mod(accumulator+double(bundle.CPLengths(symbol)),double(bundle.OFDMInfo.Nfft));
        end
        qRx(symbol)=accumulator;
    end
end
symbols=find(any(effectiveMask,1)); k=double(bundle.PhysicalSubcarrierIndices(:));
phase=zeros(numel(k),numel(symbols));
for i=1:numel(symbols)
    phase(:,i)=angle(exp(1i*2*pi*k*(qRx(symbols(i))-qAbs(symbols(i)))/ ...
        double(bundle.OFDMInfo.Nfft)));
end
rmsDeg=rad2deg(sqrt(mean(phase.^2,"all")));
end

function out=localComplexity(cfg)
profiles=["W0";"W0";"W2";"W3"]; receivers=["B0";"B1";"B2";"C0"];
n=double(cfg.validation.stress.complexityRepetitions); parts=cell(4,1);
for p=1:4
    b=sixgr.isac.buildJointWaveform(cfg,profiles(p),double(cfg.run.masterSeed),zeros(0,1),14,"default");
    values=cell(n,1);
    for i=1:n
        [row,~]=sixgr.isac.runJointWaveformTrial(cfg,b, ...
            localTrial("complexity",double(cfg.run.masterSeed)+p*1000+i,receivers(p)));
        values{i}=row;
    end
    rows=vertcat(values{:});
    parts{p}=table(receivers(p),rows.BufferComplexSamples(1),rows.BufferBytes(1), ...
        median(rows.ReceiverProcessingSeconds)*1e3,prctile(rows.ReceiverProcessingSeconds,90)*1e3, ...
        rows.FFTCountEstimate(1),rows.ComplexMultiplyEstimate(1),n, ...
        'VariableNames',{'ReceiverProfile','BufferComplexSamples','BufferBytes', ...
        'MedianProcessingLatencyMs','P90ProcessingLatencyMs','FFTCountEstimate', ...
        'ComplexMultiplyEstimate','RuntimeRepetitions'});
end
out=vertcat(parts{:});
end

function localFigures(folder,cfg,d)
localMetric(folder,cfg,"WFig29_intercell_sensing_performance",d.Intercell,"RelativeInterfererPowerDb");
localMetric(folder,cfg,"WFig30_self_interference_sensing_performance",d.SelfInterference,"ResidualSelfInterferenceDb");
    localPDSCH(folder,cfg,"WFig31_pdsch_bler_vs_snr",d.PDSCH,"BLER");
    localPDSCH(folder,cfg,"WFig32_pdsch_goodput_vs_snr",d.PDSCH,"GoodputBps");
    localPunctureFigure(folder,cfg,d.Puncture);
    localRelocationFigure(folder,cfg,d.Relocation);
    localRandomizationFigure(folder,cfg,d.Randomization);
localComplexityFigure(folder,cfg,d.Complexity);
end

function localMetric(folder,cfg,stem,t,xField)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
vars=t.Properties.VariableNames; metrics=intersect( ...
    {'DetectionProbability','RangeRMSEM','DopplerRMSEHz','WrongPeakProbability', ...
    'ResidualPhaseRMSDeg','ReferenceCoherentGain','CoherentGain','CoherentSegments', ...
    'CommunicationEVMRMS','MedianProcessingLatencyMs', ...
    'P90ProcessingLatencyMs','ComplexMultiplyEstimate','BufferBytes'},vars,"stable");
if isempty(metrics), metrics=setdiff(vars,{xField},"stable"); metrics=metrics(1:min(3,numel(metrics))); end
layout=tiledlayout(fig,1,min(5,numel(metrics)),"TileSpacing","compact","Padding","compact");
groupField="";
for candidate=["PunctureCase","RelocationClass", ...
        "RandomizationProfile","InterferenceProfile","ReceiverProfile"]
    if ismember(candidate,string(vars)), groupField=candidate; break; end
end
for i=1:min(5,numel(metrics))
    nexttile(layout); hold on;
    if groupField==""
        plot(double(t.(xField)),double(t.(metrics{i})),"-o");
    else
        groups=unique(string(t.(groupField)),"stable");
        for group=groups.'
            rows=string(t.(groupField))==group;
            [x,order]=sort(double(t.(xField)(rows))); y=double(t.(metrics{i})); y=y(rows);
            plot(x,y(order),"-o","DisplayName",group);
        end
        legend("Location","best");
    end
    xlabel(strrep(xField,"_"," ")); ylabel(strrep(metrics{i},"_"," ")); grid on;
end
title(layout,strrep(stem,"_"," ")); localExport(folder,cfg,fig,stem,t);
end

function localPDSCH(folder,cfg,stem,t,field)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU> hold on;
for profile=unique(t.WaveformProfile,"stable").'
    rows=t.WaveformProfile==profile;
    if field=="BLER"
        lower=t.(field)(rows)-t.BLERCILow(rows);
        upper=t.BLERCIHigh(rows)-t.(field)(rows);
        errorbar(t.SNRdB(rows),t.(field)(rows),lower,upper,"-o", ...
            "DisplayName",profile,"CapSize",5);
    else, plot(t.SNRdB(rows),t.(field)(rows)/1e6,"-o","DisplayName",profile); end
end
xlabel("Transmit-grid E_s/N_0 (dB)");
if field=="BLER", ylabel("BLER (95% Wilson interval)"); ylim([0 1]);
else, ylabel("Goodput (Mbit/s)"); end
legend("Location","best"); grid on; title(strrep(stem,"_"," "));
localExport(folder,cfg,fig,stem,t);
end

function localPunctureFigure(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
metrics=["ResidualPhaseRMSDeg","ReferenceCoherentGain","DopplerErrorHz","WrongPeak"];
labels=["Residual phase RMS (deg)","Reference coherent gain","Doppler RMSE (Hz)","Wrong-peak probability"];
profiles=unique(t.PunctureProfile,"stable"); rules=unique(t.ReceiverW3StateRule,"stable");
colors=lines(numel(profiles)); styles=["-","--"];
for metricIndex=1:numel(metrics)
    ax=nexttile(layout); hold(ax,"on");
    for profileIndex=1:numel(profiles)
        for ruleIndex=1:numel(rules)
            rows=t.PunctureProfile==profiles(profileIndex) ...
                & t.ReceiverW3StateRule==rules(ruleIndex);
            [x,y]=localGroupedMetric(t.CollisionRatioPercent(rows), ...
                t.(metrics(metricIndex))(rows),metrics(metricIndex));
            displayName=strrep(profiles(profileIndex),"_"," ")+" / "+ ...
                localShortRule(rules(ruleIndex));
            plot(ax,x,y,"LineStyle",styles(ruleIndex),"Marker","o", ...
                "Color",colors(profileIndex,:),"LineWidth",1.25, ...
                "DisplayName",displayName);
        end
    end
    xlabel(ax,"Punctured sensing REs (%)"); ylabel(ax,labels(metricIndex)); grid(ax,"on");
    if metricIndex==1
        lgd=legend(ax,"Location","southoutside","NumColumns",3,"FontSize",7);
        lgd.Layout.Tile="south";
    end
end
title(layout,"W3 puncture: correct absolute state versus wrong transmitted counter");
localExport(folder,cfg,fig,"WFig33_W3_puncture_robustness",t);
end

function localRelocationFigure(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
metrics=["ReferenceCoherentGain","DopplerErrorHz","WrongPeak","CoherentSegments"];
labels=["Reference coherent gain","Absolute Doppler error (Hz)", ...
    "Wrong-peak probability","Coherent segments"];
classes=unique(t.RelocationClass,"stable");
for metricIndex=1:numel(metrics)
    ax=nexttile(layout); hold(ax,"on");
    for classIndex=1:numel(classes)
        rows=t.RelocationClass==classes(classIndex);
        [x,y]=localGroupedMetric(t.ResidualPhaseDeg(rows), ...
            t.(metrics(metricIndex))(rows),metrics(metricIndex));
        plot(ax,x,y,"-o","LineWidth",1.25,"DisplayName", ...
            strrep(classes(classIndex),"_"," "));
    end
    xlabel(ax,"Residual relocation phase (deg)"); ylabel(ax,labels(metricIndex)); grid(ax,"on");
    if metricIndex==1, legend(ax,"Location","best"); end
end
title(layout,"W3 relocation knowledge: unknown, exact, and bounded-phase cases");
localExport(folder,cfg,fig,"WFig34_W3_relocation_coherency",t);
end

function localRandomizationFigure(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,2,2,"TileSpacing","compact","Padding","compact");
labels=categorical(t.RandomizationProfile,t.RandomizationProfile);
fields=["CrossCorrelation","CoherentGain","DopplerRMSEHz","DetectionProbability"];
ylabels=["Normalized cross-correlation","Cross-symbol coherent gain", ...
    "Doppler RMSE (Hz)","Detection probability"];
for i=1:numel(fields)
    ax=nexttile(layout); bar(ax,labels,t.(fields(i))); ylabel(ax,ylabels(i)); grid(ax,"on");
    if fields(i)=="CrossCorrelation" || fields(i)=="CoherentGain" || fields(i)=="DetectionProbability"
        ylim(ax,[0 max(1,1.08*max(t.(fields(i))))]);
    end
end
title(layout,"W1 randomization tradeoff — independent sequence and target trials");
localExport(folder,cfg,fig,"WFig35_randomization_tradeoff",t);
end

function [x,y]=localGroupedMetric(xRaw,yRaw,metric)
x=unique(double(xRaw(:)),"sorted"); y=NaN(size(x));
for i=1:numel(x)
    values=double(yRaw(double(xRaw(:))==x(i)));
    if metric=="WrongPeak", y(i)=mean(values~=0);
    elseif metric=="DopplerErrorHz", y(i)=sqrt(mean(values.^2,"omitnan"));
    else, y(i)=mean(values,"omitnan"); end
end
end

function value=localShortRule(rule)
if rule=="absolute_physical_symbol", value="correct absolute state";
else, value="wrong tx counter"; end
end

function localComplexityFigure(folder,cfg,t)
fig=localFigure(cfg); c=onCleanup(@()close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,1,3,"TileSpacing","compact","Padding","compact");
labels=categorical(t.ReceiverProfile,t.ReceiverProfile);
nexttile(layout); bar(labels,t.BufferBytes); ylabel("Buffer (bytes)"); grid on;
nexttile(layout); bar(labels,[t.MedianProcessingLatencyMs t.P90ProcessingLatencyMs]);
ylabel("Processing latency (ms)"); legend("median","p90"); grid on;
nexttile(layout); yyaxis left; bar(labels,t.FFTCountEstimate); ylabel("FFT count");
yyaxis right; plot(labels,t.ComplexMultiplyEstimate,"ko-","LineWidth",1.2);
ylabel("Complex multiplies"); grid on;
title(layout,"Separate receiver buffer, measured runtime, and operation estimate");
localExport(folder,cfg,fig,"WFig36_buffer_latency_complexity",t);
end

function trial=localTrial(id,seed,receiver)
trial=struct("TrialId",char(id),"Seed",double(seed),"WaveformSeed",double(seed), ...
    "DelayOverCP",.9,"NormalizedDoppler",.01,"SensingMode","trp_monostatic", ...
    "CollisionRatioPercent",0,"CollisionResponse","share_reuse", ...
    "TDDPattern","all_dl","TargetPresent",true,"UseGeometryDelay",false, ...
    "PortProfile","single_port","ReceiverProfile",char(receiver),"CoherentSymbols",14, ...
    "CollisionMaskProfile","random_isolated","SequenceVariant","default");
end

function fig=localFigure(cfg)
pixels=double(cfg.output.imageSizePixels(:).'); dpi=double(cfg.output.imageResolutionDPI);
fig=figure("Visible","off","Color","white","Units","inches","Position",[1 1 pixels(1)/dpi pixels(2)/dpi]);
end

function localExport(folder,cfg,fig,stem,t)
localPublicationStyle(fig);
save(fullfile(folder,"figures",stem+".mat"),"t"); writetable(t,fullfile(folder,"figures",stem+".csv"));
savefig(fig,fullfile(folder,"figures",stem+".fig"));
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

function localLayout(folder)
for name=["raw","aggregate","tables","figures"]
    p=fullfile(folder,name); if exist(p,"dir")~=7, mkdir(p); end
end
end

function root=localRepoRoot()
root=fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
