function [sym, info] = modulate(bits, modScheme, varargin)
%MODULATE NR-style symbol modulation (supports 1024/4096-QAM via Comm Toolbox).
%
%   [SYM,INFO] = sixgr.phy.mod.modulate(BITS, MODSCHEME) maps a column vector
%   of bits (0/1) to complex modulation symbols.
%
%   MODSCHEME (case-insensitive) examples:
%     "QPSK","16QAM","64QAM","256QAM","1024QAM","4096QAM","pi/2-BPSK","BPSK"
%
%   Name-value options:
%     "Engine"          : "auto" (default) | "nr" | "comm"
%     "UnitAveragePower": true (default)  | false   (Comm Toolbox only)
%     "SymbolOrder"     : "Gray" (default) | "Binary" (Comm Toolbox only)
%
%   Notes:
%   - For NR standard modulations up to 256QAM (and pi/2-BPSK), this wrapper
%     uses nrSymbolModulate when available.
%   - For 1024/4096-QAM it uses qammod (Communications Toolbox).
%
%   This is a PHY building block; higher layers must ensure the bit length is
%   a multiple of Qm (bits per symbol).

% Defaults
opts.Engine = "auto";
opts.UnitAveragePower = true;
opts.SymbolOrder = "Gray";

% Parse name-value pairs (lightweight, Coder-friendly style)
if rem(numel(varargin),2) ~= 0
    error("sixgr:phy:modulate:BadNV", "Name-value arguments must be in pairs.");
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
        otherwise
            error("sixgr:phy:modulate:BadNV", "Unknown option: %s", name);
    end
end

% Normalize bits
bits = bits(:);
if ~isnumeric(bits) && ~islogical(bits)
    error("sixgr:phy:modulate:BadBits", "BITS must be numeric or logical.");
end
bits = int8(bits ~= 0);

% Normalize modulation
[modStr, M, Qm, isNRStd] = localNormalizeMod(modScheme);

% Validate length
nBits = numel(bits);
if Qm <= 0
    error("sixgr:phy:modulate:BadMod", "Invalid modulation scheme: %s", string(modScheme));
end
if rem(nBits, Qm) ~= 0
    error("sixgr:phy:modulate:LenMismatch", ...
        "Bit length (%d) must be a multiple of Qm=%d for %s.", nBits, Qm, modStr);
end

% Choose engine
eng = lower(strtrim(opts.Engine));
useNR = false;
if eng == "nr"
    useNR = true;
elseif eng == "comm"
    useNR = false;
else
    % auto
    useNR = isNRStd && exist("nrSymbolModulate","file") == 2;
end

if useNR
    % NR modulator (5G Toolbox)
    try
        sym = nrSymbolModulate(double(bits), char(modStr));  %#ok<CHARTEN>
    catch ME
        % If the NR modulator rejects the scheme, fallback to Comm Toolbox if possible.
        if ~isNRStd
            rethrow(ME);
        end
        useNR = false;
    end
end

if ~useNR
    % Comm Toolbox modulation for large QAM, fallback for others
    if modStr == "BPSK"
        sym = 1 - 2*double(bits); % 0->+1, 1->-1
        sym = complex(sym, 0);
    elseif modStr == "pi/2-BPSK"
        % Simple pi/2 rotation per symbol (fallback)
        b = 1 - 2*double(bits);
        n = (0:numel(b)-1).';
        sym = b .* exp(1j*(pi/2)*n);
    else
        if exist("qammod","file") ~= 2
            error("sixgr:phy:modulate:NoQAMMOD", ...
                "qammod not found. Install Communications Toolbox or use Engine='nr'.");
        end
        % Use bit-vector input mode (qammod groups bits internally)
        symOrder = localNormalizeSymOrder(opts.SymbolOrder);
        sym = qammod(double(bits), M, symOrder, ...
            "InputType","bit", "UnitAveragePower", opts.UnitAveragePower);
        sym = sym(:);
    end
end

info = struct();
info.Modulation = char(modStr);
info.M = double(M);
info.Qm = double(Qm);
info.EngineUsed = ternary(useNR, "nrSymbolModulate", "comm");
info.UnitAveragePower = logical(opts.UnitAveragePower);
info.SymbolOrder = char(opts.SymbolOrder);

end

% ------------------------- local helpers -------------------------

function [modStr, M, Qm, isNRStd] = localNormalizeMod(modScheme)
% Return canonical modulation string and parameters.
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
        modStr = "BPSK"; M = 2; Qm = 1;
        isNRStd = true;
    case {"PI/2BPSK","PI/2-BPSK","PI2BPSK"}
        modStr = "pi/2-BPSK"; M = 2; Qm = 1;
        isNRStd = true;
    case {"QPSK"}
        modStr = "QPSK"; M = 4; Qm = 2;
        isNRStd = true;
    case {"16QAM","16"}
        modStr = "16QAM"; M = 16; Qm = 4;
        isNRStd = true;
    case {"64QAM","64"}
        modStr = "64QAM"; M = 64; Qm = 6;
        isNRStd = true;
    case {"256QAM","256"}
        modStr = "256QAM"; M = 256; Qm = 8;
        isNRStd = true;
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
