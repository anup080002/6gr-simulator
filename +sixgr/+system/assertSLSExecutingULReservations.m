function assertSLSExecutingULReservations(grants,cellIDs,reservations,absoluteSlot0)
%ASSERTSLSEXECUTINGULRESERVATIONS Recheck frozen K2 grants at execution.
% An obligation may have become known after the grant was issued. Never
% silently resize a frozen TB, drop its reservation, or count a collided TB
% as transmitted. The scheduler must resolve the conflict before execution.
arguments
    grants struct
    cellIDs double
    reservations cell
    absoluteSlot0 (1,1) double {mustBeInteger,mustBeNonnegative}
end
assert(numel(grants)==numel(cellIDs), ...
    'sixgr:system:ReservationGrantOwnership','Each executing UL grant needs its serving cell.');
for k=1:numel(grants)
    g=grants(k); c=cellIDs(k);
    assert(isfinite(c) && c==fix(c) && c>=1 && c<=numel(reservations), ...
        'sixgr:system:ReservationGrantOwnership','Executing UL cell is outside the reservation population.');
    assert(isfield(g,'ScheduledAbsoluteSlot') && isequal(double(g.ScheduledAbsoluteSlot),absoluteSlot0), ...
        'sixgr:system:ReservationExecutionClock','Execute only at the frozen grant data slot.');
    r=reservations{c};
    assert(r.CellID==c && r.DataAbsoluteSlot0==absoluteSlot0 && r.AsOfAbsoluteSlot0==absoluteSlot0, ...
        'sixgr:system:ReservationExecutionClock','Execution needs the current cell/slot reservation snapshot.');
    sixgr.system.assertSLSGrantsRespectReservations(g,r);
end
end
