function out = runCellSearch_MIB_SIB1(cfg, varargin)
%RUNSEARCH_MIB_SIB1 Link-level initial access smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("NumSubframes", 10, @(x) isnumeric(x) && isscalar(x) && x >= 1);
p.addParameter("SSBIndex", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x >= 0));
p.addParameter("CandidateSSBIndices", [], @(x) isempty(x) || ...
    (isnumeric(x) && isreal(x) && isvector(x) && ...
    all(isfinite(x)) && all(x >= 0) && all(x == fix(x)) && ...
    numel(unique(x)) == numel(x)));
p.addParameter("RunFolder", "", @(x) ischar(x) || isstring(x));
p.addParameter("RunId", "sib1_runtime", @(x) ischar(x) || isstring(x));
p.addParameter("WriteArtifacts", false, @(x) islogical(x) || isnumeric(x));
p.addParameter("UseRuntimeChannel", false, @(x) islogical(x) || isnumeric(x));
p.addParameter("InitialDLChannelState", struct(), @(x) isempty(x) || isstruct(x));
% Explicit zero-based absolute slot, independent of the coupled runner's
% one-based loop index. NaN means no explicit runtime origin was supplied.
p.addParameter("RuntimeSlot", NaN, @(x) isnumeric(x) && isreal(x) && isscalar(x) && ...
    (isnan(x) || (isfinite(x) && x >= 0 && x == fix(x))));
p.parse(varargin{:});
log = p.Results.Logger;
numSF = round(double(p.Results.NumSubframes));

out = struct();
out.Ok = false;
out.Skipped = false;
out.Crash = false;
out.Status = "started";
out.FailureIdentifier = "";
out.FailureReason = "";
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = NaN;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.FreqOffsetEstimate_Hz = NaN;
out.TrueCFO_Hz = NaN;
out.CFOError_Hz = NaN;
out.TimingOffset_samples = NaN;
out.TrueTimingOffset_samples = 0;
out.TimingError_samples = NaN;
out.InjectedCFO_Hz = NaN;
out.EstimatedCFO_PreCorrection_Hz = NaN;
out.ResidualCFO_PostCorrection_Hz = NaN;
out.InjectedTimingOffset_samples = NaN;
out.EstimatedTimingOffset_PreCorrection_samples = NaN;
out.ResidualTimingError_PostCorrection_samples = NaN;
out.RawTimingEstimate_samples = NaN;
out.AppliedTimingCorrection_samples = NaN;
out.TimingEstimateApplicationPolicy = "";
out.TimingEstimateStatus = "";
out.TimingEstimateWasClipped = false;
out.Sync = struct();
out.PBCH = struct();
out.SSBIndex = NaN;
out.SSBBeamIndex = NaN;
out.SSBReceivedPower_dB = NaN;
out.SS_RSRP_dBm = NaN;
out.SS_RSRPPerReceiveAntenna_dBm = "";
out.SS_RSRPRawObserved_dBm = NaN;
out.SS_RSRPRawObservedPerReceiveAntenna_dBm = "";
out.SS_SINR_dB = NaN;
out.SS_SINRPerReceiveAntenna_dB = "";
out.SSMeasurementSource = "";
out.SSSINRMeasurementMethod = "";
out.SSSINRReferencePlane = "";
out.SSSINRNoiseInterferencePowerPerReceiveAntenna_W = "";
out.SSSINRDesiredPowerPerReceiveAntenna_W = "";
out.SSSINRNoiseInterferenceRECount = NaN;
out.SSPhysicalMeasurementStatus = "unavailable";
out.SSSINRFailureReason = "";
out.ReferenceSignalId = NaN;
out.ReferenceSignalTxEPRE_dBm = NaN;
out.ReferenceSignalTxEPREPerAntenna_dBm = "";
out.ReferenceSignalTxMeasurementSource = "";
out.MeasuredReferenceSignalPathloss_dB = NaN;
out.MeasuredReferenceSignalPathlossSource = "";
out.PathlossReferenceRS = "";
out.PowerReferencePlane = "";
out.PBCHDMRSMetric = NaN;
out.PSSMetric = NaN;
out.SSSMetric = NaN;
out.SSSMetricMargin = NaN;
out.PSSSearchSamples = NaN;
out.PSSTimingLagsEvaluated = NaN;
out.PSSSequences = NaN;
out.PSSCorrelationVectors = NaN;
out.SSSSequenceHypotheses = NaN;
out.PBCHDMRSHypothesesTested = NaN;
out.PSSDetected = false;
out.SSSDetected = false;
out.NCellIDRecovered = false;
out.PSSDetectionSource = "";
out.SSSDetectionSource = "";
out.PBCHNoiseVar = NaN;
out.PreEqualizationNoiseVariance = NaN;
out.PreEqualizationNoiseVarianceDomain = "";
out.PreEqualizationNoiseVarianceSource = "";
out.ChannelEstimateAvailable = false;
out.ChannelEstimateSource = "";
out.EqualizationAvailable = false;
out.EqualizerType = "";
out.ReceiverHestSINR_dB = NaN;
out.ReceiverHestSINRSource = "";
out.ReceiverHestSINRValueRole = "";
out.ReceiverHestSINRValueStatus = "";
out.ReceiverHestSINRNAReason = "";
out.MeasuredTrialSINR_dB = NaN;
out.MeasuredTrialSINRSource = "";
out.MeasuredTrialSINRValueRole = "";
out.MeasuredTrialSINRValueStatus = "";
out.MeasuredTrialSINRNAReason = "";
out.PostEqSINR_dB = NaN;
out.PostEqSINRAvailable = false;
out.PostEqSINRSource = "";
out.PostEqSINRValueRole = "";
out.PostEqSINRValueStatus = "";
out.PostEqSINRNAReason = "";
out.PostEqualizationNoiseVariance = NaN;
out.PostEqualizationNoiseVarianceDomain = "";
out.PostEqualizationNoiseVarianceSource = "";
out.StrictReceiverEvidenceOk = false;
out.DetectionAttempted = false;
out.MeasurementAttempted = false;
out.ResourceExtractionAttempted = false;
out.ChannelEstimateAttempted = false;
out.EqualizationAttempted = false;
out.DecodeAttempted = false;
out.LLRAvailable = false;
out.LLRFinite = false;
out.SIB1PDSCHChannelEstimateAvailable = false;
out.SIB1PDSCHEqualizationAvailable = false;
out.SIB1PDSCHReceiverHestSINR_dB = NaN;
out.SIB1PDSCHReceiverHestSINRSource = "";
out.SIB1PDSCHStrictReceiverEvidenceOk = false;
out.RuntimeDLChannelState = sixgr.channel.ChannelFactory.emptyRuntimeChannelState();
out.RuntimeChannelReplay = struct();
out.RuntimeChannelStateUsed = false;
out.SSBTxEvidence = struct();
out.PowerContext = struct();

