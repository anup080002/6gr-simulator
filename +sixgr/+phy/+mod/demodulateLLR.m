function [llr, info] = demodulateLLR(rxSym, modScheme, noiseVar, varargin)
%DEMODULATELLR Exact or explicitly max-log LLRs with declared constellation.
%
%   [LLR,INFO] = sixgr.phy.mod.demodulateLLR(RXSYM, MODSCHEME, NOISEVAR)
%   demodulates complex symbols to soft LLRs.
%
%   - NR mappings through 1024QAM use exact axis-wise log-sum-exp by default.
%     Approx=true selects max-log (MATLAB nrSymbolDemodulate when available).
%   - Engine=comm uses qamdemod's different QAM bit labelling explicitly.
%     4096QAM remains a research mapping, not an NR claim.
%
%   Inputs:
%     RXSYM    : complex column vector of received symbols
%     MODSCHEME: "QPSK","16QAM","64QAM","256QAM","1024QAM","4096QAM","pi/2-BPSK"
%     NOISEVAR : E[abs(n)^2], positive scalar complex-noise variance.
%                Empty/scalar NaN explicitly defaults to 1 and is reported.
%
%   Name-value options:
%     "Engine"          : "auto" (default) | "nr" | "native_nr" | "comm"
%     "UnitAveragePower": true (default) (Comm Toolbox only)
%     "SymbolOrder"     : "Gray" (default) (Comm Toolbox only)
%     "Approx"          : false (default) -> exact 'llr' for qamdemod; true -> 'approxllr'

% Defaults
opts.Engine = "auto";
opts.UnitAveragePower = true;
opts.SymbolOrder = "Gray";
opts.Approx = false;

