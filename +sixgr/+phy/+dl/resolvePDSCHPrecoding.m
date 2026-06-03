function prec = resolvePDSCHPrecoding(pdsch, cfg, varargin)
%RESOLVEPDSCHPRECODING Normalize the explicit PDSCH precoding contract.
%
%   PREC = sixgr.phy.dl.resolvePDSCHPrecoding(PDSCH, CFG) keeps the 1x1
%   path on a direct map and enables explicit wideband precoding for
%   multi-layer or explicitly configured transmissions.

ip = inputParser;
ip.addParameter("PrecodingMatrix", [], @(x) isempty(x) || isnumeric(x));
ip.addParameter("NormalizeW", [], @(x) isempty(x) || islogical(x) || (isnumeric(x) && isscalar(x)));
ip.parse(varargin{:});
opt = ip.Results;

nLayers = double(pdsch.NumLayers);
nCodewords = localNumCodewords(pdsch, nLayers);

prec = struct();
prec.Active = false;
prec.Mode = "siso-bypass";
prec.Source = "none";
prec.ApplicationStage = "none";
prec.NormalizeW = false;
prec.NumLayers = nLayers;
prec.NumPorts = nLayers;
prec.NumCodewords = nCodewords;
prec.WidebandOnly = true;
prec.PMI = NaN;
prec.PMIType = "";
prec.CodebookMode = "";
prec.BeamIndices = [];
prec.MatrixRows = max(nLayers, 1);
prec.MatrixCols = max(nLayers, 1);
prec.MatrixPorts = eye(max(nLayers, 1));
prec.MatrixNR = reshape(eye(max(nLayers, 1)), [max(nLayers, 1), max(nLayers, 1), 1]);
prec.ChannelMatrixNR = permute(prec.MatrixNR, [2 1 3]);

if nCodewords > 1 || nLayers > 4
    error("sixgr:phy:dl:PDSCHPrecoding:MultiCodewordUnsupported", ...
        "PDSCH_Tx/PDSCH_Rx support a single codeword only. Requested %d layer(s) implies %d codeword(s).", ...
        nLayers, nCodewords);
end

Wcfg = opt.PrecodingMatrix;
if isempty(Wcfg)
    Wcfg = sixgr.util.structGet(cfg, "phy.pdsch.precoding.matrix", []);
end
if isempty(Wcfg)
    Wcfg = sixgr.util.structGet(cfg, "phy.pdsch.precodingMatrix", []);
end
if isempty(Wcfg)
    Wcfg = sixgr.util.structGet(cfg, "phy.pdsch.W", []);
end

requestedPorts = sixgr.util.structGet(cfg, "phy.pdsch.numPorts", []);
if isempty(requestedPorts)
    requestedPorts = sixgr.util.structGet(cfg, "phy.pdsch.nPorts", []);
end
if ~isempty(requestedPorts)
    requestedPorts = max(1, round(double(requestedPorts)));
end

if ~isempty(Wcfg) && ~localExplicitMatrixHasLayerShape(Wcfg, nLayers)
    if localHasFinitePMI(cfg)
        % A grant replay can carry a stale rank-1 explicit beam from an
        % earlier snapshot while the current grant has a higher RI.  Do not
        % reshape that matrix; regenerate the rank-consistent codebook
        % precoder from the grant PMI/TPMI and requested port count.
        Wcfg = [];
    else
        sz = size(Wcfg);
        error("sixgr:phy:dl:PDSCHPrecoding:ExplicitMatrixLayerMismatch", ...
            "Explicit PDSCH precoding matrix must be Nports-by-Nlayers or Nlayers-by-Nports. Got %dx%d for %d layer(s), with no finite PMI/TPMI to regenerate it.", ...
            sz(1), sz(2), nLayers);
    end
end

if isempty(Wcfg)
    [Wcfg, pmiMeta] = localResolvePMIPrecodingMatrix(cfg, nLayers, requestedPorts);
else
    pmiMeta = localResolveExplicitMatrixMetadata(cfg, Wcfg, nLayers, requestedPorts);
end

normalizeW = opt.NormalizeW;
if isempty(normalizeW)
    normalizeW = logical(sixgr.util.structGet(cfg, "phy.pdsch.normalizePrecodingMatrix", true));
end

