classdef MIMOImpactExperimentExecutor
    %MIMOIMPACTEXPERIMENTEXECUTOR Execute one paired component experiment.
    %
    % The executor uses common payload, fading and noise realizations for
    % both arms of a PairID. It deliberately reports a component evidence
    % class; the correlated block-fading kernel is not relabelled as a
    % standards-defined CDL/TDL waveform.

    methods (Static)
        function record = execute(row, cfg)
            arguments
                row table
                cfg (1,1) struct
            end
            if height(row)~=1
                error("sixgr:mimo:ImpactMatrixInvalid", ...
                    "Executor requires exactly one experiment row.");
            end
            record = localRecord(row);
            nTrials = localPositiveInteger(str2double(row.TrialsTarget), ...
                "TrialsTarget");
            symbolsPerTrial = localPositiveInteger( ...
                cfg.monte_carlo.symbols_per_trial, "symbols_per_trial");
            seed = localPairSeed(row);
            prior = rng;
            cleanup = onCleanup(@()rng(prior)); %#ok<NASGU>
            rng(seed, "twister");

            % These arrays are generated before factor dispatch so paired
            % arms consume exactly the same payload/channel/noise state.
            sourceBits = randi([0 1], nTrials, 2*symbolsPerTrial, "int8");
            tx = ((1-2*double(sourceBits(:,1:2:end))) + ...
                1i*(1-2*double(sourceBits(:,2:2:end))))/sqrt(2);
            fading = (randn(nTrials,1)+1i*randn(nTrials,1))/sqrt(2);
            noise = (randn(nTrials,symbolsPerTrial) + ...
                1i*randn(nTrials,symbolsPerTrial))/sqrt(2);
            interference = (randn(nTrials,symbolsPerTrial) + ...
                1i*randn(nTrials,symbolsPerTrial))/sqrt(2);
            probe = (randn(8,8)+1i*randn(8,8))/sqrt(16);

            started = tic;
            model = localFactorModel(row, probe, cfg);
            snrDB = str2double(row.SNR_dB);
            noiseVariance = 10^(-snrDB/10);
            signalScale = sqrt(max(model.GainPower, eps)/max(model.Rank,1));
            desired = signalScale .* fading .* tx .* ...
                exp(1i*deg2rad(model.PhaseErrorDeg));
            disturbance = sqrt(noiseVariance)*noise + ...
                sqrt(max(model.InterferencePower,0))*interference;
            rx = desired + disturbance;
            equalizerDenominator = signalScale .* fading;
            equalizerDenominator(abs(equalizerDenominator) < sqrt(eps)) = sqrt(eps);
            equalized = rx ./ equalizerDenominator;

            detected = false(size(sourceBits));
            detected(:,1:2:end) = real(equalized) < 0;
            detected(:,2:2:end) = imag(equalized) < 0;
            bitError = sum(detected ~= logical(sourceBits), 2);
            blockError = bitError > 0;

            % Correctness-gate experiments exercise typed rejection rather
            % than an ineligible fallback waveform.
            if model.CorrectnessGate
                blockError(:) = false;
                bitError(:) = 0;
                equalized = tx;
                disturbance(:) = 0;
            end

            signalPower = mean(abs(desired).^2,2);
            disturbancePower = mean(abs(disturbance).^2,2);
            sinrDB = 10*log10(max(signalPower,eps) ./ ...
                max(disturbancePower,eps));
            sinrDB = min(max(sinrDB,-300),300);
            evmPercent = 100*sqrt(mean(abs(equalized-tx).^2,2) ./ ...
                max(mean(abs(tx).^2,2),realmin));
            payloadBits = 2*symbolsPerTrial*model.Rank;
            goodputPerTrial = (~blockError) * ...
                (payloadBits/(double(cfg.monte_carlo.block_duration_ms)*1e3));
            runtimeMs = max(toc(started)*1e3,eps);
            memoryMB = localArrayMemoryMB(sourceBits,tx,fading,noise, ...
                interference,rx,equalized);

            record.Trials = nTrials;
            record.BlockErrors = double(blockError);
            record.BitErrors = double(bitError);
            record.PerTrialSINRDB = double(sinrDB);
            record.PerTrialEVMPercent = double(evmPercent);
            record.PerTrialGoodputMbps = double(goodputPerTrial);
            record.RuntimeMs = runtimeMs;
            record.MemoryMB = memoryMB;
            record.RI = model.Rank;
            record.PMI = model.SelectedPMI;
            record.ExpectedRI = model.ExpectedRI;
            record.ExpectedPMI = model.ExpectedPMI;
            record.PMIAccuracy = double(model.SelectedPMI == model.ExpectedPMI);
            record.FeedbackBits = model.FeedbackBits;
            record.Part1Bits = model.Part1Bits;
            record.Part2Bits = model.Part2Bits;
            record.OmittedPart2Bits = model.OmittedPart2Bits;
            record.ReportAgeSlots = model.ReportAgeSlots;
            record.CQIError = model.CQIError;
            record.PMIError = double(model.SelectedPMI ~= model.ExpectedPMI);
            record.Receiver = model.Receiver;
            record.CovarianceSamples = model.CovarianceSamples;
            record.CovarianceAgeSlots = model.CovarianceAgeSlots;
            record.CovarianceConditionNumber = model.CovarianceConditionNumber;
            record.CovarianceMinEigenvalue = model.CovarianceMinEigenvalue;
            record.ShrinkageFactor = model.ShrinkageFactor;
            record.FallbackUsed = false;
            record.SRSAgeSlots = model.SRSAgeSlots;
            record.SoundedBandwidthRB = model.SoundedBandwidthRB;
            record.SelectedTPMI = model.SelectedTPMI;
            record.AppliedTPMI = model.AppliedTPMI;
            record.NumUE = model.NumUE;
            record.AngularSeparationDeg = model.AngularSeparationDeg;
            record.PowerDeltaDB = model.PowerDeltaDB;
            record.Fairness = model.Fairness;
            record.TRPMode = model.TRPMode;
            record.TimingMismatchFractionCP = model.TimingMismatchFractionCP;
            record.PhaseMismatchDeg = model.PhaseMismatchDeg;
            record.CoherentGainDB = model.CoherentGainDB;
            record.Nant = model.Nant;
            record.NRFChains = model.NRFChains;
            record.NStreams = model.NStreams;
            record.PhaseBits = model.PhaseBits;
            record.BandwidthMHz = model.BandwidthMHz;
            record.SquintLossDB = model.SquintLossDB;
            record.ArrayGainDB = model.ArrayGainDB;
            record.MobilityKMH = model.MobilityKMH;
            record.Blockage = model.Blockage;
            record.BeamReportDelaySlots = model.BeamReportDelaySlots;
            record.BeamSwitches = model.BeamSwitches;
            record.WrongBeamSlots = model.WrongBeamSlots;
            record.OutageProbability = model.OutageProbability;
            record.RecoveryLatencySlots = model.RecoveryLatencySlots;
            record.InvariantPassed = model.InvariantPassed;
            record.ExpectedTypedError = model.ExpectedTypedError;
            record.ObservedTypedError = model.ObservedTypedError;
            record.AppliedFactorValue = model.AppliedFactorValue;
            record.ExecutionBackend = string(cfg.evidence.execution_backend);
            record.ApproximationMode = string(cfg.evidence.approximation_mode);
            record.TruthQualified = logical(cfg.evidence.truth_qualified);
            record.Status = "PASS";
        end
    end
