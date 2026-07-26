classdef DCIFieldDefinition
    %DCIFIELDDEFINITION One release-pinned contextual DCI field.

    properties (SetAccess = private)
        Name
        Width
        ValueMin
        ValueMax
        SemanticSource
        ReleaseClause
        BitOrder
        Generated
    end

    methods
        function obj = DCIFieldDefinition(name, width, valueMin, valueMax, ...
                semanticSource, releaseClause, generated)
            arguments
                name (1,1) string
                width (1,1) double
                valueMin (1,1) double = 0
                valueMax (1,1) double = NaN
                semanticSource (1,1) string = ""
                releaseClause (1,1) string = ""
                generated (1,1) logical = false
            end
            if ~(isfinite(width) && width >= 0 && width == fix(width))
                error("sixgr:phy:pdcch:dci_size_alignment_failure", ...
                    "Field %s has invalid bit width %g.", name, width);
            end
            if isnan(valueMax)
                if width == 0
                    valueMax = 0;
                else
                    valueMax = 2^width - 1;
                end
            end
            obj.Name = name;
            obj.Width = width;
            obj.ValueMin = valueMin;
            obj.ValueMax = valueMax;
            obj.SemanticSource = semanticSource;
            obj.ReleaseClause = releaseClause;
            obj.BitOrder = "MSB_FIRST";
            obj.Generated = generated;
        end
    end
end
