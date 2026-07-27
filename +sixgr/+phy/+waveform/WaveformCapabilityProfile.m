classdef WaveformCapabilityProfile
    %WAVEFORMCAPABILITYPROFILE YAML-backed executable capability planner.

    methods (Static)
        function result = plan(profileID,feature)
            profile = sixgr.phy.waveform.WaveformSpecificationProfile.resolve(profileID);
            feature = lower(strtrim(string(feature)));
            catalog = sixgr.phy.waveform.WaveformCapabilityProfile.catalog();
            key = matlab.lang.makeValidName(char(profile.ProfileID));
            if ~isfield(catalog.profiles,key)
                error("WAVEFORM:UnsupportedProfile", ...
                    "No capability catalog exists for '%s'.",profile.ProfileID);
            end
            row = catalog.profiles.(key);
            executable = string(row.execute_features);
            if ismember(feature,executable)
                evidence = "executed_bounded_study";
                if profile.NormativeClaimAllowed
                    evidence = "executed_rel19_normative_profile";
                end
                result = sixgr.phy.waveform.WaveformPlanningResult( ...
                    profile.ProfileID,feature,"EXECUTE","", ...
                    profile.NormativeClaimAllowed,evidence);
                return;
            end
            researchUnsupported = string(sixgr.util.structGet( ...
                row,"unsupported_research_features",strings(0,1)));
            errorID = "WAVEFORM:UnsupportedProfile";
            if ismember(feature,researchUnsupported)
                errorID = "WAVEFORM:UnsupportedResearchCandidate";
            end
            result = sixgr.phy.waveform.WaveformPlanningResult( ...
                profile.ProfileID,feature,"REJECT",errorID,false, ...
                "rejected_before_waveform");
        end

        function catalog = catalog()
            persistent value
            if isempty(value)
                here = fileparts(mfilename("fullpath"));
                root = fileparts(fileparts(fileparts(here)));
                path = fullfile(root,"simulator","configs","waveforms", ...
                    "phase13_waveform_profiles.yaml");
                value = sixgr.lls6g.config.readConfigFile(path);
            end
            catalog = value;
        end
    end
end
