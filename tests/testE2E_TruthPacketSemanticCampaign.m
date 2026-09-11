function ok = testE2E_TruthPacketSemanticCampaign()
%TESTE2E_TRUTHPACKETSEMANTICCAMPAIGN Randomized truth-mode packet semantics checks.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg = withCanonicalSchedulerTiming(cfg);
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

tmp = tempname;
mkdir(tmp);
c = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>

seeds = [11 22 33];
deliveredULAny = false;
generatedULAny = false;

for i = 1:numel(seeds)
    s = seeds(i);
    cfg.run.seed = double(s);
    rng(double(s), "twister");
    rep = sixgr_run_3gpp_full_campaign(cfg, ...
        "ResultsRoot", tmp, ...
        "Verbose", false, ...
        "SetupToolboxChecks", false, ...
        "OnlyE2E", true, ...
        "RunE2EStackProbe", true, ...
        "E2EDuration_s", 0.02, ...
        "E2EMaxSlots", 24, ...
        "E2EUECount", 2, ...
        "E2ETrafficModel", "mmtc", ...
        "E2EAirModel", "truth", ...
        "E2EEnableAI", false, ...
        "E2ESaveFigures", false, ...
        "UseMexAcceleration", false, ...
        "AutoBuildMexAcceleration", false, ...
        "VerifyArtifacts", false, ...
        "GenerateCampaignPlots", false, ...
        "E2EStrictValidation", false, ...
        "E2ETruthMaxSlots", 28);

    verifyCampaignSeedAuthority(rep,double(s));
    assert(isfield(rep, "E2E") && isstruct(rep.E2E), "E2E report struct missing.");
    assert(istable(rep.E2E.SummaryTable) && height(rep.E2E.SummaryTable) == 1, "E2E summary missing.");
    assert(istable(rep.E2E.PacketIntegrityTable) && height(rep.E2E.PacketIntegrityTable) >= 3, "Packet integrity table missing.");
    assert(istable(rep.E2E.CheckTable) && ~isempty(rep.E2E.CheckTable), "E2E component checks missing.");

    % Accounting alone can pass an empty run. This bidirectional fixture
    % must exercise actual grants and receiver CRC outcomes in both paths.
    G = rep.E2E.SchedulerTraceTable;
    H = rep.E2E.HARQTraceTable;
    assert(istable(G) && ~isempty(G) && istable(H) && ~isempty(H), ...
        "Truth semantic coverage requires nonempty scheduler and HARQ traces.");
    for direction = ["DL", "UL"]
        gd = upper(string(G.Direction)) == direction;
        hd = upper(string(H.Direction)) == direction;
        assert(any(gd) && any(hd), ...
            "Seed %d did not execute %s grants and receiver CRC outcomes.", s, direction);
        assert(all(isfinite(G.TBSBytes(gd)) & G.TBSBytes(gd) > 0) && ...
            all(isfinite(G.NumPRB(gd)) & G.NumPRB(gd) > 0), ...
            "Seed %d has invalid %s grant allocation evidence.", s, direction);
        crc = double(H.CRCResult(hd));
        assert(all(isfinite(crc) & (crc == 0 | crc == 1)), ...
            "Seed %d has missing or invalid %s receiver CRC outcomes.", s, direction);
    end

    S = rep.E2E.SummaryTable(1,:);
    assert(lower(string(S.E2EAirModel)) == "truth", "Truth campaign summary must report truth air model.");
    assert(lower(string(S.ExecutionBackend)) == "full_stack_replay_system_coupled", ...
        "Truth campaign must use the system-coupled full-stack replay backend.");
    assert(logical(S.E2ESystemCoupled), ...
        "Truth campaign summary must record system-coupled truth replay.");
    assert(string(S.E2ECouplingMode) == "system_waveform_grant_trace", ...
        "Truth campaign summary must report waveform system grant trace coupling.");
    assert(double(S.SemanticCheckPassRate_pct) >= 99.9, "Truth campaign semantic pass rate below expected threshold.");
    assert(double(S.PacketAccountingPassRate_pct) >= 99.9, "Truth campaign packet-accounting pass rate below expected threshold.");
    assert(strlength(string(S.PacketAccountingMeaning)) > 0, "Truth campaign must explain semantic/accounting meaning.");
    assert(istable(rep.E2E.QoSEvaluationTable) && height(rep.E2E.QoSEvaluationTable) >= 3, "QoS evaluation table missing.");

    P = rep.E2E.PacketIntegrityTable;
    dirs = upper(string(P.Direction));
    for d = ["DL","UL","ALL"]
        idx = find(dirs == d, 1, "first");
        assert(~isempty(idx), "Packet integrity table missing direction row: %s", d);
        gen = double(P.GeneratedPackets(idx));
        del = double(P.DeliveredPackets(idx));
        dup = double(P.DuplicatePackets(idx));
        reord = double(P.OutOfOrderPackets(idx));
        missRate = double(P.DeadlineMissRate(idx));
        sem = logical(P.SemanticPass(idx));
        acct = logical(P.AccountingIntegrityPass(idx));
        assert(isfinite(gen) && isfinite(del) && gen >= 0 && del >= 0, "Invalid packet counters for %s.", d);
        assert(del <= gen + 1e-9, "Delivered packets exceed generated packets for %s.", d);
        assert(dup == 0, "Duplicate packets detected for %s.", d);
        assert(reord == 0, "Out-of-order packets detected for %s.", d);
        assert(isfinite(missRate) && missRate <= 0.10 + 1e-9, "Deadline miss rate too high for %s.", d);
        assert(sem, "Semantic pass flag is false for %s.", d);
        assert(acct, "Accounting pass flag is false for %s.", d);
    end

    idxUL = find(dirs == "UL", 1, "first");
    generatedULAny = generatedULAny || (double(P.GeneratedPackets(idxUL)) > 0);
    deliveredULAny = deliveredULAny || (double(P.DeliveredPackets(idxUL)) > 0);
end

assert(generatedULAny, "Randomized truth campaign generated no UL packets across all seeds.");
if ~deliveredULAny
    warning("sixgr:test:TruthSemanticCampaignNoULDelivery", ...
        "Randomized truth campaign generated UL traffic but delivered none across the sampled seeds; semantic/accounting checks still passed, so treat this as a QoS outcome rather than a semantic failure.");
end
ok = true;
end
