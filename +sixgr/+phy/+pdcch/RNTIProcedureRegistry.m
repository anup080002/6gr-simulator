classdef RNTIProcedureRegistry
    %RNTIPROCEDUREREGISTRY Release-18 RNTI/search-space/DCI ownership.

    methods (Static)
        function procedure = resolve(rntiType)
            rntiType = sixgr.phy.pdcch.normalizeRNTIType(rntiType);
            rows = sixgr.phy.pdcch.RNTIProcedureRegistry.catalog();
            idx = find(string({rows.RNTIType}) == rntiType, 1);
            if isempty(idx)
                error("sixgr:phy:pdcch:invalid_rnti_procedure", ...
                    "RNTI type %s has no installed Release-18 PDCCH procedure.", rntiType);
            end
            procedure = rows(idx);
        end

        function validate(rntiType, rntiValue, searchSpaceType, dciFormat)
            item = sixgr.phy.pdcch.RNTIProcedureRegistry.resolve(rntiType);
            searchSpaceType = upper(strrep(string(searchSpaceType), "-", "_"));
            dciFormat = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
            allowedSpace = any(ismember(searchSpaceType, string(item.AllowedSearchSpaces)));
            allowedFormat = any(dciFormat == string(item.AllowedDCIFormats));
            if ~(allowedSpace && allowedFormat)
                error("sixgr:phy:pdcch:invalid_rnti_procedure", ...
                    "%s cannot monitor DCI %s in search space %s.", ...
                    item.RNTIType, dciFormat, searchSpaceType);
            end
            rntiValue = double(rntiValue);
            if ~(isscalar(rntiValue) && isfinite(rntiValue) && rntiValue >= 0 && ...
                    rntiValue <= 65535 && rntiValue == fix(rntiValue))
                error("sixgr:phy:pdcch:invalid_rnti_procedure", ...
                    "%s value must be an unsigned 16-bit integer.", item.RNTIType);
            end
            if isfinite(item.FixedValue) && rntiValue ~= item.FixedValue
                error("sixgr:phy:pdcch:invalid_rnti_procedure", ...
                    "%s has fixed value 0x%04X, not 0x%04X.", ...
                    item.RNTIType, item.FixedValue, rntiValue);
            end
        end

        function rows = catalog()
            rows = [
                localRow("C-RNTI", NaN, ["USS","TYPE1","TYPE3"], ["0_0","0_1","1_0","1_1"], "connected_unicast", true)
                localRow("CS-RNTI", NaN, ["USS","TYPE1A","TYPE3"], ["0_0","0_1","1_0","1_1"], "configured_scheduling", true)
                localRow("MCS-C-RNTI", NaN, ["USS","TYPE3"], ["0_0","0_1","1_0","1_1"], "mcs_specific_unicast", true)
                localRow("TC-RNTI", NaN, ["CSS","TYPE1"], ["0_0","1_0"], "contention_resolution", true)
                localRow("SI-RNTI", 65535, ["CSS","TYPE0","TYPE0A"], ["1_0"], "system_information", true)
                localRow("P-RNTI", 65534, ["CSS","TYPE2"], ["1_0"], "paging", true)
                localRow("RA-RNTI", NaN, ["CSS","TYPE1"], ["1_0"], "random_access_response", true)
                localRow("MsgB-RNTI", NaN, ["CSS","TYPE1"], ["1_0"], "two_step_random_access_response", false)
                localRow("SP-CSI-RNTI", NaN, ["USS"], ["0_1"], "semi_persistent_csi", false)
                localRow("SFI-RNTI", NaN, ["TYPE3"], ["2_0"], "slot_format_indication", false)
                localRow("INT-RNTI", NaN, ["TYPE3"], ["2_1"], "preemption_indication", false)
                localRow("TPC-PUSCH-RNTI", NaN, ["TYPE3"], ["2_2"], "group_tpc_pusch", false)
                localRow("TPC-PUCCH-RNTI", NaN, ["TYPE3"], ["2_2"], "group_tpc_pucch", false)
                localRow("TPC-SRS-RNTI", NaN, ["TYPE3"], ["2_3"], "group_tpc_srs", false)
                localRow("CI-RNTI", NaN, ["TYPE3"], ["2_4"], "cancellation_indication", false)
                localRow("PS-RNTI", NaN, ["TYPE3"], ["2_6"], "power_saving", false)
                localRow("PEI-RNTI", NaN, ["TYPE2A"], ["2_7"], "paging_early_indication", false)
                localRow("G-RNTI", NaN, ["TYPE0B","TYPE3"], ["4_0","4_1","4_2"], "multicast_broadcast", false)
                localRow("G-CS-RNTI", NaN, ["TYPE3"], ["4_1","4_2"], "multicast_configured_scheduling", false)
                localRow("MCCH-RNTI", NaN, ["TYPE0B","TYPE3"], ["4_0"], "broadcast_mcch", false)
                localRow("SL-RNTI", NaN, ["USS"], ["3_0","3_1"], "sidelink_scheduling", false)
                localRow("NCR-RNTI", NaN, ["USS"], ["release_pinned"], "network_controlled_repeater", false)];
        end
    end
end

function row = localRow(type, fixedValue, spaces, formats, procedure, createsGrant)
row = struct("RNTIType", string(type), "FixedValue", double(fixedValue), ...
    "AllowedSearchSpaces", string(spaces), "AllowedDCIFormats", string(formats), ...
    "Procedure", string(procedure), "CreatesGrant", logical(createsGrant), ...
    "CRCPolynomial", "CRC24C");
end
