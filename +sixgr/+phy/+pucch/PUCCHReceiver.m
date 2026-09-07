classdef PUCCHReceiver
    %PUCCHRECEIVER Canonical receiver using schema/length context only.

    methods (Static)
        function rx = receive(waveform,carrier,assignment,reportContext,varargin)
            p = inputParser;
            addParameter(p,"NoiseVariance",0,@(x) isnumeric(x) && isscalar(x));
            addParameter(p,"NoiseVarianceDomain","sample", ...
                @(x) ischar(x)||isstring(x));
            addParameter(p,"NoiseVarianceMode","provided", ...
                @(x) isscalar(string(x)) && any(string(x)==["provided","received_dmrs_estimate"]));
            addParameter(p,"ChannelProfile","AWGN",@(x) ischar(x)||isstring(x));
            addParameter(p,"DetectionThreshold",0.2,@(x) isnumeric(x)&&isscalar(x));
            addParameter(p,"InterferenceCovariance",[], ...
                @(x) isempty(x)||isnumeric(x));
            addParameter(p,"InterferenceCovarianceSource","", ...
                @(x) ischar(x)||isstring(x));
            parse(p,varargin{:});
            opt = p.Results;
            receiverPipelineTic = tic;
            estimateNoise=string(opt.NoiseVarianceMode)=="received_dmrs_estimate";
            if (~estimateNoise && (~isreal(opt.NoiseVariance) || ~isfinite(opt.NoiseVariance) || opt.NoiseVariance < 0)) || ...
                    (estimateNoise && (~isreal(opt.NoiseVariance) || ~isnan(opt.NoiseVariance)))
                error("sixgr:phy:pucch:InvalidNoiseVariance", ...
                    "Provide finite nonnegative variance, or NaN with explicit received_dmrs_estimate mode.");
            end
            if estimateNoise && ~isempty(opt.InterferenceCovariance)
                error("sixgr:phy:pucch:OverlappingDisturbanceAuthorities", ...
                    "The received DM-RS residual includes disturbance; do not add another interference covariance to it.");
            end
            if ~isa(reportContext,"sixgr.phy.pucch.UCIReportContext")
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "PUCCH RX requires a typed UCIReportContext.");
            end
            if ~isa(assignment,"sixgr.phy.pucch.PUCCHTransmissionAssignment")
                error("sixgr:phy:pucch:WrongResource", ...
                    "PUCCH RX requires a typed assignment.");
            end
            if assignment.ReportID ~= reportContext.ReportID || ...
                    assignment.ConfigurationEpoch ~= ...
                    reportContext.ConfigurationEpoch
                error("sixgr:phy:pucch:StaleConfiguration", ...
                    "Receiver report and assignment contexts differ.");
            end
            pucch = assignment.Resource.toolboxConfig();
            [indices,~] = nrPUCCHIndices(carrier,pucch);
            dmrs = sixgr.phy.pucch.PUCCHDMRS.generate( ...
                carrier,assignment.Resource);
            ofdmTic = tic;
            [grid,ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate( ...
                carrier,waveform);
            ofdmDemodulationLatency_ms = 1e3 .* toc(ofdmTic);
            channel = upper(string(opt.ChannelProfile));
            sampleNoiseVariance = double(opt.NoiseVariance);
            if estimateNoise
                if isempty(dmrs.Indices)
                    error("sixgr:phy:pucch:NoiseReferenceUnavailable", ...
                        "PUCCH Format 0 has no DM-RS; collect independent received disturbance evidence.");
                end
                nVar=NaN;
                noiseSource="received_pucch_dmrs_noise_plus_residual_estimate";
                noiseTransform=struct('InputDomain','grid', ...
                    'OutputDomain','resource_grid_pre_equalization', ...
                    'TransformSource',noiseSource,'SampleToGridNoiseVarianceGain',NaN);
            else
                [nVar,noiseTransform] = ...
                    sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
                    sampleNoiseVariance,ofdmInfo, ...
                    "InputDomain",opt.NoiseVarianceDomain, ...
                    "Source","pucch_receiver_argument");
                noiseSource="provided_variance_converted_to_resource_grid";
            end
            [rintGrid,effectiveScalarNVar,covarianceInfo] = ...
                localInterferenceCovariance(opt.InterferenceCovariance, ...
                opt.InterferenceCovarianceSource,noiseTransform,nVar, ...
                max(1,size(grid,3)));
            gridDisturbanceVariance = effectiveScalarNVar;
            equalizerInfo = struct();
            channelEstimationLatency_ms = NaN;
            equalizationLatency_ms = NaN;
            format0Noncoherent = assignment.Format == 0 && isempty(dmrs.Indices);
            % AWGN propagation does not imply unity TX power/RF gain or a
            % single receive branch. Formats with DM-RS must estimate their
            % effective channel and combine antennas before UCI decoding.
            if channel == "AWGN" && isempty(dmrs.Indices)
                eq = nrExtractResources(indices,grid);
                hest = [];
                channelEstimationMode = "awgn_direct_resource_extraction";
            elseif format0Noncoherent
                % PUCCH Format 0 intentionally has no DM-RS.  Its cyclic-
                % shift/sequence detector operates noncoherently on the
                % allocated resource, including on a fading channel.  Do
                % not manufacture a scalar/full-grid channel estimate and
                % do not reject a standards-valid Format-0 transmission for
                % the absence of a reference signal that does not exist.
                eq = nrExtractResources(indices,grid);
                hest = [];
                channelEstimationMode = "format0_noncoherent_sequence_detection";
            else
                if isempty(dmrs.Indices)
                    error("sixgr:phy:pucch:DMRSGenerationFailed", ...
                        "Fading-channel PUCCH Formats 1-4 require their configured DM-RS resources.");
                end
                channelEstimationTic = tic;
                [hest,estimatedNoise] = sixgr.phy.rx.channelEstimate( ...
                    carrier,grid,dmrs.Indices,dmrs.Symbols);
                channelEstimationLatency_ms = 1e3 .* toc(channelEstimationTic);
                if isempty(hest) || isscalar(hest)
                    error("sixgr:phy:pucch:DMRSGenerationFailed", ...
                        "Fading PUCCH requires a per-resource channel estimate.");
                end
                if estimateNoise && ~(isreal(estimatedNoise) && isscalar(estimatedNoise) && ...
                        isfinite(estimatedNoise) && estimatedNoise > 0)
                    error("sixgr:phy:pucch:ReceivedNoiseEstimateUnavailable", ...
                        "Actual received DM-RS did not yield a usable disturbance estimate; no supplied-noise rescue.");
                end
                if (estimateNoise || isempty(rintGrid)) && isfinite(estimatedNoise) && estimatedNoise > 0
                    nVar = estimatedNoise;
                    noiseSource="received_pucch_dmrs_noise_plus_residual_estimate";
                end
                effectiveScalarNVar = localEffectiveScalarVariance( ...
                    nVar,rintGrid,max(1,size(grid,3)));
                eqArgs = {"Indices",indices};
                if ~isempty(rintGrid)
                    eqArgs = [eqArgs {"Rint",rintGrid+nVar*eye(size(rintGrid,1)), ...
                        "RIncludesNoise",true}]; %#ok<AGROW>
                end
                equalizationTic = tic;
                [eq,~,equalizerInfo] = sixgr.phy.rx.equalizeMMSE( ...
                    grid,hest,nVar,eqArgs{:});
                equalizationLatency_ms = 1e3 .* toc(equalizationTic);
                channelEstimationMode = "dmrs_per_resource_mmse_equalization";
            end
            totalA = reportContext.Sequence1Length + ...
                reportContext.Sequence2Length;
            gridDisturbanceVariance = localEffectiveScalarVariance( ...
                nVar,rintGrid,max(1,size(grid,3)));
            decodeNoiseVariance = localEqualizedNoiseVariance( ...
                equalizerInfo,gridDisturbanceVariance);
            decodeTic = tic;
            try
                [soft,constellation,metric] = nrPUCCHDecode( ...
                    carrier,pucch,totalA,eq,decodeNoiseVariance, ...
                    "DetectionThreshold",opt.DetectionThreshold);
            catch ME
                error("sixgr:phy:pucch:UCIDecodeFailed", ...
                    "PUCCH physical decode failed: %s",ME.message);
            end
            if assignment.Format <= 1
                decoded = localCellBits(soft);
                crcPassed = true;
            else
                decodedResult = sixgr.phy.pucch.UCIDecoder.decode(soft{1},totalA);
                decoded = decodedResult.Bits;
                crcPassed = decodedResult.CRCPassed;
            end
            decodeLatency_ms = 1e3 .* toc(decodeTic);
            energyRatio = mean(abs(eq(:)).^2)/max(decodeNoiseVariance,eps);
            energyMetric = max(0,(energyRatio-1)/(energyRatio+1));
            if assignment.Format <= 1 && isscalar(metric) && isfinite(metric)
                detectionMetric = min(double(metric),double(energyMetric));
            else
                detectionMetric = double(energyMetric);
            end
            decision = sixgr.phy.pucch.PUCCHDetector.decide( ...
                assignment.Format,detectionMetric, ...
                opt.DetectionThreshold,decoded);
            if decision.DTX
                decoded = int8(zeros(0,1));
            end
            [sequence1,sequence2] = localSplit(decoded, ...
                reportContext.Sequence1Length,reportContext.Sequence2Length);
            measuredSINR_dB = localMeasuredSINR( ...
                eq,equalizerInfo,gridDisturbanceVariance,channel, ...
                format0Noncoherent);
            evmApplicable = assignment.Format >= 2;
            rx = struct( ...
                "ReceiverUsable",~decision.DTX, ...
                "DetectionAttempted",true,"DTX",decision.DTX, ...
                "DetectionMetric",decision.DetectionMetric, ...
                "DetectionThreshold",decision.DetectionThreshold, ...
                "DecodedSequence1",sequence1, ...
                "DecodedSequence2",sequence2, ...
                "DecodedFields",localFields(sequence1,sequence2,reportContext), ...
                "CRCPassed",crcPassed,"WrongRNTI",false, ...
                "WrongResource",false,"WrongSequence",false, ...
                "MeasuredSINR_dB",measuredSINR_dB, ...
                "MeasuredSINRApplicable",isfinite(measuredSINR_dB), ...
                "MeasuredSINRSource",localMeasuredSINRSource( ...
                    equalizerInfo,channel,format0Noncoherent), ...
                "EVMPercent",localEVM(constellation,evmApplicable), ...
                "EVMApplicable",logical(evmApplicable), ...
                "FailureReason",localFailure(decision.DTX), ...
                "ErrorID","","OraclePayloadBitsUsed",false, ...
                "AssignmentDigest",assignment.Digest, ...
                "ReportContextDigest",reportContext.Digest, ...
                "SampleNoiseVariance",sampleNoiseVariance, ...
                "GridNoiseVariance",nVar, ...
                "GridNoiseVarianceSource",noiseSource, ...
                "GridNoiseVarianceValueRole","receiver_disturbance_variance_for_equalization_and_decode", ...
                "DecodeNoiseInterferenceVariance",decodeNoiseVariance, ...
                "NoiseVarianceTransform",noiseTransform, ...
                "InterferenceCovariance",rintGrid, ...
                "InterferenceCovarianceAvailable",~isempty(rintGrid), ...
                "InterferenceCovarianceSource",char(string(covarianceInfo.Source)), ...
                "InterferenceCovarianceDomain",char(string(covarianceInfo.Domain)), ...
                "EffectiveGridNoiseInterferenceVariance",double(gridDisturbanceVariance), ...
                "EqualizedDecodeNoiseInterferenceVariance",double(decodeNoiseVariance), ...
                "EqualizerInfo",equalizerInfo, ...
                "ChannelEstimate",hest,"OFDMInfo",ofdmInfo, ...
                "ChannelEstimateApplicable",logical(~isempty(hest)), ...
                "NoncoherentSequenceDetection",logical(format0Noncoherent), ...
                "ChannelEstimationMode",char(channelEstimationMode), ...
                "OFDMDemodulationLatency_ms",double(ofdmDemodulationLatency_ms), ...
                "ChannelEstimationLatency_ms",double(channelEstimationLatency_ms), ...
                "EqualizationLatency_ms",double(equalizationLatency_ms), ...
                "DecodeLatency_ms",double(decodeLatency_ms), ...
                "ReceiverPipelineLatency_ms",1e3 .* toc(receiverPipelineTic), ...
                "ReceiverStageLatencySource", ...
                "matlab_tic_toc_canonical_pucch_receiver_stages");
        end
    end
