classdef RSLAUtil
    %RSLAUTIL Strict helpers shared by the bounded Release-18 RSLA profile.

    methods (Static)
        function value = readStrings(path)
            if exist(path,"file")~=2
                error("RSLA:MissingVectorInput","Required vector input is absent: %s.",path);
            end
            opts = detectImportOptions(path,"Delimiter",",","TextType","string", ...
                "VariableNamingRule","preserve");
            opts = setvartype(opts,opts.VariableNames,"string");
            value = readtable(path,opts);
            names = string(value.Properties.VariableNames);
            for index = 1:numel(names)
                if iscell(value.(names(index))) || ischar(value.(names(index))) || ...
                        iscategorical(value.(names(index)))
                    value.(names(index)) = string(value.(names(index)));
                end
            end
        end

        function value = text(row,name,defaultValue)
            if nargin<3, defaultValue = ""; end
            value = string(defaultValue);
            if istable(row) && ismember(string(name),string(row.Properties.VariableNames))
                raw = row.(char(name));
                if ~isempty(raw), value = string(raw(1)); end
            elseif isstruct(row) && isfield(row,char(name))
                value = string(row.(char(name)));
            end
            if ismissing(value), value = string(defaultValue); end
        end

        function value = number(row,name,defaultValue)
            if nargin<3, defaultValue = NaN; end
            raw = sixgr.phy.rsla.RSLAUtil.text(row,name,"");
            value = str2double(raw);
            if ~isscalar(value) || ~isfinite(value)
                if isnumeric(defaultValue), value = double(defaultValue); end
            end
        end

        function value = truth(row,name,defaultValue)
            if nargin<3, defaultValue = false; end
            raw = upper(strtrim(sixgr.phy.rsla.RSLAUtil.text(row,name,"")));
            if strlength(raw)==0
                value = logical(defaultValue);
            else
                value = ismember(raw,["TRUE","1","YES","PASS","EXECUTE"]);
            end
        end

        function values = numberList(raw)
            token = strtrim(string(raw));
            if strlength(token)==0
                values = zeros(1,0);
                return;
            end
            pieces = split(token,[";",",","|"," "]);
            pieces = pieces(strlength(pieces)>0);
            values = str2double(pieces).';
            if any(~isfinite(values))
                error("RSLA:InvalidNumericList","Invalid numeric-list token: %s.",token);
            end
        end

        function value = hash(input)
            if istable(input)
                payload = jsonencode(table2struct(input));
            elseif isstruct(input) || iscell(input)
                payload = jsonencode(input);
            elseif isnumeric(input) || islogical(input)
                payload = jsonencode(double(input));
            else
                payload = char(join(string(input(:)),"|"));
            end
            value = string(sixgr.util.sha256Hex( ...
                uint8(unicode2native(char(payload),"UTF-8"))));
        end

        function value = fileHash(path)
            fid = fopen(path,"rb");
            if fid<0
                error("RSLA:MissingArtifact","Cannot open artifact: %s.",path);
            end
            cleanup = onCleanup(@() fclose(fid));
            value = string(sixgr.util.sha256Hex(fread(fid,inf,"*uint8")));
        end

        function value = status(flag)
            if flag, value = "PASS"; else, value = "FAIL"; end
        end

        function value = bool(flag)
            if flag, value = "true"; else, value = "false"; end
        end

        function value = contractTable(contract,fileName,nRows)
            row = contract(string(contract.FileName)==string(fileName),:);
            if height(row)~=1
                error("RSLA:MissingArtifactContract", ...
                    "No unique artifact contract exists for %s.",fileName);
            end
            columns = split(string(row.RequiredColumns),";");
            value = array2table(strings(nRows,numel(columns)));
            value.Properties.DimensionNames = ...
                {'RSLAObservations','RSLAVariables'};
            value.Properties.VariableNames = cellstr(columns);
        end

        function row = appendLike(value)
            names = string(value.Properties.VariableNames);
            row = array2table(strings(1,numel(names)));
            row.Properties.DimensionNames = ...
                {'RSLAObservations','RSLAVariables'};
            row.Properties.VariableNames = cellstr(names);
        end

        function validateFiniteScalar(value,errorID,label,minimum,maximum)
            if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
                    value>=minimum && value<=maximum)
                error(errorID,"%s must be a finite scalar in [%g,%g].", ...
                    label,minimum,maximum);
            end
        end

        function [low,high] = wilson(errors,trials,confidence)
            if trials<1 || errors<0 || errors>trials
                error("RSLA:InvalidStatisticalInput", ...
                    "Wilson interval requires 0 <= errors <= trials and trials >= 1.");
            end
            alpha = 1-confidence;
            z = -sqrt(2)*erfcinv(2*(1-alpha/2));
            rate = errors/trials;
            denominator = 1+z^2/trials;
            center = (rate+z^2/(2*trials))/denominator;
            half = z*sqrt(rate*(1-rate)/trials+z^2/(4*trials^2))/denominator;
            low = max(0,center-half);
            high = min(1,center+half);
        end
    end
end
