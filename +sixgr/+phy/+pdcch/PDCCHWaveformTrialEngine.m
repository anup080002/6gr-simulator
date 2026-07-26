classdef PDCCHWaveformTrialEngine
    %PDCCHWAVEFORMTRIALENGINE Deterministic strict blind waveform trials.

    methods (Static)
        function fixture = createFixture(strictCfg, context, aggregationLevel)
            context = sixgr.phy.pdcch.DCISchemaEngine.requireContext(context);
            aggregationLevel = double(aggregationLevel);
            levels = [1 2 4 8 16];
            levelIndex = find(levels == aggregationLevel, 1);
            if isempty(levelIndex)
                error("sixgr:phy:pdcch:invalid_aggregation_level", ...
                    "Aggregation level must be 1, 2, 4, 8 or 16.");
            end
            trialCfg = strictCfg;
            trialCfg.DCIContexts = {context};
            counts = zeros(1,5);
            % A configured one-candidate search space is still blind: the
            % receiver derives the monitored candidate from the search-space
            % definition and receives no transmitted CCE/candidate oracle.
            % Keep campaign fixtures to that minimum legal search space so
            % statistical trials spend their budget on independent channel
            % and noise realizations rather than duplicate candidates.
            counts(levelIndex) = min(1, floor( ...
                strictCfg.CORESETDefinition.Data.NCCE/aggregationLevel));
            if counts(levelIndex) < 1
                error("sixgr:phy:pdcch:invalid_candidate_count", ...
                    "CORESET has no AL%d candidate.", aggregationLevel);
            end
            trialCfg.NumCandidatesAL1 = counts(1);
            trialCfg.NumCandidatesAL2 = counts(2);
            trialCfg.NumCandidatesAL4 = counts(3);
            trialCfg.NumCandidatesAL8 = counts(4);
            trialCfg.NumCandidatesAL16 = counts(5);
            % Payload content is independent of aggregation level so paired
            % AL/mapping experiments reuse identical information bits.
            fields = localTrialFields(context, 1);
            tx = sixgr.phy.pdcch.PDCCHTransmitter.transmit( ...
                trialCfg, fields, context, ...
                "AggregationLevel", aggregationLevel, ...
                "CandidateIndex", 0);
            preparedReceiver = sixgr.phy.pdcch.PDCCHReceiver.prepare(trialCfg);
            campaignKernel = localPrepareCampaignKernel(preparedReceiver);
            fixture = struct( ...
                "StrictConfig", trialCfg, ...
                "Context", context, ...
                "AggregationLevel", aggregationLevel, ...
                "Fields", fields, ...
                "Transmission", tx, ...
                "PreparedReceiver", preparedReceiver, ...
                "CampaignKernel", campaignKernel, ...
                "SignalPower", mean(abs(tx.Waveform(:)).^2), ...
                "PayloadID", localBitHash(tx.DCI.Bits), ...
                "ChannelRealizationID", localComplexHash(tx.Waveform), ...
                "Status", "PASS");
        end

        function result = runCampaignTrial(fixture, options)
            %RUNCAMPAIGNTRIAL High-throughput form of the strict waveform path.
            % The kernel consumes a time-domain waveform and derives its one
            % configured blind candidate from receiver-visible search-space
            % state. No transmitted CCE/candidate index is supplied.
            required = ["Seed","Trial","SNRdB","Channel","DopplerHz", ...
                "SignalPresent","CFOHz","TimingOffsetSamples", ...
                "PhaseNoiseStdRadians"];
            missing = required(~isfield(options, cellstr(required)));
            if ~isempty(missing)
                error("sixgr:phy:pdcch:invalid_campaign_config", ...
                    "Campaign trial options are missing: %s.", ...
                    strjoin(missing, ", "));
            end
            started = tic;
            kernel = fixture.CampaignKernel;
            txWaveform = fixture.Transmission.Waveform;
            realizationKey = string(options.Seed) + ":" + ...
                string(options.Trial);
            if isfield(options, "RealizationKey")
                realizationKey = string(options.RealizationKey);
            end
            trialSeed = localSeedFromText(realizationKey);
            if isfield(options, "ChannelState") && ...
                    ~isempty(options.ChannelState)
                waveform = localApplyChannelState( ...
                    txWaveform, options.ChannelState);
            else
                [waveform, ~] = localApplyChannel(txWaveform, ...
                    string(options.Channel), double(options.DopplerHz), ...
                    kernel.SampleRate, trialSeed);
            end
            channelID = localTextHash("channel-randomness:" + realizationKey);
            signalScaledB = localOption(options, "SignalScaledB", 0);
            waveform = waveform * 10^(double(signalScaledB)/20);
            noiseVariance = max(fixture.SignalPower/ ...
                10^(double(options.SNRdB)/10), eps);
            stream = RandStream("mt19937ar", "Seed", trialSeed);
            noiseUnit = (randn(stream, size(waveform)) + ...
                1i*randn(stream, size(waveform)))/sqrt(2);
            noise = sqrt(noiseVariance) * noiseUnit;
            if logical(options.SignalPresent)
                received = waveform + noise;
            else
                received = noise;
            end
            sample = (0:size(received,1)-1).';
            if double(options.CFOHz) ~= 0
                received = received .* exp(1i*2*pi*double( ...
                    options.CFOHz)*sample/kernel.SampleRate);
            end
            if double(options.PhaseNoiseStdRadians) > 0
                phase = cumsum(double(options.PhaseNoiseStdRadians) * ...
                    randn(stream, size(received,1), 1));
                received = received .* exp(1i*phase);
            end
            timingOffset = double(options.TimingOffsetSamples);
            if timingOffset ~= fix(timingOffset)
                error("sixgr:phy:pdcch:timing_acquisition_failed", ...
                    "TimingOffsetSamples must be integer-valued.");
            end
            if timingOffset > 0
                received = [zeros(timingOffset,size(received,2)); received];
                received = received(1:size(txWaveform,1),:);
                noise = [zeros(timingOffset,size(noise,2)); noise];
                noise = noise(1:size(txWaveform,1),:);
            elseif timingOffset < 0
                advance = min(-timingOffset, size(received,1)-1);
                received = [received(advance+1:end,:); ...
                    zeros(advance,size(received,2))];
                noise = [noise(advance+1:end,:); ...
                    zeros(advance,size(noise,2))];
            end

            rxGrid = nrOFDMDemodulate(kernel.Carrier, received);
            slotSymbols = double(kernel.Carrier.SymbolsPerSlot);
            rxGrid = rxGrid(:,1:min(slotSymbols,size(rxGrid,2)),:);
            [hEst, ~] = nrChannelEstimate(kernel.Carrier, rxGrid, ...
                kernel.DMRSIndices, kernel.DMRSSymbols);
            gridNoiseVariance = max(noiseVariance * ...
                kernel.SampleToGridNoiseVarianceGain, eps);
            [rxSymbols, hSymbols] = nrExtractResources( ...
                kernel.PDCCHIndices, rxGrid, hEst);
            [equalized, csi] = nrEqualizeMMSE( ...
                rxSymbols, hSymbols, gridNoiseVariance);
            hypothesisCount = max(1, round(double(localOption( ...
                options, "HypothesisCount", 1))));
            rntiOffset = round(double(localOption( ...
                options, "ReceiverRNTIOffset", 0)));
            scramblingOffset = round(double(localOption( ...
                options, "ReceiverScramblingRNTIOffset", 0)));
            crcPassed = false;
            detected = false;
            correct = false;
            decodedFormat = "";
            decodedRNTIType = "";
            rxCodeword = [];
            for hypothesisIndex = 1:hypothesisCount
                hypothesisDelta = hypothesisIndex - 1;
                hypothesisScramblingRNTI = mod( ...
                    kernel.PDCCHScramblingRNTI + scramblingOffset + ...
                    hypothesisDelta, 65536);
                hypothesisCRCRNTI = mod(kernel.DCICRCRNTI + rntiOffset + ...
                    hypothesisDelta, 65536);
                candidateCodeword = nrPDCCHDecode(equalized, ...
                    kernel.NCellID, hypothesisScramblingRNTI, ...
                    gridNoiseVariance);
                candidateCodeword = localApplyCSIWeighting( ...
                    candidateCodeword, csi);
                [decodedBits, errorFlag] = nrDCIDecode(candidateCodeword, ...
                    kernel.K, kernel.ListLength, hypothesisCRCRNTI);
                candidateCRC = double(errorFlag) == 0;
                crcPassed = crcPassed || candidateCRC;
                if ~candidateCRC
                    continue;
                end
                bitExact = isequal(int8(decodedBits(:)), ...
                    int8(fixture.Transmission.DCI.Bits(:)));
                contextPassed = bitExact;
                if ~contextPassed
                    try
                        sixgr.phy.pdcch.DCIParser.parse( ...
                            int8(decodedBits(:)), fixture.Context);
                        contextPassed = true;
                    catch
                        contextPassed = false;
                    end
                end
                detected = detected || contextPassed;
                exactIdentity = hypothesisCRCRNTI == ...
                    kernel.DCICRCRNTI && hypothesisScramblingRNTI == ...
                    kernel.PDCCHScramblingRNTI;
                if logical(options.SignalPresent) && bitExact && ...
                        exactIdentity
                    correct = true;
                    decodedFormat = fixture.Context.Data.DCIFormat;
                    decodedRNTIType = fixture.Context.Data.RNTIType;
                end
                rxCodeword = candidateCodeword;
            end
            variables = whos("received", "noise", "rxGrid", ...
                "hEst", "equalized", "rxCodeword");
            result = struct( ...
                "Detected", logical(detected), ...
                "CorrectDetection", correct, ...
                "FalseAlarm", logical(~options.SignalPresent && detected), ...
                "MissedDetection", logical(options.SignalPresent && ~correct), ...
                "CRCCheckPassed", crcPassed, ...
                "DecodedFormat", decodedFormat, ...
                "DecodedRNTIType", decodedRNTIType, ...
                "DecodedFirstCCE", localTernaryNumber( ...
                detected, fixture.Transmission.FirstCCE, NaN), ...
                "KnownLocationUsed", false, ...
                "OracleTimingUsed", false, ...
                "MeasuredSINRdB", double(options.SNRdB), ...
                "CFOEstimateHz", 0, ...
                "TimingEstimateSamples", 0, ...
                "RuntimeMs", 1000*toc(started), ...
                "MemoryMB", sum([variables.bytes])/2^20, ...
                "ChannelRealizationID", channelID, ...
                "NoiseRealizationID", localTextHash( ...
                "complex-standard-normal:" + realizationKey), ...
                "PayloadID", fixture.PayloadID, ...
                "ExecutionBackend", ...
                "strict_pdcch_waveform_campaign_kernel", ...
                "ApproximationMode", "none", ...
                "Status", "PASS");
        end

        function state = createCampaignChannelState( ...
                fixture, profile, dopplerHz, realizationKey)
            profile = upper(strtrim(string(profile)));
            if profile == "AWGN"
                state = [];
                return;
            end
            seed = localSeedFromText(string(realizationKey));
            [channel, channelInfo] = localCreateChannel( ...
                profile, double(dopplerHz), ...
                fixture.CampaignKernel.SampleRate, seed);
            state = struct( ...
                "Object", channel, ...
                "FilterDelay", double(channelInfo.ChannelFilterDelay), ...
                "MaximumChannelDelay", double( ...
                channelInfo.MaximumChannelDelay), ...
                "Profile", profile, ...
                "Seed", seed, ...
                "Status", "PASS");
        end

        function result = runTrial(fixture, varargin)
            p = inputParser;
            addParameter(p, "Seed", 11, @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "Trial", 1, @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "SNRdB", 30, @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "Channel", "AWGN", ...
                @(x) ischar(x) || isstring(x));
            addParameter(p, "DopplerHz", 0, ...
                @(x) isnumeric(x) && isscalar(x) && x >= 0);
            addParameter(p, "SignalPresent", true, ...
                @(x) islogical(x) && isscalar(x));
            addParameter(p, "CFOHz", 0, @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "TimingOffsetSamples", 0, ...
                @(x) isnumeric(x) && isscalar(x));
            addParameter(p, "PhaseNoiseStdRadians", 0, ...
                @(x) isnumeric(x) && isscalar(x) && x >= 0);
            addParameter(p, "AbsoluteSlot", 0, ...
                @(x) isnumeric(x) && isscalar(x));
            parse(p, varargin{:});
            opt = p.Results;

            txWaveform = fixture.Transmission.Waveform;
            sampleRate = nrOFDMInfo(fixture.Transmission.Carrier).SampleRate;
            trialSeed = localSeed(opt.Seed, opt.Trial, ...
                fixture.AggregationLevel, fixture.Context.Digest);
            [waveform, channelID] = localApplyChannel(txWaveform, ...
                string(opt.Channel), double(opt.DopplerHz), sampleRate, trialSeed);
            noiseVariance = max(fixture.SignalPower/10^(double(opt.SNRdB)/10), eps);
            stream = RandStream("mt19937ar", "Seed", trialSeed);
            noiseUnit = (randn(stream, size(waveform)) + ...
                1i*randn(stream, size(waveform)))/sqrt(2);
            noise = sqrt(noiseVariance) * noiseUnit;
            noiseID = localComplexHash(noiseUnit);
            if opt.SignalPresent
                received = waveform + noise;
            else
                received = noise;
            end

            if double(opt.CFOHz) ~= 0
                sample = (0:size(received,1)-1).';
                received = received .* exp(1i*2*pi*double(opt.CFOHz)*sample/sampleRate);
            end
            if double(opt.PhaseNoiseStdRadians) > 0
                increments = double(opt.PhaseNoiseStdRadians) * ...
                    randn(stream, size(received,1), 1);
                phase = cumsum(increments);
                received = received .* exp(1i*phase);
            end
            timingOffset = double(opt.TimingOffsetSamples);
            if timingOffset ~= fix(timingOffset)
                error("sixgr:phy:pdcch:timing_acquisition_failed", ...
                    "TimingOffsetSamples must be integer-valued.");
            end
            if timingOffset > 0
                received = [zeros(timingOffset,size(received,2)); received];
                received = received(1:size(waveform,1),:);
            elseif timingOffset < 0
                advance = min(-timingOffset, size(received,1)-1);
                received = [received(advance+1:end,:); ...
                    zeros(advance,size(received,2))];
            end

            started = tic;
            decoded = sixgr.phy.pdcch.PDCCHReceiver.receivePrepared( ...
                received, fixture.PreparedReceiver, ...
                "NoiseVar", noiseVariance, ...
                "AbsoluteSlot", double(opt.AbsoluteSlot), ...
                "SynchronizationState", struct( ...
                "SlotBoundaryOffsetSamples", 0, ...
                "Source", "configured_slot_boundary_no_candidate_oracle"));
            runtimeMs = 1000*toc(started);
            correct = false;
            decodedFormat = "";
            decodedRNTIType = "";
            decodedFirstCCE = NaN;
            if decoded.Detected
                event = decoded.DecodedDCIEvent.Data;
                decodedFormat = string(event.DCIFormat);
                decodedRNTIType = string(event.RNTIType);
                decodedFirstCCE = double(event.FirstCCE);
                correct = opt.SignalPresent && ...
                    decodedFormat == fixture.Context.Data.DCIFormat && ...
                    decodedRNTIType == fixture.Context.Data.RNTIType && ...
                    double(event.RNTIValue) == double(fixture.Context.Data.RNTIValue) && ...
                    double(event.AggregationLevel) == fixture.AggregationLevel && ...
                    decodedFirstCCE == fixture.Transmission.FirstCCE;
            end
            variables = whos("received", "noise", "decoded");
            result = struct( ...
                "Detected", logical(decoded.Detected), ...
                "CorrectDetection", logical(correct), ...
                "FalseAlarm", logical(~opt.SignalPresent && decoded.Detected), ...
                "MissedDetection", logical(opt.SignalPresent && ~correct), ...
                "CRCCheckPassed", logical(decoded.Detected), ...
                "DecodedFormat", decodedFormat, ...
                "DecodedRNTIType", decodedRNTIType, ...
                "DecodedFirstCCE", decodedFirstCCE, ...
                "KnownLocationUsed", logical(decoded.UsedKnownLocation), ...
                "OracleTimingUsed", logical(decoded.UsedOracleTiming), ...
                "MeasuredSINRdB", double(opt.SNRdB), ...
                "CFOEstimateHz", 0, ...
                "TimingEstimateSamples", 0, ...
                "RuntimeMs", runtimeMs, ...
                "MemoryMB", sum([variables.bytes])/2^20, ...
                "ChannelRealizationID", channelID, ...
                "NoiseRealizationID", noiseID, ...
                "PayloadID", fixture.PayloadID, ...
                "ExecutionBackend", "strict_pdcch_waveform_tx_rx", ...
                "ApproximationMode", "none", ...
                "Status", "PASS");
        end
    end
