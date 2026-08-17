function ok = testPhase7PhysicalChannelReconciliation()
%TESTPHASE7PHYSICALCHANNELRECONCILIATION Same-flow physical gates fail closed.

setup6GRSimToolkit("Verbose", false);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, "s")); %#ok<NASGU>
mkdir(fullfile(tmp, "air_interface", "csv"));
mkdir(fullfile(tmp, "reports", "csv"));

cfg = struct();
cfg.channel.model = "CDL";
cfg.channel.cdlProfile = "CDL-C";
cfg.channel.normalizePathGains = true;
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.bs.nRxAnt = 64;
cfg.scenario.ue.nTxAnt = 4;
cfg.scenario.ue.nRxAnt = 4;
cfg.antenna.bs.polarization = "cross_pol";
cfg.antenna.ue.polarization = "dual";
cfg.run.link_direction = "both";

for direction = ["DL","UL"]
    trialT = table(direction, "PASS", true, false, false, "CDL-C", ...
        true, "nrCDLChannel", true, ...
        'VariableNames', {'Direction','Status','FinalizedFlag','FallbackFlag', ...
        'PlaceholderFlag','ChannelModelApplied','ChannelFadingApplied', ...
        'ChannelObjectClass','ChannelUsesSameRuntimeAntennaAssumptions'});
    if direction == "DL"
        name = "dl_pdsch_trials.csv";
    else
        name = "ul_pusch_trials.csv";
    end
    sixgr.util.csvWriteTable(fullfile(tmp, "air_interface", "csv", name), trialT);
end

direction = ["DL";"DL";"UL";"UL"];
cirT = table(direction, repmat("nrCDLChannel",4,1), true(4,1), ...
    repmat(0.5,4,1), 'VariableNames', ...
    {'Direction','ChannelObjectClass','NormalizePathGains','NormalizedTapPower'});
sixgr.util.csvWriteTable(fullfile(tmp, "reports", "csv", "channel_impulse_response.csv"), cirT);

direction = ["DL";"UL"];
observedRows = [1;1];
physicalOk = true(2,1);
observedTx = [64;4];
observedRx = [4;64];
sameRuntime = true(2,1);
countOnly = false(2,1);
arrayT = table(direction, observedRows, physicalOk, observedTx, observedRx, ...
    sameRuntime, countOnly, 'VariableNames', {'Direction','ObservedRows', ...
    'PhysicalArrayConsistencyOk','ObservedPhysicalTxAntennas', ...
    'ObservedPhysicalRxAntennas','ChannelUsesSameRuntimeAntennaAssumptions', ...
    'ChannelUsesCountOnlyAntennaModel'});
sixgr.util.csvWriteTable(fullfile(tmp, "reports", "csv", "channel_array_consistency.csv"), arrayT);

antennaT = table(direction, repmat("dual",2,1), repmat("dual",2,1), ...
    true(2,1), repmat("CoupledTruthRuntime->active_trial",2,1), ...
    'VariableNames', {'Direction','BSAntennaPolarization','UEAntennaPolarization', ...
    'AntennaRuntimeObjectCreated','SameFlowEvidenceSource'});
sixgr.util.csvWriteTable(fullfile(tmp, "reports", "csv", "antenna_runtime_evidence.csv"), antennaT);

report = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmp);
for name = ["CdlRealizationOk","PathPowerNormalizationOk", ...
        "AntennaArrayReconciliationOk","PolarizationReconciliationOk"]
    assert(logical(report.Gates.(char(name))), ...
        "Expected measured physical-channel gate %s to pass.", name);
end

% The operator master YAML uses antenna_and_array as its authority.  The
% physical reconciliation must resolve those endpoint counts directly and
% not depend on a legacy scenario.bs/scenario.ue mirror.
cfgMaster = rmfield(cfg, "scenario");
cfgMaster.antenna_and_array.bs_num_antenna_elements = 64;
cfgMaster.antenna_and_array.ue_num_antenna_elements = 4;
reportMaster = sixgr.analytics.buildPhase7ReadinessArtifacts(cfgMaster, tmp);
assert(logical(reportMaster.Gates.AntennaArrayReconciliationOk), ...
    "Master-YAML antenna_and_array endpoint counts must reconcile for both DL and UL.");

% Removing the actual UL waveform row must not be rescued by the model
% profile or configured values.
delete(fullfile(tmp, "air_interface", "csv", "ul_pusch_trials.csv"));
reportMissing = sixgr.analytics.buildPhase7ReadinessArtifacts(cfg, tmp);
assert(height(reportMissing.PhysicalChannelReconciliation.ChannelRealization) == 2 && ...
    any(string(reportMissing.PhysicalChannelReconciliation.ChannelRealization.Direction) == "UL" & ...
    ~logical(reportMissing.PhysicalChannelReconciliation.ChannelRealization.ChannelRealizationOk)), ...
    "Absent UL waveform evidence must produce an explicit failing reconciliation row, not synthetic evidence.");
assert(~reportMissing.Gates.CdlRealizationOk, ...
    "Required UL runtime evidence must fail the channel-realization gate when absent.");
assert(~reportMissing.Gates.Phase1Ok, ...
    "A partial physical-channel campaign must not pass the full Phase-1 rollup.");

ok = true;
end
