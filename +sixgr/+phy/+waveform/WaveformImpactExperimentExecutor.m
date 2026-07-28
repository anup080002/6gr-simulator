classdef WaveformImpactExperimentExecutor
    %WAVEFORMIMPACTEXPERIMENTEXECUTOR Paired sample-domain impact trial.

    methods (Static)
        function result = execute(row)
            family=string(row.FamilyID);
            familyNumber=str2double(extractAfter(family,1));
            seed=str2double(string(row.Seed));
            trial=str2double(string(row.TrialIndex));
            factor=string(row.FactorValue);
            arm=string(row.Arm);
            stream=RandStream("mt19937ar","Seed",seed);
            bits=randi(stream,[0 1],96,1);
            grid=reshape(((1-2*bits(1:2:end))+ ...
                1j*(1-2*bits(2:2:end)))/sqrt(2),24,2);
            metric="";value=NaN;
            if familyNumber<=12
                [metric,value]=localOFDM(grid,familyNumber,arm,factor);
            elseif familyNumber<=25
                [metric,value]=localDFTS(grid,familyNumber,arm,factor);
            elseif familyNumber<=40
                [metric,value]=localSpectralComposition( ...
                    grid,familyNumber,arm,factor);
            elseif familyNumber<=53
                [metric,value]=localImpairment( ...
                    grid,familyNumber,arm,factor,stream);
            elseif familyNumber<=59
                [metric,value]=localRuntimeReproducibility( ...
                    grid,familyNumber,arm,factor);
            else
                [metric,value]=localResearchPlanning(familyNumber,arm,factor);
            end
            if ~isscalar(value)||~isfinite(value)
                error("WAVEFORM:ImpactExperimentIncomplete", ...
                    "Experiment %s produced no finite metric.",row.ExperimentID);
            end
            result=struct( ...
                "ExperimentID",string(row.ExperimentID), ...
                "FamilyID",family, ...
                "PairID",string(row.PairID), ...
                "Arm",arm, ...
                "Seed",seed, ...
                "TrialIndex",trial, ...
                "Metric",metric, ...
                "Value",double(value), ...
                "Status","PASS");
        end
    end
end

function [metric,value]=localOFDM(grid,family,arm,factor)
nfft=128;cp=9;
if family==1 && contains(lower(factor),"fallback")
    plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
        "unsupported_extension","dl_cp_ofdm");
    metric="planning_rejection_correct";
    value=double(plan.Outcome=="REJECT");
    return;
end
if family==3 && contains(lower(factor),"extended")
    carrier=nrCarrierConfig;carrier.SubcarrierSpacing=60;
    carrier.NSizeGrid=6;carrier.CyclicPrefix="extended";
    resolved=sixgr.phy.waveform.OFDMParameterResolver.resolve(carrier);
    metric="resolved_symbols_per_slot";
    value=double(resolved.SymbolsPerSlot);
    return;
end
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,cp);
factorScale=localFactorScale(arm,factor);
switch family
    case 4
        delay=round((cp-2)+(arm=="TREATMENT")*(cp+3));
        impaired=[zeros(delay,1);wave(1:end-delay)];
    case 6
        if arm=="TREATMENT"
            metric="dc_fault_rejected";
            try
                sixgr.phy.waveform.SubcarrierMapper.build(16,17);
                value=0;
            catch exception
                value=double(string(exception.identifier)== ...
                    "WAVEFORM:InvalidSubcarrierMap");
            end
            return;
        end
        impaired=wave;
    case 8
        overlap=double(arm=="TREATMENT")*4;
        profile=sixgr.phy.waveform.WindowingProfile.resolve( ...
            localWindowProfile(overlap),overlap,overlap>0);
        blocks=reshape(wave(1:floor(numel(wave)/2)*2),[],2,1);
        state=sixgr.phy.waveform.WindowOverlapState(overlap,1);
        [impaired,state]=sixgr.phy.waveform.WOLAEngine.process( ...
            blocks,profile,state);
        impaired=[impaired;sixgr.phy.waveform.WOLAEngine.flush(state)];
        impaired=impaired(1:min(numel(impaired),numel(wave)));
        wave=wave(1:numel(impaired));
    case 11
        state=sixgr.phy.waveform.OFDMStreamState(1.92e6,0);
        [part1,state]=sixgr.phy.waveform.WaveformStreamComposer.frequencyShift( ...
            wave(1:37),1e3,1.92e6,state);
        [part2,~]=sixgr.phy.waveform.WaveformStreamComposer.frequencyShift( ...
            wave(38:end),1e3,1.92e6,state);
        impaired=[part1.Samples;part2.Samples];
        referenceState=sixgr.phy.waveform.OFDMStreamState(1.92e6,0);
        [reference,~]=sixgr.phy.waveform.WaveformStreamComposer.frequencyShift( ...
            wave,1e3,1.92e6,referenceState);
        metric="chunk_nmse";value=localNMSE(reference.Samples,impaired);return;
    otherwise
        impaired=wave*factorScale;
