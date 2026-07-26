classdef RFSpecificationProfile
%RFSPECIFICATIONPROFILE Immutable RF execution and claim boundary.
%   The baseband simulator exposes ideal, research, and test-method
%   emulation profiles. It never exposes an RF-device certification mode.

    methods(Static)
        function profile = resolve(profileId)
            token = lower(strtrim(string(profileId)));
            switch token
                case "ideal_phy_strict"
                    classId = "ideal_phy_strict";
                    claimClass = "IDEAL_PHY";
                    claimText = "Ideal baseband PHY execution";
                    specification = "6GR-RF-IDEAL";
                    version = "1.0.0";
                    emulationOnly = false;
                    tableRegistryId = "NOT_APPLICABLE";
                    tableStatus = "NOT_APPLICABLE";
                case "rf_impaired_research"
                    classId = "rf_impaired_research";
                    claimClass = "RESEARCH";
                    claimText = "RF-impaired baseband research execution";
                    specification = "6GR-RF-RESEARCH";
                    version = "1.0.0";
                    emulationOnly = false;
                    tableRegistryId = "NOT_APPLICABLE";
                    tableStatus = "NOT_APPLICABLE";
                case {"rf_conformance_emulation_bs_fr1", ...
                        "rf_conformance_emulation_ue_fr1", ...
                        "rf_conformance_emulation_fr2"}
                    classId = "rf_conformance_emulation";
                    claimClass = "EMULATION_ONLY";
                    claimText = "Pinned RF test-method emulation; not device conformance";
                    if contains(token, "_bs_")
                        tableRegistryId = "BS_FR1_CONDUCTED_V19_4";
                        specification = "3GPP TS 38.104 V19.4.0 / TS 38.141-1 V19.4.0";
                    elseif contains(token, "_fr2")
                        tableRegistryId = "UE_FR2_CONDUCTED_V19_2";
                        specification = "3GPP TS 38.101-2 V19.4.0 / TS 38.521-2 V19.2.0";
                    else
                        tableRegistryId = "UE_FR1_CONDUCTED_V19_4";
                        specification = "3GPP TS 38.101-1 V19.4.0 / TS 38.521-1 V19.4.0";
                    end
                    table = sixgr.rf.runtime.RFSpecificationTableRegistry. ...
                        resolve(tableRegistryId);
                    tableStatus = string(table.Status);
                    if tableStatus ~= "ENABLED"
                        error("RF:SpecificationTableUnavailable", ...
                            "RF emulation profile has no enabled exact specification table.");
                    end
                    version = string(table.RequirementVersion)+"+"+ ...
                        string(table.MethodVersion);
                    emulationOnly = true;
                case {"rf_device_conformance", ...
                        "unsupported_rf_device_conformance"}
                    error("RF:DeviceConformanceClaimForbidden", ...
                        "A baseband link-level simulator cannot claim RF-device conformance or certification.");
                otherwise
                    error("RF:UnsupportedProfile", ...
                        "Unsupported RF specification profile '%s'.", token);
            end
            baseline=sixgr.rf.runtime.RFSpecificationTableRegistry.baseline();
            toolchain=sixgr.rf.runtime.RFSpecificationProfile.toolchain();
            profile = struct( ...
                "ProfileID", token, ...
                "ExecutionClass", classId, ...
                "ClaimClass", claimClass, ...
                "ClaimText", claimText, ...
                "Specification", specification, ...
                "SpecificationVersion", version, ...
                "SpecificationBaseline", baseline, ...
                "TableRegistryID", tableRegistryId, ...
                "TableStatus", tableStatus, ...
                "MATLABRelease", toolchain.MATLABRelease, ...
                "FiveGToolboxVersion", toolchain.FiveGToolboxVersion, ...
                "ReferencePlaneRequired", true, ...
                "EmulationOnly", logical(emulationOnly), ...
                "Executable", true);
        end

        function ids = executableProfileIDs()
            ids = ["ideal_phy_strict"; "rf_impaired_research"; ...
                "rf_conformance_emulation_bs_fr1"; ...
                "rf_conformance_emulation_ue_fr1"; ...
                "rf_conformance_emulation_fr2"];
        end
    end

    methods(Static,Access=private)
        function result=toolchain()
            release=string(version("-release"));
            toolboxVersion="UNAVAILABLE";
            products=ver;
            index=find(strcmp({products.Name},"5G Toolbox"),1);
            if ~isempty(index)
                toolboxVersion=string(products(index).Version);
            end
            result=struct("MATLABRelease",release, ...
                "FiveGToolboxVersion",toolboxVersion);
        end
    end
end
