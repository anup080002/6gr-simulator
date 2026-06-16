function resourceSet = buildSRSResourceSetStrict(srsCfg)
%BUILDSRSRESOURCESETSTRICT Build carrier and nrSRSConfig from strict config.

carrier = nrCarrierConfig;
carrier.NCellID = max(0, round(double(srsCfg.NCellID)));
carrier.NSizeGrid = max(1, round(double(srsCfg.NSizeGrid)));
carrier.NStartGrid = max(0, round(double(srsCfg.NStartGrid)));
carrier.SubcarrierSpacing = double(srsCfg.SubcarrierSpacingKHz);
carrier.CyclicPrefix = char(string(srsCfg.CyclicPrefix));
carrier.NSlot = double(srsCfg.ExpectedSlotSet(1));

srs = sixgr.phy.srs.buildSRSResourceStrict(srsCfg, carrier);
resourceSet = struct("Carrier", carrier, "SRS", srs);
end
