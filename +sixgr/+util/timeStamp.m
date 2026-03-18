function s = timeStamp(t)
%TIMESTAMP Create a filesystem-friendly timestamp string (YYYYMMDD_HHMMSS).
%
%   s = sixgr.util.timeStamp()
%   s = sixgr.util.timeStamp(t) where t is a datetime

if nargin < 1 || isempty(t)
    t = datetime("now","TimeZone","local");
end

if ~isa(t,"datetime")
    error("sixgr:util:timeStamp:BadType","Input must be a datetime.");
end

s = string(datestr(t, "yyyymmdd_HHMMSS"));

end
