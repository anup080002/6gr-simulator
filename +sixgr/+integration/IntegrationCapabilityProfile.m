classdef IntegrationCapabilityProfile
    %INTEGRATIONCAPABILITYPROFILE YAML-backed mode/profile planner.
    methods (Static)
        function result = plan(mode,profile,subprofile,traceProfile)
            mode = sixgr.integration.RunMode.resolve(mode);
            profile = sixgr.integration.RadioProfile.resolve(profile);
            subprofile = lower(strtrim(string(subprofile)));
            traceProfile = upper(strtrim(string(traceProfile)));
            catalog = sixgr.integration.IntegrationCapabilityProfile.catalog();
            modeRow = catalog.run_modes.(char(mode));
            allowed = string(modeRow.allowed_subprofiles);
            if ~ismember(subprofile,allowed)
                error("sixgr:integration:RunModeConflict", ...
                    "Subprofile '%s' is not enabled for mode %s.", ...
                    subprofile,mode);
            end
            if ~isfield(catalog.trace_profiles,char(traceProfile))
                error("sixgr:integration:RunModeConflict", ...
                    "Unknown trace profile '%s'.",traceProfile);
            end
            profileRow = catalog.radio_profiles.( ...
                matlab.lang.makeValidName(char(profile)));
            result = sixgr.integration.IntegrationPlanningResult( ...
                mode,profile,subprofile,string(modeRow.run_class), ...
                string(modeRow.environment_adapter), ...
                logical(profileRow.normative), ...
                string(profileRow.research_class),traceProfile);
        end
        function value = catalog()
            persistent catalogValue
            if isempty(catalogValue)
                here = fileparts(mfilename("fullpath"));
                root = fileparts(fileparts(here));
                path = fullfile(root,"simulator","configs","integration", ...
                    "integration_profiles.yaml");
                catalogValue = sixgr.lls6g.config.readConfigFile(path);
            end
            value = catalogValue;
        end
    end
end
