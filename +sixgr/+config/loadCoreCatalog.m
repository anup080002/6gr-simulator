function catalog = loadCoreCatalog()
%LOADCORECATALOG Load YAML-backed core config defaults and validation policy.

persistent cachedCatalog cachedRaw

catalogPath = localCatalogPath();
raw = fileread(catalogPath);
% A long-lived MATLAB/WebGUI session must not keep validating new YAML
% against a catalog loaded before an edit.  The file is small; compare its
% content on each call and only repeat parsing when the policy changed.
if ~isempty(cachedCatalog) && isequal(raw,cachedRaw)
    catalog = cachedCatalog;
    return;
end

try
    catalog = jsondecode(raw);
catch
    if exist("sixgr.lls6g.config.readConfigFile", "file") ~= 2
        error("sixgr:config:CoreCatalogReadFailed", ...
            "Unable to parse core config catalog '%s'.", catalogPath);
    end
    catalog = sixgr.lls6g.config.readConfigFile(catalogPath);
end

if ~(isstruct(catalog) && isscalar(catalog) && isfield(catalog, "parameters"))
    error("sixgr:config:CoreCatalogMalformed", ...
        "Core config catalog '%s' must decode to a scalar struct with a parameters section.", ...
        catalogPath);
end

cachedCatalog = catalog;
cachedRaw = raw;
end

function p = localCatalogPath()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
p = fullfile(root, "simulator", "configs", "schema", "core_parameter_catalog.yaml");
end
