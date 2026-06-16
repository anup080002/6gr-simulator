function ok = testSRSAperiodicTriggerValidation()
setup6GRSimToolkit("Verbose", false);
cfg = srsStrictAnchorResult().Config;
cfg.ResourceType = "aperiodic";
cfg.DCITriggerReferenceId = "dci_trigger_ue1_slot0";
valid = sixgr.phy.srs.validateSRSAperiodicTrigger(cfg);
assert(logical(valid.TriggerValid), "Aperiodic SRS with decoded DCI trigger reference must validate.");
cfg.DCITriggerReferenceId = "";
invalid = sixgr.phy.srs.validateSRSAperiodicTrigger(cfg);
assert(~logical(invalid.TriggerValid) && contains(string(invalid.FailureReason), "missing_decoded_dci"), ...
    "Aperiodic SRS without decoded DCI trigger reference must fail.");
ok = true;
end
