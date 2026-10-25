function [absolute, within] = validateSRSOccasionCoordinates(period,offset,absolute,within)
% One physical periodic SRS resource has one period/offset. Optional lists
% may select a subset of those occasions, not introduce additional phases.
[period,offset]=sixgr.phy.srs.validateSRSPeriodOffset(period,offset);
absolute=localCoordinates(absolute,0,flintmax,'sixgr:phy:srs:InvalidExplicitSlotSet');
within=localCoordinates(within,1,period,'sixgr:phy:srs:InvalidSlotWithinPeriod');
assert(all(mod(absolute-offset,period)==0) && all(mod(within-1-offset,period)==0), ...
    'sixgr:phy:srs:ScheduleAuthorityMismatch', ...
    'SRS slot lists must agree with the single native resource period/offset; configure separate resources for different offsets.');
end

function values=localCoordinates(values,first,last,id)
if isempty(values), values=zeros(1,0); return; end
assert(isnumeric(values) && ~islogical(values) && isreal(values) && isvector(values) && ...
    all(isfinite(values(:))) && all(values(:)>=first & values(:)<=last & values(:)==fix(values(:))), ...
    id,'SRS slot coordinates must be exact integers within the declared clock domain.');
values=unique(double(values(:).'),'stable');
end
