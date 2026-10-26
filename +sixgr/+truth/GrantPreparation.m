classdef GrantPreparation
%GRANTPREPARATION Canonical grant/TB/HARQ preparation used by production and tests.
% This is the extracted production owner, not a reduced fixture implementation.
% Receiver-derived control and shared-waveform queue admission remain separate.
methods (Static)
function job = buildJob(cfg, direction, snr_dB, frameIdx, laStateIn, trialContext)
userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
userMeta.RuntimeCurrentDirection = upper(string(direction));
cfg = sixgr.util.structSet(cfg, "lls6g.userContext", userMeta);
if nargin < 6 || ~isstruct(trialContext)
    trialContext = struct();
end
[trialContext, ~] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfg, upper(string(direction)), trialContext);
cfg = sixgr.truth.GrantPreparation.applyHARQGrantContext(cfg, upper(string(direction)), sixgr.util.structGet(trialContext, "GrantSnapshot", struct()));
cfg = sixgr.truth.GrantPreparation.applyExecutionGrantSnapshot(cfg, upper(string(direction)), sixgr.util.structGet(trialContext, "GrantSnapshot", struct()));
job = sixgr.truth.buildGrantPHYJob(cfg, upper(string(direction)), snr_dB, frameIdx, laStateIn, trialContext);
capsule=sixgr.util.structGet(cfg,'lls6g.runtime.PreparedDataPopulation',struct());
if ~isempty(fieldnames(capsule))
    assert(string(capsule.GrantContextID)==string(sixgr.util.structGet(job.PHYGrant,'GrantContextId',"")), ...
        'sixgr:truth:PreparedPopulationGrantChanged', ...
        'Final job preparation cannot silently replace the original population''s frozen grant identity.');
    logicalID=string(sixgr.util.structGet(capsule,'LogicalGrantContextID',""));
    assert(strlength(logicalID)==0 || logicalID==string(job.GrantContextId), ...
        'sixgr:truth:PreparedPopulationGrantChanged', ...
        'Final job preparation cannot replace the separately retained logical grant identity.');
end
end

function batch = prepareCoupledGrantBatch(runtimeState, cfg, multiUser, userCfg, grants, direction, snr_dB, absoluteFrame, laStates, allGrants, grantIndexOffset, resolvedGrantCache)
direction = upper(string(direction));
if nargin < 10 || ~(isstruct(allGrants) && ~isempty(allGrants))
    allGrants = grants;
end
if nargin < 11 || ~(isnumeric(grantIndexOffset) && isscalar(grantIndexOffset) && isfinite(grantIndexOffset))
    grantIndexOffset = 0;
end
if nargin < 12 || ~isstruct(resolvedGrantCache)
    resolvedGrantCache = struct([]);
end
batch = repmat(struct( ...
    "Valid", false, ...
    "UEIndex", NaN, ...
    "LinkSNR_dB", NaN, ...
    "RuntimeReportedLinkQuality_dB", NaN, ...
    "Cfg", struct(), ...
    "GrantSnapshot", struct(), ...
    "GrantRow", table(), ...
    "TrialContext", struct(), ...
    "GrantIndex", NaN, ...
    "LinkAdaptationStateIn", struct(), ...
    "TrialTable", table(), ...
    "ConstellationTable", table(), ...
    "WaveformPreviewTable", table(), ...
    "LinkAdaptationState", struct(), ...
    "Result", struct()), 0, 1);
if ~(isstruct(grants) && ~isempty(grants))
    return;
end
for gi = 1:numel(grants)
    grant = grants(gi);
    absoluteGrantIndex = double(grantIndexOffset + gi);
    ueIdx = sixgr.truth.GrantPreparation.resolveGrantUEIndex(grant, multiUser);
    if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= numel(userCfg))
        continue;
    end
    tempState = sixgr.truth.CoupledTruthRuntime.setCurrentUE(runtimeState, ueIdx, direction);
    [cfgDir, tempState] = sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(userCfg{ueIdx}, tempState, ueIdx, direction);
    if isfield(runtimeState,'SharedWaveformStream')
        % A future UL waveform is prepared using knowledge available now.
        % Only its resource/config calendar changes; no future state view,
        % traffic, feedback processing or channel execution is performed.
        cfgDir=sixgr.truth.bindSharedDataOccasion(cfgDir,grant.Slot,grant.Frame, ...
            runtimeState.SharedWaveformStream.SampleRateHz);
    end
    [tempState, trialContext, grantRow] = sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(tempState, cfgDir, ueIdx, direction, grant);
    cacheEntry = sixgr.truth.GrantPreparation.findCoupledResolvedGrantCacheEntry(resolvedGrantCache, absoluteGrantIndex, ueIdx);
    if isstruct(cacheEntry) && logical(sixgr.util.structGet(cacheEntry, "Valid", false))
        liveGrant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
        grantResolved = sixgr.truth.GrantPreparation.mergeLiveRuntimeGrantFields( ...
            sixgr.util.structGet(cacheEntry, "GrantSnapshot", struct()), liveGrant);
        trialContext.GrantSnapshot = grantResolved;
        trialContext.TransportBlockBits = int8(sixgr.util.structGet(cacheEntry, "TransportBlockBits", int8([])));
        rvCached = sixgr.util.structGet(cacheEntry, "RV", []);
        if ~isempty(rvCached)
            trialContext.RV = rvCached;
        end
        % UCI-on-PUSCH is occasion-local runtime state.  It must come from
        % the live grant merged above, never from the immutable TB cache.
        % In particular, a retransmission must not replay feedback that was
        % already consumed on the original UL occasion.
        expectedUCI = sixgr.util.structGet(grantResolved, ...
            "ExpectedUCIBits", int8([]));
        trialContext.ExpectedUCIBits = int8(expectedUCI(:));
        trialContext.HARQContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
        trialContext.HARQContext.GrantSnapshot = grantResolved;
        if ~isempty(rvCached)
            trialContext.HARQContext.RV = double(rvCached);
        end
        [trialContext, resolvedBits] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfgDir, direction, trialContext);
        grantResolved = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
    else
        [trialContext, resolvedBits] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfgDir, direction, trialContext);
        grantResolved = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
    end
    [cfgDir, grantResolved] = sixgr.rf.bindScheduledGrantPowerBudget( ...
        cfgDir, direction, grantResolved, allGrants);
    trialContext.GrantSnapshot = grantResolved;
    trialContext.HARQContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
    trialContext.HARQContext.GrantSnapshot = grantResolved;
    grantRow = sixgr.truth.GrantPreparation.refreshGrantRowFromGrant(grantRow, grantResolved, resolvedBits);
    if ~(isfinite(resolvedBits) && resolvedBits > 0)
        continue;
    end
    runtimeReportedLinkQuality_dB = sixgr.truth.resolveDeliveredLinkQuality(tempState, ueIdx, direction);
    trialContext.RuntimeReportedLinkQuality_dB = double(runtimeReportedLinkQuality_dB);
    trialContext.ConfiguredReplaySNR_dB = double(snr_dB);
    plan = struct( ...
        "Valid", true, ...
        "UEIndex", double(ueIdx), ...
        "LinkSNR_dB", double(snr_dB), ...
        "RuntimeReportedLinkQuality_dB", double(runtimeReportedLinkQuality_dB), ...
        "Cfg", cfgDir, ...
        "GrantSnapshot", grantResolved, ...
        "GrantRow", grantRow, ...
        "TrialContext", trialContext, ...
        "GrantIndex", double(absoluteGrantIndex), ...
        "LinkAdaptationStateIn", laStates{ueIdx}, ...
        "TrialTable", table(), ...
        "ConstellationTable", table(), ...
        "WaveformPreviewTable", table(), ...
        "LinkAdaptationState", laStates{ueIdx}, ...
        "Result", struct());
    batch(end + 1, 1) = plan; %#ok<AGROW>
end
end

function ueIdx = resolveGrantUEIndex(grant, multiUser)
ueIdx=sixgr.truth.CoupledRadioIdentity.grantUEIndex(grant,double(multiUser.NumUsers));
end

function [cfgU, state] = applyCoupledRuntimeUserContext(cfgIn, state, ueIdx, direction)
[cfgU, state] = sixgr.truth.CoupledTruthRuntime.applyUserContext(cfgIn, state, ueIdx, direction);
end

function entry = findCoupledResolvedGrantCacheEntry(cache, grantIndex, ueIdx)
entry = struct("Valid", false);
if ~(isstruct(cache) && ~isempty(cache))
    return;
end
grantIndex = double(grantIndex);
ueIdx = double(ueIdx);
for ci = 1:numel(cache)
    if logical(sixgr.util.structGet(cache(ci), "Valid", false)) && ...
            double(sixgr.util.structGet(cache(ci), "GrantIndex", NaN)) == grantIndex && ...
            double(sixgr.util.structGet(cache(ci), "UEIndex", NaN)) == ueIdx
        entry = cache(ci);
        return;
    end
end
end

function grantOut = mergeLiveRuntimeGrantFields(grantCached, grantLive)
grantOut = sixgr.truth.mergeCachedGrantWithLiveRuntime( ...
    grantCached, grantLive);
end

function [trialContext, resolvedBits] = finalizeGrantTrialContext(cfgIn, direction, trialContext)
resolvedBits = NaN;
if ~(isstruct(trialContext) && isstruct(sixgr.util.structGet(trialContext, "GrantSnapshot", struct())))
    return;
end
grant = sixgr.util.structGet(trialContext, "GrantSnapshot", struct());
direction = upper(string(direction));
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
isRetx = sixgr.phy.grant.isExplicitHARQRetransmission( ...
    grant, sixgr.util.structGet(grant, "PHYGrant", struct()), harqContext);
queueBitsUpper = 8 * floor(max(0, double(sixgr.util.structGet(grant, "BufferBytesBefore", sixgr.util.structGet(grant, "TBSBytes", 0)))));
if isRetx
    replayBits = double(numel(sixgr.util.structGet(trialContext, "TransportBlockBits", [])));
    grant = sixgr.truth.GrantPreparation.resolveRetransmissionGrantSnapshot(cfgIn, direction, grant, replayBits, trialContext);
else
    grant = sixgr.truth.GrantPreparation.resolveStrictGrantSnapshot(cfgIn, direction, grant, queueBitsUpper);
    % New-data scheduling is finalized exactly once here, after strict TBS,
    % resource, layer and precoder hydration.  Carry that immutable grant
    % through the cache/job boundary.  Refreezing later from a transient
    % per-user cfg can silently replace the scheduler's measured MU-MIMO RF
    % matrix with the configured base matrix.
    cfgFreeze = sixgr.truth.GrantPreparation.applyExecutionGrantSnapshot(cfgIn, direction, grant);
    phyGrant = sixgr.phy.grant.freezePHYGrant(cfgFreeze, direction, grant, ...
        "Frame", double(sixgr.util.structGet(grant, "Frame", NaN)), ...
        "Slot", double(sixgr.util.structGet(grant, "Slot", NaN)), ...
        "HARQContext", sixgr.util.structGet(trialContext, "HARQContext", struct()));
    grant.PHYGrant = phyGrant;
    grant.PHYGrantContextId = char(string(phyGrant.GrantContextId));
    trialContext.PHYGrant = phyGrant;
end
trialContext.GrantSnapshot = grant;
resolvedBits = double(sixgr.util.structGet(grant, "TransportBlockSize", sixgr.util.structGet(grant, "TBSBits", NaN)));
if ~isRetx
    needNewTB = isempty(sixgr.util.structGet(trialContext, "TransportBlockBits", [])) || ...
        ~(isfinite(resolvedBits) && resolvedBits > 0 && numel(trialContext.TransportBlockBits) == round(resolvedBits));
    if needNewTB && isfinite(resolvedBits) && resolvedBits > 0
        trialContext.TransportBlockBits = sixgr.truth.GrantPreparation.generateGrantTransportBlockBits(cfgIn, grant, direction, round(resolvedBits));
    end
