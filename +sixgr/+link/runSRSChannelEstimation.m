function out = runSRSChannelEstimation(cfg, varargin)
%RUNSRSCHANNELESTIMATION SRS Tx/Rx channel-estimation smoke case.

p = inputParser;
p.addParameter("Logger", [], @(x) isempty(x) || isa(x,"sixgr.core.Logger"));
p.addParameter("SNR_dB", sixgr.util.structGet(cfg, "channel.snr_dB", 20), @(x) isnumeric(x) && isscalar(x));
p.addParameter("ChannelState", [], @(x) isempty(x) || isstruct(x));
p.addParameter("TrialIndex", 1, @(x) isnumeric(x) && isscalar(x));
p.addParameter("SlotIndex", NaN, @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
log = p.Results.Logger;
snr_dB = double(p.Results.SNR_dB);
trialIdx = max(1, round(double(p.Results.TrialIndex)));
slotIdx = double(p.Results.SlotIndex);

out = struct();
out.Ok = false;
out.Skipped = false;
out.BER = NaN;
out.BLER = NaN;
out.Throughput_Mbps = NaN;
out.EVM_rms = NaN;
out.Notes = "";
out.NMSE_dB = NaN;
out.NMSEReferenceSource = "";
out.TrueChannelOracleAvailable = false;
out.TrueChannelNMSE_dB = NaN;
out.ChannelNMSEThreshold_dB = NaN;
out.InterpolationLoss_dB = NaN;
out.MismatchSensitivity_dB = NaN;
out.QCLAccuracy = NaN;
out.ComputeLatency_ms = NaN;
out.ProcedureDelay_ms = 0;
out.AirInterfaceObservation_ms = NaN;
out.AcquisitionTime_ms = NaN;
out.TrackingFailure = 1;
out.NoiseVariance = NaN;
out.NoiseVarianceSource = "";
out.SignalEnergyPerOccupiedRE = NaN;
out.ReferenceAWGNGridNoiseVariance = NaN;
out.ReferenceAWGNSampleNoiseVariance = NaN;
out.SampleToGridNoiseVarianceGain = NaN;
out.SNRReferencePlane = "";
out.AppliedNoiseSNR_dB = NaN;
out.WaveformPowerUsedForAWGN = false;
out.NoiseVarStatus = "";
out.NoiseVarSource = "";
out.NoiseVarReason = "";
out.NoiseVarStrictFailure = false;
out.ChannelEstimateUsable = false;
out.DetectionAttempted = false;
out.DetectionSuccess = false;
out.DetectionUsable = false;
out.ResourceExtractionAttempted = false;
out.ResourceExtractionAvailable = false;
out.ChannelEstimateAttempted = false;
out.ChannelEstimateAvailable = false;
out.SRSChannelEstimateAvailable = false;
out.StrictReceiverEvidenceOk = false;
out.StrictOk = false;
out.SRSRuntimeEvidenceUsable = false;
out.ConfiguredSNR_dB = double(snr_dB);
out.AppliedAWGNSNR_dB = NaN;
out.NoiseOperatingMode = "";
out.NoisePowerSource = "";
out.ThermalNoisePower_dBm = NaN;
out.ServingRxPower_dBm = NaN;
out.ServingRxPowerSource = "";
out.PowerContextDirection = "";
out.PowerContextTotalTxPower_dBm = NaN;
out.SRSPowerControlAppliedPower_dBm = NaN;
out.SRSPowerControlRequestedPower_dBm = NaN;
out.SRSPowerControlPathlossSource = "";
out.SRSPowerControlClipped = false;
out.TxRFExecutionStatus = "";
out.TxRFStageOrder = "";
out.TxRFAppliedStageCount = NaN;
out.CompositeReceiverFrontEndApplied = false;
out.CompositeReceiverFrontEndStatus = "";
out.RuntimeChannelStateUsed = false;
out.RuntimeChannelLinkKeys = "";
out.RuntimeNoiseApplied = false;
out.RuntimeNoiseVarianceMean = NaN;
out.RuntimeStageCount = 5;
out.AppliedLargeScaleGain_dB = NaN;
out.AppliedLargeScaleLoss_dB = NaN;
out.AppliedBasePathloss_dB = NaN;
out.AppliedPathloss_dB = NaN;
out.AppliedShadowFading_dB = NaN;
out.AppliedO2I_dB = NaN;
out.AppliedLargeScaleGainSource = "";
out.InjectedCFO_Hz = NaN;
out.InjectedTimingOffset_samples = NaN;
out.ChannelModelApplied = "";
out.ChannelFadingApplied = false;
out.MeasurementAttempted = false;
out.MeasurementUsable = false;
out.FailureReason = "";
out.InjectedDoppler_Hz = NaN;
out.EstimatedDopplerHz = NaN;
out.DopplerError_Hz = NaN;
out.DopplerEstimateCRLB_Hz = NaN;
out.EstimatedRI = NaN;
out.EstimatedTPMI = NaN;
out.RankEstimate = NaN;
out.RIEstimate = NaN;
out.TPMIEstimate = NaN;
out.SINR_dB = NaN;
out.SINRSource = "";
out.SINRValueStatus = "";
out.SINRMeasurementDomain = "";
out.PowerReferencePlane = "";
out.CQI = NaN;
out.CQISource = "";
out.CQIValueStatus = "";
out.MCSIndex = NaN;
out.Modulation = "";
out.TargetCodeRate = NaN;
out.RISource = "";
out.TPMISource = "";
out.TPMICandidateCount = NaN;
out.TPMIMutualInformation = NaN;
out.PredictedPUSCHPostEqSINRPerLayer_dB = [];
out.PredictedPUSCHMinimumLayerSINR_dB = NaN;
out.PredictedPUSCHWidebandMeanSINR_dB = NaN;
out.PredictedPUSCHPostEqSINRSource = "";
out.PredictedPUSCHPostEqSINRValueRole = "";
out.PredictedPUSCHPostEqSINRValueStatus = "NOT_AVAILABLE";
out.SRSConditionNumber_dB = NaN;
out.SRSOccupiedPRBCount = NaN;
out.SRSCarrierPRBCount = NaN;
out.SRSBandwidthFraction = NaN;
out.SRSFrequencyPRBStart = NaN;
out.SRSFrequencyPRBEnd = NaN;
out.SRSBandwidthCoverageStatus = "";
out.SpatialSignatureToken = "";
out.SpatialSignatureSHA256 = "";
out.SpatialSignatureRows = NaN;
out.SpatialSignatureColumns = NaN;
out.SpatialSignatureSource = "";
out.SpatialSignatureRawRank = NaN;
out.SpatialSignatureRetainedRank = NaN;
out.SpatialSignatureDetectionThreshold = NaN;
out.SpatialSignatureNoiseVariance = NaN;
out.SpatialSignatureNoiseMargin_dB = NaN;
out.SpatialSignatureSnapshotCount = NaN;
out.SpatialSignatureReductionMode = "";
out.ChannelState = p.Results.ChannelState;
out.ObservedREAllocationTable = table();

configuredSRS = logical(sixgr.util.structGet(cfg, "phy.srs.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "srs", configuredSRS, ...
    "runSRSChannelEstimation");
if ~configuredSRS
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageDisabled", ...
        "Strict mode requires phy.srs.enable=true for SRS coverage.");
    out.Skipped = true;
    out.Ok = false;
    out.Notes = "Skipped: cfg.phy.srs.enable=false";
    out.FailureReason = "srs_disabled_fail_closed";
    return;
end

if exist("nrSRS", "file") ~= 2 || exist("nrSRSIndices", "file") ~= 2
    sixgr.link.failIfStrictCoverageGap(cfg, "sixgr:link:StrictCoverageUnavailable", ...
        "Strict mode requires nrSRS/nrSRSIndices for SRS coverage.");
    out.Skipped = true;
    out.Ok = false;
    out.Notes = "Skipped: nrSRS APIs unavailable.";
    out.FailureReason = "srs_toolbox_unavailable_fail_closed";
    return;
end

try
    tStart = tic;
    [cfgSRS, srsCfg] = localBindRuntimeSRSConfig(cfg, slotIdx);
    [tx, info] = sixgr.phy.ul.SRS_Tx(cfgSRS, ...
        "Carrier", srsCfg.ToolboxCarrier, ...
        "SRS", srsCfg.ToolboxSRS);
    observedSlot0 = double(tx.Carrier.NSlot);
    if isfinite(slotIdx) && slotIdx >= 1
        observedSlot0 = round(slotIdx) - 1;
    end
    out.ObservedREAllocationTable = sixgr.truth.buildObservedREAllocation(tx, ...
        "Direction", "UL", "Channel", "SRS", ...
        "AbsoluteSlot", observedSlot0, ...
        "CellID", double(tx.Carrier.NCellID), ...
        "UEID", double(sixgr.util.structGet(cfgSRS, "lls6g.userContext.UEIndex", ...
            sixgr.util.structGet(cfgSRS, "phy.ueId", NaN))), ...
        "AllocationID", "srs_slot_" + string(observedSlot0));
    srsCoverage = sixgr.phy.srs.computeSRSCoverage( ...
        srsCfg.ToolboxCarrier, srsCfg.ToolboxSRS, tx.SRSIndices, srsCfg);
    out.SRSOccupiedPRBCount = double(srsCoverage.OccupiedPRBCount);
    out.SRSCarrierPRBCount = double(srsCoverage.CarrierPRBCount);
    out.SRSBandwidthFraction = double(srsCoverage.CoveragePercent) / 100;
    out.SRSFrequencyPRBStart = double(srsCoverage.PRBStart);
    out.SRSFrequencyPRBEnd = double(srsCoverage.PRBEnd);
    out.SRSBandwidthCoverageStatus = char(string(srsCoverage.BandwidthCoverageStatus));
    sampleRateHz = localResolveSampleRate(info, tx, cfg);
    injectedDopplerHz = localResolveInjectedDopplerHz(cfg);
    rng(localTrialSeed(cfg, trialIdx), "twister");
    [rxWave, injectedNoiseVariance, replay, txWaveForReference, chState] = ...
        localApplySRSChannelAndNoise(tx.Waveform, cfgSRS, tx, info, sampleRateHz, injectedDopplerHz, snr_dB, p.Results.ChannelState, trialIdx);
    out.ChannelState = chState;
    out.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
    out.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
    out.NoiseOperatingMode = char(string(sixgr.util.structGet(replay, "NoiseOperatingMode", "")));
    out.NoisePowerSource = char(string(sixgr.util.structGet(replay, "NoisePowerSource", "")));
    out.ThermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
    out.ServingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
    out.ServingRxPowerSource = char(string(sixgr.util.structGet(replay, "ServingRxPowerSource", "")));
    out.PowerContextDirection = char(string(sixgr.util.structGet(replay, "PowerContextDirection", "")));
    out.PowerContextTotalTxPower_dBm = double(sixgr.util.structGet(replay, "PowerContextTotalTxPower_dBm", NaN));
    out.SRSPowerControlAppliedPower_dBm = double(sixgr.util.structGet( ...
        replay,"SRSPowerControl.AppliedPower_dBm",NaN));
    out.SRSPowerControlRequestedPower_dBm = double(sixgr.util.structGet( ...
        replay,"SRSPowerControl.RequestedPower_dBm",NaN));
    out.SRSPowerControlPathlossSource = char(string(sixgr.util.structGet( ...
        replay,"SRSPowerControl.PathlossSource","")));
    out.SRSPowerControlClipped = logical(sixgr.util.structGet( ...
        replay,"SRSPowerControl.Clipped",false));
    out.TxRFExecutionStatus = char(string(sixgr.util.structGet( ...
        replay,"TxRFExecutionStatus","")));
    out.TxRFStageOrder = char(string(sixgr.util.structGet( ...
        replay,"TxRFStageOrder","")));
    out.TxRFAppliedStageCount = double(sixgr.util.structGet( ...
        replay,"TxRFAppliedStageCount",NaN));
    out.CompositeReceiverFrontEndApplied = logical(sixgr.util.structGet( ...
        replay,"CompositeReceiverFrontEndApplied",false));
    out.CompositeReceiverFrontEndStatus = char(string(sixgr.util.structGet( ...
        replay,"CompositeReceiverFrontEndStatus","")));
    out.RuntimeChannelStateUsed = logical(sixgr.util.structGet( ...
        replay,"RuntimeChannelStateUsed",false));
    out.RuntimeChannelLinkKeys = char(string(sixgr.util.structGet( ...
        replay,"RuntimeChannelLinkKey","")));
    out.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
    out.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
    out.AppliedBasePathloss_dB = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
    out.AppliedPathloss_dB = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
    out.AppliedShadowFading_dB = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
    out.AppliedO2I_dB = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
    out.AppliedLargeScaleGainSource = char(string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", "")));
    out.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
    out.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", NaN));
    out.ChannelModelApplied = char(string(sixgr.util.structGet(replay, "ChannelModelApplied", "")));
    out.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
    strictNoiseVarianceRequired = ~localThermalNoiseSINRUnavailable(replay);
    noiseVarArgs = {};
    if isnumeric(injectedNoiseVariance) && isscalar(injectedNoiseVariance) && ...
            isfinite(double(injectedNoiseVariance)) && double(injectedNoiseVariance) >= 0
        noiseVarArgs = {"NoiseVar", double(injectedNoiseVariance), ...
            "NoiseVarDomain", "time"};
    end
    [rx, ~] = sixgr.phy.ul.SRS_Rx(rxWave, cfgSRS, ...
        "Carrier", tx.Carrier, ...
        "SRS", tx.SRS, ...
        noiseVarArgs{:}, ...
        "StrictNoiseVarianceRequired", strictNoiseVarianceRequired);
    out.NoiseVariance = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
    out.RuntimeNoiseApplied = isfinite(out.NoiseVariance) && out.NoiseVariance > 0;
    out.RuntimeNoiseVarianceMean = out.NoiseVariance;
    out.NoiseVarStatus = char(string(sixgr.util.structGet(rx, "NoiseVarStatus", "")));
    out.NoiseVarSource = char(string(sixgr.util.structGet(rx, "NoiseVarSource", "")));
    out.NoiseVarReason = char(string(sixgr.util.structGet(rx, "NoiseVarReason", "")));
    out.NoiseVarStrictFailure = logical(sixgr.util.structGet(rx, "NoiseVarStrictFailure", false));
    out.NoiseVarianceSource = char(string(sixgr.util.structGet( ...
        replay,"NoiseVarianceSource",out.NoiseVarSource)));
    out.SignalEnergyPerOccupiedRE = double(sixgr.util.structGet( ...
        replay,"SignalEnergyPerOccupiedRE",NaN));
    out.ReferenceAWGNGridNoiseVariance = double(sixgr.util.structGet( ...
        replay,"ReferenceAWGNGridNoiseVariance",NaN));
    out.ReferenceAWGNSampleNoiseVariance = double(sixgr.util.structGet( ...
        replay,"ReferenceAWGNSampleNoiseVariance",NaN));
    out.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet( ...
        replay,"SampleToGridNoiseVarianceGain",NaN));
    out.SNRReferencePlane = char(string(sixgr.util.structGet( ...
        replay,"SNRReferencePlane","")));
    out.WaveformPowerUsedForAWGN = logical(sixgr.util.structGet( ...
        replay,"WaveformPowerUsedForAWGN",false));
    if isfinite(out.SignalEnergyPerOccupiedRE) && ...
            out.SignalEnergyPerOccupiedRE > 0 && ...
            isfinite(out.ReferenceAWGNGridNoiseVariance) && ...
            out.ReferenceAWGNGridNoiseVariance > 0
        out.AppliedNoiseSNR_dB = 10 .* log10( ...
            out.SignalEnergyPerOccupiedRE ./ ...
            out.ReferenceAWGNGridNoiseVariance);
    end
    if isfinite(double(injectedNoiseVariance)) && double(injectedNoiseVariance) > 0 && ...
            (~isfinite(out.NoiseVariance) || out.NoiseVariance <= 0)
        rx.NoiseVar = double(injectedNoiseVariance);
        out.NoiseVariance = double(injectedNoiseVariance);
        out.NoiseVarStatus = "OK";
        out.NoiseVarSource = char(string(sixgr.util.structGet(replay, "NoiseVarianceSource", ...
            "srs_replay_reference_waveform_awgn")));
        out.NoiseVarReason = "calibrated_injected_noise_variance_from_receiver_noise_bridge";
        out.NoiseVarStrictFailure = false;
    end
    out.MeasurementAttempted = logical(sixgr.util.structGet(rx, "MeasurementAttempted", false));
    out.MeasurementUsable = logical(sixgr.util.structGet(rx, "MeasurementUsable", false));
    out.FailureReason = char(string(sixgr.util.structGet(rx, "FailureReason", "")));
    out.DetectionAttempted = true;
    out.ResourceExtractionAttempted = true;
    out.ResourceExtractionAvailable = ~isempty(sixgr.util.structGet(rx, "SRSIndices", [])) && ...
        ~isempty(sixgr.util.structGet(rx, "SRSSymbols", []));
    out.ChannelEstimateAttempted = true;
    out.ChannelEstimateAvailable = localHasFiniteComplexData(sixgr.util.structGet(rx, "Hest", []));
    out.SRSChannelEstimateAvailable = logical(out.ChannelEstimateAvailable);
    out.DetectionSuccess = logical(out.ChannelEstimateAvailable);
    out.DetectionUsable = logical(out.DetectionSuccess) && logical(out.ResourceExtractionAvailable);

    if isempty(rx.Hest)
        out.Ok = false;
        out.Notes = "SRS channel estimate is empty.";
        out.FailureReason = "srs_channel_estimate_unavailable";
        return;
    end
    out.ChannelEstimateUsable = true;

    hEst = localSRSLSEstimate(rx.Hest, rx.RxGrid, tx.SRSIndices, tx.SRSSymbols);
    if ~localHasFiniteComplexData(hEst)
        out.Ok = false;
        out.Notes = "SRS pilot resource channel estimate is unavailable.";
        out.FailureReason = "srs_pilot_estimate_unavailable";
        out.ChannelEstimateAvailable = false;
        out.SRSChannelEstimateAvailable = false;
        out.DetectionSuccess = false;
        out.DetectionUsable = false;
        return;
    end
    [hTrue, symTimes_s, symIdx, nmseReferenceSource] = localReferencePilotChannel( ...
        txWaveForReference, tx.Carrier, tx.SRSIndices, tx.SRSSymbols, tx.SRS, sampleRateHz, injectedDopplerHz);
    nmse = localNormalizedMSE(hEst, hTrue);
    estimatedDopplerHz = localEstimateDopplerHz(hEst, symTimes_s);
    out.DopplerEstimateCRLB_Hz = localDopplerCRLBHz(hEst, symTimes_s, rx.NoiseVar);

    out.NMSE_dB = 10*log10(max(nmse, eps));
    out.TrueChannelNMSE_dB = double(out.NMSE_dB);
    out.NMSEReferenceSource = char(string(nmseReferenceSource));
    out.TrueChannelOracleAvailable = startsWith(string(nmseReferenceSource), "applied_channel_gain_truth");
    out.ChannelNMSEThreshold_dB = localResolveSRSNMSEThreshold(cfgSRS);
    out.InterpolationLoss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue);
    out.MismatchSensitivity_dB = localStaticMismatchSensitivity(hTrue);
    out.QCLAccuracy = localReferenceCorrelation(hEst, hTrue);
    out.ComputeLatency_ms = 1e3 * toc(tStart);
    out.ProcedureDelay_ms = 0;
    out.AirInterfaceObservation_ms = 1e3 * (size(txWaveForReference, 1) / max(sampleRateHz, eps));
    % Legacy alias preserved for backward compatibility with older exports.
    % It mirrors radio-time observation duration, not wall-clock compute runtime.
    out.AcquisitionTime_ms = out.AirInterfaceObservation_ms;
    out.TrackingFailure = 0;
    out.InjectedDoppler_Hz = injectedDopplerHz;
    out.EstimatedDopplerHz = estimatedDopplerHz;
    if isfinite(out.EstimatedDopplerHz) && isfinite(out.InjectedDoppler_Hz)
        out.DopplerError_Hz = out.EstimatedDopplerHz - out.InjectedDoppler_Hz;
    end
    srsULCSI = sixgr.phy.ul.estimateSRSRITPMI(rx.Hest, rx.NoiseVar, cfgSRS);
    out.EstimatedRI = double(sixgr.util.structGet(srsULCSI, "RI", NaN));
    out.EstimatedTPMI = double(sixgr.util.structGet(srsULCSI, "TPMI", NaN));
    out.RankEstimate = out.EstimatedRI;
    out.RIEstimate = out.EstimatedRI;
    out.TPMIEstimate = out.EstimatedTPMI;
    out.RISource = char(string(sixgr.util.structGet(srsULCSI, "RISource", "")));
    out.TPMISource = char(string(sixgr.util.structGet(srsULCSI, "TPMISource", "")));
    out.TPMICandidateCount = double(sixgr.util.structGet(srsULCSI, "TPMICandidateCount", NaN));
    out.TPMIMutualInformation = double(sixgr.util.structGet(srsULCSI, "TPMIMutualInformation", NaN));
    out.PredictedPUSCHPostEqSINRPerLayer_dB = double(sixgr.util.structGet( ...
        srsULCSI, "SelectedPostEqSINRPerLayer_dB", []));
    out.PredictedPUSCHMinimumLayerSINR_dB = double(sixgr.util.structGet( ...
        srsULCSI, "SelectedMinimumLayerMeanPostEqSINR_dB", NaN));
    out.PredictedPUSCHWidebandMeanSINR_dB = double(sixgr.util.structGet( ...
        srsULCSI, "SelectedWidebandMeanPostEqSINR_dB", NaN));
    out.PredictedPUSCHPostEqSINRSource = char(string(sixgr.util.structGet( ...
        srsULCSI, "SelectedPostEqSINRSource", "")));
    out.PredictedPUSCHPostEqSINRValueRole = char(string(sixgr.util.structGet( ...
        srsULCSI, "SelectedPostEqSINRValueRole", "")));
    out.PredictedPUSCHPostEqSINRValueStatus = char(string(sixgr.util.structGet( ...
        srsULCSI, "SelectedPostEqSINRValueStatus", "NOT_AVAILABLE")));
    out.SRSConditionNumber_dB = double(sixgr.util.structGet(srsULCSI, "ConditionNumber_dB", NaN));
    spatialSignatureMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.mimo.muMimoSpatialSignatureMode", ...
        sixgr.util.structGet(cfg, "mac.scheduler.muMimoSpatialSignatureMode", ...
        "dominant_scheduled_rank")))));
    spatialSignatureNoiseMargin_dB = double(sixgr.util.structGet(cfg, ...
        "phy.mimo.muMimoSpatialSubspaceNoiseMargin_dB", ...
        sixgr.util.structGet(cfg, ...
        "mac.scheduler.muMimoSpatialSubspaceNoiseMargin_dB", NaN)));
    spatialSignatureArgs = {"Rank", out.EstimatedRI, ...
        "SubspaceMode", spatialSignatureMode};
    if spatialSignatureMode == "complete_detectable_subspace"
        spatialSignatureEstimate = localPilotSpatialChannelEstimateSlice( ...
            rx.Hest, tx.SRSIndices);
        if ~localHasFiniteComplexData(spatialSignatureEstimate)
            error("sixgr:link:SRS:SpatialPilotEstimateUnavailable", ...
                "Complete MU-MIMO spatial evidence requires finite channel " + ...
                "vectors at the actually transmitted SRS pilot REs.");
        end
        spatialSignatureArgs = [spatialSignatureArgs, ...
            {"NoiseVariance", double(rx.NoiseVar), ...
             "NoiseMargin_dB", spatialSignatureNoiseMargin_dB}]; %#ok<AGROW>
    else
        spatialSignatureEstimate = rx.Hest;
    end
    [spatialSignature, spatialSignatureInfo] = ...
        sixgr.phy.mimo.spatialSignatureFromChannelEstimate( ...
        spatialSignatureEstimate, spatialSignatureArgs{:});
    out.SpatialSignatureToken = char( ...
        sixgr.phy.mimo.MatrixContract.serialize(spatialSignature));
    out.SpatialSignatureSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(spatialSignature));
    out.SpatialSignatureRows = double(size(spatialSignature, 1));
    out.SpatialSignatureColumns = double(size(spatialSignature, 2));
    out.SpatialSignatureRawRank = double(spatialSignatureInfo.RawNumericalRank);
    out.SpatialSignatureRetainedRank = double(spatialSignatureInfo.RetainedRank);
    out.SpatialSignatureDetectionThreshold = double(spatialSignatureInfo.DetectionThreshold);
    out.SpatialSignatureNoiseVariance = double(spatialSignatureInfo.NoiseVariance);
    out.SpatialSignatureNoiseMargin_dB = double(spatialSignatureInfo.NoiseMargin_dB);
    out.SpatialSignatureSnapshotCount = double(spatialSignatureInfo.SnapshotCount);
    out.SpatialSignatureReductionMode = char(string(spatialSignatureInfo.ReductionMode));
    if spatialSignatureMode == "complete_detectable_subspace"
        out.SpatialSignatureSource = ...
            "measured_srs_receiver_channel_estimate_pilot_re_frequency_selective_complete_detectable_subspace";
    else
        out.SpatialSignatureSource = ...
            "measured_srs_receiver_channel_estimate_dominant_rank_subspace";
    end
    linkState = sixgr.phy.ul.measureULLinkState(rx.Hest, rx.NoiseVar, cfgSRS, ...
        "ReceivedGrid", rx.RxGrid, ...
        "ReferenceIndices", tx.SRSIndices, ...
        "ReferenceSymbols", tx.SRSSymbols, ...
        "ChannelEstimateDomain", "srs_port_domain");
    out.SINR_dB = double(sixgr.util.structGet(linkState, "SINR_dB", NaN));
    out.SINRSource = char(string(sixgr.util.structGet(linkState, "SINRSource", "")));
    out.SINRValueStatus = char(string(sixgr.util.structGet(linkState, "SINRValueStatus", "")));
    out.SINRMeasurementDomain = char(string(sixgr.util.structGet(linkState, "SINRMeasurementDomain", "")));
    out.PowerReferencePlane = char(string(sixgr.util.structGet(linkState, "PowerReferencePlane", "")));
    if localThermalNoiseSINRUnavailable(replay)
        out.SINR_dB = NaN;
        out.SINRSource = "ul_srs_sinr_unavailable_without_runtime_rx_power_or_pathloss";
        out.SINRValueStatus = "unavailable";
        out.SINRMeasurementDomain = "";
        out.PowerReferencePlane = "";
        out.CQI = NaN;
        out.CQISource = "";
        out.CQIValueStatus = "unavailable";
    else
        rawCQI = double(sixgr.util.structGet(linkState, "CQI", NaN));
        if isfinite(rawCQI)
            out.CQI = double(max(0, min(15, round(rawCQI))));
        else
            out.CQI = NaN;
        end
        out.CQISource = char(string(sixgr.util.structGet(linkState, "CQISource", "")));
        out.CQIValueStatus = char(string(sixgr.util.structGet(linkState, "CQIValueStatus", "")));
    end
    if isfinite(out.CQI) && out.CQI >= 0
        [modStr, targetCodeRate, mcsIndex] = sixgr.link.amcFromCQI(out.CQI, "", NaN, cfgSRS, "UL");
        out.MCSIndex = double(mcsIndex);
        out.Modulation = char(string(modStr));
        out.TargetCodeRate = double(targetCodeRate);
    end
    out.MeasurementAttempted = true;
    out.MeasurementUsable = isfinite(out.SINR_dB) && sixgr.util.isAcceptableSINRStatus(out.SINRValueStatus);
    strictNoiseOk = ~logical(out.NoiseVarStrictFailure) && ...
        (~strictNoiseVarianceRequired || (isfinite(out.NoiseVariance) && out.NoiseVariance >= 0));
    nmseStrictOk = isfinite(out.NMSE_dB) && out.NMSE_dB <= out.ChannelNMSEThreshold_dB;
    out.SRSChannelEstimateAvailable = logical(out.SRSChannelEstimateAvailable) && logical(nmseStrictOk);
    out.SRSRuntimeEvidenceUsable = logical(out.DetectionUsable) && ...
        logical(out.ResourceExtractionAvailable) && logical(out.ChannelEstimateAvailable) && ...
        logical(out.SRSChannelEstimateAvailable) && logical(out.MeasurementUsable) && ...
        logical(strictNoiseOk) && logical(nmseStrictOk);
    out.StrictReceiverEvidenceOk = logical(out.SRSRuntimeEvidenceUsable);
    out.StrictOk = logical(out.SRSRuntimeEvidenceUsable);
    out.Ok = logical(out.StrictOk);
    if ~logical(out.Ok) && strlength(strtrim(string(out.FailureReason))) == 0
        if ~logical(nmseStrictOk)
            out.FailureReason = "srs_channel_nmse_above_threshold";
        else
            out.FailureReason = "srs_runtime_evidence_incomplete";
        end
    end
    if logical(out.MeasurementUsable)
        out.Notes = "SRS NMSE=" + string(round(out.NMSE_dB,2)) + ...
            " dB, injected Doppler=" + string(round(injectedDopplerHz, 3)) + " Hz" + ...
            ", CQI=" + string(out.CQI) + ", MCS=" + string(out.MCSIndex);
    else
        out.Notes = "SRS channel estimate available; SINR/CQI unavailable from receiver noise evidence: " + ...
            string(out.NoiseVarReason);
    end
