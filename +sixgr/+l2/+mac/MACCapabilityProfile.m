classdef MACCapabilityProfile
    %MACCAPABILITYPROFILE Explicit planning support/rejection.
    methods (Static)
        function result=resolve(profileID)
            profileID=string(profileID);
            supported=["nr_rel18_dl_harq_strict","nr_rel18_ul_harq_strict", ...
                "nr_rel18_qos_scheduler_strict","nr_rel18_bsr_phr_sr_strict", ...
                "nr_rel18_persistent_grant_strict","nr_rel18_ca_scheduler_strict", ...
                "nr_rel18_timing_advance_strict"];
            if ismember(profileID,supported)
                result=struct("Supported",true,"PlanningRejected",false, ...
                    "StateChanged",false,"Reason","supported_bounded_rel18_profile");
            elseif profileID=="unsupported_extension"
                result=struct("Supported",false,"PlanningRejected",true, ...
                    "StateChanged",false,"Reason","unsupported_extension");
            else
                error("sixgr:mac:UnknownCapabilityProfile", ...
                    "Unknown MAC capability profile %s.",profileID);
            end
        end
    end
end