end
end

function grant = resolveRetransmissionGrantSnapshot(cfgIn, direction, grant, replayBits, trialContext)
direction = upper(string(direction));
if nargin < 5 || ~isstruct(trialContext)
    trialContext = struct();
end
harqContext = sixgr.util.structGet(trialContext, "HARQContext", struct());
tbContext = sixgr.truth.GrantPreparation.resolveGrantHARQTBContext(grant, harqContext);
if isstruct(tbContext) && ~isempty(fieldnames(tbContext))
    grant.HARQTBContext = tbContext;
end
hasCarrier = ~isempty(sixgr.util.structGet(grant, "CarrierConfig", []));
if direction == "UL"
    hasDirectionConfig = ~isempty(sixgr.util.structGet(grant, "PUSCHConfig", []));
else
    hasDirectionConfig = ~isempty(sixgr.util.structGet(grant, "PDSCHConfig", []));
end
if ~(hasCarrier && hasDirectionConfig)
    grant = sixgr.truth.GrantPreparation.hydrateGrantSnapshot(cfgIn, direction, grant);
end
resolvedTBSBits = double(sixgr.util.structGet(tbContext, "TBSBits", NaN));
if ~(isfinite(resolvedTBSBits) && resolvedTBSBits > 0)
    resolvedTBSBits = double(replayBits);
elseif isfinite(replayBits) && replayBits > 0 && round(resolvedTBSBits) ~= round(replayBits)
    error("sixgr:truth:HARQReplayTBSMismatch", ...
        "%s HARQ replay context TBSBits=%d does not match stored TB bits=%d.", ...
        char(direction), round(resolvedTBSBits), round(replayBits));
end
harq = sixgr.util.structGet(grant, "HARQ", struct());
if ~isstruct(harq)
    harq = struct();
end
harq.IsRetransmission = true;
harq.NDI = logical(sixgr.util.structGet(harqContext, "NDI", sixgr.util.structGet(tbContext, "NDI", sixgr.util.structGet(harq, "NDI", false))));
harq.NDIEpoch = double(sixgr.util.structGet(harqContext, "NDIEpoch", sixgr.util.structGet(tbContext, "NDIEpoch", sixgr.util.structGet(harq, "NDIEpoch", NaN))));
harq.HarqID = double(sixgr.util.structGet(harqContext, "HarqID", sixgr.util.structGet(tbContext, "HARQProcessId", sixgr.util.structGet(harq, "HarqID", NaN))));
harq.HARQProcess = double(sixgr.util.structGet(harqContext, "HARQProcess", sixgr.util.structGet(tbContext, "HARQProcessId", sixgr.util.structGet(harq, "HARQProcess", harq.HarqID))));
harq.RV = double(sixgr.util.structGet(harqContext, "RV", sixgr.util.structGet(harq, "RV", NaN)));
grant.HARQ = harq;
grant.IsRetransmission = true;
grant.HARQSoftCombiningEvidenceAvailable = logical(sixgr.util.structGet(harqContext, "SoftCombiningEvidenceAvailable", ...
    sixgr.util.structGet(harqContext, "PreviousCombinedLLRAvailable", false)));
if isfinite(resolvedTBSBits) && resolvedTBSBits > 0
    grant.TransportBlockSize = double(resolvedTBSBits);
    grant.TBSBits = double(resolvedTBSBits);
    grant.TBSBytes = floor(double(resolvedTBSBits) / 8);
    grant.ScheduledTransportBlockSize = double(resolvedTBSBits);
end
end

function tbContext = resolveGrantHARQTBContext(grant, harqContext)
tbContext = struct();
if nargin < 1 || ~isstruct(grant)
    grant = struct();
end
if nargin < 2 || ~isstruct(harqContext)
    harqContext = struct();
end
candidates = { ...
    sixgr.util.structGet(harqContext, "TransportBlockContext", struct()), ...
    sixgr.util.structGet(harqContext, "HARQTBContext", struct()), ...
    sixgr.util.structGet(grant, "HARQTBContext", struct())};
for i = 1:numel(candidates)
    candidate = candidates{i};
    if isstruct(candidate) && ~isempty(fieldnames(candidate))
        tbContext = candidate;
        return;
    end
end
end

function grant = hydrateGrantSnapshot(cfgIn, direction, grant)
originalDLPrecodingMatrix = [];
if upper(string(direction)) == "DL"
    % The scheduler grant is the sole spatial authority once its measured
    % MU design has been finalized.  Project its logical-port, RF and
    % element-domain matrices before any allocator or precoder consumer is
    % called; a prepared per-user 64x2 beam must not replace a frozen 64x4
    % shared-cell architecture.
    cfgIn = sixgr.truth.GrantPreparation.applyExecutionGrantSnapshot(cfgIn, "DL", grant);
    sixgr.truth.GrantPreparation.assertDLPrecodingConfigMatchesGrant(cfgIn, grant, "after_execution_grant_snapshot");
    originalDLPrecodingMatrix = sixgr.util.structGet(cfgIn, "phy.pdsch.precoding.matrix", ...
        sixgr.util.structGet(cfgIn, "phy.pdsch.precodingMatrix", ...
        sixgr.util.structGet(cfgIn, "phy.pdsch.W", [])));
end
cfgGrant = sixgr.truth.GrantPreparation.applyHARQGrantContext(cfgIn, direction, grant);
direction = upper(string(direction));
if direction == "DL"
    sixgr.truth.GrantPreparation.assertDLPrecodingConfigMatchesGrant(cfgGrant, grant, "after_harq_context");
end
cfgGrant = sixgr.truth.GrantPreparation.prepareGrantReplayExecutionConfig(cfgGrant, direction, grant);
if direction == "DL"
    sixgr.truth.GrantPreparation.assertDLPrecodingConfigMatchesGrant(cfgGrant, grant, "after_replay_config");
end
if direction == "UL"
    replayPRBSet = sixgr.truth.GrantPreparation.grantReplayPRBSet(cfgGrant, grant);
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfgGrant);
    [~, info, pusch] = sixgr.phy.grid.allocPUSCHTransport(carrier, cfgGrant, ...
        "PRBSet", replayPRBSet, ...
        "SymbolAllocation", sixgr.util.structGet(grant, "SymbolAllocation", []), ...
        "Modulation", char(string(sixgr.util.structGet(grant, "Modulation", "QPSK"))), ...
        "NumLayers", double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", 1))));
    nrePerPRB = sixgr.truth.GrantPreparation.extractGrantNREPerPRB(info, numel(pusch.PRBSet), char(string(info.Modulation)), double(pusch.NumLayers));
    xOverhead = double(sixgr.util.structGet(grant, "TBSInputXOverhead", ...
        sixgr.util.structGet(grant, "XOverhead", ...
        sixgr.util.structGet(cfgGrant, "phy.pusch.xOverhead", 0))));
    targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", ...
        sixgr.util.structGet(cfgGrant, "phy.pusch.codeRate", 0.5)));
    if isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0 && ~isempty(pusch.PRBSet)
        tbsBits = double(nrTBS(char(info.Modulation), double(pusch.NumLayers), double(numel(pusch.PRBSet)), double(nrePerPRB), ...
            targetCodeRate, double(xOverhead)));
        grant.GrantPHYDataStatus = "ok";
    else
        tbsBits = 0;
        grant.GrantPHYDataStatus = "no_data_re";
    end
    grant.CarrierConfig = carrier;
    grant.PUSCHConfig = pusch;
    grant.TransformPrecoding = logical(sixgr.util.structGet(cfgGrant, "phy.pusch.transformPrecoding", false));
    grant.XOverhead = xOverhead;
    grant.NREPerPRB = double(nrePerPRB);
    grant.TBSInputModulation = char(string(info.Modulation));
    grant.TBSInputNumLayers = double(pusch.NumLayers);
    grant.TBSInputNPRB = double(numel(pusch.PRBSet));
    grant.TBSInputNREPerPRB = double(nrePerPRB);
    grant.TBSInputTargetCodeRate = targetCodeRate;
    grant.TBSInputXOverhead = double(xOverhead);
    grant.TBSInputSource = "hydrated_grant_exact_re_accounting";
    grant.NumTxAnt = double(sixgr.phy.ul.resolveULDirectionalAntennaCount(cfgGrant, "tx", NaN));
    grant.ReplayPRBOffset = double(sixgr.util.structGet(cfgGrant, "system.waveform.replayPRBOffset", 0));
    grant.ReplayGridMode = char(string(sixgr.util.structGet(cfgGrant, "system.waveform.replayGridMode", "")));
