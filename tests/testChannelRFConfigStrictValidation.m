function testChannelRFConfigStrictValidation
bundle = channelRFStrictAnchorResult("Refresh", true);
v = sixgr.channel.validateChannelRFConfigStrict(bundle.Config);
assert(v.Ok, "Strict Channel/RF config should validate for the mini anchor.");

bad = bundle.Config;
bad.channel.model = "CDL";
bad.channel.delayProfile = "CDL";
vb = sixgr.channel.validateChannelRFConfigStrict(bad);
assert(~vb.Ok, "Bare CDL family must fail strict Channel/RF validation.");

sco = bundle.Config;
sco = sixgr.util.structSet(sco, "rf.sampleClockOffset.enable", true);
sco = sixgr.util.structSet(sco, "rf.sampleClockOffset.ppm", 25);
vs = sixgr.channel.validateChannelRFConfigStrict(sco);
assert(vs.Ok && logical(vs.SampleClockOffsetConfigured) && logical(vs.SampleClockOffsetSupported), ...
    "Configured sample-clock offset must validate because the ordered RF chain applies real SCO resampling.");
end
