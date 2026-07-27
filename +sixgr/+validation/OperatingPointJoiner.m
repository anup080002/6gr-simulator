classdef OperatingPointJoiner
    %OPERATINGPOINTJOINER Exact one-to-one complete-key joins.
    methods (Static)
        function result = join(dut,reference,varargin)
            parser = inputParser;
            parser.addParameter("Strict",false,@(x)islogical(x)&&isscalar(x));
            parser.parse(varargin{:});
            dutKeys = localKeys(dut);
            referenceKeys = localKeys(reference);
            duplicateDUT = localDuplicates(dutKeys);
            duplicateReference = localDuplicates(referenceKeys);
            allKeys = unique([dutKeys;referenceKeys],"stable");
            rows = repmat(struct("PointKey","","DUTRowCount",0, ...
                "ReferenceRowCount",0,"JoinStatus","","MissingSide","", ...
                "Status",""),numel(allKeys),1);
            for index = 1:numel(allKeys)
                key = allKeys(index);
                nd = nnz(dutKeys==key);
                nr = nnz(referenceKeys==key);
                if nd > 1
                    joinStatus = "DUPLICATE_DUT";
                elseif nr > 1
                    joinStatus = "DUPLICATE_REFERENCE";
                elseif nd == 1 && nr == 1
                    joinStatus = "MATCH";
                elseif nd == 0
                    joinStatus = "MISSING_DUT";
                else
                    joinStatus = "MISSING_REFERENCE";
                end
                missingSide = "";
                if nd == 0, missingSide = "DUT"; end
                if nr == 0, missingSide = "REFERENCE"; end
                rows(index) = struct("PointKey",key, ...
                    "DUTRowCount",nd,"ReferenceRowCount",nr, ...
                    "JoinStatus",joinStatus,"MissingSide",missingSide, ...
                    "Status",localStatus(joinStatus=="MATCH"));
            end
            report = struct2table(rows,"AsArray",true);
            result = struct("Report",report, ...
                "MatchedCount",nnz(report.JoinStatus=="MATCH"), ...
                "MissingDUTCount",nnz(report.JoinStatus=="MISSING_DUT"), ...
                "MissingReferenceCount", ...
                    nnz(report.JoinStatus=="MISSING_REFERENCE"), ...
                "ExtraDUTCount",nnz(report.JoinStatus=="MISSING_REFERENCE"), ...
                "ExtraReferenceCount",nnz(report.JoinStatus=="MISSING_DUT"), ...
                "DuplicateDUTCount",numel(duplicateDUT), ...
                "DuplicateReferenceCount",numel(duplicateReference), ...
                "Passed",all(report.JoinStatus=="MATCH"));
            if parser.Results.Strict && ~result.Passed
                error("sixgr:validation:OperatingPointJoinIncomplete", ...
                    "Exact operating-point join failed: missing DUT=%d, " + ...
                    "missing reference=%d, duplicate DUT=%d, duplicate reference=%d.", ...
                    result.MissingDUTCount,result.MissingReferenceCount, ...
                    result.DuplicateDUTCount,result.DuplicateReferenceCount);
            end
        end
    end
end

function keys = localKeys(input)
if ~istable(input)
    error("sixgr:validation:SchemaWrongType", ...
        "Operating-point joins require tables.");
end
keys = strings(height(input),1);
for index = 1:height(input)
    keys(index) = sixgr.validation.OperatingPointKey.canonical(input(index,:));
end
end
function values = localDuplicates(keys)
[uniqueKeys,~,group] = unique(keys);
counts = accumarray(group,1);
values = uniqueKeys(counts>1);
end
function out = localStatus(condition)
if condition, out = "PASS"; else, out = "FAIL"; end
end
