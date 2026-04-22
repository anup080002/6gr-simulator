function out = PDCCHModulator(codedBits, ctrlCfg)
%PDCCHModulator Apply the baseline 6GR PDCCH modulation.

if ~strcmpi(string(ctrlCfg.Modulation), "QPSK")
    error("sixgr:ctrl:PDCCHModulator:UnsupportedModulation", ...
        "Only baseline QPSK is implemented in the current study runner.");
end

[sym, info] = sixgr.phy.mod.modulate(codedBits(:), ctrlCfg.Modulation);
out = struct();
out.Symbols = sym(:);
out.Info = info;
end
