classdef CrossCarrierControlContext
    %CROSSCARRIERCONTROLCONTEXT Validated carrier-indicator routing.

    properties (SetAccess = private)
        Data
        Digest
    end

    methods
        function obj = CrossCarrierControlContext(data)
            required = ["CarrierIndicatorPresent","CarrierIndicatorWidth", ...
                "CarrierIndicatorMap","ControlCarrier","ScheduledCarrier"];
            if ~(isstruct(data) && isscalar(data)) || ...
                    any(~isfield(data, cellstr(required)))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "CrossCarrierControlContext is incomplete.");
            end
            width = double(data.CarrierIndicatorWidth);
            if logical(data.CarrierIndicatorPresent) ~= (width > 0) || ...
                    width < 0 || width ~= fix(width)
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "Carrier indicator presence and width are inconsistent.");
            end
            if ~isstruct(data.CarrierIndicatorMap)
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "CarrierIndicatorMap must be a structure array.");
            end
            obj.Data = orderfields(data);
            obj.Digest = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8( ...
                unicode2native(jsonencode(obj.Data), "UTF-8"))));
        end

        function carrier = resolve(obj, indicator)
            if ~logical(obj.Data.CarrierIndicatorPresent)
                if double(indicator) ~= 0
                    error("sixgr:phy:pdcch:wrong_scheduled_carrier", ...
                        "Carrier indicator is absent but a nonzero value was decoded.");
                end
                carrier = double(obj.Data.ControlCarrier);
                return;
            end
            map = obj.Data.CarrierIndicatorMap;
            idx = find(arrayfun(@(x) double(x.Indicator) == double(indicator), map), 1);
            if isempty(idx)
                error("sixgr:phy:pdcch:wrong_scheduled_carrier", ...
                    "Carrier indicator %d is not installed.", indicator);
            end
            carrier = double(map(idx).ScheduledCarrier);
        end
    end
end
