function assertSLSExecutingReservations(grants,cellIDs,reservations,absoluteSlot0,direction)
%ASSERTSLSEXECUTINGRESERVATIONS Recheck frozen K0/K2 allocations at execution.
% Late obligations must not resize a frozen TB or silently release resources.
arguments
    grants struct
    cellIDs double
    reservations cell
    absoluteSlot0 (1,1) double {mustBeInteger,mustBeNonnegative}
    direction (1,1) string {mustBeMember(direction,["DL","UL"])}
end
assert(numel(grants)==numel(cellIDs), ...
    'sixgr:system:ReservationGrantOwnership','Each executing grant needs its serving cell.');
for k=1:numel(grants)
    g=grants(k); c=cellIDs(k);
    assert(isfinite(c) && c==fix(c) && c>=1 && c<=numel(reservations), ...
        'sixgr:system:ReservationGrantOwnership','Executing cell is outside the reservation population.');
    assert(isfield(g,'Direction') && string(g.Direction)==direction, ...
        'sixgr:system:ReservationGrantDirection','Executing grant direction must match the reservation query.');
    assert(isfield(g,'ScheduledAbsoluteSlot') && isequal(double(g.ScheduledAbsoluteSlot),absoluteSlot0), ...
        'sixgr:system:ReservationExecutionClock','Execute only at the frozen grant data slot.');
    r=reservations{c};
    assert(r.CellID==c && r.DataAbsoluteSlot0==absoluteSlot0 && r.AsOfAbsoluteSlot0==absoluteSlot0, ...
        'sixgr:system:ReservationExecutionClock','Execution needs the current cell/slot reservation snapshot.');
    sixgr.system.assertSLSGrantsRespectReservations(g,r);
end
end