if isempty(Wcfg)
    if nLayers == 1
        prec.NormalizeW = normalizeW;
        return;
    end
    if ~isempty(requestedPorts) && requestedPorts ~= nLayers
        error("sixgr:phy:dl:PDSCHPrecoding:NumPortsNeedsMatrix", ...
            "Requested %d PDSCH port(s) for %d layer(s). Provide an explicit PrecodingMatrix for multi-port DL precoding.", ...
            requestedPorts, nLayers);
    end
    Wports = eye(nLayers);
    source = "identity";
else
    if ndims(Wcfg) > 2 && size(Wcfg, 3) ~= 1
        error("sixgr:phy:dl:PDSCHPrecoding:PRGBundleUnsupported", ...
            "Only wideband 2-D PDSCH precoding matrices are supported in this release.");
    end
    [~, precInfo] = sixgr.phy.mimo.precoder(eye(nLayers), Wcfg, "NormalizeW", normalizeW);
    Wports = double(precInfo.W);
    if isstruct(pmiMeta) && isfield(pmiMeta, "Source") && strlength(string(pmiMeta.Source)) > 0
        source = string(pmiMeta.Source);
    else
        source = "explicit-matrix";
    end
end

if size(Wports, 2) ~= nLayers
    error("sixgr:phy:dl:PDSCHPrecoding:DimMismatch", ...
        "Resolved precoding matrix must be Nports-by-Nlayers. Got %dx%d for %d layer(s).", ...
        size(Wports, 1), size(Wports, 2), nLayers);
end

if size(Wports, 1) < nLayers
    error("sixgr:phy:dl:PDSCHPrecoding:TooFewPorts", ...
        "Explicit PDSCH precoding requires NumPorts >= NumLayers. Got %d port(s) for %d layer(s).", ...
        size(Wports, 1), nLayers);
end

if ~isempty(requestedPorts) && size(Wports, 1) ~= requestedPorts
    error("sixgr:phy:dl:PDSCHPrecoding:NumPortsMismatch", ...
        "PrecodingMatrix resolves to %d port(s), but cfg.phy.pdsch.numPorts/nPorts requests %d.", ...
        size(Wports, 1), requestedPorts);
end

if logical(pdsch.EnablePTRS)
    error("sixgr:phy:dl:PDSCHPrecoding:PTRSUnsupported", ...
        "Explicit PDSCH precoding with PTRS enabled is not supported in this release.");
end