catch ME
    out.Ok = false;
    out.TrackingFailure = 1;
    out.FailureReason = char(string(ME.identifier));
    out.Notes = "Failure: " + string(ME.message);
    if ~isempty(log)
        log.warn("runSRSChannelEstimation failed: " + string(ME.message));
    end
end
end

function tf = localHasFiniteComplexData(x)
tf = false;
if isempty(x) || ~isnumeric(x)
    return;
end
tf = any(isfinite(real(x(:))) & isfinite(imag(x(:))));
end

function [cfgOut, srsCfg] = localBindRuntimeSRSConfig(cfg, slotIdx)
cfgOut = localWithSRSULRuntimeDirection(cfg);
if isfinite(slotIdx) && slotIdx > 0
    slot0 = max(0, round(double(slotIdx)) - 1);
    period = max(1, round(double(sixgr.util.structGet(cfgOut, "phy.srs.period_slots", ...
        sixgr.util.structGet(cfgOut, "lls6g.reference_signals.srs.periodicity_slots", 1)))));
    offset = mod(slot0, period);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.srs.slotNumbers", double(slot0));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.srs.period_offset", double(offset));
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.reference_signals.srs.slot_numbers", double(slot0));
    cfgOut = sixgr.util.structSet(cfgOut, "lls6g.reference_signals.srs.period_offset", double(offset));
