classdef DecodedDCIEvent
    %DECODEDDCIEVENT Immutable validated blind-decoder output.

    properties (SetAccess = private)
        Data
        EventID
    end

    methods
        function obj = DecodedDCIEvent(data)
            required = ["WaveformID","RunID","AbsoluteSlot","MonitoringSymbol", ...
                "ControlServingCell","ControlCarrier","ControlBWP", ...
                "ScheduledServingCell","ScheduledCarrier","ScheduledBWP", ...
                "SearchSpaceID","CORESETID","AggregationLevel","CandidateIndex", ...
                "FirstCCE","DCIFormat","AlignedPayloadBits","RNTIType", ...
                "RNTIValue","CRCCheckPassed","RNTIMatch","RawPayloadBits", ...
                "RawPayloadHash","ParsedFields","ContextDigest", ...
                "ConfigurationEpoch","TCIStateID","QCLSourceType", ...
                "QCLSourceID","BeamID","MeasurementProvenance"];
            if ~(isstruct(data) && isscalar(data)) || ...
                    any(~isfield(data, cellstr(required)))
                error("sixgr:phy:pdcch:decoded_event_required", ...
                    "DecodedDCIEvent is missing mandatory identity or semantic fields.");
            end
            if ~logical(data.CRCCheckPassed) || ~logical(data.RNTIMatch)
                error("sixgr:phy:pdcch:crc_rnti_mismatch", ...
                    "A DecodedDCIEvent requires a passing CRC and matching RNTI procedure.");
            end
            sixgr.phy.pdcch.PDCCHSpecificationProfile.encodedBits(data.AggregationLevel);
            if double(data.FirstCCE) < 0 || mod(double(data.FirstCCE), double(data.AggregationLevel)) ~= 0
                error("sixgr:phy:pdcch:invalid_candidate_count", ...
                    "Decoded FirstCCE must be nonnegative and aligned to the aggregation level.");
            end
            bits = int8(data.RawPayloadBits(:));
            if numel(bits) ~= double(data.AlignedPayloadBits) || any(bits ~= 0 & bits ~= 1)
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "DecodedDCIEvent payload length does not match AlignedPayloadBits.");
            end
            actualHash = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(bits)));
            if actualHash ~= string(data.RawPayloadHash)
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "DecodedDCIEvent payload hash does not match its payload bits.");
            end
            data.DCIFormat = sixgr.phy.pdcch.normalizeDCIFormat(data.DCIFormat);
            data.RNTIType = sixgr.phy.pdcch.normalizeRNTIType(data.RNTIType);
            data.RawPayloadBits = bits;
            obj.Data = orderfields(data);
            obj.EventID = string(sixgr.rrc.asn1.asn1SHA256Hex(uint8( ...
                unicode2native(jsonencode(localHashableData(obj.Data)), "UTF-8"))));
        end

        function out = toStruct(obj)
            out = obj.Data;
            out.DecodedDCIEventID = obj.EventID;
        end
    end
end

function out = localHashableData(data)
out = data;
out.RawPayloadBits = char(join(string(int8(data.RawPayloadBits(:)).'), ""));
end
