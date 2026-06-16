function ok = testTRSConfigStrictValidation()
setup6GRSimToolkit("Verbose", false);
b = trsStrictAnchorResult();
cfg = b.Config;
assert(logical(cfg.StrictValidation.StrictValid), "Strict TRS config must validate.");
assert(isa(cfg.ToolboxCSIRS, "nrCSIRSConfig") && strcmpi(char(string(cfg.CSIRSType)), "nzp"), ...
    "Strict TRS must bind to toolbox NZP-CSI-RS config.");
assert(numel(double(cfg.SlotNumbers)) >= 2, "Strict TRS requires at least two slots for CFO tracking.");
ok = true;
end