end
srsCfg = sixgr.phy.srs.buildSRSConfigFromScenario(cfgOut, ...
    "RunId", "runtime_srs_channel_estimation", ...
    "ScenarioName", string(sixgr.util.structGet(cfgOut, "meta.loadedFrom", "runtime_srs_channel_estimation")));
carrier = srsCfg.ToolboxCarrier;
if ~isempty(srsCfg.ExpectedSlotSet)
    carrier.NSlot = double(srsCfg.ExpectedSlotSet(1));
end
srsCfg.ToolboxCarrier = carrier;
end

function cfgOut = localWithSRSULRuntimeDirection(cfg)
cfgOut = cfg;
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeCurrentDirection", "UL");
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.Direction", "UL");
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext.RuntimeSignalFamily", "SRS");
cfgOut = sixgr.util.structSet(cfgOut, "phy.runtimeSignalFamily", "SRS");
cfgOut = sixgr.util.structSet(cfgOut, "channel.linkDirection", "UL");
scsKHz = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfgOut, "phy.numerology.scs_kHz", []), ...
    sixgr.util.structGet(cfgOut, "phy.carrier.SubcarrierSpacing", []), ...
    sixgr.util.structGet(cfgOut, "phy.scs", []), ...
    sixgr.util.structGet(cfgOut, "frame.scs_khz", []), ...
    30);
