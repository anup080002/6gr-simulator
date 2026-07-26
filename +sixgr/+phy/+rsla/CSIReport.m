classdef CSIReport
    %CSIREPORT Typed measured CSI payload.

    properties (SetAccess=immutable)
        Configuration sixgr.phy.rsla.CSIReportConfigurationState
        Part1 struct
        Part2 struct
        MeasurementIdentity struct
        ReportID string
        ProducerSlot double
        AvailableSlot double
    end

    methods
        function obj = CSIReport(configuration,fieldValues,measurement)
            if ~isa(configuration,"sixgr.phy.rsla.CSIReportConfigurationState")
                error("RSLA:InvalidCSIReportConfiguration", ...
                    "CSI report requires an installed typed configuration.");
            end
            if ~isstruct(measurement) || ~isfield(measurement,"Provenance") || ...
                    string(measurement.Provenance)~= ...
                    "observed_received_sample_statistics"
                error("RSLA:MissingMeasuredInput", ...
                    "Strict CSI reports require receiver-observed measurement state.");
            end
            data = configuration.Data;
            obj.Part1 = localPart(data.Part1Fields,data.Part1Widths,fieldValues,1);
            obj.Part2 = localPart(data.Part2Fields,data.Part2Widths,fieldValues,2);
            obj.Configuration = configuration;
            obj.MeasurementIdentity = measurement;
            obj.ProducerSlot = double(measurement.ProducerSlot);
            obj.AvailableSlot = double(measurement.AvailableSlot);
            obj.ReportID = "CSI-"+sixgr.phy.rsla.RSLAUtil.hash(struct( ...
                "Configuration",data,"MeasurementID",measurement.MeasurementID, ...
                "ProducerSlot",obj.ProducerSlot));
        end
    end
end

function value = localPart(fields,widths,values,part)
value = struct("Part",part,"Fields",string(fields), ...
    "Widths",double(widths),"Values",zeros(size(widths)));
for index = 1:numel(fields)
    name = char(fields(index));
    if ~isfield(values,name)
        error("RSLA:InvalidCSIReportConfiguration", ...
            "CSI report field %s is absent.",fields(index));
    end
    raw = double(values.(name));
    maximum = 2^double(widths(index))-1;
    if ~(isscalar(raw)&&isfinite(raw)&&raw>=0&&raw<=maximum&&raw==floor(raw))
        error("RSLA:InvalidCSIReportConfiguration", ...
            "CSI report field %s does not fit its exact %d-bit allocation.", ...
            fields(index),widths(index));
    end
    value.Values(index) = raw;
end
end
