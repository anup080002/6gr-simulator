classdef ValueExpressionParser
    %VALUEEXPRESSIONPARSER Parse the allowlisted Phase-18 scalar grammar.
    methods (Static)
        function ast = parse(expression)
            text = strtrim(string(expression));
            if ismissing(text) || strlength(text)==0
                error("FULLSTACK:ValueExpressionMissing", ...
                    "A required value expression is empty.");
            end
            ast = struct("Text",text,"Kind","","Column","", ...
                "Columns",strings(0,1),"Selector","","Value",[]);
            numeric = str2double(text);
            if isfinite(numeric)
                ast.Kind = "NUMERIC_LITERAL";
                ast.Value = numeric;
                return;
            end
            if ismember(lower(text),["true","false"])
                ast.Kind = "LOGICAL_LITERAL";
                ast.Value = lower(text)=="true";
                return;
            end
            token = regexp(char(text), ...
                '^all\(isfinite\(([A-Za-z][A-Za-z0-9_]*)\)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "ALL_ISFINITE";
                ast.Column = string(token{1});
                return;
            end
            token = regexp(char(text), ...
                '^all\(([A-Za-z][A-Za-z0-9_]*)>=([-+0-9.eE]+)\s*&\s*\1<=([-+0-9.eE]+)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "ALL_RANGE";
                ast.Column = string(token{1});
                ast.Value = [str2double(token{2}),str2double(token{3})];
                return;
            end
            token = regexp(char(text), ...
                '^(all|any|max|min|sum|count)\(([A-Za-z][A-Za-z0-9_]*)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = upper(string(token{1}));
                ast.Column = string(token{2});
                return;
            end
            token = regexp(char(text), ...
                '^max\(abs\(([A-Za-z][A-Za-z0-9_]*)-([A-Za-z][A-Za-z0-9_]*)(/c)?\)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "MAX_ABS_DIFFERENCE";
                ast.Columns = [string(token{1});string(token{2})];
                if numel(token)>=3 && strcmp(token{3},"/c")
                    ast.Selector = "SECOND_DIVIDED_BY_C";
                end
                return;
            end
            token = regexp(char(text), ...
                '^max\(abs\(([A-Za-z][A-Za-z0-9_]*)\)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "MAX_ABS";
                ast.Column = string(token{1});
                return;
            end
            token = regexp(char(text), ...
                '^abs\(([A-Za-z][A-Za-z0-9_]*)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "ABS";
                ast.Column = string(token{1});
                return;
            end
            token = regexp(char(text), ...
                '^([A-Za-z][A-Za-z0-9_]*)\((highestSNR|lowestSNR|first|last|latestTime|earliestTime)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "SELECT";
                ast.Column = string(token{1});
                ast.Selector = string(token{2});
                return;
            end
            token = regexp(char(text), ...
                '^([A-Za-z][A-Za-z0-9_]*)\(where\(([A-Za-z][A-Za-z0-9_]*)\s*==\s*([^\)]+)\)\)$', ...
                'tokens','once');
            if ~isempty(token)
                ast.Kind = "SELECT_WHERE";
                ast.Column = string(token{1});
                ast.Columns = string(token{2});
                ast.Selector = strtrim(string(token{3}));
                return;
            end
            if contains(text,"+")
                terms = strip(split(text,"+"));
                if all(~cellfun(@isempty,regexp(cellstr(terms), ...
                        '^[A-Za-z][A-Za-z0-9_]*$','once')))
                    ast.Kind = "SUM_COLUMNS";
                    ast.Columns = terms;
                    return;
                end
            end
            if ~isempty(regexp(char(text), ...
                    '^[A-Za-z][A-Za-z0-9_]*$','once'))
                ast.Kind = "IDENTIFIER";
                ast.Column = text;
                return;
            end
            error("FULLSTACK:UnsupportedValueExpression", ...
                "Unsupported qualification expression '%s'.",text);
        end

        function columns = referencedColumns(ast)
            columns = strings(0,1);
            if strlength(string(ast.Column))>0
                columns(end+1,1) = string(ast.Column); %#ok<AGROW>
            end
            if ~isempty(ast.Columns)
                columns = [columns;string(ast.Columns(:))]; %#ok<AGROW>
            end
            columns = unique(columns(strlength(columns)>0),"stable");
        end
    end
end