else
    rawPrecodingMatrix = originalDLPrecodingMatrix;
    replayPRBSet = sixgr.truth.GrantPreparation.grantReplayPRBSet(cfgGrant, grant);
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfgGrant);
    [~, info, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfgGrant, ...
        "PRBSet", replayPRBSet, ...
        "SymbolAllocation", sixgr.util.structGet(grant, "SymbolAllocation", []), ...
        "Modulation", char(string(sixgr.util.structGet(grant, "Modulation", "QPSK"))), ...
        "NumLayers", double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", 1))));
    nrePerPRB = sixgr.truth.GrantPreparation.extractGrantNREPerPRB(info, numel(pdsch.PRBSet), char(string(pdsch.Modulation)), double(pdsch.NumLayers));
    xOverhead = double(sixgr.util.structGet(grant, "TBSInputXOverhead", ...
        sixgr.util.structGet(grant, "XOverhead", ...
        sixgr.util.structGet(cfgGrant, "phy.pdsch.xOverhead", 0))));
    targetCodeRate = double(sixgr.util.structGet(grant, "TargetCodeRate", ...
        sixgr.util.structGet(cfgGrant, "phy.pdsch.codeRate", 0.5)));
    if isfinite(double(nrePerPRB)) && double(nrePerPRB) > 0 && ~isempty(pdsch.PRBSet)
        tbsBits = double(nrTBS(char(pdsch.Modulation), double(pdsch.NumLayers), double(numel(pdsch.PRBSet)), double(nrePerPRB), ...
            targetCodeRate, double(xOverhead)));
        grant.GrantPHYDataStatus = "ok";
    else
        tbsBits = 0;
        grant.GrantPHYDataStatus = "no_data_re";
    end
    grantSpatialContract = sixgr.phy.grant.resolveGrantSpatialContract(grant, "Direction", "DL");
    if double(pdsch.NumLayers) ~= double(grantSpatialContract.NumLayers)
        error("sixgr:truth:PDSCHGrantLayerMismatch", ...
            "Hydrated PDSCH layers=%d differ from finalized grant layers=%d (%s).", ...
            round(double(pdsch.NumLayers)), round(double(grantSpatialContract.NumLayers)), ...
            char(grantSpatialContract.AliasSummary));
    end
    cfgGrant = sixgr.truth.GrantPreparation.pruneIncompatibleDLPrecodingConfig(cfgGrant, pdsch, grant);
    sixgr.truth.GrantPreparation.assertDLPrecodingConfigMatchesGrant(cfgGrant, grant, "after_precoding_prune");
    [grant, cfgGrant] = sixgr.truth.GrantPreparation.sanitizeDLGrantFeedback(cfgGrant, pdsch, grant);
    sixgr.truth.GrantPreparation.assertDLPrecodingConfigMatchesGrant(cfgGrant, grant, "after_feedback_sanitize");
    prec = sixgr.phy.dl.resolvePDSCHPrecoding(pdsch, cfgGrant);
    selectedCSI = sixgr.util.structGet(grant,"PHYGrant.PrecodingState",struct());
    if logical(sixgr.util.structGet(selectedCSI,"CSIRSPortBasisApplied",false))
        % The runtime precoder resolves the installed explicit operator; it
        % does not decode the original CSI selection again. Carry that
        % provenance only after proving all three materialized operators
        % equal the already validated frozen selection.
        assert(isequal(double(prec.MatrixLogicalPorts),double(selectedCSI.MatrixLogicalPorts)) && ...
            isequal(double(prec.MatrixPorts),double(selectedCSI.MatrixPhysicalPorts)) && ...
            isequal(double(prec.HybridElementToPortMatrix),double(selectedCSI.HybridElementToPortMatrix)), ...
            'sixgr:truth:MaterializedSelectedCSIMismatch', ...
            'Hydrated PDSCH operator differs from the frozen selected CSI basis/PMI.');
        assert(string(sixgr.phy.mimo.MatrixContract.digest(double(prec.MatrixPorts)))== ...
                string(selectedCSI.SelectedMatrixSHA256) && ...
            string(sixgr.phy.mimo.MatrixContract.digest(double(prec.HybridElementToPortMatrix)))== ...
                string(selectedCSI.HybridElementToPortMatrixSHA256), ...
            'sixgr:truth:MaterializedSelectedCSIDigestMismatch', ...
            'Hydrated PDSCH selected CSI matrix identity is inconsistent.');
        prec.PMI=selectedCSI.PMI;
        prec.PMIType=selectedCSI.PMIType;
        prec.CodebookMode=selectedCSI.CodebookMode;
        prec.Source=selectedCSI.Source;
    end
    precActive = logical(sixgr.util.structGet(prec, "Active", false));
    precMatrix = [];
    if precActive
        precMatrix = sixgr.util.structGet(prec, "MatrixPorts", sixgr.util.structGet(prec, "MatrixNR", []));
    end
    if precActive && isempty(precMatrix)
        precMatrix = sixgr.truth.GrantPreparation.adaptDLPrecodingMatrix(rawPrecodingMatrix, double(pdsch.NumLayers));
    end
    if precActive && ~isempty(precMatrix)
        % resolvePDSCHPrecoding already owns orientation, normalization, and
        % hybrid element expansion. Re-normalizing only the physical matrix
        % here breaks its exact relationship to MatrixLogicalPorts and
        % silently changes the selected scheduler beam.
        if ndims(precMatrix) > 2 && size(precMatrix, 3) == 1
            precMatrix = squeeze(precMatrix);
        end
        if ~isnumeric(precMatrix) || ~ismatrix(precMatrix) || ...
                size(precMatrix, 2) ~= double(pdsch.NumLayers) || ...
                size(precMatrix, 1) < double(pdsch.NumLayers) || ...
                any(~isfinite(real(precMatrix(:)))) || ...
                any(~isfinite(imag(precMatrix(:))))
            error("sixgr:truth:BadGrantDLPrecodingMatrix", ...
                "DL grant hydration received an invalid resolved %d-layer precoder.", ...
                round(double(pdsch.NumLayers)));
        end
        precMatrix = double(precMatrix);
    end
    numTxAnt = sixgr.truth.GrantPreparation.resolveDLPDSCHLogicalPortCount(cfgGrant, grant, double(pdsch.NumLayers));
    matrixPorts = sixgr.truth.GrantPreparation.precodingPortCount(precMatrix, double(pdsch.NumLayers));
    hybridElementDomainApplied = logical(sixgr.util.structGet(prec, ...
        "HybridElementDomainApplied", false));
    if hybridElementDomainApplied
        expectedElements = round(double(sixgr.util.structGet(prec, "NumElements", NaN)));
        logicalMatrix = sixgr.util.structGet(prec, "MatrixLogicalPorts", []);
        if ~(isfinite(expectedElements) && expectedElements >= numTxAnt && ...
                isfinite(matrixPorts) && round(matrixPorts) == expectedElements)
            error("sixgr:truth:DLHybridElementDomainShapeMismatch", ...
                ['Resolved hybrid PDSCH precoder has %d physical row(s); expected ' ...
                '%d configured gNB element row(s) for %d logical port(s).'], ...
                round(double(matrixPorts)), expectedElements, round(double(numTxAnt)));
        end
        if ~isnumeric(logicalMatrix) || ~ismatrix(logicalMatrix) || ...
                size(logicalMatrix, 1) ~= round(double(numTxAnt)) || ...
                size(logicalMatrix, 2) ~= round(double(pdsch.NumLayers))
            error("sixgr:truth:DLHybridLogicalPortShapeMismatch", ...
                ['Resolved hybrid PDSCH logical precoder is %dx%d; expected %dx%d ' ...
                'logical-port-by-layer.'], ...
                size(logicalMatrix, 1), size(logicalMatrix, 2), ...
                round(double(numTxAnt)), round(double(pdsch.NumLayers)));
        end
    elseif isfinite(matrixPorts) && matrixPorts ~= round(double(numTxAnt))
        if matrixPorts > sixgr.truth.GrantPreparation.maxNRLogicalPDSCHPorts()
            [precMatrix, precSource] = sixgr.truth.GrantPreparation.resolveDLLogicalPrecoderFromPMI(cfgGrant, grant, double(pdsch.NumLayers), numTxAnt);
            grant.PrecoderSource = char(string(precSource));
        else
            numTxAnt = max(numTxAnt, matrixPorts);
        end
    end
    if isempty(precMatrix) && isfinite(numTxAnt) && numTxAnt >= 1 && double(pdsch.NumLayers) == 1
        precMatrix = zeros(max(1, round(numTxAnt)), 1);
        precMatrix(1, 1) = 1;
    end
    matrixPorts = sixgr.truth.GrantPreparation.precodingPortCount(precMatrix, double(pdsch.NumLayers));
    if ~hybridElementDomainApplied && isfinite(matrixPorts) && matrixPorts ~= round(double(numTxAnt))
        if matrixPorts > sixgr.truth.GrantPreparation.maxNRLogicalPDSCHPorts()
            [precMatrix, precSource] = sixgr.truth.GrantPreparation.resolveDLLogicalPrecoderFromPMI(cfgGrant, grant, double(pdsch.NumLayers), numTxAnt);
            grant.PrecoderSource = char(string(precSource));
        else
            numTxAnt = max(numTxAnt, matrixPorts);
        end
    end
    grant.CarrierConfig = carrier;
    grant.PDSCHConfig = pdsch;
    grant.XOverhead = xOverhead;
    grant.NREPerPRB = double(nrePerPRB);
    grant.TBSInputModulation = char(string(pdsch.Modulation));
    grant.TBSInputNumLayers = double(pdsch.NumLayers);
    grant.TBSInputNPRB = double(numel(pdsch.PRBSet));
    grant.TBSInputNREPerPRB = double(nrePerPRB);
    grant.TBSInputTargetCodeRate = targetCodeRate;
    grant.TBSInputXOverhead = double(xOverhead);
    grant.TBSInputSource = "hydrated_grant_exact_re_accounting";
    grant.NumTxAnt = double(numTxAnt);
    grant.PrecodingMatrix = precMatrix;
    grant.PrecodingMatrixLogicalPorts = sixgr.util.structGet(prec, ...
        "MatrixLogicalPorts", precMatrix);
    % Preserve the exact RF/baseband architecture that produced the
    % element-domain matrix.  Reconstructing this later from a broader
    % scenario config can select a different RF-chain partition even when
    % the physical element and logical-port counts are unchanged.
    grant.NumElements = double(sixgr.util.structGet(prec, "NumElements", ...
        size(precMatrix, 1)));
    grant.NumRFChains = double(sixgr.util.structGet(prec, "NumRFChains", NaN));
    grant.HybridElementToPortMatrix = sixgr.util.structGet(prec, ...
        "HybridElementToPortMatrix", []);
    grant.HybridAnalogPrecoderMatrix = sixgr.util.structGet(prec, ...
        "HybridAnalogPrecoderMatrix", []);
    grant.HybridDigitalPortToRFChainMatrix = sixgr.util.structGet(prec, ...
        "HybridDigitalPortToRFChainMatrix", []);
    grant.ConfiguredBeamSelectionStrategy = char(string(sixgr.util.structGet(cfgGrant, "lls6g.userContext.BeamSelectionStrategy", ...
        sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""))));
    grant.PrecoderSource = char(string(sixgr.util.structGet(prec, "Source", sixgr.util.structGet(grant, "PrecoderSource", "none"))));
    grant.PrecodingMode = char(string(sixgr.util.structGet(prec, "Mode", sixgr.util.structGet(grant, "PrecodingMode", "siso-bypass"))));
    grant.PrecodingApplicationStage = char(string(sixgr.util.structGet(prec, "ApplicationStage", sixgr.util.structGet(grant, "PrecodingApplicationStage", "none"))));
    grant.PrecodingActive = precActive;
    grant.ExplicitBeamWeightsApplied = precActive;
    grant.BeamformingApplied = precActive;
    grant.AppliedBeamIndexSet = char(sixgr.truth.GrantPreparation.formatIndexSet(sixgr.util.structGet(prec, "BeamIndices", [])));
    grant.AppliedPrecoderPMI = double(sixgr.util.structGet(prec, "PMI", NaN));
    grant.AppliedPrecoderPMIType = char(string(sixgr.util.structGet(prec, "PMIType", "")));
    grant.AppliedPrecoderCodebookMode = char(string(sixgr.util.structGet(prec, "CodebookMode", "")));
    if ~isempty(precMatrix)
        grant.PrecodingNumPorts = double(size(precMatrix, 1));
        grant.PrecodingNumLogicalPorts = double(sixgr.util.structGet(prec, ...
            "NumLogicalPorts", double(pdsch.NumLayers)));
        grant.PrecodingNumLayers = double(size(precMatrix, 2));
        grant.PrecodingMatrixRows = double(size(precMatrix, 1));
        grant.PrecodingMatrixCols = double(size(precMatrix, 2));
    else
        grant.PrecodingNumPorts = double(sixgr.util.structGet(prec, "NumPorts", NaN));
        grant.PrecodingNumLayers = double(sixgr.util.structGet(prec, "NumLayers", NaN));
        grant.PrecodingMatrixRows = double(sixgr.util.structGet(prec, "MatrixRows", NaN));
        grant.PrecodingMatrixCols = double(sixgr.util.structGet(prec, "MatrixCols", NaN));
    end
    grant.ReplayPRBOffset = double(sixgr.util.structGet(cfgGrant, "system.waveform.replayPRBOffset", 0));
    grant.ReplayGridMode = char(string(sixgr.util.structGet(cfgGrant, "system.waveform.replayGridMode", "")));
