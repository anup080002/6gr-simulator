function ok = testRAPDSCHPrecodingIsolation()
%TESTRAPDSCHPRECODINGISOLATION RA Msg2/Msg4 must not inherit data PDSCH beams.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

cfg = struct();
cfg.phy.nTxAnt = 64;
cfg.phy.pdsch.nLayers = 2;
cfg.phy.pdsch.numPorts = 64;
cfg.phy.pdsch.nPorts = 64;
cfg.phy.pdsch.precoding.matrix = ones(64, 2);
cfg.phy.pdsch.precodingMatrix = ones(64, 2);
cfg.phy.pdsch.W = ones(64, 2);

pdsch = struct("NumLayers", 1);
cfgRA = sixgr.phy.ra.localizeRAPDSCHConfig(cfg, pdsch);

assert(double(sixgr.util.structGet(cfgRA, "phy.pdsch.nLayers", NaN)) == 1, ...
    "RA PDSCH must use the schedule layer count.");
assert(double(sixgr.util.structGet(cfgRA, "phy.pdsch.numPorts", NaN)) == 1, ...
    "RA PDSCH must use schedule-local logical ports.");
assert(isempty(sixgr.util.structGet(cfgRA, "phy.pdsch.precoding.matrix", [])), ...
    "RA PDSCH must clear inherited data-plane explicit precoding matrix.");
assert(isempty(sixgr.util.structGet(cfgRA, "phy.pdsch.precodingMatrix", [])), ...
    "RA PDSCH must clear inherited data-plane legacy precodingMatrix.");
assert(isempty(sixgr.util.structGet(cfgRA, "phy.pdsch.W", [])), ...
    "RA PDSCH must clear inherited data-plane W.");
assert(strcmpi(char(string(sixgr.util.structGet(cfgRA, "phy.pdsch.precoding.mode", ""))), ...
    "ra_control_identity"), "RA PDSCH must disclose its control identity precoding mode.");

ok = true;
end
