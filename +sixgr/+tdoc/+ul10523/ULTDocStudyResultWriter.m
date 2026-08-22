classdef ULTDocStudyResultWriter
    %RESULTWRITER Provenance-enriched, read-back-checked CSV writer.

    methods (Static)
        function write(path, value, context)
            if ~istable(value) || height(value) == 0
                error("sixgr:tdoc:ul10523:EmptyArtifact", ...
                    "Refusing to write empty primary evidence artifact %s.", path);
            end
            value = sixgr.tdoc.ul10523.ULTDocStudyResultWriter.withContext(value, context);
            parent = fileparts(path);
            if ~isfolder(parent), mkdir(parent); end
            sixgr.util.csvWriteTable(path, value, "PreserveSchema", true);
            observed = readcell(path, "Delimiter", ",");
            observedRows=size(observed,1)-1; observedCols=size(observed,2);
            if observedRows ~= height(value) || observedCols ~= width(value)
                error("sixgr:tdoc:ul10523:CSVReadbackMismatch", ...
                    "CSV readback shape changed for %s (expected %dx%d; read %dx%d).", ...
                    path, height(value), width(value), observedRows, observedCols);
            end
        end

        function value = withContext(value, context)
            names = string(value.Properties.VariableNames);
            fields = {"RunId", string(context.RunId); ...
                "ConfigSHA256", string(context.ConfigSHA256); ...
                "GitCommit", string(context.GitCommit)};
            for idx = size(fields,1):-1:1
                if ~ismember(fields{idx,1}, names)
                    scalarValue=string(fields{idx,2});
                    if ~isscalar(scalarValue)
                        error("sixgr:tdoc:ul10523:NonScalarProvenance", ...
                            "Context field %s must be scalar.",fields{idx,1});
                    end
                    value = addvars(value, repmat(scalarValue,height(value),1), ...
                        'Before', 1, 'NewVariableNames', char(fields{idx,1}));
                end
            end
        end
    end
end
