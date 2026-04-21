function stamp = utcNowISO8601()
%UTCNOWISO8601 Return the current UTC time as an ISO-8601 string.
% Keep this helper simple and version-tolerant across MATLAB releases.

dt = datetime("now", "TimeZone", "UTC");
dt.Format = "yyyy-MM-dd HH:mm:ss";
stamp = replace(string(dt), " ", "T") + "Z";
end