configuredSSB = logical(sixgr.util.structGet(cfg, "phy.ssb.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "ssb", configuredSSB, ...
    "runCellSearch_MIB_SIB1.SSB");
configuredPBCH = logical(sixgr.util.structGet(cfg, "phy.pbch.enable", ...
    sixgr.util.structGet(cfg, "phy.mib.enable", false)));
sixgr.config.assertRuntimeFeatureUse(cfg, "pbch", configuredPBCH, ...
    "runCellSearch_MIB_SIB1.PBCH");
if ~(configuredSSB && configuredPBCH)
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.ssb.enable=true for CellSearch_MIB_SIB1 coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Status = "SKIPPED";
    out.FailureReason = "ssb_or_pbch_disabled_by_configuration";
    out.Notes = "Skipped: cfg.phy.ssb.enable=false";
    return;
end

if exist("nrWaveformGenerator","file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires 5G Toolbox SSB/PBCH APIs for CellSearch_MIB_SIB1 coverage.");
    out.Skipped = true;
    out.Ok = true;
    out.Status = "SKIPPED";
    out.FailureReason = "required_5g_toolbox_ssb_pbch_api_unavailable";
    out.Notes = "Skipped: 5G Toolbox SSB/PBCH APIs not available.";
    return;
end

wantSIB1 = logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false));
if ~isempty(p.Results.CandidateSSBIndices) && ...
        (~wantSIB1 || logical(p.Results.WriteArtifacts))
    error("sixgr:link:InvalidSharedBurstReceiverRequest", ...
        "Shared-burst candidate decoding requires the SIB1 capture path and in-memory artifact ownership.");
end
sixgr.config.assertRuntimeFeatureUse(cfg, "sib1", wantSIB1, ...
    "runCellSearch_MIB_SIB1.SIB1");
