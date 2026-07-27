classdef EvidenceProvenanceGraph
    %EVIDENCEPROVENANCEGRAPH Validated evidence nodes and directed edges.
    properties (SetAccess=private)
        Nodes table
        Edges table
    end
    methods
        function obj=EvidenceProvenanceGraph(nodes,edges)
            if nargin<1, nodes=table(); end
            if nargin<2, edges=table(); end
            if ~istable(nodes)||~istable(edges)
                error("sixgr:validation:SchemaWrongType", ...
                    "Evidence nodes and edges must be tables.");
            end
            if ~isempty(nodes) && ismember("NodeID",string(nodes.Properties.VariableNames)) && ...
                    numel(unique(string(nodes.NodeID)))~=height(nodes)
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "Evidence NodeID values must be unique.");
            end
            obj.Nodes=nodes; obj.Edges=edges;
        end
        function out=roots(obj,nodeID)
            out=strings(0,1);
            if isempty(obj.Nodes), return; end
            row=find(string(obj.Nodes.NodeID)==string(nodeID),1);
            if isempty(row), error("sixgr:validation:OperatingPointMissing", ...
                    "Evidence node %s was not found.",string(nodeID)); end
            if ismember("RootID",string(obj.Nodes.Properties.VariableNames))
                out=string(obj.Nodes.RootID(row));
            end
        end
    end
end
