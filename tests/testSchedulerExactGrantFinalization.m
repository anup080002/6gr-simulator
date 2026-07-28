function ok = testSchedulerExactGrantFinalization()
%TESTSCHEDULEREXACTGRANTFINALIZATION Guard exact grant/DCI finalization.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.useMex = false;
cfg.mac.scheduler.fastNREApprox = true;
cfg.mac.scheduler.tbsMode = "approximate";
cfg.channel.bandwidth_Hz = 20e6;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.pdsch.prbSet = 0:11;
cfg.phy.pdsch.symbolAllocation = [2 10];
cfg.phy.pdsch.mcsIndex = 4;
cfg.phy.pdsch.mcsTable = "qam256_table2";
mcsProfile = sixgr.link.resolveMCSProfile( ...
    cfg.phy.pdsch.mcsTable, cfg.phy.pdsch.mcsIndex);
cfg.phy.pdsch.modulation = mcsProfile.Modulation;
cfg.phy.pdsch.codeRate = mcsProfile.TargetCodeRate;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.mcsContext = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", ...
    "OperatingBand", "n78", ...
    "DeploymentClass", "controlled_test");
cfg.phy.pdcch.coreset.duration = 2;
cfg.phy.pdcch.coreset.id = 0;
cfg.phy.pdcch.searchSpace.id = 1;
cfg = sixgr.config.normalizeConfig(cfg);
cfg = withCanonicalSchedulerTiming(cfg);

grant = sixgr.link.resolveWaveformGrant(cfg, "DL", 0);
assert(logical(grant.Valid), "Resolved waveform grant must be valid.");
assert(double(grant.UEIndex) == 1 && double(grant.UEID) == 1 && ...
    string(grant.UEIdentitySource) == "standalone_single_user_default", ...
    "A standalone grant must carry one consistent, explicitly sourced UE identity.");
assert(logical(grant.ExactPHYFeasibilityChecked) && logical(grant.ExactPHYFeasible), ...
    "Resolved waveform grant must carry exact PHY feasibility evidence.");
assert(~logical(grant.ExactTBSUsedFastNREApprox), ...
    "Executable grant finalization must not use the fast NRE approximation.");
assert(~logical(grant.PlanningOnlyApproximation), ...
    "Executable grant must not retain planning-only approximation status.");

sch = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL");
[refBits, refBytes, refNRE] = sch.estimateTBS(grant.Modulation, grant.NumLayers, ...
    numel(grant.PRBSet), grant.SymbolAllocation, grant.TargetCodeRate, ...
    "PlanningOnly", false, "ForceExact", true);
assert(double(grant.TBSBits) == double(refBits) && double(grant.TBSBytes) == double(refBytes), ...
    "Finalized grant TBS must match the authoritative exact TBS calculation.");
assert(double(grant.NREPerPRB) == double(refNRE), ...
    "Finalized grant NREPerPRB must match exact resource accounting.");
assert(double(grant.PHYGrant.CodingLayout.TBSBits) == double(grant.TBSBits), ...
    "Frozen PHYGrant coding layout must carry the finalized TBS.");

dci = grant.DCI;
assert(isstruct(dci) && logical(dci.FinalizedGrant) && logical(dci.ExactPHYFeasible), ...
    "DCI must disclose that it was packed from a finalized feasible grant.");
assert(logical(dci.BitExactPDCCHPayload) && strcmp(string(dci.StandardProfile), "ts38212_supported_dci_payload"), ...
    "Supported scheduler DCI must be packed by the bit-exact TS 38.212 payload encoder.");
assert(double(dci.SourceGrantTBSBits) == double(grant.TBSBits), ...
    "DCI must retain the source grant TBS lineage.");
assert(double(dci.RBStart) == min(double(grant.PRBSet)) && ...
    double(dci.RBLength) == numel(grant.PRBSet), ...
    "DCI frequency assignment must reconstruct the finalized PRB allocation.");
assert(double(dci.FieldValues.MCS) == double(grant.MCSIndex), ...
    "DCI MCS field must be packed from the finalized grant MCS.");

[pdcchTx, pdcchInfo] = sixgr.phy.dl.PDCCH_Tx(cfg, "Grant", grant, ...
    "K", numel(dci.Bits), "OFDMModulate", false);
assert(isequal(int8(dci.Bits(:)), pdcchTx.DCIBits), ...
    "PDCCH_Tx must consume finalized grant DCI bits when a grant is supplied.");
assert(strcmpi(string(pdcchInfo.DCIPayloadSource), "finalized_scheduler_grant_dci_bits") && ...
    ~logical(pdcchInfo.RandomDCIPayload), ...
    "PDCCH_Tx must not mark finalized-grant payloads as random.");
