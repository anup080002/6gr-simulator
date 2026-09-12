function [tx, info] = PDSCH_Tx(cfg, varargin)
%PDSCH_Tx Generate a basic PDSCH transmission (DL-SCH -> PDSCH -> OFDM).
%
%   [TX,INFO] = sixgr.phy.dl.PDSCH_Tx(CFG) builds a carrier and PDSCH
%   allocation from an explicit calibration request or immutable strict
%   scheduling assignment, generates or accepts a
%   transport block, performs LDPC-based DL-SCH encoding (CRC, segmentation,
%   LDPC encode, rate matching), maps PDSCH + DMRS (and optional PTRS) into
%   a resource grid, and returns an OFDM waveform.
%
%   The TB/coding blocks are factored so PDSCH and PUSCH can reuse them.
%
%   Name-Value options:
%     "Carrier"      : nrCarrierConfig override
%     "PDSCH"        : nrPDSCHConfig override
%     "TransportBlockBits" : column vector of bits (int8/double)
%     "TransportBlockSizeOverride" : stored HARQ TB size to preserve during replay
%     "RV"           : redundancy version (0..3)
%     "TargetCodeRate": code rate (0..1)
%     "XOverhead"    : xOverhead for nrTBS (default 0)
%     "NumTxAnt"     : number of TX antennas / mapped antenna ports
%     "PrecodingMatrix" : wideband Nports-by-Nlayers matrix (or transpose),
%                         or an Nports-by-Nlayers-by-NPRG PRG bundle array
%     "PHYGrant"     : frozen canonical grant dimensional contract
%     "CellCommonSignalOwnershipMode" : controls whether configured
%                         serving-cell common signals are emitted by this
%                         waveform component. The default, "emit", maps
%                         them normally. "reserve_only" retains their RE
%                         reservation but does not duplicate them in a
%                         user-dedicated shared-slot component.
%
%   CFG.phy.pdsch.dmrs.dataToDMRSEPREDifference_dB controls the PDSCH
%   data-EPRE minus DM-RS-EPRE difference. The default is 0 dB. The
%   normative -3 dB token maps to exact beta=sqrt(2), with configured and
%   realized dB values retained separately in the output metadata.
%
%   Outputs:
%     TX.Waveform      : time-domain OFDM waveform
%     TX.Grid          : frequency-domain transmit resource grid; may contain
%                        more pages than the PDSCH port count when auxiliary
%                        runtime signals such as CSI-RS reserve additional
%                        transmit pages
%     TX.TransportBlock: original TB bits
%     TX.Codeword      : rate-matched codeword bits (pre-scramble)
%     TX.Carrier       : carrier config object
%     TX.PDSCH         : PDSCH config object
%     TX.PDSCHIndices  : linear indices for PDSCH mapping
%     TX.DMRSIndices   : linear indices for PDSCH DMRS mapping
%     TX.DMRSSymbols   : DMRS symbols
%     TX.PTRSIndices   : linear indices for PTRS mapping (maybe empty)
%     TX.PTRSSymbols   : PTRS symbols (maybe empty)
%     TX.PDSCHAntennaIndices : antenna-oriented PDSCH indices after precoding
%     TX.DMRSAntennaIndices  : antenna-oriented DMRS indices after precoding
%     TX.ResourceGridPortContract : truthful page-count provenance for the
%                        full transmit grid versus the PDSCH/DM-RS signals
%     TX.PrecodeInfo    : explicit precoding metadata / guard decisions
%
%   Notes:
%     * nrPDSCH internally performs scrambling using pdsch.NID / pdsch.RNTI.
%       Therefore, TX.Codeword is NOT scrambled here.
%     * Ranks 1-4 use one codeword. Ranks 5-8 use the exact NR
%       two-codeword mapping with independent TB, RV and CodingLayout state.

sixgr.runtime.RuntimeCallLedger.record("sixgr.phy.dl.PDSCH_Tx", ...
    "PDSCH", "DL", struct("Stage","TX"));