end
grant.PRBSet = double(sixgr.util.structGet(grant, "PRBSet", []));
grant.PRBs = double(numel(grant.PRBSet));
tbContext = sixgr.truth.GrantPreparation.resolveGrantHARQTBContext(grant, struct());
if sixgr.truth.GrantPreparation.grantUsesHARQTBContext(grant, tbContext)
    currentRateMatchedBits = sixgr.truth.GrantPreparation.estimateGrantCurrentRateMatchedBits(grant);
    currentRateMatchedBitsPerCB = sixgr.truth.GrantPreparation.estimateGrantCurrentRateMatchedBitsPerCodeBlock(tbContext, currentRateMatchedBits);
    rvSequence = double(sixgr.util.structGet(tbContext, "RVSequence", ...
        sixgr.util.structGet(cfgGrant, "phy.harq.rvSequence", [0 2 3 1])));
    validationMeta = struct( ...
        "Direction", char(direction), ...
        "Grant", grant, ...
        "PHYGrant", sixgr.util.structGet(tbContext, "FrozenPHYGrant", struct()), ...
        "FrozenPHYGrant", sixgr.util.structGet(tbContext, "FrozenPHYGrant", struct()), ...
        "FrozenPDSCHorPUSCHConfig", sixgr.util.structGet(tbContext, "FrozenPDSCHorPUSCHConfig", []), ...
        "CodingLayout", sixgr.util.structGet(sixgr.util.structGet(tbContext, "FrozenPHYGrant", struct()), "CodingLayout", struct()), ...
        "PreviousContext", tbContext, ...
        "TransportBlockContext", tbContext, ...
        "IsRetransmission", true, ...
        "RateMatchedBitsTotal", double(currentRateMatchedBits), ...
        "RateMatchedBitsPerCB", double(currentRateMatchedBitsPerCB), ...
        "RV", double(sixgr.util.structGet(sixgr.util.structGet(grant, "HARQ", struct()), "RV", sixgr.util.structGet(grant, "RV", NaN))), ...
        "PreviousRV", double(sixgr.util.structGet(tbContext, "LastObservedRV", NaN)), ...
        "RVSequence", rvSequence, ...
        "SoftCombiningEvidenceAvailable", logical(sixgr.util.structGet(grant, "HARQSoftCombiningEvidenceAvailable", false)), ...
        "PreviousCombinedLLRAvailable", logical(sixgr.util.structGet(grant, "HARQSoftCombiningEvidenceAvailable", false)));
    [validatedContext, ctxStatus] = sixgr.harq.validateTBContextForTransmission(validationMeta);
    grant.HARQTBContext = validatedContext;
    grant.OriginalTBSBits = double(ctxStatus.OriginalTBSBits);
    grant.CurrentTBSBits = double(ctxStatus.CurrentTBSBits);
    grant.OriginalRateMatchedBits = double(ctxStatus.OriginalRateMatchedBits);
    grant.CurrentRateMatchedBits = double(ctxStatus.CurrentRateMatchedBits);
    grant.EffectiveInitialCodeRate = double(ctxStatus.EffectiveInitialCodeRate);
    grant.EffectiveCurrentTxCodeRate = double(ctxStatus.EffectiveCurrentTxCodeRate);
    grant.ShortIRRetx = logical(ctxStatus.ShortIRRetx);
    grant.CodeBlockLayoutHash = char(string(ctxStatus.CodeBlockLayoutHash));
    grant.HARQContextHash = char(string(ctxStatus.HARQContextHash));
    grant.HARQContextStatus = char(string(ctxStatus.HARQContextStatus));
    tbsBits = double(validatedContext.TBSBits);
end
grant.TransportBlockSize = double(tbsBits);
grant.TBSBits = double(tbsBits);
grant.TBSBytes = floor(max(double(tbsBits), 0) / 8);
end

function cfgOut = applyExecutionGrantSnapshot(cfgIn, direction, grant)
cfgOut = cfgIn;
direction = upper(string(direction));
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
if direction ~= "DL"
    return;
end

phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false))
    % The immutable PHYGrant is the sole execution authority.  In
    % particular, retain MatrixLogicalPorts here; clearing it causes the
    % transmitter to silently resolve a fresh codebook precoder and breaks
    % the measured-SRS MU spatial contract.
    cfgOut = sixgr.truth.applyFrozenDLGrantAuthority( ...
        cfgOut, grant, "sixgr.truth.GrantPreparation.applyExecutionGrantSnapshot");
    sixgr.truth.GrantPreparation.assertDLPrecodingConfigMatchesGrant( ...
        cfgOut, grant, "localApplyExecutionGrantSnapshot_frozen");
    return;
end
nLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
if isfinite(nLayers) && nLayers >= 1
    cfgOut = sixgr.truth.GrantPreparation.pruneIncompatibleDLPrecodingConfigForLayers(cfgOut, nLayers, grant);
end
expectedPorts = sixgr.truth.GrantPreparation.resolveDLPDSCHLogicalPortCount(cfgOut, grant, nLayers);
hybridMatrix = sixgr.util.structGet(grant, "HybridElementToPortMatrix", ...
    sixgr.util.structGet(grant, ...
    "PHYGrant.PrecodingState.HybridElementToPortMatrix", []));
if ~isempty(hybridMatrix)
    if ~isnumeric(hybridMatrix) || ~ismatrix(hybridMatrix) || ...
            any(~isfinite(real(hybridMatrix(:)))) || ...
            any(~isfinite(imag(hybridMatrix(:)))) || ...
            ~(isfinite(expectedPorts) && size(hybridMatrix, 2) == round(expectedPorts))
        error("sixgr:truth:ExecutionGrantHybridArchitectureMismatch", ...
            "DL execution grant hybrid matrix is %dx%d but the grant requires %d logical ports.", ...
            size(hybridMatrix, 1), size(hybridMatrix, 2), round(double(expectedPorts)));
    end
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pdsch.hybridElementToPortMatrix", double(hybridMatrix));
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pdsch.hybridElementToPortMatrixSHA256", ...
        char(sixgr.phy.mimo.MatrixContract.digest(double(hybridMatrix))));
end
grantRFChains = double(sixgr.util.structGet(grant, "NumRFChains", NaN));
if isscalar(grantRFChains) && isfinite(grantRFChains) && ...
        grantRFChains >= expectedPorts && grantRFChains == round(grantRFChains)
    cfgOut = sixgr.util.structSet(cfgOut, ...
        "phy.pdsch.numRFChains", double(grantRFChains));
end
precodingMatrix = sixgr.truth.selectGrantReplayPDSCHPrecodingMatrix(grant);
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
if sixgr.truth.GrantPreparation.grantCarriesActiveDLPrecoding(grant, precodingMatrix)
    nPorts = sixgr.truth.GrantPreparation.precodingPortCount(precodingMatrix, nLayers);
    if ~(isfinite(nPorts) && nPorts >= max(1, round(double(nLayers)))) || ...
            (isfinite(expectedPorts) && expectedPorts >= 1 && nPorts ~= round(double(expectedPorts)))
        % The grant may still carry a PMI; do not replay a dimensionally
        % invalid explicit matrix as if it were a physical precoder.
        for i = 1:numel(paths)
            cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
        end
        if isfinite(expectedPorts) && expectedPorts >= max(1, round(double(nLayers)))
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", round(double(expectedPorts)));
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", round(double(expectedPorts)));
        end
        return;
    end
    for i = 1:numel(paths)
        cfgOut = sixgr.util.structSet(cfgOut, paths(i), precodingMatrix);
    end
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", nPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", nPorts);
else
    for i = 1:numel(paths)
        cfgOut = sixgr.util.structSet(cfgOut, paths(i), []);
    end
    expectedPorts = sixgr.truth.GrantPreparation.resolveDLPDSCHLogicalPortCount(cfgOut, grant, nLayers);
    if isfinite(expectedPorts) && expectedPorts >= max(1, round(double(nLayers)))
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", round(double(expectedPorts)));
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", round(double(expectedPorts)));
    else
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", []);
    end
end
end


function assertDLPrecodingConfigMatchesGrant(cfg, grant, stage)
contract = sixgr.phy.grant.resolveGrantSpatialContract(grant, "Direction", "DL");
nLayers = double(contract.NumLayers);
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
isFrozen = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
    logical(sixgr.util.structGet(phyGrant, "IsFrozen", false));
expectedLogical = [];
expectedLogicalDigest = "";
if isFrozen
    expectedLogical = double(sixgr.util.structGet(phyGrant, ...
        "PrecodingState.MatrixLogicalPorts", []));
    if isempty(expectedLogical)
        error("sixgr:truth:FrozenDLLogicalPrecoderMissing", ...
            "Frozen DL grant at stage '%s' has no logical-port precoder.", ...
            char(string(stage)));
    end
    expectedLogicalDigest = string(sixgr.phy.mimo.MatrixContract.digest(expectedLogical));
end
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
for i = 1:numel(paths)
    W = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(W)
        if isFrozen
            error("sixgr:truth:FrozenDLLogicalPrecoderAuthorityMismatch", ...
                "Frozen DL grant at stage '%s' is missing %s.", ...
                char(string(stage)), char(paths(i)));
        end
        continue;
    end
    valid = isnumeric(W) && ismatrix(W) && ...
        ((size(W, 2) == nLayers && size(W, 1) >= nLayers) || ...
        (size(W, 1) == nLayers && size(W, 2) >= nLayers));
    if ~valid
        error("sixgr:truth:DLPrecodingConfigGrantMismatch", ...
            "DL precoding configuration diverged at stage '%s': %s is %dx%d for grant layers=%d (%s).", ...
            char(string(stage)), char(paths(i)), size(W, 1), size(W, 2), ...
            round(nLayers), char(contract.AliasSummary));
    end
    if isFrozen && string(sixgr.phy.mimo.MatrixContract.digest(double(W))) ~= expectedLogicalDigest
        error("sixgr:truth:FrozenDLLogicalPrecoderAuthorityMismatch", ...
            "Frozen DL grant at stage '%s' does not own the exact matrix in %s.", ...
            char(string(stage)), char(paths(i)));
    end
end
if isFrozen
    sixgr.truth.applyFrozenDLGrantAuthority(cfg, grant, stage);
end
end

function cfgOut = pruneIncompatibleDLPrecodingConfigForLayers(cfgIn, nLayers, grant)
cfgOut = cfgIn;
if nargin < 3 || ~isstruct(grant)
    grant = struct();
end
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false))
    % HARQ-context hydration may update coding/allocation fields, but it
    % must never renormalize or regenerate a frozen spatial decision.
    cfgOut = sixgr.truth.applyFrozenDLGrantAuthority( ...
        cfgOut, grant, "harq_context_precoding_prune");
    return;
end
nLayers = max(1, round(double(nLayers)));
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
expectedPorts = sixgr.truth.GrantPreparation.resolveDLPDSCHLogicalPortCount(cfgOut, grant, nLayers);
resolvedPorts = NaN;
for i = 1:numel(paths)
    path = paths(i);
    Wcfg = sixgr.util.structGet(cfgOut, path, []);
    if isempty(Wcfg)
        continue;
    end
    Wcfg = sixgr.truth.GrantPreparation.adaptDLPrecodingMatrix(Wcfg, nLayers);
    if isempty(Wcfg)
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    nPorts = sixgr.truth.GrantPreparation.precodingPortCount(Wcfg, nLayers);
    if ~(isfinite(nPorts) && nPorts >= nLayers) || ...
            (isfinite(expectedPorts) && expectedPorts >= 1 && nPorts ~= round(double(expectedPorts)))
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    cfgOut = sixgr.util.structSet(cfgOut, path, Wcfg);
    resolvedPorts = nPorts;
end
if isfinite(resolvedPorts) && resolvedPorts >= nLayers
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", resolvedPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", resolvedPorts);
end
end

function nPorts = resolveDLPDSCHLogicalPortCount(cfg, grant, nLayers)
nPorts = sixgr.phy.grant.resolveDLLogicalPortCount(cfg, grant, nLayers);
end

function Wout = adaptDLPrecodingMatrix(Wcfg, nLayers)
Wout = [];
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
sz = size(Wcfg);
if ndims(Wcfg) > 2 && sz(3) == 1
    Wcfg = squeeze(Wcfg);
    sz = size(Wcfg);
end
if ndims(Wcfg) > 2 || numel(sz) < 2
    return;