assert(double(pdcchTx.PDCCH.CORESET.CORESETID) == double(cfg.phy.pdcch.coreset.id) && ...
    double(pdcchTx.PDCCH.SearchSpace.SearchSpaceID) == double(cfg.phy.pdcch.searchSpace.id), ...
    "PDCCH_Tx must apply the configured CORESET/search-space IDs to value-class toolbox objects.");

[txA, infoA] = sixgr.phy.dl.PDCCH_Tx(cfg, "K", 32, "OFDMModulate", false);
[txB, infoB] = sixgr.phy.dl.PDCCH_Tx(cfg, "K", 32, "OFDMModulate", false);
assert(isequal(txA.DCIBits, txB.DCIBits) && all(txA.DCIBits == 0), ...
    "Standalone PDCCH_Tx without DCI bits must be deterministic, not random.");
assert(~logical(infoA.RandomDCIPayload) && ~logical(infoB.RandomDCIPayload), ...
    "Standalone deterministic PDCCH payloads must not be reported as random DCI.");

missingMultiUserIdentity = cfg;
missingMultiUserIdentity = sixgr.util.structSet(missingMultiUserIdentity, "lls6g.users.enabled", true);
missingMultiUserIdentity = sixgr.util.structSet(missingMultiUserIdentity, "lls6g.users.n_users", 2);
missingMultiUserIdentity = sixgr.util.structSet(missingMultiUserIdentity, "lls6g.userContext.RuntimeUEIndex", NaN);
missingMultiUserIdentity = sixgr.util.structSet(missingMultiUserIdentity, "lls6g.userContext.UEIndex", NaN);
threwMissingIdentity = false;
try
    sixgr.link.resolveWaveformGrant(missingMultiUserIdentity, "DL", 0);
catch ME
    threwMissingIdentity = strcmp(string(ME.identifier), ...
        "sixgr:link:resolveWaveformGrant:MissingMultiUserIdentity");
end
assert(threwMissingIdentity, ...
    "A multi-user grant without an explicit runtime UE identity must fail closed.");

bad = grant;
dropFields = intersect(fieldnames(bad), {'PHYGrant','DCI'});
if ~isempty(dropFields)
    bad = rmfield(bad, dropFields);
end
bad.PRBSet = [0 0 1];
badFinal = sch.finalizeExactPHYFeasibility(bad);
assert(~logical(badFinal.Valid) && strcmpi(string(badFinal.GrantBlocker), "duplicate_prb_allocation"), ...
    "Duplicate PRB grants must be rejected before DCI packing.");
threw = false;
try
    sch.buildDCIBitfield(badFinal);
catch ME
    threw = strcmp(ME.identifier, "sixgr:SchedulerBase:InfeasibleGrantDCI");
end
assert(threw, "DCI packing must fail closed for infeasible finalized grants.");

invalidSymbols = grant;
invalidSymbols.SymbolAllocation = [-1 15];
threw = false;
try
    sch.buildDCIBitfield(invalidSymbols);
catch ME
    threw = strcmp(ME.identifier, ...
        "sixgr:SchedulerBase:InvalidSymbolAllocation");
end
assert(threw, ...
    "DCI SLIV encoding must reject, not clamp, an invalid explicit allocation.");

job = sixgr.truth.buildGrantPHYJob(cfg, "DL", 30, 0, struct(), struct("GrantSnapshot", grant));
assert(isstruct(job.DCI) && isequal(uint8(job.DCI.Bits(:)), uint8(dci.Bits(:))), ...
    "buildGrantPHYJob must preserve finalized DCI bits for the worker payload.");
assert(double(job.PHYGrant.CodingLayout.TBSBits) == double(grant.TBSBits), ...
    "buildGrantPHYJob must preserve exact finalized TBS in the frozen PHYGrant.");

badTBSGrant = grant.PHYGrant;
badTBSGrant.CodingLayout.TBSBits = double(grant.TBSBits) + 8;
badTBSGrant.CodingLayout.TBSBitsPerCodeword = double(grant.TBSBits) + 8;
threw = false;
actualIdentifier = "";
try
    sixgr.phy.dl.PDSCH_Tx(cfg, "PHYGrant", badTBSGrant, ...
        "TransportBlockSizeOverride", double(grant.TBSBits) + 8, ...
        "ExecutionProfile", "phy_calibration", "CompactOutput", true);
catch ME
    actualIdentifier = string(ME.identifier);
    threw = strcmp(ME.identifier, "sixgr:phy:dl:PDSCHGrantTBSMismatch");
end
assert(threw, ...
    "PDSCH_Tx must not let TransportBlockSizeOverride self-certify a frozen-grant TBS mismatch. Actual error: %s", ...
    actualIdentifier);

ok = true;
end