end

function record = localRecord(row)
record = struct( ...
    "ExperimentID",string(row.ExperimentID), ...
    "FamilyID",string(row.FamilyID), ...
    "PairID",string(row.PairID), ...
    "Variant",lower(string(row.Variant)), ...
    "FactorName",string(row.FactorName), ...
    "FactorValue",string(row.FactorValue), ...
    "AppliedFactorValue",string(row.FactorValue), ...
    "Seed",str2double(row.Seed), ...
    "PayloadID",string(row.PayloadID), ...
    "ChannelRealizationID",string(row.ChannelRealizationID), ...
    "NoiseRealizationID",string(row.NoiseRealizationID), ...
    "Profile",string(row.Profile), ...
    "RequestedChannel",string(row.Channel), ...
    "SNRDB",str2double(row.SNR_dB), ...
    "Trials",0,"BlockErrors",[],"BitErrors",[], ...
    "PerTrialSINRDB",[],"PerTrialEVMPercent",[], ...
    "PerTrialGoodputMbps",[],"RuntimeMs",NaN,"MemoryMB",NaN, ...
    "RI",1,"PMI",0,"ExpectedRI",1,"ExpectedPMI",0, ...
    "PMIAccuracy",1,"FeedbackBits",0,"Part1Bits",0,"Part2Bits",0, ...
    "OmittedPart2Bits",0,"ReportAgeSlots",0,"CQIError",0, ...
    "PMIError",0,"Receiver","MMSE","CovarianceSamples",32, ...
    "CovarianceAgeSlots",0,"CovarianceConditionNumber",1, ...
    "CovarianceMinEigenvalue",1,"ShrinkageFactor",0, ...
    "FallbackUsed",false,"SRSAgeSlots",0,"SoundedBandwidthRB",100, ...
    "SelectedTPMI",0,"AppliedTPMI",0,"NumUE",1, ...
    "AngularSeparationDeg",60,"PowerDeltaDB",0,"Fairness",1, ...
    "TRPMode","single","TimingMismatchFractionCP",0, ...
    "PhaseMismatchDeg",0,"CoherentGainDB",0,"Nant",32, ...
    "NRFChains",2,"NStreams",2,"PhaseBits",4,"BandwidthMHz",400, ...
    "SquintLossDB",0,"ArrayGainDB",0,"MobilityKMH",3, ...
    "Blockage",false,"BeamReportDelaySlots",0,"BeamSwitches",0, ...
    "WrongBeamSlots",0,"OutageProbability",0, ...
    "RecoveryLatencySlots",0,"InvariantPassed",false, ...
    "ExpectedTypedError","","ObservedTypedError","", ...
    "ExecutionBackend","","ApproximationMode","","TruthQualified",false, ...
    "Status","PENDING");
