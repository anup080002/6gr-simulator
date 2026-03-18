function ok = testAttachProcedure()
%TESTATTACHPROCEDURE Slot-driven UE<->gNB attach should reach CONNECTED.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;

ueRRC = sixgr.l3.rrc.RRC(cfg, "UE", "UEId", 1);
gnbRRC = sixgr.l3.rrc.RRC(cfg, "gNB", "CellID", double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1)));
ueRRC.setSystemInformation(sixgr.l3.rrc.SystemInformation(cfg, "CellID", double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1))));

okAttach = false;
rar = struct();
rnti = 1;
for s = 0:63
    actUE = ueRRC.step(s, struct("RAR", rar));
    rar = struct();
    if isfield(actUE, "PrachTx") && ~isempty(actUE.PrachTx)
        actG = gnbRRC.step(s, struct("PrachDetect", actUE.PrachTx));
        if isfield(actG, "RAR") && ~isempty(actG.RAR)
            rar = actG.RAR;
            rnti = double(sixgr.util.structGet(rar, "TempCRNTI", 1));
        end
    end

    ul = ueRRC.pollTxMACSDUs(256);
    if ~isempty(ul)
        gnbRRC.receiveMACSDUs(ul, "RNTI", rnti);
    end
    dl = gnbRRC.pollTxMACSDUs(256, "RNTI", rnti);
    if ~isempty(dl)
        ueRRC.receiveMACSDUs(dl);
    end
    if strcmpi(ueRRC.State, "CONNECTED")
        okAttach = true;
        break;
    end
end

assert(okAttach, "Attach procedure did not reach CONNECTED within slot budget.");
ok = true;
end
