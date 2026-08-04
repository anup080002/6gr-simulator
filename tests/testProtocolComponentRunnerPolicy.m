function tests = testProtocolComponentRunnerPolicy
%TESTPROTOCOLCOMPONENTRUNNERPOLICY Guard package-visible YAML runner policy.
tests = functiontests(localfunctions);
end

function testRequiresBothProtocolAndComponentCampaign(testCase)
cfg = struct();
cfg.protocol = struct( ...
    "enabled", true, ...
    "component_validation", struct("enabled", true));

verifyTrue(testCase, ...
    sixgr.lls6g.runners.shouldRunProtocolComponentEvidence(cfg));

cfg.protocol.enabled = false;
verifyFalse(testCase, ...
    sixgr.lls6g.runners.shouldRunProtocolComponentEvidence(cfg));

cfg.protocol.enabled = true;
cfg.protocol.component_validation.enabled = false;
verifyFalse(testCase, ...
    sixgr.lls6g.runners.shouldRunProtocolComponentEvidence(cfg));
end

function testMissingConfigurationFailsClosed(testCase)
verifyFalse(testCase, ...
    sixgr.lls6g.runners.shouldRunProtocolComponentEvidence(struct()));

cfg = struct("protocol", struct("enabled", true));
verifyFalse(testCase, ...
    sixgr.lls6g.runners.shouldRunProtocolComponentEvidence(cfg));
end