% ---------------------- Parse inputs ----------------------
ip = inputParser;
ip.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
ip.addParameter('PDSCH', [], @(x) isempty(x) || isobject(x));
ip.addParameter('TransportBlockBits', [], @(x) isempty(x) || isnumeric(x) || islogical(x) || iscell(x));
ip.addParameter('TransportBlockSizeOverride', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>0)));
ip.addParameter('RV', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>=0 & x(:)<=3)));
ip.addParameter('TargetCodeRate', [], @(x) isempty(x) || (isnumeric(x) && isvector(x) && all(x(:)>0 & x(:)<1)));
ip.addParameter('XOverhead', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=0));
ip.addParameter('NumTxAnt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>=1));
ip.addParameter('PrecodingMatrix', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('PHYGrant', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('SchedulerGrantContext', struct(), @(x) isempty(x) || isstruct(x));
ip.addParameter('Assignment', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHSchedulingAssignment'));
ip.addParameter('ResourcePlan', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHResourcePlan'));
ip.addParameter('ReferenceSignalConfig', struct(), ...
    @(x) (isstruct(x) && isscalar(x)) || ...
        isa(x, 'sixgr.pdsch.PDSCHReferenceSignalConfig'));
ip.addParameter('PrecoderBundle', [], @(x) isempty(x) || isa(x, 'sixgr.pdsch.PDSCHPrecoderBundle'));
ip.addParameter('IntegrationContext', struct(), @(x) isstruct(x) && isscalar(x));
ip.addParameter('Nref', [], @(x) isempty(x) || isnumeric(x));
ip.addParameter('ExecutionProfile', "", @(x) ischar(x) || isstring(x));
ip.addParameter('CompactOutput', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter('CellCommonSignalOwnershipMode', "emit", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
ip.addParameter('ISACReferenceGrid', [], @(x) isempty(x) || isnumeric(x));
ip.parse(varargin{:});
opt = ip.Results;
cellCommonSignalOwnershipMode = localCellCommonSignalOwnershipMode( ...
    opt.CellCommonSignalOwnershipMode);
phyGrant = opt.PHYGrant;
hasPHYGrant = isstruct(phyGrant) && ~isempty(fieldnames(phyGrant));
executionProfile = localResolveExecutionProfile(cfg, opt.ExecutionProfile, opt.Assignment);
ptrsAuthority = localPTRSAuthorityFeature(cfg, executionProfile, opt.Assignment);
sixgr.config.assertRuntimeFeatureUse(cfg, ptrsAuthority, ...
    localRequestedPTRSEnabled(cfg, opt, phyGrant, hasPHYGrant), ...
    "PDSCH_Tx:" + executionProfile);
localPreflightConfiguredTDRA( ...
    cfg, opt, hasPHYGrant, executionProfile);
strictAssignmentProfile = any(executionProfile == ...
    ["connected_strict","sps_strict","ra_si_strict"]);
if strictAssignmentProfile
    if isempty(opt.Assignment)
        error("sixgr:pdsch:MissingSchedulingAssignment", ...
            "%s PDSCH transmission requires an immutable scheduling assignment.", ...
            executionProfile);
    end
    if isempty(opt.ResourcePlan)
        error("sixgr:pdsch:MissingResourcePlan", ...
            "%s PDSCH execution requires the resolved resource ownership plan.", ...
            executionProfile);
    end
    if hasPHYGrant
        error("sixgr:pdsch:ConfiguredGrantNotAllowed", ...
            "A configured/frozen PHYGrant cannot replace decoded assignment ownership.");
    end
    if opt.Assignment.Profile ~= executionProfile
        error("sixgr:pdsch:ExecutionProfileMismatch", ...
            "Assignment profile '%s' does not match requested '%s'.", ...
            opt.Assignment.Profile, executionProfile);
    end
    if executionProfile == "ra_si_strict" && ...
            string(opt.Assignment.get("ControlAuthority")) ~= ...
            "transmitter_scheduled_dci"
        error("sixgr:pdsch:InvalidRASITransmitAuthority", ...
            "RA/SI PDSCH transmission requires transmitter-scheduled DCI ownership.");
    end
end
if ~isempty(opt.Assignment)
    [tx, info] = localDelegateCanonicalPDSCHTransmitter( ...
        opt, executionProfile, hasPHYGrant);
    return;
end
if any(executionProfile == ["phy_calibration","scheduler_truth"])
    [tx, info] = localDelegateCanonicalGrantTransmitter( ...
        cfg, opt, phyGrant, hasPHYGrant, executionProfile);
    return;
end
error("sixgr:pdsch:MissingSchedulingAssignment", ...
    "Non-calibration PDSCH transmission requires an immutable scheduling assignment.");
end

function featureName = localPTRSAuthorityFeature(cfg, executionProfile, assignment)
featureName = "ptrs";
rntiType = "";
if isa(assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    assignmentData = assignment.toStruct();
    rntiType = upper(strtrim(string(sixgr.util.structGet( ...
        assignmentData, "RNTIType", ""))));
end
if string(executionProfile) ~= "ra_si_strict"
    return;
end
features = sixgr.util.structGet(cfg, "runtime.features", struct());
if rntiType == "SI-RNTI" && isfield(features, "sib1_ptrs")
    featureName = "sib1_ptrs";
elseif rntiType == "RA-RNTI" && isfield(features, "ra_msg2_ptrs")
    featureName = "ra_msg2_ptrs";
elseif rntiType == "TC-RNTI" && isfield(features, "ra_msg4_ptrs")
    featureName = "ra_msg4_ptrs";
end
end

function localPreflightConfiguredTDRA( ...
        cfg, opt, hasPHYGrant, executionProfile)
% Preserve configuration-error authority before execution-profile dispatch.
% An explicit PDSCH object, frozen grant, or immutable assignment owns its
% own TDRA. The configured calibration path must expose both fields.
if executionProfile ~= "phy_calibration" || ...
        ~isempty(opt.PDSCH) || hasPHYGrant || ~isempty(opt.Assignment) || ...
        ~logical(sixgr.util.structGet(cfg, "run.strictMode", false))
    return;
end
symbolAllocation = sixgr.util.structGet(cfg, ...
    "phy.pdsch.symbolAllocation", []);
if isempty(symbolAllocation)
    symbolAllocation = sixgr.util.structGet(cfg, ...
        "phy.pdsch.SymbolAllocation", []);
end
mappingType = string(sixgr.util.structGet(cfg, ...
    "phy.pdsch.mappingType", ""));
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(cfg, ...
        "phy.pdsch.MappingType", ""));
end
if isempty(symbolAllocation) || strlength(strtrim(mappingType)) == 0
    error("sixgr:phy:grid:allocREsPDSCH:MissingExplicitTDRA", ...
        "Strict PDSCH execution requires explicit SymbolAllocation and MappingType.");
end
end

function [pdschInd, pdschInfo, pdsch] = localBuildPDSCHFromFrozenGrant(carrier, cfg, phyGrant)
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
pdschArgs = { ...
    "PRBSet", double(sixgr.util.structGet(ra, "PRBSet", [])), ...
    "SymbolAllocation", double(sixgr.util.structGet(ra, "SymbolAllocation", [])), ...
    "NumLayers", localPositiveIntegerValue(sixgr.util.structGet(cl, "NumLayers", 1), "PHYGrant.CodingLayout.NumLayers"), ...
    "Modulation", char(string(sixgr.util.structGet(cl, "Modulation", "QPSK"))), ...
    "RNTI", localResolveGrantRNTI(cfg, phyGrant), ...
    "NID", localResolveGrantNID(cfg, carrier), ...
    "MappingType", localResolveGrantMappingType(cfg, phyGrant), ...
    "FixedReferenceMode", true};
[pdschInd, pdschInfo, pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier, cfg, pdschArgs{:});
localAssertExplicitPDSCHMatchesGrant(pdsch, phyGrant);
end

function rnti = localResolveGrantRNTI(cfg, phyGrant)
rnti = localFirstFiniteScalarValue( ...
    sixgr.util.structGet(phyGrant, "ChannelStateKey.RNTI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.RNTI", []), ...
    sixgr.util.structGet(cfg, "phy.pdsch.RNTI", []), ...
    1);
rnti = localNonnegativeIntegerValue(rnti, "PDSCH RNTI");
end

function nid = localResolveGrantNID(cfg, carrier)
nid = sixgr.util.structGet(cfg, "phy.pdsch.NID", ...
    sixgr.util.structGet(cfg, "phy.pdsch.nid", []));
if isempty(nid)
    nid = sixgr.util.structGet(cfg, "phy.NCellID", []);
end
if isempty(nid)
    try
        nid = carrier.NCellID;
    catch
        nid = 0;
    end
end
nid = localNonnegativeIntegerValue(nid, "PDSCH NID");
end

function mappingType = localResolveGrantMappingType(cfg, phyGrant)
mappingType = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.MappingType", ""));
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.mappingType", ""));
end
if strlength(strtrim(mappingType)) == 0
    mappingType = string(sixgr.util.structGet(cfg, "phy.pdsch.mappingType", "A"));
end
if strlength(strtrim(mappingType)) == 0
    mappingType = "A";
end
mappingType = upper(strtrim(mappingType));
end

function localAssertExplicitPDSCHMatchesGrant(pdsch, phyGrant)
ra = sixgr.util.structGet(phyGrant, "ResourceAllocation", struct());
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
localAssertSameVector(localObjectValue(pdsch, "PRBSet", []), sixgr.util.structGet(ra, "PRBSet", []), ...
    "sixgr:phy:dl:PDSCHGrantPRBMismatch", "PDSCH PRBSet does not match frozen PHYGrant.");
localAssertSameVector(localObjectValue(pdsch, "SymbolAllocation", []), sixgr.util.structGet(ra, "SymbolAllocation", []), ...
    "sixgr:phy:dl:PDSCHGrantSymbolMismatch", "PDSCH SymbolAllocation does not match frozen PHYGrant.");
localAssertSameScalar(localObjectValue(pdsch, "NumLayers", NaN), sixgr.util.structGet(cl, "NumLayers", NaN), ...
    "sixgr:phy:dl:PDSCHGrantLayerMismatch", "PDSCH NumLayers does not match frozen PHYGrant.");
grantMod = char(localModulationText(sixgr.util.structGet(cl, "Modulation", "")));
pdschMod = char(localModulationText(localObjectValue(pdsch, "Modulation", "")));
if strlength(string(grantMod)) > 0 && ~strcmpi(strtrim(pdschMod), strtrim(grantMod))
    error("sixgr:phy:dl:PDSCHGrantModulationMismatch", ...
        "PDSCH Modulation '%s' does not match frozen PHYGrant '%s'.", pdschMod, grantMod);
end
grantRNTI = localFirstFiniteScalarValue(sixgr.util.structGet(phyGrant, "ChannelStateKey.RNTI", []), ...
    sixgr.util.structGet(phyGrant, "LegacyGrantSnapshot.RNTI", []), NaN);
if isfinite(grantRNTI)
    localAssertSameScalar(localObjectValue(pdsch, "RNTI", NaN), grantRNTI, ...
        "sixgr:phy:dl:PDSCHGrantRNTIMismatch", "PDSCH RNTI does not match frozen PHYGrant.");
end
grantMap = localResolveGrantMappingType(struct(), phyGrant);
if strlength(strtrim(grantMap)) > 0
    pdschMap = upper(strtrim(string(localObjectValue(pdsch, "MappingType", ""))));
    if strlength(pdschMap) > 0 && pdschMap ~= grantMap
        error("sixgr:phy:dl:PDSCHGrantMappingMismatch", ...
            "PDSCH MappingType '%s' does not match frozen PHYGrant '%s'.", char(pdschMap), char(grantMap));
    end
end
end

function rv = localResolvePDSCHRV(cfg, optRV, phyGrant, hasPHYGrant)
if ~isempty(optRV)
    rv = double(optRV(:).');
elseif hasPHYGrant
    rv = localFirstFiniteVectorValue(sixgr.util.structGet(phyGrant, "HARQProcessKey.RVPerCodeword", []), ...
        sixgr.util.structGet(phyGrant, "HARQProcessKey.RV", []), ...
        sixgr.util.structGet(phyGrant, "CodingLayout.RV", []), ...
        sixgr.util.structGet(cfg, "phy.pdsch.rv", []), 0);
else
    rv = double(sixgr.util.structGet(cfg, 'phy.pdsch.rv', 0));
    rv = rv(:).';
end
if isempty(rv) || any(~isfinite(rv) | rv < 0 | abs(rv - round(rv)) > 1e-9)
    error("sixgr:phy:dl:PDSCHBadRV", "PDSCH RV must contain integer values in [0,3].");
end
rv = round(rv);
if any(rv > 3)
    error("sixgr:phy:dl:PDSCHBadRV", "PDSCH RV must be in [0,3].");
end
end

function targetCodeRate = localResolvePDSCHTargetCodeRate(cfg, optRate, phyGrant, hasPHYGrant)
grantRate = NaN;
if hasPHYGrant
    grantRate = double(sixgr.util.structGet(phyGrant, "CodingLayout.TargetCodeRatePerCodeword", ...
        sixgr.util.structGet(phyGrant, "CodingLayout.TargetCodeRate", NaN)));
end
if ~isempty(grantRate) && all(isfinite(grantRate(:)) & grantRate(:) > 0)
    if ~isempty(optRate) && ~isequal(size(double(optRate(:).')), size(grantRate(:).')) || ...
            (~isempty(optRate) && any(abs(double(optRate(:).') - grantRate(:).') > 1e-12))
        error("sixgr:phy:dl:PDSCHGrantCodeRateMismatch", ...
            "TargetCodeRate %s does not match frozen PHYGrant %s.", mat2str(double(optRate(:).')), mat2str(grantRate(:).'));
    end
    targetCodeRate = grantRate(:).';
elseif ~isempty(optRate)
    targetCodeRate = double(optRate(:).');
else
    targetCodeRate = double(sixgr.util.structGet(cfg, 'phy.pdsch.codeRate', 0.4785));
    targetCodeRate = targetCodeRate(:).';
end
if isempty(targetCodeRate) || any(~isfinite(targetCodeRate) | targetCodeRate <= 0 | targetCodeRate >= 1)
    error("sixgr:phy:dl:PDSCHBadCodeRate", "PDSCH TargetCodeRate must be finite in (0,1).");
end
end

function xOverhead = localResolvePDSCHXOverheadExact(cfg, optXOverhead, phyGrant, hasPHYGrant, pdsch)
grantXOverhead = NaN;
if hasPHYGrant
    grantXOverhead = double(sixgr.util.structGet(phyGrant, "CodingLayout.XOverhead", NaN));
end
if isfinite(grantXOverhead) && grantXOverhead >= 0
    if ~isempty(optXOverhead) && abs(double(optXOverhead) - grantXOverhead) > 1e-12
        error("sixgr:phy:dl:PDSCHGrantXOverheadMismatch", ...
            "XOverhead %.15g does not match frozen PHYGrant %.15g.", double(optXOverhead), grantXOverhead);
    end
    xOverhead = grantXOverhead;
elseif ~isempty(optXOverhead)
    xOverhead = double(optXOverhead);
else
    xOverhead = sixgr.phy.dl.resolvePDSCHXOverhead(cfg, ...
        localObjectValue(pdsch, "SymbolAllocation", []));
end
if ~(isscalar(xOverhead) && isfinite(xOverhead) && xOverhead >= 0)
    error("sixgr:phy:dl:PDSCHBadXOverhead", "PDSCH XOverhead must be finite and non-negative.");
end
end

function [trBlkSize, scheduledTrBlkSize, source] = localResolvePDSCHTransportBlockSize( ...
    overrideTBS, phyGrant, hasPHYGrant, pdsch, nPRB, nrePerPRB, targetCodeRate, xOverhead)
scheduledTrBlkSize = double(nrTBS(pdsch.Modulation, pdsch.NumLayers, nPRB, nrePerPRB, targetCodeRate, xOverhead));
grantTBS = NaN;
if hasPHYGrant
    grantTBS = double(sixgr.util.structGet(phyGrant, "CodingLayout.TBSBitsPerCodeword", ...
        sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", NaN)));
end
if ~isempty(grantTBS) && all(isfinite(grantTBS(:)) & grantTBS(:) > 0)
    trBlkSize = round(double(grantTBS(:).'));
    isHARQRetx = logical(sixgr.util.structGet(phyGrant, "HARQProcessKey.IsRetransmission", false));
    % An override that echoes the frozen grant is not independent evidence.
    % It must not suppress exact nrTBS validation of a new-data grant.
    if ~isHARQRetx && ...
            (numel(trBlkSize) ~= numel(scheduledTrBlkSize) || any(abs(double(scheduledTrBlkSize(:).') - double(trBlkSize)) > 1e-9))
        error("sixgr:phy:dl:PDSCHGrantTBSMismatch", ...
            "Frozen PHYGrant TBS=%s does not match exact nrTBS=%s for the materialized allocation. HARQ retx flag=%d RV=%s NDI=%s. Check mac.scheduler.fastNREApprox / tbsMode on the scenario that produced this grant.", ...
            mat2str(trBlkSize), mat2str(round(double(scheduledTrBlkSize(:).'))), ...
            logical(isHARQRetx), ...
            mat2str(double(sixgr.util.structGet(phyGrant, "HARQProcessKey.RV", NaN))), ...
            mat2str(double(sixgr.util.structGet(phyGrant, "HARQProcessKey.NDI", NaN))));
    end
    if ~isempty(overrideTBS) && ~isequal(round(double(overrideTBS(:).')), trBlkSize)
        error("sixgr:phy:dl:PDSCHReplayTBSMismatch", ...
            "TransportBlockSizeOverride=%s does not match frozen PHYGrant TBS=%s.", ...
            mat2str(round(double(overrideTBS(:).'))), mat2str(trBlkSize));
    end
    if isHARQRetx
        source = 'frozen_phygrant_harq_original_transport_block_size';
    else
        source = 'frozen_phygrant_transport_block_size';
    end
elseif ~isempty(overrideTBS)
    trBlkSize = round(double(overrideTBS(:).'));
    source = 'harq_replay_stored_transport_block';
elseif hasPHYGrant
    trBlkSize = round(double(scheduledTrBlkSize(:).'));
    source = 'nrTBS_from_frozen_phygrant_resource_accounting';
else
    trBlkSize = round(double(scheduledTrBlkSize(:).'));
    source = 'nrTBS_from_current_allocation';
end
scheduledTrBlkSize = round(double(scheduledTrBlkSize(:).'));
if isempty(trBlkSize) || ~all(isfinite(trBlkSize) & trBlkSize > 0 & abs(trBlkSize - round(trBlkSize)) < 1e-9)
    error('PDSCH_Tx:BadReplayTBSize', 'PDSCH transport block size must be a positive finite integer.');
end
end

function codingLayouts = localResolveTxCodingLayouts(phyGrant, hasPHYGrant, trBlkSize, targetCodeRate, rv, modulationPerCodeword, pdsch, GPerCodeword)
nCodewords = numel(GPerCodeword);
layerCounts = localLayerCountPerCodeword(double(pdsch.NumLayers), nCodewords);
codingLayouts = cell(1, nCodewords);
for c = 1:nCodewords
    layout = sixgr.phy.phycode.resolveCodingLayout( ...
        "Direction", "DL", ...
        "TransportBlockSize", double(trBlkSize(c)), ...
        "TargetCodeRate", double(targetCodeRate(c)), ...
        "RV", double(rv(c)), ...
        "Modulation", modulationPerCodeword{c}, ...
        "NumLayers", double(layerCounts(c)), ...
        "RateMatchedBitCount", double(GPerCodeword(c)));
    layout.CodewordIndex = uint8(c);
    layout.NumCodewords = uint8(nCodewords);
    layout.PDSCHNumLayers = uint8(pdsch.NumLayers);
    layout.CodewordLayerCount = uint8(layerCounts(c));
    layout.CodewordLayerCountPerCodeword = uint8(layerCounts);
    codingLayouts{c} = layout;
end
if hasPHYGrant
    localAssertCodingLayoutMatchesGrant(codingLayouts{1}, phyGrant);
end
end

function localAssertCodingLayoutMatchesGrant(codingLayout, phyGrant)
cl = sixgr.util.structGet(phyGrant, "CodingLayout", struct());
localAssertSameScalar(double(codingLayout.A), sixgr.util.structGet(cl, "TBSBits", NaN), ...
    "sixgr:phy:dl:PDSCHCodingGrantTBSMismatch", "Canonical CodingLayout A does not match frozen PHYGrant TBSBits.");
layoutTotalLayers = double(sixgr.util.structGet(codingLayout, "PDSCHNumLayers", double(codingLayout.NumLayers)));
localAssertSameScalar(layoutTotalLayers, sixgr.util.structGet(cl, "NumLayers", NaN), ...
    "sixgr:phy:dl:PDSCHCodingGrantLayerMismatch", "Canonical CodingLayout NumLayers does not match frozen PHYGrant.");
grantE = double(sixgr.util.structGet(cl, "RateMatchedBitCount", NaN));
if isfinite(grantE)
    localAssertSameScalar(double(codingLayout.RateMatchedBitCount), grantE, ...
        "sixgr:phy:dl:PDSCHCodingGrantGMismatch", "Canonical CodingLayout G does not match frozen PHYGrant.");
end
grantMod = string(sixgr.util.structGet(cl, "Modulation", ""));
if strlength(strtrim(grantMod)) > 0 && upper(strtrim(string(codingLayout.Modulation))) ~= upper(strtrim(grantMod))
    error("sixgr:phy:dl:PDSCHCodingGrantModulationMismatch", ...
        "Canonical CodingLayout modulation '%s' does not match frozen PHYGrant '%s'.", ...
        char(string(codingLayout.Modulation)), char(grantMod));
end
end

function localAssertPDSCHResourceAccounting(resourceAccounting, pdsch, fixedReferenceMode)
requiredInts = ["LayerDataRE", "PortMappedRE", "ModulationSymbolCount", "CodedBitCountG", "NREPerPRBForTBS"];
for i = 1:numel(requiredInts)
    name = char(requiredInts(i));
    value = double(resourceAccounting.(name));
    if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
        error("sixgr:phy:dl:PDSCHResourceAccountingBadInteger", ...
            "PDSCH resource accounting field %s must be a positive integer. Got %.15g.", name, value);
    end
end
if ~logical(resourceAccounting.GMatchesLayerRE)
    error("sixgr:phy:dl:PDSCHResourceAccountingGMismatch", ...
        "PDSCH G=%d does not equal LayerDataRE=%d * Qm=%d * NumLayers=%d.", ...
        round(double(resourceAccounting.CodedBitCountG)), round(double(resourceAccounting.LayerDataRE)), ...
        round(double(resourceAccounting.Qm)), round(double(resourceAccounting.NumLayers)));
end
if logical(fixedReferenceMode) && ~logical(resourceAccounting.DisjointMasks)
    error("sixgr:phy:dl:PDSCHResourceAccountingOverlap", ...
        "PDSCH frozen grant has overlapping or duplicate data/DMRS/PTRS/reserved RE masks. OverlapCount=%d.", ...
        round(double(resourceAccounting.OverlapCount)));
end
if round(double(resourceAccounting.NumLayers)) ~= round(double(pdsch.NumLayers))
    error("sixgr:phy:dl:PDSCHResourceAccountingLayerMismatch", ...
        "PDSCH resource accounting NumLayers=%d but pdsch.NumLayers=%d.", ...
        round(double(resourceAccounting.NumLayers)), round(double(pdsch.NumLayers)));
end
end

function mapping = localBuildPDSCHCodewordLayerContract(pdsch, codewords, codingLayouts, resourceAccounting)
nLayers = localPositiveIntegerValue(localObjectValue(pdsch, "NumLayers", 1), "PDSCH.NumLayers");
nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers);
localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
if numel(codewords) ~= nCodewords || numel(codingLayouts) ~= nCodewords
    error("sixgr:phy:dl:PDSCHCodewordContainerMismatch", ...
        "PDSCH codeword/coding-layout container count must equal NumCodewords=%d. Got %d codeword(s), %d layout(s).", ...
        nCodewords, numel(codewords), numel(codingLayouts));
end
rateBits = zeros(1, nCodewords);
layoutBits = zeros(1, nCodewords);
for c = 1:nCodewords
    rateBits(c) = double(numel(codewords{c}));
    layoutBits(c) = double(codingLayouts{c}.RateMatchedBitCount);
end
layerCountPerCodeword = localLayerCountPerCodeword(nLayers, nCodewords);
[codewordIndexByLayer, layerIndexWithinCodeword] = localCodewordLayerIndexMap(layerCountPerCodeword);
mapping = struct();
mapping.ContractVersion = "PDSCHCodewordLayer/v2";
mapping.Direction = "DL";
mapping.MappingStandard = "3GPP_TS_38_211_codeword_to_layer_mapping";
mapping.MappingEngine = "nrPDSCH_internal_nrLayerMap";
mapping.InverseEngine = "nrPDSCHDecode_internal_nrLayerDemap";
mapping.SupportedScope = "single_codeword_ranks_1_to_4_and_two_codeword_ranks_5_to_8";
mapping.UnsupportedScope = "";
mapping.NumCodewords = double(nCodewords);
mapping.NumLayers = double(nLayers);
mapping.GrantNumLayers = double(nLayers);
mapping.CodewordIndexByLayer = double(codewordIndexByLayer);
mapping.CodewordIndexBase = 0;
mapping.LayerIndexWithinCodeword = double(layerIndexWithinCodeword);
mapping.LayerCountPerCodeword = double(layerCountPerCodeword);
mapping.RateMatchedBitCountPerCodeword = double(rateBits);
mapping.CodingLayoutRateMatchedBitCountPerCodeword = double(layoutBits);
mapping.ResourceAccountingG = double(resourceAccounting.CodedBitCountG);
mapping.ExpectedLayerDataRE = double(resourceAccounting.LayerDataRE);
mapping.ExpectedLayerSymbolCount = double(resourceAccounting.LayerDataRE) * double(nLayers);
mapping.ActualLayerColumns = NaN;
mapping.ActualLayerSymbolCount = NaN;
mapping.ActualLayersEqualGrantLayers = false;
mapping.LayerColumnEnergy = NaN(1, nLayers);
mapping.AllLayerStreamsNonzero = false;
mapping.Equation = "b_G_c_to_QAM_d_c_to_layers_S_using_TS38211_7_3_1_3_then_ports_X_equals_S_times_W_transpose";
end

function mapping = localFinalizePDSCHCodewordLayerContract(mapping, layerSym)
if isempty(layerSym)
    nCols = 0;
    energy = zeros(1, 0);
else
    if isvector(layerSym)
        layerSym2D = layerSym(:);
    else
        layerSym2D = layerSym;
    end
    nCols = size(layerSym2D, 2);
    energy = sum(abs(layerSym2D).^2, 1);
end
mapping.ActualLayerColumns = double(nCols);
mapping.ActualLayerSymbolCount = double(numel(layerSym));
mapping.ActualLayersEqualGrantLayers = logical(nCols == double(mapping.NumLayers));
mapping.LayerColumnEnergy = double(energy);
mapping.AllLayerStreamsNonzero = logical(~isempty(energy) && all(energy > 0));
end

function nCodewords = localResolvePDSCHNumCodewords(pdsch, nLayers)
nCodewords = 1 + (double(nLayers) > 4);
raw = localObjectValue(pdsch, "NumCodewords", []);
if ~isempty(raw)
    nCodewords = double(raw);
end
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1 && abs(nCodewords - round(nCodewords)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadCodewordCount", "PDSCH NumCodewords must be a positive integer scalar.");
end
nCodewords = round(nCodewords);
end

function localAssertPDSCHCodewordLayerScope(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nLayers < 1 || nLayers > 8
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH supports ranks 1-8 in this truth path. Requested NumLayers=%d.", nLayers);
end
expected = 1 + double(nLayers > 4);
if nCodewords ~= expected
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d requires NumCodewords=%d by TS 38.211 codeword-to-layer mapping. Requested %d.", ...
        nLayers, expected, nCodewords);
end
end

function counts = localLayerCountPerCodeword(nLayers, nCodewords)
nLayers = round(double(nLayers));
nCodewords = round(double(nCodewords));
if nCodewords == 1
    counts = double(nLayers);
    return;
end
switch nLayers
    case 5
        counts = [2 3];
    case 6
        counts = [3 3];
    case 7
        counts = [3 4];
    case 8
        counts = [4 4];
    otherwise
        error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
            "Two-codeword PDSCH mapping is defined here only for ranks 5-8. Requested rank %d.", nLayers);
end
if numel(counts) ~= nCodewords
    error("sixgr:phy:dl:PDSCHCodewordLayerScope", ...
        "PDSCH rank-%d maps to %d codeword layer groups, not %d.", nLayers, numel(counts), nCodewords);
end
end

function [cwByLayer, layerInCw] = localCodewordLayerIndexMap(layerCountPerCodeword)
cwByLayer = zeros(1, sum(layerCountPerCodeword));
layerInCw = zeros(1, sum(layerCountPerCodeword));
pos = 1;
for c = 1:numel(layerCountPerCodeword)
    n = double(layerCountPerCodeword(c));
    idx = pos:(pos + n - 1);
    % TS 38.211 7.3.1: physical q is zero-based; c indexes MATLAB cells.
    cwByLayer(idx) = c - 1;
    layerInCw(idx) = 1:n;
    pos = pos + n;
end
end

function values = localExpandPerCodewordDouble(values, nCodewords, name)
values = double(values(:).');
if numel(values) ~= nCodewords || any(~isfinite(values))
    error("sixgr:phy:dl:PDSCHBadPerCodewordVector", ...
        "%s must contain exactly NumCodewords=%d explicit values.", ...
        char(string(name)), nCodewords);
end
end

function values = localExpandPerCodewordInteger(values, nCodewords, name)
values = localExpandPerCodewordDouble(values, nCodewords, name);
if any(abs(values - round(values)) > 1e-9)
    error("sixgr:phy:dl:PDSCHBadPerCodewordVector", ...
        "%s must contain integer values.", char(string(name)));
end
values = round(values);
end

function rv = localExpandPerCodewordRV(rv, nCodewords)
rv = localExpandPerCodewordInteger(rv, nCodewords, "PDSCH RV");
if any(rv < 0 | rv > 3)
    error("sixgr:phy:dl:PDSCHBadRV", "PDSCH RV must be in [0,3].");
end
end

function bits = localResolveRateMatchedBitsPerCodeword(resourceAccounting, nCodewords)
bits = double(sixgr.util.structGet(resourceAccounting, "CodedBitCountGPerCodeword", []));
bits = bits(:).';
if isempty(bits)
    bits = double(sixgr.util.structGet(resourceAccounting, "GPerCodeword", []));
    bits = bits(:).';
end
if isempty(bits)
    bits = double(sixgr.util.structGet(resourceAccounting, "CodedBitCountG", NaN));
end
bits = localExpandPerCodewordInteger(bits, nCodewords, "PDSCH G per codeword");
if any(bits <= 0)
    error("sixgr:phy:dl:PDSCHBadRateMatchedBitCount", ...
        "PDSCH per-codeword G must be positive. Got %s.", mat2str(bits));
end
end

function mods = localPDSCHModulationPerCodeword(pdsch, nCodewords)
raw = localObjectValue(pdsch, "Modulation", "");
tokens = string(raw);
tokens = tokens(:).';
if isempty(tokens) || any(strlength(strtrim(tokens)) == 0) ...
        || numel(tokens) ~= nCodewords
    error("sixgr:phy:dl:PDSCHMissingCodewordSpecificModulation", ...
        "PDSCH Modulation must contain exactly NumCodewords=%d " + ...
        "nonempty explicit tokens.", nCodewords);
end
normalized = upper(strrep(strtrim(tokens), " ", ""));
supported = ["QPSK","16QAM","64QAM","256QAM","1024QAM"];
if any(~ismember(normalized, supported))
    bad = normalized(find(~ismember(normalized, supported), 1));
    error("sixgr:pdsch:UnsupportedNRModulation", ...
        "Unsupported strict NR PDSCH modulation '%s'.", bad);
end
mods = cellstr(normalized);
end

function text = localModulationText(raw)
if iscell(raw)
    tokens = string(raw);
else
    tokens = string(raw);
end
tokens = tokens(:).';
tokens = tokens(strlength(strtrim(tokens)) > 0);
if isempty(tokens)
    text = "";
else
    text = strjoin(tokens, "|");
end
end

function trBlkCell = localResolvePDSCHTransportBlockBits(rawBits, trBlkSize)
nCodewords = numel(trBlkSize);
trBlkCell = cell(1, nCodewords);
if isempty(rawBits)
    for c = 1:nCodewords
        trBlkCell{c} = int8(randi([0 1], trBlkSize(c), 1));
    end
    return;
end
if iscell(rawBits)
    if numel(rawBits) ~= nCodewords
        error("PDSCH_Tx:BadTBSize", ...
            "TransportBlockBits cell count %d does not match NumCodewords=%d.", numel(rawBits), nCodewords);
    end
    for c = 1:nCodewords
        trBlkCell{c} = int8(rawBits{c}(:));
        if numel(trBlkCell{c}) ~= trBlkSize(c)
            error("PDSCH_Tx:BadTBSize", ...
                "TransportBlockBits{%d} length %d does not match expected TBS %d.", ...
                c, numel(trBlkCell{c}), trBlkSize(c));
        end
    end
    return;
end
rawBits = int8(rawBits(:));
if nCodewords == 1
    trBlkCell{1} = rawBits;
    if numel(trBlkCell{1}) ~= trBlkSize(1)
        error("PDSCH_Tx:BadTBSize", ...
            "TransportBlockBits length %d does not match expected TBS %d.", numel(rawBits), trBlkSize(1));
    end
    return;
end
if numel(rawBits) ~= sum(trBlkSize)
    error("PDSCH_Tx:BadTBSize", ...
        "Concatenated TransportBlockBits length %d does not match expected sum(TBS) %d for %d codewords.", ...
        numel(rawBits), sum(trBlkSize), nCodewords);
end
offset = 0;
for c = 1:nCodewords
    idx = offset + (1:trBlkSize(c));
    trBlkCell{c} = rawBits(idx);
    offset = offset + trBlkSize(c);
end
end

function localAssertPDSCHLayerSymbolContract(codewords, pdschSym, pdschInd, resourceAccounting, pdsch, codingLayouts, codewordLayerMapping)
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
if numel(codewords) ~= double(codewordLayerMapping.NumCodewords)
    error("sixgr:phy:dl:PDSCHCodewordCountContract", ...
        "PDSCH emitted %d codeword(s), but the mapping contract requires %d.", ...
        numel(codewords), round(double(codewordLayerMapping.NumCodewords)));
end
rateMatchedBits = zeros(1, numel(codewords));
for c = 1:numel(codewords)
    rateMatchedBits(c) = numel(codewords{c});
    if numel(codewords{c}) ~= double(codingLayouts{c}.RateMatchedBitCount)
        error("sixgr:phy:dl:PDSCHCodewordCodingLayoutContract", ...
            "PDSCH codeword %d length %d does not match CodingLayout RateMatchedBitCount=%d.", ...
            c, numel(codewords{c}), round(double(codingLayouts{c}.RateMatchedBitCount)));
    end
end
if sum(rateMatchedBits) ~= double(resourceAccounting.CodedBitCountG)
    error("sixgr:phy:dl:PDSCHCodewordGContract", ...
        "PDSCH total codeword length %d does not match resource-accounting G=%d.", ...
        sum(rateMatchedBits), round(double(resourceAccounting.CodedBitCountG)));
end
expectedLayerSymbols = double(resourceAccounting.LayerDataRE) * double(pdsch.NumLayers);
if numel(pdschSym) ~= expectedLayerSymbols
    error("sixgr:phy:dl:PDSCHLayerSymbolCountContract", ...
        "PDSCH layer symbol count %d does not equal LayerDataRE=%d * NumLayers=%d.", ...
        numel(pdschSym), round(double(resourceAccounting.LayerDataRE)), round(double(pdsch.NumLayers)));
end
if numel(pdschInd) ~= expectedLayerSymbols
    error("sixgr:phy:dl:PDSCHLayerIndexCountContract", ...
        "PDSCH layer index cell count %d does not equal layer symbol count %d.", ...
        numel(pdschInd), expectedLayerSymbols);
end
if double(codewordLayerMapping.ActualLayerColumns) ~= double(pdsch.NumLayers)
    error("sixgr:phy:dl:PDSCHLayerColumnContract", ...
        "PDSCH actual layer columns %d do not match grant NumLayers=%d.", ...
        round(double(codewordLayerMapping.ActualLayerColumns)), round(double(pdsch.NumLayers)));
end
if double(pdsch.NumLayers) > 1 && ~logical(codewordLayerMapping.AllLayerStreamsNonzero)
    error("sixgr:phy:dl:PDSCHLayerStreamEnergyContract", ...
        "PDSCH rank-%d transmission must materialize nonzero symbols on every layer stream.", ...
        round(double(pdsch.NumLayers)));
end
end

function localAssertPortDomainContract(layerSym, layerInd, portSym, portInd, resourceAccounting, prec)
if numel(layerInd) ~= numel(layerSym)
    error("sixgr:phy:dl:PDSCHLayerDomainMismatch", ...
        "PDSCH layer-domain index count %d does not match symbol count %d.", numel(layerInd), numel(layerSym));
end
if numel(portInd) ~= numel(portSym)
    error("sixgr:phy:dl:PDSCHPortDomainMismatch", ...
        "PDSCH port-domain index count %d does not match symbol count %d.", numel(portInd), numel(portSym));
end
if logical(prec.Active)
    expectedPortSymbols = double(resourceAccounting.LayerDataRE) * double(prec.NumPorts);
else
    expectedPortSymbols = numel(layerSym);
end
if numel(portSym) ~= expectedPortSymbols
    error("sixgr:phy:dl:PDSCHPortSymbolCountContract", ...
        "PDSCH port symbol count %d does not match expected port-domain count %d.", ...
        numel(portSym), round(double(expectedPortSymbols)));
end
end

function localAssertSignalResourceDisjoint(dataInd, dmrsInd, ptrsInd)
checks = {dataInd, "data"; dmrsInd, "dmrs"; ptrsInd, "ptrs"};
for i = 1:size(checks, 1)
    raw = double(checks{i, 1}(:));
    if numel(raw) ~= numel(unique(raw))
        error("sixgr:phy:dl:PDSCHDuplicateMappedRE", ...
            "PDSCH %s indices contain duplicate port-domain RE.", char(checks{i, 2}));
    end
end
dataSet = localIndexSet(dataInd);
dmrsSet = localIndexSet(dmrsInd);
ptrsSet = localIndexSet(ptrsInd);
if ~isempty(intersect(dataSet, dmrsSet))
    error("sixgr:phy:dl:PDSCHDataDMRSOverlap", "PDSCH data and DMRS port-domain RE overlap.");
end
if ~isempty(intersect(dataSet, ptrsSet))
    error("sixgr:phy:dl:PDSCHDataPTRSOverlap", "PDSCH data and PTRS port-domain RE overlap.");
end
if ~isempty(intersect(dmrsSet, ptrsSet))
    error("sixgr:phy:dl:PDSCHDMRSPTRSOverlap", "PDSCH DMRS and PTRS port-domain RE overlap.");
end
end

function powerInfo = localBuildPrecodePowerInfo(layerSym, portSym, prec)
W = double(prec.MatrixPorts);
if isempty(W)
    W = eye(max(1, round(double(prec.NumLayers))));
end
columnNorms = sqrt(sum(abs(W).^2, 1));
gram = W' * W;
identityRef = eye(size(gram));
layerEnergy = sum(abs(layerSym(:)).^2);
portEnergy = sum(abs(portSym(:)).^2);
powerInfo = struct();
powerInfo.ContractVersion = "PDSCHPrecodePower/v1";
powerInfo.NormalizeW = logical(prec.NormalizeW);
powerInfo.NumLayers = double(prec.NumLayers);
powerInfo.NumPorts = double(prec.NumPorts);
powerInfo.ColumnNorms = double(columnNorms);
powerInfo.ColumnNormMaxError = double(max(abs(columnNorms(:) - 1), [], "omitnan"));
powerInfo.OrthonormalColumnMaxError = double(max(abs(gram(:) - identityRef(:)), [], "omitnan"));
powerInfo.LayerTotalEnergy = double(layerEnergy);
powerInfo.PortTotalEnergy = double(portEnergy);
powerInfo.TotalEnergyDelta = double(portEnergy - layerEnergy);
powerInfo.TotalPowerMaxAbsError = double(abs(portEnergy - layerEnergy));
powerInfo.TotalPowerRelativeError = double(abs(portEnergy - layerEnergy) / max(layerEnergy, eps));
powerInfo.Equation = "X_equals_S_times_W_transpose";
end

function ctx = localBuildTxContext(tx, trBlk, tbCrc, codewords, txGrid, txWaveform, pdschInd, pdschSym, pdschAntInd, pdschAntSym, ...
    dmrsInd, dmrsSym, dmrsAntInd, dmrsAntSym, ptrsInd, ptrsSym, ptrsAntInd, ptrsAntSym, ...
    carrier, pdsch, codingLayouts, resourceAccounting, prec, precodePowerInfo, codewordLayerMapping, phyGrant, hasPHYGrant)
ctx = struct();
ctx.ContractVersion = "PDSCH_TxContext/v1";
ctx.GrantDriven = logical(hasPHYGrant);
ctx.GrantContextId = string(sixgr.util.structGet(phyGrant, "GrantContextId", ""));
if ~iscell(trBlk)
    trBlk = {trBlk};
end
if ~iscell(tbCrc)
    tbCrc = {tbCrc};
end
ctx.TransportBlocks = cell(size(trBlk));
ctx.TransportBlockCRCPerCodeword = cell(size(tbCrc));
for c = 1:numel(trBlk)
    ctx.TransportBlocks{c} = int8(trBlk{c}(:));
end
for c = 1:numel(tbCrc)
    ctx.TransportBlockCRCPerCodeword{c} = int8(tbCrc{c}(:));
end
ctx.TransportBlock = vertcat(ctx.TransportBlocks{:});
ctx.TransportBlockCRC = vertcat(ctx.TransportBlockCRCPerCodeword{:});
if ~iscell(codewords)
    codewords = {codewords};
end
if ~iscell(codingLayouts)
    codingLayouts = {codingLayouts};
end
ctx.Codewords = cell(size(codewords));
for c = 1:numel(codewords)
    ctx.Codewords{c} = int8(codewords{c}(:));
end
ctx.Codeword = ctx.Codewords{1};
ctx.CodingLayouts = codingLayouts;
ctx.CodingLayout = codingLayouts{1};
ctx.CodewordLayerMapping = codewordLayerMapping;
ctx.LayerSymbols = pdschSym;
ctx.LayerIndices = pdschInd;
ctx.PortSymbols = pdschAntSym;
ctx.PortIndices = pdschAntInd;
ctx.DMRSLayerSymbols = dmrsSym;
ctx.DMRSLayerIndices = dmrsInd;
ctx.DMRSPortSymbols = dmrsAntSym;
ctx.DMRSPortIndices = dmrsAntInd;
ctx.PTRSLayerSymbols = ptrsSym;
ctx.PTRSLayerIndices = ptrsInd;
ctx.PTRSPortSymbols = ptrsAntSym;
ctx.PTRSPortIndices = ptrsAntInd;
ctx.PortGrid = txGrid;
ctx.Waveform = txWaveform;
ctx.Precoder = prec.MatrixPorts;
ctx.Precoding = prec;
ctx.PowerNormalization = precodePowerInfo;
ctx.ResourceAccounting = resourceAccounting;
ctx.Carrier = struct( ...
    "NCellID", double(localObjectValue(carrier, "NCellID", NaN)), ...
    "NSizeGrid", double(localObjectValue(carrier, "NSizeGrid", NaN)), ...
    "SubcarrierSpacing", double(localObjectValue(carrier, "SubcarrierSpacing", NaN)), ...
    "CyclicPrefix", string(localObjectValue(carrier, "CyclicPrefix", "")), ...
    "NSlot", double(localObjectValue(carrier, "NSlot", NaN)));
ctx.PDSCH = struct( ...
    "PRBSet", double(localObjectValue(pdsch, "PRBSet", [])), ...
    "SymbolAllocation", double(localObjectValue(pdsch, "SymbolAllocation", [])), ...
    "MappingType", string(localObjectValue(pdsch, "MappingType", "")), ...
    "Modulation", string(localObjectValue(pdsch, "Modulation", "")), ...
    "NumLayers", double(localObjectValue(pdsch, "NumLayers", NaN)), ...
    "RNTI", double(localObjectValue(pdsch, "RNTI", NaN)), ...
    "NID", double(localObjectValue(pdsch, "NID", NaN)));
ctx.DimensionContract = struct( ...
    "LayerDataRE", double(resourceAccounting.LayerDataRE), ...
    "PortIndexCellCount", double(numel(pdschAntInd)), ...
    "QAMSymbolCount", double(numel(pdschSym)), ...
    "NumCodewords", double(codewordLayerMapping.NumCodewords), ...
    "ActualNumLayers", double(codewordLayerMapping.ActualLayerColumns), ...
    "RateMatchedBitCount", double(sum(cellfun(@numel, ctx.Codewords))), ...
    "RateMatchedBitCountPerCodeword", double(codewordLayerMapping.RateMatchedBitCountPerCodeword), ...
    "LayerIndexCellCount", double(numel(pdschInd)), ...
    "PortSymbolCount", double(numel(pdschAntSym)), ...
    "GridSize", double(size(txGrid)), ...
    "WaveformSize", double(size(txWaveform)));
if isfield(tx, "LayerSymbolOrder")
    ctx.LayerSymbolOrder = tx.LayerSymbolOrder;
end
if isfield(tx, "PortSymbolOrder")
    ctx.PortSymbolOrder = tx.PortSymbolOrder;
end
end

function value = localPositiveIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value > 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadInteger", "%s must be a positive integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localNonnegativeIntegerValue(raw, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value >= 0 && abs(value - round(value)) < 1e-9)
    error("sixgr:phy:dl:PDSCHBadInteger", "%s must be a non-negative integer scalar.", char(string(name)));
end
value = round(value);
end

function value = localFirstFiniteScalarValue(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
        continue;
    end
    raw = double(raw(:));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw(1);
        return;
    end
end
end

function value = localFirstFiniteVectorValue(varargin)
value = NaN;
for i = 1:nargin
    raw = varargin{i};
    if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
        continue;
    end
    raw = double(raw(:).');
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        value = raw;
        return;
    end
end
end

function localAssertSameVector(actual, expected, id, message)
expected = double(expected(:).');
actual = double(actual(:).');
if isempty(expected)
    return;
end
if numel(actual) ~= numel(expected) || any(abs(actual - expected) > 1e-9)
    error(id, "%s Actual=%s Expected=%s.", message, mat2str(actual), mat2str(expected));
end
end

function localAssertSameScalar(actual, expected, id, message)
actual = double(actual);
expected = double(expected);
if ~(isscalar(expected) && isfinite(expected))
    return;
end
if ~(isscalar(actual) && isfinite(actual) && abs(actual - expected) <= 1e-9)
    error(id, "%s Actual=%.15g Expected=%.15g.", message, actual, expected);
end
end

function localAssertRateMatchMapAgreement(rateMatchInfo, codingLayout)
txMap = sixgr.util.structGet(rateMatchInfo, "PositionMap", struct());
layoutMap = sixgr.util.structGet(codingLayout, "RateMatchPositionMap", struct());
txIdx = sixgr.util.structGet(txMap, "MotherCodeLinearIndex", []);
layoutIdx = sixgr.util.structGet(layoutMap, "MotherCodeLinearIndex", []);
if isempty(txIdx) || isempty(layoutIdx) || numel(txIdx) ~= numel(layoutIdx) || any(uint32(txIdx(:)) ~= uint32(layoutIdx(:)))
    error("sixgr:phy:dl:PDSCHCodingLayoutMapMismatch", ...
        "PDSCH rate-match position map does not match canonical CodingLayout.");
end
end

function localValidateSupportedCodewordScope(cfg, pdsch)
if isempty(pdsch)
    nLayers = double(sixgr.util.structGet(cfg, 'phy.pdsch.numLayers', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.nLayers', 1)));
    nCodewords = double(sixgr.util.structGet(cfg, 'phy.pdsch.numCodewords', ...
        sixgr.util.structGet(cfg, 'phy.pdsch.NumCodewords', 1 + (nLayers > 4))));
else
    try
        nLayers = double(pdsch.NumLayers);
    catch
        nLayers = 1;
    end
    nCodewords = double(localObjectValue(pdsch, "NumCodewords", 1 + (nLayers > 4)));
end
if ~(isscalar(nLayers) && isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
nLayers = round(nLayers);
if ~(isscalar(nCodewords) && isfinite(nCodewords) && nCodewords >= 1)
    nCodewords = 1 + (nLayers > 4);
end
nCodewords = round(nCodewords);
localAssertPDSCHCodewordLayerScope(nLayers, nCodewords);
end

function [tx, info] = localDelegateCanonicalGrantTransmitter( ...
        cfg, opt, phyGrant, hasPHYGrant, executionProfile)
cellCommonSignalOwnershipMode = localCellCommonSignalOwnershipMode( ...
    opt.CellCommonSignalOwnershipMode);
if ~any(executionProfile == ["phy_calibration","scheduler_truth"])
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        "Grant adapter received execution profile '%s'.", ...
        executionProfile);
end
if executionProfile == "scheduler_truth"
    localRequireSchedulerTruthGrantAdapterInputs( ...
        phyGrant, hasPHYGrant, opt.SchedulerGrantContext);
end
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions( ...
        phyGrant, "pdsch_tx_calibration_adapter_entry");
    cfg = sixgr.phy.grant.applyPHYGrantToConfig(cfg, phyGrant);
end
localValidateSupportedCodewordScope(cfg, opt.PDSCH);

if isempty(opt.Carrier)
    [carrier, carrierInfo] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
    carrierInfo = struct();
end
[~, pdschInfo, pdsch] = localResolvePDSCHMaterialization( ...
    carrier, cfg, opt, phyGrant, hasPHYGrant, false);
nCodewords = localResolvePDSCHNumCodewords( ...
    pdsch, round(double(pdsch.NumLayers)));
mcsOwnership = ...
    sixgr.pdsch.PDSCHCalibrationFacadeAdapter.resolveMCSOwnership( ...
        cfg, phyGrant, nCodewords);

rv = localResolvePDSCHRV(cfg, opt.RV, phyGrant, hasPHYGrant);
targetRate = localResolvePDSCHTargetCodeRate( ...
    cfg, opt.TargetCodeRate, phyGrant, hasPHYGrant);
xOverhead = localResolvePDSCHXOverheadExact( ...
    cfg, opt.XOverhead, phyGrant, hasPHYGrant, pdsch);
[~, dmrsPowerInfo] = localApplyPDSCHDMRSEPREDifference( ...
    complex(1), cfg);
[csirsInd, csirsSym, csirsInfo, csirsCfg, csirsEvent] = ...
    localGenerateCSIRSRuntimeResource(carrier, cfg);
reservedZeroBased = localCalibrationBasePlaneZeroBased( ...
    csirsInd, carrier, pdsch);
[isacReferenceGrid,isacReservedZeroBased]=localSanitizeISACReferenceGrid( ...
    opt.ISACReferenceGrid,carrier,pdsch);
if ~isempty(isacReservedZeroBased)
    pdsch.ReservedRE=unique([double(pdsch.ReservedRE(:)); ...
        double(isacReservedZeroBased(:))],"sorted");
end
reservedZeroBased=union(reservedZeroBased,isacReservedZeroBased,"sorted");

transportBlockSizes = opt.TransportBlockSizeOverride;
transportBlockSizeSource = "nrTBS_from_current_allocation";
if hasPHYGrant
    grantTBS = double(sixgr.util.structGet( ...
        phyGrant, "CodingLayout.TBSBitsPerCodeword", ...
        sixgr.util.structGet( ...
            phyGrant, "CodingLayout.TBSBits", [])));
    if ~isempty(grantTBS) && all(isfinite(grantTBS(:)) ...
            & grantTBS(:) > 0)
        grantTBS = round(double(grantTBS(:).'));
        if ~isempty(transportBlockSizes) ...
                && ~isequal(round(double( ...
                    transportBlockSizes(:).')), grantTBS)
            error("sixgr:phy:dl:PDSCHReplayTBSMismatch", ...
                "TransportBlockSizeOverride does not match the frozen " + ...
                "PHYGrant TBS.");
        end
        transportBlockSizes = grantTBS;
        if logical(sixgr.util.structGet( ...
                phyGrant, "HARQProcessKey.IsRetransmission", false))
            transportBlockSizeSource = ...
                "frozen_phygrant_harq_original_transport_block_size";
        else
            transportBlockSizeSource = ...
                "frozen_phygrant_transport_block_size";
        end
    end
elseif ~isempty(transportBlockSizes)
    transportBlockSizeSource = ...
        "harq_replay_stored_transport_block";
end

nRx = double(sixgr.util.structGet(cfg, ...
    "channel.nRxAnt", sixgr.util.structGet(cfg, "phy.nRxAnt", NaN)));
maxIterations = sixgr.phy.phycode.resolveLDPCMaxIterations( ...
    cfg, "Direction", "DL");
algorithm = char(string(sixgr.util.structGet( ...
    cfg, "phy.ldpc.algorithm", "Normalized min-sum")));
request = struct( ...
    "ExecutionProfile", executionProfile, ...
    "SchedulerGrantContext", opt.SchedulerGrantContext, ...
    "SchedulerPHYGrant", phyGrant, ...
    "TargetCodeRate", targetRate, ...
    "RV", rv, "XOverhead", xOverhead, ...
    "MCSTablePerCodeword", mcsOwnership.MCSTablePerCodeword, ...
    "MCSIndexPerCodeword", mcsOwnership.MCSIndexPerCodeword, ...
    "UECapability1024QAM", mcsOwnership.UECapability1024QAM, ...
    "RRCEnabled1024QAM", mcsOwnership.RRCEnabled1024QAM, ...
    "DCIEnabled1024QAM", mcsOwnership.DCIEnabled1024QAM, ...
    "DCIFormat", mcsOwnership.DCIFormat, ...
    "UECapability1024QAMVariant", ...
        mcsOwnership.UECapability1024QAMVariant, ...
    "MaxNumberMIMOLayersPDSCH", ...
        mcsOwnership.MaxNumberMIMOLayersPDSCH, ...
    "NumLayers", double(pdsch.NumLayers), ...
    "DeploymentAllows1024QAM", ...
        mcsOwnership.DeploymentAllows1024QAM, ...
    "FrequencyRange", mcsOwnership.FrequencyRange, ...
    "OperatingBand", mcsOwnership.OperatingBand, ...
    "DeploymentClass", mcsOwnership.DeploymentClass, ...
    "FrequencyRangeAllows1024QAM", ...
        mcsOwnership.FrequencyRangeAllows1024QAM, ...
    "BandAllows1024QAM", mcsOwnership.BandAllows1024QAM, ...
    "TransportBlockSizes", transportBlockSizes, ...
    "TransportBlockBits", {opt.TransportBlockBits}, ...
    "CodingPlans", [], ...
    "PrecodingMatrix", opt.PrecodingMatrix, ...
    "ReservedREZeroBased", reservedZeroBased, ...
    "DMRSAmplitudeScale", ...
        double(dmrsPowerInfo.DMRSAmplitudeScale), ...
    "DMRSPortResolutionPolicy", ...
        "explicit_calibration_rank_order_ports", ...
    "NPhysicalRxAntennas", nRx, ...
    "NoiseVariance", [], "NoiseVarianceDomain", "grid", ...
    "MaxIterations", maxIterations, ...
    "Algorithm", algorithm);
bundle = sixgr.pdsch.PDSCHCalibrationFacadeAdapter.materialize( ...
    cfg, carrier, pdsch, request);
if hasPHYGrant
    localAssertFrozenGrantTBSMatchesMaterializedAllocation( ...
        phyGrant, bundle.ScheduledTransportBlockSizes);
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pdsch_tx_after_materialization", "PDSCH", pdsch, ...
        "Precoding", bundle.LegacyPrecoder, ...
        "NumTxAnt", double(bundle.ReferenceConfig.get("NPhysicalTxAntennas")));
end

canonical = sixgr.pdsch.PDSCHTransmitter( ...
    localUnwrapCanonicalBlocks(bundle.TransportBlocks), ...
    bundle.Assignment, bundle.ResourcePlan, bundle.Carrier, ...
    bundle.ReferenceConfig, ...
    "PrecoderBundle", bundle.PrecoderBundle, ...
    "Nref", opt.Nref);
    if logical(sixgr.util.structGet( ...
        csirsEvent, "Scheduled", false)) && ~isempty(csirsInd) && ...
            cellCommonSignalOwnershipMode == "emit"
        [canonical, csirsEvent] = localMapCalibrationCSIRS( ...
            canonical, csirsInd, csirsSym, csirsInfo, csirsEvent, cfg, ...
            bundle.PrecoderBundle);
    elseif logical(sixgr.util.structGet( ...
            csirsEvent, "Scheduled", false)) && ~isempty(csirsInd)
        % CSI-RS remains reserved while materializing a user-dedicated
        % PDSCH component.  The serving-cell common plane is emitted once
        % by the victim/base waveform; repeating it in every peer component
        % creates a non-3GPP duplicate transmission outside the frozen MU
        % precoder and corrupts sample-domain superposition.
        csirsEvent.Transmitted = false;
        csirsEvent.RuntimeMaterializationStatus = ...
            "reserved_only_serving_cell_common_plane_owned_elsewhere";
        csirsEvent.UpdateOutcome = ...
            "reserved_not_duplicated_in_user_dedicated_component";
        csirsEvent.RuntimeEvidenceSource = ...
            "sixgr.phy.dl.PDSCH_Tx:shared_slot_cell_common_signal_ownership";
    end
    [canonical,isacEvent]=localMapISACReferenceGrid(canonical,isacReferenceGrid);
    csirsEvent.CellCommonSignalOwnershipMode = ...
        char(cellCommonSignalOwnershipMode);
[tx, info] = localAdaptCanonicalCalibrationTX( ...
    canonical, bundle, pdschInfo, carrierInfo, ...
    dmrsPowerInfo, csirsInd, csirsSym, csirsInfo, ...
    csirsCfg, csirsEvent, transportBlockSizeSource, ...
    phyGrant, hasPHYGrant, logical(opt.CompactOutput));
tx.ISACReferenceGrid=isacReferenceGrid;
tx.ISACReferenceEvent=isacEvent;
info.ISACReferenceEvent=isacEvent;
if hasPHYGrant
    sixgr.phy.grant.assertPHYGrantDimensions(phyGrant, ...
        "pdsch_tx_after_waveform", "PDSCH", pdsch, ...
        "Precoding", bundle.LegacyPrecoder, ...
        "NumTxAnt", double(bundle.ReferenceConfig.get("NPhysicalTxAntennas")), ...
        "Grid", tx.Grid, "Waveform", tx.Waveform, ...
        "AllowAuxiliaryWaveformColumns", true);
end
end

function mode = localCellCommonSignalOwnershipMode(raw)
mode = lower(strtrim(string(raw)));
if mode == ""
    mode = "emit";
end
if mode == "reserve_only"
    return;
end
if mode ~= "emit"
    error("sixgr:pdsch:InvalidCellCommonSignalOwnershipMode", ...
        "CellCommonSignalOwnershipMode must be 'emit' or 'reserve_only'; observed '%s'.", ...
        char(mode));
end
end

function localRequireSchedulerTruthGrantAdapterInputs( ...
        phyGrant, hasPHYGrant, grant)
if ~hasPHYGrant
    error("sixgr:pdsch:MissingSchedulerTruthPHYGrant", ...
        "scheduler_truth PDSCH requires a frozen exact PHYGrant.");
end
if ~(isstruct(grant) && isscalar(grant) && ~isempty(fieldnames(grant)))
    error("sixgr:pdsch:MissingSchedulerTruthGrantContext", ...
        "scheduler_truth PDSCH transmission requires the authored scheduler grant.");
end
if ~logical(sixgr.util.structGet(phyGrant, "IsFrozen", false))
    error("sixgr:pdsch:UnfrozenSchedulerTruthPHYGrant", ...
        "scheduler_truth PDSCH requires the immutable frozen PHYGrant produced after exact feasibility.");
end
end

function localAssertFrozenGrantTBSMatchesMaterializedAllocation( ...
        phyGrant, scheduledTBS)
grantTBS = double(sixgr.util.structGet( ...
    phyGrant, "CodingLayout.TBSBitsPerCodeword", ...
    sixgr.util.structGet(phyGrant, "CodingLayout.TBSBits", [])));
if isempty(grantTBS) || any(~isfinite(grantTBS(:)) ...
        | grantTBS(:) <= 0)
    return;
end
if logical(sixgr.util.structGet( ...
        phyGrant, "HARQProcessKey.IsRetransmission", false))
    return;
end
grantTBS = round(double(grantTBS(:).'));
scheduledTBS = round(double(scheduledTBS(:).'));
if numel(grantTBS) ~= numel(scheduledTBS) ...
        || any(grantTBS ~= scheduledTBS)
    error("sixgr:phy:dl:PDSCHGrantTBSMismatch", ...
        "Frozen PHYGrant TBS=%s does not match exact nrTBS=%s for the materialized allocation; an echoed TransportBlockSizeOverride is not independent TBS evidence.", ...
        mat2str(grantTBS), mat2str(scheduledTBS));
end
end

function value = localUnwrapCanonicalBlocks(blocks)
if numel(blocks) == 1
    value = blocks{1};
else
    value = blocks;
end
end

function indices = localCalibrationBasePlaneZeroBased(raw, carrier, pdsch)
if isempty(raw)
    indices = zeros(1,0);
    return;
end
plane = double(carrier.NSizeGrid) * 12 ...
    * double(carrier.SymbolsPerSlot);
raw = double(raw(:));
if any(~isfinite(raw) | raw ~= fix(raw) | raw < 1)
    error("sixgr:pdsch:InvalidReservedRE", ...
        "Auxiliary calibration indices must be positive one-based values.");
end
indices = unique(mod(raw - 1, plane), "sorted").';
prbs = double(pdsch.PRBSet(:).');
symbolAllocation = double(pdsch.SymbolAllocation(:).');
subcarriers = reshape(12 .* prbs + (0:11).',1,[]);
scheduledSymbols = symbolAllocation(1) ...
    + (0:(symbolAllocation(2)-1));
[k,l] = ndgrid(subcarriers,scheduledSymbols);
allocation = double(k(:) ...
    + 12 .* double(carrier.NSizeGrid) .* l(:));
indices = intersect(indices,allocation(:).',"stable");
end

function [referenceGrid,indices]=localSanitizeISACReferenceGrid(referenceGrid,carrier,pdsch)
if isempty(referenceGrid)
    indices=zeros(1,0); return;
end
K=double(carrier.NSizeGrid)*12; L=double(carrier.SymbolsPerSlot);
if size(referenceGrid,1)~=K || size(referenceGrid,2)~=L || ...
        any(~isfinite(referenceGrid),"all")
    error("sixgr:pdsch:InvalidISACReferenceGrid", ...
        "ISAC reference grid must be finite and have physical size [%d %d P].",K,L);
end
referenceIndices=[nrPDSCHDMRSIndices(carrier,pdsch);nrPDSCHPTRSIndices(carrier,pdsch)];
if ~isempty(referenceIndices)
    baseReference=unique(mod(double(referenceIndices(:))-1,K*L),"sorted")+1;
    for page=1:size(referenceGrid,3)
        pageGrid=referenceGrid(:,:,page);
        pageGrid(baseReference)=0;
        referenceGrid(:,:,page)=pageGrid;
    end
end
prbs=double(pdsch.PRBSet(:).'); symbols=double(pdsch.SymbolAllocation(:).');
subcarriers=reshape(12.*prbs+(0:11).',1,[]);
scheduled=symbols(1)+(0:symbols(2)-1);
[k,l]=ndgrid(subcarriers,scheduled);
allocation=k(:)+K*l(:);
allocationMask=false(K,L); allocationMask(double(allocation)+1)=true;
for page=1:size(referenceGrid,3)
    pageGrid=referenceGrid(:,:,page);
    pageGrid(~allocationMask)=0;
    referenceGrid(:,:,page)=pageGrid;
end
occupied=find(any(referenceGrid~=0,3))-1;
indices=double(occupied(:).');
end

function [canonical,event]=localMapISACReferenceGrid(canonical,referenceGrid)
event=struct("Enabled",false,"Transmitted",false,"NRE",0, ...
    "PhysicalPortCount",size(canonical.Grid,3),"GridSHA256","", ...
    "EvidenceClass","disabled");
if isempty(referenceGrid), return; end
grid=canonical.Grid; K=size(grid,1); L=size(grid,2); P=size(grid,3);
if size(referenceGrid,1)~=K || size(referenceGrid,2)~=L
    error("sixgr:pdsch:InvalidISACReferenceGrid", ...
        "ISAC reference grid does not match the production PDSCH carrier grid.");
end
if size(referenceGrid,3)==1 && P>1
    referenceGrid=repmat(referenceGrid,1,1,P)/sqrt(P);
elseif size(referenceGrid,3)~=P
    error("sixgr:pdsch:ISACReferencePortMismatch", ...
        "ISAC reference pages must be one or match %d physical transmit ports.",P);
end
mask=referenceGrid~=0;
if any(grid(mask)~=0)
    error("sixgr:pdsch:ISACReferenceResourceCollision", ...
        "The coded PDSCH resource plan did not reserve every occupied ISAC RE.");
end
grid(mask)=referenceGrid(mask);
ofdmOptions=canonical.ReferenceConfig.get("OFDMOptions");
[waveform,ofdmInfo]=sixgr.phy.waveform.ofdmModulate( ...
    canonical.Carrier,grid,ofdmOptions{:});
canonical.Grid=grid; canonical.Waveform=waveform; canonical.OFDMInfo=ofdmInfo;
event.Enabled=true; event.Transmitted=true; event.NRE=nnz(mask);
event.PhysicalPortCount=P;
event.GridSHA256=sixgr.util.sha256Hex(typecast( ...
    [real(referenceGrid(:));imag(referenceGrid(:))],"uint8"));
event.EvidenceClass="production_pdsch_reserved_and_transmitted_isac_grid_truth";
canonical.StageTrace=[canonical.StageTrace;table( ...
    "isac_reference_grid_mapping","PASS",nnz(mask), ...
    'VariableNames',canonical.StageTrace.Properties.VariableNames)];
end

function [canonical, event] = localMapCalibrationCSIRS( ...
        canonical, indices, symbols, info, event, cfg, dataPrecoderBundle)
grid = canonical.Grid;
plane = size(grid,1) * size(grid,2);
resources = sixgr.util.structGet(info, "Resources", []);
if isempty(resources)
    resources = struct("ResourceID", double(sixgr.util.structGet(event, "ResourceID", 0)), ...
        "Indices", indices, "Symbols", symbols);
end
precoders = sixgr.util.structGet(cfg, "phy.csirs.precoderMatrices", []);
strictCSI = logical(sixgr.util.structGet(cfg, "phy.mimo.strict", false));
if isempty(precoders)
    if strictCSI || numel(resources) > 1 || isempty(dataPrecoderBundle)
        error("sixgr:pdsch:MissingCSIRSPhysicalPrecoder", ...
            "Strict or multi-resource CSI-RS requires a YAML-materialized physical precoder matrix per resource.");
    end
    resource = resources(1);
    [logicalSymbols, baseIndices, prb, symbolNumber] = ...
        localCSIRSLogicalResourceMatrix(double(resource.Indices), ...
        complex(resource.Symbols), size(grid,1), size(grid,2), ...
        dataPrecoderBundle.NLayerPorts);
    if any(~ismember(prb, dataPrecoderBundle.PRBSet)) || ...
            any(~ismember(symbolNumber, dataPrecoderBundle.ScheduledSymbols))
        error("sixgr:pdsch:MissingCSIRSPhysicalPrecoder", ...
            ['CSI-RS occupies resources outside the scheduled PDSCH ' ...
             'precoder bundle. Configure reference_signals.' ...
             'csi_rs_precoder_codebook so CSI-RS has its own explicit ' ...
             'physical spatial filter.']);
    end
    if dataPrecoderBundle.NPhysicalTxAntennas ~= size(grid,3)
        error("sixgr:pdsch:CSIRSPrecoderDimensionMismatch", ...
            "The PDSCH precoder physical-port count does not match the waveform grid.");
    end
    [physicalSymbols, trace] = dataPrecoderBundle.apply( ...
        logicalSymbols, prb, symbolNumber, "Domain", "csirs");
    grid = localMapCSIRSPhysicalPortSymbols(grid, baseIndices, physicalSymbols);
    [waveformIndices, waveformSymbols] = localCSIRSPhysicalMapping( ...
        baseIndices, physicalSymbols, plane);
    resourceEvents = repmat(localEmptyMappedCSIRSResourceEvent(), 1, 1);
    resourceEvents(1).ResourceID = resources(1).ResourceID;
    resourceEvents(1).MappedRE = nnz(logicalSymbols);
    resourceEvents(1).PhysicalRE = numel(physicalSymbols);
    resourceEvents(1).PhysicalPortCount = size(grid,3);
    resourceEvents(1).WaveformPortCount = size(grid,3);
    resourceEvents(1).LogicalPortCount = dataPrecoderBundle.NLayerPorts;
    resourceEvents(1).PrecoderSource = "canonical_pdsch_precoder_bundle_shared_physical_chain";
    resourceEvents(1).PrecoderDigest = strjoin(unique(string(trace.AppliedMatrixDigest)), "|");
    resourceEvents(1).WaveformPrecoderDigest = resourceEvents(1).PrecoderDigest;
    resourceEvents(1).PortToElementMatrixDigest = ...
        sixgr.phy.mimo.MatrixContract.digest(eye(size(grid,3)));
    resourceEvents(1).PortProjectionSource = "shared_pdsch_grid_domain_identity";
    resourceEvents(1).PortProjectionResidual = 0;
    resourceEvents(1).PRBSpan = [min(prb) max(prb)];
    resourceEvents(1).SymbolSet = unique(symbolNumber(:)).';
    resourceEvents(1).MappingStatus = "physical_element_grid_mapped";
    resourceEvents(1).WaveformIndices = waveformIndices;
    resourceEvents(1).WaveformSymbols = waveformSymbols;
    resourceEvents(1).WaveformMappedRE = numel(waveformIndices);
else
    % MATLAB removes trailing singleton dimensions, so a one-resource
    % [Nphysical x Nlogical x 1] codebook is reported as a 2-D matrix.
    % Validate each semantic axis explicitly instead of using ndims().
    if size(precoders,3) ~= numel(resources)
        error("sixgr:pdsch:CSIRSPrecoderDimensionMismatch", ...
            "CSI-RS physical precoder shape %s does not match %d configured resource(s).", ...
            mat2str(size(precoders)), numel(resources));
    end
    physicalElementCount = size(precoders,1);
    waveformPortCount = size(grid,3);
    [portToElement, projectionSource] = localResolveCSIRSPortProjection( ...
        cfg, physicalElementCount, waveformPortCount);
    resourceEvents = repmat(localEmptyMappedCSIRSResourceEvent(), numel(resources), 1);
    occupied = zeros(0,1);
    for ordinal = 1:numel(resources)
        resource = resources(ordinal);
        resourceIndices = double(resource.Indices);
        resourceSymbols = complex(resource.Symbols);
        W = complex(precoders(:,:,ordinal));
        [logicalSymbols, baseIndices, prb, symbolNumber] = ...
            localCSIRSLogicalResourceMatrix(resourceIndices, resourceSymbols, ...
            size(grid,1), size(grid,2), size(W,2));
        if ~isempty(intersect(baseIndices(:), occupied))
            error("sixgr:pdsch:CSIRSResourceCollision", ...
                "CSI-RS resource %g overlaps another CSI-RS resource on the physical grid.", ...
                double(resource.ResourceID));
        end
        occupied = [occupied; baseIndices(:)]; %#ok<AGROW>
        if physicalElementCount == waveformPortCount
            waveformPrecoder = W;
            projectionResidual = 0;
        else
            waveformPrecoder = portToElement' * W;
            reconstructedPhysicalPrecoder = portToElement * waveformPrecoder;
            projectionResidual = norm(reconstructedPhysicalPrecoder - W, "fro") / ...
                max(norm(W, "fro"), eps);
            if ~(isfinite(projectionResidual) && projectionResidual <= 1e-9)
                error("sixgr:pdsch:CSIRSPrecoderOutsideRuntimePortSubspace", ...
                    ['CSI-RS resource %g physical precoder is outside the configured ' ...
                     '%d-port to %d-element runtime antenna subspace (relative residual %.3g).'], ...
                    double(resource.ResourceID), waveformPortCount, ...
                    physicalElementCount, projectionResidual);
            end
        end
        physicalSymbols = W * logicalSymbols;
        waveformSymbols = waveformPrecoder * logicalSymbols;
        localAssertFiniteCSIRSPrecoder(W, physicalSymbols, resource.ResourceID);
        localAssertFiniteCSIRSPrecoder( ...
            waveformPrecoder, waveformSymbols, resource.ResourceID);
        grid = localMapCSIRSPhysicalPortSymbols(grid, baseIndices, waveformSymbols);
        [waveformIndices, mappedWaveformSymbols] = ...
            localCSIRSPhysicalMapping(baseIndices, waveformSymbols, plane);
        resourceEvents(ordinal).ResourceID = double(resource.ResourceID);
        resourceEvents(ordinal).MappedRE = double(nnz(logicalSymbols));
        resourceEvents(ordinal).PhysicalRE = double(numel(physicalSymbols));
        resourceEvents(ordinal).PhysicalPortCount = size(W,1);
        resourceEvents(ordinal).WaveformPortCount = waveformPortCount;
        resourceEvents(ordinal).LogicalPortCount = size(W,2);
        resourceEvents(ordinal).PrecoderSource = ...
            "yaml_dft_ura_physical_csirs_resource_filter_via_runtime_port_projection";
        resourceEvents(ordinal).PrecoderDigest = sixgr.phy.mimo.MatrixContract.digest(W);
        resourceEvents(ordinal).WaveformPrecoderDigest = ...
            sixgr.phy.mimo.MatrixContract.digest(waveformPrecoder);
        resourceEvents(ordinal).PortToElementMatrixDigest = ...
            sixgr.phy.mimo.MatrixContract.digest(portToElement);
        resourceEvents(ordinal).PortProjectionSource = char(projectionSource);
        resourceEvents(ordinal).PortProjectionResidual = double(projectionResidual);
        resourceEvents(ordinal).BeamIndices = double(sixgr.util.structGet(cfg, ...
            "phy.csirs.precoderBeamIndices", nan(numel(resources),size(W,2))));
        resourceEvents(ordinal).BeamIndices = resourceEvents(ordinal).BeamIndices(ordinal,:);
        resourceEvents(ordinal).PRBSpan = [min(prb) max(prb)];
        resourceEvents(ordinal).SymbolSet = unique(symbolNumber(:)).';
        resourceEvents(ordinal).MappingStatus = ...
            "logical_port_grid_mapped_with_exact_physical_element_projection";
        resourceEvents(ordinal).WaveformIndices = waveformIndices;
        resourceEvents(ordinal).WaveformSymbols = mappedWaveformSymbols;
        resourceEvents(ordinal).WaveformMappedRE = numel(waveformIndices);
    end
end
ofdmOptions = canonical.ReferenceConfig.get("OFDMOptions");
[waveform, ofdmInfo] = sixgr.phy.waveform.ofdmModulate( ...
    canonical.Carrier, grid, ofdmOptions{:});
canonical.Grid = grid;
canonical.Waveform = waveform;
canonical.OFDMInfo = ofdmInfo;
event.Transmitted = true;
if any(double([resourceEvents.WaveformPortCount]) ~= ...
        double([resourceEvents.PhysicalPortCount]))
    event.RuntimeMaterializationStatus = ...
        "physical_element_precoder_exact_runtime_port_projection_mapping";
    event.UpdateOutcome = ...
        "all_configured_resources_projected_exactly_and_transmitted_on_reserved_re";
else
    event.RuntimeMaterializationStatus = ...
        "physical_element_domain_csirs_resource_set_mapping";
    event.UpdateOutcome = ...
        "all_configured_resources_precoded_and_transmitted_on_reserved_re";
end
event.ResourceEvents = resourceEvents;
event.NumResources = numel(resourceEvents);
event.PhysicalPortCount = max(double([resourceEvents.PhysicalPortCount]));
event.WaveformPortCount = size(grid,3);
event.PortProjectionSource = strjoin(unique(string( ...
    {resourceEvents.PortProjectionSource}), "stable"), "|");
event.PortProjectionResidualMax = max(double( ...
    [resourceEvents.PortProjectionResidual]), [], "omitnan");
event.WaveformPrecoderDigests = string( ...
    {resourceEvents.WaveformPrecoderDigest});
event.PortToElementMatrixDigests = string( ...
    {resourceEvents.PortToElementMatrixDigest});
event.PrecoderSource = strjoin(unique(string({resourceEvents.PrecoderSource}), ...
    "stable"), "|");
event.PrecoderDigests = string({resourceEvents.PrecoderDigest});
event.WaveformIndices = vertcat(resourceEvents.WaveformIndices);
event.WaveformSymbols = vertcat(resourceEvents.WaveformSymbols);
event.WaveformMappedRE = numel(event.WaveformIndices);
if any(abs(grid(event.WaveformIndices) - event.WaveformSymbols) > 1e-12)
    error("sixgr:pdsch:CSIRSExecutedGridEvidenceMismatch", ...
        "Executed CSI-RS physical indices/symbols do not match the transmitted resource grid.");
end
canonical.StageTrace = [canonical.StageTrace; table( ...
    "physical_csirs_resource_set_mapping_via_runtime_port_domain", "PASS", numel(symbols), ...
    'VariableNames', canonical.StageTrace.Properties.VariableNames)];
end

function [portToElement, source] = localResolveCSIRSPortProjection( ...
        cfg, physicalElementCount, waveformPortCount)
physicalElementCount = double(physicalElementCount);
waveformPortCount = double(waveformPortCount);
if physicalElementCount == waveformPortCount
    portToElement = eye(physicalElementCount);
    source = "identity_element_domain_waveform";
    return;
end
arch = sixgr.rf.AntennaArrayFactory.resolvePortArchitecture( ...
    cfg, "bs", "Signal", "PDSCH", ...
    "NumElements", physicalElementCount, ...
    "NumPorts", waveformPortCount, ...
    "MinimumPorts", waveformPortCount);
portToElement = complex(double(sixgr.util.structGet( ...
    arch, "PortToElementMatrix", [])));
if ~isequal(size(portToElement), [physicalElementCount waveformPortCount]) || ...
        any(~isfinite(real(portToElement(:))) | ...
        ~isfinite(imag(portToElement(:))))
    error("sixgr:pdsch:CSIRSPrecoderDimensionMismatch", ...
        ['Runtime antenna projection must be a finite %d-by-%d ' ...
         'element-by-waveform-port matrix; observed %s.'], ...
        physicalElementCount, waveformPortCount, mat2str(size(portToElement)));
end
gramResidual = norm(portToElement' * portToElement - ...
    eye(waveformPortCount), "fro");
if gramResidual > 1e-10
    error("sixgr:pdsch:InvalidCSIRSPortProjection", ...
        "Runtime port-to-element projection is not semi-unitary (residual %.3g).", ...
        gramResidual);
end
source = "AntennaArrayFactory.resolvePortArchitecture.PDSCH.PortToElementMatrix";
end

function [logicalSymbols, baseIndices, prb, symbolNumber] = ...
        localCSIRSLogicalResourceMatrix(indices, symbols, K, L, logicalPorts)
plane = double(K) * double(L);
if isempty(indices) || isempty(symbols)
    error("sixgr:pdsch:EmptyCSIRSResource", ...
        "A scheduled CSI-RS resource cannot be empty.");
end
if any(~isfinite(indices(:)) | indices(:) < 1 | indices(:) ~= round(indices(:)))
    error("sixgr:pdsch:InvalidCSIRSIndex", ...
        "CSI-RS indices must be finite positive one-based integers.");
end
portOfIndex = floor((indices(:) - 1) ./ plane) + 1;
if any(portOfIndex > logicalPorts)
    error("sixgr:pdsch:CSIRSPrecoderDimensionMismatch", ...
        "CSI-RS reference port exceeds the physical precoder logical-port dimension.");
end
baseRaw = mod(indices(:) - 1, plane) + 1;
baseIndices = unique(baseRaw, "sorted");
logicalSymbols = complex(zeros(logicalPorts, numel(baseIndices)));
symbolVector = symbols(:);
if numel(symbolVector) ~= numel(baseRaw)
    error("sixgr:pdsch:CSIRSResourceSymbolCountMismatch", ...
        "CSI-RS resource has %d indices but %d symbols.", numel(baseRaw), numel(symbolVector));
end
[present, positions] = ismember(baseRaw, baseIndices);
if any(~present)
    error("sixgr:pdsch:CSIRSResourceIndexMismatch", ...
        "CSI-RS logical indices could not be resolved on the base grid.");
end
for item = 1:numel(symbolVector)
    logicalSymbols(portOfIndex(item), positions(item)) = symbolVector(item);
end
[subcarrierOne, symbolOne] = ind2sub([K L], baseIndices);
prb = floor((double(subcarrierOne) - 1) ./ 12);
symbolNumber = double(symbolOne) - 1;
end

function grid = localMapCSIRSPhysicalPortSymbols(grid, baseIndices, values)
if size(values,1) ~= size(grid,3) || size(values,2) ~= numel(baseIndices)
    error("sixgr:pdsch:CSIRSPhysicalMappingShapeMismatch", ...
        "Physical CSI-RS symbols do not match the grid port/resource shape.");
end

for port = 1:size(grid,3)
    plane = grid(:,:,port);
    if any(plane(baseIndices) ~= 0)
        error("sixgr:pdsch:CSIRSResourceCollision", ...
            "CSI-RS mapping collided with another physical signal on port %d.", port - 1);
    end
    plane(baseIndices) = values(port,:).';
    grid(:,:,port) = plane;
end
end

function [indices, symbols] = localCSIRSPhysicalMapping(baseIndices, values, plane)
% Return the exact nonzero waveform-port REs written into the TX grid.
% The Toolbox CSI-RS indices describe logical CSI ports.  After the YAML
% spatial filter is applied, runtime occupancy must instead follow the
% physical waveform-port pages that actually contain transmitted samples.
portCount = size(values, 1);
indexMatrix = double(baseIndices(:)) + ...
    double(plane) .* (0:(portCount - 1));
symbolMatrix = transpose(values);
mask = abs(symbolMatrix) > 0;
indices = indexMatrix(mask);
symbols = symbolMatrix(mask);
indices = double(indices(:));
symbols = complex(symbols(:));
if isempty(indices)
    error("sixgr:pdsch:EmptyCSIRSPhysicalMapping", ...
        "A scheduled CSI-RS resource produced no nonzero physical waveform-port REs.");
end
if numel(unique(indices)) ~= numel(indices)
    error("sixgr:pdsch:DuplicateCSIRSPhysicalMapping", ...
        "A scheduled CSI-RS resource produced duplicate physical waveform-port RE indices.");
end
end

function localAssertFiniteCSIRSPrecoder(W, values, resourceID)
if any(~isfinite(real(W(:))) | ~isfinite(imag(W(:)))) || ...
        any(~isfinite(real(values(:))) | ~isfinite(imag(values(:))))
    error("sixgr:pdsch:InvalidCSIRSPhysicalPrecoder", ...
        "CSI-RS resource %g produced nonfinite physical symbols.", double(resourceID));
end
if any(abs(sum(abs(W).^2,1) - 1) > 1e-10)
    error("sixgr:pdsch:InvalidCSIRSPhysicalPrecoder", ...
        "CSI-RS resource %g physical precoder columns must have unit norm.", double(resourceID));
end
end

function event = localEmptyMappedCSIRSResourceEvent()
event = struct("ResourceID",NaN,"MappedRE",NaN,"PhysicalRE",NaN, ...
    "PhysicalPortCount",NaN,"WaveformPortCount",NaN, ...
    "LogicalPortCount",NaN, ...
    "PrecoderSource","","PrecoderDigest","", ...
    "WaveformPrecoderDigest","","PortToElementMatrixDigest","", ...
    "PortProjectionSource","","PortProjectionResidual",NaN, ...
    "BeamIndices",[],"WaveformIndices",zeros(0,1), ...
    "WaveformSymbols",complex(zeros(0,1)),"WaveformMappedRE",0, ...
    "PRBSpan",[],"SymbolSet",[],"MappingStatus","");
end

function [tx, info] = localAdaptCanonicalCalibrationTX( ...
        canonical, bundle, pdschInfo, carrierInfo, dmrsPowerInfo, ...
        csirsInd, csirsSym, csirsInfo, csirsCfg, csirsEvent, ...
        transportBlockSizeSource, phyGrant, hasPHYGrant, compactOutput)
pdsch = bundle.PDSCH;
carrier = bundle.Carrier;
nLayers = double(pdsch.NumLayers);
nPorts = double(bundle.ReferenceConfig.get("NPhysicalTxAntennas"));
nCodewords = numel(bundle.TransportBlocks);
planeSize = double(carrier.NSizeGrid) * 12 ...
    * double(carrier.SymbolsPerSlot);

[pdschInd, kernelInfo] = nrPDSCHIndices(carrier, pdsch);
dmrsInd = nrPDSCHDMRSIndices(carrier, pdsch);
dmrsSym = complex(nrPDSCHDMRS(carrier, pdsch)) ...
    .* double(dmrsPowerInfo.DMRSAmplitudeScale);
ptrsInd = [];
ptrsSym = complex(zeros(0,1));
if pdsch.EnablePTRS
    ptrsInd = nrPDSCHPTRSIndices(carrier, pdsch);
    ptrsSym = complex(nrPDSCHPTRS(carrier, pdsch));
end
pdschAntInd = localCalibrationPortIndices( ...
    bundle.ResourcePlan.DataIndices, nPorts, planeSize);
dmrsUnion = unique([bundle.ResourcePlan.DMRSIndicesPerPort{:}], ...
    "sorted");
dmrsAntInd = localCalibrationPortIndices( ...
    dmrsUnion, nPorts, planeSize);
ptrsUnion = unique([bundle.ResourcePlan.PTRSIndicesPerPort{:}], ...
    "sorted");
ptrsAntInd = localCalibrationPortIndices( ...
    ptrsUnion, nPorts, planeSize);
pdschAntSym = canonical.DataPortSymbols.';
dmrsAntSym = canonical.DMRSPortSymbols.';
ptrsAntSym = canonical.PTRSPortSymbols.';

[codewords, codingLayouts, tbCRC, crcInfo, segInfo, ...
    rateMatchInfo, baseGraphs, B] = ...
    localCanonicalTXCodingEvidence(canonical, nCodewords);
codeword = codewords{1};
pdschSym = canonical.LayerSymbols;
resourceAccounting = localCanonicalResourceAccounting( ...
    bundle, nLayers, nPorts);
codewordLayerMapping = localBuildPDSCHCodewordLayerContract( ...
    pdsch, codewords, codingLayouts, resourceAccounting);
codewordLayerMapping = localFinalizePDSCHCodewordLayerContract( ...
    codewordLayerMapping, pdschSym);
prec = bundle.LegacyPrecoder;
precodePowerInfo = localBuildPrecodePowerInfo( ...
    pdschSym, pdschAntSym, prec);
gridPortContract = localBuildResourceGridPortContract( ...
    canonical.Grid, pdschAntInd, pdschAntSym, ...
    dmrsAntInd, dmrsAntSym, ptrsAntInd, ptrsAntSym, ...
    csirsInd, csirsSym, csirsEvent, nPorts, prec);
localValidateResourceGridPortContract(gridPortContract, prec);

trBlkSize = double(bundle.TransportBlockSizes);
scheduledTBS = double(bundle.ScheduledTransportBlockSizes);
targetRate = double(bundle.TargetCodeRate);
rv = double(bundle.RV);
GPerCodeword = double(bundle.ResourcePlan.GPerCodeword);
G = sum(GPerCodeword);
nrePerPRB = double(bundle.NREPerPRBForTBS);
pdschInfo = localMergeStructs(pdschInfo, kernelInfo);
pdschInfo.ResourceAccounting = resourceAccounting;
pdschInfo.LayerDataRE = resourceAccounting.LayerDataRE;
pdschInfo.PortMappedRE = resourceAccounting.PortMappedRE;
pdschInfo.ModulationSymbolCount = ...
    resourceAccounting.ModulationSymbolCount;
pdschInfo.CodedBitCountG = G;
pdschInfo.G = G;
pdschInfo.NREPerPRB = nrePerPRB;

tx = canonical;
tx.ReceiverConfig = bundle.ReceiverConfig;
executionProfile = string(bundle.Assignment.Profile);
isSchedulerTruth = executionProfile == "scheduler_truth";
tx.ExecutionProfile = char(executionProfile);
tx.FacadeContractVersion = "PDSCH_TxCompatibilityFacade/v3";
tx.CanonicalDelegation = true;
tx.DelegationTarget = "sixgr.pdsch.PDSCHTransmitter";
tx.StrictSchedulingOwnership = logical(isSchedulerTruth);
tx.SchedulingOwnership = char(ternaryPDSCHProfile( ...
    isSchedulerTruth, ...
    "authored_scheduler_dci_transmitter_assignment", ...
    "explicit_phy_calibration_assignment"));
tx.AssignmentId = char(bundle.Assignment.AssignmentId);
tx.OFDM = canonical.OFDMInfo;
tx.TransportBlockSize = trBlkSize;
tx.ScheduledTransportBlockSize = scheduledTBS;
tx.TransportBlockSizeSource = transportBlockSizeSource;
tx.TransportBlock = vertcat(bundle.TransportBlocks{:});
tx.TransportBlocks = bundle.TransportBlocks;
tx.TransportBlockSizePerCodeword = trBlkSize;
tx.TransportBlockCRCType = char(crcInfo{1}.Type);
tx.TransportBlockCRCLength = double(crcInfo{1}.Length);
tx.TransportBlockCRCTypePerCodeword = cellfun( ...
    @(x) char(string(x.Type)), crcInfo, "UniformOutput", false);
tx.TransportBlockCRCLengthPerCodeword = cellfun( ...
    @(x) double(x.Length), crcInfo);
tx.TransportBlockLenWithCRC = B(1);
tx.TransportBlockLenWithCRCPerCodeword = B;
tx.RV = rv;
tx.RVPerCodeword = rv;
tx.TargetCodeRate = targetRate;
tx.TargetCodeRatePerCodeword = targetRate;
tx.RequestedTargetCodeRate = ...
    double(bundle.RequestedTargetCodeRate);
tx.CodingLayout = codingLayouts{1};
tx.CodingLayouts = codingLayouts;
tx.PDSCH = pdsch;
tx.PDSCHIndices = pdschInd;
tx.PDSCHSymbolsForEvidence = pdschSym;
tx.PDSCHLayerSymbolsForEvidence = pdschSym;
tx.PDSCHPortSymbolsForEvidence = pdschAntSym;
tx.PDSCHLayerSymbols = pdschSym;
tx.PDSCHPortSymbols = pdschAntSym;
tx.PDSCHLayerIndices = pdschInd;
tx.PDSCHPortIndices = pdschAntInd;
tx.LayerSymbolOrder = ...
    sixgr.phy.resource.buildSymbolOrderingMap( ...
        carrier, pdschInd, "layer");
tx.PortSymbolOrder = ...
    sixgr.phy.resource.buildSymbolOrderingMap( ...
        carrier, pdschAntInd, "port");
tx.LayerSymbolDomain = "layer";
tx.PortSymbolDomain = "port";
tx.XOverhead = double(bundle.XOverhead);
tx.G = G;
tx.GPerCodeword = GPerCodeword;
tx.NREPerPRB = nrePerPRB;
tx.LayerDataRE = resourceAccounting.LayerDataRE;
tx.PortMappedRE = resourceAccounting.PortMappedRE;
tx.ModulationSymbolCount = ...
    resourceAccounting.ModulationSymbolCount;
tx.QAMSymbolCount = numel(pdschSym);
tx.PortIndexCellCount = numel(pdschAntInd);
tx.RateMatchedBitCount = G;
tx.NumCodewords = nCodewords;
tx.RateMatchedBitCountPerCodeword = GPerCodeword;
tx.CodewordLayerMapping = codewordLayerMapping;
tx.ResourceAccounting = resourceAccounting;
tx.PrecodeInfo = prec;
tx.PrecodePowerInfo = precodePowerInfo;
tx.DMRSEPREDifference = dmrsPowerInfo;
tx.DMRSDataToDMRSEPREDifference_dB = ...
    double(dmrsPowerInfo.DataToDMRSEPREDifference_dB);
tx.DMRSPowerBoost_dB = ...
    double(dmrsPowerInfo.DMRSPowerBoost_dB);
tx.DMRSConfiguredPowerBoost_dB = ...
    double(dmrsPowerInfo.ConfiguredDMRSPowerBoost_dB);
tx.DMRSRealizedDataToDMRSEPREDifference_dB = ...
    double(dmrsPowerInfo.RealizedDataToDMRSEPREDifference_dB);
tx.DMRSAmplitudeScale = ...
    double(dmrsPowerInfo.DMRSAmplitudeScale);
tx.DMRSPowerScale = double(dmrsPowerInfo.DMRSPowerScale);
tx.SymbolDomainInfo = struct( ...
    "ReferenceDomain", "layer", "PortDomain", "port", ...
    "Transform", "canonical_PDSCHPrecoderBundle", ...
    "NumLayers", nLayers, "NumPorts", nPorts, ...
    "Status", "canonical_layer_and_physical_port_symbols", ...
    "Equation", ...
        "b_G_to_QAM_d_to_layers_S_to_ports_X_equals_W_times_S");
tx.OFDMWindowingSamples = double( ...
    sixgr.util.structGet(bundle.WindowingInfo, ...
        "OFDMWindowingSamples", 0));
tx.OFDMWindowingSource = char(string(sixgr.util.structGet( ...
    bundle.WindowingInfo, "OFDMWindowingSource", "")));
tx.OFDMWindowingEnabled = logical(sixgr.util.structGet( ...
    bundle.WindowingInfo, "OFDMWindowingEnabled", false));
tx.TransportBlockCRC = tbCRC{1};
tx.TransportBlockCRCPerCodeword = tbCRC;
tx.BaseGraph = baseGraphs(1);
tx.BaseGraphPerCodeword = baseGraphs;
tx.Codeword = codeword;
tx.Codewords = codewords;
tx.PDSCHInfo = pdschInfo;
tx.PDSCHSymbols = pdschSym;
tx.DMRSIndices = dmrsInd;
tx.DMRSSymbols = dmrsSym;
tx.PDSCHAntennaIndices = pdschAntInd;
tx.PDSCHAntennaSymbols = pdschAntSym;
tx.DMRSAntennaIndices = dmrsAntInd;
tx.DMRSAntennaSymbols = dmrsAntSym;
tx.PTRSIndices = ptrsInd;
tx.PTRSSymbols = ptrsSym;
tx.PTRSAntennaIndices = ptrsAntInd;
tx.PTRSAntennaSymbols = ptrsAntSym;
tx.CSIRSIndices = csirsInd;
tx.CSIRSSymbols = csirsSym;
tx.CSIRSPhysicalIndices = double(sixgr.util.structGet( ...
    csirsEvent, "WaveformIndices", zeros(0,1)));
tx.CSIRSPhysicalSymbols = complex(sixgr.util.structGet( ...
    csirsEvent, "WaveformSymbols", complex(zeros(0,1))));
tx.CSIRSInfo = csirsInfo;
tx.CSIRS = csirsCfg;
tx.CSIRSRuntimeEvent = csirsEvent;
tx.ResourceGridPortContract = gridPortContract;
if compactOutput
    % Canonical stage evidence is intentionally retained even when legacy
    % callers request their former compact alias surface.
    tx.CompactOutputRequested = true;
end
if hasPHYGrant
    tx.PHYGrant = phyGrant;
end
tx.TxContext = localBuildTxContext( ...
    tx, bundle.TransportBlocks, tbCRC, codewords, ...
    canonical.Grid, canonical.Waveform, pdschInd, pdschSym, ...
    pdschAntInd, pdschAntSym, dmrsInd, dmrsSym, ...
    dmrsAntInd, dmrsAntSym, ptrsInd, ptrsSym, ...
    ptrsAntInd, ptrsAntSym, carrier, pdsch, ...
    codingLayouts, resourceAccounting, prec, ...
    precodePowerInfo, codewordLayerMapping, phyGrant, hasPHYGrant);
tx.TxContext.DMRSEPREDifference = dmrsPowerInfo;
tx.TxContext.CanonicalDelegation = true;

info = struct( ...
    "FacadeContractVersion", "PDSCH_TxCompatibilityFacade/v3", ...
    "CanonicalDelegation", true, ...
    "DelegationTarget", "sixgr.pdsch.PDSCHTransmitter", ...
    "ExecutionProfile", char(executionProfile), ...
    "CarrierInfo", carrierInfo, ...
    "CRC", crcInfo{1}, "CRCPerCodeword", {crcInfo}, ...
    "Segmentation", segInfo{1}, ...
    "SegmentationPerCodeword", {segInfo}, ...
    "RateMatch", rateMatchInfo{1}, ...
    "RateMatchPerCodeword", {rateMatchInfo}, ...
    "CodingLayout", codingLayouts{1}, ...
    "CodingLayouts", {codingLayouts}, ...
    "PDSCHSymbols", struct( ...
        "Source", "canonical_pdsch_modulator_and_layer_mapper"), ...
    "PTRS", struct("Enabled", logical(pdsch.EnablePTRS)), ...
    "CSIRS", csirsInfo, ...
    "CSIRSRuntimeEvent", csirsEvent, ...
    "ResourceGridPortContract", gridPortContract, ...
    "OFDM", canonical.OFDMInfo, ...
    "OFDMWindowing", bundle.WindowingInfo, ...
    "Precoding", prec, ...
    "PrecodePowerInfo", precodePowerInfo, ...
    "DMRS", localCalibrationDMRSInfo(dmrsPowerInfo), ...
    "DMRSEPREDifference", dmrsPowerInfo, ...
    "XOverhead", double(bundle.XOverhead), ...
    "ResourceAccounting", resourceAccounting, ...
    "CodewordLayerMapping", codewordLayerMapping, ...
    "TxContext", tx.TxContext, ...
    "ResourcePlan", bundle.ResourcePlan, ...
    "StageTrace", canonical.StageTrace, ...
    "Source", char(ternaryPDSCHProfile(isSchedulerTruth, ...
        "canonical_pdsch_transmitter_scheduler_truth_facade", ...
        "canonical_pdsch_transmitter_calibration_facade")));
if executionProfile == "phy_calibration"
    receiverBundle = bundle;
    % The receiver needs the immutable assignment/resource/reference/coding
    % objects, not a second copy of the payload.  Passing this same-Tx
    % context avoids rebuilding the complete calibration facade while
    % retaining the canonical PDSCH_Rx/PDSCHReceiver chain.
    receiverBundle.TransportBlocks = cell(1,numel(bundle.TransportBlocks));
    info.CalibrationReceiverBundle = receiverBundle;
end
end

function value = ternaryPDSCHProfile(condition, trueValue, falseValue)
if condition
    value = string(trueValue);
else
    value = string(falseValue);
end
end

function indices = localCalibrationPortIndices(baseZero, nPorts, plane)
baseOne = double(baseZero(:)) + 1;
indices = baseOne + plane .* (0:(nPorts - 1));
end

function [codewords, layouts, tbCRC, crcInfo, segInfo, ...
        rateInfo, baseGraphs, B] = ...
        localCanonicalTXCodingEvidence(canonical, nCodewords)
if nCodewords == 1
    encoded = {canonical.DLSCHEncode};
else
    encoded = canonical.DLSCHEncode.Codewords;
end
codewords = cell(1,nCodewords);
layouts = cell(1,nCodewords);
tbCRC = cell(1,nCodewords);
crcInfo = cell(1,nCodewords);
segInfo = cell(1,nCodewords);
rateInfo = cell(1,nCodewords);
baseGraphs = zeros(1,nCodewords);
B = zeros(1,nCodewords);
for cw = 1:nCodewords
    item = encoded{cw};
    codewords{cw} = int8(item.RateMatchedBits(:));
    layouts{cw} = item.CodingLayout;
    tbCRC{cw} = int8(item.TBCRCBlock(:));
    crcInfo{cw} = struct( ...
        "Type", string(item.TBCRCType), ...
        "Length", double(item.CodingLayout.TBCRCLength));
    segInfo{cw} = item.SegmentationInfo;
    rateInfo{cw} = item.RateMatchInfo;
    baseGraphs(cw) = double(item.BaseGraph);
    B(cw) = numel(item.TBCRCBlock);
end
end

function accounting = localCanonicalResourceAccounting( ...
        bundle, nLayers, nPorts)
plan = bundle.ResourcePlan;
GPerCodeword = double(plan.GPerCodeword);
dmrsUnion = unique([plan.DMRSIndicesPerPort{:}], "sorted");
ptrsUnion = unique([plan.PTRSIndicesPerPort{:}], "sorted");
dmrsLinearRE = sum(cellfun(@numel, plan.DMRSIndicesPerPort));
ptrsLinearRE = sum(cellfun(@numel, plan.PTRSIndicesPerPort));
accounting = struct( ...
    "ContractVersion", "CanonicalPDSCHResourcePlan/v1", ...
    "IndexBase", "zero_based", ...
    "LayerDataRE", double(plan.ExactDataRECount), ...
    "PortMappedRE", double(plan.ExactDataRECount * nPorts), ...
    "ModulationSymbolCount", ...
        double(plan.ExactDataRECount * nLayers), ...
    "CodedBitCountG", sum(GPerCodeword), ...
    "CodedBitCountGPerCodeword", GPerCodeword, ...
    "GPerCodeword", GPerCodeword, ...
    "NREPerPRBForTBS", double(bundle.NREPerPRBForTBS), ...
    "NREPerPRB", double(plan.NREPerPRB), ...
    "DataREPerPRB", double(plan.NREPerPRB), ...
    "DMRSRE", double(numel(dmrsUnion)), ...
    "PTRSRE", double(numel(ptrsUnion)), ...
    "DMRSLinearRE", double(dmrsLinearRE), ...
    "PTRSLinearRE", double(ptrsLinearRE), ...
    "ReservedRE", double(numel(unique(plan.ReservedUnionIndices))), ...
    "DisjointMasks", logical( ...
        plan.OverlapCounts.DMRSPTRS == 0 ...
        && plan.OverlapCounts.DMRSReserved == 0 ...
        && plan.OverlapCounts.PTRSReserved == 0), ...
    "ExactResourcePlan", true, ...
    "Source", "immutable_pdsch_resource_plan");
end

function value = localMergeStructs(primary, secondary)
value = primary;
names = fieldnames(secondary);
for idx = 1:numel(names)
    if ~isfield(value, names{idx})
        value.(names{idx}) = secondary.(names{idx});
    end
end
end

function info = localCalibrationDMRSInfo(powerInfo)
info = struct( ...
    "DataToDMRSEPREDifference_dB", ...
        double(powerInfo.DataToDMRSEPREDifference_dB), ...
    "DMRSPowerBoost_dB", double(powerInfo.DMRSPowerBoost_dB), ...
    "ConfiguredDMRSPowerBoost_dB", ...
        double(powerInfo.ConfiguredDMRSPowerBoost_dB), ...
    "RealizedDataToDMRSEPREDifference_dB", ...
        double(powerInfo.RealizedDataToDMRSEPREDifference_dB), ...
    "DMRSAmplitudeScale", double(powerInfo.DMRSAmplitudeScale), ...
    "DMRSPowerScale", double(powerInfo.DMRSPowerScale), ...
    "EPREConfigSource", char(string(powerInfo.Source)), ...
    "EPREScalePolicy", char(string(powerInfo.ScalePolicy)));
end

function [tx, info] = localDelegateCanonicalPDSCHTransmitter( ...
        opt, executionProfile, hasPHYGrant)
assignment = opt.Assignment;
if isempty(opt.ResourcePlan)
    error("sixgr:pdsch:MissingResourcePlan", ...
        "Assignment-owned PDSCH execution requires PDSCHResourcePlan.");
end
if ~isa(opt.Carrier, "nrCarrierConfig")
    error("sixgr:pdsch:MissingCanonicalCarrier", ...
        "Assignment-owned PDSCH execution requires an explicit nrCarrierConfig.");
end
if ~isa(opt.ReferenceSignalConfig, ...
        "sixgr.pdsch.PDSCHReferenceSignalConfig")
    error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
        "Assignment-owned PDSCH execution requires an immutable " + ...
        "PDSCHReferenceSignalConfig.");
end
if isempty(opt.TransportBlockBits)
    error("sixgr:pdsch:MissingTransportBlock", ...
        "Assignment-owned PDSCH execution requires one explicit transport block per codeword.");
end
if hasPHYGrant
    error("sixgr:pdsch:ConfiguredGrantNotAllowed", ...
        "A frozen PHYGrant cannot replace immutable assignment ownership.");
end
legacyOverridesPresent = ~isempty(opt.PDSCH) ...
    || ~isempty(opt.TransportBlockSizeOverride) ...
    || ~isempty(opt.RV) ...
    || ~isempty(opt.TargetCodeRate) ...
    || ~isempty(opt.XOverhead) ...
    || ~isempty(opt.NumTxAnt) ...
    || ~isempty(opt.PrecodingMatrix);
if legacyOverridesPresent
    error("sixgr:pdsch:LegacyOverrideNotAllowed", ...
        "Assignment-owned PDSCH execution rejects legacy PDSCH, rate, RV, TBS, antenna, and matrix overrides.");
end
if logical(opt.CompactOutput)
    error("sixgr:pdsch:CompactStrictOutputNotAllowed", ...
        "Canonical assignment-owned PDSCH execution must retain its complete stage evidence.");
end
if assignment.Profile ~= executionProfile
    error("sixgr:pdsch:ExecutionProfileMismatch", ...
        "Assignment profile '%s' does not match requested '%s'.", ...
        assignment.Profile, executionProfile);
end
assignmentDigest = assignment.validateForExecution();

canonical = sixgr.pdsch.PDSCHTransmitter( ...
    opt.TransportBlockBits, assignment, opt.ResourcePlan, opt.Carrier, ...
    opt.ReferenceSignalConfig, ...
    "PrecoderBundle", opt.PrecoderBundle, ...
    "IntegrationContext", opt.IntegrationContext, ...
    "Nref", opt.Nref);
tx = canonical;
tx.FacadeContractVersion = "PDSCH_TxCompatibilityFacade/v2";
tx.CanonicalDelegation = true;
tx.DelegationTarget = "sixgr.pdsch.PDSCHTransmitter";
tx.ExecutionProfile = char(executionProfile);
tx.StrictSchedulingOwnership = any(executionProfile == ...
    ["connected_strict","sps_strict","ra_si_strict"]);
tx.SchedulingOwnership = "immutable_pdsch_scheduling_assignment";
tx.AssignmentValidationDigest = assignmentDigest;
tx.IntegrationBinding = canonical.IntegrationBinding;
tx.OFDM = canonical.OFDMInfo;
tx.TransportBlockSize = double(canonical.TransportBlockSizes);
tx.ScheduledTransportBlockSize = double(canonical.TransportBlockSizes);
tx.TransportBlockSizePerCodeword = double(canonical.TransportBlockSizes);
tx.TransportBlockSizeSource = "canonical_explicit_transport_blocks";
tx.TransportBlocks = localCanonicalTransportBlockCells(opt.TransportBlockBits);
tx.TransportBlock = vertcat(tx.TransportBlocks{:});
tx.RV = double(assignment.get("RVPerCodeword"));
tx.RVPerCodeword = tx.RV;
tx.TargetCodeRate = double(assignment.get("TargetCodeRatePerCodeword"));
tx.TargetCodeRatePerCodeword = tx.TargetCodeRate;
tx.G = sum(double(opt.ResourcePlan.GPerCodeword));
tx.GPerCodeword = double(opt.ResourcePlan.GPerCodeword);
tx.RateMatchedBitCount = tx.G;
tx.RateMatchedBitCountPerCodeword = tx.GPerCodeword;
tx.PDSCHIndicesZeroBased = double(opt.ResourcePlan.DataIndices);
tx.DMRSIndicesPerPortZeroBased = opt.ResourcePlan.DMRSIndicesPerPort;
tx.PTRSIndicesPerPortZeroBased = opt.ResourcePlan.PTRSIndicesPerPort;

info = struct( ...
    "FacadeContractVersion", "PDSCH_TxCompatibilityFacade/v2", ...
    "CanonicalDelegation", true, ...
    "DelegationTarget", "sixgr.pdsch.PDSCHTransmitter", ...
    "ExecutionProfile", executionProfile, ...
    "AssignmentValidationDigest", assignmentDigest, ...
    "IntegrationBinding", canonical.IntegrationBinding, ...
    "ResourcePlan", opt.ResourcePlan, ...
    "StageTrace", canonical.StageTrace, ...
    "OFDM", canonical.OFDMInfo, ...
    "Source", "canonical_pdsch_transmitter_facade");
end

function cells = localCanonicalTransportBlockCells(raw)
if iscell(raw)
    cells = reshape(raw, 1, []);
else
    cells = {raw};
end
for idx = 1:numel(cells)
    cells{idx} = int8(cells{idx}(:));
end
end

function profile = localResolveExecutionProfile(cfg, explicitProfile, assignment)
profile = lower(strtrim(string(explicitProfile)));
if strlength(profile) == 0
    profile = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "phy.pdsch.executionProfile", ...
        sixgr.util.structGet(cfg, "run.pdschExecutionProfile", "")))));
end
if strlength(profile) == 0 && ...
        isa(assignment, "sixgr.pdsch.PDSCHSchedulingAssignment")
    profile = assignment.Profile;
end
if strlength(profile) == 0
    error("sixgr:pdsch:MissingExecutionProfile", ...
        "PDSCH execution requires an explicit ExecutionProfile, " + ...
        "cfg.phy.pdsch.executionProfile, cfg.run.pdschExecutionProfile, " + ...
        "or an immutable assignment-owned profile.");
end
if ~any(profile == ...
        ["connected_strict","sps_strict","ra_si_strict","scheduler_truth","phy_calibration"])
    error("sixgr:pdsch:UnsupportedExecutionProfile", ...
        "Unsupported PDSCH execution profile '%s'.", profile);
end
end

function [indices, info, pdsch] = localResolvePDSCHMaterialization( ...
        carrier, cfg, opt, phyGrant, hasPHYGrant, strictAssignmentProfile)
providedPDSCH = opt.PDSCH;
if strictAssignmentProfile
    if ~isempty(providedPDSCH)
        error("sixgr:pdsch:ConfigurationOverrideNotAllowed", ...
            "Strict PDSCH configuration is materialized only from the immutable assignment.");
    end
    if isempty(fieldnames(opt.ReferenceSignalConfig))
        error("sixgr:pdsch:IncompleteReferenceSignalConfiguration", ...
            "Strict PDSCH materialization requires explicit reference-signal configuration.");
    end
    pdsch = sixgr.pdsch.PDSCHConfigMaterializer.fromAssignment( ...
        opt.Assignment, opt.ReferenceSignalConfig);
    [indices, info] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
    return;
end

if isempty(providedPDSCH)
    if hasPHYGrant
        [indices, info, pdsch] = localBuildPDSCHFromFrozenGrant( ...
            carrier, cfg, phyGrant);
    else
        [indices, info, pdsch] = sixgr.phy.grid.allocREsPDSCH( ...
            carrier, cfg);
    end
else
    pdsch = providedPDSCH;
    if hasPHYGrant
        localAssertExplicitPDSCHMatchesGrant(pdsch, phyGrant);
    end
    [indices, info] = nrPDSCHIndices(carrier, pdsch, "IndexStyle", "index");
end
end

function localAssertResourcePlanAgreement(plan, pdsch, accounting)
if ~isa(plan, "sixgr.pdsch.PDSCHResourcePlan")
    error("sixgr:pdsch:MissingResourcePlan", ...
        "Strict PDSCH execution requires PDSCHResourcePlan.");
end
if plan.IndexBase ~= "zero_based"
    error("sixgr:pdsch:ResourcePlanIndexConventionMismatch", ...
        "Strict PDSCH resource plans must use zero-based NR indices.");
end
if ~isequal(double(plan.PRBSet(:).'), double(pdsch.PRBSet(:).')) || ...
        ~isequal(double(plan.SymbolAllocation(:).'), ...
        double(pdsch.SymbolAllocation(:).'))
    error("sixgr:pdsch:ResourcePlanAssignmentMismatch", ...
        "Resource plan allocation differs from the materialized assignment.");
end
actualG = double(accounting.CodedBitCountGPerCodeword(:).');
if ~isequal(double(plan.GPerCodeword(:).'), actualG)
    error("sixgr:pdsch:ResourcePlanGMismatch", ...
        "Resource plan G=%s differs from exact materialized G=%s.", ...
        mat2str(double(plan.GPerCodeword(:).')), mat2str(actualG));
end
overlapFields = ["DMRSPTRS","DMRSReserved","PTRSReserved", ...
    "DuplicateAllocation","DuplicateData"];
hasCollision = false;
for idx = 1:numel(overlapFields)
    hasCollision = hasCollision || ...
        double(plan.OverlapCounts.(overlapFields(idx))) ~= 0;
end
if hasCollision
    error("sixgr:pdsch:DataDMRSPTRSReservedCollision", ...
        "Strict PDSCH resource plan contains an ownership overlap.");
end
end

function [csirsInd, csirsSym, csirsInfo, csirsCfg, event] = localGenerateCSIRSRuntimeResource(carrier, cfg)
csirsInd = zeros(0, 1);
csirsSym = zeros(0, 1, "like", 1i);
csirsInfo = struct("Channel", "CSI-RS", "Enabled", false);
csirsCfg = [];
event = localEmptyCSIRSEvent(cfg);
configuredCSIRS = logical(sixgr.util.structGet(cfg, "phy.csirs.enable", false));
sixgr.config.assertRuntimeFeatureUse(cfg, "csi_rs", configuredCSIRS, ...
    "PDSCH_Tx.CSI-RS");
if ~configuredCSIRS
    event.RuntimeMaterializationStatus = "disabled";
    event.Blocker = "phy.csirs.enable_false";
    event.UpdateOutcome = "not_scheduled";
    return;
end
periodSlots = double(sixgr.util.structGet(cfg, "phy.csirs.period_slots", NaN));
offsetSlots = double(sixgr.util.structGet(cfg, "phy.csirs.offset_slots", NaN));
if ~(isscalar(periodSlots) && isfinite(periodSlots) && periodSlots >= 1 && ...
        periodSlots == round(periodSlots) && isscalar(offsetSlots) && ...
        isfinite(offsetSlots) && offsetSlots >= 0 && offsetSlots < periodSlots && ...
        offsetSlots == round(offsetSlots))
    error("sixgr:pdsch:InvalidCSIRSOccasionConfig", ...
        "Enabled CSI-RS requires integer phy.csirs.period_slots and offset_slots.");
end
absoluteSlot0 = double(sixgr.util.structGet(cfg, ...
    "lls6g.runtime.AbsoluteSlotIndex0", double(carrier.NSlot)));
if mod(absoluteSlot0 - offsetSlots, periodSlots) ~= 0
    event.Scheduled = false;
    event.RuntimeMaterializationStatus = "configured_not_scheduled_this_slot";
    event.Blocker = "outside_yaml_csirs_period_offset";
    event.UpdateOutcome = "not_scheduled";
    event.Periodicity = string(periodSlots) + ":" + string(offsetSlots);
    return;
end
event.Scheduled = true;
try
    [csirsInd, csirsSym, csirsInfo, csirsCfg] = sixgr.phy.refsig.csirs(carrier, cfg);
catch ME
    error("sixgr:pdsch:CSIRSResourceResolutionFailed", ...
        "Enabled CSI-RS could not be resolved before PDSCH coding: %s", ME.message);
end
event.RuntimeEvidenceSource = "sixgr.phy.dl.PDSCH_Tx:csirs_runtime_grid_mapping";
event.NRE = double(numel(csirsSym));
event.NumResources = double(sixgr.util.structGet(csirsInfo, "NumResources", 1));
event.ResourceIDs = localFormatNumericVector(sixgr.util.structGet(csirsInfo, "ResourceIDs", ...
    sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0)));
event.SymbolLocations = localFormatNumericVector(sixgr.util.structGet(csirsInfo, ...
    "SymbolLocations", localObjectValue(csirsCfg, "SymbolLocations", [])));
event.SubcarrierLocations = localFormatNumericVector(sixgr.util.structGet(csirsInfo, ...
    "SubcarrierLocations", localObjectValue(csirsCfg, "SubcarrierLocations", [])));
event.RBOffset = localFirstFiniteScalarValue(sixgr.util.structGet(csirsInfo, "RBOffset", NaN), ...
    localObjectValue(csirsCfg, "RBOffset", NaN));
event.NumRB = localFirstFiniteScalarValue(sixgr.util.structGet(csirsInfo, "NumRB", NaN), ...
    localObjectValue(csirsCfg, "NumRB", NaN));
event.NumPorts = double(sixgr.util.structGet(csirsInfo, "NumCSIRSPorts", NaN));
event.RowNumber = double(sixgr.util.structGet(csirsInfo, "RowNumber", NaN));
event.CSIRSType = string(localObjectValue(csirsCfg, "CSIRSType", "nzp"));
event.Density = string(localObjectValue(csirsCfg, "Density", ""));
event.Periodicity = localFormatCSIRSPeriod(localObjectValue(csirsCfg, "CSIRSPeriod", ""));
if isempty(csirsSym)
    error("sixgr:pdsch:CSIRSResourceResolutionFailed", ...
        "Enabled CSI-RS resolved to an empty resource.");
else
    event.RuntimeMaterializationStatus = "generated_not_yet_mapped";
    event.UpdateOutcome = "generated_runtime_symbols";
end
end

function event = localEmptyCSIRSEvent(cfg)
event = struct();
event.SignalFamily = "CSI-RS";
event.SignalDirection = "DL";
event.ResourceID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceID", 0));
event.ResourceSetID = double(sixgr.util.structGet(cfg, "phy.csirs.resourceSetID", 0));
event.Scheduled = false;
event.Transmitted = false;
event.Observed = false;
event.Consumed = false;
event.Consumer = "";
event.RuntimeMaterializationStatus = "";
event.Blocker = "";
event.UpdateOutcome = "";
event.RuntimeEvidenceSource = "";
event.NRE = NaN;
event.NumPorts = NaN;
event.RowNumber = NaN;
event.CSIRSType = "";
event.Density = "";
event.Periodicity = "";
event.SymbolLocations = "";
event.SubcarrierLocations = "";
event.RBOffset = NaN;
event.NumRB = NaN;
event.NumResources = NaN;
event.ResourceIDs = "";
event.ResourceEvents = repmat(localEmptyMappedCSIRSResourceEvent(), 0, 1);
event.PhysicalPortCount = NaN;
event.PrecoderSource = "";
event.PrecoderDigests = strings(0,1);
end

function localAssertAuxiliaryResourceDisjoint(csirsInd, pdschInd, dmrsInd, ptrsInd)
csirsSet = localIndexSet(csirsInd);
if isempty(csirsSet)
    return;
end

checks = {pdschInd, "pdsch"; dmrsInd, "dmrs"; ptrsInd, "ptrs"};
for i = 1:size(checks, 1)
    other = localIndexSet(checks{i, 1});
    if ~isempty(other) && ~isempty(intersect(csirsSet, other))
        error("sixgr:pdsch:DataDMRSPTRSReservedCollision", ...
            "CSI-RS collides with resolved %s resources before PDSCH coding.", ...
            string(checks{i, 2}));
    end
end
end

function enabled = localRequestedPTRSEnabled(cfg, opt, phyGrant, hasPHYGrant)
if hasPHYGrant
    enabled = logical(sixgr.util.structGet(phyGrant, ...
        "CodingLayout.PTRSEnabled", false));
elseif ~isempty(opt.PDSCH)
    enabled = logical(localObjectValue(opt.PDSCH, "EnablePTRS", false));
elseif isa(opt.ReferenceSignalConfig, ...
        "sixgr.pdsch.PDSCHReferenceSignalConfig")
    enabled = logical(opt.ReferenceSignalConfig.get("EnablePTRS"));
else
    enabled = logical(sixgr.util.structGet(cfg, "phy.pdsch.enablePTRS", ...
        sixgr.util.structGet(cfg, "phy.ptrs.enable", false)));
end
end

function values = localIndexSet(ind)
values = [];
if isempty(ind)
    return;
end
try
    values = unique(double(ind(:)));
    values = values(isfinite(values));
catch
    values = [];
end
end

function text = localFormatNumericVector(values)
try
    values = double(values(:).');
catch
    values = [];
end
values = values(isfinite(values));
if isempty(values)
    text = "";
else
    text = strjoin(string(values), "|");
end
end

function text = localFormatCSIRSPeriod(value)
if isnumeric(value)
    text = localFormatNumericVector(value);
else
    text = string(value);
end
end

function value = localObjectValue(obj, propName, defaultValue)
value = defaultValue;
if isempty(obj)
    return;
end
try
    raw = obj.(propName);
catch
    return;
end
if isempty(raw)
    return;
end
value = raw;
end

function grid = localMapToGrid(grid, ind, sym)
if isempty(ind) || isempty(sym)
    return;
end

indLin = ind(:);
symLin = sym(:);
if numel(indLin) == numel(symLin)
    grid(indLin) = symLin;
    return;
end

if isnumeric(ind) && size(ind,1) == numel(symLin) && size(ind,2) >= 1
    grid(ind(:,1)) = symLin;
    return;
end

error('sixgr:phy:dl:PDSCHGridMappingMismatch', ...
    ['PDSCH grid mapping requires one symbol per resource element. ' ...
     'IndexCount=%d SymbolCount=%d IndexShape=%s SymbolShape=%s.'], ...
    numel(indLin), numel(symLin), mat2str(size(ind)), mat2str(size(sym)));
end

function numTxAnt = localResolveNumTxAnt(cfg, requested, prec)
if isempty(requested)
    if prec.Active
        numTxAnt = prec.NumPorts;
    else
        numTxAnt = double(sixgr.util.structGet(cfg, 'phy.nTxAnt', 1));
    end
else
    numTxAnt = double(requested);
end

numTxAnt = max(1, round(numTxAnt));
if prec.Active && numTxAnt ~= prec.NumPorts
    error("PDSCH_Tx:NumTxAntMismatch", ...
        "Explicit PDSCH precoding resolves to %d antenna port(s), but NumTxAnt=%d.", ...
        prec.NumPorts, numTxAnt);
end
end

function contract = localBuildResourceGridPortContract(txGrid, pdschAntInd, pdschAntSym, ...
    dmrsAntInd, dmrsAntSym, ptrsInd, ptrsSym, csirsInd, csirsSym, csirsEvent, numTxAnt, prec)
gridNumPages = max(1, size(txGrid, 3));
pdschPorts = localResolveMappedPortCount(pdschAntInd, pdschAntSym, 0);
dmrsPorts = localResolveMappedPortCount(dmrsAntInd, dmrsAntSym, 0);
ptrsPorts = localResolveMappedPortCount(ptrsInd, ptrsSym, 0);
csirsIndexPorts = localResolveMappedPortCount(csirsInd, csirsSym, 0);
csirsRequestedPorts = localNormalizeNonnegativePortCount(sixgr.util.structGet(csirsEvent, "NumPorts", 0));
primarySignalPorts = max([pdschPorts, dmrsPorts, ptrsPorts, 1]);
channelEstimatePorts = max([pdschPorts, dmrsPorts, 1]);
expansionSources = strings(0, 1);

if gridNumPages > primarySignalPorts
    if numTxAnt > primarySignalPorts
        expansionSources(end+1, 1) = "configured_tx_antennas";
    end
    if csirsRequestedPorts > primarySignalPorts
        expansionSources(end+1, 1) = "csirs_runtime_ports";
    end
    if csirsIndexPorts > primarySignalPorts
        expansionSources(end+1, 1) = "csirs_index_pages";
    end
end
if isempty(expansionSources)
    expansionSources = "primary_signal_ports_only";
end

contract = struct();
contract.GridNumPages = double(gridNumPages);
contract.ConfiguredTxAntennaPages = double(max(1, round(numTxAnt)));
contract.PDSCHAntennaPortCount = double(pdschPorts);
contract.DMRSAntennaPortCount = double(dmrsPorts);
contract.PTRSAntennaPortCount = double(ptrsPorts);
contract.CSIRSRequestedPortCount = double(csirsRequestedPorts);
contract.CSIRSIndexPageCount = double(csirsIndexPorts);
contract.PrimarySignalPortCount = double(primarySignalPorts);
contract.ChannelEstimateSignalPortCount = double(channelEstimatePorts);
contract.GridPagesExceedPrimarySignalPorts = logical(gridNumPages > primarySignalPorts);
contract.GridPageExpansionSources = expansionSources;
contract.PDSCHDMRSPortAlignmentOk = logical(dmrsPorts <= 0 || dmrsPorts == pdschPorts);
contract.PrecodingPortAlignmentOk = logical(~logical(prec.Active) || ...
    (pdschPorts == double(prec.NumPorts) && dmrsPorts == double(prec.NumPorts)));
contract.ResourceSelectiveChannelEstimateRequired = logical(channelEstimatePorts > 1);
contract.ScalarOrUnitShortcutEligibleBySignalGeometry = logical(channelEstimatePorts <= 1);
end

function localValidateResourceGridPortContract(contract, prec)
gridNumPages = double(contract.GridNumPages);
primarySignalPorts = double(contract.PrimarySignalPortCount);
configuredTxPages = double(contract.ConfiguredTxAntennaPages);
if gridNumPages < max([primarySignalPorts, configuredTxPages, 1])
    error("PDSCH_Tx:ResourceGridPageContractViolation", ...
        "Transmit grid has %d page(s), but truthful DL mapping requires at least %d page(s).", ...
        round(gridNumPages), round(max([primarySignalPorts, configuredTxPages, 1])));
end
if ~logical(contract.PDSCHDMRSPortAlignmentOk)
    error("PDSCH_Tx:DMRSPortAlignmentViolation", ...
        "PDSCH antenna port count (%d) and DM-RS antenna port count (%d) must match.", ...
        round(double(contract.PDSCHAntennaPortCount)), round(double(contract.DMRSAntennaPortCount)));
end
if ~logical(contract.PrecodingPortAlignmentOk)
    error("PDSCH_Tx:PrecodingPortAlignmentViolation", ...
        "Precoding resolves to %d port(s), but the mapped PDSCH/DM-RS antenna ports are %d/%d.", ...
        round(double(prec.NumPorts)), round(double(contract.PDSCHAntennaPortCount)), ...
        round(double(contract.DMRSAntennaPortCount)));
end
end

function numPorts = localResolveMappedPortCount(ind, sym, emptyValue)
if nargin < 3
    emptyValue = 0;
end
numPorts = emptyValue;
if isnumeric(ind) && ~isempty(ind)
    if ~isvector(ind)
        numPorts = size(ind, 2);
    else
        numPorts = 1;
    end
elseif isnumeric(sym) && ~isempty(sym)
    if ~isvector(sym)
        numPorts = size(sym, 2);
    else
        numPorts = 1;
    end
end
numPorts = localNormalizeNonnegativePortCount(numPorts);
end

function numPorts = localNormalizeNonnegativePortCount(value)
numPorts = double(value);
if ~(isscalar(numPorts) && isfinite(numPorts) && numPorts >= 0)
    numPorts = 0;
end
numPorts = round(numPorts);
end

function [dmrsSym, info] = localApplyPDSCHDMRSEPREDifference(dmrsSym, cfg)
[dmrsSym, info] = sixgr.phy.dl.applyPDSCHDMRSEPREDifference(dmrsSym, cfg);
end
