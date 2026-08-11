function catalog = loadParameterCatalog(kind)
%LOADPARAMETERCATALOG Load the YAML-backed 6G config parameter catalog.

if nargin < 1 || strlength(string(kind)) == 0
    kind = "scenario";
end
kind = lower(string(kind));

persistent scenarioCatalog matrixCatalog

switch kind
    case "scenario"
        if isempty(scenarioCatalog)
            scenarioCatalog = localLoadMergedCatalog("scenario");
        end
        catalog = scenarioCatalog;
    case "matrix"
        if isempty(matrixCatalog)
            matrixCatalog = localLoadMergedCatalog("matrix");
        end
        catalog = matrixCatalog;
    otherwise
        error("sixgr:lls6g:config:UnknownCatalogKind", ...
            "Unsupported parameter catalog kind '%s'.", string(kind));
end
end

function catalog = localLoadMergedCatalog(kind)
base = sixgr.lls6g.config.readConfigFile(localCatalogPath(kind));
overlayPaths = localCatalogOverlayPaths(kind);
if isempty(overlayPaths)
    catalog = base;
    return;
end
catalog = base;
for i = 1:numel(overlayPaths)
    overlayPath = overlayPaths(i);
    if exist(char(overlayPath), "file") ~= 2
        continue;
    end
    overlay = sixgr.lls6g.config.readConfigFile(overlayPath);
    catalog = localMergeCatalogOverlay(catalog, overlay);
end
end

function merged = localMergeCatalogOverlay(baseCatalog, overlayCatalog)
merged = sixgr.util.mergeStruct(baseCatalog, overlayCatalog);
if isfield(baseCatalog, "top_level_order") || isfield(overlayCatalog, "top_level_order")
    baseTop = string(sixgr.util.structGet(baseCatalog, "top_level_order", strings(0,1)));
    overlayTop = string(sixgr.util.structGet(overlayCatalog, "top_level_order", strings(0,1)));
    merged.top_level_order = cellstr(union(baseTop(:), overlayTop(:), "stable"));
end
end

function p = localCatalogPath(kind)
root = localRepoRoot();
switch kind
    case "scenario"
        p = fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog.yaml");
    case "matrix"
        p = fullfile(root, "simulator", "configs", "schema", "matrix_parameter_catalog.yaml");
    otherwise
        error("sixgr:lls6g:config:UnknownCatalogKind", ...
            "Unsupported parameter catalog kind '%s'.", string(kind));
end
end

function paths = localCatalogOverlayPaths(kind)
root = localRepoRoot();
switch kind
    case "scenario"
        paths = [ ...
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_01.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_02.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_03.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_04.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_05.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_06.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_07.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_09.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_12.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_13.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_16.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_18.yaml"))
            string(fullfile(root, "simulator", "configs", "schema", "scenario_parameter_catalog_extension_19.yaml"))
            ];
    case "matrix"
        paths = strings(0,1);
    otherwise
        paths = strings(0,1);
end
end

function out = localRepoRoot()
here = fileparts(mfilename("fullpath"));
out = fileparts(fileparts(fileparts(here)));
end
