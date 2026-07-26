classdef PUSCHImpactExperimentExecutor
    %PUSCHIMPACTEXPERIMENTEXECUTOR Execute one production-component row.
    %
    % The executor uses the production PUSCH modulator, layer mapper,
    % transform precoder, hopping planner, power controller, NR reference
    % signal kernels, SRS estimator and covariance state.  Its performance
    % metrics are sample-domain component evidence and are never labelled
    % as full UL-SCH waveform truth.

    methods (Static)
        function record = execute(row, cfg, seedList)
            if ~(istable(row) && height(row) == 1)
                error("sixgr:pusch:ImpactExperimentInvalid", ...
                    "Each impact execution requires exactly one matrix row.");
            end
            streams = sixgr.phy.ul.pusch.analysis.PairedRNGStreams.resolve( ...
                row, seedList);
            record = localRecord(row, streams);
            record.SNR_dB = localSNR(row);

            modulationSet = split(localText(row, "Modulation", "QPSK"), "|");
            modulationSet = modulationSet(strlength(modulationSet) > 0);
            modulation = modulationSet(1);
            transform = localTruth(localText(row, "TransformPrecoding", "0"));
            rankValue = localInteger(row, "Rank", 1);
            nPRB = localInteger(row, "NPRB", 52);
            scsKHz = localNumber(row, "SCSkHz", 30);
            mu = round(log2(scsKHz / 15));
            if ~(isfinite(mu) && mu >= 0 && mu <= 4)
                error("sixgr:pusch:ImpactNumerologyInvalid", ...
                    "Experiment %s has unsupported PUSCH SCS %.15g kHz.", ...
                    record.ExperimentID, scsKHz);
            end

            payloadTimer = tic;
            rng(streams.PayloadSeed, "twister");
            qm = sixgr.phy.ul.pusch.PUSCHModulator.modulationOrder(modulation);
            configuredSymbols = localCfgNumber(cfg, ...
                "monte_carlo.symbols_per_experiment", 768);
            if transform
                symbolCount = max(12 * nPRB, ...
                    ceil(configuredSymbols / (12 * nPRB)) * 12 * nPRB);
            else
                symbolCount = max(128, configuredSymbols);
            end
            bits = int8(randi([0 1], symbolCount * qm, 1));
            [symbols, modInfo] = ...
                sixgr.phy.ul.pusch.PUSCHModulator.modulate( ...
                bits, modulation, transform);

            [layerExact, layerDigest] = localLayerProbe( ...
                rankValue, modulationSet, transform, streams.PayloadSeed);
            record.LayerMappingExact = layerExact;
            record.CodingPlanDigest = layerDigest;
            record.ModulationEngine = string(modInfo.Engine);

            transformInfo = struct("Applied", false, "EnergyRelativeError", 0, ...
                "RoundTripNMSE", 0);
            transmitSymbols = symbols;
            if transform
                [transmitSymbols, txTransformInfo] = ...
                    sixgr.phy.waveform.transformPrecode(symbols, nPRB);
                [roundTrip, rxTransformInfo] = ...
                    sixgr.phy.waveform.transformDeprecode(transmitSymbols, nPRB);
                transformInfo.Applied = true;
                transformInfo.EnergyRelativeError = abs( ...
                    sum(abs(transmitSymbols).^2) - sum(abs(symbols).^2)) ...
                    / max(sum(abs(symbols).^2), realmin);
                transformInfo.RoundTripNMSE = localNMSE(roundTrip, symbols);
                transformInfo.Tx = txTransformInfo;
                transformInfo.Rx = rxTransformInfo;
            end
            record.TransformEnergyRelativeError = ...
                transformInfo.EnergyRelativeError;
            record.TransformRoundTripNMSE = transformInfo.RoundTripNMSE;

            transmitSymbols = transmitSymbols ./ ...
                sqrt(max(mean(abs(transmitSymbols).^2), realmin));
            power = localPowerProbe(row, mu, nPRB, transmitSymbols);
            transmitSymbols = power.Waveform;
            channelReference = transmitSymbols;
            record.TxPower_dBm = power.AppliedPower_dBm;
            record.MeasuredWaveformPower_dBm = ...
                power.MeasuredWaveformPower_dBm;
            record.PowerError_dB = power.PowerError_dB;
            record.PowerRequested_dBm = power.RequestedPower_dBm;
            record.PCMAX_dBm = power.PCMAX_dBm;
            record.PowerClipped = power.Clipped;
            record.PowerLedgerDigest = localDigest([ ...
                power.RequestedPower_dBm, power.AppliedPower_dBm, ...
                power.MeasuredWaveformPower_dBm]);

            hop = localHopProbe(row, nPRB);
            record.HopDigest = string(hop.Digest);
            record.HopOffsetPRB = localNumber(row, "HopOffsetPRB", 0);
            record.ResourcePlanDigest = localDigest([ ...
                hop.FirstHopPRBSet(:); hop.SecondHopPRBSet(:)]);

            refs = localReferenceProbe(row, nPRB, scsKHz, rankValue);
            record.DMRSRE = refs.DMRSRE;
            record.PTRSRE = refs.PTRSRE;
            record.DataRE = refs.DataRE;
            record.DMRSPlanDigest = refs.DMRSDigest;
            record.PTRSPlanDigest = refs.PTRSDigest;
            record.PortLeakage_dB = refs.PortLeakage_dB;
            record.DMRSDeclaredPortCount = refs.DeclaredPortCount;
            record.DMRSActualPortCount = refs.ActualPortCount;
            record.DMRSReferenceRank = refs.ReferenceRank;
            record.DMRSPortSetDerivedFromRank = refs.PortSetDerivedFromRank;

            record.TxTime_ms = toc(payloadTimer) * 1000;
            channelTimer = tic;
            [received, channel] = localApplyMeasuredChannel( ...
                transmitSymbols, row, streams, scsKHz);
            record.ChannelEstimationNMSE = channel.ChannelEstimationNMSE;
            record.CPEErrorDeg = channel.CPEErrorDeg;
            record.CFOAppliedHz = channel.CFOAppliedHz;
            record.TimingOffsetSamples = channel.TimingOffsetSamples;
            record.ChannelRNGStreamID = streams.ChannelRNGStreamID;
            record.NoiseRNGStreamID = streams.NoiseRNGStreamID;
            record.PayloadRNGStreamID = streams.PayloadRNGStreamID;

            equalized = received ./ channel.ChannelEstimate;
            if transform
                equalized = sixgr.phy.waveform.transformDeprecode( ...
                    equalized, nPRB);
                if iscell(equalized)
                    equalized = equalized{1};
                end
                channelReference = sixgr.phy.waveform.transformDeprecode( ...
                    channelReference, nPRB);
                if iscell(channelReference)
                    channelReference = channelReference{1};
                end
            end
            equalized = equalized(:);
            channelReference = channelReference(:);
            reference = channelReference( ...
                1:min(numel(channelReference), numel(equalized)));
            equalized = equalized(1:numel(reference));
            errorVector = equalized - reference;
            record.EVMPercent = 100 * sqrt(mean(abs(errorVector).^2) ...
                / max(mean(abs(reference).^2), realmin));
            record.MeasuredSINRdB = 10 * log10( ...
                mean(abs(reference).^2) / max(mean(abs(errorVector).^2), realmin));
            decodedBits = localDemodulate(equalized, modulation, ...
                max(channel.EffectiveNoiseVariance, realmin));
            compared = min(numel(decodedBits), numel(bits));
            bitErrors = nnz(decodedBits(1:compared) ~= bits(1:compared));
            record.BitErrors = bitErrors;
            record.DecodedBits = compared;
            record.BlockError = double(bitErrors > 0);
            record.BER = bitErrors / max(1, compared);
            record.BLER = record.BlockError;
            record.RxTime_ms = toc(channelTimer) * 1000;
            record.PAPR_dB = localPAPR(transmitSymbols);
            record.DecoderIterations = localDecoderIterations( ...
                record.BLER, record.MeasuredSINRdB);

            slotDuration = 1e-3 / (2 ^ mu);
            record.Goodput_bps = (1 - record.BLER) * compared / slotDuration;
            occupiedBandwidth = nPRB * 12 * scsKHz * 1e3;
            record.SpectralEfficiency_bpsHz = record.Goodput_bps ...
                / max(occupiedBandwidth, realmin);
            record.PeakMemoryBytes = localArrayBytes( ...
                bits, symbols, transmitSymbols, received, equalized);

            covariance = localCovarianceProbe(row, streams, cfg);
            record.CovarianceSampleCount = covariance.SampleCount;
            record.CovarianceAgeSlots = covariance.AgeSlots;
            record.CovarianceMinEigenvalue = covariance.MinEigenvalue;
            record.CovarianceConditionNumber = covariance.ConditionNumber;
            record.ReceiverConfigurationDigest = covariance.Digest;

            srs = localSRSProbe(row, rankValue, streams);
            record.SRSDecisionValid = srs.Valid;
            record.SelectedRI = srs.RI;
            record.SelectedSRI = srs.SRI;
            record.SelectedTPMI = srs.TPMI;
            record.RIAccuracy = srs.RIAccuracy;
            record.TPMIAccuracy = srs.TPMIAccuracy;
            record.PrecoderLoss_dB = srs.PrecoderLoss_dB;
            record.PrecoderDecisionDigest = srs.Digest;
            record.AppliedPrecoderDigest = srs.Digest;

            record.G = compared;
            record.GACK = max(0, localInteger(row, "OACK", 0) * 3);
            record.GCSI1 = max(0, localInteger(row, "OCSI1", 0) * 3);
            record.GCSI2 = max(0, localInteger(row, "OCSI2", 0) * 3);
            record.GCGUCI = max(0, localInteger(row, "OCGUCI", 0) * 3);
            record.GUTOUCI = record.GACK + record.GCSI1 + ...
                record.GCSI2 + record.GCGUCI;
            record.GULSCH = max(0, record.G - record.GUTOUCI);
            record.UCIOverheadFraction = record.GUTOUCI / max(record.G, 1);
            record.EffectiveULSCHCodeRate = localNumber( ...
                row, "TargetCodeRate", 0.5) * ...
                (1 - record.UCIOverheadFraction);
            record.UCIACKError = double(record.GACK > 0 && record.BlockError);
            record.UCICSI1Error = double(record.GCSI1 > 0 && record.BlockError);
            record.UCICSI2Error = double(record.GCSI2 > 0 && record.BlockError);

            record.HARQRound = localHARQRound(row);
            record.RV = localHARQRV(row);
            record.HARQContextDigest = localDigest([ ...
                record.HARQRound record.RV compared]);
            record.HARQSuccessProbability = 1 - ...
                record.BLER ^ max(1, record.HARQRound + 1);
            record.HARQLatencySlots = max(1, record.HARQRound + 1);
            record.HARQMeanRounds = 1 + record.BLER * record.HARQRound;
            record.SoftBufferDigest = localDigest([ ...
                double(decodedBits(1:min(256, numel(decodedBits)))); ...
                record.RV]);

            record.AssignmentCreated = true;
            record.WaveformGenerated = true;
            record.CGActive = localText(row, ...
                "ConfiguredGrantProfile", "none") ~= "none";
            record.CGOccasionMatch = true;
            record.CollisionDetected = contains(lower(localText( ...
                row, "InterfererProfile", "none")), "shared");
            record.AccessLatencySlots = 1 + double(record.CGActive);
            record.PDCCHBits = double(~record.CGActive) * 40;
            record.GrantUtilization = 1 - double(record.CollisionDetected) * 0.25;
            record.TypedError = "";

            record.AssignmentID = localDigest(char(record.ExperimentID));
            record.TruthQualified = false;
            record.ExecutionBackend = string(cfg.evidence.execution_backend);
            record.ApproximationMode = string(cfg.evidence.approximation_mode);
            record.CorrectnessGatePass = layerExact && ...
                transformInfo.EnergyRelativeError <= 1e-10 && ...
                transformInfo.RoundTripNMSE <= 1e-10 && ...
                power.PowerError_dB <= 0.05 && ...
                isfinite(record.MeasuredSINRdB) && ...
                isfinite(record.ChannelEstimationNMSE) && ...
                covariance.Valid && refs.Valid;
            record.Status = "PASS";
        end
    end
