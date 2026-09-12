classdef DCISchemaEngine
    %DCISCHEMAENGINE Contextual Release-18 DCI 0_0/0_1/1_0/1_1 schema.

    methods (Static)
        function schema = resolve(context)
            context = sixgr.phy.pdcch.DCISchemaEngine.requireContext(context);
            data = context.Data;
            fmt = string(data.DCIFormat);
            if string(data.RNTIType)=="TC-RNTI" && isfield(data,'FrequencyReferenceSize')
                nFreq = ceil(log2(data.FrequencyReferenceSize*(data.FrequencyReferenceSize+1)/2));
                definitions = [
                    localDef("format_identifier",1,1,1,"DL DCI format","38.212 7.3.1.2.1")
                    localDef("frequency_resource_assignment",nFreq,0,2^nFreq-1,"CORESET0","38.212 7.3.1.2.1")
                    localDef("time_resource_assignment",4,0,15,"PDSCH common TDRA","38.212 7.3.1.2.1")
                    localDef("vrb_to_prb_mapping",1,0,1,"PDSCH resource allocation","38.212 7.3.1.2.1")
                    localDef("mcs",5,0,31,"38.214 Table 5.1.3.1-1","38.212 7.3.1.2.1")
                    localDef("ndi",1,0,1,"Msg4 HARQ state","38.212 7.3.1.2.1")
                    localDef("rv",2,0,3,"Msg4 HARQ state","38.212 7.3.1.2.1")
                    localDef("harq_process",4,0,15,"Msg4 HARQ process","38.212 7.3.1.2.1")
                    localDef("dai",2,0,0,"reserved without Msg4 ACK repetitions","38.212 7.3.1.2.1")
                    localDef("tpc_command_for_pucch",2,0,3,"PUCCH power control","38.212 7.3.1.2.1")
                    localDef("pucch_resource_indicator",3,0,7,"common PUCCH resource","38.212 7.3.1.2.1")
                    localDef("pdsch_to_harq_feedback_timing",3,0,7,"Msg4 feedback timing","38.212 7.3.1.2.1")];
                schema = struct('Format',fmt,'ContextDigest',context.Digest, ...
                    'Definitions',definitions,'RawBits',nFreq+28, ...
                    'FrequencyAssignmentBits',nFreq,'TimeAssignmentBits',4, ...
                    'SchemaVersion',"sixgr_tc_rnti_msg4_dci_r18_8_0/v1", ...
                    'StandardClause',"3GPP TS 38.212 V18.8.0 7.3.1.2.1");
                return;
            end
            if string(data.RNTIType) == "RA-RNTI"
                nFreq = ceil(log2(data.FrequencyReferenceSize * ...
                    (data.FrequencyReferenceSize + 1) / 2));
                definitions = [
                    localDef("frequency_resource_assignment",nFreq,0,2^nFreq-1,"CORESET0 or initial DL BWP","38.212 7.3.1.2.1")
                    localDef("time_resource_assignment",4,0,15,"PDSCH common TDRA","38.212 7.3.1.2.1")
                    localDef("vrb_to_prb_mapping",1,0,1,"PDSCH resource allocation","38.212 7.3.1.2.1")
                    localDef("mcs",5,0,31,"38.214 Table 5.1.3.1-1","38.212 7.3.1.2.1")
                    localDef("tb_scaling",2,0,2,"38.214 Table 5.1.3.2-2","38.212 7.3.1.2.1")
                    localDef("reserved",16,0,0,"licensed FR1/FR2-1 RA-RNTI","38.212 7.3.1.2.1")];
                schema = struct("Format",fmt,"ContextDigest",context.Digest, ...
                    "Definitions",definitions,"RawBits",nFreq+28, ...
                    "FrequencyAssignmentBits",nFreq,"TimeAssignmentBits",4, ...
                    "SchemaVersion","sixgr_ra_rnti_dci_r18_8_0/v1", ...
                    "StandardClause","3GPP TS 38.212 V18.8.0 7.3.1.2.1");
                return;
            end
            if startsWith(fmt, "0_")
                nBWP = double(data.ActiveULBWPSize);
                timeRows = data.ULTimeDomainAllocations;
            else
                nBWP = double(data.ActiveDLBWPSize);
                timeRows = data.DLTimeDomainAllocations;
            end
            nFreq = sixgr.phy.pdcch.DCISchemaEngine.frequencyWidth( ...
                nBWP, data.FrequencyAllocationType);
            nTime = max(1, ceil(log2(size(timeRows, 1))));
            nHARQ = max(1, ceil(log2(double(data.HARQProcessCount))));
            definitions = sixgr.phy.pdcch.DCISchemaEngine.emptyDefinitions();

            ulWidth=6; ulMax=63; ulClause="38.212 7.3.1.1 (legacy mapping; not table-qualified)";
            sriWidth=data.SRSResourceIndicatorWidth; sriMax=2^sriWidth-1;
            ulAntennaWidth=data.AntennaPortFieldWidth;
            if fmt=="0_1" && isfield(data,'ULReferenceSignaling')
                ref=sixgr.phy.pdcch.ULReferenceSignaling.resolve(data);
                sriWidth=ref.SRIWidth; sriMax=ref.SRIMaxValue; ulAntennaWidth=ref.AntennaWidth;
            end
            if fmt=="0_1" && isfield(data,'ULPrecoding')
                ul=sixgr.phy.pdcch.ULPrecodingField.resolve(data);
                ulWidth=ul.Width; ulMax=ul.MaxValue; ulClause=ul.StandardClause;
            end
            switch fmt
                case "0_0"
                    definitions = [
                        definitions
                        localDef("format_identifier", 1, 0, 0, "DCI format 0_0", "38.212 7.3.1.1")
                        localOptional(data.CarrierIndicatorPresent, "carrier_indicator", data.CarrierIndicatorWidth, "CrossCarrierSchedulingConfig", "38.212 7.3.1.1")
                        localDef("frequency_resource_assignment", nFreq, 0, 2^nFreq-1, "active UL BWP", "38.212 7.3.1.1")
                        localDef("time_resource_assignment", nTime, 0, size(timeRows,1)-1, "active PUSCH-TimeDomainResourceAllocationList", "38.212 7.3.1.1")
                        localDef("frequency_hopping", 1, 0, 1, "PUSCH frequency hopping", "38.212 7.3.1.1")
                        localDef("mcs", 5, 0, 31, "active PUSCH MCS table", "38.212 7.3.1.1")
                        localDef("ndi", 1, 0, 1, "HARQ state", "38.212 7.3.1.1")
                        localDef("rv", 2, 0, 3, "HARQ state", "38.212 7.3.1.1")
                        localDef("harq_process", nHARQ, 0, data.HARQProcessCount-1, "HARQ process set", "38.212 7.3.1.1")
                        localDef("tpc_command_for_pusch", 2, 0, 3, "PUSCH power control", "38.212 7.3.1.1")];
                case "1_0"
                    definitions = [
                        definitions
                        localDef("format_identifier", 1, 1, 1, "DCI format 1_0", "38.212 7.3.1.2")
                        localOptional(data.CarrierIndicatorPresent, "carrier_indicator", data.CarrierIndicatorWidth, "CrossCarrierSchedulingConfig", "38.212 7.3.1.2")
                        localDef("frequency_resource_assignment", nFreq, 0, 2^nFreq-1, "initial/active DL BWP procedure context", "38.212 7.3.1.2")
                        localDef("time_resource_assignment", nTime, 0, size(timeRows,1)-1, "active PDSCH-TimeDomainResourceAllocationList", "38.212 7.3.1.2")
                        localDef("vrb_to_prb_mapping", 1, 0, 1, "PDSCH resource allocation", "38.212 7.3.1.2")
                        localDef("mcs", 5, 0, 31, "active PDSCH MCS table", "38.212 7.3.1.2")
                        localDef("ndi", 1, 0, 1, "HARQ state", "38.212 7.3.1.2")
                        localDef("rv", 2, 0, 3, "HARQ state", "38.212 7.3.1.2")
                        localDef("harq_process", nHARQ, 0, data.HARQProcessCount-1, "HARQ process set", "38.212 7.3.1.2")
                        localDef("dai", data.DAIWidth, 0, 2^data.DAIWidth-1, "HARQ-ACK codebook", "38.212 7.3.1.2")
                        localDef("tpc_command_for_pucch", 2, 0, 3, "PUCCH power control", "38.212 7.3.1.2")
                        localDef("pucch_resource_indicator", 3, 0, 7, "PUCCH resource set", "38.212 7.3.1.2")
                        localDef("pdsch_to_harq_feedback_timing", 3, 0, 7, "dl-DataToUL-ACK", "38.212 7.3.1.2")];
                case "0_1"
                    definitions = [
                        definitions
                        localDef("format_identifier", 1, 0, 0, "DCI format 0_1", "38.212 7.3.1.1")
                        localOptional(data.CarrierIndicatorPresent, "carrier_indicator", data.CarrierIndicatorWidth, "CrossCarrierSchedulingConfig", "38.212 7.3.1.1")
                        localOptional(data.SULIndicatorPresent, "sul_indicator", 1, "supplementary uplink state", "38.212 7.3.1.1")
                        localOptional(data.BWPIndicatorPresent, "bwp_indicator", data.BWPIndicatorWidth, "active UL BWP set", "38.212 7.3.1.1")
                        localDef("frequency_resource_assignment", nFreq, 0, 2^nFreq-1, "active UL BWP", "38.212 7.3.1.1")
                        localDef("time_resource_assignment", nTime, 0, size(timeRows,1)-1, "active PUSCH-TimeDomainResourceAllocationList", "38.212 7.3.1.1")
                        localDef("frequency_hopping", 1, 0, 1, "PUSCH frequency hopping", "38.212 7.3.1.1")
                        localDef("mcs", 5, 0, 31, "active PUSCH MCS table", "38.212 7.3.1.1")
                        localDef("ndi", 1, 0, 1, "HARQ state", "38.212 7.3.1.1")
                        localDef("rv", 2, 0, 3, "HARQ state", "38.212 7.3.1.1")
                        localDef("harq_process", nHARQ, 0, data.HARQProcessCount-1, "HARQ process set", "38.212 7.3.1.1")
                        localDef("first_dai", data.DAIWidth, 0, 2^data.DAIWidth-1, "HARQ-ACK codebook", "38.212 7.3.1.1")
                        localDef("tpc_command_for_pusch", 2, 0, 3, "PUSCH power control", "38.212 7.3.1.1")
                        localDef("srs_resource_indicator", sriWidth, 0, sriMax, "SRS resource set", "38.212 7.3.1.1.2")
                        localDef("precoding_information_and_number_of_layers", ulWidth, 0, ulMax, "PUSCH codebook and layer capability", ulClause)
                        localDef("antenna_ports", ulAntennaWidth, 0, 2^ulAntennaWidth-1, "PUSCH DM-RS configuration", "38.212 7.3.1.1.2")
                        localDef("srs_request", data.SRSRequestWidth, 0, 2^data.SRSRequestWidth-1, "SRS request configuration", "38.212 7.3.1.1")
                        localDef("csi_request", data.CSIRequestWidth, 0, 2^data.CSIRequestWidth-1, "CSI request configuration", "38.212 7.3.1.1")
                        localCBG(data, "0_1")];
                case "1_1"
                    definitions = [
                        definitions
                        localDef("format_identifier", 1, 1, 1, "DCI format 1_1", "38.212 7.3.1.2")
                        localOptional(data.CarrierIndicatorPresent, "carrier_indicator", data.CarrierIndicatorWidth, "CrossCarrierSchedulingConfig", "38.212 7.3.1.2")
                        localOptional(data.BWPIndicatorPresent, "bwp_indicator", data.BWPIndicatorWidth, "active DL BWP set", "38.212 7.3.1.2")
                        localDef("frequency_resource_assignment", nFreq, 0, 2^nFreq-1, "active DL BWP", "38.212 7.3.1.2")
                        localDef("time_resource_assignment", nTime, 0, size(timeRows,1)-1, "active PDSCH-TimeDomainResourceAllocationList", "38.212 7.3.1.2")
                        localDef("vrb_to_prb_mapping", 1, 0, 1, "PDSCH resource allocation", "38.212 7.3.1.2")
                        localDef("prb_bundling_size_indicator", 1, 0, 1, "PDSCH bundling configuration", "38.212 7.3.1.2")
                        localDef("rate_matching_indicator", data.RateMatchIndicatorWidth, 0, 2^data.RateMatchIndicatorWidth-1, "rateMatchPatternGroup", "38.212 7.3.1.2")
                        localDef("zp_csirs_trigger", data.ZPCSIRSTriggerWidth, 0, 2^data.ZPCSIRSTriggerWidth-1, "aperiodic ZP-CSI-RS resources", "38.212 7.3.1.2")
                        localDef("mcs", 5, 0, 31, "active PDSCH MCS table", "38.212 7.3.1.2")
                        localDef("ndi", 1, 0, 1, "HARQ state", "38.212 7.3.1.2")
                        localDef("rv", 2, 0, 3, "HARQ state", "38.212 7.3.1.2")
                        localDef("harq_process", nHARQ, 0, data.HARQProcessCount-1, "HARQ process set", "38.212 7.3.1.2")
                        localDef("dai", data.DAIWidth, 0, 2^data.DAIWidth-1, "HARQ-ACK codebook", "38.212 7.3.1.2")
                        localDef("tpc_command_for_pucch", 2, 0, 3, "PUCCH power control", "38.212 7.3.1.2")
                        localDef("pucch_resource_indicator", 3, 0, 7, "PUCCH resource set", "38.212 7.3.1.2")
                        localDef("pdsch_to_harq_feedback_timing", 3, 0, 7, "dl-DataToUL-ACK", "38.212 7.3.1.2")
                        localDef("antenna_ports", data.AntennaPortFieldWidth, 0, 2^data.AntennaPortFieldWidth-1, "PDSCH DM-RS configuration", "38.212 7.3.1.2")
                        localOptional(data.TCIPresent, "transmission_configuration_indication", data.TCIWidth, "active TCI states", "38.212 7.3.1.2")
                        localDef("srs_request", data.SRSRequestWidth, 0, 2^data.SRSRequestWidth-1, "SRS request configuration", "38.212 7.3.1.2")
                        localDef("csi_request", data.CSIRequestWidth, 0, 2^data.CSIRequestWidth-1, "CSI request configuration", "38.212 7.3.1.2")
                        localCBG(data, "1_1")
                        localOptional(data.DMRSSequenceInitializationPresent, "dmrs_sequence_initialization", 1, "PDSCH DM-RS sequence initialization", "38.212 7.3.1.2")];
                otherwise
                    error("sixgr:phy:pdcch:unsupported_dci_format", ...
                        "Unsupported DCI format %s.", fmt);
            end
            definitions = definitions(arrayfun(@(x) x.Width > 0, definitions));
            rawBits = sum(arrayfun(@(x) x.Width, definitions));
            schema = struct( ...
                "Format", fmt, ...
                "ContextDigest", context.Digest, ...
                "Definitions", definitions, ...
                "RawBits", double(rawBits), ...
                "FrequencyAssignmentBits", double(nFreq), ...
                "TimeAssignmentBits", double(nTime), ...
                "SchemaVersion", "sixgr_dci_schema_r18_8_0_v1", ...
                "StandardClause", "3GPP TS 38.212 V18.8.0");
        end

        function width = frequencyWidth(nBWP, allocationType)
            nBWP = double(nBWP);
            allocationType = lower(string(allocationType));
            if ~(isscalar(nBWP) && isfinite(nBWP) && nBWP >= 1 && nBWP == fix(nBWP))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "The active BWP size must be a positive integer.");
            end
            switch allocationType
                case {"type1","type1_riv"}
                    width = ceil(log2(nBWP * (nBWP + 1) / 2));
                case {"type0","type0_bitmap"}
                    p = localRBGSize(nBWP);
                    width = ceil(nBWP / p);
                case {"dynamic_switch","dynamic"}
                    p = localRBGSize(nBWP);
                    width = max(ceil(log2(nBWP * (nBWP + 1) / 2)), ceil(nBWP / p)) + 1;
                otherwise
                    error("sixgr:phy:pdcch:missing_dci_context", ...
                        "FrequencyAllocationType '%s' is unsupported.", allocationType);
            end
            width = max(1, double(width));
        end

        function context = requireContext(context)
            if isa(context, "sixgr.phy.pdcch.DCIContext")
                return;
            end
            if isstruct(context) && isscalar(context) && isfield(context, "SpecRelease")
                context = sixgr.phy.pdcch.DCIContext(context);
                return;
            end
            error("sixgr:phy:pdcch:missing_dci_context", ...
                "A complete sixgr.phy.pdcch.DCIContext is required.");
        end
    end

    methods (Static, Access = private)
        function definitions = emptyDefinitions()
            definitions = sixgr.phy.pdcch.DCIFieldDefinition.empty(0, 1);
        end
    end