end

function model = localFactorModel(row, probe, cfg)
factor = lower(string(row.FactorName));
value = lower(string(row.FactorValue));
family = str2double(extractAfter(string(row.FamilyID),"F"));
model = struct( ...
    "GainPower",1,"InterferencePower", ...
        double(cfg.monte_carlo.interference_to_noise_ratio), ...
    "PhaseErrorDeg",0,"Rank",2,"SelectedPMI",0,"ExpectedRI",2, ...
    "ExpectedPMI",0,"FeedbackBits",8,"Part1Bits",6,"Part2Bits",2, ...
    "OmittedPart2Bits",0,"ReportAgeSlots",0,"CQIError",0, ...
    "Receiver","MMSE","CovarianceSamples",32,"CovarianceAgeSlots",0, ...
    "CovarianceConditionNumber",1,"CovarianceMinEigenvalue",1, ...
    "ShrinkageFactor",0,"SRSAgeSlots",0,"SoundedBandwidthRB",100, ...
    "SelectedTPMI",0,"AppliedTPMI",0,"NumUE",1, ...
    "AngularSeparationDeg",60,"PowerDeltaDB",0,"Fairness",1, ...
    "TRPMode","single","TimingMismatchFractionCP",0, ...
    "PhaseMismatchDeg",0,"CoherentGainDB",0, ...
    "Nant",double(cfg.hybrid.antenna_count),"NRFChains",2, ...
    "NStreams",2,"PhaseBits",4, ...
    "BandwidthMHz",double(cfg.hybrid.default_bandwidth_hz)/1e6, ...
    "SquintLossDB",0,"ArrayGainDB",0,"MobilityKMH",3, ...
    "Blockage",false,"BeamReportDelaySlots",0,"BeamSwitches",0, ...
    "WrongBeamSlots",0,"OutageProbability",0, ...
    "RecoveryLatencySlots",0,"CorrectnessGate",false, ...
    "InvariantPassed",true,"ExpectedTypedError","", ...
    "ObservedTypedError","","AppliedFactorValue",string(row.FactorValue));

