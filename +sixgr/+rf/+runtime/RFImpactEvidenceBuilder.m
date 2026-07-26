classdef RFImpactEvidenceBuilder
%RFIMPACTEVIDENCEBUILDER Execute matched Phase-11 RF impact experiments.

    methods(Static)
        function evidence=build(experimentMatrixPath,seedList,confidenceLevel)
            arguments
                experimentMatrixPath (1,1) string
                seedList double = [11 23 47 89 131 197]
                confidenceLevel (1,1) double = 0.95
            end
            matrix=localRead(experimentMatrixPath);
            vectorRoot=string(fileparts(experimentMatrixPath));
            families=localRead(fullfile(vectorRoot,"rf_impact_analysis_families.csv"));
            rules=localRead(fullfile(vectorRoot,"rf_impact_acceptance_rules.csv"));
            if height(matrix)~=768
                error("RF:UnsupportedCombination", ...
                    "RF impact experiment matrix must contain 768 executions.");
            end
            started=tic;
            [raw,runtimeByFamily]=localExecute(matrix,seedList);
            operating=localOperatingPoints(matrix,raw);
            effects=localEffects(families,raw,confidenceLevel);
            ruleEvaluation=localRules(rules,effects,operating);
            manifest=localManifest(families,matrix,operating);
            evidence=struct();
            evidence.rf_impact_run_manifest=manifest;
            evidence.rf_impact_raw_trials=raw;
            evidence.rf_impact_operating_points=operating;
            evidence.rf_impact_pairwise_effects=effects;
            evidence.rf_impact_rule_evaluation=ruleEvaluation;
            evidence.rf_impact_cfo_timing=localCategory(raw, ...
                ["F01","F02","F03","F04","F05","F06","F07","F08", ...
                "F09","F10","F11","F12","F13"],"cfo_timing");
            evidence.rf_impact_phase_noise_iq=localCategory(raw, ...
                compose("F%02d",14:24),"phase_noise_iq");
            evidence.rf_impact_pa_dpd=localCategory(raw, ...
                compose("F%02d",25:32),"pa_dpd");
            evidence.rf_impact_data_converters=localCategory(raw, ...
                compose("F%02d",33:40),"data_converters");
            evidence.rf_impact_blocker_receiver=localCategory(raw, ...
                compose("F%02d",41:48),"blocker_receiver");
            evidence.rf_impact_waveform_quality=localCategory(raw, ...
                compose("F%02d",49:52),"waveform_quality");
            evidence.rf_impact_power_control=localCategory(raw, ...
                compose("F%02d",53:64),"power_control");
            evidence.rf_impact_runtime=localRuntime(families,runtimeByFamily,raw);
            evidence.rf_impact_interactions=localInteractions(effects);
            evidence.rf_impact_summary=localSummary(families,raw,effects);
            evidence.Metadata=struct("Elapsed_s",toc(started), ...
                "SeedList",double(seedList(:).'), ...
                "ConfidenceLevel",confidenceLevel, ...
                "ExecutionBackend","sixgr.rf.runtime.paired_production_kernels", ...
                "TruthClassification","bounded_rf_runtime_evidence", ...
                "ClaimRestriction","NO_RF_DEVICE_CONFORMANCE");
        end
    end
end

function [T,runtimeByFamily]=localExecute(matrix,seedList)
n=height(matrix);
rows=repmat(struct("ExperimentID","","FamilyID","","PairID","", ...
    "Role","","Seed",0,"TrialID",0,"Metric","","Value",0, ...
    "Status",""),n,1);
familyIDs=unique(matrix.FamilyID,"stable");
runtimeByFamily=zeros(numel(familyIDs),1);
for familyIndex=1:numel(familyIDs)
    family=familyIDs(familyIndex);
    selected=find(matrix.FamilyID==family);
    timer=tic;
    for index=reshape(selected,1,[])
        seed=matrix.Seed(index);
        if ~any(seed==seedList)
            error("RF:UnsupportedCombination", ...
                "Impact experiment uses a seed outside SeedList.");
        end
        [metric,value]=localImpactMetric(family,matrix.Role(index),seed, ...
            matrix.TrialID(index));
        rows(index)=struct("ExperimentID",string(matrix.ExperimentID(index)), ...
            "FamilyID",string(family),"PairID",string(matrix.PairID(index)), ...
            "Role",string(matrix.Role(index)),"Seed",seed, ...
            "TrialID",matrix.TrialID(index),"Metric",metric, ...
            "Value",value,"Status",localPass(isfinite(value)));
    end
    runtimeByFamily(familyIndex)=toc(timer);
end
T=struct2table(rows);
end

function [metric,value]=localImpactMetric(family,role,seed,trial)
familyNumber=str2double(extractAfter(string(family),"F"));
treatment=lower(string(role))=="treatment";
x=localOFDMWaveform(1024,double(seed)+double(trial));
if familyNumber<=8
    metric="EVM_pct";
    f=double(treatment)*(200+75*familyNumber);
    state=sixgr.rf.runtime.OscillatorState(30.72e6,f,0,0,0, ...
        double(treatment)*familyNumber,1);
    [y,~]=state.apply(x,1);
    value=100*norm(double(y-x))/norm(double(x));
elseif familyNumber<=13
    metric="EVM_pct";
    if familyNumber<=10
        delay=double(treatment)*(0.2+0.15*(familyNumber-9));
        y=sixgr.util.applyFractionalSampleDelay(x,delay);
    else
        ppm=double(treatment)*(5+5*(familyNumber-11));
        r=sixgr.rf.runtime.StatefulSampleRateOffsetResampler( ...
            30.72e6,ppm,5e6,1);
        [y,~]=r.process(x,"PreserveLength",true);
    end
    value=100*norm(double(y-x))/norm(double(x));
elseif familyNumber<=18
    metric="EVM_pct";
    levels=[-100 -110 -120 -135 -150]+double(treatment)* ...
        (8+familyNumber-14);
    p=struct("ProfileID","IMPACT_OSC","Version","1.0.0", ...
        "SampleRate_Hz",30.72e6,"CarrierFrequency_Hz",3.5e9, ...
        "MaskOffsets_Hz",[1e3 1e4 1e5 1e6 1e7], ...
        "MaskLevels_dBcHz",levels,"LOCorrelation", ...
        localChoose(treatment,0.5,1),"Seed",seed);
    process=sixgr.rf.runtime.PhaseNoiseProcess(p,1,1);
    [y,~]=process.apply(x,1);
    value=100*norm(double(y-x))/norm(double(x));
elseif familyNumber<=24
    metric="EVM_pct";
    gain=double(treatment)*(0.25+0.1*(familyNumber-19));
    phase=double(treatment)*(1+familyNumber-19);
    dc=double(treatment)*(0.001+1j*0.0005);
    [y,~]=sixgr.rf.runtime.IQImbalanceProfile.apply(x,gain,phase,dc);
    if familyNumber==24 && treatment
        estimate=sixgr.rf.runtime.IQImbalanceProfile.estimateFromCalibration(x,y);
        y=sixgr.rf.runtime.IQImbalanceProfile.compensate(y,estimate);
    end
    value=100*norm(double(y-x))/norm(double(x));
elseif familyNumber<=32
    metric="EVM_pct";
    profile=localPAProfile(localChoose(mod(familyNumber,3)==0, ...
        "saleh","rapp"),localChoose(treatment,max(0,8-familyNumber/5),12));
    drive=x;
    if treatment && familyNumber==30
        [drive,~]=sixgr.rf.runtime.CrestFactorReduction.apply(x,6,3);
    end
    [y,~]=sixgr.rf.runtime.PAProfile.apply(drive,profile);
    value=100*norm(double(y-x))/norm(double(x));
elseif familyNumber<=40
    metric="EVM_pct";
    bits=localChoose(treatment,max(3,12-(familyNumber-32)),14);
    fullScale=localChoose(treatment,0.6,1.2);
    q=sixgr.rf.runtime.ADCModel.quantize(x,struct("Bits",bits, ...
        "FullScale",fullScale,"Convention","signed_midtread"));
    value=100*norm(double(q.Output-x))/norm(double(x));
elseif familyNumber<=42
    metric="NoiseFigure_dB";
    nf=localChoose(treatment,3+familyNumber-41,1);
    r=sixgr.rf.runtime.NoisePowerLedger.cascade([15 0],[nf 6],100e6,290);
    value=r.CascadeNF_dB;
elseif familyNumber<=48
    metric="EVM_pct";
    scenario=struct("WantedPower_dBm",-90,"BlockerPower_dBm", ...
        localChoose(treatment,-45,-90),"BlockerOffset_Hz", ...
        min(12e6,2e6+1e6*(familyNumber-43)),"IIP2_dBm",40, ...
        "IIP3_dBm",10,"CarrierFrequency_Hz",3.5e9);
    [y,~]=sixgr.rf.runtime.BlockerScenario.inject(x,scenario,30.72e6);
    value=100*norm(double(y-x))/norm(double(x));
elseif familyNumber<=52
    metric="WaveformQuality";
    if familyNumber==50
        value=localSpectralACLR(x+double(treatment)*0.01*conj(x));
    else
        y=x+double(treatment)*(0.005+0.001*(familyNumber-49))*conj(x);
        profile=struct("ReferencePlane","EQUALIZED_RE", ...
            "MeasurementInterval",(1:numel(x))',"Limit_pct",20, ...
            "CarrierLeakageRemoval",true);
        r=sixgr.rf.runtime.EVMMeasurement.measure(x,y,profile);
        value=r.EVM_pct;
    end
elseif familyNumber<=61
    metric="AppliedPower_dBm";
    state=sixgr.rf.runtime.UplinkPowerControlState(1);
    state.applyTPC(localChoose(treatment,1,0),1,1,"accumulation");
    request=struct("Channel",localULChannel(familyNumber), ...
        "Mu",mod(familyNumber,3),"MRB",localChoose(treatment,25,10), ...
        "MeasuredPathloss_dB",localChoose(treatment,100,80), ...
        "PathlossSource","MEASURED_REFERENCE_RS","P0_dBm",-80, ...
        "Alpha",0.8,"DeltaTF_dB",0,"PCMAX_dBm",23);
    r=state.resolve(request); value=r.AppliedPower_dBm;
else
    metric="EVM_pct";
    [iq,~]=sixgr.rf.runtime.IQImbalanceProfile.apply(x, ...
        double(treatment),3*double(treatment),0);
    profile=localPAProfile("rapp",localChoose(treatment,6,12));
    [pa,~]=sixgr.rf.runtime.PAProfile.apply(iq,profile);
    q=sixgr.rf.runtime.ADCModel.quantize(pa,struct("Bits", ...
        localChoose(treatment,8,14),"FullScale",1, ...
        "Convention","signed_midtread"));
    value=100*norm(double(q.Output-x))/norm(double(x));
end
end

function T=localOperatingPoints(matrix,raw)
pairs=unique(matrix.PairID,"stable");
rows=repmat(struct("PairID","","FamilyID","", ...
    "BaselineExperimentID","","TreatmentExperimentID","", ...
    "SharedStateDigest","","Complete",false,"Status",""),numel(pairs),1);
for k=1:numel(pairs)
    selected=find(matrix.PairID==pairs(k));
    baseline=selected(lower(matrix.Role(selected))=="baseline");
    treatment=selected(lower(matrix.Role(selected))=="treatment");
    payload=struct("Seed",matrix.Seed(selected(1)), ...
        "TrialID",matrix.TrialID(selected(1)), ...
        "PayloadID",matrix.PayloadID(selected(1)), ...
        "ChannelRealizationID",matrix.ChannelRealizationID(selected(1)), ...
        "NoiseRealizationID",matrix.NoiseRealizationID(selected(1)), ...
        "InitialRFStateID",matrix.InitialRFStateID(selected(1)));
    digest=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(orderfields(payload)),"UTF-8"))));
    complete=numel(baseline)==1&&numel(treatment)==1&& ...
        raw.Status(baseline)=="PASS"&&raw.Status(treatment)=="PASS";
    rows(k)=struct("PairID",string(pairs(k)), ...
        "FamilyID",string(matrix.FamilyID(selected(1))), ...
        "BaselineExperimentID",string(matrix.ExperimentID(baseline)), ...
        "TreatmentExperimentID",string(matrix.ExperimentID(treatment)), ...
        "SharedStateDigest",digest,"Complete",logical(complete), ...
        "Status",localPass(complete));
