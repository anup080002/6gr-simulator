classdef SlotFormatResolver
    %SLOTFORMATRESOLVER Canonical facade for TDD common/dedicated maps.

    methods (Static)
        function state = resolve(varargin)
            p = inputParser;
            addParameter(p, "ReferenceSubcarrierSpacingKHz", []);
            addParameter(p, "ActiveSubcarrierSpacingKHz", []);
            addParameter(p, "CyclicPrefix", "normal");
            addParameter(p, "Pattern1", struct());
            addParameter(p, "Pattern2", struct());
            addParameter(p, "DedicatedOverrides", struct([]));
            parse(p, varargin{:});

            common = sixgr.phy.frame.TDDCommonConfig.resolve( ...
                "ReferenceSubcarrierSpacingKHz", ...
                p.Results.ReferenceSubcarrierSpacingKHz, ...
                "ActiveSubcarrierSpacingKHz", ...
                p.Results.ActiveSubcarrierSpacingKHz, ...
                "CyclicPrefix", p.Results.CyclicPrefix, ...
                "Pattern1", p.Results.Pattern1, ...
                "Pattern2", p.Results.Pattern2);
            if isempty(p.Results.DedicatedOverrides)
                state = common;
            else
                state = sixgr.phy.frame.TDDDedicatedConfig.apply( ...
                    common, p.Results.DedicatedOverrides);
            end
        end

        function result = isAvailable(state, absoluteSlot, startSymbol, ...
                numSymbols, direction)
            %ISAVAILABLE Check one zero-based TDD symbol allocation.
            validateattributes(absoluteSlot, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(startSymbol, {'numeric'}, ...
                {'scalar','integer','nonnegative','finite'});
            validateattributes(numSymbols, {'numeric'}, ...
                {'scalar','integer','positive','finite'});
            direction = upper(string(direction));
            if ~any(direction == ["DL","UL"])
                error("sixgr:phy:frame:InvalidAllocationDirection", ...
                    "Direction must be DL or UL.");
            end
            [resolved, slots, symbols] = ...
                sixgr.phy.frame.SlotFormatResolver.stateDirections(state);
            if startSymbol + numSymbols > symbols
                result = sixgr.phy.frame.SlotFormatResolver.result( ...
                    false, "symbol_range_out_of_bounds", strings(1, 0));
                return;
            end
            row = mod(double(absoluteSlot), slots) + 1;
            cols = startSymbol + (1:numSymbols);
            observed = resolved(row, cols);
            if any(observed == "UNRESOLVED_FLEX")
                result = sixgr.phy.frame.SlotFormatResolver.result( ...
                    false, "flexible_symbols_unresolved", observed);
                return;
            end
            if any(observed == "GUARD")
                result = sixgr.phy.frame.SlotFormatResolver.result( ...
                    false, "allocation_hits_guard", observed);
                return;
            end
            if any(observed == "UNUSED")
                result = sixgr.phy.frame.SlotFormatResolver.result( ...
                    false, "allocation_hits_unused", observed);
                return;
            end
            if direction == "DL" && any(observed == "U" | observed == "UL")
                result = sixgr.phy.frame.SlotFormatResolver.result( ...
                    false, "allocation_hits_fixed_ul", observed);
                return;
            end
            if direction == "UL" && any(observed == "D" | observed == "DL")
                result = sixgr.phy.frame.SlotFormatResolver.result( ...
                    false, "allocation_hits_fixed_dl", observed);
                return;
            end
            result = sixgr.phy.frame.SlotFormatResolver.result( ...
                true, "available", observed);
        end
    end

    methods (Static, Access = private)
        function [resolved, slots, symbols] = stateDirections(state)
            if isa(state, "sixgr.phy.frame.TDDCommonConfig") || ...
                    isa(state, "sixgr.phy.frame.TDDDedicatedConfig")
                resolved = state.ResolvedDirection;
            elseif isstruct(state) && isfield(state, "ResolvedDirection")
                if isfield(state, "DuplexMode") && ...
                        upper(string(state.DuplexMode)) ~= "TDD"
                    error("sixgr:phy:frame:TDDResolverCalledForFDD", ...
                        "TDD SlotFormatResolver cannot resolve FDD availability.");
                end
                resolved = string(state.ResolvedDirection);
            else
                error("sixgr:phy:frame:InvalidSlotFormatState", ...
                    "Unsupported slot-format state type %s.", class(state));
            end
            slots = size(resolved, 1);
            symbols = size(resolved, 2);
        end

        function out = result(available, reason, observed)
            out = struct( ...
                "Available", logical(available), ...
                "ReasonCode", string(reason), ...
                "ObservedDirections", string(observed), ...
                "DuplexMode", "TDD");
        end
    end
end
