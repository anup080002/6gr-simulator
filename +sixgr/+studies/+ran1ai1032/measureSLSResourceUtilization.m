function out = measureSLSResourceUtilization(grants, opportunities, direction, firstTTI)
%MEASURESLSRESOURCEUTILIZATION Compatibility entrypoint for AI 10.3.2.
% General SLS owns the resource-union definition; study callers retain their
% historical error identifiers without duplicating the measurement math.
try
    out = sixgr.system.measureResourceUtilization(grants,opportunities,direction,firstTTI);
catch ME
    prefix = "sixgr:system:";
    id = string(ME.identifier);
    if startsWith(id,prefix)
        mapped = "sixgr:ran1ai1032:" + extractAfter(id,strlength(prefix));
        error(char(mapped),'%s',ME.message);
    end
    rethrow(ME);
end
end
