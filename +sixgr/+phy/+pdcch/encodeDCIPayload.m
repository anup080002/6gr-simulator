function dci = encodeDCIPayload(fields, dciFormat, pdcchCfg)
%ENCODEDCIPAYLOAD Strict contextual DCI payload serialization.

context = sixgr.phy.pdcch.resolveDCIContext(pdcchCfg, dciFormat);
dci = sixgr.phy.pdcch.DCIPacker.pack(fields, context);
end
