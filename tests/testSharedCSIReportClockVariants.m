function ok=testSharedCSIReportClockVariants()
% Actual shared PUCCH reception variants; component inputs remain explicit
% inside testSharedCSIReportClock, not integrated access/measurement truth.
assert(testSharedCSIReportClock("FDD",false,false));
assert(testSharedCSIReportClock("TDD",true,false));
assert(testSharedCSIReportClock("FDD",true,false));
assert(testSharedCSIReportClock("TDD",false,true));
ok=true;
disp('SHARED_CSI_REPORT_CLOCK_VARIANTS_PASS FDD, combined TDD/FDD and stale metadata.');
end
