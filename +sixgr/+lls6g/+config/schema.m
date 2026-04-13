function out = schema(kind)
%SCHEMA Schema definition for 6G PHY LLS scenario and matrix configs.

if nargin < 1 || strlength(string(kind)) == 0
    kind = "scenario";
end
kind = lower(string(kind));

catalog = sixgr.lls6g.config.loadParameterCatalog(kind);
out = localBuildSchemaFromCatalog(catalog, kind);
end

function s = localBuildSchemaFromCatalog(catalog, kind)
s = struct();
sectionNames = string(fieldnames(catalog.sections));
if isfield(catalog, "top_level_order")
    orderedTop = string(catalog.top_level_order(:));
else
    orderedTop = sectionNames;
end
s.AllowedTopLevel = orderedTop(:);
requiredTop = strings(0,1);

s.RequiredBySection = struct();
s.AllowedBySection = struct();
for i = 1:numel(sectionNames)
    sec = sectionNames(i);
    secRule = catalog.sections.(sec);
    paramNames = string(fieldnames(secRule.parameters));
    s.AllowedBySection.(sec) = paramNames(:);
    reqFields = strings(0,1);
    for j = 1:numel(paramNames)
        rule = secRule.parameters.(paramNames(j));
        if localIsRequired(rule)
            reqFields(end+1,1) = paramNames(j); %#ok<AGROW>
        end
    end
    s.RequiredBySection.(sec) = reqFields;
    if localIsRequired(secRule)
        requiredTop(end+1,1) = sec; %#ok<AGROW>
    end
end
s.RequiredTopLevel = requiredTop;

s.NestedAllowed = struct();
if isfield(catalog, "nested_sections")
    nestedNames = string(fieldnames(catalog.nested_sections));
    for i = 1:numel(nestedNames)
        nestedKey = nestedNames(i);
        nestedRule = catalog.nested_sections.(nestedKey);
        s.NestedAllowed.(nestedKey) = string(fieldnames(nestedRule.parameters));
    end
end

if kind == "matrix" && ~isfield(s.AllowedBySection, "scenarios")
    s.AllowedBySection.scenarios = string.empty(0,1);
end
end

function tf = localIsRequired(rule)
tf = isfield(rule, "required") && logical(rule.required);
end