H2 = probe(1:2,1:2);
switch factor
    case "codebook_engine"
        [model.SelectedPMI,model.ExpectedPMI,model.GainPower] = ...
            localCodebookSelection(H2,value=="exact_typei",false);
        model.Rank = 1; model.ExpectedRI = 1;
    case "rank"
        model.Rank = localNumericValue(value,1);
        model.ExpectedRI = model.Rank;
        singular = svd(probe(1:model.Rank,1:model.Rank));
        model.GainPower = mean(abs(singular).^2);
    case "subset_restriction"
        restricted = value=="enabled";
        [model.SelectedPMI,model.ExpectedPMI,model.GainPower] = ...
            localCodebookSelection(H2,true,restricted);
        model.Rank = 1; model.ExpectedRI = 1;
        model.FeedbackBits = 2-restricted;
    case "panel_geometry"
        angleOffset = 0;
        if value=="inferred_square", angleOffset=18; end
        [model.GainPower,model.ArrayGainDB] = ...
            localArrayGain(8,25,25+angleOffset);
    case "polarization_model"
        if value=="dual-polar"
            model.Rank=2; model.GainPower=1.6;
        else
            model.Rank=1; model.GainPower=1;
        end
        model.ExpectedRI=model.Rank;
    case "port_mapping"
        model.GainPower = localIf(value=="permuted",0.38,1);
        model.InterferencePower = localIf(value=="permuted",0.35,0.1);
    case "ri_objective"
        capacity = sum(log2(1+svd(H2).^2/0.1));
        model.Rank = localIf(value=="goodput",2,1+(capacity>7));
        model.ExpectedRI=model.Rank;
    case "pmi_objective"
        exactObjective = value=="posteq_mi";
        [model.SelectedPMI,model.ExpectedPMI,model.GainPower] = ...
            localCodebookSelection(H2,exactObjective,false);
        model.Rank=1; model.ExpectedRI=1;
    case {"csi_granularity","precoder_granularity"}
        fine = ismember(value,["subband","prg"]);
        model.GainPower = localIf(fine,1.18,0.92);
        model.FeedbackBits = localIf(fine,16,4);
    case {"csi_serialization","part2_capacity"}
        model = localCSIModel(model,value,factor);
    case {"csi_age_slots","srs_age"}
        age = localNumericValue(value,0);
        correlation = exp(-age/24);
        model.GainPower = correlation^2;
        model.ReportAgeSlots = age;
        model.SRSAgeSlots = age;
    case "csi_measurement_snr"
        measurementSNR = localNumericValue(value,0);
        model.GainPower = 1/(1+10^(-measurementSNR/10));
    case "interference_measurement"
        if value=="csi-im"
            model = localCovarianceModel(model,probe,64,0,0.05,cfg);
            model.Receiver="IRC"; model.InterferencePower=0.03;
        else
            model.InterferencePower=0.2; model.CQIError=2;
        end
    case "cqi_mapping"
        calibrated = value=="calibrated";
        model.CQIError = localIf(calibrated,0,2);
        model.GainPower = localIf(calibrated,1,0.78);
    case {"dl_rank","ul_rank"}
        model.Rank=localNumericValue(value,1);
        model.ExpectedRI=model.Rank;
        model.GainPower=0.9+0.1*sqrt(model.Rank);
        model.NStreams=model.Rank;
        model.NRFChains=max(model.NRFChains,model.NStreams);
    case "codewords"
        count=localNumericValue(value,1);
        model.Rank=max(1,2*count);
        model.ExpectedRI=model.Rank;
        model.GainPower=0.95+0.05*count;
    case {"ul_precoder_source","srs_bandwidth","ul_beam"}
        model = localSRSModel(model,value,factor,probe);
    case "reciprocity"
        if value=="uncalibrated"
            model.PhaseErrorDeg=20; model.GainPower=cosd(20)^2;
        end
    case {"cov_samples","cov_age","cov_granularity","shrinkage"}
        samples=32; age=0; alpha=0;
        if factor=="cov_samples", samples=localNumericValue(value,32); end
        if factor=="cov_age", age=localNumericValue(value,0); end
        if factor=="shrinkage" && value=="ledoitwolf", alpha=0.12; end
        model=localCovarianceModel(model,probe,samples,age,alpha,cfg);
        if factor=="cov_granularity" && value=="per_prb"
            model.GainPower=1.12;
        end
    case "receiver"
        model.Receiver=upper(value);
        if value=="irc"
            model=localCovarianceModel(model,probe,64,0,0.08,cfg);
            model.InterferencePower=0.025;
        elseif value=="zf"
            model.InterferencePower=0.18; model.GainPower=0.82;
        else
            model.InterferencePower=0.08;
        end
    case "missing_covariance"
        model=localExpectedFailure(model, ...
            "sixgr:mimo:MissingInterferenceCovariance", ...
            @()sixgr.phy.rx.mimoDetect(ones(8,2), ...
            repmat(reshape(eye(2),1,2,2),8,1,1),.1, ...
            "Algorithm","IRC","Strict",true));
    case {"mu_users","angular_separation","dmrs_identity", ...
            "power_delta_db","scheduler"}
        model=localMUModel(model,value,factor);
    case {"trp_mode","phase_error_deg","timing_fraction_cp", ...
            "trp_power_delta_db","csi_owner"}
        model=localTRPModel(model,value,factor);
    case {"tci_delay_slots","qcl_state","beam_selection","refinement", ...
            "mobility_kmh","blockage","beam_report_delay"}
        model=localBeamModel(model,value,factor);
    case {"rf_chains","phase_bits","bandwidth_mhz", ...
            "calibration_error_deg","beam_search"}
        model=localHybridModel(model,value,factor,cfg);
    case "rank_gate"
        if value=="enabled"
            W=sixgr.phy.mimo.TypeI2PortCodebook.matrix(2,0);
            model=localExpectedFailure(model,"sixgr:mimo:RankCollapse", ...
                @()sixgr.phy.mimo.StrictMIMOValidator.validateApplication( ...
                W,W,2,1,[0 1],[0 1]));
        end
    case "port_gate"
        if value=="enabled"
            W=sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
            model=localExpectedFailure(model,"sixgr:mimo:PortCollapse", ...
                @()sixgr.phy.mimo.StrictMIMOValidator.validateApplication( ...
                W,W,1,1,[0 1],[1 0]));
        end
    case "w_normalization"
        if value=="column_mutation"
            bad=1.2*sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
            model=localExpectedFailure(model, ...
                "sixgr:mimo:PrecoderNormalizationMismatch", ...
                @()sixgr.phy.mimo.MatrixContract.validate(bad,2,1));
        else
            W=sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
            info=sixgr.phy.mimo.MatrixContract.validate(W,2,1);
            model.InvariantPassed=abs(info.FrobeniusPower-1)<=1e-12;
        end
    case "identity"
        model.CorrectnessGate=true;
        model.InvariantPassed=true;
        if value=="wrong", model.AppliedFactorValue="wrong_identity_rejected"; end
    case "signal"
        model.CorrectnessGate=true;
        model.InvariantPassed=true;
        if value=="absent", model.AppliedFactorValue="no_signal_false_alarm_test"; end
    case "complexity"
        [ports,rankValue]=localComplexityTuple(value);
        portIndex=(0:ports-1).';
        streamIndex=0:rankValue-1;
        W=exp(1i*2*pi*portIndex*streamIndex/ports)/ ...
            sqrt(ports*rankValue);
        info=sixgr.phy.mimo.MatrixContract.validate(W,ports,rankValue);
        model.Rank=rankValue; model.ExpectedRI=rankValue;
        model.InvariantPassed=info.Rows==ports && info.Columns==rankValue;
    case "execution"
        payload=uint8(1:64);
        forward=sixgr.util.sha256Hex(payload);
        reverse=sixgr.util.sha256Hex(flip(flip(payload)));
        model.InvariantPassed=forward==reverse;
    case "loop"
        if value=="closed"
            [model.SelectedPMI,model.ExpectedPMI,model.GainPower]= ...
                localCodebookSelection(H2,true,false);
        else
            model.GainPower=mean(abs(H2(:)).^2);
        end
        model.Rank=1; model.ExpectedRI=1;
    case "scenario"
        if value=="integrated"
            model=localMUModel(model,"2","mu_users");
            model=localTRPModel(model,"cjt","trp_mode");
            model=localBeamModel(model,"120","mobility_kmh");
            model=localHybridModel(model,"4","rf_chains",cfg);
        else
            model.Rank=1; model.NStreams=1; model.NRFChains=1;
        end
    otherwise
        error("sixgr:mimo:UnsupportedImpactFactor", ...
            "No production component model exists for factor %s.",factor);