if wantSIB1
    try
        cfg = localSanitizeSIB1PrecodingConfig(cfg);
        tStart = tic;
        requestedSNR_dB = double(sixgr.util.structGet(cfg, "channel.snr_dB", Inf));
        generatorSNR_dB = requestedSNR_dB;
        if logical(p.Results.UseRuntimeChannel)
            generatorSNR_dB = Inf;
        end
        tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
            "SNRdB", generatorSNR_dB, ...
            "Seed", double(sixgr.util.structGet(cfg, "run.seed", 1501)));
        out.SSBTxEvidence = localBuildSSBTxEvidence(tx);
        rxWaveform = tx.Waveform;
        receiverCfg = cfg;
        if logical(p.Results.UseRuntimeChannel)
            txInfo = struct("OFDM", struct("SampleRate", double(tx.SampleRateHz)));
            try
                if isfield(tx, "Carrier") && ~isempty(tx.Carrier)
                    txInfo.OFDM = nrOFDMInfo(tx.Carrier);
                    % Bind fixed-EPRE normalization to the exact composite
                    % waveform that carries SS/PBCH and SI-RNTI SIB1.  The
                    % grid is recovered from the unscaled generated
                    % waveform on the same carrier; it is not regenerated
                    % from YAML or inferred from planned allocations.
                    txInfo.PortGrid = nrOFDMDemodulate( ...
                        tx.Carrier, tx.Waveform);
                    txInfo.PowerNormalizationGridSource = ...
                        "exact_composite_ssb_pbch_sib1_waveform_demodulation";
                end
            catch exception
                policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
                    "lls6g.resolvedConfig.power_and_rf_frontend.downlink_power_normalization_policy", ...
                    sixgr.util.structGet(cfg, ...
                    "powerAndRF.downlinkPowerNormalizationPolicy", "")))));
                if any(policy == ["fixed_epre_over_configured_bwp", ...
                        "full_bwp_reference_epre", "fixed_full_bwp_epre"])
                    wrapped = MException( ...
                        "sixgr:link:BroadcastPowerNormalizationGridUnavailable", ...
                        ["The exact SS/PBCH/SIB1 composite resource grid " ...
                         "could not be recovered for configured fixed-EPRE " ...
                         "normalization: %s"], exception.message);
                    wrapped = addCause(wrapped, exception);
                    throwAsCaller(wrapped);
                end
            end
            [runtimeTxWaveform, powerContext] = sixgr.rf.applyPowerContext( ...
                tx.Waveform, cfg, "DL", txInfo);
            out.PowerContext = powerContext;
            receiverCfg = sixgr.util.structSet( ...
                receiverCfg, "lls6g.runtimePowerContext", powerContext);
            runtimeTx = tx;
            runtimeTx.Waveform = runtimeTxWaveform;
            runtimeTx.PowerContext = powerContext;
            txInfo.PowerContext = powerContext;
            truthState = sixgr.link.initWaveformTruthChannelState( ...
                receiverCfg, runtimeTx, txInfo, ...
                "InitialRuntimeChannelState", p.Results.InitialDLChannelState);
            runtimeSlot = double(p.Results.RuntimeSlot);
            if isfinite(runtimeSlot) && runtimeSlot >= 0 && ...
                    logical(sixgr.util.structGet( ...
                    truthState, "RuntimeChannelState.Initialized", false))
                slotStart_s = runtimeSlot * sixgr.time.slotDurationSec(cfg);
                truthState.RuntimeChannelState = ...
                    sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime( ...
                    truthState.RuntimeChannelState, slotStart_s, ...
                    size(runtimeTxWaveform, 2), runtimeTxWaveform);
            end
            [rxWaveform, channelReplay, truthState] = ...
                sixgr.link.applyWaveformTruthImpairments( ...
                runtimeTxWaveform, requestedSNR_dB, truthState, ...
                receiverCfg, runtimeTx, txInfo);
            out.RuntimeDLChannelState = truthState.RuntimeChannelState;
            out.RuntimeChannelReplay = channelReplay;
            out.RuntimeChannelStateUsed = logical(sixgr.util.structGet( ...
                channelReplay, "RuntimeChannelStateUsed", false));
        end
        % Materialize and receive the physical burst once. Candidate search
        % windows must not regenerate TX, fading, RF impairments, or noise.
        observationOut = out;
        candidateIndices = double(p.Results.CandidateSSBIndices(:).');
        if isempty(candidateIndices)
            candidateIndices = double(p.Results.SSBIndex);
        end
        if isempty(candidateIndices)
            candidateIndices = NaN; % Original blind receiver, no candidate hint.
        end
        candidateOutputs = cell(1, numel(candidateIndices));
        for candidateOrdinal = 1:numel(candidateIndices)
        out = observationOut;
        receiverArgs = {};
        if isfinite(candidateIndices(candidateOrdinal))
            % A coupled P1 sweep transmits the configured active SS burst
            % set once and measures each exact SS/PBCH occasion.  Preserve
            % blind acquisition when no candidate is requested, but gate a
            % sweep row to the requested canonical candidate window.
            receiverArgs = {"CandidateSSBIndex", ...
                candidateIndices(candidateOrdinal)};
        end
        rec = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
            rxWaveform, receiverCfg, receiverArgs{:});
        if logical(p.Results.UseRuntimeChannel)
            txSSBPower = localMeasureTransmitSSBEPRE( ...
                runtimeTxWaveform, receiverCfg, double(tx.SampleRateHz), ...
                double(sixgr.util.structGet(rec, "SSBIndex", NaN)));
            rec.ReferenceSignalId = double(sixgr.util.structGet(rec, "SSBIndex", NaN));
            rec.ReferenceSignalTxEPRE_dBm = double(txSSBPower.AggregateEPRE_dBm);
            rec.ReferenceSignalTxEPREPerAntenna_dBm = string( ...
                txSSBPower.PerTransmitPortEPREToken_dBm);
            rec.ReferenceSignalTxMeasurementSource = string(txSSBPower.Source);
            rec.PathlossReferenceRS = "SSB-" + string(rec.ReferenceSignalId);
            rec.PowerReferencePlane = ...
                "generated_tx_sss_epre_to_ue_antenna_connector_sss_rsrp";
            if logical(txSSBPower.Available) && ...
                    isfinite(double(sixgr.util.structGet(rec, "SS_RSRP_dBm", NaN)))
                rec.MeasuredReferenceSignalPathloss_dB = ...
                    double(txSSBPower.AggregateEPRE_dBm) - ...
                    double(rec.SS_RSRP_dBm);
                rec.MeasuredReferenceSignalPathlossSource = ...
                    "exact_generated_tx_sss_epre_minus_ue_measured_noise_debiased_ss_rsrp";
            else
                rec.MeasuredReferenceSignalPathloss_dB = NaN;
                rec.MeasuredReferenceSignalPathlossSource = "";
            end
        end
        rec = sixgr.phy.broadcast.attachSIB1ValidationComparison(tx, rec);
        out.ComputeLatency_ms = 1e3 * toc(tStart);
        out.ProcedureDelay_ms = NaN;
        out.AirInterfaceObservation_ms = localResolvePBCHObservationDurationMs(cfg);
        out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
        out.Ok = logical(rec.StrictOk);
        out.Status = string(sixgr.util.structGet(rec, "Status", "FAIL"));
        out.FailureReason = string(sixgr.util.structGet(rec, "FailureReason", ""));
        out.DetectionAttempted = logical(sixgr.util.structGet(rec, "DetectionAttempted", false));
        out.PSSDetected = logical(sixgr.util.structGet(rec, "PSSDetected", false));
        out.SSSDetected = logical(sixgr.util.structGet(rec, "SSSDetected", false));
        out.NCellIDRecovered = logical(sixgr.util.structGet(rec, "NCellIDRecovered", false));
        out.PSSDetectionSource = string(sixgr.util.structGet(rec, "PSSDetectionSource", ""));
        out.SSSDetectionSource = string(sixgr.util.structGet(rec, "SSSDetectionSource", ""));
        out.MeasurementAttempted = logical(sixgr.util.structGet(rec, "MeasurementAttempted", false));
        out.ResourceExtractionAttempted = logical(sixgr.util.structGet(rec, "ResourceExtractionAttempted", false));
        out.ChannelEstimateAttempted = logical(sixgr.util.structGet(rec, "ChannelEstimateAttempted", false));
        out.EqualizationAttempted = logical(sixgr.util.structGet(rec, "EqualizationAttempted", false));
        out.DecodeAttempted = logical(sixgr.util.structGet(rec, "DecodeAttempted", false));
        out.LLRAvailable = logical(sixgr.util.structGet(rec, "LLRAvailable", false));
        out.LLRFinite = logical(sixgr.util.structGet(rec, "LLRFinite", false));
        out.BLER = double(~out.Ok);
        out.Sync = struct("NCellID", double(rec.NCellID), "TimingOffset", double(rec.TimingOffset), ...
            "FreqOffset_Hz", double(rec.FrequencyOffsetHz));
        out.PBCH = struct("Ok", logical(rec.BCHCrcPass), "ErrFlag", double(~logical(rec.BCHCrcPass)), ...
            "NCellID", double(rec.NCellID), "SSBIndex", double(rec.SSBIndex), ...
            "ChannelEstimateAvailable", logical(sixgr.util.structGet(rec, "ChannelEstimateAvailable", false)), ...
            "BCHTransportBlockNumBits", double(sixgr.util.structGet(rec, "BCHTransportBlockNumBits", NaN)), ...
            "BCHTransportBlockHex", string(sixgr.util.structGet(rec, "BCHTransportBlockHex", "")), ...
            "BCHTransportBlockHash", string(sixgr.util.structGet(rec, "BCHTransportBlockHash", "")), ...
            "BCHScrambledBlockNumBits", double(sixgr.util.structGet(rec, "BCHScrambledBlockNumBits", NaN)), ...
            "BCHScrambledBlockHex", string(sixgr.util.structGet(rec, "BCHScrambledBlockHex", "")), ...
            "BCHScrambledBlockHash", string(sixgr.util.structGet(rec, "BCHScrambledBlockHash", "")), ...
            "MIBDecodedBitSource", string(sixgr.util.structGet(rec, "MIBDecodedBitSource", "")), ...
            "MIBSFN4LSBValue", double(sixgr.util.structGet(rec, "MIBSFN4LSBValue", NaN)), ...
            "MIBSFN4LSBBitString", string(sixgr.util.structGet(rec, "MIBSFN4LSBBitString", "")), ...
            "MIBHalfFrameBit", double(sixgr.util.structGet(rec, "MIBHalfFrameBit", NaN)), ...
            "MIBKSSBSubcarrierOffset", double(sixgr.util.structGet(rec, "MIBKSSBSubcarrierOffset", NaN)), ...
            "MIBSSBIndex", double(sixgr.util.structGet(rec, "MIBSSBIndex", NaN)), ...
            "PBCHiBarSSB", double(sixgr.util.structGet(rec, "PBCHiBarSSB", NaN)), ...
            "PBCHv", double(sixgr.util.structGet(rec, "PBCHv", NaN)), ...
            "SS_RSRP_dBm", double(sixgr.util.structGet(rec, "SS_RSRP_dBm", NaN)), ...
            "SS_RSRPPerReceiveAntenna_dBm", string(sixgr.util.structGet( ...
                rec, "SS_RSRPPerReceiveAntenna_dBm", "")), ...
            "SS_RSRPRawObserved_dBm", double(sixgr.util.structGet( ...
                rec, "SS_RSRPRawObserved_dBm", NaN)), ...
            "SS_RSRPRawObservedPerReceiveAntenna_dBm", string(sixgr.util.structGet( ...
                rec, "SS_RSRPRawObservedPerReceiveAntenna_dBm", "")), ...
            "SS_SINR_dB", double(sixgr.util.structGet(rec, "SS_SINR_dB", NaN)), ...
            "SS_SINRPerReceiveAntenna_dB", string(sixgr.util.structGet( ...
                rec, "SS_SINRPerReceiveAntenna_dB", "")), ...
            "SSMeasurementSource", string(sixgr.util.structGet( ...
                rec, "SSMeasurementSource", "")), ...
            "SSSINRMeasurementMethod", string(sixgr.util.structGet( ...
                rec, "SSSINRMeasurementMethod", "")), ...
            "SSSINRReferencePlane", string(sixgr.util.structGet( ...
                rec, "SSSINRReferencePlane", "")), ...
            "SSSINRNoiseInterferencePowerPerReceiveAntenna_W", string( ...
                sixgr.util.structGet(rec, ...
                "SSSINRNoiseInterferencePowerPerReceiveAntenna_W", "")), ...
            "SSSINRDesiredPowerPerReceiveAntenna_W", string( ...
                sixgr.util.structGet(rec, ...
                "SSSINRDesiredPowerPerReceiveAntenna_W", "")), ...
            "SSSINRNoiseInterferenceRECount", double(sixgr.util.structGet( ...
                rec, "SSSINRNoiseInterferenceRECount", NaN)), ...
            "SSPhysicalMeasurementStatus", string(sixgr.util.structGet( ...
                rec, "SSPhysicalMeasurementStatus", "unavailable")), ...
            "SSSINRFailureReason", string(sixgr.util.structGet( ...
                rec, "SSSINRFailureReason", "")), ...
            "ChannelEstimateSource", string(sixgr.util.structGet(rec, "ChannelEstimateSource", "")), ...
            "EqualizationAvailable", logical(sixgr.util.structGet(rec, "EqualizationAvailable", false)), ...
            "EqualizerType", string(sixgr.util.structGet(rec, "EqualizerType", "")), ...
            "ReceiverHestSINR_dB", double(sixgr.util.structGet(rec, "ReceiverHestSINR_dB", NaN)), ...
            "ReceiverHestSINRSource", string(sixgr.util.structGet(rec, "ReceiverHestSINRSource", "")), ...
            "ReceiverHestSINRValueRole", string(sixgr.util.structGet(rec, "ReceiverHestSINRValueRole", "")), ...
            "ReceiverHestSINRValueStatus", string(sixgr.util.structGet(rec, "ReceiverHestSINRValueStatus", "")), ...
            "ReceiverHestSINRNAReason", string(sixgr.util.structGet(rec, "ReceiverHestSINRNAReason", "")), ...
            "MeasuredTrialSINR_dB", double(sixgr.util.structGet(rec, "MeasuredTrialSINR_dB", NaN)), ...
            "MeasuredTrialSINRSource", string(sixgr.util.structGet(rec, "MeasuredTrialSINRSource", "")), ...
            "MeasuredTrialSINRValueRole", string(sixgr.util.structGet(rec, "MeasuredTrialSINRValueRole", "")), ...
            "MeasuredTrialSINRValueStatus", string(sixgr.util.structGet(rec, "MeasuredTrialSINRValueStatus", "")), ...
            "MeasuredTrialSINRNAReason", string(sixgr.util.structGet(rec, "MeasuredTrialSINRNAReason", "")), ...
            "PostEqSINR_dB", double(sixgr.util.structGet(rec, "PostEqSINR_dB", NaN)), ...
            "PostEqSINRAvailable", logical(sixgr.util.structGet(rec, "PostEqSINRAvailable", false)), ...
            "PostEqSINRSource", string(sixgr.util.structGet(rec, "PostEqSINRSource", "")), ...
            "PostEqSINRValueRole", string(sixgr.util.structGet(rec, "PostEqSINRValueRole", "")), ...
            "PostEqSINRValueStatus", string(sixgr.util.structGet(rec, "PostEqSINRValueStatus", "")), ...
            "PostEqSINRNAReason", string(sixgr.util.structGet(rec, "PostEqSINRNAReason", "")), ...
            "PreEqualizationNoiseVariance", double(sixgr.util.structGet(rec, "PreEqualizationNoiseVariance", NaN)), ...
            "PreEqualizationNoiseVarianceDomain", string(sixgr.util.structGet(rec, "PreEqualizationNoiseVarianceDomain", "")), ...
            "PreEqualizationNoiseVarianceSource", string(sixgr.util.structGet(rec, "PreEqualizationNoiseVarianceSource", "")), ...
            "PostEqualizationNoiseVariance", double(sixgr.util.structGet(rec, "PostEqualizationNoiseVariance", NaN)), ...
            "PostEqualizationNoiseVarianceDomain", string(sixgr.util.structGet(rec, "PostEqualizationNoiseVarianceDomain", "")), ...
            "PostEqualizationNoiseVarianceSource", string(sixgr.util.structGet(rec, "PostEqualizationNoiseVarianceSource", "")), ...
            "StrictReceiverEvidenceOk", logical(sixgr.util.structGet(rec, "StrictReceiverEvidenceOk", false)));
        out.SIB1 = rec;
        if logical(p.Results.WriteArtifacts) && strlength(string(p.Results.RunFolder)) > 0
            tx.RunId = string(p.Results.RunId);
            out.SIB1Artifacts = sixgr.phy.broadcast.exportSIB1EvidenceArtifacts( ...
                string(p.Results.RunFolder), tx, rec, "NegativeResults", struct([]));
        end
        out.SSBIndex = double(rec.SSBIndex);
        out.SSBBeamIndex = out.SSBIndex + 1;
        out.SSBReceivedPower_dB = double(sixgr.util.structGet(rec, "SSBReceivedPower_dB", NaN));
        out.SS_RSRP_dBm = double(sixgr.util.structGet(rec, "SS_RSRP_dBm", NaN));
        out.SS_RSRPPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
            rec, "SS_RSRPPerReceiveAntenna_dBm", ""));
        out.SS_RSRPRawObserved_dBm = double(sixgr.util.structGet( ...
            rec, "SS_RSRPRawObserved_dBm", NaN));
        out.SS_RSRPRawObservedPerReceiveAntenna_dBm = string(sixgr.util.structGet( ...
            rec, "SS_RSRPRawObservedPerReceiveAntenna_dBm", ""));
        out.SS_SINR_dB = double(sixgr.util.structGet(rec, "SS_SINR_dB", NaN));
        out.SS_SINRPerReceiveAntenna_dB = string(sixgr.util.structGet( ...
            rec, "SS_SINRPerReceiveAntenna_dB", ""));
        out.SSMeasurementSource = string(sixgr.util.structGet( ...
            rec, "SSMeasurementSource", ""));
        out.SSSINRMeasurementMethod = string(sixgr.util.structGet( ...
            rec, "SSSINRMeasurementMethod", ""));
        out.SSSINRReferencePlane = string(sixgr.util.structGet( ...
            rec, "SSSINRReferencePlane", ""));
        out.SSSINRNoiseInterferencePowerPerReceiveAntenna_W = string( ...
            sixgr.util.structGet(rec, ...
            "SSSINRNoiseInterferencePowerPerReceiveAntenna_W", ""));
        out.SSSINRDesiredPowerPerReceiveAntenna_W = string( ...
            sixgr.util.structGet(rec, ...
            "SSSINRDesiredPowerPerReceiveAntenna_W", ""));
        out.SSSINRNoiseInterferenceRECount = double(sixgr.util.structGet( ...
            rec, "SSSINRNoiseInterferenceRECount", NaN));
        out.SSPhysicalMeasurementStatus = string(sixgr.util.structGet( ...
            rec, "SSPhysicalMeasurementStatus", "unavailable"));
        out.SSSINRFailureReason = string(sixgr.util.structGet( ...
            rec, "SSSINRFailureReason", ""));
        out.ReferenceSignalId = double(sixgr.util.structGet( ...
            rec, "ReferenceSignalId", NaN));
        out.ReferenceSignalTxEPRE_dBm = double(sixgr.util.structGet( ...
            rec, "ReferenceSignalTxEPRE_dBm", NaN));
        out.ReferenceSignalTxEPREPerAntenna_dBm = string(sixgr.util.structGet( ...
            rec, "ReferenceSignalTxEPREPerAntenna_dBm", ""));
        out.ReferenceSignalTxMeasurementSource = string(sixgr.util.structGet( ...
            rec, "ReferenceSignalTxMeasurementSource", ""));
        out.MeasuredReferenceSignalPathloss_dB = double(sixgr.util.structGet( ...
            rec, "MeasuredReferenceSignalPathloss_dB", NaN));
        out.MeasuredReferenceSignalPathlossSource = string(sixgr.util.structGet( ...
            rec, "MeasuredReferenceSignalPathlossSource", ""));
        out.PathlossReferenceRS = string(sixgr.util.structGet( ...
            rec, "PathlossReferenceRS", ""));
        out.PowerReferencePlane = string(sixgr.util.structGet( ...
            rec, "PowerReferencePlane", ""));
        out.PBCHDMRSMetric = double(sixgr.util.structGet(rec, "PBCHDMRSMetric", NaN));
        out.PSSMetric = double(sixgr.util.structGet(rec, "PSSMetric", NaN));
        out.SSSMetric = double(sixgr.util.structGet(rec, "SSSMetric", NaN));
        out.SSSMetricMargin = double(sixgr.util.structGet(rec, "SSSMetricMargin", NaN));
        out.PSSSearchSamples = double(sixgr.util.structGet(rec, "PSSSearchSamples", NaN));
        out.PSSTimingLagsEvaluated = double(sixgr.util.structGet(rec, "PSSTimingLagsEvaluated", NaN));
        out.PSSSequences = double(sixgr.util.structGet(rec, "PSSSequences", NaN));
        out.PSSCorrelationVectors = double(sixgr.util.structGet(rec, "PSSCorrelationVectors", NaN));
        out.SSSSequenceHypotheses = double(sixgr.util.structGet(rec, "SSSSequenceHypotheses", NaN));
        out.PBCHDMRSHypothesesTested = double(sixgr.util.structGet(rec, "PBCHDMRSHypothesesTested", NaN));
        out.PBCHNoiseVar = double(sixgr.util.structGet(rec, "PBCHNoiseVar", NaN));
        out.PreEqualizationNoiseVariance = double(sixgr.util.structGet(rec, "PreEqualizationNoiseVariance", NaN));
        out.PreEqualizationNoiseVarianceDomain = string(sixgr.util.structGet(rec, "PreEqualizationNoiseVarianceDomain", ""));
        out.PreEqualizationNoiseVarianceSource = string(sixgr.util.structGet(rec, "PreEqualizationNoiseVarianceSource", ""));
        out.ChannelEstimateAvailable = logical(sixgr.util.structGet(rec, "ChannelEstimateAvailable", false));
        out.ChannelEstimateSource = string(sixgr.util.structGet(rec, "ChannelEstimateSource", ""));
        out.EqualizationAvailable = logical(sixgr.util.structGet(rec, "EqualizationAvailable", false));
        out.EqualizerType = string(sixgr.util.structGet(rec, "EqualizerType", ""));
        out.ReceiverHestSINR_dB = double(sixgr.util.structGet(rec, "ReceiverHestSINR_dB", NaN));
        out.ReceiverHestSINRSource = string(sixgr.util.structGet(rec, "ReceiverHestSINRSource", ""));
        out.ReceiverHestSINRValueRole = string(sixgr.util.structGet(rec, "ReceiverHestSINRValueRole", ""));
        out.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(rec, "ReceiverHestSINRValueStatus", ""));
        out.ReceiverHestSINRNAReason = string(sixgr.util.structGet(rec, "ReceiverHestSINRNAReason", ""));
        out.MeasuredTrialSINR_dB = double(sixgr.util.structGet(rec, "MeasuredTrialSINR_dB", NaN));
        out.MeasuredTrialSINRSource = string(sixgr.util.structGet(rec, "MeasuredTrialSINRSource", ""));
        out.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(rec, "MeasuredTrialSINRValueRole", ""));
        out.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(rec, "MeasuredTrialSINRValueStatus", ""));
        out.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(rec, "MeasuredTrialSINRNAReason", ""));
        out.PostEqSINR_dB = double(sixgr.util.structGet(rec, "PostEqSINR_dB", NaN));
        out.PostEqSINRAvailable = logical(sixgr.util.structGet(rec, "PostEqSINRAvailable", false));
        out.PostEqSINRSource = string(sixgr.util.structGet(rec, "PostEqSINRSource", ""));
        out.PostEqSINRValueRole = string(sixgr.util.structGet(rec, "PostEqSINRValueRole", ""));
        out.PostEqSINRValueStatus = string(sixgr.util.structGet(rec, "PostEqSINRValueStatus", ""));
        out.PostEqSINRNAReason = string(sixgr.util.structGet(rec, "PostEqSINRNAReason", ""));
        out.PostEqualizationNoiseVariance = double(sixgr.util.structGet(rec, "PostEqualizationNoiseVariance", NaN));
        out.PostEqualizationNoiseVarianceDomain = string(sixgr.util.structGet(rec, "PostEqualizationNoiseVarianceDomain", ""));
        out.PostEqualizationNoiseVarianceSource = string(sixgr.util.structGet(rec, "PostEqualizationNoiseVarianceSource", ""));
        out.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(rec, "StrictReceiverEvidenceOk", false));
        out.SIB1PDSCHChannelEstimateAvailable = logical(sixgr.util.structGet(rec, "SIB1PDSCHChannelEstimateAvailable", false));
        out.SIB1PDSCHEqualizationAvailable = logical(sixgr.util.structGet(rec, "SIB1PDSCHEqualizationAvailable", false));
        out.SIB1PDSCHReceiverHestSINR_dB = double(sixgr.util.structGet(rec, "SIB1PDSCHReceiverHestSINR_dB", NaN));
        out.SIB1PDSCHReceiverHestSINRSource = string(sixgr.util.structGet(rec, "SIB1PDSCHReceiverHestSINRSource", ""));
        out.SIB1PDSCHStrictReceiverEvidenceOk = logical(sixgr.util.structGet(rec, "SIB1PDSCHStrictReceiverEvidenceOk", false));
        out.FreqOffsetEstimate_Hz = double(rec.FrequencyOffsetHz);
        out.TrueCFO_Hz = 0;
        out.CFOError_Hz = double(rec.FrequencyOffsetHz);
        out.TimingOffset_samples = double(rec.TimingOffset);
        out.RawTimingEstimate_samples = double(rec.TimingOffset);
        out.EstimatedTimingOffset_PreCorrection_samples = double(rec.TimingOffset);
        out.TrueTimingOffset_samples = NaN;
        out.TimingError_samples = NaN;
        out.TimingEstimateStatus = "estimated_ssb_position_no_injected_timing_reference";
        out.Notes = "Strict SIB1 waveform path: " + string(rec.Status) + ...
            "; DCI=" + string(rec.DCIPayloadHex) + ...
            "; SIB1TreeEqual=" + string(logical(rec.SIB1TreeEqual));
        candidateOutputs{candidateOrdinal} = out;
        end
        out = candidateOutputs{1};
        if ~isempty(p.Results.CandidateSSBIndices)
            out.CandidateResults = candidateOutputs;
            out.CandidateSSBIndices = candidateIndices;
        end
        return;
    catch ME
        out.Ok = false;
        out.BLER = 1;
        out.Skipped = false;
        out.Crash = true;
        out.Status = "CRASH";
        out.FailureIdentifier = string(ME.identifier);
        out.FailureReason = string(ME.identifier) + ":" + string(ME.message);
        out.Notes = "Strict SIB1 waveform failure: " + string(ME.message);
        if ~isempty(log)
            log.warn("runCellSearch_MIB_SIB1 strict SIB1 failed: " + string(ME.message));
        end
        return;
    end
