classdef ValidationSpecificationProfile
    %VALIDATIONSPECIFICATIONPROFILE Public profile-resolution facade.
    methods (Static)
        function result = resolve(profileID)
            result = sixgr.validation.ValidationCapabilityProfile.plan(profileID);
            result.requireExecutable();
        end
    end
end
