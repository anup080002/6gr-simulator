function metrics = measureULLinkState(Hest, nVar, cfg, varargin)
%MEASUREULLINKSTATE Derive UL link-state measurements from actual UL RX evidence.
%
% This helper intentionally does not reuse DL CSI feedback semantics for UL.
% It reports only measurements that can be supported by the active UL
% receive chain:
%   - DMRS-reference Hest/noise-variance SINR estimate
%   - received reference-signal power
%   - CQI derived only from a data-channel scheduling SINR estimate
%   - rank estimate from the wideband channel estimate
%   - TPMI/beam metadata only when the active UL path is codebook-based

ip = inputParser;
ip.addParameter("ReceivedGrid", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReferenceIndices", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("ReferenceSymbols", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("PrecoderInfo", struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter("ChannelEstimateDomain", "", @(x) ischar(x) || isstring(x));
ip.parse(varargin{:});
opt = ip.Results;
channelEstimateDomain = lower(strtrim(string(opt.ChannelEstimateDomain)));
validEstimateDomains = ["srs_port_domain", "pusch_dmrs_effective_layer_domain"];
if strlength(channelEstimateDomain) == 0
    error("sixgr:phy:ul:MissingChannelEstimateDomain", ...
        "UL link-state measurement requires an explicit channel-estimate domain. " + ...
        "Use 'srs_port_domain' for unprecoded SRS port observations or " + ...
        "'pusch_dmrs_effective_layer_domain' for the already-precoded PUSCH receiver estimate.");
end
if ~any(channelEstimateDomain == validEstimateDomains)
    error("sixgr:phy:ul:InvalidChannelEstimateDomain", ...
        "Unsupported UL channel-estimate domain '%s'.", char(channelEstimateDomain));
end
reportCQI = logical(sixgr.util.structGet(cfg, "phy.csi.reportCQI", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "cqi_reporting", reportCQI, ...
    "measureULLinkState.CQI");

metrics = struct( ...
    "NMSE_dB", NaN, ...
    "DetectionMetric", NaN, ...
    "SINR_dB", NaN, ...
    "SINRSource", "", ...
    "SINRValueRole", "", ...
    "SINRValueStatus", "", ...
    "SINRNAReason", "", ...
    "SINRMeasurementDomain", "", ...
    "PowerReferencePlane", "", ...
    "PilotSINR_dB", NaN, ...
    "PilotSINRSource", "", ...
    "PilotSINRValueRole", "diagnostic_reference_signal_quality_not_for_scheduling", ...
    "PilotSINRValueStatus", "", ...
    "PilotSINRNAReason", "", ...
    "CQI", NaN, ...
    "CQISource", "", ...
    "CQIValueStatus", "", ...
    "RI", NaN, ...
    "PMI", NaN, ...
    "CRI", NaN, ...
    "PMIType", "", ...
    "PMICodebookMode", "", ...
    "CSIReportMode", "", ...
    "CSIPayloadBitLength", NaN, ...
    "CSIPayloadHex", "", ...
    "ChannelGain_dB", NaN, ...
    "RankEstimate", NaN, ...
    "ConditionNumber_dB", NaN, ...
    "NumRxAnt", NaN, ...
    "NumTxPorts", NaN, ...
    "SelectedBeamIndices", [], ...
    "SelectedBeamIndex", NaN, ...
    "BestBeamIndex", NaN, ...
    "BeamHit", NaN, ...
    "TopKBeamHit", NaN, ...
    "BeamCandidateCount", NaN, ...
    "SelectedBeamGain_dB", NaN, ...
    "BestBeamGain_dB", NaN, ...
    "BeamGainGap_dB", NaN, ...
    "BeamScoreVector_dB", "", ...
    "TopBeamIndexSet", "", ...
    "TopBeamGainSet_dB", "", ...
    "BeamScoreSource", "", ...
    "ConfiguredPMI", NaN, ...
    "ConfiguredCRI", NaN, ...
    "ULNormalizedReferencePower_dB", NaN, ...
    "ULNormalizedReferencePowerSource", "measurement_unavailable", ...
    "ULNormalizedWindowRSSI_dB", NaN, ...
    "ULNormalizedWindowRSSISource", "measurement_unavailable", ...
    "ULNormalizedWindowPowerRatio_dB", NaN, ...
    "ULNormalizedWindowPowerRatioSource", "measurement_unavailable", ...
    "ULNormalizedPowerEvidenceJSON", "", ...
    "RISource", "", ...
    "PMISource", "", ...
    "RuntimeAppliedPMI", NaN, ...
    "SelectedCodebookPortIndices1Based", [], ...
    "TPMICandidateCount", NaN, ...
    "TPMIMutualInformation", NaN, ...
    "SRSConditionNumber_dB", NaN, ...
    "SRSRITPMIValid", false, ...
    "SRSRITPMIStatus", "", ...
    "ChannelEstimateDomain", char(channelEstimateDomain));

if isempty(Hest)
    metrics.SINRSource = "ul_receiver_hest_missing";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "ul_channel_estimate_empty";
    return;
end

Hwb = localWidebandChannelMatrix(Hest, cfg);
if isempty(Hwb)
    metrics.SINRSource = "ul_receiver_hest_wideband_matrix_unavailable";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "ul_wideband_channel_matrix_unavailable";
    return;
end

[metrics.NumRxAnt, metrics.NumTxPorts] = size(Hwb);
[metrics.ChannelGain_dB, metrics.RankEstimate, metrics.ConditionNumber_dB] = localWidebandChannelDescriptors(Hwb);
metrics.RI = localResolveULRankIndicator(metrics.RankEstimate);
if channelEstimateDomain == "srs_port_domain"
    metrics.RISource = "ul_srs_port_domain_wideband_rank_descriptor";
    srsEstimate = sixgr.phy.ul.estimateSRSRITPMI(Hest, nVar, cfg);
    metrics.SRSRITPMIValid = logical(sixgr.util.structGet(srsEstimate, "Valid", false));
    metrics.SRSRITPMIStatus = localSRSRITPMIStatus(srsEstimate);
    metrics.SRSConditionNumber_dB = double(sixgr.util.structGet(srsEstimate, "ConditionNumber_dB", NaN));
    metrics.TPMICandidateCount = double(sixgr.util.structGet(srsEstimate, "TPMICandidateCount", NaN));
    metrics.TPMIMutualInformation = double(sixgr.util.structGet(srsEstimate, "TPMIMutualInformation", NaN));
    if isfinite(double(sixgr.util.structGet(srsEstimate, "RI", NaN)))
        metrics.RI = double(sixgr.util.structGet(srsEstimate, "RI", metrics.RI));
        metrics.RISource = char(string(sixgr.util.structGet(srsEstimate, "RISource", "ul_srs_covariance_rank_estimator_lab_default")));
    end
else
    % PUSCH DM-RS estimates observe the effective channel after the active
    % codebook/hybrid precoder. Their final dimension is a layer dimension,
    % not an antenna-port dimension. Running the SRS RI/TPMI search here can
    % either invent missing ports or reject a valid rank-L waveform. Keep
    % the effective-channel descriptor and the actually applied TPMI, while
    % leaving SRS recommendation fields explicitly not applicable.
    metrics.RISource = "ul_pusch_dmrs_effective_layer_rank_descriptor_not_srs_ri";
    metrics.SRSRITPMIStatus = "not_applicable_pusch_dmrs_effective_layer_domain";
    srsEstimate = struct("Valid", false, "RI", NaN, "TPMI", NaN, ...
        "SelectedBeamIndices", [], "TPMISource", ...
        "not_applicable_pusch_dmrs_effective_layer_domain");
end

[sinr_dB, sinrSource, sinrStatus, pilotNMSE_dB, perRBSINR_dB] = localMeasureReferenceSINR(Hest, nVar, ...
    opt.ReceivedGrid, opt.ReferenceIndices, opt.ReferenceSymbols, cfg);
measuredSINRAvailable = isfinite(sinr_dB);
metrics.PilotSINR_dB = double(sinr_dB);
metrics.PilotSINRSource = char(string(sinrSource));
metrics.PilotSINRValueRole = "diagnostic_reference_signal_quality_not_for_scheduling";
metrics.PilotSINRValueStatus = char(string(sinrStatus));
if isfinite(sinr_dB)
    metrics.SINR_dB = double(sinr_dB);
    metrics.SINRValueStatus = char(string(sinrStatus));
    metrics.SINRNAReason = "";
    if channelEstimateDomain == "srs_port_domain"
        metrics.SINRSource = "measured_ul_srs_pilot_reconstruction_sinr";
        metrics.SINRValueRole = ...
            "diagnostic_reference_signal_quality_not_for_scheduling";
        metrics.SINRMeasurementDomain = "srs_pilot_resource_elements_channel_reconstruction_residual";
        metrics.PowerReferencePlane = "receiver_srs_resource_elements_after_ofdm_demodulation";
    else
        metrics.SINRSource = "measured_ul_pusch_dmrs_reconstruction_sinr";
        metrics.SINRValueRole = "measured_ul_data_channel_cqi_input";
        metrics.SINRMeasurementDomain = "pusch_dmrs_resource_elements_effective_layer_channel_reconstruction_residual";
        metrics.PowerReferencePlane = "receiver_pusch_dmrs_resource_elements_after_ofdm_demodulation";
    end
else
    metrics.SINRSource = char(string(sinrSource));
    if strlength(strtrim(string(metrics.SINRSource))) == 0
        metrics.SINRSource = "ul_reference_signal_sinr_unavailable";
    end
    metrics.SINRValueRole = "unavailable";
    metrics.SINRValueStatus = "unavailable";
    metrics.SINRNAReason = "ul_reference_signal_sinr_not_available_from_receiver_evidence";
    metrics.PilotSINRNAReason = metrics.SINRNAReason;
end

if isfinite(pilotNMSE_dB)
    metrics.NMSE_dB = double(pilotNMSE_dB);
    metrics.DetectionMetric = 1 / (1 + 10.^(pilotNMSE_dB / 10));
end

if ~isempty(opt.ReceivedGrid) && ~isempty(opt.ReferenceIndices) && ~isempty(opt.ReferenceSymbols)
    power=sixgr.phy.ul.measureNormalizedReferencePower( ...
        opt.ReceivedGrid,opt.ReferenceIndices,opt.ReferenceSymbols);
    metrics.ULNormalizedReferencePower_dB=power.ReferencePower_dB;
    metrics.ULNormalizedWindowRSSI_dB=power.WindowRSSI_dB;
    metrics.ULNormalizedWindowPowerRatio_dB=power.WindowPowerRatio_dB;
    metrics.ULNormalizedReferencePowerSource="normalized_UL_reference_RE_energy_linear_branch_mean";
    metrics.ULNormalizedWindowRSSISource="normalized_UL_reference_PRBs_and_symbols_linear_branch_mean";
    metrics.ULNormalizedWindowPowerRatioSource="diagnostic_N_times_reference_over_window_power_not_NR_RSRQ";
    metrics.ULNormalizedPowerEvidenceJSON=string(jsonencode(power));
end

if measuredSINRAvailable && reportCQI && ...
        channelEstimateDomain == "pusch_dmrs_effective_layer_domain"
    feedback = sixgr.link.resolveWidebandCQI(struct( ...
        "WidebandSINR_dB", metrics.SINR_dB, ...
        "PerRBSINR_dB", double(perRBSINR_dB), ...
        "SINRSource", metrics.SINRSource, ...
        "SINRValueRole", metrics.SINRValueRole, ...
        "SINRValueStatus", metrics.SINRValueStatus), cfg, "UL");
    rawCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
    if isfinite(rawCQI)
        metrics.CQI = double(max(0, min(15, round(rawCQI))));
        metrics.CQISource = "ul_measured_rs_sinr_to_cqi:" + string(sixgr.util.structGet(feedback, "Mode", "sinr_threshold_table"));
        if metrics.CQI == 0
            metrics.CQIValueStatus = "out_of_range_cqi0_from_measured_ul_sinr";
        else
            metrics.CQIValueStatus = "OK";
        end
    else
        metrics.CQI = NaN;
        metrics.CQISource = "ul_measured_rs_sinr_rejected_for_cqi:" + string(sixgr.util.structGet(feedback, "SINRInputRejectionReason", ""));
        metrics.CQIValueStatus = "unavailable_non_scheduling_sinr_input";
    end
end
if reportCQI && channelEstimateDomain == "srs_port_domain"
    metrics.CQI = NaN;
    metrics.CQISource = ...
        "not_derived_from_srs_pilot_reconstruction_residual";
    metrics.CQIValueStatus = ...
        "unavailable_until_power_plane_calibrated_pusch_prediction";
end

metrics = localResolveULPrecoderMeasurementFields(metrics, cfg, opt.PrecoderInfo, srsEstimate);
end

function status = localSRSRITPMIStatus(srsEstimate)
if logical(sixgr.util.structGet(srsEstimate, "Valid", false))
    status = "valid_measured_srs_port_domain_estimate";
else
    status = "unavailable_measured_srs_port_domain_estimate";
end
end

function [gain_dB, rankEstimate, cond_dB] = localWidebandChannelDescriptors(Hwb)
gain_dB = NaN;
rankEstimate = NaN;
cond_dB = NaN;
gainLin = mean(abs(Hwb(:)).^2, "omitnan");
if isfinite(gainLin) && gainLin > 0
    gain_dB = 10 * log10(max(gainLin, eps));
end
try
    [cond, ~, rankEst] = sixgr.mimo.channelConditionNumber(Hwb);
catch
    cond = NaN;
    rankEst = NaN;
end
if isfinite(rankEst)
    rankEstimate = double(rankEst);
end
cond_dB = double(cond);
end

function ri = localResolveULRankIndicator(rankEstimate)
% A measured channel-rank descriptor is not a configured transmission rank.
% Zero/unavailable channel rank supplies no positive RI recommendation.
ri = NaN;
if isscalar(rankEstimate) && isfinite(rankEstimate) && rankEstimate >= 1 && rankEstimate==fix(rankEstimate)
    ri = double(rankEstimate);
end
end

function metrics = localResolveULPrecoderMeasurementFields(metrics, cfg, precInfo, srsEstimate)
configuredPMI = double(sixgr.util.structGet(cfg, "phy.pusch.TPMI", ...
    sixgr.util.structGet(cfg, "phy.pusch.PMI", NaN)));
metrics.ConfiguredPMI = configuredPMI;
metrics.ConfiguredCRI = NaN;

scheme = lower(string(sixgr.util.structGet(cfg, "phy.pusch.transmissionScheme", "nonCodebook")));
transformPrecoding = logical(sixgr.util.structGet(cfg, "phy.pusch.transformPrecoding", false));
isCodebook = scheme == "codebook" && ~transformPrecoding;

appliedPMI = sixgr.util.structGet(precInfo, "AppliedPrecoderPMI", NaN);
if ~(isCodebook && isnumeric(appliedPMI) && isscalar(appliedPMI) && ...
        isreal(appliedPMI) && isfinite(appliedPMI) && appliedPMI>=0 && appliedPMI==fix(appliedPMI))
    appliedPMI = NaN;
end
metrics.RuntimeAppliedPMI = double(appliedPMI);

if isCodebook
    estimatedTPMI = double(sixgr.util.structGet(srsEstimate, "TPMI", NaN));
    measuredSRS=strcmp(metrics.ChannelEstimateDomain,'srs_port_domain');
    if measuredSRS && logical(sixgr.util.structGet(srsEstimate,'Valid',false)) && ...
            isscalar(estimatedTPMI) && isfinite(estimatedTPMI) && estimatedTPMI>=0 && estimatedTPMI==fix(estimatedTPMI)
        metrics.PMI = estimatedTPMI;
        metrics.PMISource = char(string(srsEstimate.TPMISource));
        metrics.SelectedCodebookPortIndices1Based = double(sixgr.util.structGet( ...
            srsEstimate,'SelectedCodebookPortIndices1Based',[]));
    elseif ~measuredSRS && isfinite(appliedPMI)
        metrics.PMI = double(appliedPMI);
        metrics.PMISource = "ul_runtime_applied_codebook_tpmi";
    else
        metrics.PMI = NaN;
        metrics.PMISource = "ul_tpmi_unavailable_no_measured_recommendation_or_applicable_transmit_evidence";
    end
    metrics.PMIType = char(string(sixgr.util.structGet(precInfo, "AppliedPrecoderPMIType", "pusch_codebook")));
    metrics.PMICodebookMode = char(string(sixgr.util.structGet(precInfo, "AppliedPrecoderCodebookMode", ...
        sixgr.util.structGet(cfg, "phy.pusch.codebookType", ""))));
    if measuredSRS
        metrics.CSIReportMode = "ul_srs_measured_ri_tpmi_recommendation";
    else
        metrics.CSIReportMode = "ul_pusch_dmrs_effective_channel_no_tpmi_recommendation";
    end
    % Codebook support identifies antenna ports, not spatial beam IDs.
    % Applied physical-beam evidence belongs to the transmitter trace;
    % neither an SRS recommendation nor effective DM-RS creates beam IDs.
else
    if transformPrecoding
        metrics.CSIReportMode = "ul_gnb_reference_measurement_transform_precoding_active";
    else
        metrics.CSIReportMode = "ul_gnb_reference_measurement_noncodebook";
    end
    metrics.PMI = NaN;
    metrics.CRI = NaN;
    metrics.PMIType = "";
    metrics.PMICodebookMode = "";
    metrics.SelectedBeamIndices = [];
    metrics.PMISource = "ul_tpmi_not_applicable";
end
metrics.CSIPayloadBitLength = NaN;
metrics.CSIPayloadHex = "";
end

function Hwb = localWidebandChannelMatrix(Hest, cfg)
Hwb = [];
if isempty(Hest)
    return;
end
nd = ndims(Hest);
if nd >= 4
    try
        Havg = mean(mean(Hest, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(Hest, 1), 2);
    end
    Hwb = squeeze(Havg);
elseif nd == 3
    try
        Havg = mean(mean(Hest, 1, "omitnan"), 2, "omitnan");
    catch
        Havg = mean(mean(Hest, 1), 2);
    end
    Hwb = reshape(squeeze(Havg), [], 1);
elseif ismatrix(Hest)
    [expectedRx, expectedTx] = localExpectedWidebandMatrixSize(cfg);
    if size(Hest, 1) == expectedRx && size(Hest, 2) == expectedTx
        Hwb = double(Hest);
    else
        try
            Havg = mean(Hest(:), "omitnan");
        catch
            Havg = mean(Hest(:));
        end
        Hwb = Havg;
    end
end
if isvector(Hwb)
    Hwb = reshape(Hwb, numel(Hwb), 1);
end
if ~ismatrix(Hwb)
    Hwb = [];
end
end

function [expectedRx, expectedTx] = localExpectedWidebandMatrixSize(cfg)
expectedRx = double(sixgr.util.structGet(cfg, "phy.nRxAnt", 1));
expectedTx = double(sixgr.util.structGet(cfg, "phy.nTxAnt", ...
    sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)));
if ~(isscalar(expectedRx) && isfinite(expectedRx) && expectedRx >= 1)
    expectedRx = 1;
end
if ~(isscalar(expectedTx) && isfinite(expectedTx) && expectedTx >= 1)
    expectedTx = 1;
end
expectedRx = max(1, round(expectedRx));
expectedTx = max(1, round(expectedTx));
end


function [sinr_dB, source, status, pilotNMSE_dB, perRBSINR_dB] = localMeasureReferenceSINR(Hest, nVar, rxGrid, refInd, refSym, cfg)
sinr_dB = NaN;
source = "measurement_unavailable";
status = "unavailable";
pilotNMSE_dB = NaN;
perRBSINR_dB = [];
if isempty(Hest) || isempty(rxGrid) || isempty(refInd) || isempty(refSym)
    return;
end
% Reconstruct the union of physical pilot REs with each port's own symbols.
% A reshape of the port arrays is not that union for disjoint CDM groups.
% This shared receiver metric uses no transmitted data or true-channel input.
try
    reference = sixgr.phy.rx.referenceSignalMetrics(rxGrid, Hest, refInd, refSym, ...
        "NoiseVariance", nVar, "ContextLabel", "ul_received_reference");
catch ME
    if ~startsWith(string(ME.identifier), "sixgr:phy:rx:ReferenceMetric")
        rethrow(ME);
    end
    status = "reference_signal_measurement_unavailable:" + string(ME.identifier);
    return;
end
sinr_dB = reference.SINRdB;
pilotNMSE_dB = reference.NMSEdB;
source = "receiver_hest_reference_signal_measurement";
status = "OK";
perRBSINR_dB = localPerRBReferenceSINR(reference);
maxTrustedSINR = localMaxTrustedReferenceSINR(cfg);
if isfinite(maxTrustedSINR)
    perRBSINR_dB = min(perRBSINR_dB, maxTrustedSINR);
    if sinr_dB > maxTrustedSINR
        sinr_dB = maxTrustedSINR;
        status = "OK_dynamic_range_limited";
    end
end
end

function maxSINR = localMaxTrustedReferenceSINR(cfg)
maxSINR = double(sixgr.util.structGet(cfg, "phy.csi.maxTrustedReferenceSINR_dB", 80));
if ~(isscalar(maxSINR) && isfinite(maxSINR) && maxSINR > 0)
    maxSINR = inf;
end
end

function perRBSINR_dB = localPerRBReferenceSINR(reference)
% Aggregate linear powers over the same physical RE union as wideband SINR.
% Apply the measured noise floor after RB averaging, not per-RE clipping.
rbIndex = floor((reference.SubcarrierIndices - 1) ./ 12) + 1;
perRBSINR_dB = nan(max(rbIndex), 1);
for rb = 1:numel(perRBSINR_dB)
    mask = reference.ValidRowMask & rbIndex == rb;
    if ~any(mask), continue; end
    signal = mean(reference.PerRESignalPower(mask));
    disturbance = mean(reference.PerREResidualPower(mask));
    if isfinite(reference.NoiseVariance)
        disturbance = max(disturbance, reference.NoiseVariance);
    end
    if isfinite(signal) && signal > 0 && isfinite(disturbance) && disturbance >= 0
        perRBSINR_dB(rb) = 10*log10(signal/max(disturbance,eps));
    end
end
end
