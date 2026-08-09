function ok = testLLSHARQGrantReplayTBConsistency()
%TESTLLSHARQGRANTREPLAYTBCONSISTENCY Ensure HARQ replay preserves original TBS-driving grant.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.run.strictMode = false;
cfg.run.noProxyTruthContract = false;
cfg.run.pdschExecutionProfile = "scheduler_truth";
cfg.run.puschExecutionProfile = "scheduler_truth";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.snr_dB = 18;
cfg.channel.bandwidth_Hz = 5e6;
cfg.phy.frameStructure.BandwidthHz = 5e6;
cfg.phy.carrier.NSizeGrid = 11;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.channel.nTxAnt = 1;
cfg.channel.nRxAnt = 1;
cfg.channel.dl.nTxAnt = 1;
cfg.channel.dl.nRxAnt = 1;
cfg.channel.ul.nTxAnt = 1;
cfg.channel.ul.nRxAnt = 1;
cfg.scenario.bs.nTxAnt = 1;
cfg.scenario.bs.nRxAnt = 1;
cfg.scenario.ue.nTxAnt = 1;
cfg.scenario.ue.nRxAnt = 1;
cfg.phy.bsArray = [1 1 1];
cfg.phy.ueArray = [1 1 1];
cfg.antenna.bs.numElements = 1;
cfg.antenna.bs.numPorts = 1;
cfg.antenna.bs.numRFChains = 1;
cfg.antenna.bs.hybridBeamformingEnabled = false;
cfg.antenna.ue.numElements = 1;
cfg.antenna.ue.numPorts = 1;
cfg.antenna.ue.numRFChains = 1;
cfg.antenna.ue.hybridBeamformingEnabled = false;
cfg.rf.bs.hybridBeamformingEnabled = false;
cfg.rf.ue.hybridBeamformingEnabled = false;
cfg.phy.beamManagement.hybridBeamformingEnabled = false;
cfg.mimo.hybrid_beamforming_flag = false;
cfg.phy.pdsch.executionProfile = "scheduler_truth";
cfg.phy.pusch.executionProfile = "scheduler_truth";
% Isolated calibration still requires an explicit production resource
% allocation; the PHY must not manufacture a full-slot TDRA.
cfg.phy.pdsch.symbolAllocation = [2 10];
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pdsch.prbSet = 0:9;
cfg.phy.pdsch.nPRB = 10;
cfg.phy.pusch.symbolAllocation = [0 14];
cfg.phy.pusch.mappingType = "A";
cfg.phy.pusch.prbSet = 0:9;
cfg.phy.pusch.nPRB = 10;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pusch.enablePTRS = false;
cfg.phy.ptrs.enable = false;
cfg.phy.csirs.enable = false;
cfg.phy.trs.enable = false;
cfg.phy.pdsch.modulation = "QPSK";
cfg.phy.pdsch.codeRate = 120/1024;
cfg.phy.pdsch.mcsTable = "qam256_table2";
cfg.phy.pdsch.mcsIndex = 0;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.nPorts = 1;
cfg.phy.pdsch.numRFChains = 1;
cfg.phy.pdsch.hybridBeamformingEnabled = false;
cfg.phy.pdsch.precoding.matrix = [];
cfg.phy.pdsch.precodingMatrix = [];
cfg.phy.pdsch.W = [];
cfg.phy.pdsch.RNTI = 1001;
cfg.phy.pdsch.equalizer = "MMSE";
cfg.phy.pusch.modulation = "QPSK";
cfg.phy.pusch.codeRate = 120/1024;
cfg.phy.pusch.mcsTable = "qam256_table2";
cfg.phy.pusch.mcsIndex = 0;
cfg.phy.pusch.nLayers = 1;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.numPorts = 1;
cfg.phy.pusch.nPorts = 1;
cfg.phy.pusch.numRFChains = 1;
cfg.phy.pusch.hybridBeamformingEnabled = false;
cfg.phy.pusch.RNTI = 1001;
cfg.phy.pusch.transformPrecoding = true;
cfg.phy.pusch.powerControl.enabled = false;
cfg.phy.pusch.equalizer = "MMSE";
cfg.phy.channelEstimation.method = "LS";
mcsContext = struct( ...
    "UECapability1024QAM", false, ...
    "RRCEnabled1024QAM", false, ...
    "DCIEnabled1024QAM", false, ...
    "DeploymentAllows1024QAM", false, ...
    "FrequencyRangeAllows1024QAM", false, ...
    "BandAllows1024QAM", false, ...
    "FrequencyRange", "FR1", ...
    "OperatingBand", "n78", ...
    "DeploymentClass", "harq_replay_calibration");