end

try
    tStart = tic;
    ssbArgs = {"NumSubframes", numSF};
    if ~isempty(p.Results.SSBIndex)
        ssbArgs = [ssbArgs, {"SSBIndex", round(double(p.Results.SSBIndex))}]; %#ok<AGROW>
    end
    [txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfg, ssbArgs{:});
    sampleRateHz = localResolveSampleRate(txInfo, cfg);
    injectedCFO_Hz = localResolveInjectedCFOHz(cfg);
    injectedTimingOffset = localResolveInjectedTimingOffsetSamples(cfg);
    rxWaveRaw = localApplyCellSearchImpairments(txWave, sampleRateHz, injectedCFO_Hz, injectedTimingOffset);
    estimatedCFO_PreCorrection_Hz = localEstimateWaveformCFO(txWave, rxWaveRaw, sampleRateHz, injectedTimingOffset);
    rxWave = localApplyCFOCorrection(rxWaveRaw, sampleRateHz, estimatedCFO_PreCorrection_Hz);
    out.DetectionAttempted = true;
    out.MeasurementAttempted = true;
    rxArgs = {"SampleRate_Hz", sampleRateHz};
    if ~isempty(p.Results.SSBIndex)
        % A sweep measurement is time-gated to its configured SS/PBCH
        % candidate occasion.  Ordinary acquisition leaves this empty and
        % retains the fully blind search across the entire burst set.
        rxArgs = [rxArgs, {"CandidateSSBIndex", ...
            round(double(p.Results.SSBIndex))}]; %#ok<AGROW>
    end
    [rxSSB, sync] = sixgr.phy.dl.SSB_Rx(rxWave, cfg, rxArgs{:});
    out.PSSDetected = logical(sixgr.util.structGet(sync, "PSSDetected", false));
    out.SSSDetected = logical(sixgr.util.structGet(sync, "SSSDetected", false));
    out.NCellIDRecovered = logical(sixgr.util.structGet(sync, "NCellIDRecovered", false));
    out.PSSDetectionSource = string(sixgr.util.structGet(sync, "PSSDetectionSource", ""));
    out.SSSDetectionSource = string(sixgr.util.structGet(sync, "SSSDetectionSource", ""));
    out.ResourceExtractionAttempted = true;
    out.ChannelEstimateAttempted = true;
    out.EqualizationAttempted = true;
    out.DecodeAttempted = true;
    [pb, pbchInfo] = sixgr.phy.dl.PBCH_Recovery(rxSSB, sync, cfg);
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = NaN;
    out.AirInterfaceObservation_ms = double(numSF);
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.Sync = sync;
    out.PBCH = pb;
    out.SSBIndex = double(sixgr.util.structGet(pb, "SSBIndex", sixgr.util.structGet(txInfo, "SSB.SSBIndex", NaN)));
    out.SSBBeamIndex = out.SSBIndex + 1;
    out.SSBReceivedPower_dB = localGridMeanPowerDb(rxSSB);
    out.PBCHDMRSMetric = double(sixgr.util.structGet(pbchInfo, "Selected.metric", NaN));
    out.PSSMetric = double(sixgr.util.structGet(sync, "FreqInfo.Metric", NaN));
    out.SSSMetric = double(sixgr.util.structGet(sync, "SSSInfo.Metric", NaN));
    out.SSSMetricMargin = double(sixgr.util.structGet(sync, "SSSInfo.MetricMargin", NaN));
    out.PSSSearchSamples = double(sixgr.util.structGet(sync, "FreqInfo.SearchSamples", NaN));
    out.PSSTimingLagsEvaluated = double(sixgr.util.structGet(sync, "FreqInfo.TimingLagsEvaluated", NaN));
    out.PSSSequences = double(sixgr.util.structGet(sync, "FreqInfo.PSSSequences", NaN));
    out.PSSCorrelationVectors = double(sixgr.util.structGet(sync, "FreqInfo.PSSCorrelationVectors", NaN));
    out.SSSSequenceHypotheses = double(sixgr.util.structGet(sync, "SSSInfo.SearchSpaceSize", NaN));
    out.PBCHDMRSHypothesesTested = double(numel(sixgr.util.structGet(pbchInfo, "PerCandidate", struct([]))));
    out.PBCHNoiseVar = double(sixgr.util.structGet(pb, "NoiseVar", NaN));
    out.PreEqualizationNoiseVariance = double(sixgr.util.structGet(pb, "PreEqualizationNoiseVariance", NaN));
    out.PreEqualizationNoiseVarianceDomain = string(sixgr.util.structGet(pb, "PreEqualizationNoiseVarianceDomain", ""));
    out.PreEqualizationNoiseVarianceSource = string(sixgr.util.structGet(pb, "PreEqualizationNoiseVarianceSource", ""));
    out.ChannelEstimateAvailable = logical(sixgr.util.structGet(pb, "ChannelEstimateAvailable", false));
    out.ChannelEstimateSource = string(sixgr.util.structGet(pb, "ChannelEstimateSource", ""));
    out.EqualizationAvailable = logical(sixgr.util.structGet(pb, "EqualizationAvailable", false));
    out.EqualizerType = string(sixgr.util.structGet(pb, "EqualizerType", ""));
    out.ReceiverHestSINR_dB = double(sixgr.util.structGet(pb, "ReceiverHestSINR_dB", NaN));
    out.ReceiverHestSINRSource = string(sixgr.util.structGet(pb, "ReceiverHestSINRSource", ""));
    out.ReceiverHestSINRValueRole = string(sixgr.util.structGet(pb, "ReceiverHestSINRValueRole", ""));
    out.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(pb, "ReceiverHestSINRValueStatus", ""));
    out.ReceiverHestSINRNAReason = string(sixgr.util.structGet(pb, "ReceiverHestSINRNAReason", ""));
    out.MeasuredTrialSINR_dB = double(sixgr.util.structGet(pb, "MeasuredTrialSINR_dB", NaN));
    out.MeasuredTrialSINRSource = string(sixgr.util.structGet(pb, "MeasuredTrialSINRSource", ""));
    out.MeasuredTrialSINRValueRole = string(sixgr.util.structGet(pb, "MeasuredTrialSINRValueRole", ""));
    out.MeasuredTrialSINRValueStatus = string(sixgr.util.structGet(pb, "MeasuredTrialSINRValueStatus", ""));
    out.MeasuredTrialSINRNAReason = string(sixgr.util.structGet(pb, "MeasuredTrialSINRNAReason", ""));
    out.PostEqSINR_dB = double(sixgr.util.structGet(pb, "PostEqSINR_dB", NaN));
    out.PostEqSINRAvailable = logical(sixgr.util.structGet(pb, "PostEqSINRAvailable", false));
    out.PostEqSINRSource = string(sixgr.util.structGet(pb, "PostEqSINRSource", ""));
    out.PostEqSINRValueRole = string(sixgr.util.structGet(pb, "PostEqSINRValueRole", ""));
    out.PostEqSINRValueStatus = string(sixgr.util.structGet(pb, "PostEqSINRValueStatus", ""));
    out.PostEqSINRNAReason = string(sixgr.util.structGet(pb, "PostEqSINRNAReason", ""));
    out.PostEqualizationNoiseVariance = double(sixgr.util.structGet(pb, "PostEqualizationNoiseVariance", NaN));
    out.PostEqualizationNoiseVarianceDomain = string(sixgr.util.structGet(pb, "PostEqualizationNoiseVarianceDomain", ""));
    out.PostEqualizationNoiseVarianceSource = string(sixgr.util.structGet(pb, "PostEqualizationNoiseVarianceSource", ""));
    out.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(pb, "StrictReceiverEvidenceOk", false));
    out.LLRAvailable = logical(sixgr.util.structGet(pb, "PBCHDecodeAvailable", false));
    out.LLRFinite = out.LLRAvailable && isfinite(double(sixgr.util.structGet(pb, "NoiseVar", NaN)));

    out.Ok = logical(pb.Ok) && (double(pb.ErrFlag) == 0);
    if out.Ok
        out.Status = "PASS";
        out.FailureReason = "";
    else
        out.Status = "FAIL";
        out.FailureReason = "pbch_bch_crc_failed";
    end
    out.BLER = double(~out.Ok);
    out.InjectedCFO_Hz = injectedCFO_Hz;
    out.EstimatedCFO_PreCorrection_Hz = estimatedCFO_PreCorrection_Hz;
    out.ResidualCFO_PostCorrection_Hz = localEstimateWaveformCFO(txWave, rxWave, sampleRateHz, injectedTimingOffset);
    out.InjectedTimingOffset_samples = injectedTimingOffset;
    out.RawTimingEstimate_samples = double(sixgr.util.structGet(sync, "RawTimingEstimate_samples", ...
        sixgr.util.structGet(sync, "TimingOffset", NaN)));
    out.AppliedTimingCorrection_samples = double(sixgr.util.structGet(sync, "AppliedTimingCorrection_samples", NaN));
    out.TimingEstimateApplicationPolicy = string(sixgr.util.structGet(sync, "TimingEstimateApplicationPolicy", ""));
    out.TimingEstimateStatus = string(sixgr.util.structGet(sync, "TimingEstimateStatus", ""));
    out.TimingEstimateWasClipped = logical(sixgr.util.structGet(sync, "TimingEstimateWasClipped", false));
    out.EstimatedTimingOffset_PreCorrection_samples = out.RawTimingEstimate_samples;
    out.ResidualTimingError_PostCorrection_samples = localResidualTimingAfterSync(rxWave, sync, cfg, sampleRateHz);

    % Legacy aliases kept for backward compatibility with existing reports.
    out.FreqOffsetEstimate_Hz = out.EstimatedCFO_PreCorrection_Hz;
    out.TrueCFO_Hz = out.InjectedCFO_Hz;
    out.CFOError_Hz = out.ResidualCFO_PostCorrection_Hz;
    out.TimingOffset_samples = out.RawTimingEstimate_samples;
    out.TrueTimingOffset_samples = out.InjectedTimingOffset_samples;
    out.TimingError_samples = out.ResidualTimingError_PostCorrection_samples;
    out.Notes = "NCellID=" + string(pb.NCellID) + ...
        ", SSBIdx=" + string(pb.SSBIndex) + ...
        ", injected CFO=" + string(round(out.InjectedCFO_Hz, 3)) + " Hz" + ...
        ", residual CFO=" + string(round(out.ResidualCFO_PostCorrection_Hz, 3)) + " Hz";

    % Optional consolidated wrapper (best-effort).
    try
        rec = sixgr.phy.rrc.MIB_SIB1_Recovery(txWave, cfg, "SampleRate_Hz", txInfo.SampleRate_Hz); %#ok<NASGU>
    catch
    end
