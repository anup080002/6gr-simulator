classdef ControlBeamState
    %CONTROLBEAMSTATE Observed TCI/QCL/beam monitoring state.

    properties (SetAccess = private)
        Data
        Digest
    end

    methods
        function obj = ControlBeamState(data)
            required = ["TCIStateID","TCIActive","QCLSourceType","QCLSourceID", ...
                "BeamID","BeamActive","BeamBlocked","MeasurementSlot", ...
                "MeasurementMaxAgeSlots","MeasurementProvenance"];
            if ~(isstruct(data) && isscalar(data)) || ...
                    any(~isfield(data, cellstr(required)))
                error("sixgr:phy:pdcch:inactive_tci_state", ...
                    "ControlBeamState is incomplete.");
            end
            if strlength(string(data.MeasurementProvenance)) == 0
                error("sixgr:phy:pdcch:stale_beam_measurement", ...
                    "Control beam state requires observed RS/beam provenance.");
            end
            obj.Data = orderfields(data);
            obj.Digest = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8( ...
                unicode2native(jsonencode(obj.Data), "UTF-8"))));
        end

        function validateForSlot(obj, absoluteSlot)
            if ~logical(obj.Data.TCIActive) || ~logical(obj.Data.BeamActive) || ...
                    logical(obj.Data.BeamBlocked)
                error("sixgr:phy:pdcch:inactive_tci_state", ...
                    "TCI state %s/beam %s is inactive or blocked.", ...
                    string(obj.Data.TCIStateID), string(obj.Data.BeamID));
            end
            age = double(absoluteSlot) - double(obj.Data.MeasurementSlot);
            if age < 0 || age > double(obj.Data.MeasurementMaxAgeSlots)
                error("sixgr:phy:pdcch:stale_beam_measurement", ...
                    "Control beam measurement age %g exceeds the configured maximum %g slots.", ...
                    age, double(obj.Data.MeasurementMaxAgeSlots));
            end
        end
    end
end
