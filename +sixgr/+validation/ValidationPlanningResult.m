classdef ValidationPlanningResult
    %VALIDATIONPLANNINGRESULT Immutable resolved validation profile.
    properties (SetAccess=private)
        Data struct
    end
    methods
        function obj = ValidationPlanningResult(data)
            if ~(isstruct(data) && isscalar(data))
                error("sixgr:validation:InvalidProfile", ...
                    "A validation planning result requires one scalar struct.");
            end
            obj.Data = data;
        end
        function requireExecutable(obj)
            if ~logical(obj.Data.Supported)
                error("sixgr:validation:UnsupportedProfile", ...
                    "Validation profile %s is not executable.",obj.Data.ProfileID);
            end
        end
        function out = toStruct(obj)
            out = obj.Data;
        end
    end
end
