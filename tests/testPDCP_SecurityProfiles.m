function ok = testPDCP_SecurityProfiles()
%TESTPDCP_SECURITYPROFILES Verify PDCP security profile guards and modes.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();

% Non-strict simulation profile remains usable.
cfgSim = cfg;
cfgSim.run.strictMode = false;
cfgSim.l2.pdcp.ciphering.enable = true;
cfgSim.l2.pdcp.integrity.enable = true;
cfgSim.l2.pdcp.ciphering.algorithm = "SIM_XOR_SHA256";
cfgSim.l2.pdcp.integrity.algorithm = "SIM_SHA256_4B";
p1 = sixgr.l2.pdcp.PDCP(cfgSim, "Direction", "DL", "DRBID", 1); %#ok<NASGU>

% Strict mode must reject simulation security algorithms.
cfgStrictBad = cfg;
cfgStrictBad.run.strictMode = true;
cfgStrictBad.l2.pdcp.ciphering.enable = true;
cfgStrictBad.l2.pdcp.integrity.enable = true;
cfgStrictBad.l2.pdcp.ciphering.algorithm = "SIM_XOR_SHA256";
cfgStrictBad.l2.pdcp.integrity.algorithm = "SIM_SHA256_4B";
threw = false;
try
    sixgr.l2.pdcp.PDCP(cfgStrictBad, "Direction", "DL", "DRBID", 1); %#ok<NASGU>
catch
    threw = true;
end
assert(threw, "Strict mode should reject simulation PDCP algorithms.");

% Strict mode with 3GPP-null algorithms should pass.
cfgStrictNull = cfg;
cfgStrictNull.run.strictMode = true;
cfgStrictNull.l2.pdcp.ciphering.enable = true;
cfgStrictNull.l2.pdcp.integrity.enable = true;
cfgStrictNull.l2.pdcp.ciphering.algorithm = "NEA0";
cfgStrictNull.l2.pdcp.integrity.algorithm = "NIA0";
p2 = sixgr.l2.pdcp.PDCP(cfgStrictNull, "Direction", "DL", "DRBID", 1);
[pdu, ~] = p2.tx(uint8([1 2 3 4 5]));
assert(~isempty(pdu), "PDCP NEA0/NIA0 profile should produce a PDU.");

ok = true;
end
