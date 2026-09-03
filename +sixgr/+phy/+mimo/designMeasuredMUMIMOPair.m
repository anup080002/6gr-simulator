function design = designMeasuredMUMIMOPair(signatureA, signatureB, cfg, direction, rankA, rankB, spatialAuthorityMode)
%DESIGNMEASUREDMUMIMOPAIR Design an executable two-user MU spatial filter.
% Inputs are causal measured channel subspaces. TDD DL consumes an UL-SRS
% receiver subspace and converts it through calibrated reciprocity. FDD DL
% consumes the transmit-side right-singular subspace measured from DL
% CSI-RS directly. UL consumes its SRS receive subspace directly. The
% executable receiver keeps every physical observation branch and performs
% per-RE IRC using the desired channel and peer covariance.

direction = upper(strtrim(string(direction)));
if ~(direction == "DL" || direction == "UL")
    error("sixgr:mimo:InvalidMUMIMODirection", ...
        "Measured MU-MIMO design direction must be DL or UL.");
end
if nargin < 7 || strlength(strtrim(string(spatialAuthorityMode))) == 0
    if direction == "DL"
        spatialAuthorityMode = "tdd_reciprocity";
    else
        spatialAuthorityMode = "direct_ul_srs";
    end
end
spatialAuthorityMode = lower(strtrim(string(spatialAuthorityMode)));
if direction == "DL" && ...
        ~ismember(spatialAuthorityMode, ["tdd_reciprocity","direct_dl_csirs"])
    error("sixgr:mimo:InvalidDLMUMIMOSpatialAuthority", ...
        "DL MU-MIMO spatial authority must be tdd_reciprocity or direct_dl_csirs.");
elseif direction == "UL" && spatialAuthorityMode ~= "direct_ul_srs"
    error("sixgr:mimo:InvalidULMUMIMOSpatialAuthority", ...
        "UL MU-MIMO spatial authority must be direct_ul_srs.");
end
rankA = localPositiveRank(rankA, "rankA");
rankB = localPositiveRank(rankB, "rankB");
[qA, statusA] = localMeasuredSubspace(signatureA, rankA);
[qB, statusB] = localMeasuredSubspace(signatureB, rankB);

