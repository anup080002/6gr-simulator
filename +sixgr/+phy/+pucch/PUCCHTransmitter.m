classdef PUCCHTransmitter
    %PUCCHTRANSMITTER Canonical typed-report PUCCH waveform transmitter.

    methods (Static)
        function tx = transmit(carrier,assignment,report)
            if ~isa(assignment,"sixgr.phy.pucch.PUCCHTransmissionAssignment") || ...
                    ~isa(report,"sixgr.phy.pucch.UCIReport")
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "PUCCH TX requires typed assignment and report.");
            end
            if assignment.ReportID ~= report.ReportID || ...
                    assignment.ConfigurationEpoch ~= report.ConfigurationEpoch
                error("sixgr:phy:pucch:StaleConfiguration", ...
                    "PUCCH report and assignment ownership differ.");
            end
            if isfield(assignment.Data,'ReportDigest')
                bound=assignment.Data.ReportDigest;
                validText=(ischar(bound)&&isrow(bound)) || (isstring(bound)&&isscalar(bound));
                assert(validText && ~ismissing(string(bound)) && string(bound)==report.Digest, ...
                    'sixgr:phy:pucch:PlannedReportMismatch', ...
                    'The transmitted report must exactly match the report used for resource planning.');
            else
                % Explicit isolated calibration has no payload-derived plan.
                % Missing binding is never a connected-mode compatibility path.
                assert(string(assignment.Data.AssignmentSource)=="calibration" && ...
                    isequal(assignment.Data.ConnectedModeEvidenceEligible,false) && ...
                    ~isfield(assignment.Data,'AllocationBudget'), ...
                    'sixgr:phy:pucch:MissingPlannedReportBinding', ...
                    'A planned PUCCH assignment must retain its exact report digest.');
            end
            powerState=assignment.PowerControlState.Data;
            if isfield(assignment.Data,'AllocationBudget') && ...
                    ~isempty(fieldnames(assignment.Data.AllocationBudget))
                sixgr.phy.pucch.PUCCHResource.validateAllocationCarrier(assignment.Data.AllocationBudget,carrier);
            end
            mu=log2(double(carrier.SubcarrierSpacing)/15);
            if double(powerState.Mu)~=mu || ...
                    double(powerState.MRB)~=double(assignment.Resource.Data.NumPRBs)
                error("sixgr:phy:pucch:PowerResourceMismatch", ...
                    "PUCCH power-control Mu/MRB must match the actual carrier and allocated resource.");
            end
            serialized = sixgr.phy.pucch.UCIReportSerializer.serialize(report);
            bits = [serialized.Sequence1.Bits;serialized.Sequence2.Bits];
            context=sixgr.phy.pucch.UCIReportContext.fromReport(report);
            sixgr.phy.pucch.PUCCHFormatValidator.validateResource( ...
                assignment.Resource.Data,numel(bits),context);
            pucch = assignment.Resource.toolboxConfig();
            [~,info] = nrPUCCHIndices(carrier,pucch);
            transmissionPresent=true;
            if assignment.Format <= 1
                owners=string(serialized.Layout.BitOwner);
                harq=bits(owners=="HARQ_ACK");
                sr=bits(owners=="SR");
                transmissionPresent=~isempty(harq) || isempty(sr) || logical(sr);
                if assignment.Format==0
                    symbols=nrPUCCH(carrier,pucch,{harq,sr});
                elseif isempty(harq)
                    % Format-1 positive SR is the fixed BPSK symbol for 0,
                    % not modulation of the semantic SR value 1.
                    if transmissionPresent, symbols=nrPUCCH(carrier,pucch,int8(0));
                    else, symbols=complex(zeros(0,1)); end
                else
                    symbols=nrPUCCH(carrier,pucch,harq);
                end
                coding = struct("Plan",sixgr.phy.pucch.UCIEncodingPlan( ...
                    numel(bits),numel(bits)),"CodedBits",bits, ...
                    "CodedDigest",sixgr.phy.pucch.PUCCHUtil.hash(bits.'));
            else
                coding = sixgr.phy.pucch.UCIEncoder.encode( ...
                    sixgr.phy.pucch.UCISequence(1,bits, ...
                    repmat("UCI",numel(bits),1), ...
                    repmat("combined_report_sequence",numel(bits),1)), ...
                    double(info.G),localModulation(pucch));
                symbols = nrPUCCH(carrier,pucch,coding.CodedBits);
            end
            mapped = sixgr.phy.pucch.PUCCHGridMapper.map( ...
                carrier,assignment,symbols,transmissionPresent);
            [waveform,ofdmInfo] = sixgr.phy.waveform.ofdmModulate( ...
                carrier,mapped.Grid);
            power = sixgr.phy.pucch.PUCCHPowerController.resolve( ...
                assignment.PowerControlState);
            activeSymbols=double(assignment.Resource.Data.StartSymbol)+ ...
                (0:double(assignment.Resource.Data.NumSymbols)-1);
            normalized=logical(sixgr.phy.pucch.PUCCHUtil.field(power,'NormalizedPowerReference',false));
            if normalized || ~transmissionPresent
                % Keep the original generated IFFT. No absolute power is
                % fabricated and no scale is applied only to undo it later.
                scale=1;
                [~,~,reference]=sixgr.rf.measureActiveOFDMTotalPower( ...
                    waveform,struct('OFDM',ofdmInfo),'ActiveSymbolIndices',activeSymbols);
            else
                [waveform,scale,reference] = localApplyPower( ...
                    waveform,power.AppliedPowerdBm,ofdmInfo,activeSymbols);
            end
            % Canonical simulator samples use sqrt(mW), so mean |x|^2 is
            % directly expressed in mW and converts to dBm without a
            % watts-to-milliwatts factor.
            [measured_mW,~,measuredInfo]=sixgr.rf.measureActiveOFDMTotalPower( ...
                waveform,struct('OFDM',ofdmInfo),'ActiveSymbolIndices',activeSymbols);
            measured = 10*log10(measured_mW);
            power.MeasuredWaveformPowerdBm = measured;
            power.PowerError_dB = measured-power.AppliedPowerdBm;
            power.MeasurementReferenceDomain=string(measuredInfo.ReferenceDomain);
            power.MeasurementActiveSymbolIndices0=activeSymbols;
            power.MeasurementSampleCount=measuredInfo.SampleCount;
            power.MeasuredSlotAveragePowerdBm=10*log10(mean(sum(abs(double(waveform)).^2,2)));
            power.WaveformAmplitudeUnit="sqrt_mW";
            power.WaveformScale=scale;
            power.PreScalingActivePower=reference;
            power.TransmissionPresent=transmissionPresent;
            if ~transmissionPresent
                power.UnappliedRequestedPowerdBm=power.AppliedPowerdBm;
                power.AppliedPowerdBm=NaN;
                power.PowerError_dB=NaN;
            end
            if normalized
                power.NormalizedActiveMeanSquare=measured_mW;
                power.NormalizedSlotAverageMeanSquare=mean(sum(abs(double(waveform)).^2,2));
                power.MeasuredWaveformPowerdBm=NaN;
                power.MeasuredSlotAveragePowerdBm=NaN;
                power.PowerError_dB=NaN;
                power.WaveformAmplitudeUnit="normalized_complex_baseband";
            end
            tx = struct( ...
                "Waveform",waveform,"Grid",mapped.Grid,"Carrier",carrier, ...
                "TransmissionPresent",transmissionPresent, ...
                "PUCCH",pucch,"Assignment",assignment,"Report",report, ...
                "PUCCHIndices",mapped.DataIndices, ...
                "DMRSIndices",mapped.DMRS.Indices, ...
                "Serialization",serialized,"Coding",coding, ...
                "Ownership",mapped.Ownership,"DMRS",mapped.DMRS, ...
                "Power",power,"OFDMInfo",ofdmInfo, ...
                "ExecutionProfile",localProfile(assignment), ...
                "ConnectedModeEvidenceEligible",logical( ...
                assignment.Data.ConnectedModeEvidenceEligible), ...
                "AssignmentDigest",assignment.Digest, ...
                "ReportDigest",report.Digest, ...
                "SerializationDigest",serialized.Digest, ...
                "CodingPlanDigest",coding.Plan.Digest, ...
                "ResourceOwnershipDigest",mapped.Ownership.Digest, ...
                "DMRSSequenceDigest",mapped.DMRS.SequenceSHA256, ...
                "DMRSIndexDigest",mapped.DMRS.IndexSHA256, ...
                "PowerStateDigest",assignment.PowerControlState.Digest, ...
                "SpatialStateDigest",assignment.SpatialRelationState.Digest, ...
                "WaveformSHA256",sixgr.phy.pucch.PUCCHUtil.hash( ...
                [real(waveform(:)).' imag(waveform(:)).']));
        end
    end
end

function value = localModulation(pucch)
value = "QPSK";
if isprop(pucch,"Modulation"), value = string(pucch.Modulation); end
end

function [waveform,scale,reference] = localApplyPower(waveform,powerdBm,ofdmInfo,activeSymbols)
% Match the shared runtime's useful-symbol reference, without including
% silent slot samples or relying on an energy detector to choose symbols.
[current,~,reference] = sixgr.rf.measureActiveOFDMTotalPower( ...
    waveform,struct('OFDM',ofdmInfo),'ActiveSymbolIndices',activeSymbols);
target = 10^(double(powerdBm)/10);
if current <= 0 || ~isfinite(current) || ~isfinite(target) || target<=0 || ...
        string(reference.ReferenceDomain)~="specified_active_ofdm_symbols_excluding_cp" || ...
        any(~isfinite(waveform),'all')
    error("sixgr:phy:pucch:InvalidPowerControlState", ...
        "PUCCH power requires finite samples and complete allocated OFDM-symbol evidence.");
end
scale=sqrt(target/current);
waveform = waveform*scale;
end

function value = localProfile(assignment)
if assignment.Data.ConnectedModeEvidenceEligible
    value = "connected_strict";
else
    value = "calibration";
end
end
