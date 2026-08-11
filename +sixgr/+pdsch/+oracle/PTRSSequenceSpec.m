classdef PTRSSequenceSpec
    %PTRSSEQUENCESPEC Independent TS 38.211 PDSCH PT-RS sequence oracle.
    %
    % The oracle derives QPSK samples from the Gold-sequence definition and
    % the associated DM-RS port.  It calls neither production reference
    % generation nor MATLAB nrPDSCHPTRS.

    methods (Static)
        function result = generate(request)
            required = ["Indices0Based","GridNumPRB","PRBSet", ...
                "DMRSConfigurationType","AssociatedDMRSPort", ...
                "NIDNSCID","NSCID","ReferenceDMRSSymbol", ...
                "SlotNumber","SymbolsPerSlot"];
            if ~isstruct(request) || ~isscalar(request)
                error("sixgr:pdsch:oracle:InvalidPTRSSequenceRequest", ...
                    "PT-RS sequence request must be a scalar struct.");
            end
            missing = required(~isfield(request,required));
            if ~isempty(missing)
                error("sixgr:pdsch:oracle:IncompletePTRSSequenceRequest", ...
                    "PT-RS sequence request is missing: %s.", ...
                    strjoin(cellstr(missing),", "));
            end
            indices = double(request.Indices0Based(:));
            nGridPRB = localInteger(request.GridNumPRB,1,inf);
            prbs = localVector(request.PRBSet,0,nGridPRB-1);
            configType = localInteger( ...
                request.DMRSConfigurationType,1,2);
            port = localInteger(request.AssociatedDMRSPort,0,23);
            nid = localInteger(request.NIDNSCID,0,65535);
            nscid = localInteger(request.NSCID,0,1);
            referenceDMRSSymbol = localInteger( ...
                request.ReferenceDMRSSymbol,0,13);
            slot = localInteger(request.SlotNumber,0,inf);
            symbolsPerSlot = localInteger( ...
                request.SymbolsPerSlot,1,14);
            K = 12*nGridPRB;
            subcarrier = mod(indices,K);
            symbols = floor(indices/K);
            if any(symbols >= symbolsPerSlot)
                error("sixgr:pdsch:oracle:PTRSIndexOutsideSlot", ...
                    "PT-RS sequence indices extend outside the slot.");
            end
            sequence = complex(zeros(numel(indices),1));
            if configType == 1
                delta = floor(mod(port,4)/2);
                localPattern = delta + [0 2 4 6 8 10];
            else
                delta = 2*floor(mod(port,6)/2);
                localPattern = delta + [0 1 6 7];
            end
            rePerPRB = numel(localPattern);
            cInit = mod( ...
                2^17*(symbolsPerSlot*slot + referenceDMRSSymbol + 1) ...
                *(2*nid + 1) + 2*nid + nscid,2^31);
            % DM-RS sequence indexing is anchored to the PRB reference
            % point, so holes in a noncontiguous allocation must advance
            % the Gold sequence.  Generating only numel(PRBSet) blocks
            % incorrectly compacts those holes and changes PT-RS symbols.
            fullSequenceRE = rePerPRB*(max(prbs)+1);
            bits = sixgr.pdsch.oracle.GoldSequenceSpec( ...
                cInit,2*fullSequenceRE);
            base = ((1-2*double(bits(1:2:end))) ...
                + 1j*(1-2*double(bits(2:2:end))))/sqrt(2);
            uniqueSymbols = unique(symbols,"stable").';
            for symbol = uniqueSymbols
                rows = find(symbols == symbol);
                for row = rows(:).'
                    prb = floor(subcarrier(row)/12);
                    prbOrder = find(prbs == prb,1);
                    local = mod(subcarrier(row),12);
                    localOrder = find(localPattern == local,1);
                    if isempty(prbOrder) || isempty(localOrder)
                        error("sixgr:pdsch:oracle:PTRSIndexOutsideSequenceMap", ...
                            "PT-RS index cannot be mapped to its associated DM-RS sequence.");
                    end
                    m = prb*rePerPRB + localOrder;
                    % TS 38.211 7.4.1.2.1 reuses the underlying DM-RS
                    % pseudorandom sequence for PDSCH PT-RS.  The
                    % associated DM-RS port selects the PT-RS RE through
                    % the delta/local-pattern mapping above; it does not
                    % apply the DM-RS frequency-domain OCC weight again.
                    % Applying w_f here negated every port-1 PT-RS sample
                    % and caused an exact NMSE of four in two-user MU-MIMO.
                    sequence(row) = base(m);
                end
            end
            result = struct( ...
                "Sequence",sequence, ...
                "IndexBase","zero_based", ...
                "StandardReference","TS_38.211_7.4.1.2");
        end
    end
end

function value = localInteger(value,minimum,maximum)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) ...
        || value ~= floor(value) || value < minimum || value > maximum
    error("sixgr:pdsch:oracle:InvalidPTRSSequenceField", ...
        "PT-RS sequence integer is outside its explicit range.");
end
value = double(value);
end

function value = localVector(value,minimum,maximum)
if ~isnumeric(value) || isempty(value) || ~isvector(value) ...
        || any(~isfinite(value)) || any(value ~= floor(value)) ...
        || any(value < minimum) || any(value > maximum) ...
        || numel(unique(value,"stable")) ~= numel(value)
    error("sixgr:pdsch:oracle:InvalidPTRSSequenceField", ...
        "PT-RS sequence vectors must be explicit unique integers.");
end
value = double(value(:).');
end
