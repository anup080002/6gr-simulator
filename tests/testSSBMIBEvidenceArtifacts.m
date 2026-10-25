function ok=testSSBMIBEvidenceArtifacts()
% Original native SSB-only TX/RX -> real CSV writer. Unit-link component only.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
folder=fullfile(pwd,'results','validation','ssb_mib_evidence',char(java.util.UUID.randomUUID()));
cfg=localConfig();
tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'SNRdB',Inf,'Content','SSB_MIB');
o=sixgr.phy.waveform.WaveformObservationBuffer(tx.BroadcastStartSample, ...
    tx.BroadcastStartSample+size(tx.Waveform,1),tx.SampleRateHz,size(tx.Waveform,2));
o.append(sixgr.phy.waveform.WaveformChunk(tx.Waveform,tx.BroadcastStartSample),tx.SampleRateHz);
originalSHA=o.sampleHash();
rec=sixgr.phy.broadcast.recoverSIB1FromWaveform(o,cfg,'RecoveryScope','SSB_MIB');
assert(rec.BCHCrcPass && rec.MIBDecoded && rec.SSBMIBComplete && ~rec.SIB1ReceptionAttempted, ...
    'test:SSBMIBActualDecode','Original MIB-only receiver failed: %s / %s',rec.Status,rec.FailureReason);
before=rec;
paths=sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(folder,tx,rec);
T=sixgr.util.csvReadTable(paths.SSBMIBRecoveryTrialsCSV,'TextType','string');
P=sixgr.util.csvReadTable(paths.PBCHRecoveryTrialsCSV,'TextType','string');
M=sixgr.util.csvReadTable(paths.MIBFieldEvidenceCSV,'TextType','string');
stages=sixgr.util.csvReadTable(paths.WaveformDecodeTraceCSV,'TextType','string');
assert(height(T)==1 && T.RecoveryScope=="SSB_MIB" && T.WaveformContent=="ssb_mib_only");
assert(T.BCHCrcPass==rec.BCHCrcPass && T.MIBDecoded==rec.MIBDecoded && ...
    T.PBCHStrictReceiverEvidenceOk==rec.PBCHStrictReceiverEvidenceOk && T.Status==rec.Status);
for name=["DecodedKSSB","MIBKSSBLow4","PBCHKSSBMSB","PBCHKSSBHighContribution", ...
        "MIBKSSBSubcarrierOffset","CandidateIdentityConsistent","BCHCRCValid"]
    assert(isequaln(double(T.(name)),double(rec.(name))) && isequaln(double(P.(name)),double(rec.(name))));
end
assert(T.KSSBContractVersion==rec.KSSBContractVersion && ...
    P.BCHTransportBlockHash==rec.BCHTransportBlockHash);
assert(T.MIBPDCCHConfigSIB1Recovered==rec.MIBPDCCHConfigSIB1Recovered && ...
    M.NumericValue(M.MIBEvidenceField=="pdcch-ConfigSIB1")==rec.MIBPDCCHConfigSIB1Recovered);
assert(height(stages)==3 && all(stages.Attempted==1) && all(stages.StagePass==1) && ...
    ~any(contains(stages.StageName,["SIB1","DCI","PDSCH"])));
assert(~any(ismember({'DCICrcPass','DLSCHCrcPass','StrictOk','SIB1TreeEqual'},T.Properties.VariableNames)));
assert(~any(isfield(paths,{'RecoveryTrialsCSV','PDCCHCandidatesCSV','ASN1RoundtripCSV','ConformanceSummaryCSV'})));
files=dir(fullfile(folder,'**','*')); names=string({files(~[files.isdir]).name});
assert(~any(startsWith(names,'sib1_')) && ~any(names=="pbch_mib_sib1_trials.csv"));
bad=tx; bad.SIB1Transmissions=struct('declared',true);
localReject(@()sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(folder,bad,rec), ...
    'sixgr:phy:broadcast:EvidenceContentMismatch');
bad=tx; bad=rmfield(bad,'Content');
localReject(@()sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(folder,bad,rec), ...
    'sixgr:phy:broadcast:EvidenceContentMismatch');
bad=rec; bad.RecoveryScope="SSB_MIB_SIB1";
localReject(@()sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(folder,tx,bad), ...
    'sixgr:phy:broadcast:EvidenceRecoveryScopeMismatch');
bad=rec; bad.SIB1ReceptionAttempted=true;
localReject(@()sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(folder,tx,bad), ...
    'sixgr:phy:broadcast:EvidenceRecoveryScopeMismatch');
bad=rec; bad.BCHCrcPass=1;
localReject(@()sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(folder,tx,bad), ...
    'sixgr:phy:broadcast:EvidenceReceiverFlag');
assert(isequaln(before,rec) && o.sampleHash()==originalSHA);
fprintf('SSB_MIB_EVIDENCE_PASS actual_native_unit_link_no_SI %s\n',folder);
ok=true;
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig(); cfg.run.strictMode=true;
cfg.phy.sib1.enable=true; cfg.phy.carrier.NCellID=17;
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.carrier.NSizeGrid=51; cfg.phy.channelBandwidth_MHz=20;
cfg.frequency.bandwidth_hz=20e6; cfg.channel.bandwidth_Hz=20e6;
cfg.phy.ssb.NCRBSSB=30; cfg.phy.ssb.KSSB=0;
cfg.phy.ssb.periodicity_ms=10; cfg.phy.ssb.period_ms=10;
cfg.phy.ssb.activeBitmap=logical([1 0 0 0 0 0 0 0]);
cfg.phy.ssb.runtimeSSBIndex=0;
cfg.phy.sib1.coreset0Index=0; cfg.phy.sib1.searchSpaceZero=4;
cfg.phy.mib.pdcchConfigSIB1=4; cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.sync.fineCFOEnabled=true;
end

function localReject(f,id)
try, f(); catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