threshold_dB = double(sixgr.util.structGet(cfg, ...
    "mac.scheduler.muMimoPrecoderLeakageThreshold_dB", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoPrecoderLeakageThreshold_dB", NaN)));
minimumDesiredGain_dB = double(sixgr.util.structGet(cfg, ...
    "mac.scheduler.muMimoMinimumDesiredSubspaceGain_dB", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoMinimumDesiredSubspaceGain_dB", NaN)));
projectionMaxIterations = double(sixgr.util.structGet(cfg, ...
    "mac.scheduler.muMimoPhaseOnlyProjectionMaxIterations", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoPhaseOnlyProjectionMaxIterations", NaN)));
projectionTolerance = double(sixgr.util.structGet(cfg, ...
    "mac.scheduler.muMimoPhaseOnlyProjectionTolerance", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoPhaseOnlyProjectionTolerance", NaN)));
subspaceMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    "mac.scheduler.muMimoSpatialSignatureMode", ...
    sixgr.util.structGet(cfg, "phy.mimo.muMimoSpatialSignatureMode", "")))));
if ~ismember(subspaceMode, ["dominant_scheduled_rank", ...
        "complete_detectable_subspace"])
    error("sixgr:mimo:MissingMUMIMOSpatialSignatureMode", ...
        ["Measured MU-MIMO design requires the resolved YAML spatial " ...
         "signature mode; a hidden scheduled-rank/complete-subspace " ...
         "choice is forbidden."]);
end
if ~(isscalar(threshold_dB) && isfinite(threshold_dB) && threshold_dB < 0)
    error("sixgr:mimo:MissingMUMIMOLeakageThreshold", ...
        "Strict MU-MIMO requires a finite negative configured leakage threshold.");
end
if ~(isscalar(minimumDesiredGain_dB) && isfinite(minimumDesiredGain_dB) && ...
        minimumDesiredGain_dB <= 0)
    error("sixgr:mimo:MissingMUMIMODesiredGainThreshold", ...
        "Strict MU-MIMO requires a finite configured minimum desired-subspace gain in dB.");
end
if ~(isscalar(projectionMaxIterations) && isfinite(projectionMaxIterations) && ...
        projectionMaxIterations >= 1 && projectionMaxIterations == round(projectionMaxIterations))
    error("sixgr:mimo:MissingMUMIMOPhaseOnlyProjectionIterations", ...
        "Strict MU-MIMO requires a configured positive integer phase-only projection iteration limit.");
end
if ~(isscalar(projectionTolerance) && isfinite(projectionTolerance) && ...
        projectionTolerance > 0 && projectionTolerance < 1)
    error("sixgr:mimo:MissingMUMIMOPhaseOnlyProjectionTolerance", ...
        "Strict MU-MIMO requires a configured phase-only projection tolerance strictly between zero and one.");
end

design = localEmptyDesign(direction, threshold_dB, minimumDesiredGain_dB, ...
    projectionMaxIterations, projectionTolerance, spatialAuthorityMode, ...
    subspaceMode);
if isempty(qA) || isempty(qB)
    design.Status = char("invalid_measured_subspace:" + statusA + ":" + statusB);
    return;
end
if size(qA, 1) ~= size(qB, 1)
    design.Status = "measured_subspace_dimension_mismatch";
    return;
end

if direction == "DL"
    totalPorts = rankA + rankB;
    nElements = size(qA, 1);
    nRF = localFirstPositiveInteger(cfg, [ ...
        "runtime.antenna.gnb.NumTxRFChains", ...
        "antenna.bs.numTxRFChains", ...
        "scenario.bs.numTxRFChains", ...
        "antenna_and_array.bs_num_txrus"]);
    if ~isfinite(nRF) || nRF < totalPorts
        design.Status = "insufficient_gnb_tx_rf_chains";
        return;
    end
    % The hybrid baseband domain is the configured RF-chain domain, not
    % merely the number of scheduled streams. Collapsing F_RF to four
    % columns for two rank-2 UEs removes the nullspace required to suppress
    % every detectable frequency-selective peer mode even when the YAML
    % provisions additional RF chains.
    logicalRFPorts = double(nRF);
    arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, "bs", ...
        "Signal", "PDSCH", "NumElements", nElements, ...
        "NumPorts", logicalRFPorts, "NumRFChains", nRF, ...
        "MinimumPorts", totalPorts, "MatrixAuthorityScope", "role_only");
    hybridEnabled = logical(sixgr.util.structGet( ...
        arch, "HybridBeamformingEnabled", false));
    if hybridEnabled
        baseF = double(sixgr.util.structGet( ...
            arch, "HybridElementToPortMatrix", []));
    else
        % A fully-digital array is a valid measured-MU architecture when
        % every physical element has an independently controllable RF/baseband
        % dimension.  Requiring the hybrid flag here incorrectly rejected a
        % square 4-element/4-RF-chain implementation even though the exact
        % measured block-diagonalizing precoder can be applied directly.
        % Do not extend this permission to a reduced-RF-chain or rank-
        % deficient mapping: that would relabel a hybrid/analog limitation as
        % fully-digital MU truth.
        baseF = double(sixgr.util.structGet(arch, "PortToElementMatrix", []));
        if logicalRFPorts ~= nElements || nRF ~= nElements || ...
                ~isequal(size(baseF), [nElements nElements]) || ...
                rank(baseF) < nElements
            design.Status = "dl_mu_requires_full_digital_or_hybrid_element_control";
            return;
        end
    end
    if ~isequal(size(baseF), [nElements logicalRFPorts])
        design.Status = "hybrid_element_to_port_shape_mismatch";
        return;
    end
    if hybridEnabled
        rfDesignPolicy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
            "mac.scheduler.muMimoHybridRFDesignPolicy", ...
            sixgr.util.structGet(cfg, "phy.mimo.muMimoHybridRFDesignPolicy", ""))))) ;
        if ~ismember(rfDesignPolicy, ["fixed_configured_matrix", ...
                "measured_srs_phase_only_subarray"])
            error("sixgr:mimo:InvalidMUMIMOHybridRFDesignPolicy", ...
                ["Strict hybrid DL MU-MIMO requires " ...
                 "mimo.mu_mimo_hybrid_rf_design_policy to be " ...
                 "fixed_configured_matrix or " ...
                 "measured_srs_phase_only_subarray."]);
        end
    else
        rfDesignPolicy = "fully_digital_direct_element_control";
    end
    if spatialAuthorityMode == "tdd_reciprocity"
        % An UL receive subspace q corresponds to conj(q) on the reciprocal
        % DL transmit side because H_DL = H_UL.' (nonconjugate transpose).
        qADL = conj(qA);
        qBDL = conj(qB);
    else
        % CSI-RS receiver processing already returned the right-singular
        % transmit subspace of H_DL. Applying conjugation here would create
        % a physically different beam and corrupt FDD precoding.
        qADL = qA;
        qBDL = qB;
    end
    if hybridEnabled
        [F, rfStatus, rfResidual] = localDesignHybridRF(baseF, qADL, qBDL, ...
            rankA, rankB, rfDesignPolicy, projectionMaxIterations, projectionTolerance);
    else
        F = baseF;
        rfStatus = "fully_digital_full_rank_port_to_element_mapping";
        rfResidual = NaN;
    end
    if isempty(F)
        design.Status = char(rfStatus);
        return;
    end
    [wA, pA, leakA, gainA, okA, reasonA] = localNullPeer( ...
        qADL, qBDL, F, rankA, projectionTolerance, ...
        "unit_total_transmit_power", threshold_dB);
    [wB, pB, leakB, gainB, okB, reasonB] = localNullPeer( ...
        qBDL, qADL, F, rankB, projectionTolerance, ...
        "unit_total_transmit_power", threshold_dB);
    design.TotalLogicalPorts = double(logicalRFPorts);
    design.NumRFChains = double(nRF);
    design.HybridElementToPortMatrix = F;
    design.BaseHybridElementToPortMatrixSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(baseF));
    design.HybridElementToPortMatrixSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(F));
    design.HybridRFDesignPolicy = char(rfDesignPolicy);
    design.HybridRFDesignStatus = char(rfStatus);
    design.HybridRFCompletePeerResidual = double(rfResidual);
    if hybridEnabled
        design.TransmitArchitecture = "hybrid_rf_baseband";
    else
        design.TransmitArchitecture = "fully_digital_element_control";
    end
    design.Member1PrecoderLogicalPorts = wA;
    design.Member2PrecoderLogicalPorts = wB;
    design.Member1PrecoderPhysical = pA;
    design.Member2PrecoderPhysical = pB;
    design.PrecoderNormalizationConvention = "unit_frobenius";
    design.Member1ReceiveCombiner = [];
    design.Member2ReceiveCombiner = [];
    subspaceLabel = localSubspaceEvidenceLabel(subspaceMode);
    if hybridEnabled && spatialAuthorityMode == "tdd_reciprocity"
        design.MetricSource = char("measured_tdd_srs_reciprocal_" + ...
            subspaceLabel + "_hybrid_block_diagonalized_precoder_leakage");
        design.EvidenceSource = char("causal_measured_srs_" + subspaceLabel + ...
            "_reciprocity_phase_only_hybrid_and_frozen_baseband");
    elseif hybridEnabled
        design.MetricSource = char("measured_fdd_csirs_direct_transmit_" + ...
            subspaceLabel + "_hybrid_block_diagonalized_precoder_leakage");
        design.EvidenceSource = char("causal_measured_csirs_direct_transmit_" + ...
            subspaceLabel + "_phase_only_hybrid_and_frozen_baseband");
    elseif spatialAuthorityMode == "tdd_reciprocity"
        design.MetricSource = char("measured_tdd_srs_reciprocal_" + ...
            subspaceLabel + "_fully_digital_block_diagonalized_precoder_leakage");
        design.EvidenceSource = char("causal_measured_srs_" + subspaceLabel + ...
            "_reciprocity_fully_digital_and_frozen_baseband");
    else
        design.MetricSource = char("measured_fdd_csirs_direct_transmit_" + ...
            subspaceLabel + "_fully_digital_block_diagonalized_precoder_leakage");
        design.EvidenceSource = char("causal_measured_csirs_direct_transmit_" + ...
            subspaceLabel + "_fully_digital_and_frozen_baseband");
    end
