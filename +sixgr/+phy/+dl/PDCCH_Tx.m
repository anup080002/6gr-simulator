function [tx, info] = PDCCH_Tx(cfg, varargin)
%PDCCH_Tx Generate a basic PDCCH transmission for one slot.
%
%   [TX,INFO] = sixgr.phy.dl.PDCCH_Tx(CFG) builds a carrier and PDCCH
%   configuration from CFG (plus safe defaults), encodes an explicit or
%   deterministic DCI
%   payload, maps PDCCH symbols + DMRS into a resource grid, and produces an
%   OFDM waveform.
%
%   This module intentionally reuses 5G Toolbox engines:
%     nrPDCCHConfig / nrCORESETConfig / nrSearchSpaceConfig
%     nrPDCCHResources, nrDCIEncode, nrPDCCH
%     nrResourceGrid, nrOFDMModulate
%
%   Name-Value options:
%     "Carrier"     : nrCarrierConfig to use (default: from cfg)
%     "PDCCH"       : nrPDCCHConfig to use (default: from cfg)
%     "DCIBits"     : int8 column vector (default: grant DCI or zeros)
%     "Grant"       : finalized scheduler grant with DCI.Bits (optional)
%     "K"           : DCI payload length (default: cfg.phy.pdcch.KBits or 64)
%     "RNTI"        : scalar DCI CRC-mask RNTI (default: cfg.phy.pdcch.rnti or 4660)
%     "PDCCHScramblingRNTI" : scalar physical PDCCH scrambling RNTI
%                    (default: cfg.phy.pdcch.scramblingRNTI, or 0 for
%                    SI-RNTI/common search space, otherwise RNTI)
%     "NCellID"     : scalar NCellID (default: cfg.scenario.NCellID or 1)
%     "NumTxAnt"    : number of TX antennas/ports for resource grid (default: 1)
%     "OFDMModulate": true/false (default: true)
%     "AllowRandomDCI": true/false legacy standalone random payload opt-in
%
%   Outputs:
%     TX: struct with fields:
%       .Carrier, .PDCCH
%       .DCIBits, .DCICW
%       .PDCCHInd, .DMRSInd, .DMRSSym
%       .Grid, .Waveform
%
%   INFO: struct of helper values (E, K, etc.)