end

function value = localEffectiveScalarVariance(nVar,Rgrid,nRx)
value = double(nVar);
if isempty(Rgrid)
    return;
end
value = value+max(0,real(trace(Rgrid))/max(1,double(nRx)));
if ~(isfinite(value) && value >= 0)
    error("sixgr:phy:pucch:InvalidEffectiveNoiseInterferenceVariance", ...
        ["PUCCH receiver noise-plus-interference variance must be a " ...
         "finite nonnegative scalar in the resource-grid domain."]);
end
end

function value = localEqualizedNoiseVariance(equalizerInfo,fallback)
value = double(fallback);
result = sixgr.util.structGet(equalizerInfo,"EqualizerResult",struct());
covariance = sixgr.util.structGet(result, ...
    "OutputNoiseInterferenceCovariance",[]);
if isempty(covariance)
    return;
end
if ndims(covariance) == 3
    count = min(size(covariance,2),size(covariance,3));
    samples = NaN(size(covariance,1)*count,1);
    cursor = 0;
    for layer = 1:count
        layerValues = real(reshape(covariance(:,layer,layer),[],1));
        samples(cursor+(1:numel(layerValues))) = layerValues;
        cursor = cursor+numel(layerValues);
    end
    samples = samples(1:cursor);
elseif ismatrix(covariance) && size(covariance,2) == 1
    samples = real(covariance(:,1));