cfgOut = sixgr.util.structSet(cfgOut, "phy.numerology.scs_kHz", double(scsKHz));
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for ii = 1:nargin
    raw = varargin{ii};
    if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = double(raw(1));
        return;
    end
end
end

function tf = localThermalNoiseSINRUnavailable(replay)
noiseMode = lower(strtrim(string(sixgr.util.structGet(replay, "NoiseOperatingMode", ""))));
if noiseMode ~= "receiver_noise_figure_thermal_noise"
    tf = false;
    return;
end
servingSource = lower(strtrim(string(sixgr.util.structGet(replay, "ServingRxPowerSource", ""))));
noiseSource = lower(strtrim(string(sixgr.util.structGet(replay, "NoisePowerSource", ""))));
tf = servingSource == "unavailable_missing_pathloss_or_runtime_rx_power" || ...
    noiseSource == "thermal_noise_unavailable_missing_pathloss_or_runtime_rx_power";
end

function [y, nVar, replay, referenceWaveform, state] = localApplySRSChannelAndNoise(x, cfg, tx, info, sampleRateHz, injectedDopplerHz, snr_dB, state, trialIdx)
if nargin < 8
    state = [];
end
if nargin < 9
    trialIdx = 1;
end
txInfo = struct("OFDM", sixgr.util.structGet(info, "OFDMInfo", struct()));
[x,cfg,srsPower,txRfReplay] = localPrepareSRSTransmitter( ...
    x,cfg,txInfo,tx);
if isstruct(state) && isfield(state, "ContractVersion")
    state = localPrepareFactorySRSChannelState(state, cfg, tx, txInfo);
    [y, channelReplay, state] = ...
        sixgr.channel.ChannelFactory.applyRuntimeChannelState(state, x);
elseif ~(isstruct(state) && logical(sixgr.util.structGet(state, "Initialized", false)))
    state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
    state.ChannelSeed = localTrialSeed(cfg, trialIdx);
    [y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state);
else
    [y, channelReplay, state] = sixgr.link.applyRuntimeFadingChannel(x, state);
end
useFading = logical(sixgr.util.structGet(channelReplay, "ChannelFadingApplied", false));
if ~useFading
    y = localApplyTrackingDoppler(x, sampleRateHz, injectedDopplerHz);
end

referenceWaveform = y;

cfgReplay = localPrepareSRSReplayCfg(cfg, snr_dB);
[y, impairmentReplay] = sixgr.link.applyWaveformImpairments( ...
    y,cfgReplay,sampleRateHz,"ApplyRFChain",false);
replay = localMergeReplayEvidence(impairmentReplay, channelReplay);
replay.SRSPowerControl = srsPower;
replay.TxRFExecutionStatus = char(string(sixgr.util.structGet( ...
    txRfReplay,"RFExecutionStatus","applied_or_identity")));
