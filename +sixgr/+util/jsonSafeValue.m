function out = jsonSafeValue(value)
%JSONSAFEVALUE Shared wire representation for files and embedded JSON fields.
% Keep the established jsonWrite complex_array_split contract. Receiver
% calculations retain numeric complex arrays; only serialization uses this.
if isa(value, "function_handle")
    out = struct("json_type", "function_handle", "text", func2str(value));
    return;
end
if isnumeric(value) && ~isreal(value)
    out = struct("json_type", "complex_array_split", ...
        "size", double(size(value)), "real", real(value), "imag", imag(value));
    return;
end
if istable(value)
    out = sixgr.util.jsonSafeValue(table2struct(value));
    return;
end
if iscell(value)
    out = value;
    for i = 1:numel(value)
        out{i} = sixgr.util.jsonSafeValue(value{i});
    end
    return;
end
if isstruct(value)
    out = value;
    fields = fieldnames(value);
    for idx = 1:numel(value)
        for f = 1:numel(fields)
            out(idx).(fields{f}) = sixgr.util.jsonSafeValue(value(idx).(fields{f}));
        end
    end
    return;
end
out = value;
end
