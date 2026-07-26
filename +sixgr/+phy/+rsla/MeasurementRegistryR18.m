classdef MeasurementRegistryR18
    %MEASUREMENTREGISTRYR18 Selected TS 38.215 V18.8.0 definitions.

    methods (Static)
        function value = definitions()
            rows = [
                localDefinition("SS-RSRP","SSB","dBm","mean_power_over_declared_RS_REs","beam_and_antenna_bound")
                localDefinition("CSI-RSRP","CSI-RS","dBm","mean_power_over_declared_RS_REs","beam_and_antenna_bound")
                localDefinition("SS-RSRQ","SSB","dB","N_RB_times_RSRP_over_RSSI","beam_and_bandwidth_bound")
                localDefinition("CSI-RSRQ","CSI-RS","dB","N_RB_times_RSRP_over_RSSI","beam_and_bandwidth_bound")
                localDefinition("SS-SINR","SSB","dB","RS_power_over_interference_plus_noise","beam_and_resource_bound")
                localDefinition("CSI-SINR","CSI-RS","dB","RS_power_over_interference_plus_noise","beam_and_resource_bound")
                localDefinition("RSSI","configuredResources","dBm","received_power_over_measurement_bandwidth","bandwidth_bound")
                localDefinition("SRS-RSRP","SRS","dBm","mean_power_over_declared_RS_REs","UE_resource_and_port_bound")
            ];
            value = struct2table(rows,"AsArray",true);
        end

        function result = measure(request)
            definitions = sixgr.phy.rsla.MeasurementRegistryR18.definitions();
            quantity = upper(string(request.Quantity));
            match = find(upper(string(definitions.Quantity))==quantity);
            if numel(match)~=1
                error("RSLA:UnsupportedMeasurement", ...
                    "Measurement quantity %s is outside the bounded registry.",quantity);
            end
            requiredIdentity = ["ResourceID","BeamID","UEID","CellID","BWPID", ...
                "ProducerSlot","AvailableSlot","ConfigurationEpoch","SourceSHA256"];
            for field = requiredIdentity
                if ~isfield(request,char(field))
                    error("RSLA:WrongMeasurementIdentity", ...
                        "Measured state is missing identity field %s.",field);
                end
            end
            if ~isfield(request,"ResourceAvailable") || ~request.ResourceAvailable || ...
                    (isfield(request,"Muted") && request.Muted)
                error("RSLA:MissingMeasuredInput", ...
                    "The declared measurement resource was unavailable or muted.");
            end
            rs = double(request.ReferenceSignalPowerW);
            interference = double(request.InterferencePowerW);
            noise = double(request.NoisePowerW);
            rssi = double(request.RSSIPowerW);
            nRB = double(request.NRB);
            switch quantity
                case {"SS-RSRP","CSI-RSRP","SRS-RSRP"}
                    localRequireFinite([rs],rs>0);
                    linear = rs;
                    value = 10*log10(linear)+30;
                case {"SS-RSRQ","CSI-RSRQ"}
                    localRequireFinite([rs rssi nRB], ...
                        rs>0 && rssi>0 && nRB>=1);
                    linear = nRB*rs/rssi;
                    value = 10*log10(linear);
                case {"SS-SINR","CSI-SINR"}
                    localRequireFinite([rs interference noise], ...
                        rs>0 && interference>=0 && noise>=0 && ...
                        interference+noise>0);
                    linear = rs/(interference+noise);
                    value = 10*log10(linear);
                case "RSSI"
                    localRequireFinite(rssi,rssi>0);
                    linear = rssi;
                    value = 10*log10(linear)+30;
            end
            definition = definitions(match,:);
            result = struct("MeasurementID",string(request.MeasurementID), ...
                "Quantity",quantity,"Value",value,"LinearValue",linear, ...
                "Units",string(definition.Units), ...
                "ReferenceSignal",string(definition.ReferenceSignal), ...
                "UEID",double(request.UEID),"CellID",double(request.CellID), ...
                "BWPID",double(request.BWPID), ...
                "ResourceID",string(request.ResourceID), ...
                "BeamID",string(request.BeamID), ...
                "ProducerSlot",double(request.ProducerSlot), ...
                "AvailableSlot",double(request.AvailableSlot), ...
                "ConfigurationEpoch",double(request.ConfigurationEpoch), ...
                "SourceSHA256",string(request.SourceSHA256), ...
                "Confidence",double(request.Confidence), ...
                "Provenance","observed_received_sample_statistics", ...
                "Valid",true);
        end
    end
end

function localRequireFinite(values,rangeValid)
if any(~isfinite(values)) || ~rangeValid
    error("RSLA:MissingMeasuredInput", ...
        "Required measurement powers must come from finite received-sample statistics.");
end
end

function row = localDefinition(quantity,referenceSignal,units,averaging,validity)
row = struct("MeasurementID","R18-"+quantity, ...
    "Quantity",quantity,"ReferenceSignal",referenceSignal, ...
    "DefinitionVersion","TS 38.215 V18.8.0", ...
    "Units",units,"AveragingRule",averaging, ...
    "BeamAssociation","installed_RRC_resource_beam_and_antenna", ...
    "ValidityRule",validity,"AllowedConsumer", ...
    "decoded_CSI_or_measured_SRS_link_adaptation","Status","PASS");
end
