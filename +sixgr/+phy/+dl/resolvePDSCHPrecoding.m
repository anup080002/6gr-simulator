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
prec.NormalizeW = false;
prec.NumLayers = nLayers;
prec.NumPorts = nLayers;
prec.NumCodewords = nCodewords;
prec.WidebandOnly = true;
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

if isempty(Wcfg)
    [Wcfg, pmiMeta] = localResolvePMIPrecodingMatrix(cfg, nLayers, requestedPorts);
else
    pmiMeta = struct();
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
prec.NormalizeW = normalizeW;
prec.NumPorts = size(Wports, 1);
prec.MatrixPorts = Wports;
prec.MatrixNR = reshape(Wports.', [nLayers, size(Wports, 1), 1]);
prec.ChannelMatrixNR = permute(prec.MatrixNR, [2 1 3]);

end

function nCodewords = localNumCodewords(pdsch, nLayers)
nCodewords = 1 + (nLayers > 4);
try
    nCodewords = double(pdsch.NumCodewords);
catch
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
end