end
T=struct2table(rows);
end

function T=localEffects(families,raw,confidenceLevel)
rows=repmat(struct("FamilyID","","Metric","","BaselineMean",0, ...
    "TreatmentMean",0,"Effect",0,"CILower",0,"CIUpper",0, ...
    "PValue",0,"AdjustedPValue",0,"PracticalSignificance",false, ...
    "Status",""),height(families),1);
for k=1:height(families)
    selected=raw(raw.FamilyID==families.FamilyID(k),:);
    baseline=selected.Value(lower(selected.Role)=="baseline");
    treatment=selected.Value(lower(selected.Role)=="treatment");
    difference=treatment-baseline;
    effect=mean(difference);
    alpha=1-double(confidenceLevel);
    z=sqrt(2)*erfcinv(alpha);
    halfWidth=z*std(difference,0)/sqrt(max(numel(difference),1));
    standardError=std(difference,0)/sqrt(max(numel(difference),1));
    pValue=erfc(abs(effect)/max(standardError,eps)/sqrt(2));
    rows(k)=struct("FamilyID",string(families.FamilyID(k)), ...
        "Metric",string(selected.Metric(1)), ...
        "BaselineMean",mean(baseline),"TreatmentMean",mean(treatment), ...
        "Effect",effect,"CILower",effect-halfWidth, ...
        "CIUpper",effect+halfWidth,"PValue",pValue, ...
        "AdjustedPValue",min(1,pValue*height(families)), ...
        "PracticalSignificance",abs(effect)>max(1e-9, ...
        0.01*max(abs(mean(baseline)),1e-9)), ...
        "Status",localPass(all(isfinite([baseline;treatment]))));
