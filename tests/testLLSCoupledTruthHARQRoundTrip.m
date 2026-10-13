function ok = testLLSCoupledTruthHARQRoundTrip(retainedBundleFolder,repairedHARQCSV)
%TESTLLSCOUPLEDTRUTHHARQROUNDTRIP Ensure coupled-truth HARQ replay reaches real retransmissions.
% Optional retained evidence checks do not execute another physical run and
% must be reported separately from final-source end-to-end acceptance.

setup6GRSimToolkit("Verbose", false);
if nargin<1, retainedBundleFolder=""; end
if nargin<2, repairedHARQCSV=""; end

% Retain actual access/HARQ evidence even when a later assertion fails.
% The old five-slot fixture disabled RA and therefore never received a TAG.
if strlength(string(retainedBundleFolder))==0
    tmp = fullfile(pwd, "results", "lls", "coupled_truth_harq_roundtrip", ...
        char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
    mkdir(tmp);
else
    assert(isfolder(retainedBundleFolder),'Retained physical bundle must exist.');
    tmp=fileparts(char(retainedBundleFolder));
    fprintf('RETAINED_HARQ_RECHECK_ONLY: %s; no new PHY execution.\n',retainedBundleFolder);
end
fprintf('HARQ_ROUNDTRIP_RUN_FOLDER=%s\n',tmp);
scenarioPath = fullfile(pwd, "simulator", "configs", "validation", ...
    "lls_received_timing_harq.yaml");

scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "preflight"));
assert(cfg.initial_access.enabled && cfg.random_access.enabled, ...
    'The shared HARQ test must actually receive access/timing authority.');
assert(cfg.phy.pdsch.mcsIndex == 28 && cfg.phy.pusch.mcsIndex == 28, ...
    'This regression must retain the configured high-rate data comparison.');
assert(string(cfg.phy.pdcch.jointAdmissionPolicy) == "ul_preschedule_first", ...
    'Bidirectional HARQ must explicitly arbitrate coincident UL/DL control admission.');
slotDuration_s = max(eps, double(sixgr.util.structGet(cfg, "phy.numerology.slotDuration_ms", 0.5)) / 1e3);
opt = struct( ...
    "LinkDuration_s", max(double(cfg.run.totalSlots) * slotDuration_s, slotDuration_s), ...
    "LinkMaxSimFrames", double(cfg.run.totalSlots), ...
    "LinkSNR_dB", double(cfg.channel.snr_dB), ...
    "LinkSNRGrid_dB", double(cfg.channel.snr_dB), ...
    "LinkSweepFrames", 1, ...
    "LinkSweepTrialsPerSNR", double(cfg.run.totalSlots), ...
    "LinkReferenceSweepFrames", double(cfg.run.totalSlots), ...
    "LinkSweepMaxPoints", 1, ...
    "LinkAdaptiveSweepEnabled", false, ...
    "LinkAdaptiveSweepStep_dB", 2, ...
    "LinkAdaptiveSweepMaxPoints", 1, ...
    "SaveFigures", false);

airInterfaceFolder = fullfile(tmp, "bundle", "air_interface");
if strlength(string(retainedBundleFolder))==0
    assert(strlength(string(repairedHARQCSV))==0,'A fresh run must check its own HARQ export.');
    out = sixgr.truth.runWaveformLinkBundle(cfg, airInterfaceFolder, opt);
    assert(isstruct(out), "Coupled-truth HARQ roundtrip must return a runtime output struct.");
else
    airInterfaceFolder=fullfile(retainedBundleFolder,'air_interface');
end

runFolder = fileparts(airInterfaceFolder);
dlFile = fullfile(airInterfaceFolder, "csv", "dl_pdsch_trials.csv");
ulFile = fullfile(airInterfaceFolder, "csv", "ul_pusch_trials.csv");
harqFile = fullfile(runFolder, "harq", "csv", "live_harq_observation_timeline.csv");
if strlength(string(repairedHARQCSV))>0
    harqFile=char(repairedHARQCSV);
    fprintf('REPROJECTED_HARQ_CSV=%s; original failed export preserved.\n',harqFile);
end
stageFile = fullfile(runFolder, "reports", "csv", "live_stage_status.csv");

