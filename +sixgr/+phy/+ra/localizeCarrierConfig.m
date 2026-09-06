function cfgOut = localizeCarrierConfig(cfg, raCfg, absoluteSlot)
%LOCALIZECARRIERCONFIG Apply RA anchor carrier/PDCCH config to a cfg copy.
% Stage callers must supply their zero-based absolute transmission slot.
% Keeping a correct slot only in exported metadata does not set the DM-RS
% sequence or OFDM timing used by the actual transmitter and receiver.
cfgOut = cfg;
cfgOut.phy.carrier.NCellID = double(raCfg.NCellID);
cfgOut.phy.carrier.NSizeGrid = double(raCfg.NSizeGrid);
cfgOut.phy.carrier.SubcarrierSpacing = double(raCfg.CarrierSCSkHz);
cfgOut.phy.carrier.SubcarrierSpacing_kHz = double(raCfg.CarrierSCSkHz);
cfgOut.run.strictMode = logical(raCfg.StrictMode);
if nargin >= 3
    if ~(isnumeric(absoluteSlot) && isreal(absoluteSlot) && ...
            isscalar(absoluteSlot) && isfinite(absoluteSlot) && ...
            absoluteSlot >= 0 && absoluteSlot <= flintmax && ...
            absoluteSlot == fix(absoluteSlot))
        error("sixgr:phy:ra:InvalidStageAbsoluteSlot", ...
            "RA stage absolute slot must be an exactly representable nonnegative integer.");
    end
    numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
        raCfg.CarrierSCSkHz, ...
        sixgr.util.structGet(cfgOut, "phy.carrier.CyclicPrefix", "normal"), ...
        "generic_waveform_test", "");
    slotsPerFrame = double(numerology.SlotsPerFrame);
    cfgOut.phy.carrier.NSlot = mod(double(absoluteSlot), slotsPerFrame);
    % Keep the unwrapped simulation frame, as supported by nrCarrierConfig.
    % Consumers encoding an on-air SFN are responsible for modulo 1024.
    cfgOut.phy.carrier.NFrame = floor(double(absoluteSlot) / slotsPerFrame);
end
end