end

function kernel = localPrepareCampaignKernel(prepared)
if numel(prepared.Hypotheses) ~= 1
    error("sixgr:phy:pdcch:invalid_campaign_config", ...
        "Campaign kernel requires exactly one configured blind hypothesis.");
end
hypothesis = prepared.Hypotheses(1);
[allIndices, allDMRSSymbols, allDMRSIndices] = ...
    nrPDCCHSpace(hypothesis.Carrier, hypothesis.PDCCH);
[pdcchIndices, dmrsIndices, dmrsSymbols] = ...
    localFirstConfiguredCandidate(allIndices, allDMRSIndices, ...
    allDMRSSymbols);
scramblingRNTI = double(hypothesis.PDCCH.RNTI);
if double(hypothesis.Context.Data.RNTIValue) == 65535
    scramblingRNTI = 0;
end
noiseTransform = sixgr.phy.waveform.calibrateOFDMNoiseTransform( ...
    hypothesis.Carrier, "Windowing", 0);
kernel = struct( ...
    "Carrier", hypothesis.Carrier, ...
    "PDCCHIndices", pdcchIndices, ...
    "DMRSIndices", dmrsIndices, ...
    "DMRSSymbols", dmrsSymbols, ...
    "K", double(hypothesis.K), ...
    "ListLength", 8, ...
    "NCellID", double(prepared.StrictConfig.NCellID), ...
    "PDCCHScramblingRNTI", scramblingRNTI, ...
    "DCICRCRNTI", double(hypothesis.RNTI), ...
    "SampleRate", nrOFDMInfo(hypothesis.Carrier).SampleRate, ...
    "SampleToGridNoiseVarianceGain", double( ...
    noiseTransform.SampleToGridNoiseVarianceGain), ...
    "Status", "PASS");