replay.TxRFStageOrder = char(string(sixgr.util.structGet( ...
    txRfReplay,"RFStageOrder","")));
replay.TxRFAppliedStageCount = double(sixgr.util.structGet( ...
    txRfReplay,"RFAppliedStageCount",0));
replay.ChannelModelApplied = char(string(sixgr.util.structGet(cfg, "channel.model", "AWGN")));
replay.ChannelFadingApplied = logical(useFading);
desiredWaveform = y;
referenceWaveform = desiredWaveform;
    txInfo.PowerContext = sixgr.util.structGet(cfg, ...
        "lls6g.runtimePowerContext", struct());
    [preFrontEndWaveform, preFrontEndNVar, awgnEvidence] = ...
        localAddAwgnFromReplay(y,replay,desiredWaveform,txInfo,tx.Carrier,tx.SRSIndices);
    replay.InjectedNoiseVariance = double(preFrontEndNVar);
    if isfinite(preFrontEndNVar) && preFrontEndNVar > 0
        replay.NoiseVarianceSource = char(string(sixgr.util.structGet( ...
            awgnEvidence,"NoiseVarianceSource", ...
            "srs_replay_reference_waveform_awgn")));
    end
    if isstruct(awgnEvidence)
        evidenceFields = fieldnames(awgnEvidence);
        for evidenceIdx = 1:numel(evidenceFields)
            replay.(evidenceFields{evidenceIdx}) = ...
                awgnEvidence.(evidenceFields{evidenceIdx});
        end
    end
[y,replay] = sixgr.link.applyCompositeReceiverFrontEnd( ...
    preFrontEndWaveform,cfgReplay,sampleRateHz,replay,"Direction","UL");
replay = sixgr.link.applyCompositeFrontEndVarianceReplay(replay);
nVar = double(sixgr.util.structGet(replay, ...
    "InjectedNoiseVariancePostCompositeFrontEnd",preFrontEndNVar));
end

function [waveform,cfgOut,powerEvidence,txRfReplay] = ...
        localPrepareSRSTransmitter(waveform,cfg,txInfo,tx)
cfgOut = cfg;
pathloss_dB = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg,"lls6g.userContext.RuntimeServingPathloss_dB",[]), ...
    sixgr.util.structGet(cfg,"lls6g.userContext.RuntimeServingBasePathloss_dB",[]));
p0_dBm = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg,"rf.frontend.ul_power_control.srs.p0_dbm",[]), ...
    sixgr.util.structGet(cfg,"rf_frontend.ul_power_control.srs.p0_dbm",[]), ...
    sixgr.util.structGet(cfg,"rf.ul_power_control.srs.p0_dbm",[]), ...
    sixgr.util.structGet(cfg,"lls6g.reference_signals.srs.p0",[]), ...
    sixgr.util.structGet(cfg,"phy.srs.p0",[]));
alpha = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg,"rf.frontend.ul_power_control.srs.alpha",[]), ...
    sixgr.util.structGet(cfg,"rf_frontend.ul_power_control.srs.alpha",[]), ...
    sixgr.util.structGet(cfg,"rf.ul_power_control.srs.alpha",[]), ...
    sixgr.util.structGet(cfg,"lls6g.reference_signals.srs.power_control_alpha",[]), ...
    sixgr.util.structGet(cfg,"phy.srs.powerControlAlpha",[]));
deltaTF_dB = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg,"rf.frontend.ul_power_control.srs.delta_tf_db",[]), ...
    sixgr.util.structGet(cfg,"rf_frontend.ul_power_control.srs.delta_tf_db",[]), ...
    sixgr.util.structGet(cfg,"rf.ul_power_control.srs.delta_tf_db",[]), ...
    sixgr.util.structGet(cfg,"lls6g.reference_signals.srs.delta_tf_db",[]), ...
    sixgr.util.structGet(cfg,"phy.srs.deltaTF_dB",[]));
pcmax_dBm = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg,"rf.frontend.ul_power_control.srs.pcmax_dbm",[]), ...
    sixgr.util.structGet(cfg,"rf_frontend.ul_power_control.srs.pcmax_dbm",[]), ...
    sixgr.util.structGet(cfg,"rf.ul_power_control.srs.pcmax_dbm",[]), ...
    sixgr.util.structGet(cfg,"phy.pusch.powerControl.pcmax_dBm",[]), ...
    sixgr.util.structGet(cfg,"powerAndRF.ueTxPower_dBm",[]));
occupiedRB = double(sixgr.util.structGet(tx,"SRSOccupiedPRBCount",NaN));
scsKHz = double(sixgr.util.structGet(cfg,"phy.numerology.scs_kHz",NaN));
mu = log2(scsKHz/15);
required = [pathloss_dB p0_dBm alpha deltaTF_dB pcmax_dBm occupiedRB mu];
standaloneAWGN = lower(strtrim(string(sixgr.util.structGet( ...
    cfg,"run.noiseOperatingMode","")))) == ...
    "standalone_awgn_snr_argument";
strictPowerAvailable = ~any(~isfinite(required)) && occupiedRB >= 1 && ...
    mu >= 0 && mu == round(mu);
if ~strictPowerAvailable && ~standaloneAWGN
    error("sixgr:link:SRS:MissingPowerControlAuthority", ...
        "SRS waveform execution requires YAML/runtime pathloss, P0, alpha, " + ...
        "delta-TF, PCMAX, occupied RB count and numerology for TS 38.213 power control.");
end
powerContext = sixgr.rf.PowerContext(cfg,"UL", ...
    "NumPorts",size(waveform,2));
if strictPowerAvailable
    epoch = localFirstFiniteScalar( ...
        sixgr.util.structGet(cfg,"rf.frontend.configuration_epoch",[]), ...
        sixgr.util.structGet(cfg,"rf_frontend.configuration_epoch",[]), ...
        sixgr.util.structGet(cfg,"rf.configuration_epoch",[]));
    if ~(isfinite(epoch) && epoch >= 1 && epoch == round(epoch))
        error("sixgr:link:SRS:MissingPowerControlEpoch", ...
            "SRS power-control execution requires a YAML-owned RF configuration epoch.");
    end
    powerState = sixgr.rf.runtime.UplinkPowerControlState(epoch);
    request = struct("Channel","SRS","Mu",mu,"MRB",occupiedRB, ...
        "MeasuredPathloss_dB",pathloss_dB, ...
        "PathlossSource","runtime_geometry_or_reference_rs_measurement", ...
        "P0_dBm",p0_dBm,"Alpha",alpha,"DeltaTF_dB",deltaTF_dB, ...
        "PCMAX_dBm",pcmax_dBm);
    powerEvidence = sixgr.rf.runtime.SRSPowerController.resolve( ...
        powerState,request);
    powerContext.TotalTxPower_dBm = double(powerEvidence.AppliedPower_dBm);
    powerContext.TotalTxPowerSource = "ts_38_213_srs_power_control";
    powerContext.SignalSpecificPowerControl = true;
else
    powerEvidence = struct( ...
        "Channel","SRS", ...
        "RequestedPower_dBm",double(powerContext.TotalTxPower_dBm), ...
        "AppliedPower_dBm",double(powerContext.TotalTxPower_dBm), ...
        "PowerHeadroom_dB",NaN,"Clipped",false, ...
        "PathlossSource","not_applicable_standalone_awgn_reference", ...
        "EvidenceClass","standalone_awgn_reference_not_production_power_control");
    powerContext.TotalTxPowerSource = ...
        "standalone_awgn_reference_power_context";
    powerContext.SignalSpecificPowerControl = false;
end
powerContext.TotalTxPower_mW = 10.^(powerContext.TotalTxPower_dBm/10);
powerContext.TotalTxPower_W = powerContext.TotalTxPower_mW*1e-3;
powerContext.SignalFamily = "SRS";
[waveform,powerContext] = sixgr.rf.applyPowerContext( ...
    waveform,cfg,"UL",txInfo,"PowerContext",powerContext);
cfgOut = sixgr.util.structSet(cfgOut, ...
    "lls6g.runtimePowerContext",powerContext);
sampleRateHz = double(sixgr.util.structGet(txInfo,"OFDM.SampleRate",NaN));
txRfOut = sixgr.rf.applyRFImpairmentChain(waveform,cfgOut, ...
    "SampleRateHz",sampleRateHz,"Direction","UL", ...
    "MeasurementPoint","tx_output","Endpoint","tx", ...
    "StrictMutationRequired",false,"UseLegacyGlobalConfig",false, ...
    "ApplyPA",false,"ApplyADC",false);
waveform = cast(txRfOut.Waveform,"like",waveform);
txRfReplay = txRfOut.Replay;
cfgOut = sixgr.util.structSet(cfgOut, ...
    "lls6g.txRFImpairmentReplay",txRfReplay);
