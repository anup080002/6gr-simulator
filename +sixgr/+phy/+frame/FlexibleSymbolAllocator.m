classdef FlexibleSymbolAllocator
    %FLEXIBLESYMBOLALLOCATOR Resolve only common-flexible TDD symbols.
    %
    % Runtime decisions are separate from common and dedicated ownership.
    % The returned state records the owner and source of every decision.

    methods (Static)
        function state = initialize(base)
            %INITIALIZE Create runtime state without resolving flexible symbols.
            if isa(base, "sixgr.phy.frame.TDDCommonConfig")
                common = base.CommonDirection;
                dedicated = strings(size(common));
                resolved = base.ResolvedDirection;
                symbolMap = common;
            elseif isa(base, "sixgr.phy.frame.TDDDedicatedConfig")
                common = base.CommonDirection;
                dedicated = base.DedicatedDirection;
                resolved = base.ResolvedDirection;
                symbolMap = base.SymbolDirection;
            elseif isstruct(base)
                required = ["CommonDirection","ResolvedDirection"];
                for name = required
                    if ~isfield(base, name)
                        error("sixgr:phy:frame:InvalidFlexibleState", ...
                            "Base state is missing %s.", name);
                    end
                end
                common = char(base.CommonDirection);
                resolved = string(base.ResolvedDirection);
                if isfield(base, "DedicatedDirection")
                    dedicated = string(base.DedicatedDirection);
                else
                    dedicated = strings(size(common));
                end
                if isfield(base, "SymbolDirection")
                    symbolMap = char(base.SymbolDirection);
                else
                    symbolMap = common;
                end
            else
                error("sixgr:phy:frame:InvalidFlexibleState", ...
                    "Unsupported base state type %s.", class(base));
            end
            source = strings(size(common));
            source(common == 'D' | common == 'U') = "common_rrc";
            dedicatedMask = common == 'F' & ...
                (resolved == "D" | resolved == "U");
            source(dedicatedMask) = "dedicated_rrc";
            state = struct( ...
                "DuplexMode", "TDD", ...
                "CommonDirection", common, ...
                "DedicatedDirection", dedicated, ...
                "SymbolDirection", symbolMap, ...
                "ResolvedDirection", resolved, ...
                "ResolutionSource", source, ...
                "AllocationOwner", strings(size(common)), ...
                "IndexConvention", "zero_based");
        end

        function state = allocate(baseOrState, requests, varargin)
            %ALLOCATE Apply deterministic runtime decisions to flexible symbols.
            %
            % Request fields are Slot or AbsoluteSlot, StartSymbol,
            % NumSymbols, Direction (DL/UL/GUARD/UNUSED), Channel, and an
            % optional DecisionSource.
            p = inputParser;
            addParameter(p, "MinimumGuardSymbols", 0, ...
                @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
                x >= 0 && x == floor(x));
            parse(p, varargin{:});
            minimumGuard = double(p.Results.MinimumGuardSymbols);

            if isstruct(baseOrState) && isfield(baseOrState, "ResolutionSource")
                state = baseOrState;
            else
                state = sixgr.phy.frame.FlexibleSymbolAllocator.initialize( ...
                    baseOrState);
            end
            if isempty(requests)
                sixgr.phy.frame.FlexibleSymbolAllocator.validateGuard( ...
                    state.ResolvedDirection, minimumGuard);
                return;
            end
            if ~isstruct(requests)
                error("sixgr:phy:frame:InvalidFlexibleAllocationRequest", ...
                    "Runtime allocation requests must be a struct array.");
            end

            for i = 1:numel(requests)
                request = sixgr.phy.frame.FlexibleSymbolAllocator. ...
                    normalizeRequest(requests(i), size(state.CommonDirection));
                row = mod(request.AbsoluteSlot, size(state.CommonDirection, 1)) + 1;
                cols = request.StartSymbol + (1:request.NumSymbols);
                for col = cols
                    state = sixgr.phy.frame.FlexibleSymbolAllocator. ...
                        applySymbol(state, row, col, request);
                end
            end
            sixgr.phy.frame.FlexibleSymbolAllocator.validateGuard( ...
                state.ResolvedDirection, minimumGuard);
        end
    end

    methods (Static, Access = private)
        function request = normalizeRequest(raw, mapSize)
            absoluteSlot = sixgr.phy.frame.FlexibleSymbolAllocator.firstField( ...
                raw, {"AbsoluteSlot","Slot"});
            startSymbol = sixgr.phy.frame.FlexibleSymbolAllocator.firstField( ...
                raw, {"StartSymbol"});
            numSymbols = sixgr.phy.frame.FlexibleSymbolAllocator.firstField( ...
                raw, {"NumSymbols"});
            direction = sixgr.phy.frame.FlexibleSymbolAllocator.firstField( ...
                raw, {"Direction","Decision"});
            channel = sixgr.phy.frame.FlexibleSymbolAllocator.firstField( ...
                raw, {"Channel","AllocationOwner"});
            source = sixgr.phy.frame.FlexibleSymbolAllocator.firstField( ...
                raw, {"DecisionSource","ResolutionSource"});
            if isempty(absoluteSlot) || isempty(startSymbol) || ...
                    isempty(numSymbols) || isempty(direction) || isempty(channel)
                error("sixgr:phy:frame:InvalidFlexibleAllocationRequest", ...
                    "Request requires Slot/AbsoluteSlot, StartSymbol, " + ...
                    "NumSymbols, Direction, and Channel.");
            end
            validateattributes(absoluteSlot, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(startSymbol, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(numSymbols, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            if startSymbol + numSymbols > mapSize(2)
                error("sixgr:phy:frame:SymbolRangeOutOfBounds", ...
                    "Zero-based symbol range [%d,%d] exceeds the slot.", ...
                    startSymbol, startSymbol + numSymbols - 1);
            end
            direction = upper(strtrim(string(direction)));
            if direction == "D"
                direction = "DL";
            elseif direction == "U"
                direction = "UL";
            end
            if ~any(direction == ["DL","UL","GUARD","UNUSED"])
                error("sixgr:phy:frame:InvalidFlexibleDirection", ...
                    "Direction must be DL, UL, GUARD, or UNUSED.");
            end
            channel = strtrim(string(channel));
            if strlength(channel) == 0
                error("sixgr:phy:frame:InvalidFlexibleAllocationRequest", ...
                    "Channel/AllocationOwner cannot be empty.");
            end
            if isempty(source)
                source = "runtime_allocator";
            end
            request = struct( ...
                "AbsoluteSlot", double(absoluteSlot), ...
                "StartSymbol", double(startSymbol), ...
                "NumSymbols", double(numSymbols), ...
                "Direction", direction, ...
                "Channel", channel, ...
                "DecisionSource", string(source));
        end

        function state = applySymbol(state, row, col, request)
            common = state.CommonDirection(row, col);
            current = state.ResolvedDirection(row, col);
            requested = request.Direction;
            if common ~= 'F'
                if (common == 'D' && requested ~= "DL") || ...
                        (common == 'U' && requested ~= "UL")
                    if common == 'D'
                        id = "sixgr:phy:frame:AllocationHitsFixedDL";
                    else
                        id = "sixgr:phy:frame:AllocationHitsFixedUL";
                    end
                    error(id, ...
                        "Runtime %s request cannot change common fixed-%s symbol.", ...
                        requested, string(common));
                end
                state = sixgr.phy.frame.FlexibleSymbolAllocator. ...
                    appendOwner(state, row, col, request);
                return;
            end

            desired = requested;
            if requested == "DL"
                desired = "DL";
            elseif requested == "UL"
                desired = "UL";
            end
            if current == "UNRESOLVED_FLEX"
                state.ResolvedDirection(row, col) = desired;
                state.ResolutionSource(row, col) = request.DecisionSource;
                state.AllocationOwner(row, col) = request.Channel;
                return;
            end
            comparableCurrent = current;
            if current == "D"
                comparableCurrent = "DL";
            elseif current == "U"
                comparableCurrent = "UL";
            end
            if comparableCurrent ~= desired
                error("sixgr:phy:frame:ConflictingFlexibleSymbolResolution", ...
                    "Flexible symbol is already %s and cannot also be " + ...
                    "resolved %s by %s.", current, desired, request.Channel);
            end
            state = sixgr.phy.frame.FlexibleSymbolAllocator. ...
                appendOwner(state, row, col, request);
        end

        function state = appendOwner(state, row, col, request)
            owner = state.AllocationOwner(row, col);
            if strlength(owner) == 0
                state.AllocationOwner(row, col) = request.Channel;
            elseif ~contains("+" + owner + "+", "+" + request.Channel + "+")
                state.AllocationOwner(row, col) = owner + "+" + request.Channel;
            end
            source = state.ResolutionSource(row, col);
            if strlength(source) == 0
                state.ResolutionSource(row, col) = request.DecisionSource;
            end
        end

        function validateGuard(resolved, minimumGuard)
            if minimumGuard == 0
                return;
            end
            flat = reshape(resolved.', 1, []);
            direction = flat;
            direction(direction == "D") = "DL";
            direction(direction == "U") = "UL";
            directional = find(direction == "DL" | direction == "UL");
            for i = 1:(numel(directional) - 1)
                a = directional(i);
                b = directional(i + 1);
                if direction(a) == direction(b)
                    continue;
                end
                between = flat((a + 1):(b - 1));
                if nnz(between == "GUARD") < minimumGuard
                    error("sixgr:phy:frame:InsufficientDirectionSwitchGuard", ...
                        "A %s-to-%s transition has %d guard symbols; " + ...
                        "%d are required.", direction(a), direction(b), ...
                        nnz(between == "GUARD"), minimumGuard);
                end
            end
        end

        function value = firstField(s, names)
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