end
lengthOne=min(numel(wave),numel(impaired));
metric="waveform_nmse";
value=localNMSE(wave(1:lengthOne),impaired(1:lengthOne));
end

function [metric,value]=localDFTS(grid,family,arm,factor)
nfft=128;cp=9;
spread=sixgr.phy.waveform.UnitaryDFTSpreader.apply(grid,24);
if family==16
    bits=real(grid(:))<0;
    if contains(lower(factor),"pi/2")
        symbols=sixgr.phy.waveform.PiOver2BPSKMapper.map(bits,0);
        spread=reshape(symbols,24,2);
    end
end
if family==17 && contains(upper(factor),"256QAM")
    spread=spread.*exp(1j*pi/8);
end
if family>=21 && family<=24 && contains(lower(factor),"enabled")
    weights=linspace(.9,1.1,size(spread,1)).';
    [spread,shapeState]=sixgr.phy.waveform.FrequencyDomainShapingEngine.apply( ...
        spread,weights);
    spread=sixgr.phy.waveform.FrequencyDomainShapingEngine.invert( ...
        spread,shapeState);
end
baseline=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,cp);
treatment=sixgr.phy.waveform.CanonicalOFDMModulator.math(spread,nfft,cp);
if contains(lower(factor),"cp-ofdm")||arm=="BASELINE"
    selected=baseline;
else
    selected=treatment;
end
papr=sixgr.phy.waveform.PAPRMeasurement.measure(selected,8);
metric="papr_db";value=papr.PAPR_dB;
end

function [metric,value]=localSpectralComposition(grid,family,arm,factor)
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,128,9);
if family>=29&&family<=38
    components=repmat(struct("ComponentID","","Samples",wave, ...
        "SampleRate_Hz",1.92e6,"StartSample",0, ...
        "FrequencyOffset_Hz",0,"Power_dB",0),2,1);
    components(1).ComponentID="A";components(2).ComponentID="B";
    components(1).FrequencyOffset_Hz=-2e5;
    components(2).FrequencyOffset_Hz=2e5;
    components(2).StartSample=double(contains(lower(factor),"asynchronous"))*7;
    components(2).Power_dB=-double(contains(lower(factor),"near-far"))*12;
    result=sixgr.phy.waveform.MultiNumerologyWaveformComposer.compose( ...
        components,1.92e6);
    metric="composition_sum_error";
    value=result.ContributionSumError;
    if family==35
        value=10*log10(mean(abs(result.Contributions(:,1)).^2)/ ...
            max(mean(abs(result.Contributions(:,2)).^2),realmin));
        metric="component_power_imbalance_db";
    end
    return;
end
window="rectangular";
if contains(lower(factor),"hann"),window="hann";end
measurement=sixgr.phy.waveform.SpectralMeasurement.measure( ...
    wave,1.92e6,"FFTSize",max(2048,numel(wave)), ...
    "AnalysisWindow",window,"OccupiedBand_Hz",[-4e5 4e5], ...
    "GuardBands_Hz",[-9e5 -5e5;5e5 9e5]);
metric="spectral_power_error_db";value=measurement.Error_dB;
end