% Parse name-value pairs
if rem(numel(varargin),2) ~= 0
    error("sixgr:phy:demodulateLLR:BadNV", "Name-value arguments must be in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case "engine"
            opts.Engine = string(val);
        case "unitaveragepower"
            opts.UnitAveragePower = logical(val);
        case "symbolorder"
            opts.SymbolOrder = string(val);
        case "approx"
            opts.Approx = logical(val);
        otherwise
            error("sixgr:phy:demodulateLLR:BadNV", "Unknown option: %s", name);
    end
end

rxSym = rxSym(:);
if ~isnumeric(rxSym) || any(~isfinite(rxSym))
    error("sixgr:phy:demodulateLLR:BadRx", "RXSYM must be finite numeric samples.");
end

if nargin < 3
    noiseVar = [];
end
noiseDefaulted = isempty(noiseVar) || (isnumeric(noiseVar) && ...
    isscalar(noiseVar) && isnan(noiseVar));
if noiseDefaulted
    noiseVar = 1;
end
if ~(isnumeric(noiseVar) && isreal(noiseVar) && isscalar(noiseVar) ...
        && isfinite(noiseVar) && noiseVar > 0)
    error("sixgr:phy:demodulateLLR:BadNoiseVar", "NOISEVAR must be a positive finite scalar.");
end
noiseVar = double(noiseVar);

[modStr, M, Qm, isNRStd] = localNormalizeMod(modScheme);
if Qm <= 0
    error("sixgr:phy:demodulateLLR:BadMod", "Unsupported modulation.");
end

% Choose engine
eng = lower(strtrim(opts.Engine));
if ~isscalar(eng) || ~any(eng == ["auto","nr","native_nr","comm"])
    error("sixgr:phy:demodulateLLR:BadEngine", "Unknown demodulation engine.");
end
if eng == "auto"
    eng = "comm";
    if isNRStd
        eng = "native_nr";
        if opts.Approx && exist("nrSymbolDemodulate","file") == 2
            eng = "nr";
        end
    end
end
if any(eng == ["nr","native_nr"]) && ~isNRStd
    error("sixgr:phy:demodulateLLR:UnsupportedNRModulation", ...
        "%s is not a supported NR constellation.", modStr);
end
if any(eng == ["nr","native_nr"]) && (~opts.UnitAveragePower || ...
        ~any(lower(opts.SymbolOrder) == ["gray","gr"]))
    error("sixgr:phy:demodulateLLR:NonNRMappingOption", ...
        "NR mapping has fixed bit labelling and unit ensemble-average power.");
end
engineUsed = eng;
convention = "TS_38_211_section_5_1";
algorithm = ternary(opts.Approx,"max_log","exact_log_sum_exp");
if Qm == 1
    reference = repmat((1+1i)/sqrt(2),numel(rxSym),1);
    if modStr == "pi/2-BPSK"
        reference = reference .* exp(1i*pi/2*mod((0:numel(rxSym)-1).',2));
    end
    llr = 4*real(conj(reference).*rxSym)/noiseVar;
    engineUsed = "sixgr_native_nr";
    algorithm = "exact_binary_projection";
elseif eng == "nr" && opts.Approx
    llr = nrSymbolDemodulate(rxSym,char(modStr),noiseVar);
    engineUsed = "nrSymbolDemodulate";
elseif any(eng == ["nr","native_nr"])
    llr = localNRLLR(rxSym,Qm,noiseVar,opts.Approx);
    engineUsed = "sixgr_native_nr";
else
        if exist("qamdemod","file") ~= 2
            error("sixgr:phy:demodulateLLR:NoQAMDEMOD", ...
                "qamdemod not found. Install Communications Toolbox or use Engine='nr'.");
        end
        outType = ternary(opts.Approx, "approxllr", "llr");
        symOrder = localNormalizeSymOrder(opts.SymbolOrder);
        llrRaw = qamdemod(rxSym, M, symOrder, ...
            "UnitAveragePower", opts.UnitAveragePower, ...
            "OutputType", outType, "NoiseVariance", noiseVar);

        % Newer MATLAB versions may return either:
        %   - a column vector of length Nsym*Qm, or
        %   - an Nsym-by-Qm matrix of LLRs
        if ismatrix(llrRaw) && size(llrRaw,2) > 1
            llr = reshape(llrRaw.', [], 1);
        else
            llr = llrRaw(:);
        end
    convention = "communications_toolbox_" + lower(opts.SymbolOrder);
end

% Ensure column vector
llr = llr(:);

info = struct();
info.Modulation = char(modStr);
info.M = double(M);
info.Qm = double(Qm);
info.EngineUsed = engineUsed;
info.ConstellationConvention = convention;
info.LLRAlgorithmApplied = algorithm;
info.LLRSignConvention = "positive_means_bit_zero";
info.NoiseVarUsed = noiseVar;
info.NoiseVarianceDefaulted = noiseDefaulted;
info.NoiseVariancePlane = "complex_noise_E_abs_n_squared_at_demapper_input";
info.UnitAveragePower = logical(opts.UnitAveragePower);
info.SymbolOrder = char(opts.SymbolOrder);
info.Approx = logical(opts.Approx);
info.ApproximationApplied = logical(opts.Approx && Qm > 2);

end

% ------------------------- local helpers -------------------------

function llr = localNRLLR(rx,qm,nvar,approx)
% Uniform independent I/Q bits allow exact axis-wise marginalization.
% Work in bounded chunks: no Nsymbols-by-full-QAM-alphabet temporary.
[axisValues,axisBits] = sixgr.phy.mod.nrPAMAlphabet(qm);
out = zeros(numel(rx),qm);
for first = 1:512:numel(rx)
    indices = first:min(first+511,numel(rx));
    for axis = 1:2
        if axis == 1
            sample = real(rx(indices));
        else
            sample = imag(rx(indices));
        end
        metric = -(double(sample)-axisValues.').^2/nvar;
        for bit = 1:qm/2
            zero = metric(:,axisBits(:,bit)==0);
            one = metric(:,axisBits(:,bit)==1);
            if approx
                value = max(zero,[],2)-max(one,[],2);
            else
                value = localLogSumExp(zero)-localLogSumExp(one);
            end
            out(indices,2*bit-2+axis) = value;
        end
    end
end
llr = reshape(out.',[],1);
end

function value = localLogSumExp(metric)
peak = max(metric,[],2);
value = peak+log(sum(exp(metric-peak),2));
end

function [modStr, M, Qm, isNRStd] = localNormalizeMod(modScheme)
isNRStd = false;

if isnumeric(modScheme)
    M = double(modScheme);
    modStr = string(M) + "QAM";
else
    modStr = upper(string(modScheme));
    modStr = strrep(modStr, " ", "");
    modStr = strrep(modStr, "-", "");
end

switch modStr
    case {"BPSK","2QAM","2"}
        modStr = "BPSK"; M = 2; Qm = 1; isNRStd = true;
    case {"PI/2BPSK","PI/2-BPSK","PI2BPSK"}
        modStr = "pi/2-BPSK"; M = 2; Qm = 1; isNRStd = true;
    case {"QPSK","4QAM","4"}
        modStr = "QPSK"; M = 4; Qm = 2; isNRStd = true;
    case {"16QAM","16"}
        modStr = "16QAM"; M = 16; Qm = 4; isNRStd = true;
    case {"64QAM","64"}
        modStr = "64QAM"; M = 64; Qm = 6; isNRStd = true;
    case {"256QAM","256"}
        modStr = "256QAM"; M = 256; Qm = 8; isNRStd = true;
    case {"1024QAM","1024"}
        modStr = "1024QAM"; M = 1024; Qm = 10;
        isNRStd = true;
    case {"4096QAM","4096"}
        modStr = "4096QAM"; M = 4096; Qm = 12;
    otherwise
        M = NaN; Qm = -1;
end
end

function symOrder = localNormalizeSymOrder(in)
% Normalize symbol order for qammod/qamdemod.
s = lower(string(in));
if s == "gray" || s == "gr"
    symOrder = "gray";
elseif s == "binary" || s == "bin"
    symOrder = "bin";
else
    symOrder = char(in); % pass through
end
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