catch ME
    msg = string(ME.message);
    if contains(msg, "Too many output arguments")
        sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnsupported", ...
            "Strict mode forbids skipping CellSearch_MIB_SIB1 coverage due to release API mismatch: " + msg);
        out.Skipped = true;
        out.Ok = true;
        out.Status = "SKIPPED";
        out.FailureIdentifier = string(ME.identifier);
        out.FailureReason = "release_api_mismatch:" + msg;
        out.Notes = "Skipped: release API mismatch (" + msg + ")";
    else
        out.Ok = false;
        out.Crash = true;
        out.Status = "CRASH";
        out.FailureIdentifier = string(ME.identifier);
        out.FailureReason = string(ME.identifier) + ":" + msg;
        out.Notes = "Failure: " + msg;
    end
    if ~isempty(log)
        log.warn("runCellSearch_MIB_SIB1 failed: " + string(ME.message));
    end
end

function evidence = localBuildSSBTxEvidence(tx)
burstPlan = sixgr.util.structGet(tx, "SSBBurstPlan", struct());
composite = sixgr.util.structGet(tx, "SSBComposite", struct());
activeIndices = double(sixgr.util.structGet( ...
    burstPlan, "ActiveSSBIndices0Based", ...
    sixgr.util.structGet(composite, "ActiveSSBIndices0Based", [])));