% Parse options
p = inputParser;
p.addParameter('Carrier', [], @(x) isempty(x) || isobject(x));
p.addParameter('PDCCH', [], @(x) isempty(x) || isobject(x));
p.addParameter('DCIBits', [], @(x) isempty(x) || (isnumeric(x) && isvector(x)));
p.addParameter('Grant', struct(), @(x) isempty(x) || isstruct(x));
p.addParameter('K', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x>0));
p.addParameter('RNTI', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('PDCCHScramblingRNTI', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('NCellID', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
p.addParameter('NumTxAnt', 1, @(x) isnumeric(x) && isscalar(x) && x>=1);
p.addParameter('OFDMModulate', true, @(x) islogical(x) && isscalar(x));
p.addParameter('AllowRandomDCI', false, @(x) islogical(x) || (isnumeric(x) && isscalar(x)));
p.parse(varargin{:});
opt = p.Results;

% Carrier
if isempty(opt.Carrier)
    [carrier, ~] = sixgr.phy.grid.makeCarrier(cfg);
else
    carrier = opt.Carrier;
end

% Cell/RNTI
nCellID = opt.NCellID;
if isempty(nCellID)
    nCellID = sixgr.util.structGet(cfg, 'phy.carrier.NCellID', ...
        sixgr.util.structGet(cfg, 'scenario.NCellID', 1));
end
rnti = opt.RNTI;
if isempty(rnti)
    rnti = sixgr.util.structGet(cfg, 'phy.pdcch.rnti', 4660);
end
rnti = double(rnti);
pdcchScramblingRNTI = localResolvePDCCHScramblingRNTI(cfg, rnti, opt.PDCCHScramblingRNTI);

% PDCCH config
if isempty(opt.PDCCH)
    pdcch = localDefaultPDCCH(cfg, carrier, nCellID, localPDCCHConfigRNTI(rnti, pdcchScramblingRNTI));
else
    pdcch = opt.PDCCH;
end

% Indices and DMRS for this PDCCH allocation.
% Output order is [indices, dmrsSymbols, dmrsIndices].
[pdcchInd, dmrsSym, dmrsInd] = nrPDCCHResources(carrier, pdcch);

% Encoded length E (bits) for QPSK
E = 2 * numel(pdcchInd);

% DCI payload bits
if isempty(opt.K)
    K = sixgr.util.structGet(cfg, 'phy.pdcch.KBits', 64);
else
    K = double(opt.K);
end

[dciBits, payloadSource, randomPayload] = localResolveDCIPayload(cfg, opt, K);
K = numel(dciBits);

% DCI encoding (Polar + CRC mask by the DCI RNTI)
% dciCW length must be E.
dciCW = nrDCIEncode(dciBits, rnti, E);

% PDCCH modulation (38.211 scrambling).  Common-search-space SI-RNTI DCI
% uses SI-RNTI for CRC masking, but physical PDCCH scrambling uses nRNTI=0.
pdcchSym = nrPDCCH(dciCW, nCellID, pdcchScramblingRNTI);

% Build resource grid and map symbols
numTxAnt = double(opt.NumTxAnt);
txGrid = nrResourceGrid(carrier, numTxAnt);

% Map PDCCH and DMRS (single port typical; for multiport, indices include antenna dimension)
txGrid(pdcchInd) = pdcchSym;
txGrid(dmrsInd)  = dmrsSym;

% OFDM modulate
if opt.OFDMModulate
    txWaveform = sixgr.phy.waveform.ofdmModulate(carrier, txGrid);
else
    txWaveform = [];
end

% Outputs
tx = struct();
tx.Carrier   = carrier;
tx.PDCCH     = pdcch;
tx.DCIBits   = dciBits;
tx.DCICW     = dciCW;
tx.PDCCHInd  = pdcchInd;
tx.DMRSInd   = dmrsInd;
tx.DMRSSym   = dmrsSym;
tx.Grid      = txGrid;
tx.Waveform  = txWaveform;

info = struct();
info.K = K;
info.E = E;
info.NumPDCCHRE = numel(pdcchInd);
info.NumDMRSRE  = numel(dmrsInd);
info.NCellID = nCellID;
info.RNTI = rnti;
info.DCICrcRNTI = rnti;
info.PDCCHScramblingRNTI = pdcchScramblingRNTI;
info.DCIPayloadSource = char(payloadSource);
info.RandomDCIPayload = logical(randomPayload);
info.Note = 'PDCCH uses built-in 5G Toolbox functions with explicit DCI CRC RNTI and physical scrambling RNTI separation.';

end

% -------------------------------------------------------------------------
function [dciBits, source, randomPayload] = localResolveDCIPayload(cfg, opt, K)
randomPayload = false;
if ~isempty(opt.DCIBits)
    dciBits = int8(opt.DCIBits(:));
    source = "explicit_DCIBits_argument";
    return;
end

grantBits = localGrantDCIBits(opt.Grant);
if ~isempty(grantBits)
    dciBits = int8(grantBits(:));
    source = "finalized_scheduler_grant_dci_bits";
    return;
end

configuredBits = sixgr.util.structGet(cfg, 'phy.pdcch.dciBits', []);
if ~isempty(configuredBits)
    dciBits = int8(configuredBits(:));
    source = "configured_phy_pdcch_dciBits";
    return;
end

if logical(opt.AllowRandomDCI)
    dciBits = int8(randi([0 1], K, 1));
    source = "legacy_random_dci_payload_opt_in";
    randomPayload = true;
    return;
end

dciBits = int8(zeros(max(1, round(double(K))), 1));
source = "deterministic_zero_dci_payload";
end

function bits = localGrantDCIBits(grant)
bits = [];
if ~(isstruct(grant) && ~isempty(fieldnames(grant)))
    return;
end
dci = sixgr.util.structGet(grant, "DCI", struct());
if isstruct(dci) && isfield(dci, "Bits") && ~isempty(dci.Bits)
    bits = dci.Bits;
end
end

function scramblingRNTI = localResolvePDCCHScramblingRNTI(cfg, dciRNTI, optScramblingRNTI)
if ~isempty(optScramblingRNTI)
    scramblingRNTI = double(optScramblingRNTI);
    return;
end
configured = sixgr.util.structGet(cfg, 'phy.pdcch.scramblingRNTI', []);
if ~isempty(configured)
    scramblingRNTI = double(configured);
    return;
end
if double(dciRNTI) == 65535
    scramblingRNTI = 0;
else
    scramblingRNTI = double(dciRNTI);
end
end

function configRNTI = localPDCCHConfigRNTI(dciRNTI, scramblingRNTI)
% nrPDCCHConfig validators reject SI-RNTI, but resource generation only
% needs a valid object.  Use the physical scrambling RNTI for common-space
% SI PDCCH and the DCI RNTI otherwise.
if double(dciRNTI) == 65535
    configRNTI = double(scramblingRNTI);
else
    configRNTI = double(dciRNTI);
end
end

function pdcch = localDefaultPDCCH(cfg, carrier, nCellID, rnti)
%LOCALDEFAULTPDCCH Minimal, safe PDCCH configuration.
%
% We keep this intentionally simple so it works out-of-the-box.

% CORESET covering a small portion of bandwidth (avoid config validation issues)
coreset = nrCORESETConfig;
coresetID = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.id', 0));
[coreset, ~] = localSetPropIfPresent(coreset, {'CORESETID','ID'}, coresetID);

% Duration in OFDM symbols (1..3)
coreset.Duration = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.duration', 2));

% FrequencyResources is a binary row vector; length depends on CORESET definition.
% Use a conservative 6-bit bitmap (commonly used in examples) and allow user override.
fr = sixgr.util.structGet(cfg, 'phy.pdcch.coreset.frequencyResources', []);
if isempty(fr)
    fr = ones(1, 6); % numeric, not logical
else
    fr = double(fr(:).');
end
coreset.FrequencyResources = fr;

% Optional CORESET parameters
coreset.REGBundleSize = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.regBundleSize', coreset.REGBundleSize));
coreset.InterleaverSize = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.interleaverSize', coreset.InterleaverSize));
coreset.ShiftIndex = double(sixgr.util.structGet(cfg, 'phy.pdcch.coreset.shiftIndex', nCellID));

% Search space
ss = nrSearchSpaceConfig;
searchSpaceID = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.id', 1));
[ss, ~] = localSetPropIfPresent(ss, {'SearchSpaceID','ID'}, searchSpaceID);
ss.CORESETID = localGetFirstProp(coreset, {'CORESETID','ID'}, 0);
ss.StartSymbolWithinSlot = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.startSymbol', 0));
ss.SlotPeriodAndOffset = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.slotPeriodAndOffset', [1 0]));
ss.Duration = double(sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.duration', 1));

% Aggregation level and search-space candidates for [1 2 4 8 16].
aggr = double(sixgr.util.structGet(cfg, 'phy.pdcch.aggregationLevel', 4));
if ~ismember(aggr, [1 2 4 8 16])
    aggr = 4;
end
numCand = sixgr.util.structGet(cfg, 'phy.pdcch.searchSpace.numCandidates', []);
numCand = double(numCand(:).');
if isempty(numCand)
    numCand = zeros(1,5);
end
if numel(numCand) < 5
    numCand(numel(numCand)+1:5) = 0;
end
numCand = numCand(1:5);
idxAgg = find([1 2 4 8 16] == aggr, 1, 'first');
if isempty(idxAgg)
    idxAgg = 3;
end
if numCand(idxAgg) < 1
    numCand(idxAgg) = 1;
end
ss.NumCandidates = double(numCand(:).');

% PDCCH config
pdcch = nrPDCCHConfig;
[pdcch, ~] = localSetPropIfPresent(pdcch, {'NCellID','DMRSScramblingID'}, double(nCellID));
pdcch.RNTI = double(rnti);
pdcch.CORESET = coreset;
pdcch.SearchSpace = ss;

% Aggregation level (must correspond to nonzero candidate count)
pdcch.AggregationLevel = aggr;

% Keep transmitter BWP explicit so it stays aligned with the carrier grid and
% matches the receiver-side default builder.
try
    pdcch.NStartBWP = double(sixgr.util.structGet(cfg, 'phy.pdcch.nStartBWP', carrier.NStartGrid));
    pdcch.NSizeBWP  = double(sixgr.util.structGet(cfg, 'phy.pdcch.nSizeBWP', carrier.NSizeGrid));
catch
    % Ignore if these properties are unavailable in the installed toolbox.
end

end

function [obj, tf] = localSetPropIfPresent(obj, propNames, value)
tf = false;
for i = 1:numel(propNames)
    p = char(string(propNames{i}));
    if isprop(obj, p)
        try
            obj.(p) = value;
            tf = true;
            return;
        catch
        end
    end
end
end

function v = localGetFirstProp(obj, propNames, defaultVal)
v = defaultVal;
for i = 1:numel(propNames)
    p = char(string(propNames{i}));
    if isprop(obj, p)
        try
            v = obj.(p);
            return;
        catch
        end
    end
end
end
