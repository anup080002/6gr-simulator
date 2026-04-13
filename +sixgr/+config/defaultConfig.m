function cfg = defaultConfig()
% sixgr.config.defaultConfig
% Build the canonical simulator default config from the YAML-backed catalog.

catalog = sixgr.config.loadCoreCatalog();
cfg = struct();
cfg = localApplyCatalogDefaults(cfg, catalog.parameters, "");
end

function cfg = localApplyCatalogDefaults(cfg, node, prefix)
fields = fieldnames(node);
for i = 1:numel(fields)
    name = fields{i};
    child = node.(name);
    path = localJoinPath(prefix, name);
    if localIsCatalogLeaf(child)
        if isfield(child, "default") || isfield(child, "default_kind")
            cfg = sixgr.util.structSet(cfg, path, localCatalogDefaultValue(child));
        end
    elseif isstruct(child) && isscalar(child)
        cfg = localApplyCatalogDefaults(cfg, child, path);
    end
end
end

function value = localCatalogDefaultValue(entry)
kind = lower(string(sixgr.util.structGet(entry, "default_kind", "")));
valueType = lower(string(sixgr.util.structGet(entry, "value_type", "any")));

switch kind
    case ""
        value = sixgr.util.structGet(entry, "default", []);
    case "dynamic_created_utc"
        value = char(datetime("now", "TimeZone", "UTC", ...
            "Format", "yyyy-MM-dd'T'HH:mm:ss'Z'"));
    case "empty_table"
        value = table();
    case "empty_struct_array"
        value = struct([]);
    otherwise
        error("sixgr:config:UnknownCatalogDefaultKind", ...
            "Unsupported core config catalog default_kind '%s'.", kind);
end

switch valueType
    case {"string","string_or_empty"}
        value = char(string(value));
    case "boolean"
        value = logical(value);
    case {"integer","number"}
        value = double(value);
    case {"integer_vector","number_vector"}
        value = double(value);
    case "string_list"
        if isempty(value)
            value = {};
        else
            value = cellstr(string(value(:).'));
        end
    case "struct_array"
        if isempty(value) && ~isstruct(value)
            value = struct([]);
        end
    otherwise
        % Leave tables, arrays, and free-form values untouched.
end
end

function tf = localIsCatalogLeaf(node)
tf = isstruct(node) && isscalar(node) && ...
    (isfield(node, "value_type") || isfield(node, "default") || isfield(node, "default_kind"));
end

function out = localJoinPath(prefix, name)
if strlength(string(prefix)) == 0
    out = char(string(name));
else
    out = char(string(prefix) + "." + string(name));
end
end
