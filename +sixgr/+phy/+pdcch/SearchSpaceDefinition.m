classdef SearchSpaceDefinition
    %SEARCHSPACEDEFINITION Validated CSS/USS monitoring configuration.

    properties (SetAccess = private)
        Data
        Digest
    end

    methods
        function obj = SearchSpaceDefinition(data)
            required = ["SearchSpaceID","SearchSpaceType","CORESETID", ...
                "PeriodSlots","OffsetSlots","DurationSlots", ...
                "MonitoringSymbolsWithinSlot","NumCandidates", ...
                "MonitoredFormats","AllowedRNTITypes","NCI"];
            if ~(isstruct(data) && isscalar(data)) || ...
                    any(~isfield(data, cellstr(required)))
                error("sixgr:phy:pdcch:invalid_search_space_periodicity", ...
                    "SearchSpaceDefinition is missing mandatory configuration.");
            end
            data.SearchSpaceType = upper(strrep(string(data.SearchSpaceType), "-", "_"));
            if ~ismember(data.SearchSpaceType, ["CSS","USS","TYPE0","TYPE0A","TYPE1","TYPE2","TYPE3"])
                error("sixgr:phy:pdcch:invalid_search_space_periodicity", ...
                    "SearchSpaceType must be CSS, USS or Type0-Type3.");
            end
            period = localInteger(data.PeriodSlots, 1, 2560, "PeriodSlots", ...
                "sixgr:phy:pdcch:invalid_search_space_periodicity");
            offset = localInteger(data.OffsetSlots, 0, period-1, "OffsetSlots", ...
                "sixgr:phy:pdcch:invalid_search_space_periodicity");
            duration = localInteger(data.DurationSlots, 1, period, "DurationSlots", ...
                "sixgr:phy:pdcch:invalid_search_space_periodicity");
            bitmap = data.MonitoringSymbolsWithinSlot;
            if ischar(bitmap) || isstring(bitmap)
                text = char(string(bitmap));
                if numel(text) ~= 14 || any(~ismember(text, ['0','1']))
                    error("sixgr:phy:pdcch:invalid_monitoring_symbol_bitmap", ...
                        "MonitoringSymbolsWithinSlot must contain exactly 14 binary characters.");
                end
                bitmap = text == '1';
            else
                bitmap = logical(bitmap(:).');
                if numel(bitmap) ~= 14
                    error("sixgr:phy:pdcch:invalid_monitoring_symbol_bitmap", ...
                        "MonitoringSymbolsWithinSlot must contain exactly 14 values.");
                end
            end
            if ~any(bitmap)
                error("sixgr:phy:pdcch:invalid_monitoring_symbol_bitmap", ...
                    "At least one monitoring symbol must be enabled.");
            end
            candidates = double(data.NumCandidates(:).');
            if numel(candidates) ~= 5 || any(~isfinite(candidates) | candidates < 0 | candidates ~= fix(candidates))
                error("sixgr:phy:pdcch:invalid_candidate_count", ...
                    "NumCandidates must be five nonnegative integers for AL 1/2/4/8/16.");
            end
            data.PeriodSlots = period;
            data.OffsetSlots = offset;
            data.DurationSlots = duration;
            data.MonitoringSymbolsWithinSlot = bitmap;
            data.NumCandidates = candidates;
            data.MonitoredFormats = string(data.MonitoredFormats(:)).';
            data.AllowedRNTITypes = string(data.AllowedRNTITypes(:)).';
            data.NCI = localInteger(data.NCI, 0, 65535, "NCI", ...
                "sixgr:phy:pdcch:invalid_candidate_count");
            obj.Data = orderfields(data);
            obj.Digest = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8( ...
                unicode2native(jsonencode(obj.Data), "UTF-8"))));
        end
    end
end

function value = localInteger(value, minimum, maximum, name, identifier)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= minimum && value <= maximum && value == fix(value))
    error(identifier, "%s must be an integer in [%d,%d].", name, minimum, maximum);
end
end
