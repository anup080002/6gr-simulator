classdef MultiSourceValueEvaluator
    %MULTISOURCEVALUEEVALUATOR Evaluate each source independently.
    methods (Static)
        function [results,trace,resolutionTrace,adapterResults] = ...
                evaluate(contract,resolver,runID,applyAdapters)
            if nargin<4
                applyAdapters = true;
            end
            n = height(contract);
            resultRows = repmat(localResultRow(),n,1);
            traceRows = repmat(localTraceRow(),n,1);
            resolutionRows = repmat(localResolutionRow(),0,1);
            adapterResults = sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.emptyResults();
            for index = 1:n
                resultRows(index).RunID = string(runID);
                resultRows(index).CheckID = string(contract.CheckID(index));
                resultRows(index).Domain = string(contract.Domain(index));
                resultRows(index).SubcaseID = string(contract.SubcaseID(index));
                resultRows(index).Required = localTruth(contract.Required(index));
                resultRows(index).SourceCSV = string(contract.SourceCSV(index));
                resultRows(index).ObservedExpression = string( ...
                    contract.ObservedExpression(index));
                resultRows(index).ExpectedExpression = string( ...
                    contract.ExpectedExpression(index));
                resultRows(index).Comparator = string(contract.Comparator(index));
                resultRows(index).Tolerance = string(contract.Tolerance(index));
                resultRows(index).Units = string(contract.Units(index));
                resultRows(index).FailureCode = string( ...
                    contract.FailureCode(index));

                traceRows(index).CheckID = resultRows(index).CheckID;
                traceRows(index).SubcaseID = resultRows(index).SubcaseID;
                traceRows(index).Comparator = resultRows(index).Comparator;
                traceRows(index).Tolerance = resultRows(index).Tolerance;
                traceRows(index).EvaluatorVersion = ...
                    "phase18-typed-value-engine-v1";
                try
                    observedAST = sixgr.integration.qualification. ...
                        ValueExpressionParser.parse( ...
                        resultRows(index).ObservedExpression);
                    expectedAST = sixgr.integration.qualification. ...
                        ValueExpressionParser.parse( ...
                        resultRows(index).ExpectedExpression);
                    traceRows(index).ParsedExpression = ...
                        observedAST.Kind + ":" + observedAST.Text;
                    sourceNames = strip(split( ...
                        resultRows(index).SourceCSV,"|"));
                    sourceNames = sourceNames(strlength(sourceNames)>0);
                    if isempty(sourceNames)
                        error("FULLSTACK:ValueSourceMissing", ...
                            "No source artifacts are declared.");
                    end
                    observedParts = cell(numel(sourceNames),1);
                    expectedParts = cell(numel(sourceNames),1);
                    sourcePassed = false(numel(sourceNames),1);
                    paths = strings(numel(sourceNames),1);
                    artifactIDs = strings(numel(sourceNames),1);
                    sourceHashes = strings(numel(sourceNames),1);
                    for sourceIndex = 1:numel(sourceNames)
                        resolution = sixgr.integration.qualification. ...
                            ArtifactResolver.resolve( ...
                            resolver,sourceNames(sourceIndex));
                        resolutionRows(end+1,1) = localResolutionRowFrom( ... %#ok<AGROW>
                            resultRows(index).CheckID,sourceIndex,resolution);
                        if ~resolution.Resolved
                            code = string(resolution.FailureCode);
                            if strlength(code)==0
                                code = "FULLSTACK:ValueSourceMissing";
                            end
                            error(char(code),"%s",resolution.Details);
                        end
                        loaded = sixgr.integration.qualification. ...
                            QualificationTableLoader.load( ...
                            resolver,sourceNames(sourceIndex), ...
                            [observedAST.Text;expectedAST.Text], ...
                            applyAdapters);
                        if ~isempty(loaded.AdapterResults)
                            adapterResults = [adapterResults; ...
                                loaded.AdapterResults]; %#ok<AGROW>
                        end
                        if observedAST.Kind=="IDENTIFIER" && ...
                                ~ismember(observedAST.Column,string( ...
                                loaded.Table.Properties.VariableNames))
                            error("FULLSTACK:ValueColumnMissing", ...
                                "Required observed column '%s' is absent.", ...
                                observedAST.Column);
                        end
                        observedParts{sourceIndex} = ...
                            sixgr.integration.qualification. ...
                            ValueExpressionEvaluator.evaluate( ...
                            observedAST,loaded.Table);
                        expectedParts{sourceIndex} = ...
                            sixgr.integration.qualification. ...
                            ValueExpressionEvaluator.evaluate( ...
                            expectedAST,loaded.Table);
                        comparison = sixgr.integration.qualification. ...
                            ValueComparator.compare( ...
                            observedParts{sourceIndex}, ...
                            expectedParts{sourceIndex}, ...
                            resultRows(index).Comparator, ...
                            resultRows(index).Tolerance);
                        sourcePassed(sourceIndex) = comparison.Passed;
                        paths(sourceIndex) = resolution.RelativePath;
                        artifactIDs(sourceIndex) = resolution.ArtifactID;
                        sourceHashes(sourceIndex) = resolution.ActualSHA256;
                    end
                    passed = all(sourcePassed);
                    resultRows(index).ObservedValue = localJoinDisplays( ...
                        observedParts);
                    resultRows(index).ExpectedValue = localJoinDisplays( ...
                        expectedParts);
                    resultRows(index).Status = localStatus(passed);
                    resultRows(index).EvidenceArtifactID = ...
                        strjoin(artifactIDs,"|");
                    resultRows(index).Details = ...
                        localEvaluationDetails(passed,numel(sourceNames));

                    traceRows(index).ResolvedSourcePaths = strjoin(paths,"|");
                    traceRows(index).ResolvedSourceArtifactIDs = ...
                        strjoin(artifactIDs,"|");
                    traceRows(index).ResolvedSourceSHA256 = ...
                        strjoin(sourceHashes,"|");
                    traceRows(index).ObservedType = localJoinTypes( ...
                        observedParts);
                    traceRows(index).ObservedScalarOrDigest = ...
                        localJoinDisplays(observedParts);
                    traceRows(index).ExpectedType = localJoinTypes( ...
                        expectedParts);
                    traceRows(index).ExpectedScalarOrDigest = ...
                        localJoinDisplays(expectedParts);
                    traceRows(index).ComparatorResult = passed;
                    traceRows(index).Status = localStatus(passed);
                    if ~passed
                        traceRows(index).FailureCode = ...
                            resultRows(index).FailureCode;
                        traceRows(index).Details = ...
                            "Typed comparator rejected one or more independently evaluated source scalars.";
                    else
                        traceRows(index).Details = ...
                            "Typed expression and comparator completed.";
                    end
                catch ME
                    resultRows(index).Status = "FAIL";
                    resultRows(index).Details = string(ME.identifier) + ...
                        ": " + string(ME.message);
                    traceRows(index).Status = "FAIL";
                    traceRows(index).FailureCode = string(ME.identifier);
                    traceRows(index).Details = string(ME.message);
                end
            end
            results = struct2table(resultRows,"AsArray",true);
            trace = struct2table(traceRows,"AsArray",true);
            resolutionTrace = struct2table(resolutionRows,"AsArray",true);
            if ~isempty(adapterResults)
                adapterResults = unique(adapterResults,"rows","stable");
            end
        end
    end