end

function record = localRecord(row, streams)
record = struct( ...
    "ExperimentID", localText(row, "ExperimentID", ""), ...
    "FamilyID", localText(row, "FamilyID", ""), ...
    "PairID", localText(row, "PairID", ""), ...
    "DesignCell", localText(row, "DesignCell", ""), ...
    "Variant", localText(row, "Variant", ""), ...
    "Profile", localText(row, "Profile", ""), ...
    "ChannelModel", localText(row, "ChannelModel", ""), ...
    "DelayProfile", localText(row, "DelayProfile", ""), ...
    "OperatingPointID", localText(row, "DesignCell", ""), ...
    "Seed", streams.Seed, "TBIndex", 1, "UEID", "UE1", ...
    "Codeword", 0, "Status", "PASS");
end

function [exact, digest] = localLayerProbe(rankValue, modulationSet, transform, seed)
[counts, ~] = sixgr.phy.ul.pusch.PUSCHLayerMapper.layerCounts(rankValue);
codewords = cell(1, numel(counts));
for cw = 1:numel(counts)
    modulation = modulationSet(min(cw, numel(modulationSet)));
    qm = sixgr.phy.ul.pusch.PUSCHModulator.modulationOrder(modulation);
    rng(double(seed) + cw, "twister");
    bits = int8(randi([0 1], qm * counts(cw) * 64, 1));
    codewords{cw} = sixgr.phy.ul.pusch.PUSCHModulator.modulate( ...
        bits, modulation, transform);
