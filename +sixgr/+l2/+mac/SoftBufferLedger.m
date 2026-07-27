classdef SoftBufferLedger < handle
    %SOFTBUFFERLEDGER Position-aware, provenance-complete HARQ combining.
    properties (SetAccess=private)
        Contributions (1,:) cell = {}
    end
    methods
        function append(obj,contribution)
            if ~isa(contribution,"sixgr.l2.mac.SoftBufferContribution")
                error("sixgr:mac:SoftBufferProvenanceMismatch", ...
                    "Expected SoftBufferContribution.");
            end
            if ~isempty(obj.Contributions)
                first=obj.Contributions{1}.AttemptKey;
                key=contribution.AttemptKey;
                first.TBKey.assertSame(key.TBKey);
                if first.CodingLayoutSHA256~=key.CodingLayoutSHA256 || ...
                        first.RateMatchSHA256~=key.RateMatchSHA256
                    error("sixgr:mac:SoftBufferProvenanceMismatch", ...
                        "Coding/rate layout differs from the existing ledger.");
                end
            end
            obj.Contributions{end+1}=contribution;
        end
        function [positions,llr,weight]=combine(obj)
            if isempty(obj.Contributions)
                positions=zeros(0,1); llr=zeros(0,1); weight=zeros(0,1); return;
            end
            allPositions=cell2mat(cellfun(@(x)x.MotherCodePositions, ...
                obj.Contributions,"UniformOutput",false).');
            allLLR=cell2mat(cellfun(@(x)x.LLR,obj.Contributions, ...
                "UniformOutput",false).');
            [positions,~,groups]=unique(allPositions);
            llr=accumarray(groups,allLLR,[],@sum);
            weight=accumarray(groups,1,[],@sum);
        end
        function flush(obj), obj.Contributions={}; end
    end
end
