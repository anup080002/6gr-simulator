function [sym, info] = modulate(bits, modScheme, varargin)
%MODULATE NR symbol modulation; explicit Comm-QAM research mapping is separate.
%
%   [SYM,INFO] = sixgr.phy.mod.modulate(BITS, MODSCHEME) maps a column vector
%   of bits (0/1) to complex modulation symbols.
%
%   MODSCHEME (case-insensitive) examples:
%     "QPSK","16QAM","64QAM","256QAM","1024QAM","4096QAM","pi/2-BPSK","BPSK"
%
%   Name-value options:
%     "Engine"          : "auto" (default) | "nr" | "native_nr" | "comm"
%     "UnitAveragePower": true (default)  | false   (Comm Toolbox only)
%     "SymbolOrder"     : "Gray" (default) | "Binary" (Comm Toolbox only)
%
%   Notes:
%   - For NR standard modulations up to 1024QAM (and pi/2-BPSK), this wrapper
%     uses nrSymbolModulate when available.
%   - native_nr implements TS 38.211 section 5.1 without a toolbox mapper.
%   - Explicit comm QAM has different bit labels; 4096QAM is a research mode.
%     A failure in a selected engine is never retried with a different map.
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
if ~((isnumeric(bits) || islogical(bits)) && isreal(bits) ...
        && all(isfinite(double(bits))) && all(bits == 0 | bits == 1))
    error("sixgr:phy:modulate:BadBits", "BITS must contain only finite binary values.");
end
bits = int8(bits);

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
if ~isscalar(eng) || ~any(eng == ["auto","nr","native_nr","comm"])
    error("sixgr:phy:modulate:BadEngine", "Unknown modulation engine.");
end
if eng == "auto"
    if isNRStd
        eng = "native_nr";
        if exist("nrSymbolModulate","file") == 2
            eng = "nr";
        end
    else
        eng = "comm";
    end
end
if any(eng == ["nr","native_nr"]) && ~isNRStd
    error("sixgr:phy:modulate:UnsupportedNRModulation", ...
        "%s is not an NR constellation supported by this wrapper.", modStr);
end
if any(eng == ["nr","native_nr"]) && (~opts.UnitAveragePower || ...
        ~any(lower(opts.SymbolOrder) == ["gray","gr"]))
    error("sixgr:phy:modulate:NonNRMappingOption", ...
        "NR mapping has fixed bit labelling and unit ensemble-average power.");
end
engineUsed = eng;
convention = "TS_38_211_section_5_1";
if eng == "nr"
    sym = nrSymbolModulate(double(bits), char(modStr));
    engineUsed = "nrSymbolModulate";
elseif eng == "native_nr" || Qm == 1
    if Qm == 1
        sym = (1-2*double(bits))*(1+1i)/sqrt(2);
        if modStr == "pi/2-BPSK"
            sym = sym .* exp(1i*pi/2*mod((0:numel(bits)-1).',2));
        end
    else
        [axisValues,~] = sixgr.phy.mod.nrPAMAlphabet(Qm);
        groups = reshape(double(bits),Qm,[]).';
        weights = 2.^(Qm/2-1:-1:0).';
        sym = complex(axisValues(1+groups(:,1:2:end)*weights), ...
            axisValues(1+groups(:,2:2:end)*weights));
    end
    engineUsed = "sixgr_native_nr";
else
    % Explicit Communications Toolbox mapping: never label this NR bit order.
    if exist("qammod","file") ~= 2
        error("sixgr:phy:modulate:NoQAMMOD", ...
            "qammod not found. Install Communications Toolbox or use Engine='nr'.");
    end
    symOrder = localNormalizeSymOrder(opts.SymbolOrder);
    sym = qammod(double(bits), M, symOrder, ...
        "InputType","bit", "UnitAveragePower", opts.UnitAveragePower);
    sym = sym(:);
    convention = "communications_toolbox_" + lower(opts.SymbolOrder);
end

info = struct();
info.Modulation = char(modStr);
info.M = double(M);
info.Qm = double(Qm);
info.EngineUsed = engineUsed;
info.ConstellationConvention = convention;
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
    case {"BPSK","2QAM","2"}
        modStr = "BPSK"; M = 2; Qm = 1;
        isNRStd = true;
    case {"PI/2BPSK","PI/2-BPSK","PI2BPSK"}
        modStr = "pi/2-BPSK"; M = 2; Qm = 1;
        isNRStd = true;
    case {"QPSK","4QAM","4"}
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
