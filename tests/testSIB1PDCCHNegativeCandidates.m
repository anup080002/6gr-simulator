function ok = testSIB1PDCCHNegativeCandidates()
%TESTSIB1PDCCHNEGATIVECANDIDATES Wrong RNTI/no-signal/corrupt PDCCH fail.

setup6GRSimToolkit("Verbose", false);
if exist("nrWaveformGenerator", "file") ~= 2
    ok = true;
    return;
end
cfg = localCfg();
[supported, ~] = sixgr.phy.broadcast.siRNTIWaveformSupported();
if ~supported
    ok = true;
    return;
end
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
wrong = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "ReceiverRNTI", 4660);
assert(~logical(wrong.StrictOk) && double(wrong.WrongRNTIRejectCount) > 0, "Wrong SI-RNTI attempt must be rejected.");
nosig = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "nosignal");
assert(~logical(nosig.StrictOk) && double(nosig.NoSignalRejectCount) > 0, "No-signal CORESET must not decode DCI.");
corrupt = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "corruptpdcch");
assert(~logical(corrupt.StrictOk), "Corrupted PDCCH must not produce strict SIB1 success.");
assert(wrong.SIB1ReceptionAttempted && nosig.SIB1ReceptionAttempted && ...
    corrupt.SIB1ReceptionAttempted && wrong.SIB1ObservationComplete && ...
    nosig.SIB1ObservationComplete && corrupt.SIB1ObservationComplete, ...
    'Observed negative SI trials must remain actual receiver attempts.');

% A completed buffer can still end one sample before the decoded SI slot.
% Retain PBCH success, but neither invent SI samples nor attempt its CRC.
last=nosig.SIB1ObservationEndSampleExclusive;
partial=sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform(1:last-1,:),cfg,'CandidateSSBIndex',nosig.SSBIndex);
assert(partial.BCHCrcPass && partial.MIBDecoded && ~partial.StrictOk && ...
    ~partial.Crash && ~partial.SIB1ReceptionAttempted && ...
    ~partial.SIB1ObservationComplete && partial.PDCCHCandidatesAttempted==0 && ...
    partial.SIB1ObservationStatus=="incomplete_capture" && ...
    partial.SIB1AvailableCaptureSamples==last-1 && ...
    partial.SIB1ObservationEndSampleExclusive==last);
root=tempname(fullfile(pwd,'logs')); mkdir(root);
artifacts=sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(root,tx,partial);
trials=sixgr.util.csvReadTable(artifacts.RecoveryTrialsCSV,'TextType','string');
candidates=sixgr.util.csvReadTable(artifacts.PDCCHCandidatesCSV,'TextType','string');
assert(height(trials)==1 && ~trials.SIB1ReceptionAttempted && ...
    ~trials.SIB1ObservationComplete && trials.SIB1ObservationStatus=="incomplete_capture");
assert(isempty(candidates) && artifacts.RowCounts.Candidates==0, ...
    'Export must not synthesize a candidate from an unattempted SI decode.');
ok = true;
end

function cfg = localCfg()
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.carrier.NCellID = 17;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.carrier.SubcarrierSpacing_kHz = 30;
cfg.phy.carrier.NSizeGrid = 51;
cfg.phy.channelBandwidth_MHz = 20;
cfg.frequency.bandwidth_hz = 20e6;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",3);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0);
cfg.phy.sib1.coreset0Index = 0;
cfg.phy.sib1.searchSpaceZero = 0;
end
