function cfgOut = applyPHYGrantToConfig(cfgIn, phyGrant)
%APPLYPHYGRANTTOCONFIG Project frozen PHYGrant dimensions into runtime cfg.
% Keep this file ASCII-only.

cfgOut = cfgIn;
if ~(isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)))
    return;
end

sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, "apply_phygrant_to_config");

direction = upper(string(sixgr.util.structGet(phyGrant, "Direction", "DL")));
if direction == "UL"
    root = "phy.pusch";
else
    root = "phy.pdsch";
end

ant = phyGrant.AntennaArchitecture;
ra = phyGrant.ResourceAllocation;
cl = phyGrant.CodingLayout;
prec = phyGrant.PrecodingState;
normalizationConvention = lower(strtrim(string(sixgr.util.structGet( ...
    prec, "NormalizationConvention", ""))));
if strlength(normalizationConvention) > 0 && ...
        ~any(normalizationConvention == ["unit_frobenius","semi_unitary", ...
        "explicit_no_normalization"])
    error("sixgr:mimo:PrecoderNormalizationConventionUnsupported", ...
        "Frozen %s grant contains unsupported precoder normalization convention '%s'.", ...
        char(direction), char(normalizationConvention));
end

numWaveformColumns = max(1, round(double(ant.NumWaveformColumns)));
numRxAntennas = max(1, round(double(ant.NumRxAntennas)));
numLogicalPorts = max(1, round(double(ant.NumLogicalPorts)));
numLayers = max(1, round(double(ant.NumLayers)));

cfgOut = sixgr.util.structSet(cfgOut, root + ".numLayers", numLayers);
cfgOut = sixgr.util.structSet(cfgOut, root + ".nLayers", numLayers);
cfgOut = sixgr.util.structSet(cfgOut, root + ".modulation", char(string(cl.Modulation)));
if isfinite(double(cl.TargetCodeRate)) && double(cl.TargetCodeRate) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".codeRate", double(cl.TargetCodeRate));
end
if isfinite(double(cl.MCSIndex))
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsIndex", double(cl.MCSIndex));
end
cfgOut = sixgr.util.structSet(cfgOut, root + ".prbSet", double(ra.PRBSet(:).'));
cfgOut = sixgr.util.structSet(cfgOut, root + ".nPRB", numel(double(ra.PRBSet(:))));
cfgOut = sixgr.util.structSet(cfgOut, root + ".symbolAllocation", double(ra.SymbolAllocation(:).'));
dmrsPortSet = double(sixgr.util.structGet(cl, "DMRSPortSet", []));
if ~isempty(dmrsPortSet)
    % Keep the scenario-wide availablePortSet intact for scheduling.  A
    % frozen grant carries the active subset selected for this one
    % transmission, which must outrank that pool during exact replay.
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.scheduledPortSet", ...
        double(dmrsPortSet(:).'));
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.portSet", ...
        double(dmrsPortSet(:).'));
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.DMRSPortSet", ...
        double(dmrsPortSet(:).'));
end
ptrsEnabled = logical(sixgr.util.structGet(cl, "PTRSEnabled", ...
    sixgr.util.structGet(cfgOut, root + ".enablePTRS", false)));
ptrsPortSet = double(sixgr.util.structGet(cl, "PTRSPortSet", []));
cfgOut = sixgr.util.structSet(cfgOut, root + ".enablePTRS", ptrsEnabled);
if ptrsEnabled
    if isempty(ptrsPortSet)
        error("sixgr:phy:grant:MissingFrozenPTRSPortSet", ...
            "A frozen PT-RS-enabled %s PHYGrant requires PTRSPortSet.", ...
            char(direction));
    end
    cfgOut = sixgr.util.structSet(cfgOut, root + ".ptrs.portSet", ...
        double(ptrsPortSet(:).'));
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.nTxAnt", numWaveformColumns);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nRxAnt", numRxAntennas);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nTxAnt", numWaveformColumns);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nRxAnt", numRxAntennas);

if direction == "DL"
    logicalMatrix = sixgr.util.structGet(prec, "MatrixLogicalPorts", prec.Matrix);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precoding.matrix", double(logicalMatrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.precodingMatrix", double(logicalMatrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.W", double(logicalMatrix));
    if strlength(normalizationConvention) > 0
        % The scheduler may select a measured MU precoder whose immutable
        % power convention is more specific than the scenario's default.
        % Replay the convention with the matrix; validating the matrix under
        % a different convention changes the meaning of the frozen grant.
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.precoding.normalizationConvention", ...
            char(normalizationConvention));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.precoderNormalizationConvention", ...
            char(normalizationConvention));
    end
    % A frozen PHYGrant is immutable execution authority. Re-normalizing
    % its logical matrix at the transmitter changes the selected physical
    % matrix digest and invalidates MU interference predictions.
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.normalizePrecodingMatrix", false);
    frozenHybridMatrix = double(sixgr.util.structGet(prec, ...
        "HybridElementToPortMatrix", []));
    if logical(sixgr.util.structGet(prec, "HybridElementDomainApplied", false))
        if isempty(frozenHybridMatrix)
            error("sixgr:phy:grant:MissingFrozenHybridMatrix", ...
                "Element-domain PDSCH replay requires the exact frozen hybrid RF matrix.");
        end
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridElementToPortMatrix", frozenHybridMatrix);
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridElementToPortMatrixSHA256", ...
            char(string(sixgr.util.structGet(prec, ...
            "HybridElementToPortMatrixSHA256", ...
            sixgr.phy.mimo.MatrixContract.digest(frozenHybridMatrix)))));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridRFDesignPolicy", char(string(sixgr.util.structGet( ...
            prec, "HybridRFDesignPolicy", "fixed_configured_matrix"))));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pdsch.hybridRFDesignStatus", char(string(sixgr.util.structGet( ...
            prec, "HybridRFDesignStatus", ""))));
    end
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.selectedPrecoderSHA256", ...
        char(string(sixgr.util.structGet(prec, "SelectedMatrixSHA256", ...
        sixgr.phy.mimo.MatrixContract.digest(double(prec.Matrix))))));
    % CSI-RS owns an independent logical-port resource configured by the
    % scenario. A PDSCH grant freezes data-layer and antenna-element
    % dimensions only; projecting its 64 element-domain waveform columns
    % into phy.csirs.nPorts corrupts the CSI-RS row contract.