dmrsPorts = localDMRSPortSet(pdsch, nLayers);
expectedPorts = 0:(nLayers-1);
if numel(dmrsPorts) ~= nLayers || any(dmrsPorts(:).' ~= expectedPorts)
    error("sixgr:phy:dl:PDSCHPrecoding:DMRSPortSetUnsupported", ...
        "Explicit PDSCH precoding requires DM-RS ports 0:%d. Custom DMRSPortSet is not supported.", ...
        nLayers-1);
end

if exist("nrPDSCHPrecode", "file") ~= 2
    error("sixgr:phy:dl:PDSCHPrecoding:Missing5G", ...
        "nrPDSCHPrecode is required for explicit downlink precoding.");
end

prec.Active = true;
prec.Mode = "explicit-wideband";
prec.Source = source;
prec.ApplicationStage = "nrPDSCHPrecode_before_RE_mapping";
prec.NormalizeW = normalizeW;
prec.NumPorts = size(Wports, 1);
prec.MatrixRows = size(Wports, 1);
prec.MatrixCols = size(Wports, 2);
prec.MatrixPorts = Wports;
prec.MatrixNR = reshape(Wports.', [nLayers, size(Wports, 1), 1]);
prec.ChannelMatrixNR = permute(prec.MatrixNR, [2 1 3]);
if isstruct(pmiMeta)
    if isfield(pmiMeta, "PMI")
        prec.PMI = double(pmiMeta.PMI);
    end
    if isfield(pmiMeta, "PMIType")
        prec.PMIType = string(pmiMeta.PMIType);
    end
    if isfield(pmiMeta, "CodebookMode")
        prec.CodebookMode = string(pmiMeta.CodebookMode);
    end
    if isfield(pmiMeta, "BeamIndices")
        prec.BeamIndices = double(pmiMeta.BeamIndices);
    end
end

end

function nCodewords = localNumCodewords(pdsch, nLayers)
nCodewords = 1 + (nLayers > 4);
try
    nCodewords = double(pdsch.NumCodewords);
catch
end
end

function tf = localExplicitMatrixHasLayerShape(Wcfg, nLayers)
tf = false;
if isempty(Wcfg)
    return;
end
if ndims(Wcfg) > 2 && size(Wcfg, 3) == 1
    Wcfg = squeeze(Wcfg);
end
if ~ismatrix(Wcfg)
    return;
end
sz = size(Wcfg);
tf = sz(2) == nLayers || sz(1) == nLayers;
end

function tf = localHasFinitePMI(cfg)
tf = false;
paths = ["phy.pdsch.tpmi", "phy.pdsch.TPMI", "phy.pdsch.pmi", "phy.pdsch.PMI"];
for i = 1:numel(paths)
    v = sixgr.util.structGet(cfg, paths(i), []);
    if isnumeric(v) && isscalar(v) && isfinite(double(v))
        tf = true;
        return;
    end
end
end

function dmrsPorts = localDMRSPortSet(pdsch, nLayers)
dmrsPorts = [];
try
    dmrsPorts = double(pdsch.DMRS.DMRSPortSet(:).');
catch
end
if isempty(dmrsPorts)
    dmrsPorts = 0:(nLayers-1);
end
end

function [Wcfg, meta] = localResolvePMIPrecodingMatrix(cfg, nLayers, requestedPorts)
meta = struct();
Wcfg = [];
tpmi = sixgr.util.structGet(cfg, "phy.pdsch.tpmi", []);
if isempty(tpmi)
    tpmi = sixgr.util.structGet(cfg, "phy.pdsch.TPMI", []);
end
if isempty(tpmi)
    tpmi = sixgr.util.structGet(cfg, "phy.pdsch.pmi", []);
end
if isempty(tpmi)
    tpmi = sixgr.util.structGet(cfg, "phy.pdsch.PMI", []);
end
if isempty(tpmi)
    return;
end
if isnumeric(tpmi) && isscalar(tpmi) && ~isfinite(double(tpmi))
    return;
end

if ~(isnumeric(tpmi) && isscalar(tpmi) && isfinite(tpmi))
    error("sixgr:phy:dl:PDSCHPrecoding:BadTPMI", ...
        "phy.pdsch.PMI/TPMI must be a finite scalar numeric value.");
end

numPorts = requestedPorts;
if isempty(numPorts)
    numPorts = sixgr.util.structGet(cfg, "phy.nTxAnt", nLayers);
end
numPorts = max(1, round(double(numPorts)));

mode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ""));
if strlength(strtrim(mode)) == 0
    codebookType = lower(string(sixgr.util.structGet(cfg, "phy.csi.codebookType", "type1")));
    switch codebookType
        case "type1"
            mode = "type1_su_mimo";
        case "type2"
            mode = "type2_mu_mimo";
        case "etype2"
            mode = "etype2_candidate";
        otherwise
            mode = "noncodebook";
    end
end
mode = lower(strtrim(mode));
if mode == "noncodebook"
    error("sixgr:phy:dl:PDSCHPrecoding:NonCodebookPMIUnsupported", ...
        "Scalar PMI/TPMI selection is not defined for noncodebook PDSCH precoding.");
end

[candidates, info] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, numPorts, "Mode", mode);
if isempty(candidates)
    error("sixgr:phy:dl:PDSCHPrecoding:EmptyPMICodebook", ...
        "No PMI/codebook candidates were available for %d port(s), %d layer(s), mode '%s'.", ...
        numPorts, nLayers, mode);
end

pmiIndex = round(double(tpmi));
if pmiIndex < 0 || pmiIndex >= numel(candidates)
    error("sixgr:phy:dl:PDSCHPrecoding:TPMIOutOfRange", ...
        "PMI/TPMI=%d is out of range for mode '%s' with %d candidate(s).", ...
        pmiIndex, mode, numel(candidates));
end

Wcfg = candidates(pmiIndex + 1).W;
meta.Source = "pmi-codebook";
meta.Mode = info.Mode;
meta.PMI = double(pmiIndex);
meta.PMIType = string(candidates(pmiIndex + 1).PMIType);
meta.CodebookMode = string(candidates(pmiIndex + 1).CodebookMode);
meta.BeamIndices = double(candidates(pmiIndex + 1).BeamIndices);
end

function meta = localResolveExplicitMatrixMetadata(cfg, Wcfg, nLayers, requestedPorts)
meta = struct( ...
    "Source", "", ...
    "PMI", NaN, ...
    "PMIType", "", ...
    "CodebookMode", "", ...
    "BeamIndices", []);

userMeta = sixgr.util.structGet(cfg, "lls6g.userContext", struct());
userSource = string(sixgr.util.structGet(userMeta, "PrecoderSource", ""));
if strlength(strtrim(userSource)) > 0
    meta.Source = userSource;
