function ok = testRAN1AI1032PairedRuntimeWiring()
%TESTRAN1AI1032PAIREDRUNTIMEWIRING Freeze paired SLS stochastic inputs.

if isempty(which("sixgr.system.SystemLevelRunner"))
    setup6GRSimToolkit("Verbose", false);
end
study = sixgr.studies.ran1ai1032.loadStudyConfig();
cfg0 = localConfig("S0");
cfg1 = localConfig("S1");
nUE = double(cfg0.scenario.ue.nUE);

bundleA = struct("GeometrySeed", 6101, "ShadowSeed", 6102, ...
    "TrafficSeed", 6103, "AntennaOrientationSeed", 6104, ...
    "SchedulerSeed", 6105, "PropagationSeed", 6106);
populationA = sixgr.studies.ran1ai1032.buildFWAPopulation( ...
    study, "Profile-1", nUE, bundleA.GeometrySeed);

s0 = localRun(cfg0, bundleA, populationA);
s1 = localRun(cfg1, bundleA, populationA);

assert(s0.Ok && s1.Ok && s0.Details.PairedSeedBundleActive && ...
    s1.Details.PairedSeedBundleActive, ...
    "Both paired comparator runs must complete with explicit bundle authority.");
assert(s0.Details.TrafficArrivalRatePerCell_s == 2e4 && ...
    s1.Details.TrafficArrivalRatePerCell_s == 2e4, ...
    "The runtime must publish the applied FTP3 rate for load calibration.");
assert(~isempty(s0.Details.TrafficArrivalEvents) && ...
    sum(s0.Details.OfferedBitsUL,"all")==sum(s0.Details.TrafficArrivalEvents.OfferedBits), ...
    "The executed FTP3 offered load must preserve the generated fixed-file arrival ledger.");
assert(string(s0.Details.TrafficModel)=="ftp3" && ...
    string(s0.Details.TrafficModelSource)=="sixgr.system.Traffic_FTP3", ...
    "The explicit FTP3 generator must remain the runtime workload authority.");
assert(istable(s0.Details.ResourceOpportunityTable) && ...
    ismember("PRBSet",string(s0.Details.SchedulerGrants.Properties.VariableNames)), ...
    "Load calibration requires independent opportunities and exact grant PRB identities.");
assert(isequaln(s0.Details.ResourceOpportunityTable,s1.Details.ResourceOpportunityTable), ...
    "Same-grid paired comparators must retain identical independent opportunity calendars.");
assert(isequaln(s0.Details.UEInitial.pos_m, s1.Details.UEInitial.pos_m), ...
    "S0/S1 must replay identical dropped UE geometry from one GeometrySeed.");
assert(isequaln(s0.Details.FWAPopulationTable, ...
    s1.Details.FWAPopulationTable), ...
    "S0/S1 must bind the identical FWA population table.");
assert(isequaln(s0.Details.UEInitial.antenna_orientation_deg, ...
    s1.Details.UEInitial.antenna_orientation_deg), ...
    "S0/S1 must replay identical CPE orientations.");
assert(isequaln(s0.Details.TrafficArrivalEvents, ...
    s1.Details.TrafficArrivalEvents) && ...
    string(s0.Details.TrafficArrivalStreamID) == ...
    string(s1.Details.TrafficArrivalStreamID), ...
    "S0/S1 must replay the exact FTP3 arrival ledger.");

bundleB = struct("GeometrySeed", 6201, "ShadowSeed", 6202, ...
    "TrafficSeed", 6203, "AntennaOrientationSeed", 6204, ...
    "SchedulerSeed", 6205, "PropagationSeed", 6206);
populationB = sixgr.studies.ran1ai1032.buildFWAPopulation( ...
    study, "Profile-1", nUE, bundleB.GeometrySeed);
changed = localRun(cfg0, bundleB, populationB);
assert(changed.Ok, "Changed-seed paired runtime fixture must complete.");
assert(~isequaln(s0.Details.UEInitial.pos_m, ...
    changed.Details.UEInitial.pos_m), ...
    "Changing GeometrySeed must change the dropped UE geometry.");
assert(~isequaln(s0.Details.UEInitial.antenna_orientation_deg, ...
    changed.Details.UEInitial.antenna_orientation_deg), ...
    "Changing AntennaOrientationSeed must change CPE orientation.");
assert(~isequaln(s0.Details.FWAPopulationTable, ...
    changed.Details.FWAPopulationTable), ...
    "Changing the paired population seed must change identity assignment.");
assert(string(s0.Details.TrafficArrivalStreamID) ~= ...
    string(changed.Details.TrafficArrivalStreamID) && ...
    ~isequaln(s0.Details.TrafficArrivalEvents, ...
    changed.Details.TrafficArrivalEvents), ...
    "Changing TrafficSeed must change the FTP3 stream identity and ledger.");

bad = rmfield(bundleA, "ShadowSeed");
threw = false;
try
    localRun(cfg0, bad, populationA);
catch ME
    threw = ME.identifier == "sixgr:system:IncompleteSeedBundle";
end
assert(threw, "An incomplete paired seed bundle must fail closed.");

ok = true;
end

function result = localRun(cfg, bundle, population)
runFolder = tempname;
mkdir(runFolder);
cleanup = onCleanup(@() localRemove(runFolder)); %#ok<NASGU>
ctx = sixgr.core.SimContext(cfg, "RunFolder", runFolder);
stateBefore = rng;
result = sixgr.system.SystemLevelRunner.run(ctx, struct( ...
    "NumTTI", 2, "PHYBackend", "waveform", ...
    "SeedBundle", bundle, "FWAPopulationTable", population));
assert(isequal(stateBefore, rng), ...
    "SystemLevelRunner must restore the caller RNG after paired execution.");
ctx.Logger.close();
delete(ctx);
end

function cfg = localConfig(comparatorID)
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.useMex = false;
cfg.run.seed = 44021;
cfg.run.runTag = "ai_10_3_2_paired_" + lower(comparatorID);
cfg.run.executionID = cfg.run.runTag + "_execution";
cfg.meta.scenarioID = "ai_10_3_2_" + lower(comparatorID);
cfg.meta.configHash = repmat('c', 1, 64);
cfg.system.phyBackend = "waveform";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.outputs.saveFIG = false;
cfg.outputs.exportSLSOutputCatalog = false;
cfg.scenario.layout.nSites = 1;
cfg.scenario.layout.nSectorsPerSite = 1;
cfg.scenario.layout.wrapAround = false;
cfg.scenario.ue.nUE = 8;
cfg.scenario.nUE = 8;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.channel.awgnOnly = true;
cfg.channel.model = "AWGN";
cfg.channel.pathlossEnabled = false;
cfg.channel.shadowFadingEnabled = false;
cfg.channel.losEnabled = false;
cfg.channel.fading.enable = false;
cfg.traffic.model = "ftp3";
cfg.traffic.ftp3.fileSizeBytes = 500000;
cfg.traffic.ftp3.arrivalRatePerCell_s = 2e4;
cfg.traffic.ftp3.direction = "UL";
cfg.traffic.ftp3.seed = 1; % Must be superseded by params.SeedBundle.
cfg.mac.scheduler.type = "rr";
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 120/1024;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 120/1024;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.nLayers = 1;
cfg = sixgr.config.normalizeConfig(cfg);
sixgr.config.validateConfig(cfg);
end

function localRemove(folder)
if isfolder(folder)
    try
        rmdir(folder, "s");
    catch
        % Windows can briefly retain a just-closed log handle.  A leftover
        % test temp folder is preferable to making a semantic test flaky.
    end
end
end
