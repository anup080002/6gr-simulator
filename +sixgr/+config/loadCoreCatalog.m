function catalog = loadCoreCatalog()
%LOADCORECATALOG Load YAML-backed core config defaults and validation policy.

persistent cachedCatalog

if ~isempty(cachedCatalog)
    catalog = cachedCatalog;
    return;
end

catalogPath = localCatalogPath();
raw = fileread(catalogPath);

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
end

function p = localCatalogPath()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(here));
p = fullfile(root, "simulator", "configs", "schema", "core_parameter_catalog.yaml");
end
