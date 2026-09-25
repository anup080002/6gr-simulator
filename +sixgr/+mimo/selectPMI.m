function [W_opt, pmi_i1, pmi_i2, info] = selectPMI(H_wb, rankValue, nTx, nRx, cfg)
%SELECTPMI Receiver-aware exhaustive PMI selection from measured channel.
%
% This compatibility façade preserves the historical outputs while using a
% post-equalization mutual-information objective. Strict mode requires
% explicit panel geometry and an enabled enumerated codebook. It never
% infers a square panel or uses configured SNR as measurement evidence.

if nargin < 5 || ~isstruct(cfg)
    cfg = struct();
end
strict = logical(sixgr.util.structGet(cfg,"Strict", ...
    sixgr.util.structGet(cfg,"mimo.strict",false)));
H = localOrientMeasuredChannel(H_wb,nTx,strict);
nTxMeasured = size(H,2);
nRxMeasured = size(H,1);
if ~(isscalar(rankValue) && isnumeric(rankValue) && isfinite(rankValue) && ...
        rankValue == round(rankValue) && rankValue >= 1 && ...
        rankValue <= min(nTxMeasured,nRxMeasured))
    error("sixgr:mimo:UnsupportedRank", ...
        "Rank %s is invalid for measured %d-by-%d channel.", ...
        mat2str(rankValue),nRxMeasured,nTxMeasured);
end
if ~isempty(nRx) && isfinite(double(nRx)) && strict && double(nRx) ~= nRxMeasured
    error("sixgr:mimo:UnsupportedAntennaTuple", ...
        "Configured receive antennas differ from the measured channel.");
end

[candidates,candidateIndices,cbInfo] = localCandidates(nTxMeasured,rankValue,cfg,strict);
noiseVariance = double(sixgr.util.structGet(cfg,"NoiseVariance", ...
    sixgr.util.structGet(cfg,"noiseVariance",1)));
if ~(isscalar(noiseVariance) && isfinite(noiseVariance) && noiseVariance >= 0)
    error("sixgr:mimo:MissingMeasurementState", ...
        "Measured noise variance is required for strict PMI selection.");
end
Rint = sixgr.util.structGet(cfg,"InterferenceCovariance",[]);
receiver = string(sixgr.util.structGet(cfg,"Receiver","MMSE"));
[W_opt,decision] = sixgr.phy.mimo.CodebookEngine.select( ...
    H,candidates,NoiseVariance=noiseVariance, ...
    InterferenceCovariance=Rint,Receiver=receiver, ...
    InterferenceCovarianceIncludesNoise=logical(sixgr.util.structGet( ...
        cfg,"InterferenceCovarianceIncludesNoise",false)));
selected = decision.SelectedIndex+1;
pmiLinear = candidateIndices(selected);
pmi_i1 = double(pmiLinear);
pmi_i2 = NaN;

info = cbInfo;
info.Rank = double(rankValue);
info.NumRx = double(nRxMeasured);
info.NumTx = double(nTxMeasured);
info.SelectedPMI = double(pmiLinear);
info.SelectedPMI_i1 = double(pmi_i1);
info.SelectedPMI_i2 = double(pmi_i2);
info.CandidateMetric = decision.CandidateMetric;
info.SelectedMetric = decision.SelectedMetric;
info.SelectedSINRPerRELayer = decision.SelectedSINRPerRELayer;
info.SelectedGain = decision.SelectedMetric; % compatibility label only
info.SelectionMetric = "mean_log2_one_plus_measured_mmse_layer_sinr";
info.SelectionObjective = decision.Objective;
info.Receiver = decision.Receiver;
info.ConfiguredSNRUsed = false;
info.SVDThresholdUsed = false;
info.MatrixSHA256 = decision.MatrixSHA256;
info.RuntimeEvidenceSource = "measured_channel_noise_and_covariance";
end

function H = localOrientMeasuredChannel(Hin,nTx,strict)
if isempty(Hin) || ~isnumeric(Hin)
    error("sixgr:mimo:MissingMeasurementState", ...
        "PMI selection requires a measured channel matrix.");
end
H = Hin;
if ndims(H) > 3 || any(~isfinite(real(H(:))) | ~isfinite(imag(H(:))))
    error("sixgr:mimo:MissingMeasurementState", ...
        "Measured channel must be a finite matrix or frequency stack.");