end

function state = localPrepareFactorySRSChannelState(state, cfg, tx, txInfo)
% Materialize SRS with the same UL antenna and time authority as PUSCH.
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
activeTxPorts = max(1, size(tx.Waveform, 2));
runtimeNumTx = localFirstFiniteScalar( ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta.NumLogicalPorts", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumWaveformColumns", []), ...
    sixgr.util.structGet(userMeta, "RuntimeUEAntenna.NumLogicalPorts", []), ...
    sixgr.util.structGet(cfg, "phy.maxULLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.maxLayers", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.NumAntennaPorts", []), ...
    sixgr.util.structGet(cfg, "phy.pusch.numPorts", []), ...
    activeTxPorts);
runtimeNumTx = max(activeTxPorts, min(4, round(double(runtimeNumTx))));
numRx = max(1, round(double(sixgr.phy.ul.resolveULDirectionalAntennaCount( ...
    cfg, "rx", runtimeNumTx))));

txRuntimeAntenna = sixgr.util.structGet(userMeta, "RuntimeUEAntenna", struct());
txRuntimeMeta = sixgr.util.structGet(userMeta, "RuntimeUEAntennaMeta", struct());
[txRuntimeAntenna, txRuntimeMeta] = ...
    sixgr.rf.AntennaArrayFactory.logicalPortView( ...
    txRuntimeAntenna, txRuntimeMeta, activeTxPorts, ...
    "srs_runtime_waveform_port_count");
rxRuntimeAntenna = sixgr.util.structGet(userMeta, "RuntimeServingBSAntenna", struct());
rxRuntimeMeta = sixgr.util.structGet(userMeta, "RuntimeServingBSAntennaMeta", struct());

state = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    state, cfg, tx.Waveform, txInfo, ...
    "NumTxAnt", runtimeNumTx, ...
    "NumRxAnt", numRx, ...
    "TransmitAntennaRuntime", txRuntimeAntenna, ...
    "ReceiveAntennaRuntime", rxRuntimeAntenna, ...
    "TransmitAntennaMeta", txRuntimeMeta, ...
    "ReceiveAntennaMeta", rxRuntimeMeta);
slotStart_s = double(sixgr.util.structGet(state, "TargetSlotStartTime_s", ...
    sixgr.util.structGet(userMeta, "RuntimeSlotStartTime_s", NaN)));
if isfinite(slotStart_s) && slotStart_s >= 0
    state = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime( ...
        state, slotStart_s, runtimeNumTx, tx.Waveform);
end
end

function replay = localMergeReplayEvidence(primaryReplay, secondaryReplay)
replay = primaryReplay;
if ~(isstruct(secondaryReplay) && ~isempty(fieldnames(secondaryReplay)))
    return;
end
fields = fieldnames(secondaryReplay);
for idx = 1:numel(fields)
    name = fields{idx};
    value = secondaryReplay.(name);
    if ~isfield(replay, name) || localReplayValueHasEvidence(value) || ~localReplayValueHasEvidence(replay.(name))
        replay.(name) = value;
    end
end
end

function tf = localReplayValueHasEvidence(value)
tf = false;
if isempty(value)
    return;
end
if isstring(value) || ischar(value)
    tf = any(strlength(strtrim(string(value(:)))) > 0);
    return;
end
if isnumeric(value)
    tf = any(isfinite(double(value(:))));
    return;
end
if islogical(value)
    tf = true;
    return;
end
if isstruct(value)
    tf = ~isempty(fieldnames(value));
    return;
end
tf = true;
end

function cfgOut = localPrepareSRSReplayCfg(cfg, snr_dB)
cfgOut = sixgr.util.structSet(cfg, "channel.snr_dB", double(snr_dB));
if localShouldUseStandaloneAWGN(cfgOut, snr_dB)
    cfgOut = sixgr.util.structSet(cfgOut, "run.noiseOperatingMode", "standalone_awgn_snr_argument");
end
end

function tf = localShouldUseStandaloneAWGN(cfg, snr_dB)
if ~(isfinite(double(snr_dB)))
    tf = false;
    return;
end
model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", "AWGN"))));
awgnOnly = logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false));
if ~(awgnOnly || model == "AWGN" || model == "NONE" || model == "OFF")
    tf = false;
    return;
end
noiseMode = lower(strtrim(string(sixgr.util.structGet( ...
    cfg,"run.noiseOperatingMode",""))));
% A configured operating-point SNR is metadata in production.  It becomes
% an AWGN injection target only when the caller explicitly selects the
% standalone reference mode; never convert a thermal-noise run implicitly.
tf = noiseMode == "standalone_awgn_snr_argument";
end

function seed = localTrialSeed(cfg, trialIdx)
seedBase = double(sixgr.util.structGet(cfg, "run.seed", 1));
if ~isfinite(seedBase)
    seedBase = 1;
end
seed = mod(round(seedBase) + max(1, round(double(trialIdx))) - 1, 2^31 - 2) + 1;
end

function localResetChannelOnce(chObj, seed)
if isempty(chObj)
    return;
end
try
    if isprop(chObj, "Seed")
        chObj.Seed = double(seed);
    end
catch
end
try
    reset(chObj);
catch
end
end

function [y, nVar, evidence] = localAddAwgnFromReplay( ...
        x, replay, referenceWaveform, txInfo, carrier, occupiedIndices)
evidence = struct();
noiseMode = string(sixgr.util.structGet(replay, "NoiseOperatingMode", "receiver_noise_figure_thermal_noise"));
if noiseMode == "receiver_noise_figure_thermal_noise"
    nVar = localResolveThermalNoiseVariance(replay, referenceWaveform);
    if isfinite(nVar) && nVar > 0
        n = sqrt(nVar / 2) .* (randn(size(x), "like", real(x)) + 1i * randn(size(x), "like", real(x)));
        y = x + cast(n, "like", x);
        evidence.NoiseVarianceSource = "thermal_noise_relative_to_runtime_serving_rx_power";
        return;
    end
    y = x;
    nVar = NaN;
    return;
end
appliedSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
if isempty(carrier)
    error("sixgr:link:SRS:MissingOFDMNoiseCalibration", ...
        "Standalone SRS AWGN requires the transmitting carrier for occupied-grid noise calibration.");
end
[signalEnergyPerOccupiedRE, receivedEnergyEvidence] = ...
    sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        carrier,referenceWaveform,occupiedIndices,"SignalFamily","SRS");
[y, referenceNoise] = sixgr.phy.waveform.addOccupiedREAWGN( ...
    x,carrier,appliedSNR_dB, ...
    "SignalEnergyPerOccupiedRE",signalEnergyPerOccupiedRE);
nVar = double(referenceNoise.SampleNoiseVariance);
evidence.NoiseVarianceSource = ...
    "standalone_awgn_measured_received_occupied_grid_esn0_reference";
evidence.SignalEnergyMeasurementSource = char(string(receivedEnergyEvidence.Source));
evidence.SignalEnergyMeasurementPlane = char(string(receivedEnergyEvidence.MeasurementPlane));
evidence.SignalEnergyObservationCount = double(receivedEnergyEvidence.ObservationCount);
evidence.SignalEnergyReceiveBranchCount = double(receivedEnergyEvidence.ReceiveBranchCount);
evidence.SNRReferencePlane = char(string(referenceNoise.SNRReferencePlane));
evidence.SNRDefinition = char(string(referenceNoise.SNRDefinition));
evidence.SignalEnergyPerOccupiedRE = ...
    double(referenceNoise.SignalEnergyPerOccupiedRE);
evidence.ReferenceAWGNGridNoiseVariance = ...
    double(referenceNoise.GridNoiseVariance);
evidence.ReferenceAWGNSampleNoiseVariance = ...
    double(referenceNoise.SampleNoiseVariance);
evidence.SampleToGridNoiseVarianceGain = ...
    double(referenceNoise.SampleToGridNoiseVarianceGain);
evidence.NoiseCalibrationVersion = char(string(referenceNoise.Version));
evidence.WaveformPowerUsedForAWGN = false;
evidence.CyclicPrefixPowerUsedForAWGN = false;
evidence.UnusedFFTBinPowerUsedForAWGN = false;
end

function nVar = localResolveThermalNoiseVariance(replay, referenceWaveform)
nVar = NaN;
thermalNoisePower_dBm = double(sixgr.util.structGet(replay, "ThermalNoisePower_dBm", NaN));
servingRxPower_dBm = double(sixgr.util.structGet(replay, "ServingRxPower_dBm", NaN));
if ~(isfinite(thermalNoisePower_dBm) && isfinite(servingRxPower_dBm))
    return;
end
refPower = mean(abs(double(referenceWaveform(:))).^2, "omitnan");
if ~(isfinite(refPower) && refPower >= 0)
    return;