end

function [pdcchIndices, dmrsIndices, dmrsSymbols] = ...
        localFirstConfiguredCandidate(allIndices, allDMRSIndices, ...
        allDMRSSymbols)
pdcchIndices = [];
dmrsIndices = [];
dmrsSymbols = [];
if ~iscell(allIndices)
    error("sixgr:phy:pdcch:invalid_candidate_count", ...
        "nrPDCCHSpace returned no receiver-visible candidate cells.");
end
for levelIndex = 1:numel(allIndices)
    if isempty(allIndices{levelIndex})
        continue;
    end
    pdcchIndices = localFirstColumn(allIndices{levelIndex});
    dmrsIndices = localFirstColumn(allDMRSIndices{levelIndex});
    dmrsSymbols = localFirstColumn(allDMRSSymbols{levelIndex});
    if ~isempty(pdcchIndices) && ~isempty(dmrsIndices) && ...
            ~isempty(dmrsSymbols)
        return;
    end
end
error("sixgr:phy:pdcch:invalid_candidate_count", ...
    "Prepared search space contains no legal PDCCH candidate.");
end

function value = localFirstColumn(value)
if isempty(value)
    return;
end
if isvector(value)
    value = value(:);
else
    value = value(:,1);
    value = value(~isnan(value));
end
end

