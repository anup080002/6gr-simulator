function cfgOut = localizeCarrierConfig(cfg, raCfg)
%LOCALIZECARRIERCONFIG Apply RA anchor carrier/PDCCH config to a cfg copy.
cfgOut = cfg;
cfgOut.phy.carrier.NCellID = double(raCfg.NCellID);
cfgOut.phy.carrier.NSizeGrid = double(raCfg.NSizeGrid);
cfgOut.phy.carrier.SubcarrierSpacing = double(raCfg.CarrierSCSkHz);
cfgOut.phy.carrier.SubcarrierSpacing_kHz = double(raCfg.CarrierSCSkHz);
cfgOut.run.strictMode = logical(raCfg.StrictMode);
end
