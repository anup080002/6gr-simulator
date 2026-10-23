classdef RFImpactEvidenceBuilder
%RFIMPACTEVIDENCEBUILDER Original bounded kernel observations, not link trials.

    methods(Static)
        function evidence=build(experimentMatrixPath,seedList,confidenceLevel,options)
            arguments
                experimentMatrixPath (1,1) string
                seedList double = [11 23 47 89 131 197]
                confidenceLevel (1,1) double = 0.95
                options.SelectedFamilyIDs string = strings(0,1)
            end
            matrix=localRead(experimentMatrixPath);
            vectorRoot=string(fileparts(experimentMatrixPath));
            families=localRead(fullfile(vectorRoot,"rf_impact_analysis_families.csv"));
            rules=localRead(fullfile(vectorRoot,"rf_impact_acceptance_rules.csv"));
            assert(isfinite(confidenceLevel)&&confidenceLevel>0&&confidenceLevel<1, ...
                'RF:ImpactContract','ConfidenceLevel must lie strictly between zero and one.');
            selected=options.SelectedFamilyIDs(:);
            if isempty(selected), selected=families.FamilyID; end
            assert(numel(unique(selected))==numel(selected)&&all(ismember(selected,families.FamilyID))&& ...
                all(ismember(selected,matrix.FamilyID)),'RF:ImpactContract','Select existing unique families only.');
            matrix=matrix(ismember(matrix.FamilyID,selected),:);
            families=families(ismember(families.FamilyID,selected),:);
            rules=rules(ismember(rules.FamilyID,selected)|rules.FamilyID=="ALL",:);
            localValidatePairs(matrix,seedList);
            started=tic;
            [raw,runtimeByFamily,operands]=localExecute(matrix,seedList);
            operating=localOperatingPoints(matrix,raw);
            effects=localEffects(families,raw,confidenceLevel);
            ruleEvaluation=localRules(rules,effects,raw);
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
            evidence.rf_impact_metric_availability=localAvailability(raw);
            evidence.ObservationOperands=operands;
            evidence.Metadata=struct("Contract","rf_impact_actual_kernel_observations/v2","Elapsed_s",toc(started), ...
                "SeedList",double(seedList(:).'), ...
                "RequestedConfidenceLevel",confidenceLevel,"SelectedFamilyIDs",selected, ...
                "RequestedExecutionCount",height(matrix),"ExecutedCount",height(raw), ...
                "ExperimentMatrixSHA256",string(sixgr.util.sha256File(experimentMatrixPath)), ...
                "ExecutionBackend","sixgr.rf.runtime.bounded_original_kernel_calls", ...
                "TruthClassification","component_observations_not_receiver_or_link_qualification", ...
                "StatisticallyQualified",false,"ClaimRestriction","NO_RF_DEVICE_OR_LINK_CONFORMANCE");
        end
    end
end

function [T,runtimeByFamily,operands]=localExecute(matrix,seedList)
n=height(matrix);
rows=cell(n,1); operands=cell(n,1);
familyIDs=unique(matrix.FamilyID,"stable");
runtimeByFamily=table(familyIDs,zeros(numel(familyIDs),1),'VariableNames',{'FamilyID','Runtime_s'});
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
        [metric,value,observation]=localImpactMetric(family,matrix.Role(index),seed, ...
            matrix.TrialID(index));
        row=struct("ExperimentID",string(matrix.ExperimentID(index)), ...
            "CaseID",string(matrix.ExperimentID(index)), ...
            "FamilyID",string(family),"PairID",string(matrix.PairID(index)), ...
            "Role",string(matrix.Role(index)),"Seed",seed, ...
            "TrialID",matrix.TrialID(index),"Metric",metric, ...
            "Value",value,"MetricAvailable",~isnan(value), ...
            "Status","executed_component_metric_not_feature_qualification");
        for field=string(fieldnames(observation.Receipt)).'
            row.(field)=observation.Receipt.(field);
        end
        token=string(jsonencode(sixgr.util.jsonSafeValue(row)));
        row.MeasurementReceiptJSON=token; row.MeasurementReceiptSHA256=localSHA(token);
        observation.ExperimentID=row.ExperimentID;
        observation.MeasurementReceiptJSON=token; observation.MeasurementReceiptSHA256=row.MeasurementReceiptSHA256;
        rows{index}=struct2table(row,'AsArray',true); operands{index}=observation;
    end
    runtimeByFamily.Runtime_s(familyIndex)=toc(timer);
end
T=vertcat(rows{:});
end

function [metric,value,observation]=localImpactMetric(family,role,seed,trial)
familyNumber=str2double(extractAfter(string(family),"F"));
assert(isfinite(familyNumber)&&familyNumber>=1&&familyNumber<=64&&familyNumber==fix(familyNumber), ...
    'RF:ImpactContract','Unsupported family.');
treatment=lower(string(role))=="treatment"; fs=30.72e6;
x=localOFDMWaveform(1024,double(seed)+double(trial)); y=[];
cfg=struct(); returned=struct(); r=localReceipt(); r.GeneratorSeed=double(seed)+double(trial);
metric="WaveformRelativeRMSError_pct"; value=NaN;
if familyNumber<=8
    r.Kernel="OscillatorState.apply";
    cfg=struct('SampleRate_Hz',fs,'TxError_Hz',double(treatment)*(200+75*familyNumber), ...
        'RxError_Hz',0,'LinkDoppler_Hz',0,'InitialPhase_rad',0,'Drift_HzPerS',double(treatment)*familyNumber,'StateEpoch',1);
    state=sixgr.rf.runtime.OscillatorState(fs,cfg.TxError_Hz,0,0,0,cfg.Drift_HzPerS,1);
    [y,returned]=state.apply(x,1);
    r.AppliedCFOTraceAvailable=true;
    r.AppliedCFOStart_Hz=returned.RelativeCFO_Hz(1); r.AppliedCFOEnd_Hz=returned.RelativeCFO_Hz(end);
elseif familyNumber<=13
    if familyNumber<=10
        r.Kernel="applyFractionalSampleDelay"; cfg=struct('Delay_samples',double(treatment)*(0.2+0.15*(familyNumber-9)));
        y=sixgr.util.applyFractionalSampleDelay(x,cfg.Delay_samples);
    else
        r.Kernel="StatefulSampleRateOffsetResampler.process";
        cfg=struct('SampleRate_Hz',fs,'Offset_ppm',double(treatment)*(5+5*(familyNumber-11)), ...
            'Bandwidth_Hz',5e6,'StateEpoch',1,'PreserveLength',true);
        state=sixgr.rf.runtime.StatefulSampleRateOffsetResampler(fs,cfg.Offset_ppm,5e6,1);
        [y,returned]=state.process(x,"PreserveLength",true);
    end
elseif familyNumber<=18
    r.Kernel="PhaseNoiseProcess.apply";
    cfg=struct("ProfileID","IMPACT_OSC","Version","1.0.0","SampleRate_Hz",fs, ...
        "CarrierFrequency_Hz",3.5e9,"MaskOffsets_Hz",[1e3 1e4 1e5 1e6 1e7], ...
        "MaskLevels_dBcHz",[-100 -110 -120 -135 -150]+double(treatment)*(8+familyNumber-14), ...
        "LOCorrelation",localChoose(treatment,0.5,1),"Seed",seed);
    state=sixgr.rf.runtime.PhaseNoiseProcess(cfg,1,1); [y,returned]=state.apply(x,1);
    r.AppliedPhaseRMS_rad=returned.IntegratedRMS_rad;
    r.AppliedPhaseTraceAvailable=true;
elseif familyNumber<=24
    r.Kernel="IQImbalanceProfile.apply";
    cfg=struct('GainImbalance_dB',double(treatment)*(0.25+0.1*(familyNumber-19)), ...
        'PhaseImbalance_deg',double(treatment)*(1+familyNumber-19), ...
        'DCOffset',double(treatment)*(0.001+1j*0.0005),'CalibrationCompensation',familyNumber==24&&treatment);
    [y,returned]=sixgr.rf.runtime.IQImbalanceProfile.apply(x,cfg.GainImbalance_dB,cfg.PhaseImbalance_deg,cfg.DCOffset);
    if cfg.CalibrationCompensation
        returned.CalibrationEstimate=sixgr.rf.runtime.IQImbalanceProfile.estimateFromCalibration(x,y);
        y=sixgr.rf.runtime.IQImbalanceProfile.compensate(y,returned.CalibrationEstimate);
    end
elseif familyNumber<=32
    r.Kernel="PAProfile.apply";
    cfg=localPAProfile(localChoose(mod(familyNumber,3)==0,"saleh","rapp"),localChoose(treatment,max(0,8-familyNumber/5),12));
    drive=x;
    if treatment&&familyNumber==30
        [drive,returned.CFR]=sixgr.rf.runtime.CrestFactorReduction.apply(x,6,3);
        cfg.CFR=struct('TargetPAPR_dB',6,'Iterations',3);
    end
    [y,returned.PA]=sixgr.rf.runtime.PAProfile.apply(drive,cfg);
elseif familyNumber<=40
    r.Kernel="ADCModel.quantize";
    cfg=struct("Bits",localChoose(treatment,max(3,12-(familyNumber-32)),14), ...
        "FullScale",localChoose(treatment,0.6,1.2),"Convention","signed_midtread");
    returned=sixgr.rf.runtime.ADCModel.quantize(x,cfg); y=returned.Output;
    r.ADCResultAvailable=true; r.Bits=returned.Bits; r.FullScale=returned.FullScale;
    r.ClippingRatio=returned.ClippingRatio; r.ADCErrorVariance=returned.ErrorVariance;
elseif familyNumber<=42
    r.Kernel="NoisePowerLedger.cascade"; r.ReferencePlane="analytical_noise_cascade_not_receiver_samples";
    r.ObservationMode="analytical_equation_only";
    cfg=struct('Gain_dB',[15 0],'NoiseFigure_dB',[localChoose(treatment,3+familyNumber-41,1) 6], ...
        'Bandwidth_Hz',100e6,'Temperature_K',290);
    returned=sixgr.rf.runtime.NoisePowerLedger.cascade(cfg.Gain_dB,cfg.NoiseFigure_dB,100e6,290);
    r.ModeledNoiseFigure_dB=returned.CascadeNF_dB; metric="ModeledNoiseFigure_dB"; value=r.ModeledNoiseFigure_dB;
    r.ModeledNoiseFigureAvailable=true;
elseif familyNumber<=48
    r.Kernel="BlockerScenario.inject";
    cfg=struct("WantedPower_dBm",-90,"BlockerPower_dBm",localChoose(treatment,-45,-90), ...
        "BlockerOffset_Hz",min(12e6,2e6+1e6*(familyNumber-43)),"IIP2_dBm",40,"IIP3_dBm",10,"CarrierFrequency_Hz",3.5e9);
    [y,returned]=sixgr.rf.runtime.BlockerScenario.inject(x,cfg,fs);
    r.BlockerInjectionAvailable=true;
    r.MeasuredBlockerPower=mean(abs(double(returned.BlockerWaveform(:))).^2); r.BlockerOffset_Hz=cfg.BlockerOffset_Hz;
elseif familyNumber<=52
    r.Kernel="explicit_conjugate_image_waveform";
    amplitude=double(treatment)*localChoose(familyNumber==50,0.01,0.005+0.001*(familyNumber-49));
    cfg=struct('ConjugateImageAmplitude',amplitude,'ReferenceFittingApplied',false); y=x+amplitude*conj(x);
elseif familyNumber<=61
    r.Kernel="DeclaredAdditivePowerBudgetEquation"; r.ReferencePlane="analytical_assumed_input_power_budget_not_channel_specific_NR_or_applied_waveform";
    r.ObservationMode="analytical_equation_only";
    % There is no RS measurement or decoded TPC event in this component.
    % Do NOT call the guarded runtime power-state resolver with fake labels.
    cfg=struct("RequestedChannelLabel",localULChannel(familyNumber),"Mu",mod(familyNumber,3), ...
        "MRB",localChoose(treatment,25,10),"AssumedPathloss_dB",localChoose(treatment,100,80), ...
        "P0_dBm",-80,"Alpha",0.8,"DeltaTF_dB",0,"PCMAX_dBm",23, ...
        "AssumedTPCOffset_dB",localChoose(treatment,1,0), ...
        "Equation","P0+10log10(2^Mu*MRB)+Alpha*AssumedPathloss+DeltaTF+AssumedTPCOffset;clamp_at_PCMAX", ...
        "Authority","declared_inputs_not_RS_measurement_or_decoded_control");
    bandwidth=10*log10(2^cfg.Mu*cfg.MRB);
    requested=cfg.P0_dBm+bandwidth+cfg.Alpha*cfg.AssumedPathloss_dB+cfg.DeltaTF_dB+cfg.AssumedTPCOffset_dB;
    returned=struct('BandwidthTerm_dB',bandwidth,'AssumedPathlossTerm_dB',cfg.Alpha*cfg.AssumedPathloss_dB, ...
        'RequestedPower_dBm',requested,'ClampedPowerTarget_dBm',min(cfg.PCMAX_dBm,requested), ...
        'ReceiverMeasurementUsed',false,'DecodedControlUsed',false,'WaveformPowerApplied',false);
    r.RequestedPower_dBm=returned.RequestedPower_dBm; r.AppliedPowerTarget_dBm=returned.ClampedPowerTarget_dBm;
    r.PowerBudgetTargetAvailable=true;
    metric="AppliedPowerTarget_dBm"; value=r.AppliedPowerTarget_dBm;
else
    r.Kernel="IQ_PA_ADC_composite_kernel_not_end_to_end_link";
    cfg=struct('IQGain_dB',double(treatment),'IQPhase_deg',3*double(treatment), ...
        'PA',localPAProfile("rapp",localChoose(treatment,6,12)), ...
        'ADC',struct('Bits',localChoose(treatment,8,14),'FullScale',1,'Convention',"signed_midtread"));
    [iq,returned.IQ]=sixgr.rf.runtime.IQImbalanceProfile.apply(x,cfg.IQGain_dB,cfg.IQPhase_deg,0);
    [pa,returned.PA]=sixgr.rf.runtime.PAProfile.apply(iq,cfg.PA);
    returned.ADC=sixgr.rf.runtime.ADCModel.quantize(pa,cfg.ADC); y=returned.ADC.Output;
end
r.KernelConfigJSON=string(jsonencode(sixgr.util.jsonSafeValue(cfg))); r.KernelConfigSHA256=localSHA(r.KernelConfigJSON);
if ~isempty(y)
    r=localMeasure(r,x,y,fs); value=r.WaveformRelativeRMSError_pct;
    if familyNumber==50, metric="MeasuredBandPowerRatio_dB"; value=r.MeasuredBandPowerRatio_dB; end
else
    x=[]; r.GeneratorSeed=NaN; % The analytical equation did not consume a waveform.
    r.WaveformAmplitudeUnit=""; r.PowerUnit="";
end
r.ValueUnit="percent_time_waveform_relative_RMS_error";
if metric=="ModeledNoiseFigure_dB", r.ValueUnit="dB_analytical_noise_figure";
elseif metric=="AppliedPowerTarget_dBm", r.ValueUnit="dBm_assumed_input_equation_target_not_measured";
elseif metric=="MeasuredBandPowerRatio_dB", r.ValueUnit="dB_declared_two_sided_band_power_ratio"; end
observation=struct('Receipt',r,'Input',x,'Output',y,'Configuration',cfg,'ReturnedEvidence',returned, ...
    'AdditionalPHYExecutions',0);
end

function r=localReceipt()
r=struct('GeneratorSeed',NaN,'Kernel',"",'KernelConfigJSON',"",'KernelConfigSHA256',"",'ValueUnit',"", ...
    'ObservationMode',"executed_waveform_kernel",'ReceiverExecuted',false,'TransportBlockDecoderExecuted',false, ...
    'WaveformAmplitudeUnit',"normalized_complex_amplitude",'PowerUnit',"normalized_complex_amplitude_squared", ...
    'ErrorDefinition',"sum_abs_original_output_minus_input_squared_no_gain_or_phase_fit", ...
    'ReferencePlane',"normalized_complex_time_waveform_kernel_input_output", ...
    'RequestedFeatureStatus',"unqualified_component_kernel_only",'InputSHA256',"",'OutputSHA256',"", ...
    'SampleRate_Hz',NaN,'SampleCount',0,'ReferenceEnergy',NaN,'ErrorEnergy',NaN, ...
    'WaveformMetricsAvailable',false,'WaveformRelativeRMSError_pct',NaN,'InputMeanPower',NaN,'OutputMeanPower',NaN,'OutputPAPR_dB',NaN, ...
    'ADCResultAvailable',false,'Bits',NaN,'FullScale',NaN,'ClippingRatio',NaN,'ADCErrorVariance',NaN, ...
    'WaveformSignalToErrorRatio_dB',NaN,'AppliedCFOTraceAvailable',false,'AppliedPhaseTraceAvailable',false, ...
    'AppliedCFOStart_Hz',NaN,'AppliedCFOEnd_Hz',NaN,'AppliedPhaseRMS_rad',NaN, ...
    'SpectrumAvailable',false,'SpectrumNFFT',NaN,'SpectrumWindow',"", ...
    'SpectrumPowerNormalization',"sum_abs_fft_squared_divided_by_Nfft_squared",'AssignedBandLow_Hz',NaN, ...
    'AssignedBandHigh_Hz',NaN,'AdjacentAbsBandLow_Hz',NaN,'AdjacentAbsBandHigh_Hz',NaN, ...
    'AssignedBandPower',NaN,'AdjacentBandPower',NaN,'MeasuredBandPowerRatio_dB',NaN, ...
    'ModeledNoiseFigureAvailable',false,'ModeledNoiseFigure_dB',NaN,'PowerBudgetTargetAvailable',false, ...
    'RequestedPower_dBm',NaN,'AppliedPowerTarget_dBm',NaN,'BlockerInjectionAvailable',false, ...
    'MeasuredBlockerPower',NaN,'BlockerOffset_Hz',NaN,'BLER',NaN,'BLERAvailable',false, ...
    'BLERStatus',"unavailable_no_transport_block_decoder",'CFOError_Hz',NaN,'TimingError_samples',NaN,'FalseLock',NaN);
end

function r=localMeasure(r,x,y,fs)
assert(isequal(size(x),size(y))&&all(isfinite(x),'all')&&all(isfinite(y),'all'), ...
    'RF:ImpactOperand','Original finite waveform operands must have identical shape.');
r.InputSHA256=string(sixgr.phy.waveform.WaveformHash.runtimeArray(x));
r.OutputSHA256=string(sixgr.phy.waveform.WaveformHash.runtimeArray(y));
x=double(x); y=double(y); n=numel(x); r.SampleRate_Hz=fs; r.SampleCount=n;
r.ReferenceEnergy=sum(abs(x(:)).^2); r.ErrorEnergy=sum(abs(y(:)-x(:)).^2);
r.InputMeanPower=r.ReferenceEnergy/n; r.OutputMeanPower=sum(abs(y(:)).^2)/n;
if r.ReferenceEnergy>0
    r.WaveformMetricsAvailable=true;
    r.WaveformRelativeRMSError_pct=100*sqrt(r.ErrorEnergy/r.ReferenceEnergy);
    r.WaveformSignalToErrorRatio_dB=10*log10(r.ReferenceEnergy/r.ErrorEnergy);
end
if r.OutputMeanPower>0, r.OutputPAPR_dB=10*log10(max(abs(y(:)).^2)/r.OutputMeanPower); end
% Explicit two-sided rectangular-window band powers, NOT standard ACLR/SEM.
r.SpectrumNFFT=n; r.SpectrumWindow="rectangular_all_original_samples";
r.AssignedBandLow_Hz=-fs/8; r.AssignedBandHigh_Hz=fs/8;
r.AdjacentAbsBandLow_Hz=0.15*fs; r.AdjacentAbsBandHigh_Hz=0.275*fs;
f=(-n/2:n/2-1)'*fs/n; spectrum=abs(fftshift(fft(y(:),n))).^2/n^2;
r.AssignedBandPower=sum(spectrum(f>=r.AssignedBandLow_Hz&f<=r.AssignedBandHigh_Hz));
r.AdjacentBandPower=sum(spectrum(abs(f)>=r.AdjacentAbsBandLow_Hz&abs(f)<=r.AdjacentAbsBandHigh_Hz));
r.SpectrumAvailable=r.AssignedBandPower>0;
if r.SpectrumAvailable, r.MeasuredBandPowerRatio_dB=10*log10(r.AssignedBandPower/r.AdjacentBandPower); end
end

function localValidatePairs(matrix,seeds)
required=["ExperimentID","FamilyID","PairID","Role","Seed","TrialID", ...
    "PayloadID","ChannelRealizationID","NoiseRealizationID","InitialRFStateID"];
assert(all(ismember(required,string(matrix.Properties.VariableNames)))&&height(matrix)>0&& ...
    numel(unique(matrix.ExperimentID))==height(matrix),'RF:ImpactPairIdentity','Unique original executions required.');
assert(all(isfinite(matrix.Seed)&matrix.Seed>=0&matrix.Seed==fix(matrix.Seed))&& ...
    all(isfinite(matrix.TrialID)&matrix.TrialID>=0&matrix.TrialID==fix(matrix.TrialID))&& ...
    all(ismember(matrix.Seed,seeds)),'RF:ImpactPairIdentity','Valid original seed/trial values required.');
for key=["ExperimentID","FamilyID","PairID","Role"]
    assert(all(~ismissing(matrix.(key))&strlength(matrix.(key))>0),'RF:ImpactPairIdentity','Missing identity.');
end
same=["FamilyID","Seed","TrialID","PayloadID","ChannelRealizationID","NoiseRealizationID","InitialRFStateID"];
for pair=unique(matrix.PairID,'stable').'
    rows=matrix(matrix.PairID==pair,:);
    assert(height(rows)==2&&nnz(rows.Role=="baseline")==1&&nnz(rows.Role=="treatment")==1, ...
        'RF:ImpactPairIdentity','Each requested pair needs exactly one original baseline and treatment.');
    for name=same
        assert(isequaln(rows.(name)(1,:),rows.(name)(2,:)), ...
            'RF:ImpactPairIdentity','Pair %s changes original %s.',pair,name);
    end
end
end

function T=localOperatingPoints(matrix,raw)
pairs=unique(matrix.PairID,'stable'); rows=cell(numel(pairs),1);
for k=1:numel(pairs)
    m=matrix(matrix.PairID==pairs(k),:);
    b=raw(raw.PairID==pairs(k)&raw.Role=="baseline",:); t=raw(raw.PairID==pairs(k)&raw.Role=="treatment",:);
    assert(b.Kernel==t.Kernel&&b.Metric==t.Metric&&b.ReferencePlane==t.ReferencePlane&&b.InputSHA256==t.InputSHA256, ...
        'RF:ImpactPairIdentity','Pair kernels, planes and original waveform bytes must agree.');
    context=m(1,{'FamilyID','Seed','TrialID','PayloadID','ChannelRealizationID','NoiseRealizationID','InitialRFStateID'});
    token=string(jsonencode(table2struct(context)));
    rows{k}=table(pairs(k),b.FamilyID,b.ExperimentID,t.ExperimentID,localSHA(token),token,b.InputSHA256, ...
        true,"complete_original_execution_pair_not_independence", ...
        'VariableNames',{'PairID','FamilyID','BaselineExperimentID','TreatmentExperimentID', ...
        'DeclaredPairContextSHA256','DeclaredPairContextJSON','InputSHA256','Complete','Status'});
end
T=vertcat(rows{:});
end

function T=localEffects(families,raw,~)
rows=cell(height(families),1);
for k=1:height(families)
    selected=raw(raw.FamilyID==families.FamilyID(k),:); ids=sort(unique(selected.PairID));
    b=zeros(numel(ids),1); t=b;
    for j=1:numel(ids)
        b(j)=selected.Value(selected.PairID==ids(j)&selected.Role=="baseline");
        t(j)=selected.Value(selected.PairID==ids(j)&selected.Role=="treatment");
    end
    bm=NaN; tm=NaN; effect=NaN; deviation=NaN;
    if all(isfinite([b;t])), bm=mean(b); tm=mean(t); effect=mean(t-b); deviation=std(t-b,0); end
    rows{k}=table(families.FamilyID(k),selected.Metric(1),numel(ids),bm,tm,effect,deviation, ...
        NaN,NaN,NaN,NaN,false,"descriptive_matched_pairs_no_inferential_qualification", ...
        'VariableNames',{'FamilyID','Metric','PairCount','BaselineMean','TreatmentMean','Effect', ...
        'PairedDifferenceSD','CILower','CIUpper','PValue','AdjustedPValue','StatisticallyQualified','Status'});
end
T=vertcat(rows{:});
end

function T=localRules(rules,effects,raw)
rows=cell(height(rules),1);
for k=1:height(rules)
    observed=NaN; reason="unavailable_required_measurement_or_explicit_threshold";
    if rules.FamilyID(k)=="ALL"&&rules.Metric(k)=="IncompletePoints"
        observed=nnz(~raw.MetricAvailable); reason="actual_requested_component_execution_count_only";
    elseif rules.FamilyID(k)=="ALL"&&rules.Metric(k)=="NonFiniteSamples"&&any(raw.SampleCount>0)
        observed=0; reason="all_original_waveform_operands_checked_finite";
    elseif rules.FamilyID(k)~="ALL"
        e=effects(effects.FamilyID==rules.FamilyID(k),:);
        if height(e)==1&&rules.Metric(k)=="PairedEffect:"+e.Metric
            observed=e.Effect; reason="explicit_named_descriptive_pair_effect";
        end
    end
    threshold=str2double(rules.Threshold(k)); evaluated=false; passed=NaN;
    if isfinite(observed)&&isfinite(threshold)
        switch rules.Operator(k)
            case "==", passed=double(observed==threshold); evaluated=true;
            case "<=", passed=double(observed<=threshold); evaluated=true;
            case ">=", passed=double(observed>=threshold); evaluated=true;
            case "<", passed=double(observed<threshold); evaluated=true;
            case ">", passed=double(observed>threshold); evaluated=true;
        end
    end
    status="not_evaluated"; if evaluated, status=localChoose(passed==1,"PASS","FAIL"); end
    mandatory=any(lower(string(rules.Mandatory(k)))==["true","1"]);
    rows{k}=table(rules.RuleID(k),rules.FamilyID(k),rules.Metric(k),observed,rules.Operator(k), ...
        rules.Threshold(k),mandatory,evaluated,passed,reason,status, ...
        'VariableNames',{'RuleID','FamilyID','Metric','Observed','Operator','Threshold','Mandatory', ...
        'Evaluated','Passed','Evidence','Status'});
end
T=vertcat(rows{:});
end

function T=localManifest(families,matrix,operating)
rows=cell(height(families),1);
for k=1:height(families)
    id=families.FamilyID(k); planned=numel(unique(matrix.PairID(matrix.FamilyID==id)));
    completed=nnz(operating.FamilyID==id&operating.Complete);
    rows{k}=table(id,families.Wave(k),families.RequiredDependency(k),planned,completed, ...
        "executed_component_pairs_not_feature_qualification", ...
        'VariableNames',{'FamilyID','Wave','Dependency','PlannedPairs','CompletedPairs','Status'});
end
T=vertcat(rows{:});
end

function T=localCategory(raw,families,~)
% Lossless original executions only. Unsupported fields stay nonnumeric;
% this view never creates observations or converts one physical quantity.
T=raw(ismember(raw.FamilyID,string(families)),:);
end

function T=localRuntime(families,runtimes,raw)
rows=cell(height(families),1); info=whos('raw');
for k=1:height(families)
    selected=sortrows(raw(raw.FamilyID==families.FamilyID(k),:),'ExperimentID');
    digest=localSHA(string(jsonencode(sixgr.util.jsonSafeValue(table2struct(selected)))));
    elapsed=runtimes.Runtime_s(runtimes.FamilyID==families.FamilyID(k));
    assert(isscalar(elapsed),'RF:ImpactContract','Unique original family runtime required.');
    rows{k}=table(families.FamilyID(k),elapsed,true,height(selected),double(info.bytes),NaN,digest,"",false, ...
        "measured_serial_elapsed_only_no_parallel_or_peak_memory_measurement", ...
        'VariableNames',{'FamilyID','Runtime_s','RuntimeAvailable','ExecutedObservationCount','WholeRawTableStorageBytes','PeakMemory_MB', ...
        'SerialObservationDigest','ParallelDigest','ParallelExecutionPerformed','Status'});
end
T=vertcat(rows{:});
end

function T=localInteractions(~)
% No factorial interaction experiment was executed by this driver.
T=table(strings(0,1),zeros(0,1),strings(0,1), ...
    'VariableNames',{'FamilyID','InteractionEffect','Status'});
end

function T=localSummary(families,raw,effects)
rows=cell(height(families),1);
for k=1:height(families)
    selected=raw(raw.FamilyID==families.FamilyID(k),:);
    rows{k}=table(families.FamilyID(k),height(selected),height(selected),0,nnz(~selected.MetricAvailable), ...
        effects.Effect(k),false,"original_kernel_observations_only","not_feature_qualified", ...
        'VariableNames',{'FamilyID','Experiments','Completed','Failed','Incomplete','PrimaryEffect', ...
        'FeatureQualified','Conclusion','Status'});
end
T=vertcat(rows{:});
end

function T=localAvailability(raw)
metrics=["WaveformRelativeRMSError_pct","OutputPAPR_dB","MeasuredBandPowerRatio_dB", ...
    "ClippingRatio","AppliedPhaseRMS_rad","ModeledNoiseFigure_dB","AppliedPowerTarget_dBm", ...
    "BLER","CFOError_Hz","TimingError_samples","FalseLock","CPE","ICI","StandardACLR","SEM", ...
    "MeasuredPower_dBm","InteractionEffect","ParallelExecution"];
rows=cell(height(raw)*numel(metrics),1); at=0;
for k=1:height(raw)
    for metric=metrics
        at=at+1; available=false; reason="not_executed_or_not_defined_by_this_component";
        if ismember(metric,string(raw.Properties.VariableNames))
            value=raw.(metric)(k);
            if isnumeric(value), available=isscalar(value)&&~isnan(value); end
        end
        if available, reason="original_kernel_operand_or_returned_result"; end
        rows{at}=table(raw.ExperimentID(k),raw.FamilyID(k),metric,available,reason, ...
            'VariableNames',{'ExperimentID','FamilyID','Metric','Available','Status'});
    end
end
T=vertcat(rows{:});
end

function value=localSHA(token)
value=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
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

function value=localChoose(condition,a,b)
if condition, value=a; else, value=b; end
end
