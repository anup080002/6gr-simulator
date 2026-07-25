classdef DMRSSequenceSpec
    %DMRSSEQUENCESPEC Independent TS 38.211 PDSCH DM-RS sequence oracle.
    %
    % The implementation uses the independent GoldSequenceSpec and local
    % table weights only.  It calls neither production code nor nr* APIs.

    methods (Static)
        function result = generate(request)
            if ~isstruct(request) || ~isscalar(request)
                error("sixgr:pdsch:oracle:InvalidDMRSSequenceRequest", ...
                    "DM-RS sequence request must be a scalar struct.");
            end
            required = [ ...
                "DMRSConfigurationType","DMRSLength","DMRSPortSet", ...
                "DMRSSymbols","PRBSet","NIDNSCID","NSCID", ...
                "SlotNumber","SymbolsPerSlot"];
            missing = required(~isfield(request, required));
            if ~isempty(missing)
                error("sixgr:pdsch:oracle:IncompleteDMRSSequenceRequest", ...
                    "DM-RS sequence request is missing: %s.", ...
                    strjoin(cellstr(missing), ", "));
            end

            configType = localInteger(request.DMRSConfigurationType, 1, 2, ...
                "DMRSConfigurationType");
            dmrsLength = localInteger(request.DMRSLength, 1, 2, ...
                "DMRSLength");
            ports = localVector(request.DMRSPortSet, 0, 23, "DMRSPortSet");
            symbols = localVector(request.DMRSSymbols, 0, 13, "DMRSSymbols");
            prbs = localVector(request.PRBSet, 0, inf, "PRBSet");
            nid = localInteger(request.NIDNSCID, 0, 65535, "NIDNSCID");
            nscid = localInteger(request.NSCID, 0, 1, "NSCID");
            slot = localInteger(request.SlotNumber, 0, inf, "SlotNumber");
            symbolsPerSlot = localInteger( ...
                request.SymbolsPerSlot, 1, 14, "SymbolsPerSlot");
            if any(symbols >= symbolsPerSlot)
                error("sixgr:pdsch:oracle:DMRSSymbolOutsideSlot", ...
                    "DM-RS symbols must lie inside SymbolsPerSlot.");
            end
            if dmrsLength == 2 && mod(numel(symbols), 2) ~= 0
                error("sixgr:pdsch:oracle:InvalidDoubleSymbolDMRS", ...
                    "Double-symbol DM-RS requires complete symbol pairs.");
            end

            if configType == 1
                rePerPRB = 6;
            else
                rePerPRB = 4;
            end
            rePerSymbol = rePerPRB * numel(prbs);
            fullSequenceRE = rePerPRB * (max(prbs) + 1);
            selectedRE = reshape(( ...
                prbs(:) .* rePerPRB + (1:rePerPRB)).', 1, []);
            sequence = complex(zeros(rePerSymbol * numel(symbols), ...
                numel(ports)));
            cInit = zeros(numel(symbols), 1);
            for symbolIndex = 1:numel(symbols)
                l = symbols(symbolIndex);
                cInit(symbolIndex) = mod( ...
                    2^17 * (symbolsPerSlot * slot + l + 1) * ...
                        (2 * nid + 1) + 2 * nid + nscid, ...
                    2^31);
                bits = sixgr.pdsch.oracle.GoldSequenceSpec( ...
                    cInit(symbolIndex), 2 * fullSequenceRE);
                baseFull = ((1 - 2 * double(bits(1:2:end))) + ...
                    1j * (1 - 2 * double(bits(2:2:end)))) / sqrt(2);
                base = baseFull(selectedRE);
                rows = (symbolIndex - 1) * rePerSymbol + ...
                    (1:rePerSymbol);
                for portIndex = 1:numel(ports)
                    [wf, wt] = localWeights(configType, ports(portIndex));
                    % The OCC phase is referenced to the physical PRB
                    % coordinate.  Do not compact gaps in a sparse PRBSet:
                    % enhanced type-1 four-chip covers otherwise acquire
                    % the wrong phase after a missing PRB.
                    sequenceRE = reshape((prbs(:) .* rePerPRB ...
                        + (0:(rePerPRB-1))).',[],1);
                    frequencyWeights = wf( ...
                        mod(sequenceRE,numel(wf))+1).';
                    frequencyWeights = frequencyWeights(:);
                    if dmrsLength == 2
                        lPrime = mod(symbolIndex - 1, 2) + 1;
                    else
                        lPrime = 1;
                    end
                    sequence(rows, portIndex) = base .* ...
                        frequencyWeights .* wt(lPrime);
                end
            end
            result = struct( ...
                "Sequence", sequence, ...
                "SequenceInitPerSymbol", double(cInit), ...
                "DMRSSymbols", double(symbols(:).'), ...
                "DMRSPortSet", double(ports(:).'), ...
                "REPerPRBPerSymbol", double(rePerPRB), ...
                "REPerSymbolPerPort", double(rePerSymbol), ...
                "IndexBase", "zero_based", ...
                "StandardReference", "TS_38.211_7.4.1.1.1");
        end
    end
end

function value = localInteger(value, minimum, maximum, field)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
        value ~= floor(value) || value < minimum || value > maximum
    error("sixgr:pdsch:oracle:InvalidDMRSSequenceField", ...
        "%s is outside its explicit integer range.", field);
end
value = double(value);
end

function values = localVector(values, minimum, maximum, field)
if ~isnumeric(values) || isempty(values) || ~isvector(values) || ...
        any(~isfinite(values)) || any(values ~= floor(values)) || ...
        any(values < minimum) || any(values > maximum) || ...
        numel(unique(values, "stable")) ~= numel(values)
    error("sixgr:pdsch:oracle:InvalidDMRSSequenceField", ...
        "%s must be a unique integer vector.", field);
end
values = double(values(:).');
end

function [wf, wt] = localWeights(configType, port)
if configType == 1
    block = floor(port / 4);
    if port < 8
        evenPattern = [1 1 1 1];
        oddPattern = [1 -1 1 -1];
    else
        evenPattern = [1 1 -1 -1];
        oddPattern = [1 -1 -1 1];
    end
else
    block = floor(port / 6);
    if port < 12
        evenPattern = [1 1 1 1];
        oddPattern = [1 -1 1 -1];
    else
        evenPattern = [1 1 -1 -1];
        oddPattern = [1 -1 -1 1];
    end
end
if mod(port, 2) == 0
    wf = evenPattern;
else
    wf = oddPattern;
end
if mod(block, 2) == 0
    wt = [1 1];
else
    wt = [1 -1];
end
end