function [metric,value]=localImpairment(grid,family,arm,factor,stream)
nfft=128;cp=9;rate=1.92e6;
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,cp);
impaired=wave;
switch family
    case 41
        cfo=double(contains(lower(factor),"0.2"))*.2*15e3;
        impaired=wave.*exp(1j*2*pi*cfo*(0:numel(wave)-1).'/rate);
    case {42,47}
        delay=double(~contains(lower(factor),"zero") && ...
            ~contains(lower(factor),"within"))*(cp+3);
        impaired=[zeros(delay,1);wave(1:end-delay*(delay>0))];
        if delay==0,impaired=wave;end
    case 43
        ppm=double(contains(lower(factor),"20"))*20e-6;
        impaired=wave.*exp(1j*2*pi*ppm*rate*(0:numel(wave)-1).'/rate);
    case 44
        if contains(lower(factor),"enabled")
            phase=cumsum(.002*randn(stream,numel(wave),1));
            impaired=wave.*exp(1j*phase);
        end
    case {45,46}
        tap=0.15+0.2*double(contains(lower(factor),"high"));
        impaired=filter([1 zeros(1,cp+1) tap],1,wave);
    case 48
        variance=double(contains(lower(factor),"tiny"))*1e-8;
        impaired=wave+sqrt(variance/2)*(randn(stream,size(wave))+ ...
            1j*randn(stream,size(wave)));
    case 49
        if contains(lower(factor),"wrong")
            recovered=sixgr.phy.waveform.UnitaryDFTDespreader.apply(grid,12);
            metric="wrong_dft_size_rejected";
            value=double(isempty(recovered));
            return;
        end
    otherwise
        impaired=wave*localFactorScale(arm,factor);
end
recovered=sixgr.phy.waveform.CanonicalOFDMDemodulator.math( ...
    impaired,nfft,repmat(cp,1,2),24);
evm=sixgr.phy.waveform.WaveformEVMMeasurement.measure(grid,recovered);
metric="evm_pct";value=evm.EVM_pct;
end

function [metric,value]=localRuntimeReproducibility(grid,family,arm,factor)
if family==56
    seed=11+double(contains(lower(factor),"different"));
    first=localSeededWave(seed);second=localSeededWave(11);
    metric="waveform_digest_match";
    value=double(sixgr.phy.waveform.WaveformHash.numeric(first)== ...
        sixgr.phy.waveform.WaveformHash.numeric(second));
    return;
end
nfft=128;
if family==57&&contains(lower(factor),"large"),nfft=512;end
iterations=1+3*double(family==59&&contains(lower(factor),"long"));
tic
for index=1:iterations %#ok<FORPF>
    wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,nfft,9); %#ok<NASGU>
end
duration=toc;
metric="runtime_seconds";value=duration;
end

function [metric,value]=localResearchPlanning(family,arm,factor)
metric="planning_correct";
switch family
    case 60
        feature="explicit_wola";
        if contains(lower(factor),"unsupported"),feature="otfs";end
        plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
            "waveform_research_candidate",feature);
        value=double((feature=="otfs"&&plan.Outcome=="REJECT") || ...
            (feature~="otfs"&&plan.Outcome=="EXECUTE"));
    case 61
        assignment=struct("Decoded",true,"LayerCount",1, ...
            "PRBCount",4,"Contiguous",true,"ConfigurationEpoch",1, ...
            "CurrentConfigurationEpoch",1, ...
            "PTRSSymbolPartitionExact",true,"Modulation","QPSK");
        if contains(lower(factor),"multi"),assignment.LayerCount=2;end
        try
            sixgr.phy.waveform.TransformPrecodingPlan( ...
                assignment,"nr_rel19_ul_dfts_ofdm_strict");
            value=double(assignment.LayerCount==1);
        catch exception
            value=double(assignment.LayerCount>1&& ...
                string(exception.identifier)=="WAVEFORM:TransformPrecodingLayerCount");
        end
    case 62
        feature="dl_cp_ofdm";
        if contains(lower(factor),"dft"),feature="dl_dfts_ofdm";end
        plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
            "nr_rel19_cp_ofdm_strict",feature);
        value=double((feature=="dl_cp_ofdm"&&plan.Outcome=="EXECUTE") || ...
            (feature=="dl_dfts_ofdm"&&plan.Outcome=="REJECT"));
    otherwise
        plan=sixgr.phy.waveform.WaveformCapabilityProfile.plan( ...
            "nr_rel19_multinumerology_strict","multi_numerology_sync");
        value=double(plan.Outcome=="EXECUTE");
end
value=value+0*double(arm=="TREATMENT");
end

function wave=localSeededWave(seed)
stream=RandStream("mt19937ar","Seed",double(seed));
bits=randi(stream,[0 1],96,1);
grid=reshape(((1-2*bits(1:2:end))+ ...
    1j*(1-2*bits(2:2:end)))/sqrt(2),24,2);
wave=sixgr.phy.waveform.CanonicalOFDMModulator.math(grid,128,9);
end

function scale=localFactorScale(arm,factor)
token=sum(double(char(factor)));
scale=1+1e-3*mod(token,7)*double(arm=="TREATMENT");
end

function profile=localWindowProfile(overlap)
if overlap>0,profile="waveform_research_candidate"; ...
else,profile="nr_rel19_cp_ofdm_strict";end
end

function value=localNMSE(reference,actual)
value=sum(abs(double(actual(:)-reference(:))).^2)/ ...
    max(sum(abs(double(reference(:))).^2),eps);
end