assert(exist(dlFile, "file") == 2, "Coupled-truth HARQ roundtrip must write DL trials.");
assert(exist(ulFile, "file") == 2, "Coupled-truth HARQ roundtrip must write UL trials.");
assert(exist(harqFile, "file") == 2, "Coupled-truth HARQ roundtrip must write live HARQ timeline.");
assert(exist(stageFile, "file") == 2, "Coupled-truth HARQ roundtrip must write live stage status.");

dl = readtable(dlFile, "VariableNamingRule", "preserve");
ul = readtable(ulFile, "VariableNamingRule", "preserve");
harq = readtable(harqFile, "VariableNamingRule", "preserve");
stage = readtable(stageFile, "VariableNamingRule", "preserve");
access = readtable(fullfile(airInterfaceFolder,"csv","prach_trials.csv"), ...
    "VariableNamingRule","preserve");
assert(~isempty(access) && any(logical(access.RACompleted)), ...
    'Connected HARQ trials must follow physically completed random access.');

assert(~isempty(dl), "Coupled-truth HARQ roundtrip DL trials must not be empty.");
assert(~isempty(ul), "Coupled-truth HARQ roundtrip UL trials must not be empty.");
assert(~isempty(harq), "Coupled-truth HARQ roundtrip HARQ timeline must not be empty.");
% Access establishes a radio identity different from the bootstrap RNTI.
% Verify the production outer runner, not only a directly invoked callback.
acceptedAccess=access(logical(access.RACompleted),:);
assert(all(acceptedAccess.FinalCRNTI==acceptedAccess.TemporaryCRNTI) && ...
    all(acceptedAccess.FinalCRNTI~=acceptedAccess.RNTI), ...
    'This physical regression must exercise received C-RNTI adoption.');
for ue=reshape(unique(acceptedAccess.UEIndex),1,[])
    identities=unique(acceptedAccess.FinalCRNTI(acceptedAccess.UEIndex==ue));
    assert(isscalar(identities),'This regression expects one successful access identity per UE.');
    assert(all(dl.RNTI(dl.UEIndex==ue)==identities) && ...
        all(ul.RNTI(ul.UEIndex==ue)==identities), ...
        'Connected data must retain the received C-RNTI, never a bootstrap-derived identity.');
end
assert(height(harq)==height(dl)+height(ul) && ...
    isequal(harq.Slot,[dl.Slot;ul.Slot]) && ...
    isequal(harq.CRCPass,[dl.CRCPass;ul.CRCPass]), ...
    'HARQ projection must preserve every retained primary observation and its CRC.');
assert(ismember('SweepPointIndex',dl.Properties.VariableNames) && ...
    ismember('SweepPointIndex',ul.Properties.VariableNames));
assert(all(dl.SweepPointIndex==1) && all(ul.SweepPointIndex==1) && ...
    all(harq.SweepPointIndex==1), ...
    'Raw data trials must retain the same physical sweep identity as HARQ.');
slotsPerFrame = max(1, round(double(sixgr.util.structGet(cfg, "phy.numerology.slotsPerFrame", 10))));
expectedULFrame = floor(max(0, double(ul.Slot) - 1) ./ slotsPerFrame) + 1;
assert(all(double(ul.Frame) == expectedULFrame), ...
    "Queued UL K2 grants must stamp Frame from the absolute scheduled slot, not copy the slot index.");
assert(any(logical(harq.IsRetransmission)), "Coupled-truth HARQ roundtrip must exercise a real retransmission.");
assert(~any(string(dl.Status) == "CRASH") && ~any(string(ul.Status) == "CRASH"), ...
    "Coupled-truth HARQ roundtrip must not crash data-plane waveform trials.");
assert(max(double(stage.DLCompletedFrames)) >= 1, "Coupled-truth HARQ roundtrip must advance DL frames.");
assert(max(double(stage.ULCompletedFrames)) >= 1, "Coupled-truth HARQ roundtrip must advance UL frames.");

fprintf("PASS testLLSCoupledTruthHARQRoundTrip: DL=%d UL=%d HARQ=%d.\n", ...
    height(dl), height(ul), height(harq));
ok = true;
end
