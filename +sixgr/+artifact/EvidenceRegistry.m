classdef EvidenceRegistry < handle
    %EVIDENCEREGISTRY In-memory production evidence for artifact publishing.
    %
    % Tables and renderers are registered explicitly by the subsystem that
    % executed them.  Files from an old run are intentionally not accepted as
    % evidence, which prevents stale CSV/PNG data from being republished.

    properties (Access = private)
        Tables
        TableProvenance
        Renderers
        RendererProvenance
    end

    methods
        function obj = EvidenceRegistry()
            obj.Tables = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.TableProvenance = containers.Map('KeyType', 'char', 'ValueType', 'char');
            obj.Renderers = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.RendererProvenance = containers.Map('KeyType', 'char', 'ValueType', 'char');
        end

        function registerTable(obj, domain, profile, fileName, value, provenance)
            arguments
                obj (1,1) sixgr.artifact.EvidenceRegistry
                domain {mustBeTextScalar}
                profile {mustBeTextScalar}
                fileName {mustBeTextScalar}
                value table
                provenance {mustBeTextScalar}
            end
            key = char(sixgr.artifact.ContractCatalog.evidenceKey( ...
                domain, profile, "CSV", fileName));
            localAssertNew(obj.Tables, key, "table");
            provenance = strtrim(char(string(provenance)));
            if isempty(provenance)
                error("sixgr:artifact:MissingEvidenceProvenance", ...
                    "Production table '%s' must identify its runtime producer.", key);
            end
            obj.Tables(key) = value;
            obj.TableProvenance(key) = provenance;
        end

        function registerRenderer(obj, domain, profile, fileName, renderer, provenance)
            arguments
                obj (1,1) sixgr.artifact.EvidenceRegistry
                domain {mustBeTextScalar}
                profile {mustBeTextScalar}
                fileName {mustBeTextScalar}
                renderer (1,1) function_handle
                provenance {mustBeTextScalar}
            end
            key = char(sixgr.artifact.ContractCatalog.evidenceKey( ...
                domain, profile, "PNG", fileName));
            localAssertNew(obj.Renderers, key, "renderer");
            provenance = strtrim(char(string(provenance)));
            if isempty(provenance)
                error("sixgr:artifact:MissingRendererProvenance", ...
                    "PNG renderer '%s' must identify its production implementation.", key);
            end
            obj.Renderers(key) = renderer;
            obj.RendererProvenance(key) = provenance;
        end

        function [found, value, provenance] = resolveTable(obj, domain, profile, fileName)
            key = char(sixgr.artifact.ContractCatalog.evidenceKey( ...
                domain, profile, "CSV", fileName));
            found = isKey(obj.Tables, key);
            if found
                value = obj.Tables(key);
                provenance = string(obj.TableProvenance(key));
            else
                value = table();
                provenance = "";
            end
        end

        function [found, renderer, provenance] = resolveRenderer(obj, domain, profile, fileName)
            key = char(sixgr.artifact.ContractCatalog.evidenceKey( ...
                domain, profile, "PNG", fileName));
            found = isKey(obj.Renderers, key);
            if found
                renderer = obj.Renderers(key);
                provenance = string(obj.RendererProvenance(key));
            else
                renderer = [];
                provenance = "";
            end
        end
    end
end

function localAssertNew(map, key, kind)
if isKey(map, key)
    error("sixgr:artifact:DuplicateEvidenceRegistration", ...
        "Production %s evidence '%s' was registered more than once.", kind, key);
end
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:artifact:TextScalarRequired", ...
        "Artifact registry identifiers must be text scalars.");
end
end