precoderIDs = string(sixgr.util.structGet(burstPlan, "PrecoderIDs", strings(0, 1)));
precoderHashes = string(sixgr.util.structGet( ...
    burstPlan, "PrecoderMatrixSHA256", ...
    sixgr.util.structGet(composite, "PrecoderMatrixSHA256", strings(0, 1))));
physicalElements = double(sixgr.util.structGet( ...
    burstPlan, "NumTransmitAntennas", ...
    sixgr.util.structGet(composite, "PhysicalTransmitAntennaElements", NaN)));
waveformPorts = size(sixgr.util.structGet(tx, "SSBWaveform", zeros(0, 0)), 2);
componentCount = double(sixgr.util.structGet(composite, "ComponentCount", NaN));
if ~(isfinite(componentCount) && componentCount == numel(activeIndices))
    error("sixgr:link:SSBBurstEvidenceMismatch", ...
        "SSB component count %.15g does not match %d active SSB indices.", ...
        componentCount, numel(activeIndices));
end
waveformDomain = string(sixgr.util.structGet( ...
    composite, "WaveformDomain", ...
    sixgr.util.structGet(sixgr.util.structGet(tx, "SSBInfo", struct()), ...
    "WaveformDomain", "")));
if waveformDomain == "physical_element_domain" && ...
        isfinite(physicalElements) && waveformPorts ~= physicalElements
    error("sixgr:link:SSBPhysicalPortMismatch", ...
        "Physical-element-domain SSB waveform has %d ports but burst plan declares %d antenna elements.", ...
        waveformPorts, round(physicalElements));
