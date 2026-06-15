function cfg = localizeRAPDCCHConfig(cfg, carrier)
%LOCALIZERAPDCCHCONFIG Keep RA control resources inside the active BWP.

nGrid = max(1, round(double(carrier.NSizeGrid)));
nGroups = max(1, floor(nGrid / 6));
freqResources = ones(1, nGroups);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.coreset.frequencyResources", freqResources);
cfg = sixgr.util.structSet(cfg, "phy.pdcch.nStartBWP", double(carrier.NStartGrid));
cfg = sixgr.util.structSet(cfg, "phy.pdcch.nSizeBWP", nGrid);
end
