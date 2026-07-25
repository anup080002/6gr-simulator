function ok = testPDSCHHARQRejectsWrongTB()
%TESTPDSCHHARQREJECTSWRONGTB Reject identity, TBS, layout, epoch and RV changes.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
manager.process(PDSCHPhaseTestSupport.harqObservation());
base = PDSCHPhaseTestSupport.harqObservation("NewData", false, "RV", 2);
localAssert(@() manager.process(localSet(base, "TBIdentityDigest", "OTHER")), ...
    "sixgr:pdsch:HARQTBIdentityMismatch");
localAssert(@() manager.process(localSet(base, "TBS", 2048)), ...
    "sixgr:pdsch:HARQTBSMismatch");
localAssert(@() manager.process(localSet(base, "CodingPlanDigest", "OTHER")), ...
    "sixgr:pdsch:HARQCodingLayoutMismatch");
localAssert(@() manager.process(localSet(base, "ConfigurationEpoch", 8)), ...
    "sixgr:pdsch:HARQConfigurationEpochMismatch");
localAssert(@() manager.process(localSet(base, "RV", 4)), ...
    "sixgr:pdsch:RVOutOfRange");
fprintf("PDSCH HARQ incompatible retransmission negatives passed.\\n");
ok = true;
end

function value = localSet(value, field, replacement)
value.(field) = replacement;
end

function localAssert(fn, id)
try
    fn();
catch ME
    assert(string(ME.identifier) == string(id), ...
        "Expected %s, got %s.", id, ME.identifier);
    return;
end
error("testPDSCHHARQRejectsWrongTB:MissingError", "Expected %s.", id);
end
