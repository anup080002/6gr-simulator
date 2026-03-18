function [eqSym, csi, info] = equalizeMMSE(rx, hEst, nVar, varargin)
%EQUALIZEMMSE MMSE equalization wrapper (SISO/MIMO) for extracted REs.
%
%   [eqSym, csi, info] = sixgr.phy.rx.equalizeMMSE(rx, hEst, nVar, ...)
%
%   Typical usage in NR:
%       [rxSym, hEstSym] = nrExtractResources(dataInd, rxGrid, hEstGrid);
%       [eqSym, csi] = nrEqualizeMMSE(rxSym, hEstSym, nVar);
%
%   This wrapper optionally performs the resource extraction if you pass
%   Indices=... (linear indices into a K-by-L-by-P grid).
%
%   Inputs
%     rx   : rxSym (NRE-by-R) or rxGrid (K-by-L-by-R)
%     hEst : hEstSym (NRE-by-R-by-P) or hEstGrid (K-by-L-by-R-by-P)
%     nVar : noise variance estimate (scalar)
%
%   Name-value
%     Indices : optional RE indices for extraction (data/PDSCH/PUSCH indices)
%
%   Outputs
%     eqSym : equalized symbols (NRE-by-P)
%     csi   : channel state information per symbol (NRE-by-P)
%     info  : metadata struct

    % Parse minimal name-value arguments (avoid inputParser for Coder friendliness)
    ind = [];
    if ~isempty(varargin)
        if mod(numel(varargin),2) ~= 0
            error("sixgr:phy:equalizeMMSE:InvalidNV", "Name-value inputs must be in pairs.");
        end
        for i = 1:2:numel(varargin)
            name = varargin{i};
            val  = varargin{i+1};
            if isstring(name) || ischar(name)
                key = lower(char(name));
            else
                error("sixgr:phy:equalizeMMSE:InvalidNV", "Name must be char or string.");
            end
            switch key
                case "indices"
                    ind = val;
                otherwise
                    error("sixgr:phy:equalizeMMSE:UnknownNV", "Unknown name-value: %s", key);
            end
        end
    end

    usedExtraction = false;
    rxSym = rx;
    hSym  = hEst;

    if ~isempty(ind)
        usedExtraction = true;
        if exist("nrExtractResources","file") ~= 2
            error("sixgr:phy:equalizeMMSE:MissingFunc", "nrExtractResources not found.");
        end
        [rxSym, hSym] = nrExtractResources(ind, rx, hEst);
    end

    % Equalization
    if exist("nrEqualizeMMSE","file") == 2
        [eqSym, csi] = nrEqualizeMMSE(rxSym, hSym, nVar);
        engine = "nrEqualizeMMSE";
    else
        % Fallback (SISO only)
        engine = "manualSISO";
        if ~isequal(size(rxSym), size(hSym))
            error("sixgr:phy:equalizeMMSE:FallbackSISOOnly", ...
                "Fallback equalizer supports only SISO with matching rx/h shapes.");
        end
        eqSym = rxSym .* conj(hSym) ./ (abs(hSym).^2 + nVar);
        csi = abs(hSym).^2 ./ (abs(hSym).^2 + nVar);
    end

    info = struct();
    info.EngineUsed = engine;
    info.UsedExtraction = usedExtraction;
    info.RxSize = size(rxSym);
    info.HEstSize = size(hSym);
    info.EqSize = size(eqSym);
    info.NVar = nVar;
end