else
    logicalMatrix = double(sixgr.util.structGet(prec, ...
        "MatrixLogicalPorts", prec.Matrix));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.NumAntennaPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.numPorts", numLogicalPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nPorts", numLogicalPorts);
    % Non-codebook PUSCH still has an immutable layer-to-logical-port
    % mapping.  Replay that mapping explicitly; regenerating an identity
    % here changes both its power convention and its spatial signature.
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.precoding.matrix", logicalMatrix);
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.precodingMatrix", logicalMatrix);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.W", logicalMatrix);
    transmissionScheme = strtrim(string(sixgr.util.structGet(prec, ...
        "TransmissionScheme", "")));
    if strlength(transmissionScheme) > 0
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.TransmissionScheme", char(transmissionScheme));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.transmissionScheme", char(transmissionScheme));
    end
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.transformPrecoding", ...
        logical(sixgr.util.structGet(prec, "TransformPrecodingApplied", ...
        sixgr.util.structGet(cfgOut, "phy.pusch.transformPrecoding", false))));
    hoppingMode = lower(strtrim(string(sixgr.util.structGet(ra, ...
        "FrequencyHoppingMode", "none"))));
    if ~any(hoppingMode == ["none","intra_slot","inter_slot"])
        error("sixgr:phy:grant:InvalidFrozenPUSCHFrequencyHoppingMode", ...
            "Frozen UL PHYGrant contains unsupported frequency-hopping mode '%s'.", ...
            char(hoppingMode));
    end
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.frequencyHopping.mode", char(hoppingMode));
    if hoppingMode ~= "none"
        secondHop = double(sixgr.util.structGet(ra, ...
            "SecondHopStartPRB", NaN));
        if ~(isscalar(secondHop) && isfinite(secondHop) && ...
                secondHop == fix(secondHop) && secondHop >= 0)
            error("sixgr:phy:grant:MissingFrozenPUSCHSecondHopStartPRB", ...
                "Enabled frozen PUSCH hopping requires SecondHopStartPRB.");
        end
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.frequencyHopping.secondHopStartPRB", secondHop);
    end
    frozenTPMI = double(sixgr.util.structGet(prec, "TPMI", ...
        sixgr.util.structGet(prec, "PMI", NaN)));
    if isscalar(frozenTPMI) && isfinite(frozenTPMI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.TPMI", frozenTPMI);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.PMI", frozenTPMI);
    end
    frozenCodebookMode = strtrim(string(sixgr.util.structGet(prec, ...
        "CodebookMode", "")));
    if strlength(frozenCodebookMode) > 0
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.CodebookType", char(frozenCodebookMode));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.codebookType", char(frozenCodebookMode));
    end
    if strlength(normalizationConvention) > 0
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.precoding.normalizationConvention", ...
            char(normalizationConvention));
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.precoderNormalizationConvention", ...
            char(normalizationConvention));
    end
    frozenHybridMatrix = double(sixgr.util.structGet(prec, ...
        "HybridElementToPortMatrix", []));
    if logical(sixgr.util.structGet(prec, "HybridElementDomainApplied", false))
        if isempty(frozenHybridMatrix)
            error("sixgr:phy:grant:MissingFrozenHybridMatrix", ...
                "Element-domain PUSCH replay requires the exact frozen hybrid RF matrix.");
        end
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.hybridElementToPortMatrix", frozenHybridMatrix);
        cfgOut = sixgr.util.structSet(cfgOut, ...
            "phy.pusch.hybridElementToPortMatrixSHA256", ...
            char(string(sixgr.util.structGet(prec, ...
            "HybridElementToPortMatrixSHA256", ...
            sixgr.phy.mimo.MatrixContract.digest(frozenHybridMatrix)))));
    end
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pusch.selectedPrecoderSHA256", ...
        char(string(sixgr.util.structGet(prec, "SelectedMatrixSHA256", ...
        sixgr.phy.mimo.MatrixContract.digest(logicalMatrix)))));
    cfgOut = sixgr.util.structSet(cfgOut, "channel.ul.nTxAnt", numWaveformColumns);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.ul.nTxAnt", numWaveformColumns);
    cfgOut = sixgr.util.structSet(cfgOut, "channel.ul.nRxAnt", numRxAntennas);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.ul.nRxAnt", numRxAntennas);
