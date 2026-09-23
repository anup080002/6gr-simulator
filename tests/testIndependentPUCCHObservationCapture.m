function ok=testIndependentPUCCHObservationCapture()
% Serialization/identity guard test; these declared samples are not RF proof.
cfg=struct('outputs',struct('rawIQCaptureEnabled',true,'saveRawWaveforms',true));
fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(zeros(11,1)));
context=sixgr.phy.pucch.UCIReportContext.fromReport(fixture.Report);
assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct( ...
    'ObservationID',"capture_fixture",'ResourceID',fixture.Assignment.Resource.ID, ...
    'RNTI',fixture.Report.Data.RNTI,'AbsoluteSlot0',0, ...
    'Source',"declared_capture_unit_fixture",'TimingSource',"received_PUCCH_DMRS"), ...
    fixture.RRCContext,context);
h=struct('Assignment',assignment,'Context',context,'UEIndex',1,'ServingCell',1);
rx=struct('AssignmentDigest',assignment.Digest,'ReportContextDigest',context.Digest, ...
    'ReceiverObservationStartSample',100,'ReceiverObservationEndSampleExclusive',117, ...
    'ReceiverObservationSampleRateHz',7680000, ...
    'EvidenceClass',"declared_capture_unit_fixture_not_physical_detection");
x=complex(single(reshape(1:34,17,2)),single(reshape(35:68,17,2)));
ids=["gnb_1_rx:pre_rf","gnb_1_rx:post_rf","ue_1:tx"];
planes=struct('ReceiverID',{},'Observation',{});
for k=1:3
    obs=sixgr.phy.waveform.WaveformObservationBuffer(100,117,7680000,2);
    samples=x*single(k);
    if k==3, samples(:)=0; end % Absence must not prevent a receiver capture.
    obs.append(sixgr.phy.waveform.WaveformChunk(samples,100),7680000);
    planes(k)=struct('ReceiverID',ids(k),'Observation',obs);
end
% Digital gain compensation can make the actual receiver input differ from
% the native post-RF audit plane. Retain both, without rerunning RF processing.
receiver=sixgr.phy.waveform.WaveformObservationBuffer(100,117,7680000,2);
receiver.append(sixgr.phy.waveform.WaveformChunk(x/single(2),100),7680000);
folder=tempname(fullfile(pwd,'logs'));
target=sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,planes,rx,receiver);
assert(isfile(target),'test:CapturePersistenceRequired','Run with persistence enabled.');
saved=readCapture(target); c=saved.capture;
assert(isequal(c.RXBeforeRF,x) && isequal(c.RXAfterRF,x*single(2)) && ...
    isa(c.RXAfterRF,'single') && all(c.TXAfterRFAudit==0,'all') && ...
    isequal(c.ReceiverInputSamples,x/single(2)));
assert(c.StartSample==100 && c.EndSampleExclusive==117 && c.SampleRateHz==7680000);
assert(c.Assignment.Digest==assignment.Digest && c.Context.Digest==context.Digest && ...
    isequaln(c.ReceivedResult,rx) && isequaln(c.Config,cfg));
assert(~isfield(c,'Prepared') && ~isfield(c,'WaveformAmplitudeUnit') && ~c.QualificationPassed);
reject(@()sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,planes,rx,receiver), ...
    'sixgr:truth:DuplicateULControlCapture');
bad=rx; bad.ReportContextDigest="wrong";
reject(@()sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,planes,bad,receiver), ...
    'sixgr:truth:PUCCHCaptureIdentityMismatch');
reject(@()sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,planes(1:2),rx,receiver), ...
    'sixgr:truth:MissingPUCCHCapturePlane');
bad=planes; bad(2)=bad(1);
reject(@()sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,bad,rx,receiver), ...
    'sixgr:truth:MissingPUCCHCapturePlane');
bad=planes; bad(2).Observation=sixgr.phy.waveform.WaveformObservationBuffer(100,117,7680000,2);
reject(@()sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,bad,rx,receiver), ...
    'WAVEFORM:IncompleteObservation');
wrongClock=sixgr.phy.waveform.WaveformObservationBuffer(101,118,7680000,2);
wrongClock.append(sixgr.phy.waveform.WaveformChunk(x,101),7680000);
reject(@()sixgr.truth.exportIndependentPUCCHObservation(folder,cfg,h,planes,rx,wrongClock), ...
    'sixgr:truth:PUCCHCaptureClockMismatch');
% Timing-advanced TX audit has its own interval; never force RX alignment.
shifted=planes; shifted(3).Observation=wrongClock;
target=sixgr.truth.exportIndependentPUCCHObservation(folder+"_shifted_tx",cfg,h,shifted,rx,receiver);
saved=readCapture(target);
assert(saved.capture.TXStartSample==101 && saved.capture.StartSample==100 && ...
    isequal(saved.capture.TXAfterRFAudit,x));
disabled=cfg; disabled.outputs.rawIQCaptureEnabled=false;
assert(sixgr.truth.exportIndependentPUCCHObservation(folder,disabled,struct(),[],[])=="");
disabled=cfg; disabled.outputs.saveRawWaveforms=false;
assert(sixgr.truth.exportIndependentPUCCHObservation(folder,disabled,struct(),[],[])=="");
fprintf('INDEPENDENT_PUCCH_CAPTURE_PASS serialization_only=1 qualification=0 folder=%s\n',folder);
ok=true;
end
function reject(action,id)
try, action(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s.',id,err.identifier); return;
end
error('test:MissingRejection','Expected %s.',id);
end
function saved=readCapture(target)
% Windows HDF5 loading can reject a valid published path longer than MAX_PATH.
% Load a byte-identical short local readback; keep the primary capture intact.
readback=string(tempname())+".mat";
cleanup=onCleanup(@()delete(readback)); %#ok<NASGU>
copyfile(target,readback);
assert(sixgr.util.sha256File(target)==sixgr.util.sha256File(readback));
saved=load(readback,'capture');
end