end
if nargin >= 2 && ~isempty(nTx) && isnumeric(nTx) && isfinite(double(nTx))
    nTx = round(double(nTx));
    if size(H,2) ~= nTx
        if ~strict && size(H,1) == nTx
            H = H.';
        else
            error("sixgr:mimo:UnsupportedAntennaTuple", ...
                "Channel orientation must be Nrx-by-Nport; received %s for %d ports.", ...
                mat2str(size(H)),nTx);
        end
    end
end
end

function [candidates,indices,info] = localCandidates(nTx,rankValue,cfg,strict)
explicit = sixgr.util.structGet(cfg,"CandidateMatrices",[]);
if ~isempty(explicit)
    candidates = explicit;
    if ndims(candidates) < 3
        candidates = reshape(candidates,size(candidates,1),size(candidates,2),1);
    end
    if size(candidates,1) ~= nTx || size(candidates,2) ~= rankValue
        error("sixgr:mimo:PrecoderDimensionMismatch", ...
            "Explicit candidate matrices must be Nport-by-rank-by-Ncandidate.");
    end
    indices = double(sixgr.util.structGet(cfg,"CandidateIndices", ...
        (0:size(candidates,3)-1).'));
    if numel(indices) ~= size(candidates,3)
        error("sixgr:mimo:InvalidPMI", ...
            "CandidateIndices must identify every candidate matrix.");
    end
    for index = 1:size(candidates,3)
        sixgr.phy.mimo.MatrixContract.validate( ...
            candidates(:,:,index),nTx,rankValue);
    end
    info = struct("CodebookType","explicit_frozen_candidates", ...
        "GenericDFTApproximationUsed",false, ...
        "NormativeSubset",logical(sixgr.util.structGet(cfg,"NormativeSubset",false)));
    return;
end

codebookType = lower(string(sixgr.util.structGet(cfg,"CodebookType", ...
    sixgr.util.structGet(cfg,"phy.csi.codebookType","typeI-SinglePanel"))));
if nTx == 2 && contains(codebookType,"typei") && ...
        ~contains(codebookType,"typeii")
    candidates = sixgr.phy.mimo.TypeI2PortCodebook.enumerate(rankValue);
    indices = (0:size(candidates,3)-1).';
    info = struct( ...
        "CodebookType","typeI-SinglePanel", ...
        "GenericDFTApproximationUsed",false, ...
        "NormativeSubset",true, ...
        "Specification","TS38.214-V18.9.0-Table5.2.2.2.1-1");
    return;
end

N1 = localExplicitInteger(cfg,["N1","mimo.N1"],strict);
N2 = localExplicitInteger(cfg,["N2","mimo.N2"],strict);
if ~(isfinite(N1) && isfinite(N2) && N1*N2 == nTx)
    if strict
        error("sixgr:mimo:InvalidPanelGeometry", ...
            "Strict PMI selection requires explicit N1*N2 equal to measured ports.");
    end
    N1 = 1;
    N2 = nTx;
end
O1 = localExplicitInteger(cfg,["O1","mimo.O1"],false,4);
O2 = localExplicitInteger(cfg,["O2","mimo.O2"],false,4);
[W1,W2,info] = sixgr.mimo.buildNRCodebook(N1,N2,O1,O2);
if rankValue == 1
    candidates = reshape(W1,nTx,1,size(W1,2));
else
    candidates = W2;
end
if strict && logical(sixgr.util.structGet(info,"GenericDFTApproximationUsed",true))
    error("sixgr:mimo:UnsupportedResearchFallback", ...
        "A compact DFT study codebook cannot enter a strict profile.");
end
indices = (0:size(candidates,3)-1).';
end

function value = localExplicitInteger(cfg,paths,required,defaultValue)
if nargin < 4
    defaultValue = NaN;
end
value = defaultValue;
for path = string(paths)
    raw = sixgr.util.structGet(cfg,path,[]);
    if isempty(raw)
        continue;
    end
    raw = double(raw);
    if isscalar(raw) && isfinite(raw) && raw >= 1 && raw == round(raw)
        value = raw;
        return;
    end
end
if required
    value = NaN;
end
end