end
evidence = struct( ...
    "ActiveSSBIndices0Based", activeIndices, ...
    "ConfiguredBeamCount", double(sixgr.util.structGet(burstPlan, "Lmax", numel(activeIndices))), ...
    "ExecutedBeamCount", double(componentCount), ...
    "PrecoderIDs", precoderIDs, ...
    "PrecoderMatrixSHA256", precoderHashes, ...
    "BurstPlanSHA256", string(sixgr.util.structGet(burstPlan, "PlanSHA256", "")), ...
    "WaveformDomain", waveformDomain, ...
    "WaveformPorts", double(waveformPorts), ...
    "PhysicalTransmitAntennaElements", physicalElements, ...
    "BeamformingApplied", logical(any(strlength(precoderHashes) > 0)), ...
    "ExplicitBeamWeightsApplied", logical(any(strlength(precoderHashes) > 0)), ...
    "Source", "sixgr.phy.dl.SSB_Tx:SSBBurstPlan");
end
end

function value = localGridMeanPowerDb(grid)
value = NaN;
if isempty(grid)
    return;
end
samples = grid(:);
samples = samples(isfinite(real(samples)) & isfinite(imag(samples)));
if isempty(samples)
    return;
end
powerLin = mean(abs(samples).^2, "omitnan");
if isfinite(powerLin) && powerLin > 0
    value = 10 * log10(powerLin);
end
end

function measurement = localMeasureTransmitSSBEPRE( ...
        txWaveform, cfg, sampleRateHz, ssbIndex)
measurement = struct( ...
    "Available", false, ...
    "AggregateEPRE_dBm", NaN, ...
    "PerTransmitPortEPREToken_dBm", "", ...
    "Source", "unavailable_exact_tx_sss_epre", ...
    "FailureReason", "");
if isempty(txWaveform) || ~(isscalar(sampleRateHz) && ...
        isfinite(sampleRateHz) && sampleRateHz > 0) || ...
        ~(isscalar(ssbIndex) && isfinite(ssbIndex) && ...
        ssbIndex >= 0 && ssbIndex == fix(ssbIndex))
    measurement.FailureReason = ...
        "missing_waveform_sample_rate_or_recovered_ssb_index";
    return;