end
relativeNoise_dB = thermalNoisePower_dBm - servingRxPower_dBm;
nVar = refPower * 10.^(relativeNoise_dB / 10);
end

function sampleRateHz = localResolveSampleRate(info, tx, cfg)
sampleRateHz = sixgr.util.structGet(info, "OFDMInfo.SampleRate", []);
if isempty(sampleRateHz)
    sampleRateHz = sixgr.util.structGet(cfg, "phy.sampleRate_Hz", []);
end
if isempty(sampleRateHz)
    try
        nrInfo = nrOFDMInfo(tx.Carrier);
        sampleRateHz = double(sixgr.util.structGet(nrInfo, "SampleRate", []));
    catch
        sampleRateHz = [];
    end
end
if isempty(sampleRateHz)
    error("sixgr:link:SRSChannelEstimationSampleRateMissing", ...
        "SRS tracking requires a known OFDM sample rate.");
end
sampleRateHz = double(sampleRateHz);
end

function dopplerHz = localResolveInjectedDopplerHz(cfg)
dopplerHz = double(sixgr.util.structGet(cfg, "channel.doppler_Hz", ...
    sixgr.util.structGet(cfg, "channel.dopplerHz", sixgr.util.structGet(cfg, "channel.fading.maxDoppler_Hz", 0))));
if ~isfinite(dopplerHz)
    dopplerHz = 0;
end
end

function threshold = localResolveSRSNMSEThreshold(cfg)
threshold = double(sixgr.util.structGet(cfg, "phy.srs.channelNMSEThresholddB", ...
    sixgr.util.structGet(cfg, "lls6g.reference_signals.srs.channel_nmse_threshold_db", -8)));
if ~(isscalar(threshold) && isfinite(threshold))
    threshold = -8;
end
end

function y = localApplyTrackingDoppler(x, sampleRateHz, dopplerHz)
y = x;
if ~(isfinite(sampleRateHz) && sampleRateHz > 0 && isfinite(dopplerHz) && dopplerHz ~= 0)
    return;
end
n = (0:size(y, 1)-1).';
h = exp(1j * 2 * pi * (dopplerHz / sampleRateHz) * n);
y = y .* h;
end

function hEst = localSRSLSEstimate(Hest, rxGrid, srsInd, srsSym)
hEst = [];
if isempty(srsInd) || isempty(srsSym)
    return;
end
if ~isempty(rxGrid)
    pilotObs = localGridPilotObservations(rxGrid, srsInd);
    pilotObs = localCollapsePilotObservations(pilotObs);
    srsSymVec = srsSym(:);
    N = min(numel(pilotObs), numel(srsSymVec));
    if N > 0
        pilotObs = pilotObs(1:N);
        srsSymVec = srsSymVec(1:N);
        den = srsSymVec;
        den(abs(den) < eps) = 1;
        hGridLS = pilotObs ./ den;
        if localHasFiniteComplexData(hGridLS)
            hEst = hGridLS(:);
            return;
        end
    end
end
pilotHest = localPilotChannelEstimateSlice(Hest, srsInd);
if ~isempty(pilotHest)
    hEst = pilotHest(:);
    return;
end
if isempty(rxGrid)
    return;
end
pilotObs = localGridPilotObservations(rxGrid, srsInd);
pilotObs = localCollapsePilotObservations(pilotObs);
srsSym = srsSym(:);
N = min(numel(pilotObs), numel(srsSym));
if N == 0
    return;
end
pilotObs = pilotObs(1:N);
srsSym = srsSym(1:N);
den = srsSym;
den(abs(den) < eps) = 1;
hEst = pilotObs ./ den;
end

function pilotObs = localGridPilotObservations(grid, pilotInd)
pilotObs = complex([]);
if isempty(grid) || isempty(pilotInd)
    return;
end
K = size(grid, 1);
L = size(grid, 2);
if ~(K > 0 && L > 0)
    return;
end
idx = double(pilotInd(:));
idx = idx(isfinite(idx) & idx >= 1);
if isempty(idx)
    return;
end
try
    maxPort = max(1, ceil(max(idx) / max(K * L, 1)));
    [k, l, ~] = ind2sub([K, L, maxPort], idx);
catch
    return;
end
n = numel(k);
pilotObs = complex(NaN(n, 1));
for ii = 1:n
    if k(ii) < 1 || k(ii) > K || l(ii) < 1 || l(ii) > L
        continue;
    end
    v = squeeze(grid(k(ii), l(ii), :));
    pilotObs(ii) = mean(v(:), "omitnan");
end
end

function pilotH = localPilotChannelEstimateSlice(H, pilotInd)
pilotH = [];
if isempty(H) || isempty(pilotInd)
    return;
end
sz = size(H);
if numel(sz) < 2
    return;
end
K = sz(1);
L = sz(2);
Nr = 1;
Np = 1;
if numel(sz) >= 3
    Nr = sz(3);
end
if numel(sz) >= 4
    Np = sz(4);
end
flatDim = max(K * L, 1);
ind = double(pilotInd(:));
ind = ind(isfinite(ind) & ind >= 1);
if isempty(ind)
    return;
end
try
    pDim = max(1, ceil(max(ind) / flatDim));
    [k, l, p] = ind2sub([K, L, pDim], ind);
catch
    return;
end
N = numel(ind);
pilotH = complex(NaN(N, 1));
for i = 1:N
    portIdx = min(max(round(double(p(i))), 1), Np);
    if numel(sz) >= 4
        v = squeeze(H(k(i), l(i), :, portIdx));
    elseif numel(sz) == 3
        v = squeeze(H(k(i), l(i), :));
    else
        v = H(k(i), l(i));
    end
    if isempty(v)
        continue;
    end
    if Nr > 1 || numel(v) > 1
        pilotH(i) = mean(v(:), "omitnan");
    else
        pilotH(i) = v;
    end
end
mask = isfinite(real(pilotH)) & isfinite(imag(pilotH));
if ~any(mask)
    pilotH = [];
end
end

function obs = localCollapsePilotObservations(pilotObs)
if isempty(pilotObs)
    obs = [];
    return;
end
if isvector(pilotObs)
    obs = pilotObs(:);
    return;
end
obs = mean(pilotObs, 2, "omitnan");
obs = obs(:);
end

function pilotH = localPilotSpatialChannelEstimateSlice(H, pilotInd)
% Keep every measured receive vector at each transmitted SRS pilot RE.
pilotH = [];
if isempty(H) || isempty(pilotInd)
    return;
end
sz = size(H);
if numel(sz) < 3
    return;
end
K = sz(1);
L = sz(2);
nRx = sz(3);
nPorts = 1;
if numel(sz) >= 4
    nPorts = sz(4);
end
flatDim = max(K * L, 1);
ind = double(pilotInd(:));
ind = ind(isfinite(ind) & ind >= 1);
if isempty(ind)
    return;
end
try
    indexPortDim = max(1, ceil(max(ind) / flatDim));
    [k, l, port] = ind2sub([K, L, indexPortDim], ind);
catch
    return;
end
n = numel(ind);
pilotH = complex(NaN(n, 1, nRx));
for index = 1:n
    portIndex = min(max(round(double(port(index))), 1), nPorts);
    if numel(sz) >= 4
        value = reshape(H(k(index), l(index), :, portIndex), 1, 1, nRx);
    else
        value = reshape(H(k(index), l(index), :), 1, 1, nRx);
    end
    pilotH(index, 1, :) = value;
end
finiteRows = squeeze(all(isfinite(real(pilotH)) & isfinite(imag(pilotH)), 3));
pilotH = pilotH(finiteRows, :, :);
if isempty(pilotH)
    pilotH = [];
end
end

function [hTrue, symTimes_s, symIdx, source] = localReferencePilotChannel(referenceWaveform, carrier, pilotInd, pilotSym, srs, sampleRateHz, dopplerHz)
nPorts = max(1, round(double(sixgr.util.structGet(srs, "NumSRSPorts", 1))));
symIdx = localPilotSymbolIndices(carrier, pilotInd, nPorts);
symbolTimes = localSymbolCenterTimes(carrier, sampleRateHz);
symTimes_s = symbolTimes(symIdx);
hTrue = localReferencePilotChannelFromWaveform(referenceWaveform, carrier, pilotInd, pilotSym, nPorts);
if localHasFiniteComplexData(hTrue)
    source = "applied_channel_gain_truth_from_noiseless_reference_waveform";
    N = min(numel(hTrue), numel(symTimes_s));
    hTrue = hTrue(1:N);
    symTimes_s = symTimes_s(1:N);
    symIdx = symIdx(1:N);
    return;
end
hTrue = exp(1j * 2 * pi * dopplerHz .* symTimes_s(:));
source = "synthetic_doppler_reference_fallback";
end

function hTrue = localReferencePilotChannelFromWaveform(referenceWaveform, carrier, pilotInd, pilotSym, nPorts)
hTrue = complex([]);
if isempty(referenceWaveform) || isempty(pilotInd) || isempty(pilotSym)
    return;
