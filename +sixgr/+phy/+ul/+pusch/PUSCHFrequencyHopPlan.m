classdef PUSCHFrequencyHopPlan
    %PUSCHFREQUENCYHOPPLAN Immutable PUSCH hopping/resource plan.

    properties (SetAccess = private)
        Mode
        ResourceAllocationType
        BWPStart
        BWPSize
        AbsoluteSlot
        RepetitionType
        RepetitionIndex
        FirstHopPRBSet
        SecondHopPRBSet
        FirstHopSymbols
        SecondHopSymbols
        Digest
    end

    methods (Static)
        function obj = resolve(varargin)
            ip = inputParser;
            ip.addParameter("Mode", "", @(x) ischar(x) || isstring(x));
            ip.addParameter("ResourceAllocationType", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("BWPStart", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("BWPSize", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("PRBStart", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("PRBLength", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("SecondHopStartPRB", [], @(x) isempty(x) || (isnumeric(x) && isscalar(x)));
            ip.addParameter("AbsoluteSlot", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("StartSymbol", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("SymbolLength", [], @(x) isnumeric(x) && isscalar(x));
            ip.addParameter("RepetitionType", "", @(x) ischar(x) || isstring(x));
            ip.addParameter("RepetitionIndex", 0, @(x) isnumeric(x) && isscalar(x));
            ip.parse(varargin{:});
            o = ip.Results;

            mode = lower(strtrim(string(o.Mode)));
            if ~ismember(mode, ["none","intra_slot","inter_slot"])
                error("sixgr:pusch:InvalidFrequencyHoppingMode", ...
                    "Frequency-hopping mode must be none, intra_slot, or inter_slot.");
            end
            allocationType = localInteger(o.ResourceAllocationType, 0, 2, "ResourceAllocationType");
            if allocationType == 2 && mode ~= "none"
                error("sixgr:pusch:FrequencyHoppingResourceTypeConflict", ...
                    "PUSCH resource-allocation type 2 cannot use frequency hopping.");
            end
            bwpStart = localInteger(o.BWPStart, 0, inf, "BWPStart");
            bwpSize = localInteger(o.BWPSize, 1, inf, "BWPSize");
            prbStart = localInteger(o.PRBStart, 0, inf, "PRBStart");
            prbLength = localInteger(o.PRBLength, 1, inf, "PRBLength");
            if prbStart + prbLength > bwpSize
                error("sixgr:pusch:PRBAllocationOutOfBWP", ...
                    "First-hop allocation [%d,%d] exceeds BWP size %d.", ...
                    prbStart, prbStart + prbLength - 1, bwpSize);
            end
            firstPRB = bwpStart + prbStart + (0:prbLength-1);
            secondPRB = zeros(1, 0);
            if mode ~= "none"
                if isempty(o.SecondHopStartPRB) || ~isfinite(double(o.SecondHopStartPRB))
                    error("sixgr:pusch:MissingSecondHopStartPRB", ...
                        "Frequency hopping requires an explicit second-hop start PRB.");
                end
                secondStart = localInteger(o.SecondHopStartPRB, 0, inf, "SecondHopStartPRB");
                if secondStart + prbLength > bwpSize
                    error("sixgr:pusch:SecondHopOutOfBWP", ...
                        "Second-hop allocation [%d,%d] exceeds BWP size %d.", ...
                        secondStart, secondStart + prbLength - 1, bwpSize);
                end
                secondPRB = bwpStart + secondStart + (0:prbLength-1);
            end
            startSymbol = localInteger(o.StartSymbol, 0, 13, "StartSymbol");
            symbolLength = localInteger(o.SymbolLength, 1, 14, "SymbolLength");
            symbols = startSymbol + (0:symbolLength-1);
            repetitionTypeB = mode == "inter_slot" ...
                && contains(lower(string(o.RepetitionType)), "b");
            if any(symbols > 13) && ~repetitionTypeB
                error("sixgr:pusch:SymbolAllocationOutsideSlot", ...
                    "PUSCH symbol allocation exceeds a 14-symbol normal-CP slot.");
            end
            if mode == "intra_slot"
                split = floor(symbolLength / 2);
                firstSymbols = symbols(1:split);
                secondSymbols = symbols(split+1:end);
            elseif repetitionTypeB
                firstSymbols = symbols(symbols <= 13);
                secondSymbols = mod(symbols(symbols > 13), 14);
            else
                firstSymbols = symbols;
                secondSymbols = zeros(1, 0);
            end
            repetitionIndex = localInteger(o.RepetitionIndex, 0, inf, "RepetitionIndex");

            obj = sixgr.phy.ul.pusch.PUSCHFrequencyHopPlan();
            obj.Mode = mode;
            obj.ResourceAllocationType = allocationType;
            obj.BWPStart = bwpStart;
            obj.BWPSize = bwpSize;
            obj.AbsoluteSlot = localInteger(o.AbsoluteSlot, 0, inf, "AbsoluteSlot");
            obj.RepetitionType = string(o.RepetitionType);
            obj.RepetitionIndex = repetitionIndex;
            obj.FirstHopPRBSet = firstPRB;
            obj.SecondHopPRBSet = secondPRB;
            obj.FirstHopSymbols = firstSymbols;
            obj.SecondHopSymbols = secondSymbols;
            obj.Digest = char(localDigest(obj));
        end
    end

    methods
        function value = toStruct(obj)
            value = struct( ...
                "Mode", obj.Mode, ...
                "ResourceAllocationType", obj.ResourceAllocationType, ...
                "BWPStart", obj.BWPStart, ...
                "BWPSize", obj.BWPSize, ...
                "AbsoluteSlot", obj.AbsoluteSlot, ...
                "RepetitionType", obj.RepetitionType, ...
                "RepetitionIndex", obj.RepetitionIndex, ...
                "FirstHopPRBSet", obj.FirstHopPRBSet, ...
                "SecondHopPRBSet", obj.SecondHopPRBSet, ...
                "FirstHopSymbols", obj.FirstHopSymbols, ...
                "SecondHopSymbols", obj.SecondHopSymbols, ...
                "Digest", obj.Digest);
        end
    end
end

function value = localInteger(raw, minimum, maximum, name)
value = double(raw);
if ~(isscalar(value) && isfinite(value) && value == fix(value) ...
        && value >= minimum && value <= maximum)
    if string(name) == "RepetitionIndex"
        id = "sixgr:pusch:InvalidRepetitionIndex";
    else
        id = "sixgr:pusch:InvalidFrequencyHopping";
    end
    error(id, "%s must be an integer in [%g,%g].", name, minimum, maximum);
end
end

function digest = localDigest(obj)
text = strjoin([obj.Mode,string(obj.ResourceAllocationType), ...
    string(obj.BWPStart),string(obj.BWPSize),string(obj.AbsoluteSlot), ...
    string(obj.RepetitionIndex),localJoinVector(obj.FirstHopPRBSet), ...
    localJoinVector(obj.SecondHopPRBSet), ...
    localJoinVector(obj.FirstHopSymbols), ...
    localJoinVector(obj.SecondHopSymbols)], "|");
bytes = uint8(unicode2native(char(text), "UTF-8"));
digest = string(sixgr.util.sha256Hex(bytes));
end

function value = localJoinVector(raw)
if isempty(raw)
    value = "";
else
    value = join(string(raw(:).'), ":");
end
end
