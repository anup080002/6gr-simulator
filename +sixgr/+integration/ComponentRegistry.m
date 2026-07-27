classdef ComponentRegistry < handle
    %COMPONENTREGISTRY One dependency/version registry per run.
    properties (SetAccess=immutable)
        RunID (1,1) string
    end
    properties (Access=private)
        Entries (1,:) struct = struct("Component",{},"Class",{}, ...
            "ImplementationPath",{},"ImplementationSHA256",{})
    end
    methods
        function obj = ComponentRegistry(runID)
            obj.RunID = string(runID);
        end
        function register(obj,name,instance)
            name = string(name);
            if any(string({obj.Entries.Component}) == name)
                error("sixgr:integration:DuplicateClockService", ...
                    "Component '%s' is already registered.",name);
            end
            if ischar(instance) || (isstring(instance) && isscalar(instance))
                className = string(instance);
            else
                className = string(class(instance));
            end
            implementationPath = string(which(char(className)));
            if strlength(implementationPath) == 0
                implementationPath = "builtin_or_value";
                digest = sixgr.integration.IntegrationHash.data(className);
            else
                digest = sixgr.integration.IntegrationHash.file(implementationPath);
            end
            obj.Entries(end+1) = struct("Component",name, ...
                "Class",className,"ImplementationPath",implementationPath, ...
                "ImplementationSHA256",digest);
        end
        function value = get(obj,name)
            names = string({obj.Entries.Component});
            index = find(names == string(name),1);
            if isempty(index)
                error("sixgr:integration:MissingComponent", ...
                    "Component '%s' is not registered.",string(name));
            end
            value = obj.Entries(index);
        end
        function value = table(obj)
            if isempty(obj.Entries)
                value = table();
                return;
            end
            value = struct2table(obj.Entries,"AsArray",true);
            value.RunID = repmat(obj.RunID,height(value),1);
            value = movevars(value,"RunID","Before",1);
            value.Status = repmat("PASS",height(value),1);
        end
    end
end