cfg.phy.pdsch.mcsContext = mcsContext;
cfg.phy.pusch.mcsContext = mcsContext;
cfg = withCanonicalSchedulerTiming(cfg);

initialDLGrant = localBindSchedulerTruthGrant( ...
    sixgr.link.resolveWaveformGrant(cfg, "DL", 0), "DL");
initialDLGrant = localBindSameWaveformProtocolFixture(initialDLGrant, "DL");
baseDL = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 1, "SNR_dB", 18, ...
    "GrantSnapshot", initialDLGrant);
localAssertAllocationEvidence(baseDL.TrialTable, initialDLGrant, "DL base");
assert(~isempty(baseDL.HARQ) && isfield(baseDL.HARQ, "TransportBlockBits"), ...
    "DL base run must return HARQ transport bits. %s", ...
    localDescribeResult(baseDL));
assert(isfield(baseDL.HARQ, "HARQTBContext") || isfield(baseDL.HARQ, "TransportBlockContext"), ...
    "DL base run must return a HARQ TB context.");
dlBits = int8(baseDL.HARQ.TransportBlockBits(:));
dlGrant = baseDL.HARQ.GrantSnapshot;
assert(double(dlGrant.NumLogicalPorts) == 1 && ...
    double(dlGrant.NumRFChains) == 1, ...
    "DL HARQ snapshot must publish the logical-port and RF-chain architecture actually used by PDSCH_Tx.");
localAssertSameWaveformProtocolBindingPreserved( ...
    dlGrant, initialDLGrant, "DL first transmission");
assert(~isempty(dlBits), "DL base run must emit a non-empty TB.");
dlGrant = localRemoveLegacySymbolAllocation(dlGrant);

cfgDLReplay = cfg;
cfgDLReplay.phy.pdsch.mcsIndex = 27;
cfgDLReplay.phy.pdsch.modulation = "64QAM";
cfgDLReplay.phy.pdsch.codeRate = 0.92;
cfgDLReplay.phy.pdsch.nPRB = 10;
cfgDLReplay.phy.pdsch.prbSet = 0:9;
dlReplay = sixgr.link.runDLPDSCHThroughput(cfgDLReplay, "NumFrames", 1, "SNR_dB", 18, ...
    "TransportBlockBits", dlBits, "RV", 2, ...
    "HARQContext", struct("IsRetransmission", true), "GrantSnapshot", dlGrant);
localAssertAllocationEvidence(dlReplay.TrialTable, dlGrant, "DL replay");
assert(~any(string(dlReplay.TrialTable.Status) == "CRASH"), "DL HARQ replay must not crash after config drift.");
assert(all(double(dlReplay.TrialTable.TBSize_bits) == numel(dlBits)), "DL HARQ replay must preserve original TB size.");
assert(all(double(dlReplay.TrialTable.OriginalTBSBits) == numel(dlBits)), "DL HARQ replay must report the original TBS.");
assert(all(double(dlReplay.TrialTable.CurrentTBSBits) == numel(dlBits)), "DL HARQ replay must keep current TBS aligned to the original TB.");
assert(all(strlength(string(dlReplay.TrialTable.CodeBlockLayoutHash)) > 0), "DL HARQ replay must expose a code-block layout hash.");
assert(all(contains(lower(string(dlReplay.TrialTable.HARQContextStatus)), "validated")), ...
    "DL HARQ replay must record a validated HARQ context status.");
assert(all(string(dlReplay.TrialTable.Modulation) == string(sixgr.util.structGet(dlGrant, "Modulation", ""))), ...
    "DL HARQ replay must report the original modulation, not drifted config.");
