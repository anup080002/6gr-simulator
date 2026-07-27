classdef PHRMappingR18
    %PHRMAPPINGR18 Exact PH and PCMAX quantizers from TS 38.133.
    methods (Static)
        function index=phIndex(valueDB)
            thresholds=[-32:-1 0:22 24 26 28 30 32 34 36 38];
            index=sum(double(valueDB)>=thresholds);
            index=min(max(index,0),63);
        end
        function index=pcmaxIndex(valueDBm)
            thresholds=-29:33;
            index=sum(double(valueDBm)>=thresholds);
            index=min(max(index,0),63);
        end
        function [lower,upper]=phRange(index)
            validateattributes(index,{'numeric'},{'scalar','integer','>=',0,'<=',63});
            thresholds=[-32:-1 0:22 24 26 28 30 32 34 36 38];
            if index==0, lower=-Inf; else, lower=thresholds(index); end
            if index==63, upper=Inf; else, upper=thresholds(index+1); end
        end
        function [lower,upper]=pcmaxRange(index)
            validateattributes(index,{'numeric'},{'scalar','integer','>=',0,'<=',63});
            thresholds=-29:33;
            if index==0, lower=-Inf; else, lower=thresholds(index); end
            if index==63, upper=Inf; else, upper=thresholds(index+1); end
        end
    end
end
