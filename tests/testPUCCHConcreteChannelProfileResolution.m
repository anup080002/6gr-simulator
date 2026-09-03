function ok = testPUCCHConcreteChannelProfileResolution()
%TESTPUCCHCONCRETECHANNELPROFILERESOLUTION Guard PUCCH profile handoff.

cfg = struct();
cfg.channel.model = "CDL";
cfg.channel.cdlProfile = "CDL-C";
cfg.channel.fading = struct("model", "CDL", "profile", "CDL-C");
assert(sixgr.channel.resolveConcreteProfile(cfg) == "CDL-C", ...
    "PUCCH runtime handoff must resolve a concrete CDL-C profile.");

cfg.channel = struct("model", "TDL", "tdlProfile", "TDL-D", ...
    "fading", struct("model", "TDL", "profile", "TDL-D"));
assert(sixgr.channel.resolveConcreteProfile(cfg) == "TDL-D", ...
    "PUCCH runtime handoff must resolve a concrete TDL-D profile.");

cfg.channel = struct("model", "TR38901", "tdlProfile", "TDL-C", ...
    "fading", struct("model", "TDL", "profile", "TDL-C"));
assert(sixgr.channel.resolveConcreteProfile(cfg) == "TDL-C", ...
    "TR38901 large-scale propagation must hand the explicitly configured TDL-C profile to waveform receivers.");

cfg.channel = struct("model", "AWGN", "awgnOnly", true);
assert(sixgr.channel.resolveConcreteProfile(cfg) == "AWGN", ...
    "AWGN runtime handoff must remain explicit.");

cfg.channel = struct("model", "CDL", ...
    "fading", struct("model", "CDL", "profile", ""));
threw = false;
try
    sixgr.channel.resolveConcreteProfile(cfg);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:config:BadChannelProfile");
end
assert(threw, "A bare CDL family must fail instead of being manufactured into a profile.");

cfg.channel = struct("model", "TR38901", ...
    "fading", struct("model", "TDL", "profile", ""));
threw = false;
try
    sixgr.channel.resolveConcreteProfile(cfg);
catch ME
    threw = strcmp(string(ME.identifier), "sixgr:config:BadChannelProfile");
end
assert(threw, "TR38901 without an explicit waveform profile must fail closed.");
ok = true;
end