end
[refGrid, ~] = sixgr.phy.waveform.ofdmDemodulate( ...
    carrier, referenceWaveform);
pilotObs = localReferenceGridPilotObservations(refGrid, carrier, pilotInd, nPorts);
pilotObs = localCollapsePilotObservations(pilotObs);
pilotSym = pilotSym(:);
N = min(numel(pilotObs), numel(pilotSym));
if N <= 0
    return;
end
pilotObs = pilotObs(1:N);
pilotSym = pilotSym(1:N);
den = pilotSym;
den(abs(den) < eps) = 1;
hTrue = pilotObs ./ den;
mask = isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    hTrue = complex([]);
end
end

function pilotObs = localReferenceGridPilotObservations(refGrid, carrier, pilotInd, nPorts)
pilotObs = complex([]);
if isempty(refGrid) || isempty(pilotInd)
    return;
end
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
if ~(isfinite(K) && K > 0 && isfinite(L) && L > 0)
    return;
end
nPorts = max(1, round(double(nPorts)));
idx = double(pilotInd(:));
idx = idx(isfinite(idx) & idx >= 1);
if isempty(idx)
    return;
end
try
    maxPort = max(nPorts, ceil(max(idx) / max(K * L, 1)));
    [k, l, ~] = ind2sub([K, L, maxPort], idx);
catch
    return;
end
n = numel(k);
pilotObs = complex(NaN(n, 1));
for ii = 1:n
    if k(ii) < 1 || k(ii) > size(refGrid, 1) || l(ii) < 1 || l(ii) > size(refGrid, 2)
        continue;
    end
    v = squeeze(refGrid(k(ii), l(ii), :));
    pilotObs(ii) = mean(v(:), "omitnan");
end
end

function symIdx = localPilotSymbolIndices(carrier, pilotInd, nPorts)
K = double(carrier.NSizeGrid) * 12;
L = double(carrier.SymbolsPerSlot);
[~, symIdx, ~] = ind2sub([K, L, max(1, round(double(nPorts)))], double(pilotInd(:)));
symIdx = double(symIdx(:));
end

function symbolTimes_s = localSymbolCenterTimes(carrier, sampleRateHz)
L = double(carrier.SymbolsPerSlot);
symbolTimes_s = [];
try
    ofdmInfo = nrOFDMInfo(carrier);
    symbolLengths = double(sixgr.util.structGet(ofdmInfo, "SymbolLengths", []));
    if ~isempty(symbolLengths)
        symbolLengths = symbolLengths(:);
        if numel(symbolLengths) < L
            symbolLengths(end+1:L, 1) = symbolLengths(end);
        end
        symbolLengths = symbolLengths(1:L);
        symbolTimes_s = (cumsum(symbolLengths) - 0.5 * symbolLengths) / max(sampleRateHz, eps);
    end
catch
end
if isempty(symbolTimes_s)
    slotDur_s = 1e-3 / max(double(carrier.SubcarrierSpacing) / 15, eps);
    symDur_s = slotDur_s / max(L, 1);
    symbolTimes_s = ((0:L-1).' + 0.5) * symDur_s;
end
end

function nmse = localNormalizedMSE(hEst, hTrue)
hEst = hEst(:);
hTrue = hTrue(:);
N = min(numel(hEst), numel(hTrue));
if N == 0
    nmse = NaN;
    return;
end
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    nmse = NaN;
    return;
end
err = hEst(mask) - hTrue(mask);
hEst = hEst(mask);
hTrue = hTrue(mask);
alpha = (hTrue' * hEst) / max(hTrue' * hTrue, eps);
ref = alpha * hTrue;
err = hEst - ref;
den = mean(abs(ref).^2, "omitnan");
nmse = mean(abs(err).^2, "omitnan") / max(den, eps);
end

function qcl = localReferenceCorrelation(hEst, hTrue)
qcl = NaN;
hEst = hEst(:);
hTrue = hTrue(:);
N = min(numel(hEst), numel(hTrue));
if N == 0
    return;
end
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    return;
end
hEst = hEst(mask);
hTrue = hTrue(mask);
den = norm(hEst) * norm(hTrue);
if den <= 0
    return;
end
qcl = abs(hTrue' * hEst) / den;
end

function dopplerHz = localEstimateDopplerHz(hEst, symTimes_s)
dopplerHz = NaN;
hEst = hEst(:);
symTimes_s = double(symTimes_s(:));
N = min(numel(hEst), numel(symTimes_s));
if N == 0
    return;
end
hEst = hEst(1:N);
symTimes_s = symTimes_s(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(symTimes_s);
if nnz(mask) < 2
    dopplerHz = 0;
    return;
end
maxTime = max(symTimes_s(mask), [], "omitnan");
if isfinite(maxTime) && maxTime >= 1e-2
    error("sixgr:link:SRS:DopplerEstimateUnexpectedTimescale", ...
        "SRS symbol times appear to be in wrong units (max %.6g s). Expected less than 10 ms.", maxTime);
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    dopplerHz = 0;
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
phaseObs = unwrap(angle(hMean(:)));
phaseRange = max(phaseObs) - min(phaseObs);
if isfinite(phaseRange) && phaseRange > 0.9 * pi
    warning("sixgr:link:SRS:PhaseUnwrapRisk", ...
        "SRS phase range %.2f rad exceeds 90%% of pi; Doppler estimation may wrap.", phaseRange);
end
p = polyfit(uTimes(:), phaseObs(:), 1);
dopplerHz = p(1) / (2 * pi);
end

function crlbHz = localDopplerCRLBHz(hEst, symTimes_s, nVar)
crlbHz = NaN;
hEst = hEst(:);
symTimes_s = double(symTimes_s(:));
N = min(numel(hEst), numel(symTimes_s));
if N < 2
    return;
end
hEst = hEst(1:N);
symTimes_s = symTimes_s(1:N);
mask = isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(symTimes_s);
if nnz(mask) < 2
    return;
end
[uTimes, ~, grp] = unique(symTimes_s(mask), "stable");
if numel(uTimes) < 2
    return;
end
hMean = accumarray(grp, hEst(mask), [], @localComplexMean);
if numel(hMean) < 2
    return;
end
snrLin = mean(abs(hMean).^2, "omitnan") / max(double(nVar), eps);
Lpilots = numel(hMean);
trep = mean(diff(uTimes), "omitnan");
if ~(isfinite(snrLin) && snrLin > 0 && isfinite(trep) && trep > 0 && Lpilots > 1)
    return;
end
crlbHz = sqrt(6 / (snrLin * Lpilots * (Lpilots^2 - 1) * (2 * pi * trep)^2));
end

function loss_dB = localInterpolationLossNormalized(symIdx, hEst, hTrue)
loss_dB = NaN;
symIdx = double(symIdx(:));
hEst = hEst(:);
hTrue = hTrue(:);
N = min([numel(symIdx), numel(hEst), numel(hTrue)]);
if N == 0
    return;
end
symIdx = symIdx(1:N);
hEst = hEst(1:N);
hTrue = hTrue(1:N);
mask = isfinite(symIdx) & isfinite(real(hEst)) & isfinite(imag(hEst)) & isfinite(real(hTrue)) & isfinite(imag(hTrue));
if nnz(mask) < 3
    loss_dB = 0;
    return;
end
[uSym, ~, grp] = unique(symIdx(mask), "stable");
if numel(uSym) < 3
    loss_dB = 0;
    return;
end
hEstSym = accumarray(grp, hEst(mask), [], @localComplexMean);
hTrueSym = accumarray(grp, hTrue(mask), [], @localComplexMean);
coarseSel = 1:2:numel(uSym);
if numel(coarseSel) < 2
    loss_dB = 0;
    return;
end
hInterp = complex( ...
    interp1(double(uSym(coarseSel)), real(hEstSym(coarseSel)), double(uSym), "linear", "extrap"), ...
    interp1(double(uSym(coarseSel)), imag(hEstSym(coarseSel)), double(uSym), "linear", "extrap"));
nmse = localNormalizedMSE(hInterp, hTrueSym);
loss_dB = 10 * log10(max(nmse, eps));
end

function sens_dB = localStaticMismatchSensitivity(hTrue)
sens_dB = NaN;
hTrue = hTrue(:);
mask = isfinite(real(hTrue)) & isfinite(imag(hTrue));
if ~any(mask)
    return;
end
hTrue = hTrue(mask);
hStatic = mean(hTrue, "omitnan");
nmse = mean(abs(hTrue - hStatic).^2, "omitnan") / max(mean(abs(hTrue).^2, "omitnan"), eps);
sens_dB = 10 * log10(max(nmse, eps));
end

function y = localComplexMean(x)
if isempty(x)
    y = complex(NaN);
else
    y = mean(x, "omitnan");
end
end