end
if sz(2) == nLayers && sz(1) >= nLayers
    Wout = double(Wcfg);
elseif sz(1) == nLayers && sz(2) >= nLayers
    % Accept the documented transposed convention Nlayers-by-Nports only
    % when the row count exactly matches the requested layer count.  A stale
    % Nports-by-1 rank-1 beam must not be reshaped into a rank-2 precoder.
    Wout = double(Wcfg.');
end
if ~isempty(Wout) && size(Wout, 1) < nLayers
    Wout = [];
    return;
end
if ~isempty(Wout)
    colNorm = sqrt(sum(abs(Wout).^2, 1));
    colNorm(colNorm <= eps) = 1;
    Wout = Wout ./ colNorm;
end
end

function nPorts = precodingPortCount(Wcfg, nLayers)
nPorts = 0;
if isempty(Wcfg)
    return;
end
nLayers = max(1, round(double(nLayers)));
sz = size(Wcfg);
if ndims(Wcfg) > 2 && sz(3) == 1
    Wcfg = squeeze(Wcfg);
    sz = size(Wcfg);
end
if ndims(Wcfg) > 2 || numel(sz) < 2
    return;
end
if sz(2) == nLayers
    nPorts = sz(1);
elseif sz(1) == nLayers
    nPorts = sz(2);
end
end

function tf = grantCarriesActiveDLPrecoding(grant, Wcfg)
tf = false;
if ~(isstruct(grant) && ~isempty(fieldnames(grant))) || isempty(Wcfg)
    return;
end
mode = lower(strtrim(string(sixgr.util.structGet(grant, "PrecodingMode", ""))));
source = lower(strtrim(string(sixgr.util.structGet(grant, "PrecoderSource", ""))));
stage = lower(strtrim(string(sixgr.util.structGet(grant, "PrecodingApplicationStage", ""))));
active = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
beamApplied = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
explicitApplied = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
tf = active || beamApplied || explicitApplied || ...
    (strlength(mode) > 0 && mode ~= "siso-bypass" && mode ~= "none") || ...
    (strlength(source) > 0 && source ~= "none" && source ~= "siso-bypass") || ...
    (strlength(stage) > 0 && stage ~= "none");
end

function cfgOut = applyHARQGrantContext(cfgIn, direction, grant)
cfgOut = cfgIn;
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
direction = upper(string(direction));
tbContext = sixgr.truth.GrantPreparation.resolveGrantHARQTBContext(grant, struct());
useTBContext = sixgr.truth.GrantPreparation.grantUsesHARQTBContext(grant, tbContext);
isRetransmission = sixgr.truth.GrantPreparation.grantIsRetransmission(grant);
spatialContract = sixgr.phy.grant.resolveGrantSpatialContract(grant, ...
    "Direction", direction, "TBContext", tbContext, ...
    "RequireTBContextMatch", logical(isRetransmission && useTBContext));
if direction == "UL"
    root = "phy.pusch";
else
    root = "phy.pdsch";
end
grantMCS = double(sixgr.util.structGet(grant, "MCS", sixgr.util.structGet(grant, "MCSIndex", NaN)));
grantMod = string(sixgr.util.structGet(grant, "Modulation", ""));
grantRate = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
grantLayers = double(spatialContract.NumLayers);
grantPRBs = double(sixgr.util.structGet(grant, "PRBs", numel(double(sixgr.util.structGet(grant, "PRBSet", [])))));
grantPRBSet = sixgr.util.structGet(grant, "PRBSet", []);
grantSymbolAllocation = sixgr.util.structGet(grant, "SymbolAllocation", []);
grantMappingType = string(sixgr.util.structGet(grant, "MappingType", ""));
grantTransformPrecoding = sixgr.util.structGet(grant, "TransformPrecoding", []);
grantPMI = double(sixgr.util.structGet(grant, "PMI", NaN));
grantCRI = double(sixgr.util.structGet(grant, "CRI", NaN));
grantMCSTable = string(sixgr.util.structGet(grant, "MCSTable", ""));
grantCQITable = string(sixgr.util.structGet(grant, "CQITable", ""));
grantDMRSPortSet = sixgr.truth.GrantPreparation.firstNonemptyNumeric( ...
    sixgr.util.structGet(grant, "DMRSPortSet", []), ...
    sixgr.util.structGet(grant, "PHYGrant.CodingLayout.DMRSPortSet", []));
grantPTRSEnabled = logical(sixgr.util.structGet(grant, ...
    "PHYGrant.CodingLayout.PTRSEnabled", sixgr.util.structGet(grant, ...
    "PTRSEnabled", sixgr.util.structGet(cfgIn, root + ".enablePTRS", false))));
grantPTRSPortSet = sixgr.truth.GrantPreparation.firstNonemptyNumeric( ...
    sixgr.util.structGet(grant, "PTRSPortSet", []), ...
    sixgr.util.structGet(grant, "PHYGrant.CodingLayout.PTRSPortSet", []));
if isRetransmission && useTBContext
    grantMCS = double(sixgr.util.structGet(tbContext, "OriginalMCS", grantMCS));
    grantMod = string(sixgr.util.structGet(tbContext, "OriginalModulation", grantMod));
    grantRate = double(sixgr.util.structGet(tbContext, "OriginalTargetCodeRate", grantRate));
    grantLayers = double(sixgr.util.structGet(tbContext, "OriginalNumLayers", grantLayers));
    if isempty(grantPRBSet)
        grantPRBSet = double(sixgr.util.structGet(tbContext, "OriginalPRBSet", []));
    end
    if isempty(grantSymbolAllocation)
        grantSymbolAllocation = double(sixgr.util.structGet(tbContext, "OriginalSymbolAllocation", []));
    end
    if strlength(strtrim(grantMappingType)) < 1
        grantMappingType = string(sixgr.util.structGet(tbContext, "OriginalMappingType", grantMappingType));
    end
    grantPRBs = double(numel(grantPRBSet));
end
if isfinite(grantMCS)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsIndex", grantMCS);
end
if strlength(strtrim(grantMod)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".modulation", char(grantMod));
end
if isfinite(grantRate) && grantRate > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".codeRate", grantRate);
end
if isfinite(grantLayers) && grantLayers >= 1
    cfgOut = sixgr.util.structSet(cfgOut, root + ".numLayers", grantLayers);
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nLayers", grantLayers);
end
if ~isempty(grantDMRSPortSet)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.portSet", ...
        double(grantDMRSPortSet(:).'));
    cfgOut = sixgr.util.structSet(cfgOut, root + ".dmrs.DMRSPortSet", ...
        double(grantDMRSPortSet(:).'));
end
if isfinite(grantPRBs) && grantPRBs >= 1
    cfgOut = sixgr.util.structSet(cfgOut, root + ".nPRB", grantPRBs);
end
if ~isempty(grantPRBSet)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".prbSet", grantPRBSet);
end
if ~isempty(grantSymbolAllocation)
    cfgOut = sixgr.util.structSet(cfgOut, root + ".symbolAllocation", grantSymbolAllocation);
end
if strlength(strtrim(grantMappingType)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mappingType", char(grantMappingType));
end
if ~isempty(grantTransformPrecoding) && direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, root + ".transformPrecoding", logical(grantTransformPrecoding));
end
if strlength(strtrim(grantMCSTable)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".mcsTable", char(grantMCSTable));
end
if strlength(strtrim(grantCQITable)) > 0
    cfgOut = sixgr.util.structSet(cfgOut, root + ".cqiTable", char(grantCQITable));
end
if direction == "DL"
    if isfinite(grantLayers) && grantLayers >= 1
        cfgOut = sixgr.truth.GrantPreparation.pruneIncompatibleDLPrecodingConfigForLayers(cfgOut, grantLayers, grant);
    end
    if isfinite(grantPMI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", grantPMI);
    end
    if isfinite(grantCRI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", grantCRI);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", grantCRI);
    end
elseif direction == "UL"
    if isfinite(grantPMI)
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.PMI", grantPMI);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.TPMI", grantPMI);
    end
end
cfgOut = sixgr.util.structSet(cfgOut, root + ".enablePTRS", ...
    grantPTRSEnabled);
if grantPTRSEnabled
    if isempty(grantPTRSPortSet)
        error("sixgr:truth:MissingFrozenPTRSPortSet", ...
            "PT-RS-enabled %s grant requires an exact frozen port set.", ...
            char(direction));
    end
    cfgOut = sixgr.util.structSet(cfgOut, root + ".ptrs.portSet", ...
        double(grantPTRSPortSet(:).'));
end
end

function tf = grantUsesHARQTBContext(grant, tbContext)
tf = false;
if ~(isstruct(tbContext) && ~isempty(fieldnames(tbContext)))
    return;
end
grantHarq = sixgr.util.structGet(grant, "HARQ", struct());
grantNDI = sixgr.util.structGet(grantHarq, "NDI", sixgr.util.structGet(grant, "NDI", NaN));
ctxNDI = sixgr.util.structGet(tbContext, "NDI", NaN);
ndiMatches = true;
if ~isempty(grantNDI) && ~isempty(ctxNDI) && all(isfinite(double([grantNDI ctxNDI])))
    ndiMatches = logical(grantNDI) == logical(ctxNDI);
end
tf = ndiMatches && isfinite(double(sixgr.util.structGet(tbContext, "TBSBits", NaN)));
end

function tf = grantIsRetransmission(grant)
tf = sixgr.phy.grant.isExplicitHARQRetransmission( ...
    grant, sixgr.util.structGet(grant, "PHYGrant", struct()), struct());
end

function value = firstNonemptyNumeric(varargin)
value = [];
for index = 1:nargin
    candidate = varargin{index};
    if isnumeric(candidate) && ~isempty(candidate)
        value = double(candidate);
        return;
    end
end
end

function cfgOut = prepareGrantReplayExecutionConfig(cfgIn, direction, grant)
cfgOut = cfgIn;
direction = upper(string(direction));
dataSlot = double(sixgr.util.structGet(grant,"Slot",NaN));
dataFrame = double(sixgr.util.structGet(grant,"Frame",NaN));
if ~(isscalar(dataSlot) && isfinite(dataSlot) && dataSlot>=1 && ...
        dataSlot==fix(dataSlot))
    error('sixgr:truth:MissingGrantReplayTimeline', ...
        'Truth waveform hydration requires the frozen grant absolute slot.');
end
% Execution hydration may inherit a carrier object from an earlier
% control/access occasion. Rebind the NR carrier to the frozen data grant
% before any PDSCH/PUSCH RE exclusion or TBS calculation is performed.
[cfgOut,~] = sixgr.phy.grid.applyRuntimeCarrierTimeline( ...
    cfgOut,dataSlot,dataFrame);
numLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
if ~(isfinite(numLayers) && numLayers >= 1)
    numLayers = 1;
end

txAnt = sixgr.truth.GrantPreparation.grantReplayTxAntennas(cfgOut, direction, grant, numLayers);
rxAnt = sixgr.truth.GrantPreparation.grantReplayRxAntennas(cfgOut, direction, grant, numLayers);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nTxAnt", txAnt);
cfgOut = sixgr.util.structSet(cfgOut, "phy.nRxAnt", rxAnt);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nTxAnt", txAnt);
cfgOut = sixgr.util.structSet(cfgOut, "channel.nRxAnt", rxAnt);

if direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.numLayers", numLayers);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nLayers", numLayers);
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numLayers", numLayers);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nLayers", numLayers);
end

cfgOut = sixgr.truth.GrantPreparation.alignGrantReplayCarrier(cfgOut, grant);
replayPRBSet = sixgr.truth.GrantPreparation.grantReplayPRBSet(cfgOut, grant);
if direction == "UL"
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.prbSet", replayPRBSet);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pusch.nPRB", numel(replayPRBSet));
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.prbSet", replayPRBSet);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPRB", numel(replayPRBSet));
end
end

