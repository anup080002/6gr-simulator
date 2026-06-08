function [layerSym, csi, info] = mimoDetect(rx, hEst, nVar, varargin)
%MIMODETECT Linear MIMO detection hooks (MMSE / IRC / ZF).
%
%   [layerSym, csi, info] = sixgr.phy.rx.mimoDetect(rx, hEst, nVar, ...)
%
%   Inputs
%     rx   : rxSym (NRE-by-R) or rxGrid (K-by-L-by-R)
%     hEst : hEstSym (NRE-by-R-by-P) or hEstGrid (K-by-L-by-R-by-P)
%     nVar : noise variance estimate (scalar)
%
%   Name-value options
%     Algorithm : "MMSE" (default) | "ZF" | "IRC"
%     Indices   : optional RE indices. If provided, this function extracts
%                 rxSym/hEstSym using nrExtractResources.
%     Rint      : interference covariance (Nr-by-Nr) or per-RE
%                 (NRE-by-Nr-by-Nr) for IRC. Optional.
%
%   Outputs
%     layerSym : detected symbols per layer (NRE-by-P)
%     csi      : per-layer CSI metric (NRE-by-P) (approx. for ZF/IRC)
%     info     : metadata struct

    alg = "MMSE";
    ind = [];
    Rint = [];

    % Parse name-value pairs
    if ~isempty(varargin)
        if mod(numel(varargin),2) ~= 0
            error("sixgr:phy:mimoDetect:InvalidNV", "Name-value inputs must be in pairs.");
        end
        for i = 1:2:numel(varargin)
            name = varargin{i};
            val  = varargin{i+1};
            if isstring(name) || ischar(name)
                key = lower(char(name));
            else
                error("sixgr:phy:mimoDetect:InvalidNV", "Name must be char or string.");
            end
            switch key
                case "algorithm"
                    alg = string(val);
                case "indices"
                    ind = val;
                case "rint"
                    Rint = val;
                otherwise
                    error("sixgr:phy:mimoDetect:UnknownNV", "Unknown name-value: %s", key);
            end
        end
    end

    usedExtraction = false;
    rxSym = rx;
    hSym  = hEst;

    if ~isempty(ind)
        usedExtraction = true;
        if exist("nrExtractResources","file") ~= 2
            error("sixgr:phy:mimoDetect:MissingFunc", "nrExtractResources not found.");
        end
        [rxSym, hSym] = nrExtractResources(ind, rx, hEst);
    end

    % Ensure hSym is NRE-by-R-by-P
    if ndims(hSym) == 2
        hSym = reshape(hSym, size(hSym,1), size(hSym,2), 1);
    end

    nRE = size(rxSym, 1);
    nR  = size(rxSym, 2);
    nP  = size(hSym, 3);

    layerSym = zeros(nRE, nP, "like", rxSym);
    csi      = zeros(nRE, nP, "like", real(rxSym));

    algLower = lower(char(alg));

    switch algLower
        case "mmse"
            nVarSafe = localSafeNoiseVariance(nVar, rxSym);
            [layerSym, csi, eqInfo] = sixgr.phy.rx.equalizeMMSE(rxSym, hSym, nVarSafe);
            engine = eqInfo.EngineUsed;

        case "zf"
            engine = "manualZF";
            for k = 1:nRE
                H = squeeze(hSym(k,:,:));      % nR-by-nP
                r = rxSym(k,:).';              % nR-by-1

                % ZF: s = (H'*H)\(H'*r)
                G = (H' * H);
                if rcond(double(G)) < 1e-12
                    W = pinv(H);               % robust fallback
                    s = W * r;
                else
                    W = localRobustSolve(G, H');
                    s = W * r;
                end
                layerSym(k,:) = s.';

                % Approx CSI for ZF (diagonal of post-eq gain)
                % Use inverse of diag(G^-1) if well-conditioned.
                if rcond(double(G)) >= 1e-12
                    Gi = localRobustSolve(G, eye(nP));
                    csi(k,:) = 1 ./ max(real(diag(Gi)).', eps);
                else
                    csi(k,:) = 0;
                end
            end

        case "irc"
            if isempty(Rint)
                % Hook point: if Rint not supplied, fall back to MMSE
                nVarSafe = localSafeNoiseVariance(nVar, rxSym);
                [layerSym, csi, eqInfo] = sixgr.phy.rx.equalizeMMSE(rxSym, hSym, nVarSafe);
                engine = "IRC_fallback_MMSE_" + eqInfo.EngineUsed;
                alg = "MMSE";
            else
                engine = "manualIRC";
                % Support constant or per-RE covariance
                perRE = (ndims(Rint) == 3);
                nVarSafe = localSafeNoiseVariance(nVar, rxSym);
                if ~perRE
                    if ~isequal(size(Rint,1), nR) || ~isequal(size(Rint,2), nR)
                        error("sixgr:phy:mimoDetect:BadRint", "Rint must be Nr-by-Nr.");
                    end
                    RinvConst = localRobustInverse(Rint, nVarSafe, nR);
                    RcovConst = double(Rint) + nVarSafe * eye(nR);
                end

                for k = 1:nRE
                    H = squeeze(hSym(k,:,:));  % nR-by-nP
                    r = rxSym(k,:).';          % nR-by-1
                    if perRE
                        Rk = squeeze(Rint(k,:,:)); % nR-by-nR
                        if ~isequal(size(Rk,1), nR) || ~isequal(size(Rk,2), nR)
                            error("sixgr:phy:mimoDetect:BadRint", "Rint must be Nr-by-Nr.");
                        end
                        Rinv = localRobustInverse(Rk, nVarSafe, nR);
                        Rcov = double(Rk) + nVarSafe * eye(nR);
                    else
                        Rinv = RinvConst;
                        Rcov = RcovConst;
                    end

                    % MMSE-IRC weight matrix using regularized covariance.
                    A = (H' * Rinv * H) + (nVarSafe * eye(nP));
                    B = (H' * Rinv);
                    W = localRobustSolve(A, B);
                    s = W * r;
                    layerSym(k,:) = s.';

                    for l = 1:nP
                        num = abs(W(l,:) * H(:,l))^2;
                        den = real(W(l,:) * Rcov * W(l,:)') + eps;
                        csi(k,l) = num / den;
                    end
                end
            end

        otherwise
            error("sixgr:phy:mimoDetect:BadAlgorithm", "Unsupported Algorithm=%s", alg);
    end

    info = struct();
    info.AlgorithmUsed = string(alg);
    info.EngineUsed = string(engine);
    info.UsedExtraction = usedExtraction;
    info.RxSize = size(rxSym);
    info.HEstSize = size(hSym);
    info.LayerSymSize = size(layerSym);
    info.NVar = nVar;
end

function nVarSafe = localSafeNoiseVariance(nVar, rxSym)
nVarSafe = double(nVar);
if ~(isfinite(nVarSafe) && nVarSafe > 0)
    p = mean(abs(rxSym(:)).^2 + eps, "omitnan");
    if ~(isfinite(p) && p > 0)
        p = 1;
    end
    nVarSafe = 1e-12 * p;
end
end

function Rinv = localRobustInverse(R, nVar, nR)
Rreg = double(R) + max(double(nVar), 1e-10) * eye(nR);
if rcond(Rreg) < 1e-12
    Rinv = pinv(Rreg);
else
    Rinv = Rreg \ eye(nR);
end
end

function X = localRobustSolve(A, B)
A = double(A);
B = double(B);
if rcond(A) < 1e-12
    X = pinv(A) * B;
else
    X = A \ B;
end
end
