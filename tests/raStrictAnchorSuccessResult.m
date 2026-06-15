function res = raStrictAnchorSuccessResult()
%RASTRICTANCHORSUCCESSRESULT Shared strict-success RA fixture for tests.

persistent cached
if isempty(cached)
    cached = sixgr.phy.ra.runFourStepRA(raStrictAnchorConfig(), ...
        "RunId", "test_ra_success_fixture", "WriteArtifacts", false);
end
res = cached;
end