function n = grantReplayTxAntennas(cfgIn, direction, grant, numLayers)
direction = upper(string(direction));
if direction == "UL"
    explicit = sixgr.truth.GrantPreparation.firstFiniteNumeric( ...
        sixgr.util.structGet(grant, "NumTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.ul.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.ue.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nTxAnt", NaN));
    n = sixgr.truth.GrantPreparation.applyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
else
    explicit = sixgr.truth.GrantPreparation.firstFiniteNumeric( ...
        sixgr.util.structGet(grant, "PrecodingNumPorts", NaN), ...
        sixgr.util.structGet(grant, "NumTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nTxAnt", NaN));
    explicitAtLeastRank = sixgr.truth.GrantPreparation.firstFiniteAtLeastNumeric(numLayers, ...
        sixgr.util.structGet(grant, "PrecodingNumPorts", NaN), ...
        sixgr.util.structGet(grant, "NumTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nTxAnt", NaN));
    if isfinite(explicitAtLeastRank)
        explicit = explicitAtLeastRank;
    end
    n = sixgr.truth.GrantPreparation.applyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
end
end

function value = firstFiniteNumeric(varargin)
value = NaN;
for i = 1:nargin
    candidate = double(varargin{i});
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        value = candidate(1);
        return;
    end
end
end

function n = applyGrantReplayAntennaCap(cfgIn, explicitValue, numLayers)
n = max(1, round(double(sixgr.truth.GrantPreparation.firstFiniteNumeric(explicitValue, numLayers))));
if logical(sixgr.util.structGet(cfgIn, "system.waveform.capReplayAntennasToLayers", false))
    n = max(1, min(n, max(1, round(double(numLayers)))));
end
end

function value = firstFiniteAtLeastNumeric(minValue, varargin)
value = NaN;
minValue = max(1, round(double(minValue)));
for i = 1:nargin-1
    candidate = double(varargin{i});
    candidate = candidate(isfinite(candidate) & candidate >= minValue);
    if ~isempty(candidate)
        value = double(candidate(1));
        return;
    end
end
end

function n = grantReplayRxAntennas(cfgIn, direction, grant, numLayers)
direction = upper(string(direction));
if direction == "UL"
    explicit = sixgr.truth.GrantPreparation.firstFiniteNumeric( ...
        sixgr.util.structGet(cfgIn, "channel.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.ul.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "scenario.bs.nTxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nRxAnt", NaN));
    n = sixgr.truth.GrantPreparation.applyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
else
    explicit = sixgr.truth.GrantPreparation.firstFiniteNumeric( ...
        sixgr.util.structGet(cfgIn, "scenario.ue.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "channel.nRxAnt", NaN), ...
        sixgr.util.structGet(cfgIn, "phy.nRxAnt", NaN));
    n = sixgr.truth.GrantPreparation.applyGrantReplayAntennaCap(cfgIn, explicit, numLayers);
end
end

function cfgOut = alignGrantReplayCarrier(cfgIn, grant)
cfgOut = cfgIn;
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
prbOffset = 0;
requiredNSizeGrid = NaN;
useGrantLocalGrid = logical(sixgr.util.structGet(cfgOut, "system.waveform.useGrantLocalGrid", false));
if ~isempty(prbSet)
    prbSet = unique(prbSet(isfinite(prbSet) & prbSet >= 0));
    if ~isempty(prbSet)
        if useGrantLocalGrid
            prbOffset = min(prbSet);
            requiredNSizeGrid = max(prbSet) - prbOffset + 1;
        else
            requiredNSizeGrid = max(prbSet) + 1;
        end
    end
end
if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    nprb = double(sixgr.util.structGet(grant, "NPRB", NaN));
    if isfinite(nprb) && nprb >= 1
        requiredNSizeGrid = round(nprb);
    end
end
if ~(isfinite(requiredNSizeGrid) && requiredNSizeGrid >= 1)
    return;
end
currentNSizeGrid = double(sixgr.util.structGet(cfgOut, "phy.carrier.NSizeGrid", NaN));
if ~(isfinite(currentNSizeGrid) && currentNSizeGrid >= 1)
    currentNSizeGrid = requiredNSizeGrid;
end
if useGrantLocalGrid
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", max(1, round(requiredNSizeGrid)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NStartGrid", max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0))) + round(prbOffset)));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", double(prbOffset));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "grant_allocation");
else
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NSizeGrid", max(round(currentNSizeGrid), round(requiredNSizeGrid)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.carrier.NStartGrid", max(0, round(double(sixgr.util.structGet(cfgOut, "phy.carrier.NStartGrid", 0)))));
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayPRBOffset", 0);
    cfgOut = sixgr.util.structSet(cfgOut, "system.waveform.replayGridMode", "full_carrier");
end
end

function prbSet = grantReplayPRBSet(cfgIn, grant)
raw = sixgr.util.structGet(grant, "PRBSet", []);
if ~(isnumeric(raw) && isreal(raw) && ~isempty(raw))
    error("sixgr:truth:MissingGrantReplayPRBSet", ...
        "Truth waveform replay requires an explicit nonempty grant PRBSet.");
end
prbSet = double(unique(raw(:).', "stable"));
if any(~isfinite(prbSet)) || any(prbSet ~= fix(prbSet)) || ...
        any(prbSet < 0)
    error("sixgr:truth:InvalidGrantReplayPRBSet", ...
        "Truth waveform replay PRBSet must contain finite nonnegative integers.");
end
offset = double(sixgr.util.structGet(cfgIn, "system.waveform.replayPRBOffset", 0));
if isfinite(offset) && offset > 0
    prbSet = prbSet - offset;
end
if any(prbSet < 0) || any(prbSet ~= fix(prbSet))
    error("sixgr:truth:InvalidGrantReplayPRBOffset", ...
        "system.waveform.replayPRBOffset moves the explicit grant PRBSet " + ...
        "outside the replay carrier.");
end
nGrid = double(sixgr.util.structGet(cfgIn, ...
    "phy.carrier.NSizeGrid", NaN));
if isfinite(nGrid) && any(prbSet >= round(nGrid))
    error("sixgr:truth:GrantReplayPRBOutOfRange", ...
        "Truth waveform replay PRBSet exceeds the replay carrier grid.");
end
end

function nrePerPRB = extractGrantNREPerPRB(info, nPRB, modStr, nLayers)
[nrePerPRB, ~] = sixgr.util.resolveDataNREPerPRB(info, nPRB, modStr, nLayers);
end

function cfgOut = pruneIncompatibleDLPrecodingConfig(cfgIn, pdsch, grant)
cfgOut = cfgIn;
if nargin < 3 || ~isstruct(grant)
    grant = struct();
end
phyGrant = sixgr.util.structGet(grant, "PHYGrant", struct());
if isstruct(phyGrant) && ~isempty(fieldnames(phyGrant)) && ...
        logical(sixgr.util.structGet(phyGrant, "IsFrozen", false))
    % A frozen scheduler grant already owns the measured logical, RF and
    % physical matrices.  The legacy compatibility path below normalizes
    % every column and would silently change that selected MU-MIMO design.
    cfgOut = sixgr.truth.applyFrozenDLGrantAuthority( ...
        cfgOut, grant, "precoding_compatibility_prune");
    return;
end
nLayers = double(sixgr.util.structGet(pdsch, "NumLayers", 1));
if ~(isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
expectedPorts = sixgr.truth.GrantPreparation.resolveDLPDSCHLogicalPortCount(cfgOut, grant, nLayers);
resolvedPorts = NaN;
for i = 1:numel(paths)
    path = paths(i);
    Wcfg = sixgr.util.structGet(cfgOut, path, []);
    if isempty(Wcfg)
        continue;
    end
    inputRows = size(Wcfg, 1);
    inputCols = size(Wcfg, 2);
    Wcfg = sixgr.truth.GrantPreparation.adaptDLPrecodingMatrix(Wcfg, nLayers);
    if isempty(Wcfg)
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    if size(Wcfg, 2) ~= round(double(nLayers))
        error("sixgr:truth:DLPrecoderAdaptationLayerMismatch", ...
            "DL precoder adaptation changed %s from %dx%d to %dx%d while resolving %d layer(s).", ...
            char(path), inputRows, inputCols, size(Wcfg, 1), size(Wcfg, 2), round(double(nLayers)));
    end
    nPorts = sixgr.truth.GrantPreparation.precodingPortCount(Wcfg, nLayers);
    if isfinite(expectedPorts) && expectedPorts >= 1 && nPorts ~= round(double(expectedPorts))
        cfgOut = sixgr.util.structSet(cfgOut, path, []);
        continue;
    end
    cfgOut = sixgr.util.structSet(cfgOut, path, Wcfg);
    resolvedPorts = nPorts;
end
if isfinite(resolvedPorts) && resolvedPorts >= max(1, round(double(nLayers)))
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", resolvedPorts);
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", resolvedPorts);
elseif isfinite(expectedPorts) && expectedPorts >= max(1, round(double(nLayers)))
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.numPorts", round(double(expectedPorts)));
    cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.nPorts", round(double(expectedPorts)));
end
for i = 1:numel(paths)
    Wcheck = sixgr.util.structGet(cfgOut, paths(i), []);
    if ~isempty(Wcheck) && size(Wcheck, 2) ~= round(double(nLayers))
        error("sixgr:truth:DLPrecoderPruneOutputMismatch", ...
            "DL precoder pruning returned %s=%dx%d for %d layer(s).", ...
            char(paths(i)), size(Wcheck, 1), size(Wcheck, 2), round(double(nLayers)));
    end
end
end

function [grantOut, cfgOut] = sanitizeDLGrantFeedback(cfgIn, pdsch, grantIn)
grantOut = grantIn;
cfgOut = cfgIn;

nLayers = max(1, round(double(sixgr.util.structGet(pdsch, "NumLayers", ...
    sixgr.util.structGet(grantOut, "NumLayers", sixgr.util.structGet(grantOut, "Layers", 1))))));
numTxPorts = sixgr.truth.GrantPreparation.resolveDLPDSCHLogicalPortCount(cfgOut, grantOut, nLayers);
explicitMatrix = sixgr.util.structGet(cfgOut, "phy.pdsch.precoding.matrix", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.precodingMatrix", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.W", [])));
pmi = double(sixgr.util.structGet(grantOut, "PMI", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.PMI", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.TPMI", ...
    sixgr.util.structGet(cfgOut, "phy.pdsch.tpmi", NaN)))));
try
    candidates = sixgr.phy.dl.pmiCodebookCandidates(cfgOut, nLayers, numTxPorts);
    validPMI=isscalar(pmi) && isreal(pmi) && isfinite(pmi) && pmi==fix(pmi) && ...
        any([candidates.PMI]==pmi);
    needsDefaultPMI = isempty(explicitMatrix) && ~isempty(candidates) && ~validPMI;
    if needsDefaultPMI
        if sixgr.truth.GrantPreparation.strictTruthMode(cfgOut)
            grantOut.PMI = NaN;
            grantOut.PMIResolutionStatus = "missing_csi_pmi_no_strict_default";
            grantOut.PrecoderSource = "pmi_unavailable_strict_truth";
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", []);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", []);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", []);
        else
            grantOut.PMI = 0;
            grantOut.PMIResolutionStatus = "legacy_non_strict_default_pmi";
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", 0);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", 0);
            cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", 0);
        end
    elseif isempty(candidates) && isfinite(pmi)
        grantOut.PMI = NaN;
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", []);
    end
