function ok = testControlChannelStubGuard()
%TESTCONTROLCHANNELSTUBGUARD Verify nontransparent PDCCH stub modes are opt-in only.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.ctrl6gr = struct( ...
    "enable", true, ...
    "DiversityMode", "nontransparent_stub", ...
    "EnableTransmitDiversity", true, ...
    "AllowStubModes", false);

localAssertThrows(@() sixgr.ctrl.ControlChannelConfig(cfg), ...
    "sixgr:ctrl:ControlChannelConfig:StubModeDisabled");

cfg.ctrl6gr.AllowStubModes = true;
ctrlCfg = sixgr.ctrl.ControlChannelConfig(cfg);
assert(strcmpi(char(string(ctrlCfg.PDCCHImplementationStatus)), "stub_mode_requested_not_decodable") && ...
    contains(lower(char(string(ctrlCfg.PDCCHImplementationBlocker))), "future_study_hook"), ...
    "Control-channel config must preserve explicit stub-mode implementation status when the user opts in.");

ok = true;
end

function localAssertThrows(fh, expectedId)
caught = false;
try
    fh();
catch ME
    caught = strcmp(ME.identifier, expectedId);
end
assert(caught, "Expected error '%s'.", expectedId);
end