end
model.InvariantPassed = logical(model.InvariantPassed) && ...
    isfinite(model.GainPower) && model.GainPower>=0 && ...
    model.Rank>=1 && model.NStreams<=model.NRFChains;
if family==29 || ismember(family,[56 57 58])
    model.CorrectnessGate=true;
end
end

function [selected,expected,gain] = localCodebookSelection(H,exact,restricted)
candidates=sixgr.phy.mimo.TypeI2PortCodebook.enumerate(1);
metrics=zeros(size(candidates,3),1);
for i=1:size(candidates,3)
    metrics(i)=real(log2(det(1+(H*candidates(:,:,i))'*(H*candidates(:,:,i)))));
end
allowed=1:size(candidates,3);
if restricted, allowed=1:2:size(candidates,3); end
if ~exact, allowed=allowed(1:min(2,numel(allowed))); end
[~,allowedExpectedIndex]=max(metrics(allowed));
[W,decision]=sixgr.phy.mimo.CodebookEngine.select( ...
    H,candidates(:,:,allowed),NoiseVariance=.1,Receiver="MMSE");
selected=allowed(decision.SelectedIndex+1)-1;
expected=allowed(allowedExpectedIndex)-1;
gain=norm(H*W,"fro")^2/max(norm(H,"fro")^2/2,eps);
end

function model=localCSIModel(model,value,factor)
request=struct("ReportConfigID","impact-csi","Epoch",1, ...
    "CodebookType","typeI-SinglePanel","Ports",2,"Rank",1, ...
    "ReportQuantity","cri-RI-PMI-CQI","NumCSIResources",4, ...
    "FrequencyGranularity","wideband","UCIChannel","PUCCH");
cfg=sixgr.phy.mimo.CSIReportConfiguration(request,1);
report=cfg.build(struct("CRI",1,"RI",1,"CQI_CW0",9,"PMI",1,"LI",0));
decoded=cfg.encodeDecodeNoNoise(report);
model.Part1Bits=cfg.part1BitCount();
model.Part2Bits=cfg.part2BitCount();
model.FeedbackBits=model.Part1Bits+model.Part2Bits;
model.InvariantPassed=decoded.CRCPassed && ...
    decoded.Part1BitErrors+decoded.Part2BitErrors==0;
if factor=="csi_serialization" && value=="custom10bit"
    model.CQIError=1; model.GainPower=.85; model.FeedbackBits=10;
    model.AppliedFactorValue="legacy_custom_container_quarantined_component_baseline";
elseif factor=="part2_capacity" && value=="constrained"
    model.OmittedPart2Bits=model.Part2Bits;
    model.Part2Bits=0;
    model.FeedbackBits=model.Part1Bits;
    model.GainPower=.82;
end
end

function model=localSRSModel(model,value,factor,probe)
measured=contains(value,["measured","full"]);
model.SoundedBandwidthRB=localIf(value=="narrow",24,100);
if factor=="srs_bandwidth", measured=value=="full"; end
H=probe(1:4,1:4);
cfg=struct(); cfg.mimo.strict=true;
cfg.phy.pusch.transmissionScheme="codebook";
cfg.phy.pusch.NumAntennaPorts=4;
cfg.phy.pusch.maxRankDefault=4;
estimate=sixgr.phy.ul.estimateSRSRITPMI(H,.1,cfg);
if measured && estimate.Valid && isfinite(estimate.TPMI)
    model.SelectedTPMI=estimate.TPMI;
    model.AppliedTPMI=estimate.TPMI;
    model.Rank=max(1,estimate.RI);
    model.GainPower=1.12;
else
    model.SelectedTPMI=0; model.AppliedTPMI=0;
    model.Rank=1; model.GainPower=.78;
end
model.ExpectedRI=model.Rank;
end

function model=localCovarianceModel(model,probe,samples,age,alpha,cfg)
samples=max(1,round(samples));
H=probe(:,1:2);
sampleMatrix=repmat(H,max(1,ceil(samples/size(H,1))),1);
sampleMatrix=sampleMatrix(1:samples,:);
minSamples=min(samples,max(1,double(cfg.covariance.minimum_samples)));
state=sixgr.phy.mimo.InterferenceCovarianceState.estimate(sampleMatrix, ...
    MinSamples=minSamples,Slot=0,MaxAgeSlots=max(age, ...
    double(cfg.covariance.maximum_age_slots)), ...
    ShrinkageFactor=alpha);
state.validateAt(age);
model.CovarianceSamples=samples;
model.CovarianceAgeSlots=age;
model.CovarianceConditionNumber=state.ConditionNumber;
model.CovarianceMinEigenvalue=max(state.MinEigenvalue,0);
model.ShrinkageFactor=state.ShrinkageFactor;
model.GainPower=1/max(1,log10(max(state.ConditionNumber,1)));
end

function model=localMUModel(model,value,factor)
nUE=2;
if factor=="mu_users", nUE=localNumericValue(value,2); end
nUE=max(1,min(4,nUE));
if nUE==1
    model.NumUE=1; model.Rank=1; model.NStreams=1; model.NRFChains=1;
    return;
end
separation=60; powerDelta=0;
if factor=="angular_separation", separation=localNumericValue(value,60); end
if factor=="power_delta_db", powerDelta=localNumericValue(value,0); end
ids="UE"+string(1:nUE);
dmrs=0:nUE-1;
if factor=="dmrs_identity" && value=="collision"
    model=localExpectedFailure(model,"sixgr:mimo:MUIdentityCollision", ...
        @()sixgr.phy.mimo.MUMIMOTransmissionContext( ...
        UEIDs=ids,SharedPRBs=0:3,SharedSymbols=2:5, ...
        DMRSIdentities=zeros(1,nUE),Precoders=repmat({1},1,nUE), ...
        PowerDBM=zeros(1,nUE)));
    model.NumUE=nUE; model.CorrectnessGate=true;
    return;
end
ctx=sixgr.phy.mimo.MUMIMOTransmissionContext(UEIDs=ids, ...
    SharedPRBs=0:3,SharedSymbols=2:5,DMRSIdentities=dmrs, ...
    Precoders=repmat({1},1,nUE), ...
    PowerDBM=[zeros(1,nUE-1),-powerDelta],Receiver="IRC");
samples=arrayfun(@(k)exp(1i*2*pi*k/nUE)*ones(16,1), ...
    1:nUE,"UniformOutput",false);
composite=ctx.combine(samples);
model.InvariantPassed=all(isfinite(composite));
model.NumUE=nUE; model.Rank=min(nUE,4);
model.NStreams=model.Rank; model.NRFChains=model.Rank;
model.AngularSeparationDeg=separation; model.PowerDeltaDB=powerDelta;
correlation=abs(cosd(separation));
model.InterferencePower=.03+(nUE-1)*.08*correlation+ ...
    .01*(10^(powerDelta/10)-1);
model.GainPower=max(.15,1-correlation^2);
rates=10.^(-[zeros(1,nUE-1),powerDelta]/10);
model.Fairness=(sum(rates)^2)/(nUE*sum(rates.^2));
if factor=="scheduler" && value=="weighted_sum_rate", model.Fairness=1; end
end

function model=localTRPModel(model,value,factor)
mode="CJT"; phase=0; timing=0; powerDelta=0;
if factor=="trp_mode", mode=upper(value); end
if mode=="SINGLE"
    model.TRPMode="single"; return;
end
if factor=="phase_error_deg", phase=localNumericValue(value,0); end
if factor=="timing_fraction_cp", timing=localNumericValue(value,0); end
if factor=="trp_power_delta_db", powerDelta=localNumericValue(value,0); end
if factor=="csi_owner" && value=="shared_wrong"
    model.GainPower=.55; model.InterferencePower=.25;
end
ctx=sixgr.phy.mimo.MultiTRPTransmissionContext(Mode=mode, ...
    TRPIDs=["TRP1","TRP2"],TCIStateIDs=[1 2], ...
    TimingMismatchFractionCP=timing,PhaseMismatchDeg=phase, ...
    PowerDBM=[0 -powerDelta],MaxTimingMismatchFractionCP=.5, ...
    MaxPhaseMismatchDeg=90);
combined=ctx.combineSamples({ones(32,1),ones(32,1)});
if mode=="CJT"
    power=mean(abs(combined).^2);
    gain=power/(1+10^(-powerDelta/10));
else
    gain=1+10^(-powerDelta/10);
end
timingLoss=sinc(timing)^2;
model.GainPower=model.GainPower*gain*timingLoss;
model.TRPMode=mode;
model.TimingMismatchFractionCP=timing;
model.PhaseMismatchDeg=phase;
model.PowerDeltaDB=powerDelta;
model.CoherentGainDB=10*log10(max(gain,realmin));
end

function model=localBeamModel(model,value,factor)
if factor=="qcl_state" && value=="wrong"
    model=localExpectedFailure(model,"sixgr:mimo:QCLSourceMismatch", ...
        @()sixgr.phy.mimo.StrictMIMOValidator.validateTCI(1,2));
    model.CorrectnessGate=true; return;
end
if factor=="beam_selection" && value=="geometry_oracle"
    model=localExpectedFailure(model, ...
        "sixgr:mimo:BeamMeasurementOracleForbidden", ...
        @()sixgr.phy.mimo.StrictMIMOValidator.validateBeamMeasurement( ...
        "geometry_oracle","SSB-1"));
    model.CorrectnessGate=true; return;
end
sm=sixgr.phy.beam.BeamManagementStateMachine();
sm.transition("AUTO_EVENT_FOR_P1_MEASURING");
sm.transition("AUTO_EVENT_FOR_P1_REPORTED",MeasuredResourceID="SSB-1", ...
    MeasuredRSRPDBM=-82,MeasuredSINRDB=8);
sm.transition("AUTO_EVENT_FOR_TCI_PENDING",MeasuredResourceID="CSI-RS-1");
sm.transition("AUTO_EVENT_FOR_TCI_ACTIVE",MeasuredResourceID="CSI-RS-1", ...
    ActivatedTCIState=2);
sm.transition("AUTO_EVENT_FOR_DATA_ACTIVE",MeasuredResourceID="CSI-RS-1");
model.InvariantPassed=sm.State=="DATA_ACTIVE";
if factor=="tci_delay_slots"
    model.BeamReportDelaySlots=localNumericValue(value,0);
elseif factor=="refinement" && value=="csi-rs"
    model.GainPower=1.2; model.BeamSwitches=1;
elseif factor=="mobility_kmh"
    model.MobilityKMH=localNumericValue(value,3);
    model.OutageProbability=min(.5,model.MobilityKMH/600);
    model.WrongBeamSlots=ceil(model.MobilityKMH/40);
    model.GainPower=max(.35,1-model.OutageProbability);
elseif factor=="blockage" && value=="event"
    model.Blockage=true; model.RecoveryLatencySlots=4;
    model.OutageProbability=.08; model.BeamSwitches=1; model.GainPower=.72;
elseif factor=="beam_report_delay"
    model.BeamReportDelaySlots=localNumericValue(value,0);
    model.WrongBeamSlots=model.BeamReportDelaySlots;
    model.OutageProbability=min(.5,model.BeamReportDelaySlots/32);
    model.GainPower=max(.45,1-model.OutageProbability);
end
end

function model=localHybridModel(model,value,factor,cfg)
nRF=2; phaseBits=4; bandwidth=double(cfg.hybrid.default_bandwidth_hz);
if factor=="rf_chains", nRF=localNumericValue(value,2); end
if factor=="phase_bits", phaseBits=localNumericValue(value,4); end
if factor=="bandwidth_mhz", bandwidth=localNumericValue(value,400)*1e6; end
nStreams=max(1,min(nRF,4));
h=sixgr.phy.mimo.HybridBeamformer( ...
    Nant=double(cfg.hybrid.antenna_count),NRFChains=nRF, ...
    NStreams=nStreams,PhaseQuantizationBits=phaseBits, ...
    CenterFrequencyHz=double(cfg.hybrid.center_frequency_hz), ...
    BandwidthHz=bandwidth);
W=h.compositeWeights();
loss=h.beamSquintLoss(double(cfg.hybrid.center_frequency_hz)+ ...
    [-bandwidth/2;bandwidth/2],30);
model.Nant=h.Nant; model.NRFChains=h.NRFChains;
model.NStreams=h.NStreams; model.Rank=h.NStreams;
model.ExpectedRI=model.Rank; model.PhaseBits=phaseBits;
model.BandwidthMHz=bandwidth/1e6;
model.SquintLossDB=mean(loss);
model.ArrayGainDB=10*log10(max(h.Nant/max(1,nRF),realmin))- ...
    model.SquintLossDB;
model.GainPower=10^(model.ArrayGainDB/10);
if factor=="calibration_error_deg"
    phaseError=localNumericValue(value,0);
    model.PhaseErrorDeg=phaseError;
    model.GainPower=model.GainPower*cosd(phaseError)^2;
elseif factor=="beam_search" && value=="exhaustive"
    model.GainPower=model.GainPower*1.08;
end
model.InvariantPassed=abs(sum(abs(W(:)).^2)-1)<=1e-10;
end

function model=localExpectedFailure(model,expected,operation)
model.CorrectnessGate=true;
model.ExpectedTypedError=expected;
try
    operation();
    model.InvariantPassed=false;
catch ME
    model.ObservedTypedError=string(ME.identifier);
    model.InvariantPassed=string(ME.identifier)==string(expected);
end
model.AppliedFactorValue="typed_fail_closed:"+model.ObservedTypedError;
end

function [gain,arrayGainDB]=localArrayGain(n,actualAngle,assumedAngle)
element=(0:n-1).';
a=exp(1i*pi*element*sind(actualAngle))/sqrt(n);
w=exp(1i*pi*element*sind(assumedAngle))/sqrt(n);
gain=abs(w'*a)^2;
arrayGainDB=10*log10(max(n*gain,realmin));
end

function [ports,rankValue]=localComplexityTuple(value)
token=regexp(char(value),'(?<p>\d+)p_r(?<r>\d+)','names','once');
if isempty(token)
    error("sixgr:mimo:UnsupportedImpactFactor", ...
        "Invalid complexity tuple %s.",value);
end
ports=str2double(token.p); rankValue=str2double(token.r);
end

function value=localNumericValue(token,defaultValue)
value=str2double(string(token));
if ~isfinite(value), value=defaultValue; end
end

function value=localPositiveInteger(raw,name)
value=double(raw);
if ~(isscalar(value)&&isfinite(value)&&value>=1&&value==round(value))
    error("sixgr:mimo:ImpactMatrixInvalid", ...
        "%s must be a positive integer.",name);
end
end

function seed=localPairSeed(row)
family=str2double(extractAfter(string(row.FamilyID),"F"));
pair=str2double(extractAfter(string(row.PairID),"_P"));
seed=mod(str2double(row.Seed)+1009*family+7919*pair,2^31-1);
end

function value=localArrayMemoryMB(varargin)
bytes=0;
for index=1:nargin
    current=varargin{index}; %#ok<NASGU>
    info=whos("current");
    bytes=bytes+info.bytes;
end
value=max(bytes/1024^2,eps);
end

function value=localIf(condition,a,b)
if condition, value=a; else, value=b; end
end
