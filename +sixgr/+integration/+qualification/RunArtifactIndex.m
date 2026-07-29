classdef RunArtifactIndex
    %RUNARTIFACTINDEX One recursive scan shared by qualification auditors.
    methods (Static)
        function index = build(root)
            root = string(root);
            listing = dir(fullfile(root, "**", "*"));
            listing = listing(~[listing.isdir]);
            if isempty(listing)
                paths = strings(0,1);
                names = strings(0,1);
            else
                paths = string(fullfile({listing.folder}, ...
                    {listing.name}))';
                names = string({listing.name})';
            end
            byName = containers.Map("KeyType","char","ValueType","any");
            for item = 1:numel(paths)
                key = char(names(item));
                if isKey(byName,key)
                    byName(key) = unique([string(byName(key));paths(item)]);
                else
                    byName(key) = paths(item);
                end
            end
            index = struct("Root",root,"Paths",paths,"Names",names, ...
                "ByName",byName);
        end

        function [path, uniquePath] = findUnique(index, name)
            key = char(string(name));
            if ~isKey(index.ByName,key)
                path = "";
                uniquePath = false;
                return;
            end
            paths = unique(string(index.ByName(key)));
            uniquePath = numel(paths) == 1;
            if uniquePath
                path = paths(1);
            else
                path = "";
            end
        end

        function paths = endingWith(index, suffix)
            mask = endsWith(lower(index.Names),lower(string(suffix)));
            paths = index.Paths(mask);
        end
    end
end
