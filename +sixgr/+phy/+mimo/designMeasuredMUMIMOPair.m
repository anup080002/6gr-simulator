function design = designMeasuredMUMIMOPair(signatureA, signatureB, cfg, direction, rankA, rankB)
%DESIGNMEASUREDMUMIMOPAIR Design an executable two-user MU spatial filter.
% The inputs are causal receiver channel subspaces measured from SRS.  In
% TDD DL they are conjugated into the reciprocal downlink transmit
% subspace, used to select a hardware-realizable phase-only subarray RF
% matrix, and block diagonalized in baseband. In UL they define the receive
% projection that the configured IRC receiver must be capable of realizing.

direction = upper(strtrim(string(direction)));
if ~(direction == "DL" || direction == "UL")
    error("sixgr:mimo:InvalidMUMIMODirection", ...
        "Measured MU-MIMO design direction must be DL or UL.");
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
if ~(isscalar(threshold_dB) && isfinite(threshold_dB) && threshold_dB < 0)
    error("sixgr:mimo:MissingMUMIMOLeakageThreshold", ...
        "Strict MU-MIMO requires a finite negative configured leakage threshold.");
end
if ~(isscalar(minimumDesiredGain_dB) && isfinite(minimumDesiredGain_dB) && ...
        minimumDesiredGain_dB <= 0)
    error("sixgr:mimo:MissingMUMIMODesiredGainThreshold", ...
        "Strict MU-MIMO requires a finite configured minimum desired-subspace gain in dB.");
end

design = localEmptyDesign(direction, threshold_dB, minimumDesiredGain_dB);
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
    arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture(cfg, "bs", ...
        "Signal", "PDSCH", "NumElements", nElements, ...
        "NumPorts", totalPorts, "NumRFChains", nRF, ...
        "MinimumPorts", totalPorts, "MatrixAuthorityScope", "role_only");
    if ~logical(sixgr.util.structGet(arch, "HybridBeamformingEnabled", false))
        design.Status = "dl_mu_requires_element_domain_hybrid_precoding";
        return;
    end
    baseF = double(sixgr.util.structGet(arch, "HybridElementToPortMatrix", []));
    if ~isequal(size(baseF), [nElements totalPorts])
        design.Status = "hybrid_element_to_port_shape_mismatch";
        return;
    end
    rfDesignPolicy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "mac.scheduler.muMimoHybridRFDesignPolicy", ...
        sixgr.util.structGet(cfg, "phy.mimo.muMimoHybridRFDesignPolicy", ""))))) ;
    if ~ismember(rfDesignPolicy, ["fixed_configured_matrix", ...
            "measured_srs_phase_only_subarray"])
        error("sixgr:mimo:InvalidMUMIMOHybridRFDesignPolicy", ...
            ["Strict DL MU-MIMO requires mimo.mu_mimo_hybrid_rf_design_policy " ...
             "to be fixed_configured_matrix or measured_srs_phase_only_subarray."]);
    end
    % An UL receive subspace q corresponds to conj(q) on the reciprocal DL
    % transmit side because H_DL = H_UL.' (nonconjugate transpose).
    qADL = conj(qA);
    qBDL = conj(qB);
    [F, rfStatus] = localDesignHybridRF(baseF, qADL, qBDL, rankA, rankB, rfDesignPolicy);
    if isempty(F)
        design.Status = char(rfStatus);
        return;
    end
    [wA, pA, leakA, gainA, okA, reasonA] = localNullPeer(qADL, qBDL, F, rankA);
    [wB, pB, leakB, gainB, okB, reasonB] = localNullPeer(qBDL, qADL, F, rankB);
    design.TotalLogicalPorts = double(totalPorts);
    design.NumRFChains = double(nRF);
    design.HybridElementToPortMatrix = F;
    design.BaseHybridElementToPortMatrixSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(baseF));
    design.HybridElementToPortMatrixSHA256 = char( ...
        sixgr.phy.mimo.MatrixContract.digest(F));
    design.HybridRFDesignPolicy = char(rfDesignPolicy);
    design.HybridRFDesignStatus = char(rfStatus);
    design.Member1PrecoderLogicalPorts = wA;
    design.Member2PrecoderLogicalPorts = wB;
    design.Member1PrecoderPhysical = pA;
    design.Member2PrecoderPhysical = pB;
    design.Member1ReceiveCombiner = [];
    design.Member2ReceiveCombiner = [];
    design.MetricSource = "measured_tdd_srs_reciprocal_hybrid_block_diagonalized_precoder_leakage";
    design.EvidenceSource = "causal_measured_srs_reciprocity_phase_only_hybrid_and_frozen_baseband";