end

function item = localDef(name, width, valueMin, valueMax, source, clause)
item = sixgr.phy.pdcch.DCIFieldDefinition( ...
    string(name), double(width), double(valueMin), double(valueMax), ...
    string(source), string(clause), false);
end

function item = localOptional(present, name, width, source, clause)
if logical(present)
    item = localDef(name, width, 0, 2^double(width)-1, source, clause);
else
    item = sixgr.phy.pdcch.DCIFieldDefinition.empty(0, 1);
end
end

function items = localCBG(data, format)
items = sixgr.phy.pdcch.DCIFieldDefinition.empty(0, 1);
if ~logical(data.CBGFieldsPresent)
    return;
end
if startsWith(string(format), "0_")
    items = [
        localDef("cbg_transmission_information", data.CBGTransmissionWidth, 0, 2^data.CBGTransmissionWidth-1, "PUSCH CBG state", "38.212 7.3.1.1")
        localDef("ptrs_dmrs_association", 2, 0, 3, "PUSCH PTRS/DM-RS association", "38.212 7.3.1.1")];
else
    items = [
        localDef("cbg_transmission_information", data.CBGTransmissionWidth, 0, 2^data.CBGTransmissionWidth-1, "PDSCH CBG state", "38.212 7.3.1.2")
        localDef("cbg_flushing_information", data.CBGFlushWidth, 0, 2^data.CBGFlushWidth-1, "PDSCH CBG state", "38.212 7.3.1.2")];
end
items = items(arrayfun(@(x) x.Width > 0, items));
end

function p = localRBGSize(nBWP)
if nBWP <= 36
    p = 2;
elseif nBWP <= 72
    p = 4;
elseif nBWP <= 144
    p = 8;
else
    p = 16;
end
end
