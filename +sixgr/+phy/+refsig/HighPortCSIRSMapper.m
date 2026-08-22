classdef HighPortCSIRSMapper
    %HIGHPORTCSIRSMAPPER Streamed localized OCC CSI-RS waveform kernel.
    %
    % Logical ports are processed one CDM group at a time.  Every group is
    % OFDM modulated, propagated through its measured MIMO channel, OFDM
    % demodulated and despread.  No requested port is silently discarded.

    methods (Static)
        function plan = plan(carrierCfg,portCount,cdmSize,family,density,fdtdSplit)
            arguments
                carrierCfg (1,1) struct
                portCount (1,1) double {mustBePositive,mustBeInteger}
                cdmSize (1,1) double {mustBePositive,mustBeInteger}
                family (1,1) string
                density (1,1) double {mustBePositive}
                fdtdSplit (1,1) string = ""
            end
            if portCount < cdmSize || mod(portCount,cdmSize) ~= 0
                error("sixgr:csi:InvalidHighPortGrouping", ...
                    "csirs.port_count=%d must be an integer multiple of cdm_size=%d.", ...
                    portCount,cdmSize);
            end
            if ~ismember(density,[1 .5 .25])
                error("sixgr:csi:InvalidCSIRSDensity", ...
                    "CSI-RS density must be one of [1, 0.5, 0.25].");
            end
            [fdOcc,tdOcc,splitLabel]=localFDTDSplit(fdtdSplit,cdmSize);
            persistent planCache
            if isempty(planCache)
                planCache=containers.Map("KeyType","char","ValueType","any");
            end
            cacheKey=char(strjoin(string([double(carrierCfg.n_rb), ...
                double(sixgr.util.structGet(carrierCfg,"scs_khz",30)), ...
                portCount,cdmSize,density])+"",":")+":"+lower(family)+":"+splitLabel);
            if isKey(planCache,cacheKey)
                plan=planCache(cacheKey);
                return;
            end
            C = sixgr.phy.refsig.OCCFactory.matrix(family,cdmSize);
            nSC = 12*double(carrierCfg.n_rb);
            nSym = 14;
            groupCount = portCount/cdmSize;
            frequencyStride=max(1,round(1/density));
            groupWidth=(fdOcc-1)*frequencyStride+1;
            frequencyBlocks=floor(nSC/groupWidth);
            timeBlocks=floor(nSym/tdOcc);
            capacity=frequencyBlocks*timeBlocks;
            if groupCount > capacity
                error("sixgr:csi:CSIRSPatternDoesNotFit", ...
                    ["Requested %d ports with CDM%d, %s and density %.2g requires %d " ...
                     "localized groups, but the configured %d-RB grid provides %d."], ...
                    portCount,cdmSize,splitLabel,density,groupCount, ...
                    carrierCfg.n_rb,capacity);
            end
            re=zeros(cdmSize,groupCount);
            for g=1:groupCount
                frequencyBlock=mod(g-1,frequencyBlocks);
                timeBlock=floor((g-1)/frequencyBlocks);
                chip=0;
                for td=0:tdOcc-1
                    for fd=0:fdOcc-1
                        chip=chip+1;
                        subcarrier=frequencyBlock*groupWidth+fd*frequencyStride;
                        symbol=timeBlock*tdOcc+td;
                        re(chip,g)=subcarrier+1+symbol*nSC;
                    end
                end
            end
            rows = repmat(localMapRow(),portCount*cdmSize,1);
            q = 0;
            for g = 1:groupCount
                for p = 1:cdmSize
                    logicalPort = (g-1)*cdmSize+p;
                    for chip = 1:cdmSize
                        q=q+1;
                        linear = re(chip,g);
                        rows(q)=struct("LogicalPort",logicalPort-1, ...
                            "CDMGroup",g-1,"OCCIndex",p-1,"ChipIndex",chip-1, ...
                            "LinearREZeroBased",linear-1, ...
                            "SubcarrierZeroBased",mod(linear-1,nSC), ...
                            "SymbolZeroBased",floor((linear-1)/nSC), ...
                            "FDOccLength",fdOcc,"TDOccLength",tdOcc, ...
                            "SequenceReal",real(C(chip,p)), ...
                            "SequenceImag",imag(C(chip,p)));
                    end
                end
            end
            map = struct2table(rows,"AsArray",true);
            plan = struct("PortCount",portCount,"CDMSize",cdmSize, ...
                "OCCFamily",lower(family),"Density",density, ...
                "FDTDSplit",splitLabel,"FDOccLength",fdOcc, ...
                "TDOccLength",tdOcc, ...
                "GroupCount",groupCount,"REPerPort",cdmSize, ...
                "REIndices",re,"OCC",C,"Map",map, ...
                "MapSHA256",sixgr.util.sha256Hex(uint8(unicode2native( ...
                    jsonencode(table2struct(map)),"UTF-8"))));
            planCache(cacheKey)=plan;
        end

        function result = runWaveformPoint(cfg,portCount,cdmSize,family, ...
                density,powerNormalization,snrDb,seed,options)
            arguments
                cfg (1,1) struct
                portCount (1,1) double {mustBePositive,mustBeInteger}
                cdmSize (1,1) double {mustBePositive,mustBeInteger}
                family (1,1) string
                density (1,1) double {mustBePositive}
                powerNormalization (1,1) string
                snrDb (1,1) double {mustBeFinite}
                seed (1,1) double {mustBeNonnegative,mustBeInteger}
                options.ChannelSeed (1,1) double {mustBeNonnegative,mustBeInteger} = seed
                options.NoiseSeed (1,1) double {mustBeNonnegative,mustBeInteger} = seed
                options.ChannelMatrix double = []
                options.ChipPhaseDeg (1,1) double {mustBeFinite} = 0
                options.CommonPhaseDeg (1,1) double {mustBeFinite} = 0
                options.PowerOffsetDb (1,1) double {mustBeFinite} = 0
                options.FDTDSplit (1,1) string = ""
                options.Estimator (1,1) string = "LS"
                options.ResidualCFOHz (1,1) double {mustBeFinite} = 0
                options.TimingOffsetSamples (1,1) double {mustBeInteger} = 0
                options.PhaseNoiseStdDeg (1,1) double {mustBeNonnegative,mustBeFinite} = 0
                options.PortPowerOffsetsDb double = []
            end
            carrierCfg = struct("n_rb",double(cfg.carrier.n_rb), ...
                "scs_khz",double(cfg.carrier.scs_khz), ...
                "n_cell_id",0);
            plan = sixgr.phy.refsig.HighPortCSIRSMapper.plan( ...
                carrierCfg,portCount,cdmSize,family,density,options.FDTDSplit);
            carrier = nrCarrierConfig("NSizeGrid",carrierCfg.n_rb, ...
                "SubcarrierSpacing",carrierCfg.scs_khz,"NCellID",0,"NSlot",0);
            nSC = 12*carrier.NSizeGrid;
            nRx = double(cfg.arrays.rx_antennas(1));
            switch lower(string(powerNormalization))
                case "fixed_total_csirs"
                    amplitude = sqrt(1/portCount);
                case "fixed_per_port_epre"
                    amplitude = 1;
                otherwise
                    error("sixgr:csi:InvalidPowerNormalization", ...
                        "Unsupported CSI-RS power normalization '%s'.",powerNormalization);
            end
            amplitude=amplitude*10^(double(options.PowerOffsetDb)/20);
            estimator=upper(string(options.Estimator));
            if ~ismember(estimator,["LS","LMMSE"])
                error("sixgr:csi:UnsupportedHighPortEstimator", ...
                    "Estimator must be LS or LMMSE, not '%s'.",options.Estimator);
            end
            portPowerOffsets=double(options.PortPowerOffsetsDb(:));
            if isempty(portPowerOffsets), portPowerOffsets=zeros(portCount,1); end
            if numel(portPowerOffsets)~=portCount || any(~isfinite(portPowerOffsets))
                error("sixgr:csi:InvalidHighPortPowerOffsets", ...
                    "PortPowerOffsetsDb must be empty or contain one finite value per logical port.");
            end
            portAmplitudes=amplitude*10.^(portPowerOffsets/20);
            old = rng; cleanup = onCleanup(@() rng(old)); %#ok<NASGU>
            rng(double(options.ChannelSeed),"twister");
            truth = complex(zeros(nRx,portCount));
            estimate = complex(zeros(nRx,portCount));
            % Use the repository-wide occupied-grid Es/N0 contract. A raw
            % time-domain variance here would be amplified by the OFDM
            % demodulator and put this CSI-RS path on a different SNR
            % convention from the production and conformance chains.
            noiseVariance = NaN;
            sampleNoiseVariance = NaN;
            sampleToGridGain = NaN;
            for g = 1:plan.GroupCount
                ports = (g-1)*cdmSize+(1:cdmSize);
                if isempty(options.ChannelMatrix)
                    H = (randn(nRx,cdmSize)+1j*randn(nRx,cdmSize))/sqrt(2);
                else
                    if ~isequal(size(options.ChannelMatrix),[nRx portCount]) || ...
                            any(~isfinite(real(options.ChannelMatrix)),"all") || ...
                            any(~isfinite(imag(options.ChannelMatrix)),"all")
                        error("sixgr:csi:InvalidHighPortChannelMatrix", ...
                            "ChannelMatrix must be a finite Nrx-by-Nport matrix.");
                    end
                    H=options.ChannelMatrix(:,ports);
                end
                truth(:,ports)=H;
                grid = complex(zeros(nSC,14,cdmSize));
                re = plan.REIndices(:,g);
                for p = 1:cdmSize
                    for chip = 1:cdmSize
                        [k,l]=ind2sub([nSC 14],re(chip));
                        grid(k,l,p)=portAmplitudes(ports(p))*plan.OCC(chip,p)* ...
                            exp(1j*deg2rad(double(options.ChipPhaseDeg))*(chip-1))* ...
                            exp(1j*deg2rad(double(options.CommonPhaseDeg)));
                    end
                end
                tx = nrOFDMModulate(carrier,grid);
                rx = tx*transpose(H);
                sampleRate=double(nrOFDMInfo(carrier).SampleRate);
                if options.ResidualCFOHz~=0
                    time=(0:size(rx,1)-1).'/sampleRate;
                    rx=rx.*exp(1j*2*pi*double(options.ResidualCFOHz)*time);
                end
                if options.PhaseNoiseStdDeg>0
                    rng(double(options.NoiseSeed)+100000+g-1,"twister");
                    phase=deg2rad(double(options.PhaseNoiseStdDeg))*randn(size(rx,1),1);
                    rx=rx.*exp(1j*phase);
                end
                timingOffset=double(options.TimingOffsetSamples);
                if timingOffset>0
                    rx=[complex(zeros(timingOffset,size(rx,2),"like",rx));rx];
                    rx=rx(1:size(tx,1),:);
                elseif timingOffset<0
                    advance=min(-timingOffset,size(rx,1));
                    rx=[rx(advance+1:end,:);complex(zeros(advance,size(rx,2),"like",rx))];
                end
                [rx,noiseInfo] = sixgr.phy.waveform.addOccupiedREAWGN( ...
                    rx,carrier,snrDb,"Seed",double(options.NoiseSeed)+g-1, ...
                    "SignalEnergyPerOccupiedRE",1);
                if g == 1
                    noiseVariance = double(noiseInfo.GridNoiseVariance);
                    sampleNoiseVariance = double(noiseInfo.SampleNoiseVariance);
                    sampleToGridGain = double( ...
                        noiseInfo.SampleToGridNoiseVarianceGain);
                elseif abs(noiseVariance-double(noiseInfo.GridNoiseVariance)) > ...
                        1e-12*max(1,noiseVariance)
                    error("sixgr:csi:InconsistentHighPortNoiseContract", ...
                        "Every streamed CSI-RS CDM group must use one grid-domain noise variance.");
                end
                rxGrid = nrOFDMDemodulate(carrier,rx);
                Y = complex(zeros(cdmSize,nRx));
                for chip = 1:cdmSize
                    [k,l]=ind2sub([nSC 14],re(chip));
                    Y(chip,:)=reshape(rxGrid(k,l,:),1,nRx);
                end
                ls=transpose(plan.OCC' * Y);
                ls=ls./reshape(portAmplitudes(ports),1,[]);
                if estimator=="LMMSE"
                    estimatorNoiseVariance=noiseVariance./max(portAmplitudes(ports).^2,eps);
                    shrinkage=1./(1+estimatorNoiseVariance);
                    estimate(:,ports)=ls.*reshape(shrinkage,1,[]);
                else
                    estimate(:,ports)=ls;
                end
            end
            errorPower=sum(abs(estimate(:)-truth(:)).^2);
            truthPower=sum(abs(truth(:)).^2);
            nmse=errorPower/max(truthPower,eps);
            result=struct("Plan",plan,"Truth",truth,"Estimate",estimate, ...
                "NMSE",nmse,"NMSEdB",10*log10(max(nmse,realmin)), ...
                "SGCS",localSGCS(truth,estimate), ...
                "PerPortEPRE",mean(portAmplitudes.^2), ...
                "TotalCSIRSPower",sum(portAmplitudes.^2), ...
                "NoiseVariance",noiseVariance, ...
                "GridNoiseVariance",noiseVariance, ...
                "SampleNoiseVariance",sampleNoiseVariance, ...
                "SampleToGridNoiseVarianceGain",sampleToGridGain, ...
                "NoiseVarianceDomain","resource_grid_pre_equalization", ...
                "NoiseSource","sixgr.phy.waveform.addOccupiedREAWGN", ...
                "SNRdB",double(snrDb), ...
                "Seed",double(seed),"ChannelSeed",double(options.ChannelSeed), ...
                "NoiseSeed",double(options.NoiseSeed),"ReceiverAntennas",nRx, ...
                "ChipPhaseDeg",double(options.ChipPhaseDeg), ...
                "CommonPhaseDeg",double(options.CommonPhaseDeg), ...
                "PowerOffsetDb",double(options.PowerOffsetDb), ...
                "PortPowerOffsetRangeDb",max(portPowerOffsets)-min(portPowerOffsets), ...
                "FDTDSplit",string(plan.FDTDSplit), ...
                "Estimator",estimator, ...
                "EstimatorSource",localEstimatorSource(estimator), ...
                "ResidualCFOHz",double(options.ResidualCFOHz), ...
                "TimingOffsetSamples",double(options.TimingOffsetSamples), ...
                "PhaseNoiseStdDeg",double(options.PhaseNoiseStdDeg), ...
                "ExecutionBackend","nr_ofdm_streamed_high_port_occ_waveform", ...
                "ApproximationMode","none", ...
                "EvidenceClass","LLS_CONTROLLED");
        end

        function result = runMultiSlotWaveformPoint(cfg,options)
            %RUNMULTISLOTWAVEFORMPOINT Repeat the canonical mapper over a
            % bounded, time-evolving measured channel and logged phase
            % events. Every slot performs real NR OFDM modulation,
            % propagation, calibrated noise injection, demodulation and OCC
            % despreading through runWaveformPoint.
            arguments
                cfg (1,1) struct
                options.M1 (1,1) double {mustBePositive,mustBeInteger}
                options.PortCount (1,1) double {mustBePositive,mustBeInteger}
                options.CDMSize (1,1) double {mustBePositive,mustBeInteger}
                options.OCCFamily (1,1) string = "walsh"
                options.Density (1,1) double {mustBePositive} = 1
                options.PowerNormalization (1,1) string = "fixed_per_port_epre"
                options.SNRdB (1,1) double {mustBeFinite} = 10
                options.SpeedKmph (1,1) double {mustBeNonnegative} = 0
                options.PhaseIncrementDeg (1,1) double {mustBeFinite} = 0
                options.Seed (1,1) double {mustBeNonnegative,mustBeInteger} = 1
            end
            nRx=double(cfg.arrays.rx_antennas(1)); p=double(options.PortCount);
            old=rng; cleanup=onCleanup(@()rng(old)); %#ok<NASGU>
            rng(double(options.Seed),"twister");
            H=(randn(nRx,p)+1j*randn(nRx,p))/sqrt(2);
            fc=double(cfg.carrier.center_frequency_hz);
            fd=(double(options.SpeedKmph)/3.6)*fc/299792458;
            rho=besselj(0,2*pi*fd*double(cfg.multislot.slot_duration_s));
            rho=max(-1,min(1,real(rho)));
            estimates=complex(zeros(nRx,p,options.M1));
            truths=complex(zeros(nRx,p,options.M1));
            rows=repmat(localMultiSlotRow(),options.M1,1);
            for slot=1:options.M1
                if slot>1
                    innovation=(randn(nRx,p)+1j*randn(nRx,p))/sqrt(2);
                    H=rho*H+sqrt(max(0,1-rho^2))*innovation;
                end
                phaseDeg=(slot-1)*double(options.PhaseIncrementDeg);
                point=sixgr.phy.refsig.HighPortCSIRSMapper.runWaveformPoint( ...
                    cfg,p,options.CDMSize,options.OCCFamily,options.Density, ...
                    options.PowerNormalization,options.SNRdB,options.Seed+slot, ...
                    "ChannelMatrix",H,"ChannelSeed",options.Seed, ...
                    "NoiseSeed",options.Seed+1000*slot, ...
                    "CommonPhaseDeg",phaseDeg);
                estimates(:,:,slot)=point.Estimate;
                truths(:,:,slot)=point.Truth;
                rows(slot)=struct("SlotIndex",slot-1,"M1",options.M1, ...
                    "TxPorts",p,"CDMSize",options.CDMSize, ...
                    "PhaseEventDeg",phaseDeg,"MaximumDopplerHz",fd, ...
                    "AdjacentSlotCorrelation",rho,"SNRdB",options.SNRdB, ...
                    "SlotNMSE",localNMSE(point.Truth,estimates(:,:,slot)), ...
                    "SlotSGCS",localSGCS(point.Truth,estimates(:,:,slot)), ...
                    "ChannelSeed",options.Seed,"NoiseSeed",options.Seed+1000*slot, ...
                    "ExecutionBackend",point.ExecutionBackend, ...
                    "ApproximationMode","none","EvidenceClass","LLS_CONTROLLED", ...
                    "Status","PASS");
            end
            reference=mean(truths,3);
            uncorrected=mean(estimates,3);
            phase=reshape(exp(-1j*deg2rad((0:options.M1-1)* ...
                double(options.PhaseIncrementDeg))),1,1,[]);
            corrected=mean(estimates.*phase,3);
            summary=table(["coherent_uncorrected";"phase_corrected"], ...
                [localNMSE(reference,uncorrected);localNMSE(reference,corrected)], ...
                [localSGCS(reference,uncorrected);localSGCS(reference,corrected)], ...
                repmat(options.M1,2,1),repmat(p,2,1), ...
                repmat("LLS_CONTROLLED",2,1),repmat("PASS",2,1), ...
                'VariableNames',{'ReceiverMode','NMSELinear','SGCS','M1', ...
                'TxPorts','EvidenceClass','Status'});
            summary.NMSEdB=10*log10(max(summary.NMSELinear,realmin));
            result=struct("Trace",struct2table(rows,"AsArray",true), ...
                "Summary",summary,"Estimate",estimates,"Truth",truths, ...
                "CoherentEstimate",uncorrected, ...
                "PhaseCorrectedEstimate",corrected, ...
                "ReferenceChannel",reference, ...
                "ExecutionBackend","nr_ofdm_multislot_high_port_occ_waveform", ...
                "ApproximationMode","none","EvidenceClass","LLS_CONTROLLED");
        end
    end
end

function row=localMapRow()
row=struct("LogicalPort",NaN,"CDMGroup",NaN,"OCCIndex",NaN, ...
    "ChipIndex",NaN,"LinearREZeroBased",NaN,"SubcarrierZeroBased",NaN, ...
    "SymbolZeroBased",NaN,"FDOccLength",NaN,"TDOccLength",NaN, ...
    "SequenceReal",NaN,"SequenceImag",NaN);
end

function [fdOcc,tdOcc,label]=localFDTDSplit(raw,cdmSize)
raw=lower(strtrim(string(raw)));
if raw==""
    fdOcc=cdmSize;
    tdOcc=1;
else
    tokens=regexp(char(raw),'^(\d+)x(\d+)$','tokens','once');
    if isempty(tokens)
        error("sixgr:csi:InvalidFDTDSplit", ...
            "FD/TD split '%s' must use the form <FD>x<TD>.",raw);
    end
    fdOcc=str2double(tokens{1});
    tdOcc=str2double(tokens{2});
end
if fdOcc<1 || tdOcc<1 || fdOcc*tdOcc~=cdmSize
    error("sixgr:csi:InvalidFDTDSplit", ...
        "FD/TD split %dx%d must have product CDM%d.",fdOcc,tdOcc,cdmSize);
end
label=string(fdOcc)+"x"+string(tdOcc);
end

function source=localEstimatorSource(estimator)
if estimator=="LMMSE"
    source="iid_unit_variance_channel_prior_grid_noise_lmmse";
else
    source="occ_matched_filter_least_squares";
end
end

function value=localSGCS(a,b)
num=abs(sum(conj(a(:)).*b(:)))^2;
den=sum(abs(a(:)).^2)*sum(abs(b(:)).^2);
value=num/max(den,eps);
end

function value=localNMSE(reference,estimate)
value=sum(abs(estimate(:)-reference(:)).^2)/max(sum(abs(reference(:)).^2),eps);
end

function row=localMultiSlotRow()
row=struct("SlotIndex",NaN,"M1",NaN,"TxPorts",NaN,"CDMSize",NaN, ...
    "PhaseEventDeg",NaN,"MaximumDopplerHz",NaN, ...
    "AdjacentSlotCorrelation",NaN,"SNRdB",NaN,"SlotNMSE",NaN, ...
    "SlotSGCS",NaN,"ChannelSeed",NaN,"NoiseSeed",NaN, ...
    "ExecutionBackend","","ApproximationMode","none", ...
    "EvidenceClass","LLS_CONTROLLED","Status","PASS");
end
