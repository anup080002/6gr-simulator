function out = runSIB1StrictMiniAnchor(runFolder, cfg)
%RUNSIB1STRICTMINIANCHOR Execute and export the AUD-015 strict mini-run.

if nargin < 1 || strlength(string(runFolder)) == 0
    runFolder = fullfile(tempdir, "sixgr_sib1_strict_mini_anchor");
end
if nargin < 2 || isempty(cfg)
    cfg = sixgr.config.defaultConfig();
end
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.phy.sib1.ssbObservationSubframes = 5;
cfg.phy.carrier.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 17));
cfg.phy.carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
cfg.phy.carrier.SubcarrierSpacing_kHz = cfg.phy.carrier.SubcarrierSpacing;
cfg.phy.carrier.NSizeGrid = double(sixgr.util.structGet(cfg, "phy.carrier.NSizeGrid", 52));
cfg.phy.sib1.coreset0Index = double(sixgr.util.structGet(cfg, "phy.sib1.coreset0Index", 0));
cfg.phy.sib1.searchSpaceZero = double(sixgr.util.structGet(cfg, "phy.sib1.searchSpaceZero", 0));

tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, "SNRdB", 35, "Seed", 1501);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, ...
    "ExpectedTxTree", tx.TxTree, ...
    "ExpectedPayloadHash", tx.SIB1PayloadHash, ...
    "ExpectedTreeHash", tx.TxTreeHash);
negatives = localRunNegatives(tx, cfg);
artifacts = sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(runFolder, tx, rx, "NegativeResults", negatives);
out = struct("Ok", logical(rx.StrictOk), "RunFolder", string(runFolder), "Tx", tx, "Rx", rx, ...
    "NegativeResults", negatives, "Artifacts", artifacts);
end

function negatives = localRunNegatives(tx, cfg)
negatives = repmat(struct(), 0, 1);
wrong = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "ReceiverRNTI", 4660, ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
wrong.NegativeTrialType = "wrong_si_rnti";
wrong.InjectedFault = "receiver_attempted_wrong_rnti_4660";
wrong.ExpectedFailureStage = "pdcch_decode_failed";
negatives = localAppendNegative(negatives, wrong);

nosig = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "nosignal", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
nosig.NegativeTrialType = "no_signal_coreset0";
nosig.InjectedFault = "zeroed_sib1_slot";
nosig.ExpectedFailureStage = "pdcch_decode_failed";
negatives = localAppendNegative(negatives, nosig);

cpdcch = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "corruptpdcch", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
cpdcch.NegativeTrialType = "corrupted_pdcch";
cpdcch.InjectedFault = "pdcch_and_dmrs_resource_elements_zeroed";
cpdcch.ExpectedFailureStage = "pdcch_decode_failed";
negatives = localAppendNegative(negatives, cpdcch);

cpdsch = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "corruptpdsch", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
cpdsch.NegativeTrialType = "corrupted_pdsch";
cpdsch.InjectedFault = "pdsch_and_dmrs_resource_elements_zeroed";
cpdsch.ExpectedFailureStage = "pdsch_dlsch_crc_failed";
negatives = localAppendNegative(negatives, cpdsch);

casn1 = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg, "FaultMode", "corruptasn1", ...
    "ExpectedTxTree", tx.TxTree, "ExpectedPayloadHash", tx.SIB1PayloadHash, "ExpectedTreeHash", tx.TxTreeHash);
casn1.NegativeTrialType = "corrupted_asn1_payload";
casn1.InjectedFault = "post_dlsch_payload_bit_flip";
casn1.ExpectedFailureStage = "sib1_asn1_decode_or_tree_match_failed";
negatives = localAppendNegative(negatives, casn1);
end

function negatives = localAppendNegative(negatives, item)
if isempty(negatives)
    negatives = item;
    return;
end
allFields = unique([fieldnames(negatives); fieldnames(item)]);
for i = 1:numel(allFields)
    f = allFields{i};
    if ~isfield(negatives, f)
        [negatives.(f)] = deal([]);
    end
    if ~isfield(item, f)
        item.(f) = [];
    end
end
negatives(end+1, 1) = orderfields(item, fieldnames(negatives)); %#ok<AGROW>
end
