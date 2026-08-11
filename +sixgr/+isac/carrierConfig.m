function [carrier,profile,ofdmInfo] = carrierConfig(cfg,profileName)
%CARRIERCONFIG Construct an NR carrier directly from the selected YAML profile.

arguments
    cfg (1,1) struct
    profileName (1,1) string = ""
end
if strlength(profileName) == 0
    profileName = string(cfg.carrier.activeProfile);
end
profile = sixgr.util.structGet(cfg,"carrier.profiles."+profileName,[]);
if ~(isstruct(profile) && isscalar(profile))
    error("sixgr:isac:MissingCarrierProfile","Unknown carrier profile %s.",profileName);
end
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = double(profile.subcarrierSpacingKHz);
carrier.NSizeGrid = double(profile.nSizeGrid);
carrier.NStartGrid = double(profile.nStartGrid);
carrier.NCellID = double(profile.nCellID);
carrier.CyclicPrefix = char(string(profile.cyclicPrefix));
carrier.NFrame = 0;
carrier.NSlot = 0;
ofdmInfo = nrOFDMInfo(carrier,"Windowing",double(cfg.waveform.ofdmWindowingSamples));
end
