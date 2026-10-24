function ok=testSharedCSIRSPowerReference()
% Actual shared CSI-only production completion/report/append/drain/CSV.
% Reuse the original-owner fixture, not copied/extracted receiver code.
% One logical port mapped to four installed TX columns, two RX elements;
% no multiport nonlinear attribution, UCI delivery or standardized accuracy.
setup6GRSimToolkit('Verbose',false);
failures=strings(0,1);
for unit=["normalized_complex_baseband","sqrt_mW"]
    try
        assert(testCSIRSComponentIsolationEvidence(unit,true));
    catch cause
        failures(end+1)=unit+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'SHARED_CSIRS_POWER_REFERENCE_FAIL unit=%s %s\n',unit,getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(isempty(failures),'test:SharedCSIRSPowerReference', ...
    '%s',strjoin(failures,newline));
ok=true;
fprintf('SHARED_CSIRS_POWER_REFERENCE_PASS actual_original_owner_modes=2 standardized_accuracy=0 multiport_attribution=0\n');
end
