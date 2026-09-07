classdef RARDCIContext
    %RARDCICONTEXT RA-RNTI semantics; binary coding uses DCIPacker/DCIParser.
    % Release-18 licensed FR1/FR2-1, default-A common TDRA. Deliberately
    % rejects unsupported spectrum/list authority rather than substituting it.
    methods (Static)
        function context = create(reference, rnti)
            data = reference;
            data.SpecRelease = "Release18";
            data.SpecVersion = "18.8.0";
            data.DCIFormat = "1_0";
            data.RNTIType = "RA-RNTI";
            data.RNTIValue = rnti;
            data.SearchSpaceType = "TYPE1";
            data.MonitoredFormats = "1_0";
            data.LegacyCompatibility = false;
            context = sixgr.phy.pdcch.DCIContext(data);
        end

        function validate(d)
            required = ["SpecRelease","SpecVersion","DCIFormat","RNTIType", ...
                "RNTIValue","SearchSpaceType","MonitoredFormats", ...
                "FrequencyReferenceSize","FrequencyReferenceStart", ...
                "FrequencyReferenceSource","DMRSTypeAPosition", ...
                "CyclicPrefix","SharedSpectrum","FrequencyRange", ...
                "TimeAllocationSource","ConfigurationEpoch","LegacyCompatibility"];
            if ~all(isfield(d,required))
                error("sixgr:phy:pdcch:missing_dci_context", ...
                    "RA-RNTI requires explicit common-control sizing/TDRA authority.");
            end
            if string(d.DCIFormat) ~= "1_0" || string(d.SearchSpaceType) ~= "TYPE1" || ...
                    ~isequal(string(d.MonitoredFormats),"1_0") || logical(d.LegacyCompatibility)
                error("sixgr:phy:pdcch:invalid_rar_dci_context", ...
                    "RA-RNTI requires its own nonlegacy Type1 DCI 1_0 context.");
            end
            validateattributes(d.FrequencyReferenceSize,{'numeric'},{'scalar','integer','>=',1,'<=',275});
            validateattributes(d.FrequencyReferenceStart,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(d.RNTIValue,{'numeric'},{'scalar','integer','>=',1,'<=',65535});
            validateattributes(d.ConfigurationEpoch,{'numeric'},{'scalar','integer','nonnegative','finite'});
            if ~ismember(d.DMRSTypeAPosition,[2 3]) || ...
                    ~ismember(string(d.CyclicPrefix),["normal","extended"]) || ...
                    ~ismember(string(d.FrequencyReferenceSource), ...
                    ["decoded_mib_coreset0","decoded_sib1_initial_dl_bwp", ...
                    "scenario_initial_dl_bwp","scenario_coreset0"]) || ...
                    string(d.TimeAllocationSource) ~= "38.214_default_A"
                error("sixgr:phy:pdcch:invalid_rar_dci_context", ...
                    "RAR frequency reference, DMRS position, CP or TDRA authority is invalid.");
            end
            if ~(islogical(d.SharedSpectrum) && isscalar(d.SharedSpectrum)) || ...
                    d.SharedSpectrum || ~ismember(string(d.FrequencyRange),["FR1","FR2-1"])
                error("sixgr:phy:pdcch:unsupported_rar_dci_context", ...
                    "RA-RNTI shared-spectrum/FR2-2 sizing requires its SFN/reserved-bit rules.");
            end
        end

        function [allocations, mapping] = defaultA(cp, dmrs)
            % TS 38.214 V18.7.0 Tables 5.1.2.1.1-2 and -3, zero-based index.
            if ~ismember(dmrs,[2 3]) || ~ismember(string(cp),["normal","extended"])
                error("sixgr:phy:pdcch:invalid_rar_dci_context","Invalid default-A CP/DMRS position.");
            end
            sl = [2 12;2 10;2 9;2 7;2 5;9 4;4 4;5 7;5 2;9 2;12 2;1 13;1 6;2 4;4 7;8 4];
            if string(cp) == "extended"
                sl([1 6 8 11 12 15],:) = [2 6;6 4;5 6;10 2;1 11;4 6];
            end
            if dmrs == 3
                sl(1:5,1) = sl(1:5,1)+1;
                sl(1:5,2) = sl(1:5,2)-1;
                sl(6:7,:) = [10 4;6 4];
                if string(cp) == "extended", sl(6,:) = [8 2]; end
            end
            allocations = [(0:15).' sl zeros(16,1)];
            mapping = ["A";"A";"A";"A";"A";"B";"B";"B";"B";"B";"B";"A";"A";"A";"B";"B"];
        end

        function grant = resolveSemantics(fields, context)
            d = context.Data;
            [start,count] = sixgr.bwop.RIVFDRA.decode(d.FrequencyReferenceSize, ...
                fields.frequency_resource_assignment);
            if sixgr.bwop.RIVFDRA.encode(d.FrequencyReferenceSize,start,count) ~= ...
                    fields.frequency_resource_assignment
                error("sixgr:phy:pdcch:field_out_of_range","Noncanonical RAR FDRA RIV.");
            end
            [rows,mapping] = sixgr.phy.pdcch.RARDCIContext.defaultA(d.CyclicPrefix,d.DMRSTypeAPosition);
            row = rows(fields.time_resource_assignment+1,:);
            scales = [1 .5 .25];
            grant = struct("prb_start",start,"num_prb",count, ...
                "reference_start",d.FrequencyReferenceStart, ...
                "symbol_start",row(2),"num_symbols",row(3), ...
                "timing_offset_slots",row(4),"mapping_type",mapping(fields.time_resource_assignment+1), ...
                "tb_scaling_factor",scales(fields.tb_scaling+1), ...
                "direction","DL","grant_type","PDSCH", ...
                "configuration_epoch",d.ConfigurationEpoch);
        end
    end
end
