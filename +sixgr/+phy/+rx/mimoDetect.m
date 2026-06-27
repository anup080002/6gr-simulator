function [layerSym, csi, info] = mimoDetect(rx, hEst, nVar, varargin)
%MIMODETECT Linear MIMO detection wrapper for MMSE / IRC / ZF.
%
%   The detector delegates all equalizer math to equalizeMMSE so equalized
%   symbols, CSI weights and post-EQ SINR share one EqualizerResult.

alg = "MMSE";
ind = [];
Rint = [];
RIncludesNoise = [];
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:phy:mimoDetect:InvalidNV", "Name-value inputs must be in pairs.");
    end
    for ii = 1:2:numel(varargin)
        name = varargin{ii};
        val = varargin{ii+1};
        if ~(ischar(name) || isstring(name))
            error("sixgr:phy:mimoDetect:InvalidNV", "Name must be char or string.");
        end
        switch lower(char(string(name)))
            case "algorithm"
                alg = string(val);
            case "indices"
                ind = val;
            case "rint"
                Rint = val;
            case {"rincludesnoise","rintincludesnoise","covarianceincludesnoise"}
                RIncludesNoise = logical(val);
            otherwise
                error("sixgr:phy:mimoDetect:UnknownNV", "Unknown name-value: %s", char(string(name)));
        end
    end
end

algRequested = upper(strtrim(string(alg)));
if strlength(algRequested) == 0
    algRequested = "MMSE";
end
algEffective = algRequested;
if algEffective == "IRC" && isempty(Rint)
    algEffective = "MMSE";
end

args = {"Algorithm", algEffective, "Rint", Rint};
if ~isempty(ind)
    args = [args, {"Indices", ind}]; %#ok<AGROW>
end
if ~isempty(RIncludesNoise)
    args = [args, {"RIncludesNoise", logical(RIncludesNoise)}]; %#ok<AGROW>
end

[layerSym, csi, eqInfo] = sixgr.phy.rx.equalizeMMSE(rx, hEst, nVar, args{:});
result = eqInfo.EqualizerResult;

engine = char(string(eqInfo.EngineUsed));
if algRequested == "IRC" && algEffective == "MMSE"
    engine = "IRC_fallback_MMSE_" + string(engine);
elseif algEffective == "IRC"
    engine = "manualIRC";
elseif algEffective == "ZF"
    engine = "manualZF";
elseif algEffective == "MMSE"
    engine = "manualMMSE";
end

info = eqInfo;
info.AlgorithmRequested = char(string(algRequested));
info.AlgorithmUsed = char(string(algEffective));
info.EngineUsed = char(string(engine));
info.LayerSymSize = size(layerSym);
info.EqualizerResult = result;
info.NVar = double(eqInfo.NVar);
end
