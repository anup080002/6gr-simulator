function ok = testSystemDemandStallClock()
% Reproduce an access interval longer than the watchdog, without sleeping.
start = NaN;
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 208.2, false, false);
assert(isnan(start) && elapsed == 0);
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 213, true, false);
assert(start == 213 && elapsed == 0, 'First demand must not inherit access time.');
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 392, true, false);
assert(elapsed == 179 && elapsed < 180);
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 393, true, false);
assert(elapsed == 180, 'A genuine continuous stall must still reach the configured timeout.');
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 394, true, true);
assert(isnan(start) && elapsed == 0, 'Productive grants/service must reset the interval.');
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 400, true, false);
assert(start == 400 && elapsed == 0);
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 401, false, false);
assert(isnan(start) && elapsed == 0, 'Idle or inaccessible intervals must disarm demand timing.');
[start, elapsed] = sixgr.system.updateDemandStallClock(start, 1000, true, false);
assert(start == 1000 && elapsed == 0);
ok = true;
end