catch cause
    if isempty(explicitMatrix) && sixgr.truth.GrantPreparation.strictTruthMode(cfgOut)
        rethrow(cause);
    end
    if isempty(explicitMatrix)
        grantOut.PMI = NaN;
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.PMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.TPMI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.pdsch.tpmi", []);
    end
end

cri = double(sixgr.util.structGet(grantOut, "CRI", NaN));
if isfinite(cri)
    numCandidates = sixgr.util.structGet(cfgOut, "phy.csi.numResourceCandidates", ...
        sixgr.util.structGet(cfgOut, "phy.csirs.numResources", ...
        sixgr.util.structGet(cfgOut, "phy.beamManagement.trpCount", 1)));
    numCandidates = max(1, round(double(numCandidates)));
    if cri < 0 || cri >= numCandidates
        grantOut.CRI = NaN;
        cfgOut = sixgr.util.structSet(cfgOut, "phy.beamManagement.selectedCRI", []);
        cfgOut = sixgr.util.structSet(cfgOut, "phy.csi.selectedCRI", []);
    end
end
end

function tf = strictTruthMode(cfg)
tf = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false)) || ...
    lower(strtrim(string(sixgr.util.structGet(cfg, "run.honestyMode", "")))) == "strict";
end

function nPorts = maxNRLogicalPDSCHPorts()
nPorts = 32;
end

function [W, source] = resolveDLLogicalPrecoderFromPMI(cfg, grant, nLayers, nPorts)
nLayers = max(1, round(double(nLayers)));
nPorts = max(nLayers, round(double(nPorts)));
source = "logical_identity_from_element_domain_precoder";
W = eye(nPorts, nLayers);
pmi = sixgr.truth.GrantPreparation.firstFiniteNumeric( ...
    sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN), ...
    sixgr.util.structGet(grant, "PMI", NaN), ...
    sixgr.util.structGet(grant, "TPMI", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.PMI", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.pmi", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.TPMI", NaN), ...
    sixgr.util.structGet(cfg, "phy.pdsch.tpmi", NaN));