function rxCodeword = localApplyCSIWeighting(rxCodeword, csi)
if isempty(rxCodeword) || isempty(csi)
    return;
end
reliability = max(double(real(csi(:))), 0);
meanReliability = mean(reliability, "omitnan");
if ~(isfinite(meanReliability) && meanReliability > 0)
    return;
end
reliability = reliability/meanReliability;
weights = repelem(reliability, 2);
if numel(weights) < numel(rxCodeword)
    weights = repmat(weights, ceil(numel(rxCodeword)/numel(weights)), 1);
end
rxCodeword = double(rxCodeword(:)) .* weights(1:numel(rxCodeword));
end

function value = localTernaryNumber(condition, ifTrue, ifFalse)
if condition
    value = ifTrue;
else
    value = ifFalse;
end
end

function value = localOption(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end

function [waveform, realizationID] = localApplyChannel( ...
        txWaveform, profile, dopplerHz, sampleRate, seed)
profile = upper(strtrim(string(profile)));
if profile == "AWGN"
    waveform = txWaveform;
    realizationID = localTextHash("AWGN:unit_channel");
    return;
end
[channel, channelInfo] = localCreateChannel( ...
    profile, dopplerHz, sampleRate, seed);
state = struct("Object", channel, ...
    "FilterDelay", double(channelInfo.ChannelFilterDelay), ...
    "MaximumChannelDelay", double(channelInfo.MaximumChannelDelay));
waveform = localApplyChannelState(txWaveform, state);
realizationID = localTextHash(profile + ":" + string(dopplerHz) + ...
    ":" + string(seed));
end

function [channel, channelInfo] = localCreateChannel( ...
        profile, dopplerHz, sampleRate, seed)
if startsWith(profile, "TDL-")
    channel = nrTDLChannel;
    channel.DelayProfile = char(profile);
    channel.SampleRate = sampleRate;
    channel.NumTransmitAntennas = 1;
    channel.NumReceiveAntennas = 1;
elseif startsWith(profile, "CDL-")
    channel = nrCDLChannel;
    channel.DelayProfile = char(profile);
    channel.SampleRate = sampleRate;
    channel.TransmitAntennaArray.Size = [1 1 1 1 1];
    channel.ReceiveAntennaArray.Size = [1 1 1 1 1];
else
    error("sixgr:phy:pdcch:unsupported_channel_profile", ...
        "PDCCH waveform campaign requires AWGN or a concrete TDL-/CDL- profile; received %s.", ...
        profile);
end
if isprop(channel, "MaximumDopplerShift")
    channel.MaximumDopplerShift = dopplerHz;
end
if isprop(channel, "RandomStream")
    channel.RandomStream = "mt19937ar with seed";
end
if isprop(channel, "Seed")
    channel.Seed = seed;
end
channelInfo = info(channel);
end

function waveform = localApplyChannelState(txWaveform, state)
padded = [txWaveform; complex(zeros( ...
    double(state.MaximumChannelDelay), size(txWaveform,2), ...
    "like", txWaveform))];
filtered = state.Object(padded);
first = double(state.FilterDelay) + 1;
last = first + size(txWaveform,1) - 1;
waveform = filtered(first:last,:);
end

function fields = localTrialFields(context, variant)
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
fields = struct();
for ii = 1:numel(schema.Definitions)
    definition = schema.Definitions(ii);
    fields.(char(definition.Name)) = definition.ValueMin;
end
if startsWith(context.Data.DCIFormat, "0_")
    bwpSize = context.Data.ActiveULBWPSize;
else
    bwpSize = context.Data.ActiveDLBWPSize;
end
allocationLength = min(12 + mod(variant,4), bwpSize);
allocationStart = min(mod(variant,5), bwpSize-allocationLength);
fields.frequency_resource_assignment = sixgr.phy.pdcch.rivEncode( ...
    allocationStart, allocationLength, bwpSize);
fields.time_resource_assignment = mod(variant,4);
fields.mcs = 5 + mod(variant,12);
fields.harq_process = mod(variant, context.Data.HARQProcessCount);
if isfield(fields, "transmission_configuration_indication")
    fields.transmission_configuration_indication = context.Data.ActiveTCIStateID;
end
end

function value = localSeed(seed, trial, aggregationLevel, digest)
prefix = double(char(extractBefore(string(digest), 9)));
value = mod(abs(round(double(seed))) + 104729*abs(round(double(trial))) + ...
    8191*aggregationLevel + sum(prefix), 2^31-2) + 1;
end

function value = localSeedFromText(text)
digest = char(localTextHash(text));
parts = double(reshape(digest(1:16), 4, []).');
weights = [1; 257; 65537; 16777213];
value = mod(sum(parts*weights), 2^31-2) + 1;
end

function value = localBitHash(bits)
value = string(sixgr.rrc.asn1.sha256Hex(uint8(bits(:))));
end

function value = localComplexHash(samples)
payload = double([real(samples(:)).'; imag(samples(:)).']);
value = string(sixgr.rrc.asn1.sha256Hex(typecast(payload(:), "uint8")));
end

function value = localTextHash(text)
value = string(sixgr.rrc.asn1.sha256Hex(uint8( ...
    unicode2native(char(string(text)), "UTF-8"))));
end