else
    requested = upper(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.pusch.equalizer", sixgr.util.structGet(cfg, "phy.rx.equalizer", "")))));
    if ~contains(requested, "IRC")
        design.Status = "ul_mu_requires_configured_irc_receiver";
        return;
    end
    receiveProcessingMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "mac.scheduler.ulMuMimoReceiveProcessingMode", ...
        sixgr.util.structGet(cfg, "phy.mimo.ulMuMimoReceiveProcessingMode", "")))));
    if receiveProcessingMode ~= "full_dimensional_per_re_irc"
        error("sixgr:mimo:InvalidULMUMIMOReceiveProcessingMode", ...
            "UL MU-MIMO requires the YAML-owned " + ...
            "full_dimensional_per_re_irc receiver mode. A frozen wideband " + ...
            "rank-reducing projection is not valid for a frequency-selective " + ...
            "production waveform.");
    end
    F = eye(size(qA, 1));
    [cA, ~, leakA, gainA, okA, reasonA] = localNullPeer( ...
        qA, qB, F, rankA, projectionTolerance, ...
        "semi_unitary_receive_combiner", threshold_dB);
    [cB, ~, leakB, gainB, okB, reasonB] = localNullPeer( ...
        qB, qA, F, rankB, projectionTolerance, ...
        "semi_unitary_receive_combiner", threshold_dB);
    % cA/cB are an admission diagnostic, not a receiver preprocessor. A
    % wideband projection to the scheduled rank destroyed receive dimensions
    % before per-RE IRC on CDL channels. Freeze an identity preprocessor so
    % the exact received waveform and peer tensor retain all Nrx branches.
    runtimeCombiner = eye(size(qA, 1));
    design.Member1AdmissionReceiveCombiner = cA;
    design.Member2AdmissionReceiveCombiner = cB;
    design.Member1AdmissionMatrixSHA256 = char(localMatrixDigestOrEmpty(cA));
    design.Member2AdmissionMatrixSHA256 = char(localMatrixDigestOrEmpty(cB));
    design.Member1ReceiveCombiner = runtimeCombiner;
    design.Member2ReceiveCombiner = runtimeCombiner;
    design.ReceiveCombinerNormalizationConvention = "full_dimensional_unitary_identity";
    design.ULReceiveProcessingMode = char(receiveProcessingMode);
    subspaceLabel = localSubspaceEvidenceLabel(subspaceMode);
    design.MetricSource = char("measured_srs_" + subspaceLabel + ...
        "_admission_projection_leakage_full_dimensional_per_re_irc");
    design.EvidenceSource = char("causal_measured_srs_" + subspaceLabel + ...
        "_pairing_with_full_receiver_observation_and_runtime_per_re_irc_covariance");