localAssertSameWaveformProtocolBindingPreserved( ...
    dlReplay.HARQ.GrantSnapshot, dlGrant, "DL retransmission");

initialULGrant = localBindSchedulerTruthGrant( ...
    sixgr.link.resolveWaveformGrant(cfg, "UL", 0), "UL");
initialULGrant = localBindSameWaveformProtocolFixture(initialULGrant, "UL");
baseUL = sixgr.link.runULPUSCHThroughput(cfg, "NumFrames", 1, "SNR_dB", 18, ...
    "GrantSnapshot", initialULGrant);
localAssertAllocationEvidence(baseUL.TrialTable, initialULGrant, "UL base");
localAssertULDecodedPDCCHAuthority(baseUL.TrialTable);
assert(~isempty(baseUL.HARQ) && isfield(baseUL.HARQ, "TransportBlockBits"), ...
    "UL base run must return HARQ transport bits. %s", ...
    localDescribeResult(baseUL));
assert(isfield(baseUL.HARQ, "HARQTBContext") || isfield(baseUL.HARQ, "TransportBlockContext"), ...
    "UL base run must return a HARQ TB context.");
ulBits = int8(baseUL.HARQ.TransportBlockBits(:));
ulGrant = baseUL.HARQ.GrantSnapshot;
assert(double(ulGrant.NumLogicalPorts) == 1 && ...
    double(ulGrant.NumRFChains) == 1, ...
    "UL HARQ snapshot must publish the logical-port and RF-chain architecture actually used by PUSCH_Tx.");
localAssertSameWaveformProtocolBindingPreserved( ...
    ulGrant, initialULGrant, "UL first transmission");
assert(~isempty(ulBits), "UL base run must emit a non-empty TB.");
ulGrant = localRemoveLegacySymbolAllocation(ulGrant);

cfgULReplay = cfg;
cfgULReplay.phy.pusch.mcsIndex = 27;
cfgULReplay.phy.pusch.modulation = "64QAM";
cfgULReplay.phy.pusch.codeRate = 0.92;
cfgULReplay.phy.pusch.nPRB = 10;
cfgULReplay.phy.pusch.prbSet = 0:9;
ulReplay = sixgr.link.runULPUSCHThroughput(cfgULReplay, "NumFrames", 1, "SNR_dB", 18, ...
    "TransportBlockBits", ulBits, "RV", 2, ...
    "HARQContext", struct("IsRetransmission", true), "GrantSnapshot", ulGrant);
localAssertAllocationEvidence(ulReplay.TrialTable, ulGrant, "UL replay");
assert(~any(string(ulReplay.TrialTable.Status) == "CRASH"), "UL HARQ replay must not crash after config drift.");
assert(all(double(ulReplay.TrialTable.TBSize_bits) == numel(ulBits)), "UL HARQ replay must preserve original TB size.");
assert(all(double(ulReplay.TrialTable.OriginalTBSBits) == numel(ulBits)), "UL HARQ replay must report the original TBS.");
assert(all(double(ulReplay.TrialTable.CurrentTBSBits) == numel(ulBits)), "UL HARQ replay must keep current TBS aligned to the original TB.");
assert(all(strlength(string(ulReplay.TrialTable.CodeBlockLayoutHash)) > 0), "UL HARQ replay must expose a code-block layout hash.");
assert(all(contains(lower(string(ulReplay.TrialTable.HARQContextStatus)), "validated")), ...
    "UL HARQ replay must record a validated HARQ context status.");
assert(all(string(ulReplay.TrialTable.Modulation) == string(sixgr.util.structGet(ulGrant, "Modulation", ""))), ...
    "UL HARQ replay must report the original modulation, not drifted config.");
localAssertSameWaveformProtocolBindingPreserved( ...
    ulReplay.HARQ.GrantSnapshot, ulGrant, "UL retransmission");

ok = true;
end

function localAssertAllocationEvidence(trialT, grant, label)
required = ["PRBStart","AllocatedPRBCount","PRBCount", ...
    "SymbolStart","NumSymbols"];
assert(istable(trialT) && height(trialT) > 0 && ...
    all(ismember(required, string(trialT.Properties.VariableNames))), ...
    "%s must export exact PRB and symbol allocation scalars.", label);
