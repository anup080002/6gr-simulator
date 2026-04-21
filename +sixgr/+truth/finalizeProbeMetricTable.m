function T = finalizeProbeMetricTable(T)
%FINALIZEPROBEMETRICTABLE Backfill textual probe value fields truthfully.

if ~(istable(T) && ~isempty(T))
    if ~istable(T)
        T = table();
    end
    return;
end

names = string(T.Properties.VariableNames);
hasValue = ismember("Value", names);
hasText = ismember("TextValue", names);
if hasValue && hasText
    values = double(T.Value);
    textVals = string(T.TextValue);
    mask = strlength(strtrim(textVals)) == 0 & isfinite(values);
    if any(mask)
        textVals(mask) = compose("%.12g", values(mask));
        T.TextValue = textVals;
    end
end

if ismember("Availability", names)
    avail = string(T.Availability);
    blankAvail = strlength(strtrim(avail)) == 0;
    if any(blankAvail)
        if hasValue
            avail(blankAvail & isfinite(double(T.Value))) = "available";
            avail(blankAvail & ~isfinite(double(T.Value))) = "not_available";
        else
            avail(blankAvail) = "available";
        end
        T.Availability = avail;
    end
end
end