end

% DL MU admission is a joint pair decision.  The interference observed by
% UE A is UE B's beam through UE A's measured channel, divided by UE A's
% own desired beam through that same channel (and conversely for UE B).
% The former implementation divided each beam's peer leakage by that
% beam's power at its intended UE.  Those denominators belong to different
% receivers and can falsely admit a pair when the two desired links are
% unequal.  UL cA/cB are receiver combiners, so localNullPeer already
% evaluates the correct per-victim peer/desired ratio there.
if direction == "DL" && ~isempty(pA) && ~isempty(pB)
    desiredAtA = norm(qADL' * pA, "fro").^2;
    peerAtA = norm(qADL' * pB, "fro").^2;
    desiredAtB = norm(qBDL' * pB, "fro").^2;
    peerAtB = norm(qBDL' * pA, "fro").^2;
    leakA = 10 .* log10(max(peerAtA ./ max(desiredAtA, realmin), realmin));
    leakB = 10 .* log10(max(peerAtB ./ max(desiredAtB, realmin), realmin));
end
design.MemberLeakage_dB = double([leakA leakB]);
design.MemberDesiredGain_dB = double([gainA gainB]);
design.WorstLeakage_dB = double(max([leakA leakB]));
design.MinimumDesiredGainObserved_dB = double(min([gainA gainB]));
design.Member1MatrixSHA256 = char(localSelectedDigest(design, 1, direction));
design.Member2MatrixSHA256 = char(localSelectedDigest(design, 2, direction));
design.Compatible = logical(okA && okB && ...
    design.WorstLeakage_dB <= threshold_dB && ...
    design.MinimumDesiredGainObserved_dB >= minimumDesiredGain_dB);
if design.Compatible
    design.Status = "compatible_executable_measured_spatial_design";
elseif ~okA || ~okB
    design.Status = char("spatial_design_failed:" + string(reasonA) + ":" + string(reasonB));
elseif design.WorstLeakage_dB > threshold_dB
    design.Status = "designed_pair_victim_leakage_exceeds_configured_threshold";
else
    design.Status = "desired_subspace_gain_below_configured_threshold";
end
end

function [F, status, worstResidual] = localDesignHybridRF( ...
        baseF, qA, qB, rankA, rankB, policy, maxIterations, tolerance)
F = [];
status = "hybrid_rf_design_not_evaluated";
worstResidual = NaN;
if policy == "fixed_configured_matrix"
    F = baseF;
    status = "fixed_configured_hybrid_matrix";
    peerResiduals = [localNormalizedPeerResidual(qB, F(:,1:rankA)), ...
        localNormalizedPeerResidual(qA, F(:,rankA+(1:rankB)))];
    worstResidual = max(peerResiduals);
    return;
end
targets = [qA(:, 1:rankA), qB(:, 1:rankB)];
peerSubspaces = {qB, qA};
if size(targets, 2) ~= size(baseF, 2)
    status = "hybrid_rf_target_stream_count_mismatch";
    return;
end
F = complex(zeros(size(baseF)));
columnResiduals = NaN(1, size(baseF, 2));
for column = 1:size(baseF, 2)
    magnitude = abs(baseF(:, column));
    support = magnitude > 1e-14;
    if ~any(support)
        F = [];
        status = "hybrid_rf_base_matrix_zero_column";
        return;
    end
    if column <= rankA
        peer = peerSubspaces{1};
    else
        peer = peerSubspaces{2};
    end
    [columnVector, columnResidual, columnStatus] = ...
        localPhaseOnlyPeerNullColumn(targets(:, column), peer, ...
        magnitude, support, baseF(:, column), maxIterations, tolerance);
    if isempty(columnVector)
        F = [];
        status = "hybrid_rf_complete_peer_projection_failed:" + columnStatus;
        worstResidual = columnResidual;
        return;
    end
    F(:, column) = columnVector;
    columnResiduals(column) = columnResidual;
end
if ~localSamePhaseOnlyHardwareContract(baseF, F)
    F = [];
    status = "hybrid_rf_phase_only_hardware_contract_failed";
    return;
end
worstResidual = max(columnResiduals);
if ~(isfinite(worstResidual) && worstResidual <= tolerance)
    F = [];
    status = "hybrid_rf_complete_peer_projection_tolerance_not_met";
    return;
end
status = "measured_spatial_phase_only_subarray_complete_peer_null_rf_matrix";
end

function [columnVector, bestResidual, status] = localPhaseOnlyPeerNullColumn( ...
        target, peerSubspace, magnitude, support, baseColumn, maxIterations, tolerance)
columnVector = [];
bestResidual = Inf;
status = "not_evaluated";
supportIndex = find(support);
peerOnSupport = double(peerSubspace(supportIndex, :));
if isempty(peerOnSupport)
    status = "peer_subspace_empty_on_rf_support";
    return;
end
nullBasis = null(peerOnSupport');
if isempty(nullBasis)
    status = "no_constant_modulus_support_peer_nullspace";
    return;
end
targetOnSupport = double(target(supportIndex));
projectedTarget = nullBasis * (nullBasis' * targetOnSupport);
if norm(projectedTarget) <= eps
    projectedTarget = nullBasis(:, 1);
end
supportMagnitude = double(magnitude(supportIndex));
phaseSeed = angle(projectedTarget);
zeroSeed = abs(projectedTarget) <= 1e-14;
phaseSeed(zeroSeed) = angle(double(baseColumn(supportIndex(zeroSeed))));
candidate = supportMagnitude .* exp(1i .* phaseSeed);
bestCandidate = candidate;
bestGain = -Inf;
for iteration = 1:round(maxIterations)
    projected = nullBasis * (nullBasis' * candidate);
    if norm(projected) <= eps || any(~isfinite(real(projected)) | ~isfinite(imag(projected)))
        status = "nonfinite_or_zero_peer_null_projection";
        return;
    end
    updated = supportMagnitude .* exp(1i .* angle(projected));
    residual = norm(peerOnSupport' * updated) ./ max(norm(updated), eps);
    desiredGain = abs(targetOnSupport' * updated) ./ ...
        max(norm(targetOnSupport) * norm(updated), eps);
    if residual < bestResidual || ...
            (abs(residual - bestResidual) <= eps(max(1, bestResidual)) && desiredGain > bestGain)
        bestResidual = double(residual);
        bestGain = double(desiredGain);
        bestCandidate = updated;
    end
    candidate = updated;
end
if ~(isfinite(bestResidual) && bestResidual <= tolerance)
    status = "phase_only_alternating_projection_did_not_converge";
    return;
end
columnVector = complex(zeros(size(target)));
columnVector(supportIndex) = bestCandidate;
status = "ok";
end

function residual = localNormalizedPeerResidual(peerSubspace, candidate)
residual = norm(peerSubspace' * candidate, "fro") ./ max(norm(candidate, "fro"), eps);
end

function tf = localSamePhaseOnlyHardwareContract(baseF, candidateF)
baseSupport = abs(baseF) > 1e-14;
candidateSupport = abs(candidateF) > 1e-14;
scale = max(norm(abs(baseF), "fro"), eps);
tf = isequal(size(baseF), size(candidateF)) && ...
    all(isfinite(real(candidateF(:)))) && all(isfinite(imag(candidateF(:)))) && ...
    isequal(baseSupport, candidateSupport) && ...
    norm(abs(baseF) - abs(candidateF), "fro") ./ scale <= 1e-12 && ...
    all(abs(sum(abs(candidateF).^2, 1) - sum(abs(baseF).^2, 1)) <= 1e-12);
end

function rankValue = localPositiveRank(value, label)
rankValue = double(value);
if ~(isscalar(rankValue) && isfinite(rankValue) && rankValue >= 1 && ...
        rankValue == round(rankValue))
    error("sixgr:mimo:InvalidMUMIMORank", "%s must be a positive integer.", label);
end
end

function [q, status] = localMeasuredSubspace(value, requestedRank)
q = [];
status = "unavailable";
if ~(isnumeric(value) && ismatrix(value) && ~isempty(value))
    return;
end
value = double(value);
if any(~isfinite(real(value(:)))) || any(~isfinite(imag(value(:)))) || ...
        norm(value, "fro") <= 0 || size(value, 2) < requestedRank
    status = "nonfinite_zero_or_rank_deficient_input";
    return;
end
[u, s, ~] = svd(value, "econ");
singularValues = diag(s);
tol = max(size(value)) * eps(max([singularValues(:); 1]));
if nnz(singularValues > tol) < requestedRank
    status = "rank_deficient_measured_subspace";
    return;
end
% Preserve every numerically detectable measured peer-channel dimension
% and its measured energy. requestedRank remains a minimum validity
% condition, not a truncation instruction. MU nulling against only the
% scheduled layer count leaves the peer's remaining measured spatial modes
% as real interference; discarding S also makes desired-gain selection
% insensitive to the channel covariance actually measured by SRS/CSI-RS.
retainedRank = nnz(singularValues > tol);
q = u(:, 1:retainedRank) * s(1:retainedRank, 1:retainedRank);
status = "ok";
end

function [wLogical, wPhysical, leakage_dB, gain_dB, ok, reason] = ...
        localNullPeer(qDesired, qPeer, F, nStreams, designedNullTolerance, normalizationMode, requiredLeakage_dB)
wLogical = [];
wPhysical = [];
leakage_dB = NaN;
gain_dB = NaN;
ok = false;
reason = "uninitialized";
peerEffective = qPeer' * F;
[~, sPeer, vPeer] = svd(peerEffective);
svPeer = diag(sPeer);
machineTolerance = max(size(peerEffective)) * eps(max([svPeer(:); 1]));
designedTolerance = double(designedNullTolerance) * max([svPeer(:); 1]);
tolPeer = max(machineTolerance, designedTolerance);
peerRank = nnz(svPeer > tolPeer);
normalizationMode = lower(strtrim(string(normalizationMode)));
if ~ismember(normalizationMode, ["unit_total_transmit_power", ...
        "semi_unitary_receive_combiner"])
    error("sixgr:mimo:InvalidMUMIMONormalizationMode", ...
        "Unsupported measured MU matrix normalization mode '%s'.", ...
        char(normalizationMode));
end
% Retain the exact block-diagonalizer as a candidate when it exists, but
% do not fail before evaluating a finite-leakage constrained solution.
if size(vPeer, 2) - peerRank >= nStreams
    nullBasis = vPeer(:, (peerRank + 1):end);
    desiredInNull = qDesired' * F * nullBasis;
    [~, sDesired, vDesired] = svd(desiredInNull, "econ");
    svDesired = diag(sDesired);
    tolDesired = max(size(desiredInNull)) * eps(max([svDesired(:); 1]));
    if nnz(svDesired > tolDesired) >= nStreams && ...
            size(vDesired, 2) >= nStreams
        exactLogical = nullBasis * vDesired(:, 1:nStreams);
        [exactLogical, ~] = qr(exactLogical, 0);
        [exactLogical, exactPhysical, exactOK] = ...
            localNormalizeSpatialCandidate(exactLogical, F, ...
            normalizationMode, nStreams);
        if exactOK
            wLogical = exactLogical;
            wPhysical = exactPhysical;
        end
    end
end
% Zero-forcing is only one feasible point.  On a frequency-selective
% measured channel, nulling every detectable peer covariance mode can
% place the desired UE in a near-null and make small estimation errors
% dominate the actual waveform.  Search the measured generalized
% eigenmodes for the highest desired power that still satisfies the exact
% YAML leakage ratio.  This is a covariance-constrained SLNR design: no
% configured channel value or oracle FIR participates.
desiredCovariance = F' * (qDesired * qDesired') * F;
peerCovariance = F' * (qPeer * qPeer') * F;
desiredCovariance = (desiredCovariance + desiredCovariance') ./ 2;
peerCovariance = (peerCovariance + peerCovariance') ./ 2;
requiredLeakageRatio = 10.^(double(requiredLeakage_dB) ./ 10);
if isempty(wPhysical)
    bestDesiredPower = -Inf;
else
    bestDesiredPower = norm(qDesired' * wPhysical, "fro").^2;
end
bestLogical = wLogical;
bestPhysical = wPhysical;
covarianceScale = max(real(trace(peerCovariance)) ./ ...
    max(size(peerCovariance, 1), 1), eps);
regularizationGrid = covarianceScale .* 10.^linspace(-12, 6, 73);
for regularization = regularizationGrid
    regularizedPeer = peerCovariance + ...
        double(regularization) .* eye(size(peerCovariance));
    try
        [candidateVectors, candidateValues] = eig( ...
            desiredCovariance, regularizedPeer, "vector");
    catch
        continue;
    end
    [~, order] = sort(real(candidateValues), "descend");
    if numel(order) < nStreams
        continue;
    end
    candidateLogical = candidateVectors(:, order(1:nStreams));
    [candidateLogical, ~] = qr(candidateLogical, 0);
    [candidateLogical, candidatePhysical, candidateOK] = ...
        localNormalizeSpatialCandidate(candidateLogical, F, ...
        normalizationMode, nStreams);
    if ~candidateOK
        continue;
    end
    candidateDesiredPower = norm(qDesired' * candidatePhysical, "fro").^2;
    candidatePeerPower = norm(qPeer' * candidatePhysical, "fro").^2;
    candidateLeakageRatio = candidatePeerPower ./ ...
        max(candidateDesiredPower, realmin);
    if isfinite(candidateDesiredPower) && candidateDesiredPower > bestDesiredPower && ...
            isfinite(candidateLeakageRatio) && ...
            candidateLeakageRatio <= requiredLeakageRatio
        bestDesiredPower = candidateDesiredPower;
        bestLogical = candidateLogical;
        bestPhysical = candidatePhysical;
    end
end
wLogical = bestLogical;
wPhysical = bestPhysical;
if isempty(wLogical) || isempty(wPhysical)
    reason = "no_leakage_constrained_spatial_solution";
    return;
end
% Both admission quantities are ratios.  The prior implementation exposed
% absolute projected energy in dB; that value changed merely when the
% measured signature retained another singular mode and therefore was not
% a valid cross-scenario threshold.  Use the same peer-to-desired ratio
% later verified on the exact waveform, and express desired gain as the
% fraction of the best unconstrained measured beam that survives peer
% nulling.  These definitions are invariant to signature scale, retained
% snapshot count and scheduled layer count.
peerPower = norm(qPeer' * wPhysical, "fro").^2;
desiredPower = norm(qDesired' * wPhysical, "fro").^2;
[~, ~, vReference] = svd(qDesired' * F, "econ");
if size(vReference, 2) < nStreams
    reason = "desired_reference_subspace_rank_deficient";
    return;
end
referenceLogical = vReference(:, 1:nStreams);
[referenceLogical, ~] = qr(referenceLogical, 0);
referencePhysical = F * referenceLogical;
if normalizationMode == "unit_total_transmit_power"
    referenceNorm = norm(referencePhysical, "fro");
    if ~(isfinite(referenceNorm) && referenceNorm > eps)
        reason = "zero_or_nonfinite_desired_reference_power";
        return;
    end
    referencePhysical = referencePhysical ./ referenceNorm;
elseif normalizationMode == "semi_unitary_receive_combiner"
    [referencePhysical, ~] = qr(referencePhysical, 0);
end
referenceDesiredPower = norm(qDesired' * referencePhysical, "fro").^2;
if ~(isfinite(desiredPower) && desiredPower > realmin && ...
        isfinite(referenceDesiredPower) && referenceDesiredPower > realmin)
    reason = "zero_or_nonfinite_desired_subspace_power";
    return;
end
leakageRatio = peerPower ./ desiredPower;
retainedDesiredGainRatio = desiredPower ./ referenceDesiredPower;
leakage_dB = 10 .* log10(max(double(leakageRatio), realmin));
gain_dB = 10 .* log10(max(double(retainedDesiredGainRatio), realmin));
ok = isfinite(leakage_dB) && isfinite(gain_dB);
reason = "ok";
end

function [logicalMatrix, physicalMatrix, ok] = ...
        localNormalizeSpatialCandidate(logicalMatrix, F, normalizationMode, nStreams)
ok = false;
physicalMatrix = F * logicalMatrix;
if isempty(physicalMatrix) || any(~isfinite(real(physicalMatrix(:)))) || ...
        any(~isfinite(imag(physicalMatrix(:)))) || ...
        any(vecnorm(physicalMatrix, 2, 1) <= eps)
    return;
end
if normalizationMode == "unit_total_transmit_power"
    totalPowerNorm = norm(physicalMatrix, "fro");
    if ~(isfinite(totalPowerNorm) && totalPowerNorm > eps)
        return;
    end
    logicalMatrix = logicalMatrix ./ totalPowerNorm;
    physicalMatrix = F * logicalMatrix;
    normalizedPower = norm(physicalMatrix, "fro").^2;
    ok = isfinite(normalizedPower) && abs(normalizedPower - 1) <= 1e-10;
else
    [physicalMatrix, ~] = qr(physicalMatrix, 0);
    if size(F, 1) == size(F, 2) && ...
            norm(F - eye(size(F)), "fro") <= 1e-12
        logicalMatrix = physicalMatrix;
    else
        logicalMatrix = pinv(F) * physicalMatrix;
    end
    gramResidual = norm(physicalMatrix' * physicalMatrix - eye(nStreams), "fro") ./ ...
        max(1, norm(physicalMatrix' * physicalMatrix, "fro"));
    ok = isfinite(gramResidual) && gramResidual <= 1e-10;
end
end

function value = localFirstPositiveInteger(cfg, paths)
value = NaN;
for path = string(paths(:)).'
    candidate = double(sixgr.util.structGet(cfg, path, NaN));
    if isscalar(candidate) && isfinite(candidate) && candidate >= 1 && ...
            candidate == round(candidate)
        value = candidate;
        return;
    end
end
end

function token = localSelectedDigest(design, memberIndex, direction)
if direction == "DL"
    matrix = design.("Member" + string(memberIndex) + "PrecoderPhysical");
else
    matrix = design.("Member" + string(memberIndex) + "ReceiveCombiner");
end
if isempty(matrix)
    token = "";
else
    token = string(sixgr.phy.mimo.MatrixContract.digest(double(matrix)));
end
end

function token = localMatrixDigestOrEmpty(matrix)
if isempty(matrix)
    token = "";
else
    token = string(sixgr.phy.mimo.MatrixContract.digest(double(matrix)));
end
end

function design = localEmptyDesign(direction, threshold_dB, minimumDesiredGain_dB, ...
        projectionMaxIterations, projectionTolerance, spatialAuthorityMode, subspaceMode)
design = struct( ...
    "ContractVersion", "MeasuredMUMIMOPairDesign/v13", ...
    "LeakageMetricConvention", "per_victim_other_user_beam_power_over_own_desired_beam_power", ...
    "DesiredGainMetricConvention", "leakage_constrained_desired_power_over_unconstrained_measured_desired_power", ...
    "Direction", char(direction), ...
    "SpatialAuthorityMode", char(spatialAuthorityMode), ...
    "SpatialSignatureSubspaceMode", char(subspaceMode), ...
    "Compatible", false, ...
    "Status", "not_evaluated", ...
    "RequiredLeakageThreshold_dB", double(threshold_dB), ...
    "RequiredMinimumDesiredGain_dB", double(minimumDesiredGain_dB), ...
    "WorstLeakage_dB", NaN, ...
    "MinimumDesiredGainObserved_dB", NaN, ...
    "MemberLeakage_dB", [NaN NaN], ...
    "MemberDesiredGain_dB", [NaN NaN], ...
    "MetricSource", "", ...
    "EvidenceSource", "", ...
    "TotalLogicalPorts", NaN, ...
    "NumRFChains", NaN, ...
    "HybridElementToPortMatrix", [], ...
    "BaseHybridElementToPortMatrixSHA256", "", ...
    "HybridElementToPortMatrixSHA256", "", ...
    "HybridRFDesignPolicy", "", ...
    "HybridRFDesignStatus", "", ...
    "HybridRFCompletePeerResidual", NaN, ...
    "TransmitArchitecture", "", ...
    "PhaseOnlyProjectionMaxIterations", double(projectionMaxIterations), ...
    "PhaseOnlyProjectionTolerance", double(projectionTolerance), ...
    "Member1PrecoderLogicalPorts", [], ...
    "Member2PrecoderLogicalPorts", [], ...
    "Member1PrecoderPhysical", [], ...
    "Member2PrecoderPhysical", [], ...
    "PrecoderNormalizationConvention", "", ...
    "Member1ReceiveCombiner", [], ...
    "Member2ReceiveCombiner", [], ...
    "Member1AdmissionReceiveCombiner", [], ...
    "Member2AdmissionReceiveCombiner", [], ...
    "Member1AdmissionMatrixSHA256", "", ...
    "Member2AdmissionMatrixSHA256", "", ...
    "ReceiveCombinerNormalizationConvention", "", ...
    "ULReceiveProcessingMode", "", ...
    "Member1MatrixSHA256", "", ...
    "Member2MatrixSHA256", "");
end

function label = localSubspaceEvidenceLabel(mode)
mode = lower(strtrim(string(mode)));
if mode == "complete_detectable_subspace"
    label = "complete_peer_subspace";
elseif mode == "dominant_scheduled_rank"
    label = "scheduled_rank_peer_subspace";
else
    error("sixgr:mimo:InvalidMUMIMOSpatialSignatureMode", ...
        "Unsupported MU-MIMO spatial signature mode '%s'.", char(mode));
end
end
