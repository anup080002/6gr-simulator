classdef PUCCHReceiver
    %PUCCHRECEIVER Canonical receiver using schema/length context only.

    methods (Static)
        function rx = receive(waveform,carrier,assignment,reportContext,varargin)
            p = inputParser;
            addParameter(p,"NoiseVariance",0,@(x) isnumeric(x) && isscalar(x));
            addParameter(p,"NoiseVarianceDomain","sample", ...
                @(x) ischar(x)||isstring(x));
            addParameter(p,"ChannelProfile","AWGN",@(x) ischar(x)||isstring(x));
            addParameter(p,"DetectionThreshold",0.2,@(x) isnumeric(x)&&isscalar(x));
            parse(p,varargin{:});
            opt = p.Results;
            if ~isfinite(opt.NoiseVariance) || opt.NoiseVariance < 0
                error("sixgr:phy:pucch:InvalidNoiseVariance", ...
                    "PUCCH noise variance must be a finite nonnegative scalar.");
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
            [grid,ofdmInfo] = sixgr.phy.waveform.ofdmDemodulate( ...
                carrier,waveform);
            channel = upper(string(opt.ChannelProfile));
            sampleNoiseVariance = max(double(opt.NoiseVariance),eps);
            [nVar,noiseTransform] = ...
                sixgr.phy.waveform.convertNoiseVarianceToGridDomain( ...
                sampleNoiseVariance,ofdmInfo, ...
                "InputDomain",opt.NoiseVarianceDomain, ...
                "Source","pucch_receiver_argument");
            if channel == "AWGN"
                eq = nrExtractResources(indices,grid);
                hest = [];
            else
                if isempty(dmrs.Indices)
                    error("sixgr:phy:pucch:DMRSGenerationFailed", ...
                        "Fading-channel PUCCH reception requires DM-RS.");
                end
                [hest,estimatedNoise] = sixgr.phy.rx.channelEstimate( ...
                    carrier,grid,dmrs.Indices,dmrs.Symbols);
                if isempty(hest) || isscalar(hest)
                    error("sixgr:phy:pucch:DMRSGenerationFailed", ...
                        "Fading PUCCH requires a per-resource channel estimate.");
                end
                if isfinite(estimatedNoise) && estimatedNoise > 0
                    nVar = estimatedNoise;
                end
                [eq,~,~] = sixgr.phy.rx.equalizeMMSE( ...
                    grid,hest,nVar,"Indices",indices);
            end
            totalA = reportContext.Sequence1Length + ...
                reportContext.Sequence2Length;
            try
                [soft,constellation,metric] = nrPUCCHDecode( ...
                    carrier,pucch,totalA,eq,nVar, ...
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
            energyRatio = mean(abs(eq(:)).^2)/max(nVar,eps);
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
                "MeasuredSINR_dB",localSINR(eq,nVar), ...
                "EVMPercent",localEVM(constellation), ...
                "FailureReason",localFailure(decision.DTX), ...
                "ErrorID","","OraclePayloadBitsUsed",false, ...
                "AssignmentDigest",assignment.Digest, ...
                "ReportContextDigest",reportContext.Digest, ...
                "SampleNoiseVariance",sampleNoiseVariance, ...
                "GridNoiseVariance",nVar, ...
                "NoiseVarianceTransform",noiseTransform, ...
                "ChannelEstimate",hest,"OFDMInfo",ofdmInfo);
        end
    end
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

function value = localSINR(symbols,nVar)
value = 10*log10(max(mean(abs(symbols(:)).^2),eps)/max(nVar,eps));
end

function value = localEVM(symbols)
if isempty(symbols), value = 100; return; end
ideal = sign(real(symbols))+1i*sign(imag(symbols));
ideal = ideal/sqrt(2);
value = 100*sqrt(mean(abs(symbols(:)-ideal(:)).^2)/ ...
    max(mean(abs(ideal(:)).^2),eps));
end

function value = localFailure(dtx)
if dtx, value = "dtx"; else, value = ""; end
end
