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
sixgr.system.assertSLSExecutingReservations(grants,cellIDs,reservations,absoluteSlot0,"UL");
end
