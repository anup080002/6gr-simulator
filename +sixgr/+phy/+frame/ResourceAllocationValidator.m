classdef ResourceAllocationValidator
    %RESOURCEALLOCATIONVALIDATOR Validate channel grants without mutation.
    %
    % Allocation indices are zero based. Time-domain allocation must be
    % explicit (StartSymbol/NumSymbols or SLIV). Collision checks operate on
    % exact subcarrier/symbol/port resource-element keys.

    methods (Static)
        function allocation = makeAllocation(channel, direction, varargin)
            p = inputParser;
            addRequired(p, "channel", @(x) ischar(x) || isstring(x));
            addRequired(p, "direction", @(x) ischar(x) || isstring(x));
            addParameter(p, "CCID", 0);
            addParameter(p, "BWPID", 0);
            addParameter(p, "AbsoluteSlot", 0);
            addParameter(p, "StartSymbol", []);
            addParameter(p, "NumSymbols", []);
            addParameter(p, "SLIV", []);
            addParameter(p, "TDRAID", "");
            addParameter(p, "K0", []);
            addParameter(p, "K2", []);
            addParameter(p, "MappingType", "");
            addParameter(p, "StartRB", []);
            addParameter(p, "NumRB", []);
            addParameter(p, "GridNumRB", []);
            addParameter(p, "Ports", 0);
            addParameter(p, "RECoordinates", []);
            addParameter(p, "RateMatchedREKeys", strings(0, 1));
            addParameter(p, "ReservedREKeys", strings(0, 1));
            addParameter(p, "ReservedReason", "");
            addParameter(p, "GridID", "");
            addParameter(p, "TestID", "");
            parse(p, channel, direction, varargin{:});
            allocation = p.Results;
            allocation.Channel = upper(strtrim(string(channel)));
            allocation.Direction = upper(strtrim(string(direction)));
            allocation.MappingType = upper(strtrim(string(allocation.MappingType)));
            allocation.TDRAID = strtrim(string(allocation.TDRAID));
            allocation.RateMatchedREKeys = string(allocation.RateMatchedREKeys);
            allocation.ReservedREKeys = string(allocation.ReservedREKeys);
            allocation.ReservedReason = string(allocation.ReservedReason);
            allocation.GridID = string(allocation.GridID);
            allocation.TestID = string(allocation.TestID);
        end

        function result = validate(allocation, slotState, varargin)
            p = inputParser;
            addParameter(p, "SymbolsPerSlot", []);
            addParameter(p, "Strict", true, @(x) islogical(x) && isscalar(x));
            addParameter(p, "FDDContext", struct());
            addParameter(p, "GridNumRB", []);
            parse(p, varargin{:});
            original = allocation;
            result = sixgr.phy.frame.ResourceAllocationValidator.baseResult();
            try
                symbolsPerSlot = sixgr.phy.frame. ...
                    ResourceAllocationValidator.resolveSymbolsPerSlot( ...
                    allocation, slotState, p.Results.SymbolsPerSlot);
                normalized = sixgr.phy.frame.ResourceAllocationValidator. ...
                    normalizeAllocation(allocation, symbolsPerSlot, ...
                    p.Results.Strict);
                gridNumRB = p.Results.GridNumRB;
                if isempty(gridNumRB) && isfield(normalized, "GridNumRB")
                    gridNumRB = normalized.GridNumRB;
                end
                if ~isempty(gridNumRB)
                    validateattributes(gridNumRB, {'numeric'}, ...
                        {'scalar','integer','positive','finite'});
                    if normalized.StartRB + normalized.NumRB > gridNumRB
                        error("sixgr:phy:frame:FrequencyAllocationOutOfBounds", ...
                            "RB allocation [%d,%d] exceeds the zero-based " + ...
                            "grid extent [0,%d].", normalized.StartRB, ...
                            normalized.StartRB + normalized.NumRB - 1, ...
                            gridNumRB - 1);
                    end
                end
            catch ME
                result.ErrorID = string(ME.identifier);
                if ME.identifier == "sixgr:phy:frame:MissingExplicitTDRA"
                    result.ReasonCode = "missing_explicit_tdra_in_strict_mode";
                elseif ME.identifier == "sixgr:phy:frame:InvalidSLIV"
                    result.ReasonCode = "invalid_sliv";
                else
                    result.ReasonCode = "invalid_allocation";
                end
                result.Message = string(ME.message);
                result.OriginalUnchanged = isequaln(original, allocation);
                return;
            end

            if isa(slotState, "sixgr.phy.frame.FDDCarrierContexts")
                try
                    context = p.Results.FDDContext;
                    if isempty(fieldnames(context))
                        context = slotState.context(normalized.Direction);
                    end
                    slotState.isAvailable(normalized.AbsoluteSlot, ...
                        normalized.Direction, context);
                    if strlength(string(normalized.GridID)) == 0
                        normalized.GridID = string(context.GridID);
                    elseif string(normalized.GridID) ~= ...
                            string(context.GridID)
                        error("sixgr:phy:frame:FDDGridContextMismatch", ...
                            "Allocation GridID '%s' does not match the " + ...
                            "%s FDD grid context '%s'.", ...
                            string(normalized.GridID), ...
                            normalized.Direction, string(context.GridID));
                    end
                    availability = struct("Available", true, ...
                        "ReasonCode", "available", ...
                        "ObservedDirections", normalized.Direction);
                catch ME
                    result.ErrorID = string(ME.identifier);
                    result.ReasonCode = "fdd_grid_context_mismatch";
                    result.Message = string(ME.message);
                    result.OriginalUnchanged = isequaln(original, allocation);
                    return;
                end
            else
                availability = sixgr.phy.frame.SlotFormatResolver.isAvailable( ...
                    slotState, normalized.AbsoluteSlot, normalized.StartSymbol, ...
                    normalized.NumSymbols, normalized.Direction);
            end
            result.ActualValid = logical(availability.Available);
            result.ReasonCode = sixgr.phy.frame.ResourceAllocationValidator. ...
                classifyReason(normalized, availability);
            result.Allocation = normalized;
            result.ObservedDirections = string(availability.ObservedDirections);
            result.OriginalUnchanged = isequaln(original, allocation);
            if result.ActualValid
                result.Occupancy = sixgr.phy.frame.ResourceAllocationValidator. ...
                    buildOccupancy(normalized);
            end
        end

        function report = validateSet(allocations, slotState, varargin)
            %VALIDATESET Validate allocations and reject unhandled RE overlap.
            if ~isstruct(allocations)
                error("sixgr:phy:frame:InvalidAllocation", ...
                    "Allocations must be a struct array.");
            end
            results = repmat( ...
                sixgr.phy.frame.ResourceAllocationValidator.baseResult(), ...
                numel(allocations), 1);
            occupancy = sixgr.phy.frame.ResourceAllocationValidator.emptyOccupancy();
            for i = 1:numel(allocations)
                results(i) = sixgr.phy.frame.ResourceAllocationValidator. ...
                    validate(allocations(i), slotState, varargin{:});
                if results(i).ActualValid
                    occupancy = [occupancy; results(i).Occupancy]; %#ok<AGROW>
                end
            end
            invalid = find(~[results.ActualValid], 1);
            if ~isempty(invalid)
                report = struct("ActualValid", false, ...
                    "ReasonCode", results(invalid).ReasonCode, ...
                    "Results", results, "Occupancy", occupancy, ...
                    "CollisionKeys", strings(0, 1));
                return;
            end

            [uniqueKeys, ~, group] = unique(occupancy.REKey, "stable");
            counts = accumarray(group, 1);
            collisions = uniqueKeys(counts > 1);
            if isempty(collisions)
                valid = true;
                reason = "no_unhandled_re_collision";
            else
                valid = false;
                reason = "unreserved_re_collision";
                occupancy.CollisionFlag(ismember(occupancy.REKey, collisions)) = true;
            end
            report = struct("ActualValid", valid, ...
                "ReasonCode", reason, "Results", results, ...
                "Occupancy", occupancy, "CollisionKeys", collisions);
        end

        function tdra = resolveTDRA(raw, symbolsPerSlot)
            %RESOLVETDRA Decode explicit Start/Length or a 38.214 SLIV.
            validateattributes(symbolsPerSlot, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            if ~isstruct(raw)
                error("sixgr:phy:frame:InvalidTDRA", ...
                    "TDRA must be a validated struct.");
            end
            catalogRow = struct();
            catalogID = sixgr.phy.frame.ResourceAllocationValidator.field( ...
                raw, {"TDRAID","tdraId","CatalogID","catalogId"});
            if ~isempty(catalogID) && ...
                    strlength(strtrim(string(catalogID))) > 0
                dmrsTypeAPosition = sixgr.phy.frame. ...
                    ResourceAllocationValidator.field(raw, ...
                    {"DMRSTypeAPosition","dmrsTypeAPosition"});
                if isempty(dmrsTypeAPosition)
                    dmrsTypeAPosition = NaN;
                end
                mu = sixgr.phy.frame.ResourceAllocationValidator.field( ...
                    raw, {"Mu","mu","Numerology"});
                if isempty(mu)
                    mu = NaN;
                end
                catalogRow = sixgr.phy.frame. ...
                    TimeDomainResourceAllocationCatalog.resolve( ...
                    catalogID, "SymbolsPerSlot", symbolsPerSlot, ...
                    "DMRSTypeAPosition", dmrsTypeAPosition, "Mu", mu);
                requestedChannel = sixgr.phy.frame. ...
                    ResourceAllocationValidator.field(raw, ...
                    {"Channel","channel"});
                if ~isempty(requestedChannel) && ...
                        upper(strtrim(string(requestedChannel))) ~= ...
                        catalogRow.Channel
                    error("sixgr:phy:frame:TDRACatalogChannelMismatch", ...
                        "TDRA %s belongs to %s, not %s.", ...
                        catalogRow.ID, catalogRow.Channel, ...
                        string(requestedChannel));
                end
            end
            start = sixgr.phy.frame.ResourceAllocationValidator.field(raw, ...
                {"StartSymbol","startSymbol"});
            length = sixgr.phy.frame.ResourceAllocationValidator.field(raw, ...
                {"NumSymbols","Length","numSymbols"});
            sliv = sixgr.phy.frame.ResourceAllocationValidator.field(raw, ...
                {"SLIV","sliv"});
            if ~isempty(fieldnames(catalogRow))
                if isempty(start)
                    start = catalogRow.StartSymbol;
                elseif double(start) ~= catalogRow.StartSymbol
                    error("sixgr:phy:frame:InconsistentTDRA", ...
                        "Explicit StartSymbol does not match catalog TDRA %s.", ...
                        catalogRow.ID);
                end
                if isempty(length)
                    length = catalogRow.NumSymbols;
                elseif double(length) ~= catalogRow.NumSymbols
                    error("sixgr:phy:frame:InconsistentTDRA", ...
                        "Explicit NumSymbols does not match catalog TDRA %s.", ...
                        catalogRow.ID);
                end
                if isempty(sliv)
                    sliv = catalogRow.SLIV;
                elseif double(sliv) ~= catalogRow.SLIV
                    error("sixgr:phy:frame:InconsistentTDRA", ...
                        "Explicit SLIV does not match catalog TDRA %s.", ...
                        catalogRow.ID);
                end
            end
            if isempty(start) && isempty(length) && isempty(sliv)
                error("sixgr:phy:frame:MissingExplicitTDRA", ...
                    "Strict allocation requires an explicit TDRA row or test grant.");
            end
            if xor(isempty(start), isempty(length))
                error("sixgr:phy:frame:InvalidTDRA", ...
                    "StartSymbol and NumSymbols must be supplied together.");
            end
            if ~isempty(sliv)
                [decodedStart, decodedLength] = ...
                    sixgr.phy.frame.ResourceAllocationValidator.decodeSLIV( ...
                    sliv, symbolsPerSlot);
                if isempty(start)
                    start = decodedStart;
                    length = decodedLength;
                elseif start ~= decodedStart || length ~= decodedLength
                    error("sixgr:phy:frame:InconsistentTDRA", ...
                        "Explicit Start/Length does not match the supplied SLIV.");
                end
            end
            validateattributes(start, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(length, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            if start + length > symbolsPerSlot
                error("sixgr:phy:frame:InvalidTDRA", ...
                    "TDRA [%d,%d] exceeds a %d-symbol slot.", ...
                    start, start + length - 1, symbolsPerSlot);
            end
            mapping = sixgr.phy.frame.ResourceAllocationValidator.field(raw, ...
                {"MappingType","mappingType"});
            if ~isempty(fieldnames(catalogRow))
                if isempty(mapping)
                    mapping = catalogRow.MappingType;
                elseif upper(strtrim(string(mapping))) ~= ...
                        catalogRow.MappingType
                    error("sixgr:phy:frame:InconsistentTDRA", ...
                        "Explicit MappingType does not match catalog TDRA %s.", ...
                        catalogRow.ID);
                end
            elseif isempty(mapping)
                mapping = "";
            end
            mapping = upper(strtrim(string(mapping)));
            if strlength(mapping) > 0 && ~any(mapping == ["A","B"])
                error("sixgr:phy:frame:InvalidMappingType", ...
                    "MappingType must be A or B.");
            end
            if isempty(fieldnames(catalogRow))
                resolvedID = "";
                k0 = NaN;
                k2 = NaN;
                rowIndex = NaN;
                standardReference = "";
                sourceKind = "explicit_test_or_configuration_grant";
            else
                resolvedID = catalogRow.ID;
                k0 = catalogRow.K0;
                k2 = catalogRow.K2;
                rowIndex = catalogRow.RowIndex;
                standardReference = catalogRow.StandardReference;
                sourceKind = catalogRow.SourceKind;
            end
            tdra = struct("TDRAID", string(resolvedID), ...
                "StartSymbol", double(start), ...
                "NumSymbols", double(length), ...
                "MappingType", mapping, ...
                "SLIV", sixgr.phy.frame.ResourceAllocationValidator. ...
                    encodeSLIV(start, length, symbolsPerSlot), ...
                "K0", double(k0), "K2", double(k2), ...
                "CatalogRowIndex", double(rowIndex), ...
                "StandardReference", string(standardReference), ...
                "SourceKind", string(sourceKind));
        end

        function [startSymbol, numSymbols] = decodeSLIV(sliv, symbolsPerSlot)
            validateattributes(sliv, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            candidates = zeros(0, 2);
            for start = 0:(symbolsPerSlot - 1)
                for len = 1:(symbolsPerSlot - start)
                    encoded = sixgr.phy.frame.ResourceAllocationValidator. ...
                        encodeSLIV(start, len, symbolsPerSlot);
                    if encoded == sliv
                        candidates(end + 1, :) = [start len]; %#ok<AGROW>
                    end
                end
            end
            if size(candidates, 1) ~= 1
                error("sixgr:phy:frame:InvalidSLIV", ...
                    "SLIV %d does not uniquely identify a valid allocation.", sliv);
            end
            startSymbol = candidates(1, 1);
            numSymbols = candidates(1, 2);
        end

        function sliv = encodeSLIV(startSymbol, numSymbols, symbolsPerSlot)
            validateattributes(startSymbol, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(numSymbols, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            validateattributes(symbolsPerSlot, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            if startSymbol + numSymbols > symbolsPerSlot
                error("sixgr:phy:frame:InvalidTDRA", ...
                    "StartSymbol + NumSymbols exceeds SymbolsPerSlot.");
            end
            if numSymbols - 1 <= floor(symbolsPerSlot / 2)
                sliv = symbolsPerSlot * (numSymbols - 1) + startSymbol;
            else
                sliv = symbolsPerSlot * (symbolsPerSlot - numSymbols + 1) + ...
                    (symbolsPerSlot - 1 - startSymbol);
            end
        end

        function occupancy = buildOccupancy(allocation)
            %BUILDOCCUPANCY Build exact global subcarrier/symbol/port RE keys.
            if isfield(allocation, "RECoordinates") && ...
                    ~isempty(allocation.RECoordinates)
                coords = double(allocation.RECoordinates);
                if size(coords, 2) ~= 3 || any(~isfinite(coords), "all") || ...
                        any(coords < 0, "all") || any(coords ~= floor(coords), "all")
                    error("sixgr:phy:frame:InvalidRECoordinates", ...
                        "RECoordinates must be zero-based integer [subcarrier symbol port].");
                end
                lowerSubcarrier = allocation.StartRB * 12;
                upperSubcarrier = ...
                    (allocation.StartRB + allocation.NumRB) * 12 - 1;
                lowerSymbol = allocation.StartSymbol;
                upperSymbol = allocation.StartSymbol + ...
                    allocation.NumSymbols - 1;
                if any(coords(:, 1) < lowerSubcarrier | ...
                        coords(:, 1) > upperSubcarrier) || ...
                        any(coords(:, 2) < lowerSymbol | ...
                        coords(:, 2) > upperSymbol) || ...
                        any(~ismember(coords(:, 3), allocation.Ports))
                    error("sixgr:phy:frame:RECoordinatesOutsideAllocation", ...
                        "Explicit RECoordinates must lie inside the declared " + ...
                        "RB, symbol, and port allocation.");
                end
            else
                subcarriers = allocation.StartRB * 12 + ...
                    (0:(allocation.NumRB * 12 - 1));
                symbols = allocation.StartSymbol + (0:(allocation.NumSymbols - 1));
                ports = double(allocation.Ports(:).');
                [sc, sym, port] = ndgrid(subcarriers, symbols, ports);
                coords = [sc(:), sym(:), port(:)];
            end
            count = size(coords, 1);
            gridID = string(allocation.GridID);
            if strlength(gridID) == 0
                gridID = "cc" + string(allocation.CCID) + ...
                    "_bwp" + string(allocation.BWPID) + "_grid";
            end
            keys = strings(count, 1);
            for i = 1:count
                keys(i) = sprintf( ...
                    "%s|slot=%d|sc=%d|sym=%d|port=%d", ...
                    gridID, allocation.AbsoluteSlot, coords(i, 1), ...
                    coords(i, 2), coords(i, 3));
            end
            excluded = string(allocation.RateMatchedREKeys);
            excluded = excluded(strlength(excluded) > 0);
            reserved = string(allocation.ReservedREKeys);
            reserved = reserved(strlength(reserved) > 0);
            if ~isempty(excluded)
                if strlength(strtrim(string(allocation.ReservedReason))) == 0
                    error("sixgr:phy:frame:MissingRateMatchReservationSource", ...
                        "Rate-matched RE keys require a nonempty ReservedReason.");
                end
                if any(~ismember(excluded, reserved))
                    error("sixgr:phy:frame:UnprovenRateMatchReservation", ...
                        "Every rate-matched RE key must be present in the " + ...
                        "explicit ReservedREKeys set.");
                end
                if any(~ismember(excluded, keys))
                    error("sixgr:phy:frame:RateMatchKeyOutsideAllocation", ...
                        "A rate-matched RE key does not belong to this allocation.");
                end
            end
            keep = ~ismember(keys, excluded);
            coords = coords(keep, :);
            keys = keys(keep);
            count = numel(keys);
            occupancy = table( ...
                repmat(string(allocation.TestID), count, 1), ...
                repmat(double(allocation.CCID), count, 1), ...
                repmat(double(allocation.BWPID), count, 1), ...
                repmat(double(allocation.AbsoluteSlot), count, 1), ...
                coords(:, 2), floor(coords(:, 1) / 12), mod(coords(:, 1), 12), ...
                coords(:, 3), repmat(string(allocation.Channel), count, 1), ...
                repmat(string(allocation.Direction), count, 1), ...
                false(count, 1), ...
                repmat(string(allocation.ReservedReason), count, 1), ...
                keys, ...
                'VariableNames', {'TestID','CCID','BWPID','Slot','Symbol', ...
                'RB','SubcarrierInRB','Port','Channel','Direction', ...
                'CollisionFlag','ReservedReason','REKey'});
        end
    end

    methods (Static, Access = private)
        function normalized = normalizeAllocation(raw, symbolsPerSlot, strict)
            if ~isstruct(raw)
                error("sixgr:phy:frame:InvalidAllocation", ...
                    "Allocation must be a validated struct.");
            end
            normalized = raw;
            channel = sixgr.phy.frame.ResourceAllocationValidator.field(raw, ...
                {"Channel"});
            direction = sixgr.phy.frame.ResourceAllocationValidator.field(raw, ...
                {"Direction"});
            if isempty(channel) || isempty(direction)
                error("sixgr:phy:frame:InvalidAllocation", ...
                    "Allocation requires Channel and Direction.");
            end
            normalized.Channel = upper(strtrim(string(channel)));
            normalized.Direction = upper(strtrim(string(direction)));
            if ~any(normalized.Direction == ["DL","UL"])
                error("sixgr:phy:frame:InvalidAllocationDirection", ...
                    "Allocation Direction must be DL or UL.");
            end
            if isempty(symbolsPerSlot)
                if isfield(raw, "SymbolsPerSlot")
                    symbolsPerSlot = raw.SymbolsPerSlot;
                else
                    error("sixgr:phy:frame:MissingSymbolsPerSlot", ...
                        "Allocation validation requires explicit canonical " + ...
                        "SymbolsPerSlot or a slot state that owns it.");
                end
            end
            validateattributes(symbolsPerSlot, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            normalized.SymbolsPerSlot = double(symbolsPerSlot);
            tdra = sixgr.phy.frame.ResourceAllocationValidator. ...
                resolveTDRA(raw, symbolsPerSlot);
            if strict && any(normalized.Channel == ["PDSCH","PUSCH"]) && ...
                    strlength(tdra.MappingType) == 0
                error("sixgr:phy:frame:MissingExplicitTDRA", ...
                    "Strict PDSCH/PUSCH TDRA requires MappingType A or B.");
            end
            normalized.StartSymbol = tdra.StartSymbol;
            normalized.NumSymbols = tdra.NumSymbols;
            normalized.SLIV = tdra.SLIV;
            normalized.MappingType = tdra.MappingType;
            normalized.TDRAID = tdra.TDRAID;
            normalized.K0 = tdra.K0;
            normalized.K2 = tdra.K2;
            normalized.TDRAStandardReference = tdra.StandardReference;
            normalized.TDRASourceKind = tdra.SourceKind;
            frequencyStart = sixgr.phy.frame.ResourceAllocationValidator. ...
                field(raw, {"StartRB","startRB"});
            frequencyCount = sixgr.phy.frame.ResourceAllocationValidator. ...
                field(raw, {"NumRB","numRB"});
            if isempty(frequencyStart) || isempty(frequencyCount)
                error("sixgr:phy:frame:MissingExplicitFrequencyAllocation", ...
                    "Allocation requires explicit zero-based StartRB and NumRB.");
            end
            normalized.StartRB = frequencyStart;
            normalized.NumRB = frequencyCount;
            defaults = struct("CCID", 0, "BWPID", 0, "AbsoluteSlot", 0, ...
                "GridNumRB", [], "Ports", 0, ...
                "RECoordinates", [], "RateMatchedREKeys", strings(0, 1), ...
                "ReservedREKeys", strings(0, 1), ...
                "ReservedReason", "", "GridID", "", "TestID", "");
            names = fieldnames(defaults);
            for i = 1:numel(names)
                if ~isfield(normalized, names{i}) || isempty(normalized.(names{i}))
                    normalized.(names{i}) = defaults.(names{i});
                end
            end
            integerFields = ["CCID","BWPID","AbsoluteSlot","StartRB","NumRB"];
            for name = integerFields
                value = normalized.(name);
                if name == "NumRB"
                    validateattributes(value, {'numeric'}, ...
                        {'scalar','integer','positive','finite'});
                else
                    validateattributes(value, {'numeric'}, ...
                        {'scalar','integer','nonnegative','finite'});
                end
                normalized.(name) = double(value);
            end
            validateattributes(normalized.Ports, {'numeric'}, ...
                {'vector','integer','nonnegative','finite'});
            normalized.Ports = unique(double(normalized.Ports(:).'), "stable");
            normalized.RateMatchedREKeys = string(normalized.RateMatchedREKeys);
            normalized.ReservedREKeys = string(normalized.ReservedREKeys);
            normalized.ReservedReason = string(normalized.ReservedReason);
            normalized.GridID = string(normalized.GridID);
            normalized.TestID = string(normalized.TestID);
        end

        function reason = classifyReason(allocation, availability)
            if ~availability.Available
                reason = string(availability.ReasonCode);
                return;
            end
            observed = string(availability.ObservedDirections);
            channel = string(allocation.Channel);
            symbolsPerSlot = double(allocation.SymbolsPerSlot);
            if allocation.StartSymbol == 0 && ...
                    allocation.NumSymbols == symbolsPerSlot && ...
                    channel == "PDSCH"
                reason = "preserve_explicit_full_slot_pdsch_no_auto_shift";
            elseif allocation.StartSymbol == 0 && ...
                    allocation.NumSymbols == symbolsPerSlot && ...
                    channel == "PUSCH"
                reason = "preserve_explicit_full_slot_pusch";
            elseif all(observed == "D")
                reason = "fixed_dl_symbols";
            elseif all(observed == "U")
                reason = "fixed_ul_symbols";
            elseif all(observed == "DL")
                reason = "flexible_symbols_resolved_dl";
            elseif all(observed == "UL")
                reason = "flexible_symbols_resolved_ul";
            elseif allocation.Direction == "UL" && ...
                    any(observed == "UL") && any(observed == "U")
                reason = "flex_plus_fixed_ul";
            elseif allocation.Direction == "DL" && ...
                    any(observed == "DL") && any(observed == "D")
                reason = "flex_plus_fixed_dl";
            else
                reason = "available";
            end
        end

        function out = baseResult()
            out = struct( ...
                "ActualValid", false, ...
                "ReasonCode", "", ...
                "ErrorID", "", ...
                "Message", "", ...
                "Allocation", struct(), ...
                "ObservedDirections", strings(0, 1), ...
                "Occupancy", ...
                    sixgr.phy.frame.ResourceAllocationValidator.emptyOccupancy(), ...
                "OriginalUnchanged", true);
        end

        function occupancy = emptyOccupancy()
            occupancy = table( ...
                strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
                zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
                strings(0,1), strings(0,1), false(0,1), strings(0,1), ...
                strings(0,1), ...
                'VariableNames', {'TestID','CCID','BWPID','Slot','Symbol', ...
                'RB','SubcarrierInRB','Port','Channel','Direction', ...
                'CollisionFlag','ReservedReason','REKey'});
        end

        function symbolsPerSlot = resolveSymbolsPerSlot( ...
                allocation, slotState, requested)
            symbolsPerSlot = requested;
            if ~isempty(symbolsPerSlot)
                return;
            end
            if isstruct(allocation) && isfield(allocation, ...
                    "SymbolsPerSlot") && ~isempty(allocation.SymbolsPerSlot)
                symbolsPerSlot = allocation.SymbolsPerSlot;
                return;
            end
            if isobject(slotState) && isprop(slotState, "SymbolsPerSlot")
                symbolsPerSlot = slotState.SymbolsPerSlot;
                return;
            end
            if isstruct(slotState) && isfield(slotState, ...
                    "SymbolsPerSlot") && ~isempty(slotState.SymbolsPerSlot)
                symbolsPerSlot = slotState.SymbolsPerSlot;
                return;
            end
            candidates = ["ResolvedDirection","SymbolDirection", ...
                "CommonDirection"];
            for name = candidates
                if isstruct(slotState) && isfield(slotState, name) && ...
                        ~isempty(slotState.(name))
                    value = slotState.(name);
                    if isvector(value)
                        symbolsPerSlot = numel(value);
                    else
                        symbolsPerSlot = size(value, 2);
                    end
                    return;
                end
            end
            error("sixgr:phy:frame:MissingSymbolsPerSlot", ...
                "Allocation validation requires explicit canonical " + ...
                "SymbolsPerSlot or a slot state that owns it.");
        end

        function value = field(s, names)
            value = [];
            fields = fieldnames(s);
            for i = 1:numel(names)
                index = find(strcmpi(fields, names{i}), 1);
                if ~isempty(index)
                    value = s.(fields{index});
                    return;
                end
            end
        end
    end
end