elseif ismatrix(covariance) && size(covariance,1) == size(covariance,2)
    samples = real(diag(covariance));
else
    samples = [];
end
samples = samples(isfinite(samples) & samples >= 0);
if ~isempty(samples)
    value = double(mean(samples));
end
if ~(isfinite(value) && value >= 0)
    error("sixgr:phy:pucch:InvalidEqualizedNoiseVariance", ...
        "PUCCH equalized decode variance must be finite and nonnegative.");
end
end

function value = localMeasuredSINR(symbols,equalizerInfo,gridVariance,channel,format0)
value = NaN;
result = sixgr.util.structGet(equalizerInfo,"EqualizerResult",struct());
linear = double(sixgr.util.structGet(result,"PostEqSINRLinear",[]));
linear = linear(isfinite(linear) & linear >= 0);
if ~isempty(linear)
    value = 10*log10(max(mean(linear),eps));
    return;
end
if logical(format0) && upper(strtrim(string(channel))) ~= "AWGN"
    % Format 0 carries no DM-RS.  A fading-channel post-equalization SINR
    % is not observable without manufacturing a channel estimate.
    return;
end
power = mean(abs(symbols(:)).^2,"omitnan");
if isfinite(power) && isfinite(gridVariance) && gridVariance > 0
    signal = max(power-gridVariance,0);
    value = 10*log10(max(signal,eps)/gridVariance);