prbSet = double(sixgr.util.structGet(grant, "PRBSet", []));
symbolAllocation = double(sixgr.util.structGet(grant, ...
    "SymbolAllocation", sixgr.util.structGet(grant, ...
    "PHYGrant.ResourceAllocation.SymbolAllocation", [])));
assert(~isempty(prbSet) && numel(symbolAllocation) >= 2 && ...
    all(double(trialT.PRBStart) == min(prbSet)) && ...
    all(double(trialT.AllocatedPRBCount) == numel(prbSet)) && ...
    all(double(trialT.PRBCount) == numel(prbSet)) && ...
    all(double(trialT.SymbolStart) == symbolAllocation(1)) && ...
    all(double(trialT.NumSymbols) == symbolAllocation(2)), ...
    "%s allocation evidence must match the frozen scheduler grant exactly.", label);
end

function grant = localRemoveLegacySymbolAllocation(grant)
requiredFrozen = double(sixgr.util.structGet(grant, ...
    "PHYGrant.ResourceAllocation.SymbolAllocation", []));
assert(numel(requiredFrozen) >= 2, ...
    "The production HARQ snapshot must contain frozen symbol allocation.");
legacyFields = intersect(fieldnames(grant), ...
    {'SymbolAllocation','SymbolStart','NumSymbols'});
if ~isempty(legacyFields)
    grant = rmfield(grant, legacyFields);
end
end

function grant = localBindSchedulerTruthGrant(grant, direction)
% Unit fixture for the HARQ replay contract. The grant and DCI themselves
% are produced by the production exact-feasibility finalizer; this helper
% supplies the successful control-decode binding normally contributed by
% CoupledTruthRuntime before waveform dispatch.
assert(isstruct(grant) && logical(sixgr.util.structGet(grant, ...
    "ExactPHYFeasibilityChecked", false)) && ...
    logical(sixgr.util.structGet(grant, "ExactPHYFeasible", false)), ...
    "%s unit fixture requires an exactly feasible production grant.", direction);
dci = sixgr.util.structGet(grant, "DCI", struct());
assert(isstruct(dci) && logical(sixgr.util.structGet(dci, ...
    "BitExactPDCCHPayload", false)), ...
    "%s unit fixture requires a bit-exact production DCI payload.", direction);
bindingHash = "harq_replay_unit_" + lower(string(direction)) + "_binding";
grant.ControlDecodeOk = true;
grant.PDCCHGrantBindingRequired = true;
grant.PDCCHGrantBindingOk = true;
grant.PDCCHGrantBindingStatus = "pass";
grant.PDCCHGrantDCIId = "harq-replay-unit-" + lower(string(direction));
grant.PDCCHGrantDCIFieldsHash = bindingHash;
grant.PDCCHGrantFieldsHash = bindingHash;
grant.DCICrcPass = true;
grant.PDCCHPayloadMatch = true;
grant.PDCCHCausalGrantDecodeOk = true;
grant.PDCCHMissedDetection = false;
grant.PDCCHFalseAlarm = false;
grant.GrantValid = true;
grant.NegativeExpectedOk = false;
grant.PDCCHBlindSearchEnabled = true;
grant.PDCCHREGMappingAvailable = true;
grant.PDCCHControlFailureReason = "pdcch_dci_crc_and_payload_match";
grant.PDCCHControlEvidenceSource = "pdcch_waveform_dci_crc_and_payload_match";
grant.ControlDecodeSource = "pdcch_waveform_dci_crc_and_payload_match";
end

