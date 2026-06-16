function testChannelRFConfigStrictValidation
bundle = channelRFStrictAnchorResult("Refresh", true);
v = sixgr.channel.validateChannelRFConfigStrict(bundle.Config);
assert(v.Ok, "Strict Channel/RF config should validate for the mini anchor.");

bad = bundle.Config;
bad.channel.model = "CDL";
bad.channel.delayProfile = "CDL";
vb = sixgr.channel.validateChannelRFConfigStrict(bad);
assert(~vb.Ok, "Bare CDL family must fail strict Channel/RF validation.");
end
