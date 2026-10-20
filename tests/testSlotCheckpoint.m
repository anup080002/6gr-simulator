function ok=testSlotCheckpoint()
% Real retained CDL/RF/event owners plus explicit storage/control fixtures.
% This qualifies checkpoint mechanics, not a full connected LLS scenario.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'logs','lls_repairs',['slot_checkpoint_' char(java.util.UUID.randomUUID)]);
mkdir(root);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/shared_cdl_checkpoint.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
cfg.outputs.continuousRawIQCaptureEnabled=false; % recorder tested separately below
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),10);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
carrier=sixgr.phy.grid.makeCarrier(cfg);
fs=stream.SampleRateHz;
stop=sixgr.phy.frame.slotStartSample(carrier,1,fs);
nt=double(cfg.phy.nTxAnt);
% Use actual generated OFDM samples at the authored spatial dimensions.
grid=complex(zeros(carrier.NSizeGrid*12,carrier.SymbolsPerSlot,nt));
grid(:,3,:)=repmat(exp(1j*(0:carrier.NSizeGrid*12-1)'/7),1,1,nt);
x=nrOFDMModulate(carrier,grid);
stream.Events.enqueue('gnb_1','ofdm_fixture',sixgr.phy.waveform.WaveformChunk(x,0));
stream.Events.commitTransmissionsThrough('gnb_1',2*stop);
stream.Events.commitTransmissionsThrough('ue_1',2*stop);
stream.Events.observe('ue_1_rx:post_rf','across_checkpoint',0,2*stop);
stream.Events.advanceUntilEvent(stop);
assert(stream.Events.NextSampleIndex==stop);
rec=sixgr.truth.RuntimeTxIQStreamRecorder(root,cfg,fs);
nodes=struct('ID',"gnb_1",'Direction',"DL",'NumPorts',nt);
wave=x(1:16,:); replay=struct('Replay',struct( ...
    'RFOutputWaveformSHA256',sixgr.rf.waveformSHA256(wave)));
rec.appendBatch(nodes,{wave},replay,0,16);
state.TestRecorder=rec;
state.TestPendingGrant=struct('AbsoluteSlot',4,'HARQProcess',3,'RV',2);
state.TestSoftBuffer=[-2;3;0;9]; % explicit state-copy fixture, not decoder evidence
state.TestQueueBytes=uint8([12;4;99]);
% A real LDPC decoder's failed-attempt soft buffer must survive saving.
% This is coded-bit state qualification, not a waveform BLER population.
tb=int8(mod((1:256)',3)==0);
encoder=nrDLSCH('TargetCodeRate',.5);
setTransportBlock(encoder,tb);
decoder=nrDLSCHDecoder('TargetCodeRate',.5,'TransportBlockLength',256, ...
    'MultipleHARQProcesses',true);
[~,firstCRC]=decoder(sin((1:1024)'*1.234),'QPSK',1,0,0);
assert(firstCRC,'The saved HARQ fixture must have a real failed decode.');
state.TestDecoder=decoder;
small=fullfile(root,'small.csv'); sixgr.util.writeTextFile(small,"Slot,Value"+newline+"1,7");
large=fullfile(root,'large.bin');
localWrite(large,uint8(mod((0:1200000)',251)),'w');
% Explicit immutable-MAT storage probe, not PHY receiver measurements.
archiveRelative="air_interface/mat/receive_only_observation_"+string(repmat('a',1,64))+".mat";
archiveFile=fullfile(root,archiveRelative);
probe=rand(RandStream('mt19937ar','Seed',719201),200000,1);
sixgr.util.matSave(archiveFile,struct('StorageProbe',probe, ...
    'Source',"checkpoint_storage_fixture_not_PHY_observation"), ...
    'UseArtifactStore',false,'ForceV73',true);
archiveInfo=dir(archiveFile); assert(archiveInfo.bytes>1024*1024);
archiveHash=string(sixgr.util.sha256File(archiveFile));
source=sixgr.runtime.SlotCheckpoint.sourceIdentity();
ledgerIdentity=struct('RunId',"checkpoint_fixture",'ExecutionID',"execution_fixture", ...
    'ConfigHash',s.ConfigHash);
sixgr.runtime.RuntimeCallLedger.configure(root,ledgerIdentity);
ledgerCleanup=onCleanup(@()sixgr.runtime.RuntimeCallLedger.reset()); %#ok<NASGU>
sixgr.runtime.RuntimeCallLedger.record(mfilename,'CHECKPOINT_TEST','DL',struct('Phase','before_save'));
ledgerPrefix=sixgr.runtime.RuntimeCallLedger.snapshot();
payload=struct('RuntimeState',state,'CompletedSlot',1,'RNG',rng,'ConfigHash',s.ConfigHash);
path=sixgr.runtime.SlotCheckpoint.write(root,payload,s.toStruct(),source);
sixgr.runtime.RuntimeCallLedger.record(mfilename,'CHECKPOINT_TEST','DL',struct('Phase','after_save'));
sixgr.runtime.RuntimeCallLedger.flush();
expected=stream.Events.advanceUntilEvent(2*stop);
retry=encoder('QPSK',1,1024,2);
[expectedTB,expectedCRC]=decoder(20*(1-2*double(retry)),'QPSK',1,2,0);
assert(~expectedCRC && isequal(int8(expectedTB),tb));
rec.appendBatch(nodes,{wave},replay,16,32);
localWrite(large,uint8([8;9;10]),'a');
sixgr.util.writeTextFile(small,"Failed attempt retained,not overwritten");
[restored,receipt]=sixgr.runtime.SlotCheckpoint.read(path,s.toStruct(),"");
archived=receipt.Files(replace(string({receipt.Files.Path}),'\','/')==archiveRelative);
assert(isscalar(archived) && strlength(string(archived.Snapshot))==0 && ...
    string(archived.SHA256)==archiveHash, ...
    'Immutable receive-only archives need a verified dependency, not another full copy at every checkpoint.');
assert(~receipt.SourceChanged && ~receipt.PrimaryStudyEligible);
rs=restored.RuntimeState.SharedWaveformStream;
assert(rs.Events.ProcessorState==rs.Physical, ...
    'Restoring must preserve shared object identity, not make a second channel owner.');
actual=rs.Events.advanceUntilEvent(2*stop);
assert(isequaln(actual.Completed.Observation.readComplete(), ...
    expected.Completed.Observation.readComplete()), ...
    'CDL/RF/noise/pending-window continuation differs after restore.');
assert(isequal(restored.RuntimeState.TestSoftBuffer,state.TestSoftBuffer) && ...
    isequal(restored.RuntimeState.TestPendingGrant,state.TestPendingGrant) && ...
    isequal(restored.RuntimeState.TestQueueBytes,state.TestQueueBytes));
[restoredTB,restoredCRC]=restored.RuntimeState.TestDecoder( ...
    20*(1-2*double(retry)),'QPSK',1,2,0);
assert(isequal(restoredTB,expectedTB) && isequal(restoredCRC,expectedCRC), ...
    'A retained LDPC/HARQ decoder must continue without resetting its soft buffer.');
[restoredRoot,lineage]=sixgr.runtime.SlotCheckpoint.prepareResume(path,s.toStruct(),"",true);
assert(strcmp(restoredRoot,root) && isfolder(lineage.PreservedFailedAttempt));
assert(string(sixgr.util.sha256File(archiveFile))==archiveHash, ...
    'Resume must preserve exact immutable receiver-evidence bytes.');
sixgr.runtime.RuntimeCallLedger.reset();
ledgerIdentity.PreserveExisting=true;
sixgr.runtime.RuntimeCallLedger.configure(root,ledgerIdentity);
assert(isequaln(sixgr.runtime.RuntimeCallLedger.snapshot(),ledgerPrefix), ...
    'Slot resume must retain exactly the actual prefix, excluding later failed-attempt calls.');
localReject(@()sixgr.runtime.RuntimeCallLedger.checkpoint(root+"_other"), ...
    'sixgr:runtime:RuntimeCallLedgerCheckpointOwnerMismatch');
assert(contains(fileread(fullfile(lineage.PreservedFailedAttempt,'small.csv')),'Failed attempt') && ...
    contains(fileread(small),'1,7'));
info=dir(large); assert(info.bytes==1200001);
restored.RuntimeState.TestRecorder.appendBatch(nodes,{wave},replay,16,32);
sealed=restored.RuntimeState.TestRecorder.finalize(32,2);
assert(sealed.Ok);
different=s.toStruct(); different.simulation.random_seed=different.simulation.random_seed+1;
localReject(@()sixgr.runtime.SlotCheckpoint.read(path,different,""), ...
    'sixgr:checkpoint:ScenarioChanged');
% Alter a prefix, not the allowed post-checkpoint tail. Reject before moving.
localWrite(large,zeros(1200001,1,'uint8'),'w');
localReject(@()sixgr.runtime.SlotCheckpoint.prepareResume(path,s.toStruct(),""), ...
    'sixgr:checkpoint:ArtifactIntegrity');
assert(isfile(small),'Failed integrity validation must not move active artifacts.');
% A legacy receipt without the ledger must reject BEFORE loading or moving
% anything. Never create historical ENTER rows from decoded trial CSVs.
legacyFolder=fullfile(root,'legacy_checkpoint_fixture'); mkdir(legacyFolder);
legacyReceipt=receipt;
isLedger=replace(string({legacyReceipt.Files.Path}),'\','/')== ...
    "reports/csv/runtime_call_ledger.csv";
legacyReceipt.Files=legacyReceipt.Files(~isLedger);
sixgr.util.jsonWrite(fullfile(legacyFolder,'checkpoint.json'),legacyReceipt);
localReject(@()sixgr.runtime.SlotCheckpoint.prepareResume( ...
    fullfile(legacyFolder,'state.mat'),s.toStruct(),"",true), ...
    'sixgr:checkpoint:RuntimeCallLedgerNotCheckpointed');
assert(isfile(small),'Incomplete audit checkpoint must not move active artifacts.');
sixgr.util.jsonWrite(fullfile(root,'test_receipt.json'),struct('Ok',true, ...
    'NativeCDL_RF_ContinuationExact',true,'PendingWindowExact',true, ...
    'FailedAttemptPreserved',true,'IQAppendAfterRollback',sealed.Ok, ...
    'NativeLDPC_HARQ_RetryExact',true, ...
    'ScientificScenarioChangeRejected',true,'CorruptedPrefixRejected',true, ...
    'EvidenceScope','focused_checkpoint_mechanics_not_full_scenario_acceptance'));
disp('SLOT_CHECKPOINT_PASS'); ok=true;
end

function localWrite(path,bytes,mode)
fid=fopen(path,mode); assert(fid>=0); close=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,bytes,'uint8');
end

function localReject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
