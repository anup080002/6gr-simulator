function ok = testSchedulerPUSCHSRSAuthorityPropagation()
%TESTSCHEDULERPUSCHSRSAUTHORITYPROPAGATION Preserve SRS truth before freeze.

setup6GRSimToolkit("Verbose", false);
for schedulerName = ["PF", "RR"]
    cfg = localConfig();
    if schedulerName == "PF"
        scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "UL");
    else
        scheduler = sixgr.l2.mac.SchedulerRR(cfg, "Direction", "UL");
    end
    ue = localUEState();
    [grants, ~] = scheduler.schedule(7, ue, localBudget(7));
    assert(numel(grants) == 1, ...
        "%s scheduler must create one strict causal-SRS UL grant.", schedulerName);
    grant = grants(1);
    assert(logical(grant.SRSValid) && logical(grant.SRSCausalUsable), ...
        "%s scheduler dropped the usable SRS state before grant freeze.", schedulerName);
    assert(string(grant.SRSCausalMeasurementId) == "SRS_UE_1_slot_5" && ...
        double(grant.LastSuccessfulSRSSlot) == 5 && ...
        double(grant.SRSCausalAgeSlots) == 2, ...
        "%s scheduler changed the causal SRS identity, slot, or age.", schedulerName);
    prec = grant.PHYGrant.PrecodingState;
    assert(logical(prec.AuthoritativeSRSDecisionUsed) && ...
        string(prec.SRSMeasurementID) == "SRS_UE_1_slot_5" && ...
        double(prec.SRSMeasurementSlot) == 5, ...
        "%s frozen PUSCH grant is not bound to the scheduler SRS evidence.", schedulerName);

    missing = ue;
    missing.SRSCausalUsable = false;
    missing.SRSCausalMeasurementId = "";
    localAssertThrows(@()scheduler.schedule(8, missing, localBudget(8)), ...
        "sixgr:mimo:MissingSRSState");
end
ok = true;
end

function cfg = localConfig()
cfg = sixgr.config.defaultConfig();
cfg.system.phyBackend = "waveform";
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.fading.enable = false;
cfg.channel.bandwidth_Hz = 20e6;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.numerology.scs_kHz = 30;
cfg.phy.NCellID = 41;
cfg.phy.ueArray = [2 2 1];
cfg.antenna.ue.numElements = 4;
cfg.scenario.ue.nTxAnt = 4;
cfg.scenario.bs.nRxAnt = 4;
cfg.rf.ue.hybridBeamformingEnabled = true;
cfg.rf.ue.numRFChains = 2;
cfg.phy.mimo.strict = true;
cfg.mimo.strict = true;
cfg.phy.pusch.numLayers = 2;
cfg.phy.pusch.nLayers = 2;
cfg.phy.pusch.NumAntennaPorts = 2;
cfg.phy.pusch.numPorts = 2;
cfg.phy.pusch.nPorts = 2;
cfg.phy.pusch.TransmissionScheme = "codebook";
cfg.phy.pusch.transmissionScheme = "codebook";
cfg.phy.pusch.CodebookType = "codebook1_ng1n4n1";
cfg.phy.pusch.TPMI = 0;
cfg.phy.pusch.PMI = 0;
cfg.phy.pusch.transformPrecoding = false;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 0.30;
cfg.phy.pusch.mcsIndex = 1;
cfg.phy.pusch.mappingType = "A";
cfg.phy.pusch.symbolAllocation = [0 14];
cfg.phy.pusch.dmrs.portSet = [0 1];
% The SRS-owned RI/TPMI fields require the advanced UL DCI format.  Keep
% this production-scheduler fixture bound to an explicit monitored search
% space instead of relying on an empty legacy default.
cfg.phy.pdcch.dciFormats = {'0_1', '1_1'};
cfg.phy.linkAdaptation.mode = "fixed";
cfg.phy.linkAdaptation.rankPolicy = "fixed_rank_anchor";
cfg.mimo.rank_adaptation_policy = "fixed_rank_anchor";
cfg.mac.scheduler.maxUEPerSlot = 1;
cfg.mac.scheduler.minPRBPerUE = 6;
cfg.mac.scheduler.maxPRBAllocationPerUE = 51;
cfg.mac.scheduler.fastNREApprox = false;
cfg.mac.scheduler.tbsMode = "faithful";
cfg = withCanonicalSchedulerTiming(cfg);
end

function budget = localBudget(dataSlot)
budget = struct( ...
    "PRBSet", 0:50, "SymbolAllocation", [0 14], ...
    "ControlAbsoluteSlot", double(dataSlot - 1), ...
    "ControlSymbolAllocation", [0 2]);
end

function ue = localUEState()
ue = struct( ...
    "RNTI", 701, "ULBufferBytes", 4000, "CQI", 7, ...
    "RI", 2, "PMI", 0, "TPMI", 0, "SRI", 0, ...
    "Modulation", "QPSK", "TargetCodeRate", 0.30, ...
    "MCSIndex", 1, "FeedbackValid", true, ...
    "CausalFeedbackUsable", true, ...
    "SRSValid", true, "SRSCausalUsable", true, ...
    "SRSCausalMeasurementId", "SRS_UE_1_slot_5", ...
    "LastSuccessfulSRSSlot", 5, "SRSAgeSlots", 2, ...
    "SRSCausalAgeSlots", 2, "SRSCausalStatus", "usable", ...
    "HeadOfLineDelay_ms", 0);
end

function localAssertThrows(fh, expectedId)
try
    fh();
catch ME
    assert(strcmp(ME.identifier, expectedId), ...
        "Expected %s, got %s: %s", expectedId, ME.identifier, ME.message);
    return;
end
error("ExpectedException:notThrown", "Expected %s to be thrown.", expectedId);
end