function grant = localBindSameWaveformProtocolFixture(grant, direction)
% Model the exact immutable binding installed by the production protocol
% bridge before the waveform is dispatched. HARQ snapshot construction
% must retain every byte-lineage field; regenerating it on retransmission
% is forbidden.
direction = upper(string(direction));
token = lower(direction);
grant.TransportBlockId = char("protocol-harq-" + token + "-tb-1");
grant.ProtocolPayloadSameWaveformTruth = true;
grant.ProtocolPacketId = char("protocol-harq-" + token + "-packet-1");
grant.ProtocolApplicationPacketId = char("protocol-harq-" + token + "-application-1");
grant.ProtocolFragmentId = char("protocol-harq-" + token + "-fragment-1");
grant.ProtocolSegmentIndex = 1;
grant.ProtocolPayloadOffsetBits = 0;
grant.ProtocolPayloadBits = 8;
grant.ProtocolPayloadSHA256 = repmat('1', 1, 64);
grant.ProtocolSDAPHeaderHex = '09';
grant.ProtocolPDCPHeaderHex = '800000';
grant.ProtocolRLCHeaderHex = '800000';
grant.ProtocolEncodedRLC_SHA256 = repmat('2', 1, 64);
grant.ProtocolMACSHA256 = repmat('3', 1, 64);
grant.ProtocolMACPDUBytes = floor(double(sixgr.util.structGet( ...
    grant, "TBSBits", sixgr.util.structGet(grant, "TransportBlockSize", 0))) / 8);
grant.ProtocolMACPaddingBytes = max(0, grant.ProtocolMACPDUBytes - 8);
grant.ProtocolEvidenceSource = 'same_waveform_protocol_bridge';
end

function localAssertSameWaveformProtocolBindingPreserved(actual, expected, label)
fields = ["TransportBlockId","ProtocolPayloadSameWaveformTruth", ...
    "ProtocolPacketId","ProtocolApplicationPacketId","ProtocolFragmentId", ...
    "ProtocolSegmentIndex","ProtocolPayloadOffsetBits","ProtocolPayloadBits", ...
    "ProtocolPayloadSHA256","ProtocolSDAPHeaderHex","ProtocolPDCPHeaderHex", ...
    "ProtocolRLCHeaderHex","ProtocolEncodedRLC_SHA256","ProtocolMACSHA256", ...
    "ProtocolMACPDUBytes","ProtocolMACPaddingBytes","ProtocolEvidenceSource"];
for field = fields
    name = char(field);
    assert(isfield(actual, name), ...
        "%s must retain protocol field %s in its HARQ snapshot.", label, name);
    assert(isequaln(actual.(name), expected.(name)), ...
        "%s changed immutable protocol field %s.", label, name);
end
end

function localAssertULDecodedPDCCHAuthority(T)
required = ["DCICrcPass","PDCCHPayloadMatch", ...
    "PDCCHCausalGrantDecodeOk","PDCCHMissedDetection", ...
    "PDCCHFalseAlarm","GrantValid","PDCCHControlEvidenceSource", ...
    "ControlDecodeSource"];
assert(istable(T) && height(T) == 1 && ...
    all(ismember(required, string(T.Properties.VariableNames))), ...
    "UL trial output must expose the same decoded-PDCCH authority fields as DL.");
assert(logical(T.DCICrcPass(1)) && logical(T.PDCCHPayloadMatch(1)) && ...
    logical(T.PDCCHCausalGrantDecodeOk(1)) && logical(T.GrantValid(1)) && ...
    ~logical(T.PDCCHMissedDetection(1)) && ~logical(T.PDCCHFalseAlarm(1)), ...
    "UL K2 execution must preserve successful decoded-PDCCH authority from the frozen grant.");
assert(string(T.PDCCHControlEvidenceSource(1)) == ...
        "pdcch_waveform_dci_crc_and_payload_match" && ...
    string(T.ControlDecodeSource(1)) == ...
        "pdcch_waveform_dci_crc_and_payload_match", ...
    "UL K2 execution must preserve its waveform control-evidence source.");
end

function text = localDescribeResult(result)
parts = "Ok=" + string(sixgr.util.structGet(result, "Ok", false)) + ...
    ", Skipped=" + string(sixgr.util.structGet(result, "Skipped", false)) + ...
    ", Notes=" + string(sixgr.util.structGet(result, "Notes", ""));
trial = sixgr.util.structGet(result, "TrialTable", table());
if istable(trial) && height(trial) > 0
    fields = intersect(["Status","FailureReason","ExceptionIdentifier", ...
        "ExceptionMessage"], string(trial.Properties.VariableNames), "stable");
    for index = 1:numel(fields)
        value = trial.(fields(index));
        parts = parts + ", " + fields(index) + "=" + string(value(1));
    end
end
text = char(parts);
end