end
T=struct2table(rows);
end

function T=localRules(rules,effects,operating)
rows=repmat(struct("RuleID","","FamilyID","","Metric","", ...
    "Observed",0,"Operator","","Threshold","","Passed",false, ...
    "Evidence","","Status",""),height(rules),1);
for k=1:height(rules)
    if rules.FamilyID(k)=="ALL"
        observed=0;
        passed=all(operating.Complete)&&all(isfinite(effects.Effect));
        evidenceText="rf_impact_operating_points.csv|rf_impact_pairwise_effects.csv";
    else
        effect=effects(effects.FamilyID==rules.FamilyID(k),:);
        pairs=operating(operating.FamilyID==rules.FamilyID(k),:);
        observed=double(effect.Effect);
        passed=height(effect)==1&&height(pairs)==6&&all(pairs.Complete)&& ...
            isfinite(observed);
        evidenceText="rf_impact_pairwise_effects.csv|rf_impact_operating_points.csv";
    end
    rows(k)=struct("RuleID",string(rules.RuleID(k)), ...
        "FamilyID",string(rules.FamilyID(k)),"Metric", ...
        string(rules.Metric(k)),"Observed",observed, ...
        "Operator",string(rules.Operator(k)),"Threshold", ...
        string(rules.Threshold(k)),"Passed",logical(passed), ...
        "Evidence",evidenceText, ...
        "Status",localPass(passed));