else
    meta.Source = "explicit-matrix";
end

beamToken = string(sixgr.util.structGet(userMeta, "BeamIndexSet", ""));
parsedBeamIdx = localParseBeamIndexSet(beamToken);
if ~isempty(parsedBeamIdx)
    meta.BeamIndices = parsedBeamIdx;
end

Wports = localNormalizeExplicitMatrix(Wcfg, nLayers);
if isempty(Wports)
    return;
end
numPorts = requestedPorts;
if isempty(numPorts)
    numPorts = size(Wports, 1);
end
numPorts = max(1, round(double(numPorts)));

mode = string(sixgr.util.structGet(cfg, "phy.csi.pmiCodebookMode", ""));
if strlength(strtrim(mode)) == 0
    codebookType = lower(string(sixgr.util.structGet(cfg, "phy.csi.codebookType", "type1")));
    switch codebookType
        case "type1"
            mode = "type1_su_mimo";
        case "type2"
            mode = "type2_mu_mimo";
        case "etype2"
            mode = "etype2_candidate";
        otherwise
            mode = "";
    end
end
mode = lower(strtrim(mode));
if strlength(mode) == 0 || mode == "noncodebook"
    return;
end

try
    [candidates, info] = sixgr.phy.dl.pmiCodebookCandidates(cfg, nLayers, numPorts, "Mode", mode);
catch
    candidates = struct([]);
    info = struct();
end
if isempty(candidates)
    return;
end

matchIdx = NaN;
for i = 1:numel(candidates)
    if localMatricesEquivalent(Wports, candidates(i).W)
        matchIdx = i;
        break;
    end
end
if ~(isfinite(matchIdx) && matchIdx >= 1 && matchIdx <= numel(candidates))
    return;
end

matched = candidates(matchIdx);
meta.PMI = double(matched.PMI);
meta.PMIType = string(matched.PMIType);
meta.CodebookMode = string(matched.CodebookMode);
meta.BeamIndices = double(matched.BeamIndices);
if strlength(strtrim(meta.Source)) == 0 || meta.Source == "explicit-matrix"
    meta.Source = "codebook_dft";
end
if isstruct(info) && isfield(info, "Mode") && strlength(string(info.Mode)) > 0
    meta.CodebookMode = string(info.Mode);
end
end

function Wports = localNormalizeExplicitMatrix(Wcfg, nLayers)
Wports = [];
if isempty(Wcfg)
    return;
end
Wtry = Wcfg;
if ndims(Wtry) > 2 && size(Wtry, 3) == 1
    Wtry = squeeze(Wtry);
end
if ~ismatrix(Wtry)
    return;
end
sz = size(Wtry);
if sz(2) ~= nLayers && sz(1) == nLayers
    Wtry = Wtry.';
end
if size(Wtry, 2) ~= nLayers
    return;
end
try
    [~, precInfo] = sixgr.phy.mimo.precoder(eye(nLayers), Wtry, "NormalizeW", true);
    Wports = double(precInfo.W);
catch
    Wports = [];
end
end

function tf = localMatricesEquivalent(Wlhs, Wrhs)
tf = false;
if isempty(Wlhs) || isempty(Wrhs) || ~isequal(size(Wlhs), size(Wrhs))
    return;
end
Wlhs = double(Wlhs);
Wrhs = double(Wrhs);
for c = 1:size(Wlhs, 2)
    lhs = Wlhs(:, c);
    rhs = Wrhs(:, c);
    lhsNorm = norm(lhs);
    rhsNorm = norm(rhs);
    if ~(isfinite(lhsNorm) && lhsNorm > 0 && isfinite(rhsNorm) && rhsNorm > 0)
        return;
    end
    overlap = abs((lhs' * rhs) / (lhsNorm * rhsNorm));
    if ~(isfinite(overlap) && overlap >= (1 - 1e-9))
        return;
    end
end
tf = true;
end

function beamIdx = localParseBeamIndexSet(raw)
beamIdx = [];
raw = string(raw);
if strlength(strtrim(raw)) == 0
    return;
end
tok = regexp(char(raw), "\d+", "match");
if isempty(tok)
    return;
end
beamIdx = unique(round(str2double(string(tok))), "stable");
beamIdx = beamIdx(isfinite(beamIdx) & beamIdx >= 1);
beamIdx = double(beamIdx(:).');
end
