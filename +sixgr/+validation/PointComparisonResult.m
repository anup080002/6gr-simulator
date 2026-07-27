classdef PointComparisonResult
    %POINTCOMPARISONRESULT Immutable confidence-aware point comparison.
    properties (SetAccess=private)
        Data struct
    end
    methods
        function obj = PointComparisonResult(data)
            obj.Data = data;
        end
        function out = toStruct(obj)
            out = obj.Data;
        end
    end
end