end

cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.enabled", true);
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.contextId", char(string(phyGrant.GrantContextId)));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.direction", char(direction));
% PMI belongs to the frozen codebook coordinate system, not to an index
% inferred later from the physically composed element-domain matrix.
pmiBasis = "unavailable_no_codebook_pmi";
if isfinite(double(sixgr.util.structGet(prec,"PMI",NaN)))
    pmiBasis = lower(direction) + "_logical_port_basis";
    if direction=="DL", pmiBasis="pdsch_logical_port_basis"; end
    if direction=="UL", pmiBasis="pusch_logical_port_basis"; end
    if logical(sixgr.util.structGet(prec,"CSIRSPortBasisApplied",false))
        pmiBasis = "csi_rs_port_basis";
    end
end
identity = struct('PMIBasis',pmiBasis);
for identityField = ["PMI","PMIType","CodebookMode","BeamIndices", ...
        "CSIResourceIndex","PMICodebookMatrixCSIPortsSHA256", ...
        "CSIRSPortToElementMatrixSHA256","ComposedElementMatrixSHA256"]
    if isfield(prec,identityField)
        identity.(identityField) = prec.(identityField);
    end
end
cfgOut = sixgr.util.structSet(cfgOut,"phy.canonicalGrant.precoderIdentity",identity);
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.spatialSignature", ...
    double(prec.Matrix));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.spatialSignatureSHA256", ...
    char(sixgr.phy.mimo.MatrixContract.digest(double(prec.Matrix))));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.spatialSignatureSource", ...
    "executed_frozen_phy_grant_precoding_matrix");
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.precoderSource", ...
    char(string(sixgr.util.structGet(prec, "Source", ...
    "executed_frozen_phy_grant_precoding_matrix"))));
cfgOut = sixgr.util.structSet(cfgOut, "phy.canonicalGrant.precodingApplicationStage", ...
    char(string(sixgr.util.structGet(prec, "ApplicationStage", ...
    "nrPDSCHPrecode_before_RE_mapping"))));
if strlength(normalizationConvention) > 0
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.canonicalGrant.precoderNormalizationConvention", ...
        char(normalizationConvention));
end
end