end
end

function source = localMeasuredSINRSource(equalizerInfo,channel,format0)
if isstruct(sixgr.util.structGet(equalizerInfo,"EqualizerResult",[])) && ...
        ~isempty(fieldnames(sixgr.util.structGet(equalizerInfo, ...
        "EqualizerResult",struct())))
    source = "pucch_equalizer_effective_response_and_output_covariance";
elseif logical(format0) && upper(strtrim(string(channel))) ~= "AWGN"
    source = "unavailable_format0_fading_without_dmrs";
else
    source = "awgn_resource_power_minus_calibrated_grid_noise";
end
end

function [Rgrid,effectiveNVar,info] = localInterferenceCovariance( ...
        Rsample,source,noiseTransform,nVar,nRx)
Rgrid = [];
effectiveNVar = double(nVar);
info = struct("Source","","Domain","not_available");
if isempty(Rsample)
    return;
end
Rsample = double(Rsample);
if ~(ismatrix(Rsample) && size(Rsample,1) == nRx && ...
        size(Rsample,2) == nRx && all(isfinite(Rsample),"all"))
    error("sixgr:phy:pucch:InterferenceCovarianceShapeMismatch", ...
        "PUCCH interference covariance must be a finite %d-by-%d receiver-sample matrix.", ...
        nRx,nRx);
end
gain = double(sixgr.util.structGet(noiseTransform, ...
    "SampleToGridNoiseVarianceGain",NaN));
if ~(isfinite(gain) && gain > 0)
    error("sixgr:phy:pucch:MissingInterferenceCovarianceTransform", ...
        "PUCCH interference covariance requires the calibrated sample-to-grid noise transform.");
end
Rgrid = (Rsample+Rsample')/2*gain;
effectiveNVar = localEffectiveScalarVariance(nVar,Rgrid,nRx);
info.Source = string(source);
if strlength(strtrim(info.Source)) == 0
    info.Source = "shared_slot_pucch_receiver_sample_contribution_covariance";
end
info.Domain = "resource_grid_pre_equalization";
end

function bits = localCellBits(input)
if iscell(input), bits = int8(input{1}(:)); else, bits = int8(input(:)); end
end

function [one,two] = localSplit(bits,n1,n2)
if numel(bits) < n1+n2
    one = int8(zeros(0,1)); two = int8(zeros(0,1)); return;
end
one = bits(1:n1);
two = bits(n1+(1:n2));
end

function value = localFields(one,two,context)
d = context.Data;
i = 0;
value = struct();
if numel(one) < d.HARQACKBits+d.SRBits+d.CSIPart1Bits
    value.HARQACK = int8(zeros(0,1));
    value.SR = int8(zeros(0,1));
    value.CSIPart1 = int8(zeros(0,1));
    value.CSIPart2 = int8(zeros(0,1));
    return;
end
value.HARQACK = one(i+(1:d.HARQACKBits)); i=i+d.HARQACKBits;
value.SR = one(i+(1:d.SRBits)); i=i+d.SRBits;
value.CSIPart1 = one(i+(1:d.CSIPart1Bits));
value.CSIPart2 = two(1:min(d.CSIPart2Bits,numel(two)));
end

function value = localEVM(symbols,applicable)
if ~logical(applicable) || isempty(symbols)
    value = NaN;
    return;
end
ideal = sign(real(symbols))+1i*sign(imag(symbols));
ideal = ideal/sqrt(2);
value = 100*sqrt(mean(abs(symbols(:)-ideal(:)).^2)/ ...
    max(mean(abs(ideal(:)).^2),eps));
end

function value = localFailure(dtx)
if dtx, value = "dtx"; else, value = ""; end
end