mode = char(string(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ...
    sixgr.util.structGet(grant, "PMICodebookMode", ...
    sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo")))));
if strlength(strtrim(string(mode))) == 0
    mode = "type1_su_mimo";
end
try
    [candidates, ~] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, nPorts, "Mode", mode);
    if isempty(candidates)
        return;
    end
    idx = 1;
    if isfinite(pmi)
        pmi0 = round(double(pmi));
        if pmi0 >= 0 && pmi0 < numel(candidates)
            idx = pmi0 + 1;
        end
    end
    Wcand = double(candidates(idx).W);
    if isequal(size(Wcand), [nPorts nLayers])
        W = Wcand;
        source = "logical_pmi_codebook_from_element_domain_precoder";
    end
catch
    % Leave the identity logical precoder. The element-domain matrix cannot
    % define NR waveform ports without explicit hybrid element-domain TX.
end
end

function token = formatIndexSet(values)
if isstring(values) || ischar(values)
    values = string(values);
    values = values(:).';
    values = values(~ismissing(values) & strlength(strtrim(values)) > 0);
    if isempty(values)
        token = "";
    else
        token = join(values, "|");
    end
    return;
end
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    token = "";
    return;
end
token = join(string(round(values)), "|");
end

function totalBits = estimateGrantCurrentRateMatchedBits(grant)
totalBits = double(sixgr.util.structGet(grant, "CurrentRateMatchedBits", NaN));
if isfinite(totalBits) && totalBits > 0
    return;
end
totalBits = double(sixgr.util.structGet(grant, "CodedBitCountG", NaN));
if isfinite(totalBits) && totalBits > 0
    return;
end
totalBits = double(sixgr.util.structGet(grant, "RateMatchedBits", NaN));
if isfinite(totalBits) && totalBits > 0
    return;
end
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
prbSet = prbSet(isfinite(prbSet));
prbCount = double(numel(prbSet));
if ~(isfinite(prbCount) && prbCount > 0)
    prbCount = double(sixgr.util.structGet(grant, "PRBs", NaN));
end
nrePerPRB = double(sixgr.util.structGet(grant, "NREPerPRB", NaN));
numLayers = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
qm = sixgr.truth.GrantPreparation.grantModulationOrder(sixgr.util.structGet(grant, "Modulation", ""));
if isfinite(prbCount) && prbCount > 0 && isfinite(nrePerPRB) && nrePerPRB > 0 && ...
        isfinite(numLayers) && numLayers >= 1 && isfinite(qm) && qm >= 1
    totalBits = double(prbCount * nrePerPRB * numLayers * qm);
else
    totalBits = NaN;
end
end

function qm = grantModulationOrder(modulation)
token = upper(strtrim(char(string(modulation))));
switch token
    case {"BPSK","PI/2-BPSK"}
        qm = 1;
    case "QPSK"
        qm = 2;
    case "16QAM"
        qm = 4;
    case "64QAM"
        qm = 6;
    case "256QAM"
        qm = 8;
    case "1024QAM"
        qm = 10;
    case "4096QAM"
        qm = 12;
    otherwise
        qm = NaN;
end
end

function perCB = estimateGrantCurrentRateMatchedBitsPerCodeBlock(tbContext, totalBits)
perCB = double(sixgr.util.structGet(tbContext, "OriginalRateMatchedBitsPerCB", []));
perCB = perCB(:).';
nCB = round(double(sixgr.util.structGet(tbContext, "NumCodeBlocks", numel(perCB))));
if ~(isfinite(nCB) && nCB >= 1)
    nCB = max(1, numel(perCB));
end
if ~(isfinite(totalBits) && totalBits > 0)
    if isempty(perCB)
        perCB = zeros(1, 0);
    end
    return;
end
if isempty(perCB)
    perCB = floor(double(totalBits) / nCB) * ones(1, nCB);
    remainder = round(double(totalBits) - sum(perCB));
    if remainder > 0
        perCB(1:remainder) = perCB(1:remainder) + 1;
    end
    return;
end
perCB = perCB(1:min(numel(perCB), nCB));
if numel(perCB) < nCB
    perCB(end + 1:nCB) = perCB(end);
end
perCBSum = sum(perCB);
if ~(isfinite(perCBSum) && perCBSum > 0)
    perCB = floor(double(totalBits) / nCB) * ones(1, nCB);
else
    perCB = round(perCB .* (double(totalBits) / perCBSum));
end
delta = round(double(totalBits) - sum(perCB));
if delta ~= 0 && ~isempty(perCB)
    perCB(end) = perCB(end) + delta;
end
perCB = max(perCB, 0);
end

function grant = resolveStrictGrantSnapshot(cfgIn, direction, grant, queueBitsUpper)
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
direction = upper(string(direction));
if ~(isfinite(queueBitsUpper) && queueBitsUpper > 0)
    queueBitsUpper = inf;
end
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
if isempty(prbSet)
    error("sixgr:truth:MissingStrictGrantPRBSet", ...
        "Strict grant hydration requires an explicit scheduler PRBSet.");
end
fullGrant = sixgr.truth.GrantPreparation.hydrateGrantSnapshot(cfgIn, direction, grant);
fullBits = double(sixgr.util.structGet(fullGrant, "TransportBlockSize", ...
    sixgr.util.structGet(fullGrant, "TBSBits", NaN)));
% The scheduler has already performed queue-aware PRB selection, exact RE
% accounting, TBS finalization, DCI construction, and immutable PHY-grant
% freezing.  Re-running a PRB search here creates a second allocator after
% PDCCH and can silently transmit a different TB from the one scheduled.
% Hydration may materialize toolbox objects and matrices, but it must not
% change any field from which the receiver derives the transport-block size.
sixgr.truth.GrantPreparation.assertStrictGrantHydrationConsistency(grant, fullGrant, direction);
if ~(isfinite(fullBits) && fullBits > 0)
    error("sixgr:truth:InvalidHydratedGrantTBS", ...
        "Hydrated %s grant has no positive exact transport-block size.", ...
        char(direction));
end
if fullBits > queueBitsUpper
    error("sixgr:truth:FrozenGrantExceedsQueue", ...
        "Frozen %s grant TBS=%d exceeds the scheduler-recorded queue upper bound=%d bits; execution-time PRB resizing is forbidden.", ...
        char(direction), round(fullBits), round(queueBitsUpper));
end
fullGrant.TBSBits = double(fullBits);
fullGrant.TBSBytes = floor(double(fullBits) / 8);
grant = fullGrant;
end

function assertStrictGrantHydrationConsistency(scheduled, hydrated, direction)
direction = upper(string(direction));
scheduledBits = double(sixgr.util.structGet(scheduled, "TBSBits", ...
    sixgr.util.structGet(scheduled, "TransportBlockSize", NaN)));
hydratedBits = double(sixgr.util.structGet(hydrated, "TBSBits", ...
    sixgr.util.structGet(hydrated, "TransportBlockSize", NaN)));
scheduledMod = upper(strtrim(string(sixgr.util.structGet(scheduled, ...
    "TBSInputModulation", sixgr.util.structGet(scheduled, "Modulation", "")))));
hydratedMod = upper(strtrim(string(sixgr.util.structGet(hydrated, ...
    "TBSInputModulation", sixgr.util.structGet(hydrated, "Modulation", "")))));
numericFields = ["TBSInputNumLayers","TBSInputNPRB", ...
    "TBSInputNREPerPRB","TBSInputTargetCodeRate","TBSInputXOverhead"];
scheduledValues = NaN(1, numel(numericFields));
hydratedValues = NaN(1, numel(numericFields));
for fieldIdx = 1:numel(numericFields)
    fieldName = numericFields(fieldIdx);
    scheduledValues(fieldIdx) = double(sixgr.util.structGet(scheduled, fieldName, NaN));
    hydratedValues(fieldIdx) = double(sixgr.util.structGet(hydrated, fieldName, NaN));
end
complete = isfinite(scheduledBits) && scheduledBits > 0 && ...
    isfinite(hydratedBits) && hydratedBits > 0 && ...
    strlength(scheduledMod) > 0 && strlength(hydratedMod) > 0 && ...
    all(isfinite(scheduledValues)) && all(isfinite(hydratedValues));
if ~complete
    error("sixgr:truth:IncompleteFrozenGrantTBSContract", ...
        "%s execution requires complete scheduler and hydrated exact-TBS inputs; missing values cannot be reconstructed after PDCCH.", ...
        char(direction));
end
tol = [0 0 1e-9 1e-12 1e-9];
numericMatch = all(abs(scheduledValues - hydratedValues) <= tol);
if round(scheduledBits) ~= round(hydratedBits) || scheduledMod ~= hydratedMod || ~numericMatch
    error("sixgr:truth:FrozenGrantHydrationMismatch", ...
        "Frozen %s scheduler grant changed during execution hydration: TBS %d->%d, modulation %s->%s, layers %.0f->%.0f, NPRB %.0f->%.0f, NRE/PRB %.12g->%.12g, targetRate %.12g->%.12g, XOverhead %.12g->%.12g.", ...
        char(direction), round(scheduledBits), round(hydratedBits), ...
        char(scheduledMod), char(hydratedMod), ...
        scheduledValues(1), hydratedValues(1), ...
        scheduledValues(2), hydratedValues(2), ...
        scheduledValues(3), hydratedValues(3), ...
        scheduledValues(4), hydratedValues(4), ...
        scheduledValues(5), hydratedValues(5));
end
end

function bits = generateGrantTransportBlockBits(cfgIn, grant, direction, nBits)
nBits = max(0, round(double(nBits)));
if nBits < 1
    bits = int8([]);
    return;
end
seedBase = double(sixgr.util.structGet(cfgIn, "run.seed", 1));
seed = mod(seedBase + 53 * round(double(sixgr.util.structGet(grant, "RNTI", 1))) + 7919 * round(double(sixgr.util.structGet(grant, "Slot", 1))) + sum(double(char(upper(string(direction))))), 2^31 - 1);
rs = RandStream("mt19937ar", "Seed", max(1, round(seed)));
bits = int8(randi(rs, [0 1], nBits, 1));
end

function grantRow = refreshGrantRowFromGrant(grantRow, grant, resolvedBits)
if ~(istable(grantRow) && ~isempty(grantRow) && isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
symAlloc = double(sixgr.util.structGet(grant, "SymbolAllocation", []));
tbsBits = double(sixgr.util.structGet(grant, "TransportBlockSize", sixgr.util.structGet(grant, "TBSBits", resolvedBits)));
if ~(isfinite(tbsBits) && tbsBits >= 0)
    tbsBits = resolvedBits;
end
if ismember("PRBStart", string(grantRow.Properties.VariableNames))
    grantRow.PRBStart(1) = sixgr.truth.GrantPreparation.firstNumeric(prbSet, NaN);
end
if ismember("PRBCount", string(grantRow.Properties.VariableNames))
    grantRow.PRBCount(1) = double(numel(prbSet));
end
if ismember("SymbolStart", string(grantRow.Properties.VariableNames))
    grantRow.SymbolStart(1) = sixgr.truth.GrantPreparation.firstNumeric(symAlloc, NaN);
end
if ismember("NumSymbols", string(grantRow.Properties.VariableNames))
    grantRow.NumSymbols(1) = sixgr.truth.GrantPreparation.secondNumeric(symAlloc, NaN);
end
if ismember("TBSBits", string(grantRow.Properties.VariableNames)) && isfinite(tbsBits)
    grantRow.TBSBits(1) = double(tbsBits);
end
if ismember("TBSBytes", string(grantRow.Properties.VariableNames)) && isfinite(tbsBits)
    grantRow.TBSBytes(1) = floor(double(tbsBits) / 8);
end
if ismember("MCSIndex", string(grantRow.Properties.VariableNames))
    grantRow.MCSIndex(1) = double(sixgr.util.structGet(grant, "MCSIndex", sixgr.util.structGet(grant, "MCS", NaN)));
end
if ismember("Modulation", string(grantRow.Properties.VariableNames))
    grantRow.Modulation(1) = string(sixgr.util.structGet(grant, "Modulation", ""));
end
if ismember("TargetCodeRate", string(grantRow.Properties.VariableNames))
    grantRow.TargetCodeRate(1) = double(sixgr.util.structGet(grant, "TargetCodeRate", NaN));
end
if ismember("TBSInputModulation", string(grantRow.Properties.VariableNames))
    grantRow.TBSInputModulation(1) = string(sixgr.util.structGet(grant, ...
        "TBSInputModulation", sixgr.util.structGet(grant, "Modulation", "")));
end
exactTBSFields = ["TBSInputNumLayers","TBSInputNPRB","TBSInputNREPerPRB", ...
    "TBSInputTargetCodeRate","TBSInputXOverhead"];
for exactIdx = 1:numel(exactTBSFields)
    exactName = exactTBSFields(exactIdx);
    if ismember(exactName, string(grantRow.Properties.VariableNames))
        grantRow.(char(exactName))(1) = double(sixgr.util.structGet(grant, exactName, NaN));
    end
end
if ismember("TBSInputSource", string(grantRow.Properties.VariableNames))
    grantRow.TBSInputSource(1) = string(sixgr.util.structGet(grant, "TBSInputSource", ""));
end
if ismember("NumLayers", string(grantRow.Properties.VariableNames))
    grantRow.NumLayers(1) = double(sixgr.util.structGet(grant, "NumLayers", sixgr.util.structGet(grant, "Layers", NaN)));
end
if ismember("PMI", string(grantRow.Properties.VariableNames))
    grantRow.PMI(1) = double(sixgr.util.structGet(grant, "PMI", NaN));
end
if ismember("CRI", string(grantRow.Properties.VariableNames))
    grantRow.CRI(1) = double(sixgr.util.structGet(grant, "CRI", NaN));
end
if ismember("ConfiguredBeamSelectionStrategy", string(grantRow.Properties.VariableNames))
    grantRow.ConfiguredBeamSelectionStrategy(1) = string(sixgr.util.structGet(grant, "ConfiguredBeamSelectionStrategy", ""));
end
if ismember("PrecoderSource", string(grantRow.Properties.VariableNames))
    grantRow.PrecoderSource(1) = string(sixgr.util.structGet(grant, "PrecoderSource", ""));
end
if ismember("PrecodingMode", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingMode(1) = string(sixgr.util.structGet(grant, "PrecodingMode", ""));
end
if ismember("PrecodingApplicationStage", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingApplicationStage(1) = string(sixgr.util.structGet(grant, "PrecodingApplicationStage", ""));
end
if ismember("PrecodingActive", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingActive(1) = logical(sixgr.util.structGet(grant, "PrecodingActive", false));
end
if ismember("ExplicitBeamWeightsApplied", string(grantRow.Properties.VariableNames))
    grantRow.ExplicitBeamWeightsApplied(1) = logical(sixgr.util.structGet(grant, "ExplicitBeamWeightsApplied", false));
end
if ismember("TransformPrecodingApplied", string(grantRow.Properties.VariableNames))
    grantRow.TransformPrecodingApplied(1) = logical(sixgr.util.structGet(grant, "TransformPrecodingApplied", false));
end
if ismember("FrequencyHoppingApplied", string(grantRow.Properties.VariableNames))
    grantRow.FrequencyHoppingApplied(1) = logical(sixgr.util.structGet(grant, "FrequencyHoppingApplied", false));
end
if ismember("FrequencyHoppingMode", string(grantRow.Properties.VariableNames))
    grantRow.FrequencyHoppingMode(1) = string(sixgr.util.structGet(grant, "FrequencyHoppingMode", ""));
end
if ismember("FrequencyHoppingToolboxMode", string(grantRow.Properties.VariableNames))
    grantRow.FrequencyHoppingToolboxMode(1) = string(sixgr.util.structGet(grant, "FrequencyHoppingToolboxMode", ""));
end
if ismember("SecondHopStartPRB", string(grantRow.Properties.VariableNames))
    grantRow.SecondHopStartPRB(1) = double(sixgr.util.structGet(grant, "SecondHopStartPRB", NaN));
end
if ismember("BeamformingApplied", string(grantRow.Properties.VariableNames))
    grantRow.BeamformingApplied(1) = logical(sixgr.util.structGet(grant, "BeamformingApplied", false));
end
if ismember("AppliedBeamIndexSet", string(grantRow.Properties.VariableNames))
    grantRow.AppliedBeamIndexSet(1) = string(sixgr.util.structGet(grant, "AppliedBeamIndexSet", ""));
end
if ismember("AppliedPrecoderPMI", string(grantRow.Properties.VariableNames))
    grantRow.AppliedPrecoderPMI(1) = double(sixgr.util.structGet(grant, "AppliedPrecoderPMI", NaN));
end
if ismember("AppliedPrecoderPMIType", string(grantRow.Properties.VariableNames))
    grantRow.AppliedPrecoderPMIType(1) = string(sixgr.util.structGet(grant, "AppliedPrecoderPMIType", ""));
end
if ismember("AppliedPrecoderCodebookMode", string(grantRow.Properties.VariableNames))
    grantRow.AppliedPrecoderCodebookMode(1) = string(sixgr.util.structGet(grant, "AppliedPrecoderCodebookMode", ""));
end
if ismember("PrecodingNumPorts", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingNumPorts(1) = double(sixgr.util.structGet(grant, "PrecodingNumPorts", NaN));
end
if ismember("PrecodingNumLayers", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingNumLayers(1) = double(sixgr.util.structGet(grant, "PrecodingNumLayers", NaN));
end
if ismember("PrecodingMatrixRows", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingMatrixRows(1) = double(sixgr.util.structGet(grant, "PrecodingMatrixRows", NaN));
end
if ismember("PrecodingMatrixCols", string(grantRow.Properties.VariableNames))
    grantRow.PrecodingMatrixCols(1) = double(sixgr.util.structGet(grant, "PrecodingMatrixCols", NaN));
end
if ismember("GrantContextId", string(grantRow.Properties.VariableNames))
    grantRow.GrantContextId(1) = string(sixgr.util.structGet(grant, "GrantContextId", ""));
end
if ismember("GrantWorkerSafe", string(grantRow.Properties.VariableNames))
    grantRow.GrantWorkerSafe(1) = logical(sixgr.util.structGet(grant, "GrantWorkerSafe", true));
end
if ismember("GrantSharedStateCommitMode", string(grantRow.Properties.VariableNames))
    grantRow.GrantSharedStateCommitMode(1) = string(sixgr.util.structGet(grant, "GrantSharedStateCommitMode", "serial_coordinator_commit"));
end
if ismember("SRSGatingActive", string(grantRow.Properties.VariableNames))
    grantRow.SRSGatingActive(1) = logical(sixgr.util.structGet(grant, "SRSGatingActive", false));
end
if ismember("ControlEligible", string(grantRow.Properties.VariableNames))
    grantRow.ControlEligible(1) = logical(sixgr.util.structGet(grant, "ControlEligible", true));
end
if ismember("SchedulingEligible", string(grantRow.Properties.VariableNames))
    grantRow.SchedulingEligible(1) = logical(sixgr.util.structGet(grant, "SchedulingEligible", true));
end
if ismember("SchedulingBlockedBySRS", string(grantRow.Properties.VariableNames))
    grantRow.SchedulingBlockedBySRS(1) = logical(sixgr.util.structGet(grant, "SchedulingBlockedBySRS", false));
end
end

function value = firstNumeric(data, defaultValue)
value = defaultValue;
if nargin < 2
    value = NaN;
end
if isempty(data)
    return;
end
data = double(data(:));
idx = find(isfinite(data), 1, "first");
if ~isempty(idx)
    value = double(data(idx));
end
end

function value = secondNumeric(data, defaultValue)
value = defaultValue;
if nargin < 2
    value = NaN;
end
if isempty(data)
    return;
end
data = double(data(:));
data = data(isfinite(data));
if numel(data) >= 2
    value = double(data(2));
elseif numel(data) == 1
    value = double(data(1));
end
end

function key=sharedGrantControlKey(grant,direction)
% Scheduling identity, not receiver evidence or a substitute for DCI CRC.
key=upper(string(direction))+"_ue_"+string(grant.UEIndex)+"_rnti_"+ ...
    string(grant.RNTI)+"_control_"+string(sixgr.truth.resolvePDCCHControlSlot(grant,NaN))+ ...
    "_data_"+string(grant.Slot);
end

function [lhs, rhs] = harmonizeStructArrays(lhs, rhs)
if ~isstruct(lhs)
    lhs = struct();
end
if ~isstruct(rhs)
    rhs = struct();
end
lhsFields = string(fieldnames(lhs));
rhsFields = string(fieldnames(rhs));
allFields = union(lhsFields, rhsFields, "stable");
for i = 1:numel(allFields)
    fieldName = char(allFields(i));
    if ~isfield(lhs, fieldName)
        [lhs(1:numel(lhs)).(fieldName)] = deal([]);
    end
    if ~isfield(rhs, fieldName)
        [rhs(1:numel(rhs)).(fieldName)] = deal([]);
    end
end
end

end
end
