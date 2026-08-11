function ok = testPDSCHPTRSSequenceIndependent()
%TESTPDSCHPTRSSEQUENCEINDEPENDENT Validate nonzero-port PT-RS sequences.
%
% The coupled two-user MU-MIMO path assigns the second rank-one user
% logical DM-RS/PT-RS port 1.  This regression ensures the independent
% sequence oracle validates that exact port without applying DM-RS OCC a
% second time.

for port = 0:1
    fixture = StrictPDSCHChainFixture.create(2, ...
        "NPRB",8, "UsePTRS",true, "PTRSPortSet",port);
    generated = sixgr.pdsch.PDSCHReferenceSignalGenerator.generate( ...
        fixture.Assignment,fixture.ResourcePlan,fixture.Carrier, ...
        fixture.ReferenceConfig);
    assert(generated.PTRSSequenceNMSE <= 1e-24, ...
        "PT-RS independent sequence mismatch for associated port %d.",port);
    layer = port + 1;
    assert(~isempty(generated.PTRSSymbolsPerPort{layer}), ...
        "Associated PT-RS port %d produced no symbols.",port);
end
ok = true;
end