else
    requested = upper(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.pusch.equalizer", sixgr.util.structGet(cfg, "phy.rx.equalizer", "")))));
    if ~contains(requested, "IRC")
        design.Status = "ul_mu_requires_configured_irc_receiver";
        return;
    end
    F = eye(size(qA, 1));
    [cA, ~, leakA, gainA, okA, reasonA] = localNullPeer(qA, qB, F, rankA);
    [cB, ~, leakB, gainB, okB, reasonB] = localNullPeer(qB, qA, F, rankB);
    design.Member1ReceiveCombiner = cA;
    design.Member2ReceiveCombiner = cB;
    design.MetricSource = "measured_srs_irc_receive_projection_leakage";
    design.EvidenceSource = "causal_measured_srs_subspace_and_runtime_irc_covariance";
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
    design.Status = "designed_leakage_exceeds_configured_threshold";
else
    design.Status = "desired_subspace_gain_below_configured_threshold";
end
end

function [F, status] = localDesignHybridRF(baseF, qA, qB, rankA, rankB, policy)
F = [];
status = "hybrid_rf_design_not_evaluated";
if policy == "fixed_configured_matrix"
    F = baseF;
    status = "fixed_configured_hybrid_matrix";
    return;
end
targets = [qA(:, 1:rankA), qB(:, 1:rankB)];
if size(targets, 2) ~= size(baseF, 2)
    status = "hybrid_rf_target_stream_count_mismatch";
    return;
end
F = complex(zeros(size(baseF)));
for column = 1:size(baseF, 2)
    magnitude = abs(baseF(:, column));
    support = magnitude > 1e-14;
    if ~any(support)
        F = [];
        status = "hybrid_rf_base_matrix_zero_column";
        return;
    end
    target = targets(:, column);
    phase = angle(baseF(:, column));
    usable = support & abs(target) > 1e-14;
    phase(usable) = angle(target(usable));
    F(support, column) = magnitude(support) .* exp(1i .* phase(support));
end
if ~localSamePhaseOnlyHardwareContract(baseF, F)
    F = [];
    status = "hybrid_rf_phase_only_hardware_contract_failed";
    return;
end
status = "measured_srs_phase_only_subarray_rf_matrix";
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
q = u(:, 1:requestedRank);
status = "ok";
end

function [wLogical, wPhysical, leakage_dB, gain_dB, ok, reason] = ...
        localNullPeer(qDesired, qPeer, F, nStreams)
wLogical = [];
wPhysical = [];
leakage_dB = NaN;
gain_dB = NaN;
ok = false;
reason = "uninitialized";
peerEffective = qPeer' * F;
[~, sPeer, vPeer] = svd(peerEffective);
svPeer = diag(sPeer);
tolPeer = max(size(peerEffective)) * eps(max([svPeer(:); 1]));
peerRank = nnz(svPeer > tolPeer);
if size(vPeer, 2) - peerRank < nStreams
    reason = "insufficient_peer_nullspace";
    return;
end
nullBasis = vPeer(:, (peerRank + 1):end);
desiredInNull = qDesired' * F * nullBasis;
[~, sDesired, vDesired] = svd(desiredInNull, "econ");
svDesired = diag(sDesired);
tolDesired = max(size(desiredInNull)) * eps(max([svDesired(:); 1]));
if nnz(svDesired > tolDesired) < nStreams || size(vDesired, 2) < nStreams
    reason = "desired_channel_rank_lost_in_peer_nullspace";
    return;
end
wLogical = nullBasis * vDesired(:, 1:nStreams);
[wLogical, ~] = qr(wLogical, 0);
wPhysical = F * wLogical;
for column = 1:size(wPhysical, 2)
    columnNorm = norm(wPhysical(:, column));
    if ~(isfinite(columnNorm) && columnNorm > eps)
        reason = "zero_or_nonfinite_physical_precoder_column";
        return;
    end
    wPhysical(:, column) = wPhysical(:, column) ./ columnNorm;
    wLogical(:, column) = wLogical(:, column) ./ columnNorm;
end
leakage = norm(qPeer' * wPhysical, "fro").^2 ./ max(1, nStreams);
desiredGain = norm(qDesired' * wPhysical, "fro").^2 ./ max(1, nStreams);
leakage_dB = 10 .* log10(max(double(leakage), realmin));
gain_dB = 10 .* log10(max(double(desiredGain), realmin));
ok = isfinite(leakage_dB) && isfinite(gain_dB);
reason = "ok";
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

function design = localEmptyDesign(direction, threshold_dB, minimumDesiredGain_dB)
design = struct( ...
    "ContractVersion", "MeasuredMUMIMOPairDesign/v2", ...
    "Direction", char(direction), ...
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
    "Member1PrecoderLogicalPorts", [], ...
    "Member2PrecoderLogicalPorts", [], ...
    "Member1PrecoderPhysical", [], ...
    "Member2PrecoderPhysical", [], ...
    "Member1ReceiveCombiner", [], ...
    "Member2ReceiveCombiner", [], ...
    "Member1MatrixSHA256", "", ...
    "Member2MatrixSHA256", "");
end