end
try
    [txSSBGrid, sync] = sixgr.phy.dl.SSB_Rx(txWaveform, cfg, ...
        "SampleRate_Hz", sampleRateHz, ...
        "CandidateSSBIndex", ssbIndex);
    nfft = double(sixgr.util.structGet(sync, "Nfft", NaN));
    if ~(isscalar(nfft) && isfinite(nfft) && nfft >= 1)
        error("sixgr:link:SSBTxEPREFFTSizeUnavailable", ...
            "Exact Tx SSS EPRE requires the SSB OFDM FFT size.");
    end
    physicalGrid = txSSBGrid ./ cast(nfft * sqrt(1000), "like", txSSBGrid);
    sssIndices = nrSSSIndices;
    nTx = size(physicalGrid, 3);
    eprePerPort_W = nan(1, nTx);
    for txIdx = 1:nTx
        branch = double(physicalGrid(:, :, txIdx));
        eprePerPort_W(txIdx) = mean(abs(branch(sssIndices)).^2, "omitnan");
    end
    valid = isfinite(eprePerPort_W) & eprePerPort_W > 0;
    if ~any(valid)
        error("sixgr:link:SSBTxEPREUnavailable", ...
            "No transmit port contains finite positive SSS EPRE.");
    end
    perPort_dBm = nan(size(eprePerPort_W));
    perPort_dBm(valid) = 10 * log10(eprePerPort_W(valid)) + 30;
    measurement.Available = true;
    measurement.AggregateEPRE_dBm = ...
        10 * log10(sum(eprePerPort_W(valid))) + 30;
    measurement.PerTransmitPortEPREToken_dBm = ...
        localNumericVectorToken(perPort_dBm);
    measurement.Source = ...
        "exact_generated_power_context_waveform_sss_re_epre_linear_sum_tx_ports";
catch ME
    measurement.FailureReason = string(ME.identifier) + ":" + string(ME.message);
end
end

function token = localNumericVectorToken(values)
values = reshape(double(values), 1, []);
token = "[" + strjoin(string(compose("%.15g", values)), ",") + "]";
end

function cfgOut = localSanitizeSIB1PrecodingConfig(cfgIn)
cfgOut = cfgIn;
% SI-RNTI SIB1 is a common, single-layer broadcast allocation.  The
% scenario data-PDSCH rank and immutable UE-specific precoder are not part
% of that allocation's context.  Establish the broadcast context before
% Type-0/PDSCH materialization so a rank-2 data matrix cannot become a
% stale explicit matrix after deriveType0PDCCHFromMIB sets NumLayers=1.
nLayers = 1;
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", nLayers);
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
for i = 1:numel(paths)
    cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
end
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.enabled", false);
cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.mode", ...
    "broadcast_single_port");
end

function durationMs = localResolvePBCHObservationDurationMs(cfg)
durationMs = double(sixgr.util.structGet(cfg, "phy.sib1.ssbObservationSubframes", ...
    sixgr.util.structGet(cfg, "phy.ssb.pbchObservationSubframes", 5)));
durationMs = max(1, round(durationMs));
end

function sampleRateHz = localResolveSampleRate(txInfo, cfg)
sampleRateHz = sixgr.util.structGet(txInfo, "SampleRate_Hz", []);
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
if isempty(sampleRateHz)
    error("sixgr:link:CellSearchSampleRateMissing", ...
        "Cell-search tracking semantics require a known sample rate.");
end
sampleRateHz = double(sampleRateHz);
end

function cfoHz = localResolveInjectedCFOHz(cfg)
cfoHz = double(sixgr.util.structGet(cfg, "phy.impairments.cfoHz", ...
    sixgr.util.structGet(cfg, "impairments.cfo_hz", 0)));
if ~isfinite(cfoHz)
    cfoHz = 0;
end
end

function timingOffset = localResolveInjectedTimingOffsetSamples(cfg)
timingOffset = double(sixgr.util.structGet(cfg, "phy.impairments.timingOffsetSamples", ...
    sixgr.util.structGet(cfg, "impairments.timing_offset_samples", 0)));
if ~isfinite(timingOffset)
    timingOffset = 0;
end
end

function y = localApplyCellSearchImpairments(x, sampleRateHz, cfoHz, timingOffset)
y = x;
if isfinite(timingOffset) && timingOffset ~= 0
    y = sixgr.util.applyFractionalSampleDelay(y, timingOffset);
end
if sampleRateHz > 0 && isfinite(cfoHz) && cfoHz ~= 0
    n = (0:size(y, 1)-1).';
    rot = exp(1j * 2 * pi * (cfoHz / sampleRateHz) * n);
    y = y .* rot;
end
end

function y = localApplyCFOCorrection(x, sampleRateHz, estCFO_Hz)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(estCFO_Hz) && estCFO_Hz ~= 0)
    return;
end
n = (0:size(y, 1)-1).';
rot = exp(-1j * 2 * pi * (estCFO_Hz / sampleRateHz) * n);
y = y .* rot;
end

function ncellid = localConfiguredNCellID(cfg)
ncellid = sixgr.util.structGet(cfg, "phy.carrier.NCellID", []);
if isempty(ncellid)
    ncellid = sixgr.util.structGet(cfg, "phy.NCellID", []);
end
if isempty(ncellid)
    return;
end
ncellid = double(ncellid);
if ~(isscalar(ncellid) && isfinite(ncellid) && ncellid >= 0)
    ncellid = [];
else
    ncellid = round(ncellid);
end
end

function estCFO_Hz = localEstimateWaveformCFO(txWave, rxWave, sampleRateHz, timingOffset)
estCFO_Hz = NaN;
if isempty(txWave) || isempty(rxWave) || ~(isfinite(sampleRateHz) && sampleRateHz > 0)
    return;
end
txRef = txWave(:, 1);
rxRef = rxWave(:, 1);
if timingOffset > 0
    startRx = 1 + timingOffset;
    if startRx > numel(rxRef)
        estCFO_Hz = 0;
        return;
    end
    rxRef = rxRef(startRx:end);
elseif timingOffset < 0
    startTx = 1 + abs(timingOffset);
    if startTx > numel(txRef)
        estCFO_Hz = 0;
        return;
    end
    txRef = txRef(startTx:end);
end
N = min(numel(txRef), numel(rxRef));
if N < 32
    estCFO_Hz = 0;
    return;
end
txRef = txRef(1:N);
rxRef = rxRef(1:N);
mask = isfinite(real(txRef)) & isfinite(imag(txRef)) & isfinite(real(rxRef)) & isfinite(imag(rxRef));
mask = mask & (abs(txRef) > max(abs(txRef), [], "omitnan") * 0.05);
if nnz(mask) < 32
    estCFO_Hz = 0;
    return;
end
sampleIdx = find(mask);
phaseObs = unwrap(angle(rxRef(mask) .* conj(txRef(mask))));
p = polyfit(double(sampleIdx(:)) / sampleRateHz, phaseObs(:), 1);
estCFO_Hz = p(1) / (2 * pi);
end

function residualTiming = localResidualTimingAfterSync(rxWaveCfoCorrected, sync, cfg, sampleRateHz)
residualTiming = NaN;
appliedTiming = double(sixgr.util.structGet(sync, "AppliedTimingCorrection_samples", 0));
startIdx = 1 + max(0, round(appliedTiming));
if startIdx > size(rxWaveCfoCorrected, 1)
    residualTiming = 0;
    return;
end
rxSync = rxWaveCfoCorrected(startIdx:end, :);
blockPattern = char(sixgr.util.structGet(cfg, 'phy.ssb.blockPattern', 'Case B'));
nid2 = double(sixgr.util.structGet(sync, "NID2", mod(double(sixgr.util.structGet(sync, "NCellID", 1)), 3)));
try
    [residualTiming, ~] = sixgr.phy.sync.timingEstimate(rxSync, nid2, blockPattern, sampleRateHz);
catch
    residualTiming = NaN;
end
if ~isfinite(residualTiming)
    residualTiming = 0;
end
end
