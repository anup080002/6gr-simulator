classdef TestExecutionLedger
    %TESTEXECUTIONLEDGER Pinned runtime proof for required MATLAB tests.
    methods (Static)
        function result=validate(input)
            required=["TestName","Executed","Passed","Skipped","Blocked"];
            if ~istable(input)||any(~ismember(required,string(input.Properties.VariableNames)))
                error("sixgr:validation:SchemaMissingColumn", ...
                    "Test execution ledger is missing mandatory columns.");
            end
            executed=localBool(input.Executed); passed=localBool(input.Passed);
            skipped=localBool(input.Skipped); blocked=localBool(input.Blocked);
            if any(~executed|~passed|skipped|blocked)
                error("sixgr:validation:RequiredTestSkipped", ...
                    "Every required MATLAB test must execute and pass.");
            end
            result=struct("RequiredTests",height(input), ...
                "Executed",sum(executed),"Passed",sum(passed), ...
                "SkippedRequired",sum(skipped),"BlockedRequired",sum(blocked), ...
                "Status","PASS");
        end
    end
end

function out=localBool(value)
if islogical(value), out=value; return; end
if isnumeric(value), out=logical(value); return; end
text=lower(string(value)); out=text=="true";
if any(~ismember(text,["true","false"]))
    error("sixgr:validation:SchemaWrongType","Test Boolean field is invalid.");
end
end