end

function row = localResultRow()
row = struct("RunID","","CheckID","","Domain","","SubcaseID","", ...
    "Required",false,"SourceCSV","","ObservedExpression","", ...
    "ObservedValue","","ExpectedExpression","","ExpectedValue","", ...
    "Comparator","","Tolerance","","Units","","Status","FAIL", ...
    "FailureCode","","EvidenceArtifactID","","Details","");
end

function row = localTraceRow()
row = struct("CheckID","","SubcaseID","","ParsedExpression","", ...
    "ResolvedSourcePaths","","ResolvedSourceArtifactIDs","", ...
    "ResolvedSourceSHA256","","ObservedType","", ...
    "ObservedScalarOrDigest","","ExpectedType","", ...
    "ExpectedScalarOrDigest","","Comparator","","Tolerance","", ...
    "ComparatorResult",false,"Status","FAIL","FailureCode","", ...
    "EvaluatorVersion","","Details","");
end

function row = localResolutionRow()
row = struct("CheckID","","SourceOrdinal",0,"RequestedIdentity","", ...
    "Resolved",false,"ArtifactID","","FileName","","RelativePath","", ...
    "RegisteredSHA256","","ActualSHA256","","HashValid",false, ...
    "ResolutionMethod","","AdapterVersion","","FailureCode","", ...
    "Details","");
end

function row = localResolutionRowFrom(checkID,ordinal,resolution)
row = localResolutionRow();
row.CheckID = string(checkID);
row.SourceOrdinal = ordinal;
fields = setdiff(string(fieldnames(row)),["CheckID","SourceOrdinal"]);
for field = reshape(fields,1,[])
    if isfield(resolution,char(field))
        row.(char(field)) = resolution.(char(field));
    end
end
end

function text = localJoinDisplays(parts)
values = strings(numel(parts),1);
for index = 1:numel(parts)
    values(index) = string(parts{index}.Display);
end
text = strjoin(values,"|");
end

function text = localJoinTypes(parts)
values = strings(numel(parts),1);
for index = 1:numel(parts)
    values(index) = string(parts{index}.Type);
end
text = strjoin(values,"|");
end

function text = localEvaluationDetails(passed,count)
if passed
    text = sprintf( ...
        "Typed evaluation passed for %d independently loaded source(s).", ...
        count);
else
    text = sprintf( ...
        "Typed evaluation failed for at least one of %d independent source(s).", ...
        count);
end
end

function tf = localTruth(value)
tf = ismember(lower(strtrim(string(value))),["true","1","yes"]);
end

function value = localStatus(tf)
if tf
    value = "PASS";
else
    value = "FAIL";
end
end
