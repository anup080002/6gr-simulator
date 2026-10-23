classdef PDCCHControlRuntime
    % Canonical shared PDCCH preparation, received trial and grant binding.
    % Extracted from runWaveformLinkBundle without a second receive policy.
    % queueShared requires already-resolved joint PDCCH admission; it only
    % queues physical control, never grants receiver/data authority.
    % completeShared consumes the original completed item exactly once.
    % logSink is the caller's existing runtime logger, not a policy hook.
    methods (Static)
        function [r,receivedAssignment,channelEvidence] = receiveTrial(preparedPDCCH,observation,grantContext,snr_dB,k,nVar,replay,scoring)
        % Receive-completion reducer for a retained control preparation. This stage
        % never regenerates TX, propagates fading, or executes an RF chain.
        cfgTrial = preparedPDCCH.ReceiverConfig;
        if nargin<8, scoring=struct(); end
        receivedAssignment=struct();
        channelEvidence=table();
        tx = preparedPDCCH.Tx;
        txInfo = preparedPDCCH.TxInfo;
        grantRNTI = double(txInfo.RNTI);
        dciFormatSeed = sixgr.truth.PDCCHControlRuntime.resolvePDCCHGrantDCIFormat(grantContext, "DL");
        dciBitsSeed = int8(sixgr.util.structGet(grantContext,"DCI.Bits",int8([])));
        r = sixgr.truth.makeLinkTrialRow(cfgTrial,"DL",snr_dB,k);
        r.Status = "FAIL";
        r.CRCPass = NaN;
        r.CRCApplicable = false;
        tDecode = tic;
        noiseVariance = [];
        if isfinite(double(nVar)) && double(nVar)>=0
            noiseVariance = nVar;
        end
        [rx,rxInfo] = sixgr.link.completePDCCHReception(preparedPDCCH,observation, ...
            "NoiseVariance",noiseVariance);
        r.PDCCHReceiverTrialExecuted = true;
        if rxInfo.ReceiverConfiguredMonitoring && ~isempty(fieldnames(grantContext))
            % One shared slot may carry both UL and DL commands for the same UE.
            % Route by received semantic direction, never by expected TX payload.
            [rx,rxInfo]=sixgr.link.selectConnectedPDCCHDirection(rx,rxInfo,grantContext.Direction);
        end
        if nargout>2 && logical(sixgr.util.structGet(cfgTrial,'outputs.phySignalDiagnosticEnabled',false))
            channelEvidence=sixgr.link.buildPDCCHChannelEstimateTable(rx);
        end
        if ~isempty(fieldnames(scoring))
            [metrics,paired]=sixgr.truth.scoreSharedPDCCHChannel( ...
                preparedPDCCH,rx,rxInfo,scoring.Observation,scoring.Evidence,replay);
            for field=string(fieldnames(metrics)).', r.(field)=metrics.(field); end
            if ~isempty(channelEvidence)
                channelEvidence=sixgr.link.bindPDCCHChannelReference(channelEvidence,paired);
            end
        end
        controlLatency_ms = toc(tDecode)*1e3;
        radioTTI_ms = sixgr.truth.PDCCHControlRuntime.slotDuration(cfgTrial)*1e3;
        [be, bt] = sixgr.truth.PDCCHControlRuntime.bitErrors(tx.DCIBits, rx.DCIBits);
        r = sixgr.truth.bindPDCCHReceiverObservation(r,rx,rxInfo);
        dciCrcPass = logical(r.DCICrcPass);
        payloadMatch = logical(sixgr.util.structGet(rx, "DCIPayloadMatch", (be == 0) && (bt == numel(tx.DCIBits))));
        ok = dciCrcPass && logical(rx.Ok) && payloadMatch;
        candidateT = sixgr.util.structGet(rxInfo, "CandidateResults", table());
        if ~istable(candidateT)
            candidateT = table();
        end
        decodedDci = sixgr.truth.PDCCHControlRuntime.decodeObservedPDCCHGrantDCI( ...
            rx, tx, dciFormatSeed, grantContext, cfgTrial);
        if rxInfo.ReceiverConfiguredMonitoring && rx.Ok
            receivedAssignment=sixgr.phy.pdcch.materializeConnectedDCI(rx,rxInfo,cfgTrial);
        end
        aggLevel = sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH, "AggregationLevel", NaN);
        usedCCEs = aggLevel;
        availCCEs = sixgr.truth.PDCCHControlRuntime.pdcchAvailableCCEs(tx.PDCCH);
        controlBits = double(sixgr.util.structGet(txInfo, "E", NaN));
        r.TBSize_bits = double(numel(tx.DCIBits));
        r.DCISize_bits = double(numel(tx.DCIBits));
        r.BitsCompared = double(bt);
        r.BitErrors = double(be);
        r.PDCCHPayloadMatch = logical(payloadMatch);
        r.PDCCHCausalGrantDecodeOk = logical(sixgr.util.structGet(rx, "CausalGrantDecodeOk", ok));
        r.PDCCHExpectedDCIBitCount = double(numel(tx.DCIBits));
        r.PDCCHDecodedDCIBitCount = double(numel(sixgr.util.structGet(rx, "DCIBits", int8([]))));
        r.PDCCHDCIBitsCompared = double(sixgr.util.structGet(rx, "DCIBitsCompared", bt));
        r.PDCCHDCIBitErrors = double(sixgr.util.structGet(rx, "DCIBitErrors", be));
        r.PDCCHMissedDetection = logical(sixgr.util.structGet(rx, "MissedDetection", ~dciCrcPass));
        r.PDCCHFalseAlarm = logical(sixgr.util.structGet(rx, "FalseAlarm", dciCrcPass && ~payloadMatch));
        r.PDCCHErrFlag = double(sixgr.util.structGet(rx, "ErrFlag", NaN));
        % BitErrors/BitsCompared remain TX-reference audit fields, never detector input.
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(replay, "ConfiguredSNR_dB", snr_dB));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(replay, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(replay, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(replay, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(replay, "NoiseVarianceSource", ""));
        r.ChannelModelApplied = string(sixgr.util.structGet(replay, "ChannelModelApplied", ""));
        r.ChannelFadingApplied = logical(sixgr.util.structGet(replay, "ChannelFadingApplied", false));
        r.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleGain_dB", NaN));
        r.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(replay, "AppliedLargeScaleLoss_dB", NaN));
        r.AppliedBasePathloss_dB = double(sixgr.util.structGet(replay, "AppliedBasePathloss_dB", NaN));
        r.AppliedPathloss_dB = double(sixgr.util.structGet(replay, "AppliedPathloss_dB", NaN));
        r.AppliedShadowFading_dB = double(sixgr.util.structGet(replay, "AppliedShadowFading_dB", NaN));
        r.AppliedO2I_dB = double(sixgr.util.structGet(replay, "AppliedO2I_dB", NaN));
        r.AppliedLargeScaleGainSource = string(sixgr.util.structGet(replay, "AppliedLargeScaleGainSource", ""));
        r.PowerContextAmplitudeUnit = string(sixgr.util.structGet( ...
            replay,"PowerContextAmplitudeUnit",""));
        r.PowerContextTotalTxPower_dBm = double(sixgr.util.structGet( ...
            replay,"PowerContextTotalTxPower_dBm",NaN));
        powerContext = sixgr.util.structGet(replay,"PowerContext",struct());
        r.PowerContextTxGain_dB = double(sixgr.util.structGet( ...
            powerContext,"TxGain_dB",NaN));
        r.PowerContextRxGain_dB = double(sixgr.util.structGet( ...
            powerContext,"RxGain_dB",NaN));
        r.PowerContextAdditionalLoss_dB = double(sixgr.util.structGet( ...
            powerContext,"AdditionalLoss_dB",NaN));
        r.CellTotalTxPower_dBm = double(sixgr.util.structGet( ...
            powerContext,"CellTotalTxPower_dBm",NaN));
        r.EndpointPowerBudget_dBm = double(sixgr.util.structGet( ...
            powerContext,"EndpointPowerBudget_dBm",NaN));
        r.ConcurrentTransmitterGrantCount = double(sixgr.util.structGet( ...
            powerContext,"ConcurrentTransmitterGrantCount",NaN));
        r.GrantPowerFraction = double(sixgr.util.structGet( ...
            powerContext,"GrantPowerFraction",NaN));
        r.GrantTargetTxPower_dBm = double(sixgr.util.structGet( ...
            powerContext,"GrantTargetTxPower_dBm",NaN));
        r.ScheduledPowerPolicy = string(sixgr.util.structGet( ...
            powerContext,"ScheduledPowerPolicy",""));
        r.ScheduledPowerAuthority = string(sixgr.util.structGet( ...
            powerContext,"ScheduledPowerAuthority",""));
        r.SharedCellBudgetApplied = logical(sixgr.util.structGet( ...
            powerContext,"SharedCellBudgetApplied",false));
        r.TxRFExecutionStatus = string(sixgr.util.structGet( ...
            replay,"TxRFExecutionStatus",""));
        r.TxRFStageOrder = string(sixgr.util.structGet( ...
            replay,"TxRFStageOrder",""));
        r.TxRFAppliedStageCount = double(sixgr.util.structGet( ...
            replay,"TxRFAppliedStageCount",0));
        r.CompositeReceiverFrontEndApplied = logical(sixgr.util.structGet( ...
            replay,"CompositeReceiverFrontEndApplied",false));
        r.CompositeReceiverFrontEndStatus = string(sixgr.util.structGet( ...
            replay,"CompositeReceiverFrontEndStatus",""));
        r.ServingRSRP_dBm = double(sixgr.util.structGet(replay, "ServingRSRP_dBm", NaN));
        r.ServingRSRPSource = string(sixgr.util.structGet(replay, "ServingRSRPSource", ""));
        r.LargeScaleSINR_dB = double(sixgr.util.structGet(replay, "LargeScaleSINR_dB", NaN));
        r.LargeScaleSINRSource = string(sixgr.util.structGet(replay, "LargeScaleSINRSource", ""));
        r.InterferenceMode = string(sixgr.util.structGet(replay, "InterferenceMode", ""));
        r.InjectedCFO_Hz = double(sixgr.util.structGet(replay, "InjectedCFO_Hz", NaN));
        r.TrueCFO_Hz = r.InjectedCFO_Hz;
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(replay, "InjectedTimingOffset_samples", 0));
        r.TrueTimingOffset_samples = NaN; % RF delay alone is not received arrival timing.
        r.IQImbalanceConfigured = logical(sixgr.util.structGet(replay, "IQImbalanceConfigured", false));
        r.IQImbalanceApplied = logical(sixgr.util.structGet(replay, "IQImbalanceApplied", false));
        r.IQImbalanceModel = string(sixgr.util.structGet(replay, "IQImbalanceModel", ""));
        r.ConfiguredIQGainImbalance_dB = double(sixgr.util.structGet(replay, "ConfiguredIQGainImbalance_dB", NaN));
        r.ConfiguredIQPhaseImbalance_deg = double(sixgr.util.structGet(replay, "ConfiguredIQPhaseImbalance_deg", NaN));
        r.IQImbalanceMirrorPowerRatio_dB = double(sixgr.util.structGet(replay, "IQImbalanceMirrorPowerRatio_dB", NaN));
        r.IQImbalanceImageRejection_dB = double(sixgr.util.structGet(replay, "IQImbalanceImageRejection_dB", NaN));
        r.IQImbalanceIQPowerRatio_dB = double(sixgr.util.structGet(replay, "IQImbalanceIQPowerRatio_dB", NaN));
        r.IQImbalanceIQCorrelation = double(sixgr.util.structGet(replay, "IQImbalanceIQCorrelation", NaN));
        r.IQImbalanceEstimatedAlphaAbs = double(sixgr.util.structGet(replay, "IQImbalanceEstimatedAlphaAbs", NaN));
        r.IQImbalanceEstimatedBetaAbs = double(sixgr.util.structGet(replay, "IQImbalanceEstimatedBetaAbs", NaN));
        r.IQImbalanceMeasurementSource = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementSource", ""));
        r.IQImbalanceMeasurementStatus = string(sixgr.util.structGet(replay, "IQImbalanceMeasurementStatus", ""));
        r.ReceiverHestSINR_dB = double(sixgr.util.structGet(rx, "ReceiverHestSINR_dB", NaN));
        r.ReceiverHestSINRSource = string(sixgr.util.structGet(rx, "ReceiverHestSINRSource", ""));
        r.ReceiverHestSINRValueRole = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueRole", ""));
        r.ReceiverHestSINRValueStatus = string(sixgr.util.structGet(rx, "ReceiverHestSINRValueStatus", ""));
        r.ReceiverHestSINRNAReason = string(sixgr.util.structGet(rx, "ReceiverHestSINRNAReason", ""));
        r.MeasuredTrialSINR_dB = NaN;
        r.MeasuredTrialSINRSource = "";
        r.MeasuredTrialSINRValueRole = "unavailable";
        r.MeasuredTrialSINRValueStatus = "unavailable";
        r.MeasuredTrialSINRNAReason = "pdcch_has_no_data_post_equalization_sinr_measurement";
        r.NoiseVariance = double(sixgr.util.structGet(rx, "NoiseVar", NaN));
        r.NoiseVarStatus = string(sixgr.util.structGet(rx, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(rx, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(rx, "NoiseVarReason", ""));
        r.NoiseVarianceDomain = "resource_grid_pre_equalization";
        r.NoiseVarianceSource = r.NoiseVarSource;
        if strlength(strtrim(r.NoiseVarStatus)) == 0 && isfinite(r.NoiseVariance) && r.NoiseVariance > 0
            r.NoiseVarStatus = "OK";
            r.NoiseVarSource = "pdcch_receiver_noise_variance";
        elseif ~(isfinite(r.NoiseVariance) && r.NoiseVariance > 0)
            r.NoiseVarStrictFailure = true;
            r.NoiseVarReason = "pdcch_noise_variance_missing_or_nonpositive";
        elseif r.NoiseVarStatus ~= "OK"
            r.NoiseVarStrictFailure = true;
        end
        if sixgr.truth.PDCCHControlRuntime.thermalNoiseSINRUnavailable(replay)
            r = sixgr.truth.PDCCHControlRuntime.markControlSINRUnavailable(r, ...
                "thermal_noise_sinr_unavailable_without_runtime_rx_power_or_pathloss");
        end
        r.EVM_rms = double(sixgr.util.structGet(rx, "EVM_rms", NaN));
        for evmField=["EVMValueStatus","EVMReferenceSource","EVMErrorEnergy", ...
                "EVMReferenceEnergy","EVMSymbolCount","EVMEnergyUnit","EVMComputationDomain"]
            if isfield(rx,evmField), r.(evmField)=rx.(evmField); end
        end
        r.DecodeAttempted = true;
        r.DecodeUsable = logical(ok);
        r.MeasurementAttempted = true;
        r.MeasurementUsable = isfinite(r.ReceiverHestSINR_dB) && ...
            sixgr.util.isAcceptableSINRStatus(r.ReceiverHestSINRValueStatus);
        % Primary evidence is this actual received candidate set. Independent
        % noise-only false-alarm campaigns remain separate observations, not
        % a second RF execution used to accept or reject this scheduled DCI.
        r.FalseAlarmFlag = double(r.PDCCHFalseAlarm);
        r.FalseAlarmClassification = "actual_received_dci_payload_mismatch";
        r.NoiseFalseAlarmFlag = NaN;
        r.PDCCHObservationStartSample = rxInfo.ObservationStartSample;
        r.PDCCHObservationEndSampleExclusive = rxInfo.ObservationEndSampleExclusive;
        r.PDCCHObservationCompletionTime_s = rxInfo.ObservationCompletionTime_s;
        r.PDCCHMinimumReceiveSamples = rxInfo.ReceiveExtent.MinimumReceiveSamples;
        r.PDCCHDemodulatedSymbols = rxInfo.DemodulatedSymbols;
        r.PDCCHReceivePaddingApplied = rxInfo.ReceivePaddingApplied;
        r.BlockingFlag = double(isfinite(aggLevel) && isfinite(availCCEs) && aggLevel > availCCEs);
        r.BlindDecodeCount = double(sixgr.util.structGet(rxInfo, "NumDecodeHypothesesTried", height(candidateT)));
        r.AvailableCCECount = availCCEs;
        r.UsedCCECount = usedCCEs;
        r.NonOverlappedCCEUsage = usedCCEs / max(availCCEs, 1);
        r.AggregationLevel = aggLevel;
        r.CandidatesAttempted = double(rxInfo.NumCandidatesTried);
        r.PDCCHBlindSearchEnabled = logical(sixgr.util.structGet(rxInfo, "BlindSearch", false));
        r.PDCCHCandidatesAvailable = double(sixgr.util.structGet(rxInfo, "NumCandidatesAvailable", height(candidateT)));
        r.PDCCHCandidatesAttempted = r.CandidatesAttempted;
        txCandidateIndex = sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH, "AllocatedCandidate", 1) - 1;
        selectedAggregationLevel = double(sixgr.util.structGet( ...
            rx, "CandidateAggregationLevel", NaN));
        selectedCandidateIndex = double(sixgr.util.structGet( ...
            rx, "CandidateIndexWithinAggregation", NaN));
        r.PDCCHCandidateIndex = double(txCandidateIndex);
        r.PDCCHCandidateFlatIndex = double(sixgr.util.structGet( ...
            rx, "CandidateFlatIndex", sixgr.util.structGet(rx, "CandidateIndex", NaN)));
        r.PDCCHSelectedAggregationLevel = selectedAggregationLevel;
        r.PDCCHSelectedCandidateIndex = selectedCandidateIndex;
        r.PDCCHSelectedCCEIndex = double(sixgr.util.structGet(rx,'CandidateCCEIndex',NaN));
        r.SelectedCCEIndex = r.PDCCHSelectedCCEIndex;
        nCI=double(sixgr.util.structGet(cfgTrial,'phy.pdcch.searchSpace.nCI',0));
        assert(isscalar(nCI) && nCI==0,'sixgr:truth:UnsupportedPDCCHCarrierIndicator', ...
            'Toolbox-generated resources use nCI=0; metadata must not describe another resource map.');
        r.TxCCEIndex = sixgr.phy.pdcch.candidateFirstCCE( ...
            tx.Carrier,tx.PDCCH,aggLevel,txCandidateIndex,false);
        r.PDCCHTxCCEIndex = r.TxCCEIndex;
        r.PDCCHDCICrcRNTI = double(sixgr.util.structGet(txInfo, "DCICrcRNTI", NaN));
        r.PDCCHScramblingRNTI = double(sixgr.util.structGet(txInfo, "PDCCHScramblingRNTI", NaN));
        r.PDCCHEncodedBits = controlBits;
        r.PDCCHRECount = double(sixgr.util.structGet(txInfo, "NumPDCCHRE", numel(tx.PDCCHInd)));
        r.PDCCHDMRSRECount = double(sixgr.util.structGet(txInfo, "NumDMRSRE", numel(tx.DMRSInd)));
        r.PDCCHCandidateErrFlagVector = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "ErrFlag", nan(height(candidateT), 1)));
        r.PDCCHCandidateDecodeOKVector = sixgr.truth.PDCCHControlRuntime.formatNumericVector(double(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "DecodeOK", false(height(candidateT), 1))));
        r.PDCCHCandidateSINRVector_dB = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "ReceiverHestSINR_dB", nan(height(candidateT), 1)));
        r.PDCCHCandidateRECountVector = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "PDCCHRECount", nan(height(candidateT), 1)));
        r.PDCCHCandidateDMRSRECountVector = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "DMRSRECount", nan(height(candidateT), 1)));
        r.PDCCHCandidateAggregationLevelVector = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "AggregationLevel", nan(height(candidateT), 1)));
        r.PDCCHCandidateWithinAggregationVector = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.columnOrDefault(candidateT, "CandidateIndexWithinAggregation", nan(height(candidateT), 1)));
        r.PDCCHHypothesisReductionClass = string(sixgr.util.structGet(rxInfo, "HypothesisReductionClass", ""));
        r.PDCCHHypothesisReductionScope = string(sixgr.util.structGet(rxInfo, "DirectionalConsumer", "all_monitored_DCI"));
        r.PDCCHCompositeHypothesisReductionClass = string(sixgr.util.structGet(rxInfo, "CompositeHypothesisReductionClass", rxInfo.HypothesisReductionClass));
        r.PDCCHCompositeValidHypothesisCount = double(sixgr.util.structGet(rxInfo, "CompositeValidHypothesisCount", rxInfo.ValidHypothesisCount));
        r.PDCCHEquivalentValidHypothesisCount = double(sixgr.util.structGet(rxInfo, "EquivalentValidHypothesisCount", 0));
        r.PDCCHAmbiguousValidHypothesisCount = double(sixgr.util.structGet(rxInfo, "AmbiguousHypothesisCount", 0));
        r.PDCCHCRCDecodeSource = "nrDCIDecode_crc_masked_by_rnti";
        r.PDCCHBlindDecodeEvidenceSource = "nrPDCCHSpace_nrPDCCHDecode_nrDCIDecode";
        r.PDCCHCCE_REGMappingEvidence = "nrPDCCHResources_coreset_search_space_candidate_mapping";
        r.PDCCHREGMappingAvailable = ~isempty(tx.PDCCHInd) && ~isempty(tx.DMRSInd);
        r.PDCCHCORESETDuration = sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH.CORESET, "Duration", NaN);
        controlResources=sixgr.truth.pdcchResourceIntervalEvidence(tx);
        r.PDCCHCORESETStartSymbol=controlResources.PDCCHCORESETStartSymbol;
        r.PDCCHAllocatedPRBSetJSON=controlResources.PDCCHAllocatedPRBSetJSON;
        r.PDCCHCORESETFrequencyResources = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.pdcchScalarVector(tx.PDCCH.CORESET, "FrequencyResources"));
        r.PDCCHSearchSpaceNumCandidates = sixgr.truth.PDCCHControlRuntime.formatNumericVector(sixgr.truth.PDCCHControlRuntime.pdcchScalarVector(tx.PDCCH.SearchSpace, "NumCandidates"));
        configuredCORESETId = double(sixgr.util.structGet(cfgTrial, ...
            "phy.pdcch.coreset.id", 0));
        configuredSearchSpaceId = double(sixgr.util.structGet(cfgTrial, ...
            "phy.pdcch.searchSpace.id", 1));
        r.CORESETId = sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH.CORESET, ...
            "CORESETID", sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH.CORESET, ...
            "ID", configuredCORESETId));
        r.SearchSpaceId = sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH.SearchSpace, ...
            "SearchSpaceID", sixgr.truth.PDCCHControlRuntime.pdcchScalar(tx.PDCCH.SearchSpace, ...
            "ID", configuredSearchSpaceId));
        % CandidateIndex is the transmitted zero-based candidate within the
        % configured aggregation level. The receiver's flat blind-attempt
        % ordinal and selected hypothesis are exported separately above.
        r.CandidateIndex = double(txCandidateIndex);
        r.DCIFormat = string(dciFormatSeed);
        r.DCIId = string(sixgr.util.structGet(decodedDci, "PayloadHash", ""));
        r.DCIFieldsHash = string(sixgr.truth.PDCCHControlRuntime.hashDecodedPDCCHGrantFields(decodedDci, r.PDCCHDCICrcRNTI));
        r.DecodedDCIHARQProcessId = double(sixgr.util.structGet(decodedDci, "Fields.harq_process", NaN));
        r.DecodedDCIPRBStart = double(sixgr.util.structGet(decodedDci, "Fields.prb_start", NaN));
        r.DecodedDCIAllocatedPRBCount = double(sixgr.util.structGet(decodedDci, "Fields.num_prb", NaN));
        r.DecodedDCISymbolStart = double(sixgr.util.structGet(decodedDci, "Fields.symbol_start", NaN));
        r.DecodedDCINumSymbols = double(sixgr.util.structGet(decodedDci, "Fields.num_symbols", NaN));
        r.DecodedDCIMCSIndex = double(sixgr.util.structGet(decodedDci, "Fields.mcs", NaN));
        r.DecodedDCIRV = double(sixgr.util.structGet(decodedDci, "Fields.rv", NaN));
        r.DecodedDCINDI = double(sixgr.util.structGet(decodedDci, "Fields.ndi", NaN));
        r.DecodedDCITimeDomainAssignmentIndex = double(sixgr.util.structGet(decodedDci, ...
            "Fields.time_domain_assignment_index",sixgr.util.structGet(decodedDci,"Fields.time_resource_assignment",NaN)));
        r.DecodedDCITCICodepoint = double(sixgr.util.structGet(decodedDci,"Fields.transmission_configuration_indication",NaN));
        if ~isempty(fieldnames(receivedAssignment))
            receivedFields=sixgr.truth.connectedDCIAssignmentEvidence(receivedAssignment);
            for fieldName=string(fieldnames(receivedFields)).'
                r.(fieldName)=receivedFields.(fieldName);
            end
        end
        r.LinkedGrantId = string(sixgr.util.structGet(grantContext, "GrantContextId", ""));
        r.LinkedPDSCHOrPUSCH = upper(string(sixgr.util.structGet(grantContext, "Direction", "")));
        r.PDCCHGridHash = sixgr.truth.PDCCHControlRuntime.complexSHA256(tx.Grid);
        r.PDCCHWaveformHash = sixgr.truth.PDCCHControlRuntime.complexSHA256(tx.Waveform);
        r.PDCCHResourceHash = sixgr.truth.PDCCHControlRuntime.pdcchResourceHash(tx.PDCCHInd, tx.DMRSInd);
        r.ControlCapacityBits = controlBits;
        r.ControlCapacityUtilization = double(numel(tx.DCIBits)) / max(controlBits, 1);
        r.CORESETUtilization = usedCCEs / max(availCCEs, 1);
        r.ComputeLatency_ms = controlLatency_ms;
        r.ProcedureDelay_ms = NaN;
        r.AirInterfaceTTI_ms = radioTTI_ms;
        % Legacy alias preserved for backward compatibility with older exports.
        % It mirrors the control opportunity duration, not wall-clock decode runtime.
        r.ControlLatency_ms = radioTTI_ms;
        r.ResourceExtractionAttempted = true;
        r.ResourceExtractionAvailable = ~isempty(tx.PDCCHInd) && ~isempty(rx.EqualizedSymbols);
        r.ChannelEstimateAttempted = true;
        r.ChannelEstimateAvailable = sixgr.truth.PDCCHControlRuntime.hasFiniteNumericEvidence(sixgr.util.structGet(rx, "ChannelEstimate", []));
        r.ChannelEstimateSource = "nrChannelEstimate_pdcch_dmrs";
        r = sixgr.truth.bindReceiverSINRApplicability(r);
        r.EqualizationAttempted = true;
        r.EqualizationAvailable = sixgr.truth.PDCCHControlRuntime.hasFiniteNumericEvidence(sixgr.util.structGet(rx, "EqualizedSymbols", []));
        noiseOk = isfinite(r.NoiseVariance) && r.NoiseVariance > 0 && strcmpi(string(r.NoiseVarStatus), "OK") && ...
            ~logical(r.NoiseVarStrictFailure);
        strictOk = logical(ok) && logical(r.DetectionUsable) && logical(r.MeasurementUsable) && ...
            logical(r.ChannelEstimateAvailable) && logical(r.ResourceExtractionAvailable) && ...
            logical(r.EqualizationAvailable) && noiseOk && ~logical(r.FalseAlarmFlag);
        r.StrictReceiverEvidenceOk = logical(strictOk);
        r.StrictOk = logical(strictOk);
        r.ReceiverUsable = logical(strictOk);
        r.TruthStatus = "real_pdcch_waveform_blind_dci_crc_evidence";
        r.SourceClassification = "active_integrated";
        r.RuntimeMaterializationStatus = "active_integrated_pdcch_blind_dci_crc_cce_reg_evidence";
        r.RuntimeEvidenceSource = "sixgr.phy.dl.PDCCH_Tx|sixgr.phy.dl.PDCCH_Rx";
        r.RuntimeIntegrationMode = "coupled_slot_runtime";
        % Decoding configured test bits is a physical receiver observation, not
        % proof that a scheduled grant was installed into the connected runtime.
        if isempty(fieldnames(grantContext))
            r.SourceClassification = "isolated_component_waveform";
            r.RuntimeMaterializationStatus = "isolated_pdcch_blind_dci_crc_cce_reg_evidence";
            r.RuntimeIntegrationMode = "isolated_component_waveform";
            r.ControlGatingEffect = "none_isolated_component";
            r.RuntimeStateConsumer = "none_isolated_component";
            r.RuntimeConsumer = "none_isolated_component";
        end
        r.RuntimeTransportMode = "pdcch_tx_runtime_channel_rf_noise_pdcch_rx";
        r.RuntimeStageWaveformsRequired = true;
        r.RuntimeStageWaveformsUsed = true;
        r.RuntimeSelfLoopWaveformsUsed = false;
        r.RuntimeChannelStateUsed = logical(sixgr.util.structGet( ...
            replay, "RuntimeChannelStateUsed", false));
        injectedVariance = double(sixgr.util.structGet(replay,"InjectedNoiseVariance",NaN));
        r.RuntimeNoiseApplied = isfinite(injectedVariance) && injectedVariance > 0;
        r.RuntimeNoiseVarianceMean = double(nVar);
        r.RuntimeChannelLinkKeys = string(sixgr.util.structGet( ...
            replay, "RuntimeChannelLinkKey", ""));
        r.RuntimeStageCount = 5;
        if strictOk
            r.Status = "PASS";
        else
            r.Status = "FAIL";
            r.FailureReason = sixgr.truth.PDCCHControlRuntime.pdcchStrictFailureReason(r, rx, be, bt, payloadMatch, dciCrcPass, noiseOk);
        end
        if ~isempty(dciBitsSeed)
            r.Notes = "Grant-coupled PDCCH DCI payload decoded through blind candidate search, channel estimation, MMSE equalization, and RNTI-masked DCI CRC.";
        end
        end

        function [T, grant] = annotateGrant(T, grant, cfg, direction)
        if nargin < 3 || ~isstruct(cfg)
            cfg = struct();
        end
        if nargin < 4
            direction = sixgr.util.structGet(grant, "Direction", "DL");
        end
        if ~isstruct(grant)
            return;
        end

        direction = upper(strtrim(string(direction)));
        binding = sixgr.truth.PDCCHControlRuntime.resolvePDCCHGrantBinding(cfg, grant, direction, T);
        grant.PDCCHGrantBindingRequired = logical(binding.Required);
        grant.PDCCHGrantBindingOk = logical(binding.Ok);
        grant.PDCCHGrantBindingStatus = char(string(binding.Status));
        grant.PDCCHGrantBindingFailureCode = char(string(binding.FailureCode));
        grant.PDCCHGrantDCIId = char(string(binding.DCIId));
        grant.PDCCHGrantDCIFieldsHash = char(string(binding.DCIFieldsHash));
        grant.PDCCHGrantFieldsHash = char(string(binding.GrantFieldsHash));
        grant.PDCCHGrantSearchSpaceId = double(binding.SearchSpaceId);
        grant.PDCCHGrantCORESETId = double(binding.CORESETId);
        grant.PDCCHGrantAggregationLevel = double(binding.AggregationLevel);
        grant.PDCCHGrantCandidateIndex = double(binding.CandidateIndex);
        grant.PDCCHGrantDCIFormat = char(string(binding.DCIFormat));
        grant.PDCCHGrantFirstCCE = NaN;
        grant.PDCCHGrantNumCCE = NaN;
        if binding.Ok && istable(T) && ~isempty(T)
            % Retain the received candidate, not the configured/transmitted candidate
            % or a fixed CORESET size. This same DCI owns later HARQ resource mapping.
            grant = sixgr.truth.bindReceivedPDCCHGrantContext(grant,T(end,:));
            binding.AggregationLevel = grant.PDCCHGrantAggregationLevel;
            binding.CandidateIndex = grant.PDCCHGrantCandidateIndex;
        end

        if ~(istable(T) && ~isempty(T))
            return;
        end

        heightT = height(T);
        transmittedLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
        rankIndicator = double(sixgr.util.structGet(grant, "RIUsed", ...
            sixgr.util.structGet(grant, "RankIndicator", ...
            sixgr.util.structGet(grant, "RI", ...
            sixgr.util.structGet(grant, "Rank", transmittedLayers)))));
        if ~(isfinite(rankIndicator) && rankIndicator >= 1) && isfinite(transmittedLayers) && transmittedLayers >= 1
            rankIndicator = double(transmittedLayers);
        end
        controlResourceValid = logical(binding.Ok) && ...
            isfinite(double(binding.SearchSpaceId)) && ...
            isfinite(double(binding.CORESETId)) && ...
            isfinite(double(binding.AggregationLevel)) && ...
            double(binding.AggregationLevel) > 0 && ...
            isfinite(double(binding.CandidateIndex));
        annotations = {
            "PDCCHAdmissionPolicy", string(sixgr.util.structGet(grant,"PDCCHAdmissionPolicy",""));
            "PDCCHAdmissionSelected", double(sixgr.util.structGet(grant,"PDCCHAdmissionSelected",NaN));
            "PDCCHPlannedCandidateIndex", double(sixgr.util.structGet(grant,"PDCCHPlannedCandidateIndex",NaN));
            "PDCCHGatingActive", logical(sixgr.util.structGet(grant, "PDCCHGatingActive", false));
            "GrantControlState", string(sixgr.util.structGet(grant, "GrantControlState", "control_pending"));
            "ControlDecodeOk", logical(sixgr.util.structGet(grant, "ControlDecodeOk", false));
            "PDCCHReceiverDecodeOk", double(sixgr.util.structGet(grant,"PDCCHReceiverDecodeOk",NaN));
            "PDCCHDataAdmissionOk", double(sixgr.util.structGet(grant,"PDCCHDataAdmissionOk",NaN));
            "PDCCHTCIAdmissionStatus", string(sixgr.util.structGet(grant,"PDCCHTCIAdmissionStatus",""));
            "PDCCHControlFailureReason", string(sixgr.util.structGet(grant,"PDCCHControlFailureReason",""));
            "UEID", double(sixgr.util.structGet(grant, "UEIndex", NaN));
            "BaseStationID", double(sixgr.util.structGet(grant, "ServingCell", NaN));
            "GrantFrame", double(sixgr.util.structGet(grant, "Frame", NaN));
            "GrantSlot", double(sixgr.util.structGet(grant, "Slot", NaN));
            "ControlFrame", double(sixgr.util.structGet(grant, "ControlFrame", NaN));
            "ControlSlot", double(sixgr.util.structGet(grant, "ControlSlot", NaN));
            "ScheduledAbsoluteSlot", double(sixgr.util.structGet(grant, "ScheduledAbsoluteSlot", sixgr.util.structGet(grant, "Slot", NaN)));
            "GrantContextId", string(sixgr.util.structGet(grant, "GrantContextId", ""));
            "LinkedGrantId", string(sixgr.util.structGet(grant, "GrantContextId", ""));
            "LinkedPDSCHOrPUSCH", direction;
            "K2Slots", double(sixgr.util.structGet(grant, "K2Slots", NaN));
            "LastSuccessfulSRSSlot", double(sixgr.util.structGet(grant, "LastSuccessfulSRSSlot", NaN));
            "SRSAgeSlots", double(sixgr.util.structGet(grant, "SRSAgeSlots", NaN));
            "AllocatedPRBCount", double(numel(double(sixgr.util.structGet(grant, "PRBSet", []))));
            "PRBStart", double(sixgr.truth.PDCCHControlRuntime.firstFinite(double(sixgr.util.structGet(grant, "PRBSet", [])), NaN));
            "MCSIndex", double(sixgr.util.structGet(grant, "MCSIndex", NaN));
            "Layers", transmittedLayers;
            "Rank", transmittedLayers;
            "RankIndicator", rankIndicator;
            "GrantValid", logical(sixgr.util.structGet(grant, "GrantValid", false));
            "NegativeExpectedOk", logical(sixgr.util.structGet(grant, "NegativeExpectedOk", false));
            "ControlResourceValidity", controlResourceValid;
            "GrantBindingRequired", logical(binding.Required);
            "GrantBindingOk", logical(binding.Ok);
            "GrantBindingStatus", string(binding.Status);
            "GrantBindingFailureCode", string(binding.FailureCode);
            "GrantFieldsHash", string(binding.GrantFieldsHash);
            "DCIFieldsHash", string(binding.DCIFieldsHash);
            "DCIId", string(binding.DCIId);
            "GrantSearchSpaceId", double(binding.SearchSpaceId);
            "GrantCORESETId", double(binding.CORESETId);
            "AggregationLevel", double(binding.AggregationLevel);
            "CandidateIndex", double(binding.CandidateIndex);
            "DCIFormat", string(binding.DCIFormat);
            "PDCCHGrantBindingRequired", logical(binding.Required);
            "PDCCHGrantBindingOk", logical(binding.Ok);
            "PDCCHGrantBindingStatus", string(binding.Status);
            "PDCCHGrantBindingFailureCode", string(binding.FailureCode);
            "PDCCHGrantDCIId", string(binding.DCIId);
            "PDCCHGrantDCIFieldsHash", string(binding.DCIFieldsHash);
            "PDCCHGrantFieldsHash", string(binding.GrantFieldsHash);
            "PDCCHGrantSearchSpaceId", double(binding.SearchSpaceId);
            "PDCCHGrantCORESETId", double(binding.CORESETId);
            "PDCCHGrantAggregationLevel", double(binding.AggregationLevel);
            "PDCCHGrantCandidateIndex", double(binding.CandidateIndex);
            "PDCCHGrantDCIFormat", string(binding.DCIFormat)
            };
        for i = 1:size(annotations, 1)
            name = char(annotations{i, 1});
            value = annotations{i, 2};
            if isstring(value) || ischar(value)
                token = string(value);
                if ~isscalar(token)
                    token = token(1);
                end
                T.(name) = repmat(token, heightT, 1);
            elseif islogical(value)
                flag = logical(value);
                if ~isscalar(flag)
                    flag = flag(1);
                end
                T.(name) = repmat(flag, heightT, 1);
            else
                numValue = double(value);
                if ~isscalar(numValue)
                    numValue = sixgr.truth.PDCCHControlRuntime.firstFinite(numValue, NaN);
                end
                T.(name) = repmat(numValue, heightT, 1);
            end
        end
        end

        function state=completeShared(state,item,logSink)
        c=item.Context; p=c.Prepared;
        [post,~,~,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        [reference,referenceEvidence]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        scoring=struct('Observation',reference,'Evidence',referenceEvidence);
        [raw,receivedAssignment,channelEvidence]=sixgr.truth.PDCCHControlRuntime.receiveTrial(p,receiver,c.Grant,c.SNR,1, ...
            double(sixgr.util.structGet(replay,'SampleNoiseVariance',NaN)),replay,scoring);
        if ~isempty(channelEvidence)
            n=height(channelEvidence);
            channelEvidence.AbsoluteSlot0=repmat(double(c.Slot-1),n,1);
            channelEvidence.UEIndex=repmat(double(item.UE),n,1);
            channelEvidence.ServingCell=repmat(double(c.ServingCell),n,1);
            channelEvidence.SNR_dB=repmat(double(c.SNR),n,1);
            channelEvidence.ObservationStartSample=repmat(double(receiver.StartSample),n,1);
            channelEvidence.ObservationEndSampleExclusive=repmat(double(receiver.EndSampleExclusive),n,1);
            channelEvidence.GrantDirection=repmat(string(c.Direction),n,1);
            channelEvidence.Direction=repmat("DL",n,1);
            channelEvidence.SignalName=repmat("PDCCH",n,1);
            state.ControlTrials.PDCCHChannelEstimate=sixgr.truth.PDCCHControlRuntime.appendCompatTable( ...
                sixgr.util.structGet(state.ControlTrials,'PDCCHChannelEstimate',table()),channelEvidence);
        end
        if logical(sixgr.util.structGet(raw,'Crash',false))
            logSink("WARN", ...
                "Shared PDCCH receive completion failed: ue=%d slot=%d id=%s notes=%s", ...
                item.UE,c.Slot,string(sixgr.util.structGet(raw,'FailureReason',"")), ...
                string(sixgr.util.structGet(raw,'Notes',"")));
        end
        trial=sixgr.truth.PDCCHControlRuntime.annotateCoupledControlTrial(struct2table(raw),c.Slot,c.Frame,item.UE,c.RNTI,c.Direction,c.ServingCell);
        trial=sixgr.truth.bindSharedRFExecutionEvidence(trial,item.Planes,true);
        [trial,grant]=sixgr.truth.PDCCHControlRuntime.annotateGrant(trial,c.Grant,c.Config,c.Direction);
        [state,grant,allowed]=sixgr.truth.CoupledTruthRuntime.applyPDCCHGrantTrial(state,grant,c.Direction,trial);
        [trial,grant]=sixgr.truth.PDCCHControlRuntime.annotateGrant(trial,grant,c.Config,c.Direction);
        trial.ObservationStartSample=post.StartSample;
        trial.ObservationEndSampleExclusive=post.EndSampleExclusive;
        trial.ObservationCompletionTime_s=post.EndSampleExclusive/post.SampleRateHz;
        trial.RuntimeTransportMode="shared_physical_stream_PDCCH_received_completion";
        state.ControlTrials.PDCCH=sixgr.truth.PDCCHControlRuntime.appendCompatTable(state.ControlTrials.PDCCH,trial);
        tx=p.Tx;
        observed=sixgr.truth.buildObservedREAllocation(struct('Carrier',tx.Carrier,'Grid',tx.Grid, ...
            'PDCCHIndices',tx.PDCCHInd,'DMRSIndices',tx.DMRSInd), ...
            'Direction','DL','Channel','PDCCH','AbsoluteSlot',c.Slot-1, ...
            'CellID',double(tx.Carrier.NCellID),'UEID',item.UE,'AllocationID',"pdcch_"+c.Key);
        state.ObservedREAllocationTable=sixgr.truth.PDCCHControlRuntime.appendObservedREAllocation( ...
            sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observed);
        controls=sixgr.util.structGet(state,'SharedReceivedGrantControls',{});
        assert(~any(cellfun(@(x)x.Key==c.Key,controls)), ...
            'sixgr:truth:DuplicateSharedGrantControl','One scheduled DCI must be committed once.');
        controls{end+1}=struct('Key',c.Key,'Grant',grant,'Allowed',allowed, ...
            'ReceivedAssignment',receivedAssignment, ...
            'AvailableAtSample',post.EndSampleExclusive);
        if ~allowed
            controls{end}.ReceiverTrial=raw;
            controls{end}.RejectedControlObservation=post;
        end
        state.SharedReceivedGrantControls=controls;
        if c.Direction=="DL" && allowed && isfinite(raw.DecodedDCITCICodepoint)
            grant.ReceivedTCICodepoint=raw.DecodedDCITCICodepoint;
            if raw.DecodedDCIAssignmentAvailable
                grant.ReceivedTCIConfigurationEpoch=raw.DecodedDCIConfigurationEpoch;
            else
                grant.ReceivedTCIConfigurationEpoch=double(sixgr.util.structGet(c.Grant,'DCI.ContextData.ConfigurationEpoch',NaN));
            end
            controls{end}.Grant=grant;
            state.SharedReceivedGrantControls=controls;
        end
        logSink("INFO","Shared %s DCI received: ue=%d control_slot=%d data_slot=%d allowed=%d sample=%d.", ...
            c.Direction,item.UE,c.Slot,grant.Slot,allowed,post.EndSampleExclusive);
        if c.Direction~="UL", return; end
        if ~allowed
            if sixgr.phy.frame.resolveDuplexMode(c.UserCfg{item.UE})=="TDD"
                state=sixgr.truth.queueSharedPUSCHAfterRejectedControl(state,c.UserCfg{item.UE},controls{end});
            else
                state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime(state,grant,'UL');
            end
            return;
        end
        state=sixgr.truth.queueReceivedULGrantPreparation(state,item,controls{end});
        end

        function [state, qualifiedGrants, queuedGrants] = queueShared(state, userCfg, grants, direction, snr_dB, logSink)
        assert(isfield(state,'SharedWaveformStream'), ...
            'sixgr:truth:SharedPDCCHOwnerRequired','This queue boundary requires the live shared owner.');
        qualifiedGrants = repmat(struct(), 0, 1);
        queuedGrants = repmat(struct(), 0, 1);
        direction = upper(string(direction));
        if ~(isstruct(grants) && ~isempty(grants))
            return;
        end
        % Every grant in this path is executed with the scheduler_truth profile.
        % Consequently its DCI decode is intrinsic execution authority, not an
        % optional access-gating policy.  A disabled PDCCH must yield no qualified
        % scheduler_truth grant rather than a control-free data waveform.
        slotDLControlAllowed = logical(sixgr.util.structGet(state, "CurrentSlotDLAllowed", true)) && ...
            double(sixgr.util.structGet(state, "CurrentSlotDLNumSymbols", 0)) > 0;
        for gi = 1:numel(grants)
            grant = grants(gi);
            ueIdx = sixgr.truth.GrantPreparation.resolveGrantUEIndex(grant, state.MultiUser);
            if ~(isfinite(ueIdx) && ueIdx==fix(ueIdx) && ueIdx >= 1 && ueIdx <= numel(userCfg))
                error('sixgr:truth:InvalidPDCCHGrantUEIdentity', ...
                    'A scheduled DCI must bind to an existing UE; silently skipping the grant is forbidden.');
            end
            cfgU = userCfg{ueIdx};
            tempState = state;
            [cfgU, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfgU, tempState, ueIdx, direction); %#ok<ASGLU>
            slotIdx = double(sixgr.util.structGet(grant, "Slot", sixgr.util.structGet(state, "CurrentSlot", NaN)));
            frameIdx = double(sixgr.util.structGet(grant, "Frame", sixgr.util.structGet(state, "CurrentFrame", NaN)));
            controlSlotIdx = sixgr.truth.resolvePDCCHControlSlot(grant, ...
                sixgr.util.structGet(state, "CurrentSlot", NaN));
            grant.ControlSlot = controlSlotIdx;
            controlFrameIdx = double(state.CurrentFrame);
            validateattributes(controlFrameIdx,{'numeric'},{'scalar','real','finite','integer','positive'});
            declaredControlFrame = double(sixgr.util.structGet(grant,"ControlFrame",NaN));
            assert(isscalar(declaredControlFrame) && (isnan(declaredControlFrame) || ...
                declaredControlFrame==controlFrameIdx), ...
                'sixgr:truth:PDCCHControlFrameMismatch', ...
                'A current PDCCH must not retain a different control frame from the original HARQ attempt.');
            grant.ControlFrame = controlFrameIdx;
            rnti = double(grant.RNTI);
            assert(rnti==sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgU,ueIdx,direction), ...
                'sixgr:truth:PDCCHGrantRadioIdentityMismatch', ...
                'A scheduled control grant must use its installed received radio identity.');
            servingCell = double(sixgr.util.structGet(grant, "ServingCell", NaN));
            preTransmissionBlockReason="";
            if ~slotDLControlAllowed
                preTransmissionBlockReason="control_blocked_no_dl_control_symbols_in_tdd_slot";
            elseif isfield(grant,'PDCCHAdmissionSelected') && ~grant.PDCCHAdmissionSelected
                preTransmissionBlockReason="control_blocked_no_nonoverlapping_pdcch_candidate";
            end
            if strlength(preTransmissionBlockReason)>0
                [state, grant] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial( ...
                    state, grant, direction, preTransmissionBlockReason);
                state = sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
                    state, grant, direction, 'DCINotIssued', true);
                pdcchT = sixgr.truth.PDCCHControlRuntime.buildMissingPDCCHGrantBindingTrial(cfgU, NaN, ...
                    preTransmissionBlockReason);
                pdcchT = sixgr.truth.PDCCHControlRuntime.annotateCoupledControlTrial(pdcchT, controlSlotIdx, controlFrameIdx, ueIdx, rnti, direction, servingCell);
                [pdcchT, grant] = sixgr.truth.PDCCHControlRuntime.annotateGrant(pdcchT, grant, cfgU, direction);
                state.ControlTrials.PDCCH = sixgr.truth.PDCCHControlRuntime.appendCompatTable(state.ControlTrials.PDCCH, pdcchT);
                continue;
            end
            pdcchSNR_dB = sixgr.truth.resolveWaveformOperatingPointMetadata(cfgU, snr_dB);
            % An initialized attachment state is not a received DCI. Pre-attachment
            % may initialize access state, but never authorizes this DL/UL grant.
            % Reserve exact payload + DM-RS coordinates across both scheduling
            % passes. A search-space/CORESET ID or the scheduled data direction does
            % not create a separate physical resource pool.
            % Counter DAI is finalized after grant/control eligibility, never in a
            % tentative scheduler candidate or as a function of successful UE RX.
            [grant,candidateDAILedger]=sixgr.truth.prepareScheduledDLDAI( ...
                sixgr.util.structGet(state,'ScheduledDLDAILedger',struct()),cfgU,grant);
            grant=sixgr.truth.prepareScheduledULDAI(candidateDAILedger,cfgU,grant);
            cfgControl = sixgr.truth.PDCCHControlRuntime.resolvePDCCHTrialConfig(cfgU, pdcchSNR_dB, 1, 1, grant);
            [controlCarrier, ~] = sixgr.phy.grid.makeCarrier(cfgControl);
            [state.PDCCHResourceLedger, occupiedControlREs] = ...
                sixgr.truth.PDCCHSlotResourceLedger.lookup( ...
                sixgr.util.structGet(state, "PDCCHResourceLedger", struct()), ...
                controlSlotIdx, servingCell, controlCarrier);
            occupiedControlREs=unique([occupiedControlREs;sixgr.truth.commonPDCCHReservations( ...
                state,cfgControl,controlSlotIdx-1,servingCell,controlCarrier)],'rows');
            if isfield(grant,'PDCCHAdmissionSelected')
                assert(grant.PDCCHAdmissionSelected && grant.PDCCHAdmissionControlSlot==controlSlotIdx && ...
                    grant.PDCCHAdmissionCell==servingCell, ...
                    'sixgr:truth:PDCCHAdmissionContextMismatch','A planned candidate belongs to one cell/control occasion.');
                occupiedControlREs=unique([occupiedControlREs;grant.PDCCHAdmissionOtherReservations],'rows');
            end
            if isfield(state,'SharedWaveformStream')
                try
                    prepared=sixgr.link.prepareSharedPDCCHTransmission(cfgControl, ...
                        'Grant',grant,'RNTI',rnti,'DCIBits',grant.DCI.Bits, ...
                        'ReservedRECoordinates',occupiedControlREs);
                    if isfield(grant,'PDCCHAdmissionSelected')
                        assert(isequal(prepared.TxInfo.AllocatedRECoordinates,grant.PDCCHAdmissionCoordinates), ...
                            'sixgr:truth:PDCCHAdmissionExecutionMismatch', ...
                            'Actual PDCCH preparation must use its independently planned physical candidate.');
                    end
                catch ME
                    if ~strcmp(ME.identifier,'sixgr:phy:pdcch:NoFreeCandidate')
                        rethrow(ME);
                    end
                    if isfield(grant,'PDCCHAdmissionSelected')
                        error('sixgr:truth:PDCCHAdmissionExecutionMismatch', ...
                            'An admitted PDCCH lost its planned resources before transmission: %s',ME.message);
                    end
                    reason="control_blocked_no_nonoverlapping_pdcch_candidate";
                    [state,grant]=sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial( ...
                        state,grant,direction,reason);
                    state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
                        state,grant,direction,'DCINotIssued',true);
                    pdcchT=sixgr.truth.PDCCHControlRuntime.buildMissingPDCCHGrantBindingTrial(cfgU,NaN,reason);
                    pdcchT=sixgr.truth.PDCCHControlRuntime.annotateCoupledControlTrial(pdcchT,controlSlotIdx, ...
                        controlFrameIdx,ueIdx,rnti,direction,servingCell);
                    [pdcchT,grant]=sixgr.truth.PDCCHControlRuntime.annotateGrant( ...
                        pdcchT,grant,cfgU,direction);
                    state.ControlTrials.PDCCH=sixgr.truth.PDCCHControlRuntime.appendCompatTable( ...
                        state.ControlTrials.PDCCH,pdcchT);
                    logSink("INFO", ...
                        ["Blocked coupled %s grant before transmission: control_slot=%d " + ...
                         "ue=%d reason=%s occupied_control_res=%d."], ...
                        char(direction),round(controlSlotIdx),round(ueIdx), ...
                        char(reason),size(occupiedControlREs,1));
                    continue;
                end
                timing=sixgr.truth.CoupledTruthRuntime.receivedULTimingContextRuntime(state,ueIdx,servingCell);
                assert(isfield(timing,'DLReference'), ...
                    'sixgr:truth:ScheduledDCIReceivedClockRequired', ...
                    'Connected control reception requires the previously measured serving DL clock.');
                context=struct('Config',cfgU,'UserCfg',{userCfg},'Grant',grant, ...
                    'Direction',direction,'SNR',snr_dB,'Slot',controlSlotIdx, ...
                    'Frame',controlFrameIdx,'RNTI',rnti,'ServingCell',servingCell, ...
                    'Key',sixgr.truth.GrantPreparation.sharedGrantControlKey(grant,direction), ...
                    'ReceivedDLTimingReference',timing.DLReference);
                if direction=="UL" && sixgr.phy.frame.resolveDuplexMode(cfgU)=="TDD"
                    context.ScheduledULHARQConfig=cfgU;
                end
                state.SharedWaveformStream.queuePDCCH(ueIdx,prepared,context);
                state.ScheduledDLDAILedger=candidateDAILedger;
                state.PDCCHResourceLedger=sixgr.truth.PDCCHSlotResourceLedger.reserve( ...
                    state.PDCCHResourceLedger,controlSlotIdx,servingCell,controlCarrier,prepared.TxInfo.AllocatedRECoordinates);
                queuedGrants=sixgr.truth.PDCCHControlRuntime.appendCoupledPendingULGrants(queuedGrants,grant);
                continue;
            end
        end
        end

    end

    methods (Static, Hidden)
        function T = annotateCoupledControlTrial(T, slotIdx, frameIdx, ueIdx, rnti, direction, servingCell)
        if nargin < 7
            servingCell = NaN;
        end
        if ~istable(T)
            T = table();
            return;
        end
        n = height(T);
        if n < 1
            return;
        end
        if ismember("Frame", string(T.Properties.VariableNames))
            T.Frame(:) = double(frameIdx);
        else
            T.Frame = repmat(double(frameIdx), n, 1);
        end
        if ismember("Slot", string(T.Properties.VariableNames))
            T.Slot(:) = double(slotIdx);
        else
            T.Slot = repmat(double(slotIdx), n, 1);
        end
        if all(ismember(["SourceObservationSlot", "SourceObservationFrame"], string(T.Properties.VariableNames)))
            % Deferred RA completion is published now but still measures its
            % original Msg1 occasion. Do not move that measurement to the RRC slot.
            T.Frame = double(T.SourceObservationFrame);
            T.Slot = double(T.SourceObservationSlot);
        end
        % These values are execution context, not optional schema decoration. The
        % trial templates already contain NaN identity columns, so only filling
        % absent variables silently lost UE/cell binding in persisted control rows.
        T.UEIndex = repmat(double(ueIdx), n, 1);
        T.UEID = repmat(double(ueIdx), n, 1);
        T.RNTI = repmat(double(rnti), n, 1);
        T.Direction = repmat(string(direction), n, 1);
        if isfinite(double(servingCell))
            T.ServingCell = repmat(double(servingCell), n, 1);
            T.BaseStationID = repmat(double(servingCell), n, 1);
        end
        T.TrialDirection = repmat(string(direction), n, 1);
        T.LinkDirection = repmat(string(direction), n, 1);
        T.GrantDirection = repmat(string(direction), n, 1);
        end

        function Tout = appendCompatTable(Ta, Tb)
        if ~(istable(Ta) && ~isempty(Ta))
            if istable(Tb)
                Tout = Tb;
            else
                Tout = table();
            end
            return;
        end
        if ~(istable(Tb) && ~isempty(Tb))
            Tout = Ta;
            return;
        end
        vars = union(string(Ta.Properties.VariableNames), string(Tb.Properties.VariableNames), "stable");
        Ta = sixgr.truth.PDCCHControlRuntime.ensureTableVars(Ta, vars, Tb);
        Tb = sixgr.truth.PDCCHControlRuntime.ensureTableVars(Tb, vars, Ta);
        Tout = [Ta(:, cellstr(vars)); Tb(:, cellstr(vars))];
        end

        function pendingULGrants = appendCoupledPendingULGrants(pendingULGrants, grants)
        if ~(isstruct(grants) && ~isempty(grants))
            return;
        end
        if ~(isstruct(pendingULGrants) && ~isempty(pendingULGrants))
            pendingULGrants = grants;
            return;
        end
        [pendingULGrants, grants] = sixgr.truth.GrantPreparation.harmonizeStructArrays(pendingULGrants, grants);
        pendingULGrants = vertcat(pendingULGrants, grants);
        end

        function Tout = appendObservedREAllocation(Ta, Tb)
        % Append compatible evidence schemas, then remove exact producer replay.
        % Distinct overlapping allocations remain intact for collision validation.
        Tout = sixgr.truth.PDCCHControlRuntime.appendCompatTable(Ta, Tb);
        Tout = sixgr.truth.deduplicateObservedREAllocation(Tout);
        end

        function tf = bindingNumbersMatch(lhs, rhs)
        lhs = sixgr.truth.PDCCHControlRuntime.firstFinite(lhs, NaN);
        rhs = sixgr.truth.PDCCHControlRuntime.firstFinite(rhs, NaN);
        tf = isfinite(lhs) && isfinite(rhs) && abs(double(lhs) - double(rhs)) < 1e-9;
        end

        function tf = bindingTextsMatch(lhs, rhs)
        lhs = strtrim(string(lhs));
        rhs = strtrim(string(rhs));
        tf = strlength(lhs) > 0 && strlength(rhs) > 0 && lhs == rhs;
        end

        function [be, bt] = bitErrors(txBits, rxBits)
        txBits = int8(txBits(:));
        rxBits = int8(rxBits(:));
        L = min(numel(txBits), numel(rxBits));
        if L <= 0
            be = numel(txBits);
            bt = max(numel(txBits), 1);
            return;
        end
        be = sum(txBits(1:L) ~= rxBits(1:L));
        bt = max(numel(txBits), L);
        end

        function T = buildMissingPDCCHGrantBindingTrial(cfg, snr_dB, reason)
        r = sixgr.truth.makeLinkTrialRow(cfg, "DL", snr_dB, 1);
        r.Status = "NA";
        r.StrictOk = false;
        r.CRCApplicable = false;
        r.CRCPass = NaN;
        r.DecodeAttempted = false;
        r.DecodeUsable = false;
        r.DetectionAttempted = false;
        r.DetectionUsable = false;
        r.MeasurementAttempted = false;
        r.MeasurementUsable = false;
        r.ReceiverUsable = false;
        r.GrantValid = false;
        r.NegativeExpectedOk = false;
        r.DCICrcPass = false;
        r.PDCCHPayloadMatch = false;
        r.PDCCHCausalGrantDecodeOk = false;
        r.PDCCHMissedDetection = false;
        r.PDCCHFalseAlarm = false;
        r.NoiseVarStatus = "NOT_APPLICABLE";
        r.NoiseVarSource = "pdcch_decode_not_attempted";
        r.NoiseVarReason = string(reason);
        r.ReceiverHestSINRValueStatus = "not_applicable";
        r.ReceiverHestSINRNAReason = string(reason);
        r.MeasuredTrialSINRValueStatus = "not_applicable";
        r.MeasuredTrialSINRNAReason = string(reason);
        r.RuntimeMaterializationStatus = "active_integrated_grant_coupled_pdcch_binding_guard";
        r.FailureReason = string(reason);
        r.PDCCHReceiverTrialExecuted = false;
        r.PDCCHPreTransmissionFinalized = true;
        if string(reason) == "control_blocked_no_nonoverlapping_pdcch_candidate"
            r.ValueSource = "joint_pdcch_admission_runtime";
            r.ValueRole = "pretransmission_control_resource_decision";
            r.ValueStatus = "NOT_AVAILABLE";
            r.NAReason = string(reason);
            r.TruthStatus = "runtime_pretransmission_pdcch_admission_disposition";
            r.RuntimeMaterializationStatus = ...
                "active_integrated_pdcch_pretransmission_admission_disposition";
            r.Notes = "Joint PDCCH admission finalized this candidate before transmission; no waveform or receiver trial exists.";
        else
            r.ValueStatus = "decoded_dci_missing";
            r.TruthStatus = "runtime_pdcch_binding_missing";
            r.Notes = "Decoded PDCCH/DCI evidence was not available for this scheduled grant.";
        end
        T = struct2table(r, "AsArray", true);
        end

        function values = columnOrDefault(T, name, defaultValue)
        n = height(T);
        if ismember(name, string(T.Properties.VariableNames))
            values = T.(name);
            return;
        end
        if isstring(defaultValue) && numel(defaultValue) == n && ~isscalar(defaultValue)
            values = reshape(string(defaultValue), n, 1);
        elseif islogical(defaultValue) && numel(defaultValue) == n && ~isscalar(defaultValue)
            values = reshape(logical(defaultValue), n, 1);
        elseif isnumeric(defaultValue) && numel(defaultValue) == n && ~isscalar(defaultValue)
            values = reshape(double(defaultValue), n, 1);
        else
            values = repmat(defaultValue, n, 1);
        end
        end

        function hash = complexSHA256(value)
        hash = "";
        if isempty(value)
            return;
        end
        try
            data = single([real(value(:)).'; imag(value(:)).']);
            hash = string(sixgr.rrc.asn1.asn1SHA256Hex(typecast(data(:), "uint8")));
        catch
            hash = "";
        end
        end

        function decodedDci = decodeObservedPDCCHGrantDCI(rx, tx, dciFormat, grantContext, cfg)
        decodedDci = struct();
        if isfield(sixgr.util.structGet(cfg,'phy.pdcch.operatorControl',struct()),'connected_dci')
            if logical(sixgr.util.structGet(rx,'Ok',false))
                assert(string(rx.DCISelectionSource)=="receiver_installed_context_crc_and_semantic_parse" && ...
                    isstruct(rx.DecodedDCI) && ~isempty(fieldnames(rx.DecodedDCI)) && ...
                    isequal(int8(rx.DecodedDCI.Bits(:)),int8(rx.DCIBits(:))), ...
                    'sixgr:truth:MissingReceiverOwnedDCI','Connected control requires the actual receiver-parsed payload.');
                decodedDci=rx.DecodedDCI;
            end
            return;
        end
        bits = int8(sixgr.util.structGet(rx, "DCIBits", int8([])));
        if isempty(bits)
            return;
        end
        try
            contextData = sixgr.util.structGet(grantContext, "DCI.ContextData", struct());
            if isstruct(contextData) && isscalar(contextData) && isfield(contextData, "SpecRelease")
                dciContext = sixgr.phy.pdcch.DCIContext(contextData);
            elseif isstruct(grantContext) && ~isempty(fieldnames(grantContext))
                dciContext = sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant( ...
                    cfg, grantContext, dciFormat);
            else
                dciContext = sixgr.phy.pdcch.DCIContext.fromLegacy( ...
                    struct("NSizeGrid", double(tx.Carrier.NSizeGrid)), dciFormat);
            end
            decodedDci = sixgr.phy.pdcch.decodeDCIPayload(bits, dciFormat, dciContext);
        catch
            decodedDci = struct();
        end
        end

        function col = defaultColumnLike(refT, varName, nRows)
        if istable(refT) && ismember(varName, refT.Properties.VariableNames)
            refVal = refT.(varName);
            if isstring(refVal)
                col = strings(nRows, 1);
                return;
            end
            if islogical(refVal)
                col = false(nRows, 1);
                return;
            end
            if isnumeric(refVal)
                col = NaN(nRows, 1);
                return;
            end
        end
        col = strings(nRows, 1);
        end

        function T = ensureTableVars(T, vars, refT)
        for i = 1:numel(vars)
            v = char(vars(i));
            if ~ismember(v, T.Properties.VariableNames)
                T.(v) = sixgr.truth.PDCCHControlRuntime.defaultColumnLike(refT, v, height(T));
            end
        end
        end

        function value = firstFinite(vals, defaultValue)
        vals = double(vals(:));
        vals = vals(isfinite(vals));
        if isempty(vals)
            value = double(defaultValue);
        else
            value = double(vals(1));
        end
        end

        function token = formatNumericVector(values)
        token = sixgr.truth.formatNumericEvidenceVector(values);
        end

        function payload = grantBindingPayloadFromDecodedRow(row, direction)
        payload = struct( ...
            "Direction", char(upper(strtrim(string(direction)))), ...
            "DCIFormat", char(sixgr.truth.PDCCHControlRuntime.tableText(row, "DCIFormat", sixgr.truth.PDCCHControlRuntime.resolvePDCCHGrantDCIFormat(struct(), direction))), ...
            "RNTI", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "PDCCHDCICrcRNTI", NaN)), ...
            "HARQProcessId", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCIHARQProcessId", NaN)), ...
            "PRBStart", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCIPRBStart", NaN)), ...
            "AllocatedPRBCount", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCIAllocatedPRBCount", NaN)), ...
            "SymbolStart", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCISymbolStart", NaN)), ...
            "NumSymbols", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCINumSymbols", NaN)), ...
            "TimeDomainAssignmentIndex", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCITimeDomainAssignmentIndex", NaN)), ...
            "MCSIndex", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCIMCSIndex", NaN)), ...
            "RV", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCIRV", NaN)), ...
            "NDI", double(sixgr.truth.PDCCHControlRuntime.tableNumber(row, "DecodedDCINDI", NaN)));
        end

        function payload = grantBindingPayloadFromGrant(grant, direction)
        direction = upper(strtrim(string(direction)));
        prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
        prbSet = prbSet(isfinite(prbSet));
        prbStart = sixgr.truth.PDCCHControlRuntime.firstFinite(prbSet, double(sixgr.util.structGet(grant, "PRBStart", NaN)));
        if isempty(prbSet)
            prbCount = double(sixgr.util.structGet(grant, "AllocatedPRBCount", ...
                sixgr.util.structGet(grant, "PRBCount", NaN)));
        else
            prbCount = double(numel(prbSet));
        end
        symbolAllocation = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
        symbolAllocation = symbolAllocation(isfinite(symbolAllocation));
        if numel(symbolAllocation) >= 2
            symbolStart = double(symbolAllocation(1));
            numSymbols = double(symbolAllocation(2));
        else
            symbolStart = double(sixgr.util.structGet(grant, "SymbolStart", NaN));
            numSymbols = double(sixgr.util.structGet(grant, "NumSymbols", NaN));
        end
        payload = struct( ...
            "Direction", char(direction), ...
            "DCIFormat", char(sixgr.truth.PDCCHControlRuntime.resolvePDCCHGrantDCIFormat(grant, direction)), ...
            "RNTI", double(sixgr.util.structGet(grant, "RNTI", NaN)), ...
            "HARQProcessId", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "HARQ.HARQProcess", NaN)), ...
                double(sixgr.util.structGet(grant, "HARQ.HarqID", NaN)), ...
                double(sixgr.util.structGet(grant, "HARQProcessId", NaN))], NaN), ...
            "PRBStart", double(prbStart), ...
            "AllocatedPRBCount", double(prbCount), ...
            "SymbolStart", double(symbolStart), ...
            "NumSymbols", double(numSymbols), ...
            "TimeDomainAssignmentIndex", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "DCI.TimeDomainAssignmentIndex", NaN)), ...
                double(sixgr.util.structGet(grant, "TimeDomainResourceAssignmentIndex", NaN)), ...
                double(sixgr.util.structGet(grant, "TDRAIndex", NaN)), ...
                double(sixgr.util.structGet(grant, "TimeResourceAssignment", NaN))], NaN), ...
            "MCSIndex", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "MCSIndex", NaN)), ...
                double(sixgr.util.structGet(grant, "MCS", NaN))], NaN), ...
            "RV", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "HARQ.RV", NaN)), ...
                double(sixgr.util.structGet(grant, "RV", NaN))], NaN), ...
            "NDI", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "HARQ.NDI", NaN)), ...
                double(sixgr.util.structGet(grant, "NDI", NaN))], NaN));
        end

        function hash = grantBindingPayloadHash(payload)
        hash = "";
        if ~(isstruct(payload) && ~isempty(fieldnames(payload)))
            return;
        end
        try
            hash = char(sixgr.util.sha256Hex(uint8(unicode2native(char(jsonencode(orderfields(payload))), "UTF-8"))));
        catch
            hash = "";
        end
        end

        function tf = hasFiniteNumericEvidence(value)
        tf = false;
        if isempty(value)
            return;
        end
        try
            vals = abs(double(value(:)));
            tf = any(isfinite(vals));
        catch ME
            if prachRequired
                rethrow(ME);
            end
            tf = false;
        end
        end

        function hash = hashDecodedPDCCHGrantFields(decodedDci, rnti)
        hash = "";
        if ~(isstruct(decodedDci) && ~isempty(fieldnames(decodedDci)))
            return;
        end
        payload = struct( ...
            "Direction", char(string(sixgr.util.structGet(decodedDci, "Direction", ""))), ...
            "DCIFormat", char(string(sixgr.util.structGet(decodedDci, "Format", ""))), ...
            "RNTI", double(rnti), ...
            "HARQProcessId", double(sixgr.util.structGet(decodedDci, "Fields.harq_process", NaN)), ...
            "PRBStart", double(sixgr.util.structGet(decodedDci, "Fields.prb_start", NaN)), ...
            "AllocatedPRBCount", double(sixgr.util.structGet(decodedDci, "Fields.num_prb", NaN)), ...
            "SymbolStart", double(sixgr.util.structGet(decodedDci, "Fields.symbol_start", NaN)), ...
            "NumSymbols", double(sixgr.util.structGet(decodedDci, "Fields.num_symbols", NaN)), ...
            "TimeDomainAssignmentIndex", double(sixgr.util.structGet(decodedDci, ...
                "Fields.time_domain_assignment_index",sixgr.util.structGet(decodedDci,"Fields.time_resource_assignment",NaN))), ...
            "MCSIndex", double(sixgr.util.structGet(decodedDci, "Fields.mcs", NaN)), ...
            "RV", double(sixgr.util.structGet(decodedDci, "Fields.rv", NaN)), ...
            "NDI", double(sixgr.util.structGet(decodedDci, "Fields.ndi", NaN)));
        hash = sixgr.truth.PDCCHControlRuntime.grantBindingPayloadHash(payload);
        end

        function r = markControlSINRUnavailable(r, reason)
        reason = string(reason);
        r.ReceiverHestSINR_dB = NaN;
        r.ReceiverHestSINRSource = "";
        r.ReceiverHestSINRValueRole = "unavailable";
        r.ReceiverHestSINRValueStatus = "unavailable";
        r.ReceiverHestSINRNAReason = reason;
        r.MeasuredTrialSINR_dB = NaN;
        r.MeasuredTrialSINRSource = "";
        r.MeasuredTrialSINRValueRole = "unavailable";
        r.MeasuredTrialSINRValueStatus = "unavailable";
        r.MeasuredTrialSINRNAReason = reason;
        r.MeasuredSINR_dB = NaN;
        r.SINRValueRole = "unavailable";
        r.SINRSource = "";
        r.SINRValueStatus = "unavailable";
        r.SINRValueDefinition = "no_control_sinr_observation_available_without_runtime_noise_power_anchor";
        end

        function availCCEs = pdcchAvailableCCEs(pdcch)
        availCCEs = NaN;
        if isempty(pdcch)
            return;
        end
        core = [];
        try
            core = pdcch.CORESET;
        catch
        end
        if isempty(core)
            return;
        end
        freqResources = sixgr.truth.PDCCHControlRuntime.pdcchScalar(core, "FrequencyResources", []);
        duration = sixgr.truth.PDCCHControlRuntime.pdcchScalar(core, "Duration", NaN);
        if isempty(freqResources) || ~isfinite(duration) || duration <= 0
            return;
        end
        numREG = 6 * sum(freqResources ~= 0) * duration;
        availCCEs = floor(numREG / 6);
        end

        function reason = pdcchDecodeFailureReason(rx, bitErrors, bitsCompared)
        if ~logical(sixgr.util.structGet(rx, "Ok", false))
            errFlag = double(sixgr.util.structGet(rx, "ErrFlag", NaN));
            if isfinite(errFlag) && errFlag ~= 0
                reason = "pdcch_dci_crc_failed";
            else
                reason = "pdcch_decode_not_ok";
            end
        else
            reason = "pdcch_dci_bit_mismatch_after_crc";
        end
        bitErrors = double(bitErrors);
        bitsCompared = double(bitsCompared);
        if isfinite(bitErrors) && bitErrors > 0 && isfinite(bitsCompared) && bitsCompared > 0
            reason = reason + "_bit_errors_" + string(round(bitErrors)) + "_of_" + string(round(bitsCompared));
        end
        noiseStatus = string(sixgr.util.structGet(rx, "NoiseVarStatus", ""));
        if strlength(strtrim(noiseStatus)) > 0 && noiseStatus ~= "OK"
            reason = reason + "_noisevar_" + noiseStatus;
        end
        end

        function hash = pdcchResourceHash(pdcchInd, dmrsInd)
        hash = "";
        try
            payload = struct("PDCCHInd", double(pdcchInd(:).'), "DMRSInd", double(dmrsInd(:).'));
            hash = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(payload), "UTF-8"))));
        catch
            hash = "";
        end
        end

        function value = pdcchScalar(obj, propName, defaultValue)
        value = defaultValue;
        if isempty(obj)
            return;
        end
        try
            value = obj.(propName);
        catch
            return;
        end
        if isnumeric(value)
            value = double(value);
        elseif islogical(value)
            value = double(value);
        end
        end

        function value = pdcchScalarVector(obj, propName)
        value = [];
        if isempty(obj)
            return;
        end
        try
            value = obj.(propName);
        catch
            value = [];
            return;
        end
        if isnumeric(value) || islogical(value)
            value = double(value(:).');
        else
            value = [];
        end
        end

        function reason = pdcchStrictFailureReason(r, rx, bitErrors, bitsCompared, payloadMatch, dciCrcPass, noiseOk)
        parts = strings(0, 1);
        if ~logical(dciCrcPass)
            if isnan(r.CRCPass)
                parts(end+1, 1) = "pdcch_crc_evidence_unavailable"; %#ok<AGROW>
            else
                parts(end+1, 1) = "pdcch_dci_crc_failed"; %#ok<AGROW>
            end
        end
        if ~logical(rx.Ok)
            parts(end+1, 1) = "pdcch_receiver_context_or_hypothesis_rejected"; %#ok<AGROW>
        end
        if ~logical(payloadMatch)
            parts(end+1, 1) = sixgr.truth.PDCCHControlRuntime.pdcchDecodeFailureReason(rx, bitErrors, bitsCompared); %#ok<AGROW>
        end
        if ~logical(r.DetectionUsable)
            parts(end+1, 1) = "pdcch_blind_candidate_detection_evidence_missing"; %#ok<AGROW>
        end
        if ~logical(r.MeasurementUsable)
            parts(end+1, 1) = "pdcch_receiver_hest_sinr_missing_or_not_ok"; %#ok<AGROW>
        end
        if ~logical(r.ChannelEstimateAvailable)
            parts(end+1, 1) = "pdcch_dmrs_channel_estimate_missing"; %#ok<AGROW>
        end
        if ~logical(r.ResourceExtractionAvailable)
            parts(end+1, 1) = "pdcch_resource_extraction_missing"; %#ok<AGROW>
        end
        if ~logical(r.EqualizationAvailable)
            parts(end+1, 1) = "pdcch_equalized_symbol_evidence_missing"; %#ok<AGROW>
        end
        if ~logical(noiseOk)
            parts(end+1, 1) = "pdcch_noise_variance_missing_or_not_ok"; %#ok<AGROW>
        end
        if logical(r.FalseAlarmFlag)
            parts(end+1, 1) = "pdcch_actual_received_false_grant_decode"; %#ok<AGROW>
        end
        if isempty(parts)
            parts(end+1, 1) = "pdcch_strict_receiver_evidence_incomplete"; %#ok<AGROW>
        end
        reason = strjoin(parts, ";");
        end

        function binding = resolvePDCCHGrantBinding(cfg, grant, direction, T)
        direction = upper(strtrim(string(direction)));
        grantPayload = sixgr.truth.PDCCHControlRuntime.grantBindingPayloadFromGrant(grant, direction);
        binding = struct( ...
            "Required", true, ...
            "Ok", false, ...
            "Status", "not_required", ...
            "FailureCode", "", ...
            "DCIId", "", ...
            "DCIFieldsHash", "", ...
            "GrantFieldsHash", sixgr.truth.PDCCHControlRuntime.grantBindingPayloadHash(grantPayload), ...
            "SearchSpaceId", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "SearchSpaceID", NaN)), ...
                double(sixgr.util.structGet(grant, "SearchSpaceId", NaN)), ...
                double(sixgr.util.structGet(grant, "PDCCHGrantSearchSpaceId", NaN))], NaN), ...
            "CORESETId", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "CORESETID", NaN)), ...
                double(sixgr.util.structGet(grant, "CORESETId", NaN)), ...
                double(sixgr.util.structGet(grant, "PDCCHGrantCORESETId", NaN))], NaN), ...
            "AggregationLevel", sixgr.truth.PDCCHControlRuntime.firstFinite([ ...
                double(sixgr.util.structGet(grant, "PDCCHAggregationLevel", NaN)), ...
                double(sixgr.util.structGet(grant, "PDCCHGrantAggregationLevel", NaN))], NaN), ...
            "CandidateIndex", double(sixgr.util.structGet(grant, "PDCCHGrantCandidateIndex", NaN)), ...
            "DCIFormat", char(string(grantPayload.DCIFormat)));
        if ~binding.Required && ~(istable(T) && ~isempty(T))
            binding.Ok = true;
            return;
        end

        if ~(istable(T) && ~isempty(T))
            binding.Status = "missing_decoded_dci";
            binding.FailureCode = "decoded_dci_missing";
            return;
        end

        row = T(end, :);
        execution = sixgr.link.pdcchTrialExecutionState(row);
        if ~execution.BindingEligible
            binding.Status = "missing_decoded_dci";
            if sixgr.truth.PDCCHControlRuntime.tableLogical(row,"PDCCHPreTransmissionFinalized",false)
                binding.Status = "blocked_before_transmission";
            end
            binding.FailureCode = char(execution.BindingFailureCode);
            return;
        end
        decodedPayload = sixgr.truth.PDCCHControlRuntime.grantBindingPayloadFromDecodedRow(row, direction);
        binding.DCIId = char(sixgr.truth.PDCCHControlRuntime.tableText(row, ["DCIId","PayloadHash"], ""));
        binding.DCIFieldsHash = char(sixgr.truth.PDCCHControlRuntime.tableText(row, "DCIFieldsHash", ""));
        binding.SearchSpaceId = sixgr.truth.PDCCHControlRuntime.firstFinite([binding.SearchSpaceId, sixgr.truth.PDCCHControlRuntime.tableNumber(row, "SearchSpaceId", NaN)], NaN);
        binding.CORESETId = sixgr.truth.PDCCHControlRuntime.firstFinite([binding.CORESETId, sixgr.truth.PDCCHControlRuntime.tableNumber(row, "CORESETId", NaN)], NaN);
        binding.AggregationLevel = sixgr.truth.PDCCHControlRuntime.firstFinite([binding.AggregationLevel, sixgr.truth.PDCCHControlRuntime.tableNumber(row, "AggregationLevel", NaN)], NaN);
        binding.CandidateIndex = sixgr.truth.PDCCHControlRuntime.firstFinite([binding.CandidateIndex, ...
            sixgr.truth.PDCCHControlRuntime.tableNumber(row, ["CandidateIndex","PDCCHCandidateIndex"], NaN)], NaN);
        binding.DCIFormat = char(sixgr.truth.PDCCHControlRuntime.tableText(row, "DCIFormat", binding.DCIFormat));

        failures = strings(0, 1);
        if ~sixgr.truth.PDCCHControlRuntime.tableLogical(row, "DCICrcPass", false)
            failures(end+1, 1) = "decoded_dci_crc_failed"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.tableLogical(row, "PDCCHPayloadMatch", false)
            failures(end+1, 1) = "decoded_dci_payload_mismatch"; %#ok<AGROW>
        end
        if strlength(strtrim(string(binding.DCIFieldsHash))) == 0
            failures(end+1, 1) = "decoded_dci_fields_hash_missing"; %#ok<AGROW>
        end
        if strlength(strtrim(string(binding.GrantFieldsHash))) == 0
            failures(end+1, 1) = "grant_fields_hash_missing"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.RNTI, grantPayload.RNTI)
            failures(end+1, 1) = "rnti_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.HARQProcessId, grantPayload.HARQProcessId)
            failures(end+1, 1) = "harq_process_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.PRBStart, grantPayload.PRBStart) || ...
                ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.AllocatedPRBCount, grantPayload.AllocatedPRBCount)
            failures(end+1, 1) = "prb_allocation_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.SymbolStart, grantPayload.SymbolStart) || ...
                ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.NumSymbols, grantPayload.NumSymbols)
            failures(end+1, 1) = "symbol_allocation_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.MCSIndex, grantPayload.MCSIndex)
            failures(end+1, 1) = "mcs_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.RV, grantPayload.RV)
            failures(end+1, 1) = "rv_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.NDI, grantPayload.NDI)
            failures(end+1, 1) = "ndi_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingNumbersMatch(decodedPayload.TimeDomainAssignmentIndex, grantPayload.TimeDomainAssignmentIndex)
            failures(end+1, 1) = "time_domain_assignment_mismatch"; %#ok<AGROW>
        end
        if ~sixgr.truth.PDCCHControlRuntime.bindingTextsMatch(binding.DCIFormat, grantPayload.DCIFormat)
            failures(end+1, 1) = "dci_format_mismatch"; %#ok<AGROW>
        end
        observedSearchSpaceId = sixgr.truth.PDCCHControlRuntime.tableNumber(row, "SearchSpaceId", NaN);
        if ~(isfinite(observedSearchSpaceId) && isfinite(binding.SearchSpaceId) && ...
                double(observedSearchSpaceId) == double(binding.SearchSpaceId))
            failures(end+1, 1) = "search_space_mismatch"; %#ok<AGROW>
        end
        observedCORESETId = sixgr.truth.PDCCHControlRuntime.tableNumber(row, "CORESETId", NaN);
        if ~(isfinite(observedCORESETId) && isfinite(binding.CORESETId) && ...
                double(observedCORESETId) == double(binding.CORESETId))
            failures(end+1, 1) = "coreset_mismatch"; %#ok<AGROW>
        end
        if strlength(strtrim(string(binding.DCIFieldsHash))) > 0 && strlength(strtrim(string(binding.GrantFieldsHash))) > 0 && ...
                string(binding.DCIFieldsHash) ~= string(binding.GrantFieldsHash)
            failures(end+1, 1) = "dci_grant_fields_hash_mismatch"; %#ok<AGROW>
        end

        failures = unique(failures(strlength(strtrim(failures)) > 0), "stable");
        binding.Ok = isempty(failures);
        binding.Status = sixgr.truth.PDCCHControlRuntime.ternaryBinding(binding.Ok, "bound", "failed");
        binding.FailureCode = char(strjoin(failures, "|"));
        end

        function dciFormat = resolvePDCCHGrantDCIFormat(source, direction)
        dciFormat = string(sixgr.util.structGet(source, "DCI.Format", ...
            sixgr.util.structGet(source, "DCIFormat", "")));
        dciFormat = strtrim(dciFormat);
        if strlength(dciFormat) == 0
            direction = upper(strtrim(string(direction)));
            if direction == "UL"
                dciFormat = "0_0";
            else
                dciFormat = "1_0";
            end
        end
        try
            dciFormat = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
        catch
            % The contextual DCI decoder will fail closed for an unsupported token.
        end
        end

        function cfgTrial = resolvePDCCHTrialConfig(cfg, snr_dB, trialIdx, nTrials, grantContext)
        cfgTrial = cfg;
        levels = double(sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevels", ...
            sixgr.util.structGet(cfg, "control.aggregation_levels", ...
            sixgr.util.structGet(cfg, "ctrl6gr.StudyAggregationLevels", ...
            sixgr.util.structGet(cfg, "phy.pdcch.aggregationLevel", 4)))));
        levels = unique(levels(ismember(levels, [1 2 4 8 16])), "stable");
        if isempty(levels)
            levels = 4;
        end
        levels = sixgr.phy.pdcch.resolveExecutableAggregationLevels(cfg, levels);
        if nargin >= 5 && isstruct(grantContext) && ~isempty(fieldnames(grantContext))
            aggLevel = sixgr.phy.pdcch.resolveScheduledAggregationLevel(cfg,grantContext);
        else
            nTrials = max(1, round(double(nTrials)));
            idx = mod(max(1, round(double(trialIdx))) - 1, numel(levels)) + 1;
            if nTrials == 1
                aggLevel = sixgr.truth.PDCCHControlRuntime.selectPDCCHAggregationLevel(levels, snr_dB);
            else
                aggLevel = levels(idx);
            end
        end
        cfgTrial = sixgr.util.structSet(cfgTrial, "phy.pdcch.aggregationLevel", double(aggLevel));
        cfgTrial = sixgr.util.structSet(cfgTrial, "phy.pdcch.blindSearch", ...
            logical(sixgr.util.structGet(cfg, "phy.pdcch.blindSearch", false)));
        cfgTrial = sixgr.util.structSet(cfgTrial, "lls6g.userContext.RuntimeSignalFamily", "PDCCH");
        cfgTrial = sixgr.util.structSet(cfgTrial, "phy.runtimeSignalFamily", "PDCCH");
        % PDCCH is always transmitted by the gNB and received by the UE, including
        % when its DCI schedules a future UL grant.  The scheduled data direction
        % must not leak into RF gains, noise figure or runtime-channel identity.
        cfgTrial = sixgr.util.structSet(cfgTrial, ...
            "lls6g.userContext.RuntimeCurrentDirection","DL");
        cfgTrial = sixgr.util.structSet(cfgTrial, ...
            "lls6g.userContext.Direction","DL");
        if nargin >= 5 && isstruct(grantContext) && ~isempty(fieldnames(grantContext))
            % An UL DCI is carried in its DL control slot, not the future PUSCH
            % data slot. Bind waveform construction, channel time and RE evidence
            % to that same absolute control occasion, including frame wrap.
            controlSlot = sixgr.truth.resolvePDCCHControlSlot(grantContext, ...
                sixgr.util.structGet(cfg, "lls6g.runtime.AbsoluteSlotIndexOneBased", NaN));
            cfgTrial = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfgTrial, controlSlot);
            timingSpec=sixgr.phy.frame.NumerologyCatalog.resolve( ...
                double(cfgTrial.phy.carrier.SubcarrierSpacing),string(cfgTrial.phy.carrier.CyclicPrefix), ...
                'generic_waveform_test','');
            controlTime=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(double(controlSlot)-1,0,timingSpec);
            cfgTrial = sixgr.util.structSet(cfgTrial, "lls6g.userContext.RuntimeSlotStartTime_s", ...
                controlTime.seconds());
        end
        end

        function aggLevel = selectPDCCHAggregationLevel(levels, snr_dB)
        snr_dB = double(snr_dB);
        if ~isfinite(snr_dB)
            target = 4;
        elseif snr_dB < 0
            target = 16;
        elseif snr_dB < 5
            target = 8;
        elseif snr_dB < 10
            target = 4;
        elseif snr_dB < 15
            target = 2;
        else
            target = 1;
        end
        [~, idx] = min(abs(double(levels(:)) - double(target)));
        aggLevel = double(levels(idx));
        end

        function slotDur_s = slotDuration(cfg)
        slotDur_s = sixgr.time.slotDurationSec(cfg);
        end

        function tf = tableLogical(row, name, defaultValue)
        tf = logical(defaultValue);
        if ~(istable(row) && height(row) >= 1)
            return;
        end
        vars = string(row.Properties.VariableNames);
        if any(vars == string(name))
            raw = row.(string(name))(1);
            if islogical(raw)
                tf = logical(raw);
            elseif isnumeric(raw)
                tf = logical(raw ~= 0);
            end
        end
        end

        function value = tableNumber(row, names, defaultValue)
        value = double(defaultValue);
        if ~(istable(row) && height(row) >= 1)
            return;
        end
        names = string(names);
        vars = string(row.Properties.VariableNames);
        for ii = 1:numel(names)
            if any(vars == names(ii))
                raw = double(row.(names(ii))(1));
                if isfinite(raw)
                    value = raw;
                    return;
                end
            end
        end
        end

        function value = tableText(row, names, defaultValue)
        value = string(defaultValue);
        if ~(istable(row) && height(row) >= 1)
            return;
        end
        names = string(names);
        vars = string(row.Properties.VariableNames);
        for ii = 1:numel(names)
            if any(vars == names(ii))
                token = string(row.(names(ii))(1));
                if strlength(strtrim(token)) > 0
                    value = token;
                    return;
                end
            end
        end
        end

        function tf = thermalNoiseSINRUnavailable(replay)
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

        function value = ternaryBinding(cond, ifTrue, ifFalse)
        if cond
            value = string(ifTrue);
        else
            value = string(ifFalse);
        end
        end

    end
end