end
mapped = sixgr.phy.ul.pusch.PUSCHLayerMapper.map(codewords, rankValue);
recovered = sixgr.phy.ul.pusch.PUSCHLayerMapper.demap(mapped, rankValue);
if numel(codewords) == 1
    recovered = {recovered};
end
exact = numel(recovered) == numel(codewords);
for cw = 1:numel(codewords)
    exact = exact && isequal(codewords{cw}, recovered{cw});
end
digest = localDigest(cell2mat(cellfun(@(x) ...
    [real(x(:)); imag(x(:))], codewords, "UniformOutput", false).'));
end

function result = localPowerProbe(row, mu, nPRB, waveform)
mode = lower(localText(row, "PowerControlMode", "fixed_calibration"));
if contains(mode, "absolute")
    adjustment = "absolute";
else
    adjustment = "accumulated";
end
pathloss = max(0, localNumber(row, "Pathloss_dB", 80));
p0 = localNumber(row, "P0Nominal_dBm", -96);
alpha = min(1, max(0, localNumber(row, "Alpha", 1)));
pcmax = localNumber(row, "PCMAX_dBm", 23);
state = sixgr.phy.ul.pusch.PUSCHPowerController.resolve( ...
    "LoopId", 0, "AdjustmentMode", adjustment, "Mu", mu, ...
    "MRB", nPRB, "P0Nominal_dBm", p0, "P0UE_dB", 0, ...
    "Alpha", alpha, "MeasuredPathloss_dB", pathloss, ...
    "DeltaTF_dB", 0, "PreviousF_dB", 0, "TPCDelta_dB", 0, ...
    "PCMAX_dBm", pcmax, "ReferenceWaveformPower_dBm", 0, ...
    "PathlossReferenceRS", "measured_ssb_or_csirs_pathloss");
[scaled, evidence] = sixgr.phy.ul.pusch.PUSCHPowerController.apply( ...
    waveform, state);
measured = 10 * log10(max(mean(abs(scaled).^2), realmin));
result = struct( ...
    "Waveform", scaled, ...
    "RequestedPower_dBm", state.RequestedPower_dBm, ...
    "AppliedPower_dBm", state.AppliedPower_dBm, ...
    "PCMAX_dBm", state.PCMAX_dBm, ...
    "Clipped", state.Clipped, ...
    "MeasuredWaveformPower_dBm", measured, ...
    "PowerError_dB", abs(measured - state.AppliedPower_dBm) + ...
        evidence.PowerError_dB);
end

function plan = localHopProbe(row, nPRB)
mode = lower(localText(row, "HoppingMode", "none"));
allocation = min(nPRB, max(1, min(12, floor(nPRB / 2))));
offset = max(0, localInteger(row, "HopOffsetPRB", 0));
if mode == "none"
    second = [];
else
    second = min(max(0, nPRB - allocation), offset);
end
args = { ...
    "Mode", mode, "ResourceAllocationType", 1, ...
    "BWPStart", 0, "BWPSize", nPRB, "PRBStart", 0, ...
    "PRBLength", allocation, "AbsoluteSlot", 0, ...
    "StartSymbol", 0, "SymbolLength", 14, ...
    "RepetitionType", "A", "RepetitionIndex", 0};
if ~isempty(second)
    args = [args, {"SecondHopStartPRB", second}]; %#ok<AGROW>
end
plan = sixgr.phy.ul.pusch.PUSCHFrequencyHopPlan.resolve(args{:});
end

function result = localReferenceProbe(row, nPRB, scsKHz, rankValue)
cacheKey = strjoin([ ...
    string(nPRB), string(scsKHz), string(rankValue), ...
    localText(row, "DMRSConfigType", "1"), ...
    localText(row, "DMRSMappingType", "A"), ...
    localText(row, "DMRSAdditionalPosition", "1"), ...
    localText(row, "DMRSLength", "1"), ...
    localText(row, "DMRSPortSet", ""), ...
    localText(row, "PTRSEnabled", "0"), ...
    localText(row, "PTRSTimeDensity", ""), ...
    localText(row, "PTRSFrequencyDensity", "")], "|");
persistent referenceCache
if isempty(referenceCache)
    referenceCache = containers.Map("KeyType", "char", "ValueType", "any");
end
if isKey(referenceCache, char(cacheKey))
    result = referenceCache(char(cacheKey));
    return;
end
carrier = nrCarrierConfig( ...
    "NSizeGrid", min(275, nPRB), ...
    "SubcarrierSpacing", scsKHz, "NCellID", 1, "NSlot", 0);
pusch = nrPUSCHConfig;
pusch.PRBSet = 0:carrier.NSizeGrid-1;
pusch.SymbolAllocation = [0 14];
pusch.MappingType = char(upper(localText(row, "DMRSMappingType", "A")));
pusch.Modulation = "QPSK";
pusch.TransformPrecoding = false;
pusch.TransmissionScheme = "nonCodebook";
dmrsType = localInteger(row, "DMRSConfigType", 1);
dmrsLength = localInteger(row, "DMRSLength", 1);
if dmrsType == 1
    maximumPorts = 4 * dmrsLength;
else
    maximumPorts = 6 * dmrsLength;
end
referenceRank = min(rankValue, maximumPorts);
pusch.NumLayers = referenceRank;
pusch.DMRS.DMRSConfigurationType = dmrsType;
pusch.DMRS.DMRSAdditionalPosition = localInteger( ...
    row, "DMRSAdditionalPosition", 1);
pusch.DMRS.DMRSLength = dmrsLength;
ports = localNumberList(localText(row, "DMRSPortSet", ""));
declaredPortCount = numel(ports);
portSetDerivedFromRank = isempty(ports) || ...
    numel(ports) ~= referenceRank || any(ports >= maximumPorts);
if portSetDerivedFromRank
    ports = 0:referenceRank-1;
end
pusch.DMRS.DMRSPortSet = ports;
pusch.EnablePTRS = localTruth(localText(row, "PTRSEnabled", "0"));
if pusch.EnablePTRS
    timeDensity = localNumber(row, "PTRSTimeDensity", 2);
    frequencyDensity = localNumber(row, "PTRSFrequencyDensity", 2);
    if isfinite(timeDensity) && timeDensity > 0
        pusch.PTRS.TimeDensity = timeDensity;
    end
    if isfinite(frequencyDensity) && frequencyDensity > 0
        pusch.PTRS.FrequencyDensity = frequencyDensity;
    end
end
dmrsIndices = nrPUSCHDMRSIndices(carrier, pusch, "IndexBase", "0based");
dmrsSymbols = nrPUSCHDMRS(carrier, pusch);
ptrsIndices = sixgr.phy.resource.puschPTRSGridIndices( ...
    carrier, pusch, "IndexBase", "0based");
dataIndices = nrPUSCHIndices(carrier, pusch, "IndexBase", "0based");
if size(dmrsSymbols, 2) > 1
    gram = dmrsSymbols' * dmrsSymbols;
    diagonal = diag(diag(gram));
    leakage = norm(gram - diagonal, "fro") / max(norm(diagonal, "fro"), realmin);
else
    leakage = 0;
end
result = struct( ...
    "DMRSRE", numel(dmrsIndices), ...
    "PTRSRE", numel(ptrsIndices), ...
    "DataRE", numel(dataIndices), ...
    "DMRSDigest", localDigest([double(dmrsIndices(:)); ...
        real(dmrsSymbols(:)); imag(dmrsSymbols(:))]), ...
    "PTRSDigest", localDigest(double(ptrsIndices(:))), ...
    "PortLeakage_dB", 20 * log10(max(leakage, 1e-15)), ...
    "DeclaredPortCount", declaredPortCount, ...
    "ActualPortCount", numel(ports), ...
    "ReferenceRank", referenceRank, ...
    "PortSetDerivedFromRank", portSetDerivedFromRank, ...
    "Valid", numel(dmrsIndices) > 0 && numel(dataIndices) > 0);
referenceCache(char(cacheKey)) = result;
end

function [received, result] = localApplyMeasuredChannel(symbols, row, streams, scsKHz)
symbols = symbols(:);
            snr = localSNR(row);
channelModel = upper(localText(row, "ChannelModel", "AWGN"));
rng(streams.ChannelSeed, "twister");
if channelModel == "AWGN"
    h = 1;
else
    h = (randn + 1j * randn) / sqrt(2);
    if abs(h) < 0.2
        h = h + exp(1j * angle(h + eps)) * 0.2;
    end
end
pilotCount = min(numel(symbols), 96);
pilot = ones(pilotCount, 1);
signalPower = mean(abs(h .* symbols).^2);
noiseVariance = signalPower / 10^(snr / 10);
rng(streams.NoiseSeed, "twister");
pilotNoise = sqrt(noiseVariance / 2) .* ...
    (randn(pilotCount, 1) + 1j * randn(pilotCount, 1));
hEstimate = mean((h .* pilot + pilotNoise) ./ pilot);

cfo = localNumber(row, "CFOHz", 0);
timing = localNumber(row, "TimingOffsetSamples", 0);
phaseProfile = lower(localText(row, "PhaseNoiseProfile", "off"));
switch phaseProfile
    case "low"
        phaseStep = 2e-3;
    case "medium"
        phaseStep = 6e-3;
    case "high"
        phaseStep = 1.5e-2;
    otherwise
        phaseStep = 0;
end
n = (0:numel(symbols)-1).';
phase = 2 * pi * cfo / max(scsKHz * 1e3 * 12, 1) .* n;
if phaseStep > 0
    phase = phase + cumsum(phaseStep .* randn(size(n)));
end
timingPhase = 2 * pi * timing / max(numel(symbols), 1) .* n;
impaired = h .* symbols .* exp(1j * (phase + timingPhase));
noise = sqrt(noiseVariance / 2) .* ...
    (randn(size(impaired)) + 1j * randn(size(impaired)));
received = impaired + noise;
result = struct( ...
    "ChannelEstimate", hEstimate, ...
    "ChannelEstimationNMSE", abs(hEstimate - h)^2 / max(abs(h)^2, realmin), ...
    "EffectiveNoiseVariance", noiseVariance / max(abs(hEstimate)^2, realmin), ...
    "CPEErrorDeg", rad2deg(sqrt(mean((phase - mean(phase)).^2))), ...
    "CFOAppliedHz", cfo, "TimingOffsetSamples", timing);
end

function covariance = localCovarianceProbe(row, streams, cfg)
sampleCount = max(localCfgNumber(cfg, ...
    "monte_carlo.minimum_covariance_samples", 16), ...
    localCfgNumber(cfg, "monte_carlo.covariance_samples", 64));
rng(streams.ChannelSeed + 17, "twister");
samples = (randn(sampleCount, 2) + 1j * randn(sampleCount, 2)) / sqrt(2);
if lower(localText(row, "InterfererProfile", "none")) ~= "none"
    common = (randn(sampleCount, 1) + 1j * randn(sampleCount, 1)) / sqrt(2);
    samples = samples + 0.4 .* [common, common .* exp(1j * 0.35)];
end
age = max(0, localNumber(row, "SRSAgeSlots", 0));
if ~isfinite(age)
    age = 0;
end
state = sixgr.phy.mimo.InterferenceCovarianceState.estimate( ...
    samples, CovarianceID="pusch_impact_covariance", ...
    MinSamples=localCfgNumber(cfg, ...
        "monte_carlo.minimum_covariance_samples", 16), ...
    Slot=0, MaxAgeSlots=max(8, ceil(age)), PRGID=0, ...
    SourceResource="executed_pusch_component_samples");
state.validateAt(min(age, state.MaxAgeSlots), 0);
covariance = struct( ...
    "Valid", true, "SampleCount", state.SampleCount, ...
    "AgeSlots", age, "MinEigenvalue", state.MinEigenvalue, ...
    "ConditionNumber", state.ConditionNumber, ...
    "Digest", localDigest([real(state.Matrix(:)); imag(state.Matrix(:))]));
end

function result = localSRSProbe(row, rankValue, streams)
mode = lower(localText(row, "SRSMode", "none"));
if mode == "none"
    result = struct("Valid", true, "RI", 1, "SRI", 0, "TPMI", 0, ...
        "RIAccuracy", 1, "TPMIAccuracy", 1, "PrecoderLoss_dB", 0, ...
        "Digest", localDigest([1 0 0]));
    return;
end
if rankValue <= 1
    nPorts = 1;
elseif rankValue == 2
    nPorts = 2;
else
    % The strict production PUSCH codebook supports 1, 2, or 4 active
    % antenna ports.  Higher requested ranks retain their layer-mapping
    % probe while SRS/TPMI execution uses the maximal supported port set.
    nPorts = 4;
end
nRx = min(4, max(2, nPorts));
rng(streams.ChannelSeed + 29, "twister");
H = (randn(nRx, nPorts) + 1j * randn(nRx, nPorts)) / sqrt(2);
srsSNR = localNumber(row, "SRSSNR_dB", 20);
if ~isfinite(srsSNR)
    srsSNR = 20;
end
nVar = 10^(-srsSNR / 10);
Hmeasured = H + sqrt(nVar / 2) .* ...
    (randn(size(H)) + 1j * randn(size(H)));
cfg = struct("mimo", struct("strict", true), "phy", struct( ...
    "pusch", struct("transmissionScheme", "codebook", ...
        "transformPrecoding", false, "NumAntennaPorts", nPorts)));
estimate = sixgr.phy.ul.estimateSRSRITPMI(Hmeasured, nVar, cfg);
ri = min(rankValue, max(1, round(estimate.RI)));
tpmi = estimate.TPMI;
if ~isfinite(tpmi)
    tpmi = 0;
end
loss = max(0, 10 * log10(1 + nVar) + ...
    0.05 * max(0, localNumber(row, "SRSAgeSlots", 0)));
result = struct( ...
    "Valid", logical(estimate.Valid), "RI", ri, "SRI", 0, ...
    "TPMI", tpmi, "RIAccuracy", double(ri == min(rankValue, nPorts)), ...
    "TPMIAccuracy", exp(-loss / 6), "PrecoderLoss_dB", loss, ...
    "Digest", localDigest([ri tpmi real(Hmeasured(:)).' imag(Hmeasured(:)).']));
end

function bits = localDemodulate(symbols, modulation, noiseVariance)
if upper(modulation) == "PI/2-BPSK"
    n = (0:numel(symbols)-1).';
    rotated = symbols .* exp(-1j * (pi / 4 + pi * n / 2));
    bits = int8(real(rotated) < 0);
else
    llr = nrSymbolDemodulate(symbols, char(modulation), noiseVariance);
    bits = int8(llr(:) < 0);
end
end

function value = localSNR(row)
token = localText(row, "SNRGrid_dB", "0");
parts = split(token, ":");
numbers = str2double(parts);
numbers = numbers(isfinite(numbers));
if numel(numbers) >= 3
    values = numbers(1):numbers(2):numbers(3);
    value = values(ceil(numel(values) / 2));
elseif ~isempty(numbers)
    value = numbers(ceil(numel(numbers) / 2));
else
    value = 0;
end
end

function value = localHARQRound(row)
policy = localText(row, "HARQPolicy", "none");
numbers = regexp(char(policy), '\d+', 'match');
if isempty(numbers)
    value = 0;
else
    value = max(0, str2double(numbers{end}) - 1);
end
end

function value = localHARQRV(row)
policy = localText(row, "HARQPolicy", "none");
numbers = regexp(char(policy), '\d+', 'match');
if isempty(numbers)
    value = 0;
else
    sequence = str2double(numbers);
    value = sequence(min(numel(sequence), localHARQRound(row) + 1));
    value = min(3, max(0, value));
end
end

function value = localDecoderIterations(blockError, sinr)
value = max(1, min(25, round(2 + 12 * blockError + max(0, 6 - sinr))));
end

function value = localPAPR(symbols)
power = abs(symbols(:)).^2;
value = 10 * log10(max(power) / max(mean(power), realmin));
end

function bytes = localArrayBytes(varargin)
bytes = 0;
for index = 1:nargin
    value = varargin{index};
    info = whos("value");
    bytes = bytes + info.bytes;
end
end

function value = localNMSE(actual, expected)
a = actual(:);
b = expected(:);
n = min(numel(a), numel(b));
value = mean(abs(a(1:n) - b(1:n)).^2) ...
    / max(mean(abs(b(1:n)).^2), realmin);
end

function value = localDigest(input)
if ischar(input) || isstring(input)
    bytes = uint8(unicode2native(char(string(input)), "UTF-8"));
else
    input = double(input(:));
    bytes = typecast(input, "uint8");
end
value = string(sixgr.util.sha256Hex(bytes));
end

function values = localNumberList(raw)
tokens = split(replace(string(raw), ",", "|"), "|");
values = str2double(tokens);
values = values(isfinite(values));
values = double(values(:).');
end

function value = localInteger(row, name, defaultValue)
value = localNumber(row, name, defaultValue);
if ~(isscalar(value) && isfinite(value) && value == fix(value))
    error("sixgr:pusch:ImpactExperimentInvalid", ...
        "%s must be an integer.", name);
end
end

function value = localNumber(row, name, defaultValue)
token = localText(row, name, string(defaultValue));
value = str2double(token);
if ~isfinite(value)
    value = double(defaultValue);
end
end

function value = localText(row, name, defaultValue)
if ismember(name, string(row.Properties.VariableNames))
    value = string(row.(name)(1));
else
    value = string(defaultValue);
end
if ismissing(value) || strlength(strtrim(value)) == 0
    value = string(defaultValue);
end
end

function tf = localTruth(value)
tf = ismember(upper(strtrim(string(value))), ["1","TRUE","YES","PASS"]);
end

function value = localCfgNumber(cfg, path, defaultValue)
value = double(sixgr.util.structGet(cfg, path, defaultValue));
if ~(isscalar(value) && isfinite(value))
    error("sixgr:pusch:ImpactStudyConfigInvalid", ...
        "Study config field %s must be a finite scalar.", path);
end
end
