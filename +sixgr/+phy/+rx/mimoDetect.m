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

[rawLayerSym, csi, eqInfo] = sixgr.phy.rx.equalizeMMSE(rx, hEst, nVar, args{:});
result = eqInfo.EqualizerResult;
[layerSym, demapperContract] = localUnitDesiredGainSymbols(rawLayerSym, result);
result.RawEqualizedSymbols = rawLayerSym;
result.UnitGainEqualizedSymbols = layerSym;
result.DemapperEqualizedSymbols = layerSym;
result.DesiredResponseGain = demapperContract.DesiredResponseGain;
result.DesiredResponseGainValidMask = demapperContract.ValidMask;
result.DesiredResponseGainValidCount = demapperContract.ValidCount;
result.DesiredResponseGainInvalidCount = demapperContract.InvalidCount;
result.DemapperContractVersion = "EqualizerToDemapper/v1";
result.DemapperSymbolDomain = "unit_desired_gain";
result.DemapperNormalizationEquation = "s_hat_l=(W*y)_l/(W*H)_(l,l)";
result.DemapperEffectiveVarianceEquation = ...
    "sigma2_eff_l=(sum_(j~=l)|WH_(l,j)|^2+(W*R*W^H)_(l,l))/|WH_(l,l)|^2=1/SINR_l";

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
info.RawLayerSymSize = size(rawLayerSym);
info.DemapperContract = demapperContract;
info.EqualizerResult = result;
info.NVar = double(eqInfo.NVar);
end

function [unitGainSym, contract] = localUnitDesiredGainSymbols(rawSym, result)
% The LMMSE output W*y has desired response diag(W*H), not unit gain.
% postEqualizationNoiseVariance reports the variance after division by that
% response. Normalize the symbols at this shared boundary so the symbols
% and variance passed to the NR demapper are in the same domain.

wh = sixgr.util.structGet(result, "EffectiveResponseWH", []);
if isempty(rawSym)
    unitGainSym = rawSym;
    gain = zeros(size(rawSym));
    valid = false(size(rawSym));
elseif isempty(wh) || ...
        size(wh, 1) ~= size(rawSym, 1) || ...
        size(wh, 2) < size(rawSym, 2) || size(wh, 3) < size(rawSym, 2)
    error("sixgr:phy:mimoDetect:MissingDesiredResponseGain", ...
        "EqualizerResult EffectiveResponseWH does not match the %s raw symbol matrix.", ...
        mat2str(size(rawSym)));
else
    nRE = size(rawSym, 1);
    nLayers = size(rawSym, 2);
    gain = complex(zeros(nRE, nLayers, "like", rawSym));
    for layer = 1:nLayers
        gain(:, layer) = reshape(wh(:, layer, layer), nRE, 1);
    end
    whMagnitude = reshape(abs(wh), nRE, []);
    gainFloor = sqrt(eps(class(real(gain)))) .* max(1, max(whMagnitude, [], 2));
    valid = isfinite(real(gain)) & isfinite(imag(gain)) & ...
        abs(gain) > gainFloor;
    unitGainSym = complex(zeros(size(rawSym), "like", rawSym));
    unitGainSym(valid) = rawSym(valid) ./ gain(valid);
end

contract = struct( ...
    "ContractVersion", "EqualizerToDemapper/v1", ...
    "InputDomain", "raw_linear_equalizer_output_Wy", ...
    "OutputDomain", "unit_desired_gain_layer_symbols", ...
    "Equation", "s_hat_l=(W*y)_l/(W*H)_(l,l)", ...
    "EffectiveVarianceEquation", ...
        "sigma2_eff_l=(inter_layer_l+output_cov_l_l)/abs((W*H)_l_l)^2=1/SINR_l", ...
    "DesiredResponseGain", gain, ...
    "DesiredResponseGainFloorPolicy", "sqrt_machine_epsilon_times_max_one_and_per_re_WH_magnitude", ...
    "ValidMask", valid, ...
    "ValidCount", double(nnz(valid)), ...
    "InvalidCount", double(numel(valid) - nnz(valid)), ...
    "InvalidSymbolPolicy", "zero_soft_evidence_with_explicit_invalid_mask");
end