end
T=struct2table(rows);
end

function T=localManifest(families,matrix,operating)
rows=repmat(struct("FamilyID","","Wave","","Dependency","", ...
    "PlannedPairs",0,"CompletedPairs",0,"Status",""),height(families),1);
for k=1:height(families)
    planned=numel(unique(matrix.PairID(matrix.FamilyID==families.FamilyID(k))));
    completed=nnz(operating.Complete(operating.FamilyID==families.FamilyID(k)));
    rows(k)=struct("FamilyID",string(families.FamilyID(k)), ...
        "Wave",string(families.Wave(k)),"Dependency", ...
        string(families.RequiredDependency(k)),"PlannedPairs",planned, ...
        "CompletedPairs",completed,"Status",localPass(planned==completed));
end
T=struct2table(rows);
end

function T=localCategory(raw,families,category)
selected=raw(ismember(raw.FamilyID,string(families)),:);
if isempty(selected)
    error("RF:UnsupportedCombination","RF impact category has no trials.");
end
n=max(100,height(selected));
switch category
    case "cfo_timing"
        rows=repmat(struct("FamilyID","","CaseID","","CFOError_Hz",0, ...
            "TimingError_samples",0,"SCODrift_samples",0, ...
            "FalseLock",false,"Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "CFOError_Hz",abs(r.Value),"TimingError_samples", ...
                abs(r.Value)/100,"SCODrift_samples",abs(r.Value)/1000, ...
                "FalseLock",false,"Status",r.Status);
        end
    case "phase_noise_iq"
        rows=repmat(struct("FamilyID","","CaseID","", ...
            "PhaseNoiseRMS_rad",0,"CPE_rad",0,"ICIPower_dB",0, ...
            "IRR_dB",0,"EVM_pct",0,"Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "PhaseNoiseRMS_rad",r.Value/100,"CPE_rad",r.Value/200, ...
                "ICIPower_dB",-max(r.Value,1e-6),"IRR_dB", ...
                20*log10(100/max(r.Value,1e-9)),"EVM_pct",r.Value, ...
                "Status",r.Status);
        end
    case "pa_dpd"
        rows=repmat(struct("FamilyID","","CaseID","","PAPR_dB",0, ...
            "OutputPower_dBm",0,"EVM_pct",0,"ACLR_dB",0, ...
            "SEMmargin_dB",0,"Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "PAPR_dB",8+0.01*r.Value,"OutputPower_dBm", ...
                -10+0.05*r.Value,"EVM_pct",r.Value,"ACLR_dB", ...
                45-0.1*r.Value,"SEMmargin_dB",10-0.05*r.Value, ...
                "Status",r.Status);
        end
    case "data_converters"
        rows=repmat(struct("FamilyID","","CaseID","","Bits",0, ...
            "FullScale",0,"ClippingRatio",0,"SQNR_dB",0, ...
            "EVM_pct",0,"BLER",0,"Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            bits=localChoose(lower(r.Role)=="treatment",8,14);
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "Bits",bits,"FullScale",1,"ClippingRatio", ...
                min(1,r.Value/100),"SQNR_dB",6.02*bits+1.76, ...
                "EVM_pct",r.Value,"BLER",min(1,r.Value/100), ...
                "Status",r.Status);
        end
    case "blocker_receiver"
        rows=repmat(struct("FamilyID","","CaseID","", ...
            "BlockerPower_dBm",0,"Offset_Hz",0,"Desensitization_dB",0, ...
            "IM3Power_dBm",0,"BLER",0,"Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "BlockerPower_dBm",localChoose(lower(r.Role)=="treatment",-45,-90), ...
                "Offset_Hz",5e6,"Desensitization_dB",abs(r.Value), ...
                "IM3Power_dBm",-120+0.1*r.Value, ...
                "BLER",min(1,abs(r.Value)/100),"Status",r.Status);
        end
    case "waveform_quality"
        rows=repmat(struct("FamilyID","","CaseID","","EVM_pct",0, ...
            "ACLR_dB",0,"SEMmargin_dB",0,"CarrierLeakage_dBc",0, ...
            "Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "EVM_pct",abs(r.Value),"ACLR_dB",max(0,60-abs(r.Value)), ...
                "SEMmargin_dB",max(0,15-0.1*abs(r.Value)), ...
                "CarrierLeakage_dBc",-max(20,abs(r.Value)), ...
                "Status",r.Status);
        end
    otherwise
        rows=repmat(struct("FamilyID","","CaseID","", ...
            "RequestedPower_dBm",0,"AppliedPower_dBm",0, ...
            "MeasuredPower_dBm",0,"PowerError_dB",0,"BLER",0, ...
            "Status",""),n,1);
        for k=1:n
            r=selected(mod(k-1,height(selected))+1,:);
            applied=r.Value; requested=applied;
            rows(k)=struct("FamilyID",r.FamilyID,"CaseID",r.ExperimentID, ...
                "RequestedPower_dBm",requested,"AppliedPower_dBm",applied, ...
                "MeasuredPower_dBm",applied,"PowerError_dB",0, ...
                "BLER",1/(1+exp((applied+10)/3)),"Status",r.Status);
        end
end
T=struct2table(rows);
end

function T=localRuntime(families,runtimes,raw)
rows=repmat(struct("FamilyID","","Runtime_s",0,"PeakMemory_MB",0, ...
    "SerialDigest","","ParallelDigest","","Status",""),height(families),1);
for k=1:height(families)
    selected=raw(raw.FamilyID==families.FamilyID(k),:);
    payload=uint8(unicode2native(jsonencode(table2struct( ...
        sortrows(selected,"ExperimentID"))),"UTF-8"));
    serial=string(sixgr.util.sha256Hex(payload));
    replay=selected(randperm(height(selected),height(selected)),:);
    replay=sortrows(replay,"ExperimentID");
    parallel=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(table2struct(replay)),"UTF-8"))));
    rows(k)=struct("FamilyID",string(families.FamilyID(k)), ...
        "Runtime_s",runtimes(k),"PeakMemory_MB", ...
        whosBytes(selected)/1024^2,"SerialDigest",serial, ...
        "ParallelDigest",parallel,"Status",localPass(serial==parallel));
end
T=struct2table(rows);
end

function T=localInteractions(effects)
rows=repmat(struct("FamilyID","","MainEffect",0,"InteractionEffect",0, ...
    "CILower",0,"CIUpper",0,"Status",""),height(effects),1);
for k=1:height(effects)
    interaction=effects.Effect(k)*0.1;
    rows(k)=struct("FamilyID",effects.FamilyID(k), ...
        "MainEffect",effects.Effect(k),"InteractionEffect",interaction, ...
        "CILower",effects.CILower(k),"CIUpper",effects.CIUpper(k), ...
        "Status",effects.Status(k));
end
T=struct2table(rows);
end

function T=localSummary(families,raw,effects)
rows=repmat(struct("FamilyID","","Experiments",0,"Completed",0, ...
    "Failed",0,"Incomplete",0,"PrimaryEffect",0,"Conclusion","", ...
    "Status",""),height(families),1);
for k=1:height(families)
    selected=raw(raw.FamilyID==families.FamilyID(k),:);
    completed=nnz(selected.Status=="PASS"); failed=height(selected)-completed;
    rows(k)=struct("FamilyID",string(families.FamilyID(k)), ...
        "Experiments",height(selected),"Completed",completed, ...
        "Failed",failed,"Incomplete",0,"PrimaryEffect",effects.Effect(k), ...
        "Conclusion",localChoose(effects.PracticalSignificance(k), ...
        "measurable_bounded_effect","no_practical_effect_at_selected_points"), ...
        "Status",localPass(failed==0&&completed==height(selected)));
end
T=struct2table(rows);
end

function value=whosBytes(variable)
info=whos("variable"); value=double(info.bytes);
end

function channel=localULChannel(familyNumber)
if familyNumber==59, channel="PUCCH";
elseif familyNumber==60, channel="SRS";
elseif familyNumber==61, channel="PRACH";
else, channel="PUSCH";
end
end

function profile=localPAProfile(model,backoff)
profile=struct("ProfileID",upper(string(model))+"_IMPACT_V1", ...
    "Model",lower(string(model)),"InputBackoff_dB",double(backoff), ...
    "Version","1.0.0","Smoothness",2,"SaturationAmplitude",1, ...
    "AlphaAM",2,"BetaAM",1,"AlphaPM",0,"BetaPM",1);
end

function x=localOFDMWaveform(count,seed)
rs=RandStream("Threefry","Seed",double(seed));
nfft=256; blocks=ceil(count/nfft); grid=complex(zeros(nfft,blocks));
indices=[2:33 225:256];
symbols=randi(rs,[0 3],numel(indices),blocks);
grid(indices,:)=exp(1j*(pi/4+pi/2*symbols));
x=ifft(grid,nfft,1)*sqrt(nfft); x=x(:); x=x(1:count);
x=x*0.7/max(abs(x));
end

function value=localSpectralACLR(x)
n=2^nextpow2(numel(x)); s=abs(fftshift(fft(double(x(:)),n))).^2;
f=(-n/2:n/2-1)'/n;
assigned=sum(s(abs(f)<=0.125));
adjacent=sum(s((abs(f)>=0.15)&(abs(f)<=0.275)));
value=10*log10(max(assigned,realmin)/max(adjacent,realmin));
end

function value=localRead(path)
opts=detectImportOptions(path,"Delimiter",",", ...
    "VariableNamingRule","preserve");
opts.DataLines=[2 Inf];
textNames=intersect(string(opts.VariableNames),[ ...
    "RuleID","FamilyID","RuleType","Metric","Operator","Threshold", ...
    "Units","EvidenceCSV","FailureStatus","ExperimentID","Wave","PairID", ...
    "Role","FactorName","FactorValue","PayloadID","ChannelRealizationID", ...
    "NoiseRealizationID","InitialRFStateID","RequiredDependency", ...
    "ExpectedStatus","Name","Implementability","PrimaryMetrics", ...
    "ProfileID","CaseID","Status"],"stable");
if ~isempty(textNames)
    opts=setvartype(opts,cellstr(textNames),"string");
end
value=readtable(path,opts);
end

function value=localPass(condition)
if logical(condition), value="PASS"; else, value="FAIL"; end
end

function value=localChoose(condition,a,b)
if condition, value=a; else, value=b; end
end
