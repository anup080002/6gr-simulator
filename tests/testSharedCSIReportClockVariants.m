function ok=testSharedCSIReportClockVariants()
% Actual shared PUCCH reception variants; component inputs remain explicit
% inside testSharedCSIReportClock, not integrated access/measurement truth.
cases={"FDD",false,false; "TDD",true,false; "FDD",true,false; "TDD",false,true};
failures={};
for k=1:size(cases,1)
    fprintf('SHARED_CSI_VARIANT_START mode=%s HARQ=%d stale=%d\n',cases{k,:});
    try
        assert(testSharedCSIReportClock(cases{k,:}));
    catch cause
        % Exercise every declared variant but retain every original failure.
        % The aggregate still fails; no failing case is skipped or downgraded.
        failures{end+1}=cause; %#ok<AGROW>
        diagnostic=sixgr.util.formatExceptionDiagnostic(cause);
        fprintf(2,'SHARED_CSI_VARIANT_FAIL case=%d\n%s\n',k,diagnostic);
    end
end
if ~isempty(failures)
    aggregate=MException('sixgr:tests:SharedCSIReportClockVariantsFailed', ...
        '%d of %d shared CSI variants failed.',numel(failures),size(cases,1));
    for k=1:numel(failures), aggregate=addCause(aggregate,failures{k}); end
    throw(aggregate);
end
ok=true;
disp('SHARED_CSI_REPORT_CLOCK_VARIANTS_PASS FDD, combined TDD/FDD and stale metadata.');
end
