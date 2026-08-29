function ok = testCoupledTruthFeedbackDelayAuthority()
%TESTCOUPLEDTRUTHFEEDBACKDELAYAUTHORITY No hidden CSI-delay clamp exists.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, ...
    "phy.linkAdaptation.feedbackDelaySlots", 1);
cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 1);
assert(sixgr.truth.CoupledTruthRuntime.resolveConfiguredCSIFeedbackSlots(cfg) == 1, ...
    "Coupled truth must honor the exact YAML-derived one-slot CSI delay.");

cfg = sixgr.util.structSet(cfg, ...
    "phy.linkAdaptation.feedbackDelaySlots", 7);
cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 7);
assert(sixgr.truth.CoupledTruthRuntime.resolveConfiguredCSIFeedbackSlots(cfg) == 7, ...
    "Coupled truth must not replace an explicit CSI delay with a constant.");

cfg = sixgr.util.structSet(cfg, "phy.csi.feedbackDelaySlots", 6);
localAssertError(@()sixgr.truth.CoupledTruthRuntime.resolveConfiguredCSIFeedbackSlots(cfg), ...
    "sixgr:link:FeedbackDelayAuthorityMismatch");
ok = true;
end

function localAssertError(fcn, expectedIdentifier)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(strcmp(ME.identifier, expectedIdentifier), ...
        "Expected %s, received %s.", expectedIdentifier, ME.identifier);
end
assert(threw, "Expected error %s was not raised.", expectedIdentifier);
end
