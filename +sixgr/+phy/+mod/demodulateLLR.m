function [llr, info] = demodulateLLR(rxSym, modScheme, noiseVar, varargin)
%DEMODULATELLR Soft-demodulate to LLRs (supports 1024/4096-QAM via Comm Toolbox).
%
%   [LLR,INFO] = sixgr.phy.mod.demodulateLLR(RXSYM, MODSCHEME, NOISEVAR)
%   demodulates complex symbols to soft LLRs.
%
%   - For NR standard modulations up to 256QAM (and pi/2-BPSK), this uses
%     nrSymbolDemodulate (5G Toolbox).
%   - For 1024/4096-QAM it uses qamdemod (Communications Toolbox).
%
%   Inputs:
%     RXSYM    : complex column vector of received symbols
%     MODSCHEME: "QPSK","16QAM","64QAM","256QAM","1024QAM","4096QAM","pi/2-BPSK"
%     NOISEVAR : scalar noise variance. If empty/NaN, uses unit variance for
%                Comm Toolbox paths and omits NOISEVAR for NR demodulator.
%
%   Name-value options:
%     "Engine"          : "auto" (default) | "nr" | "comm"
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
if ~isnumeric(rxSym)
    error("sixgr:phy:demodulateLLR:BadRx", "RXSYM must be numeric.");
end

if nargin < 3
    noiseVar = [];
end
useNoiseVar = ~(isempty(noiseVar) || any(~isfinite(noiseVar)));
if useNoiseVar
    noiseVar = double(noiseVar);
    if ~(isscalar(noiseVar) && noiseVar > 0)
        error("sixgr:phy:demodulateLLR:BadNoiseVar", "NOISEVAR must be a positive scalar.");
    end
end

[modStr, M, Qm, isNRStd] = localNormalizeMod(modScheme);

% Choose engine
eng = lower(strtrim(opts.Engine));
useNR = false;
if eng == "nr"
    useNR = true;
elseif eng == "comm"
    useNR = false;
else
    useNR = isNRStd && exist("nrSymbolDemodulate","file") == 2;
end

if useNR
    try
        if useNoiseVar
            llr = nrSymbolDemodulate(rxSym, char(modStr), noiseVar);
        else
            llr = nrSymbolDemodulate(rxSym, char(modStr));
        end
    catch ME
        if ~isNRStd
            rethrow(ME);
        end
        useNR = false;
    end
end

if ~useNR
    if modStr == "BPSK" || modStr == "pi/2-BPSK"
        % Fallback: treat as BPSK on real axis (approx)
        if ~useNoiseVar
            noiseVar = 1.0;
        end
        llr = (4/noiseVar) * real(rxSym);
    else
        if exist("qamdemod","file") ~= 2
            error("sixgr:phy:demodulateLLR:NoQAMDEMOD", ...
                "qamdemod not found. Install Communications Toolbox or use Engine='nr'.");
        end
        if ~useNoiseVar
            noiseVar = 1.0;
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
    end
end

% Ensure column vector
llr = llr(:);

info = struct();
info.Modulation = char(modStr);
info.M = double(M);
info.Qm = double(Qm);
info.EngineUsed = ternary(useNR, "nrSymbolDemodulate", "comm");
info.NoiseVarUsed = ternary(useNoiseVar, noiseVar, NaN);
info.UnitAveragePower = logical(opts.UnitAveragePower);
info.SymbolOrder = char(opts.SymbolOrder);
info.Approx = logical(opts.Approx);

end

% ------------------------- local helpers -------------------------

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
    case {"BPSK"}
        modStr = "BPSK"; M = 2; Qm = 1; isNRStd = true;
    case {"PI/2BPSK","PI/2-BPSK","PI2BPSK"}
        modStr = "pi/2-BPSK"; M = 2; Qm = 1; isNRStd = true;
    case {"QPSK"}
        modStr = "QPSK"; M = 4; Qm = 2; isNRStd = true;
    case {"16QAM","16"}
        modStr = "16QAM"; M = 16; Qm = 4; isNRStd = true;
    case {"64QAM","64"}
        modStr = "64QAM"; M = 64; Qm = 6; isNRStd = true;
    case {"256QAM","256"}
        modStr = "256QAM"; M = 256; Qm = 8; isNRStd = true;
    case {"1024QAM","1024"}
        modStr = "1024QAM"; M = 1024; Qm = 10;
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
