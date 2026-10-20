function ok=testPUCCHHARQObservationEvidence()
% Actual component waveform plus receiver-evidence negative cases. This is
% not H4 fading/RF detector qualification or connected HARQ lineage evidence.
setup6GRSimToolkit('Verbose',false);
fixture=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(ones(20,1)), ...
    'NSizeGrid',273,'SCS',30,'SimultaneousHARQACKCSI',true);
trial=sixgr.link.runPUCCHWaveformTrial(fixture.Carrier, ...
    'Assignment',fixture.Assignment,'Report',fixture.Report, ...
    'ReceiverContext',fixture.Context,'Carrier',fixture.Carrier,'SNR_dB',35,'Seed',812);
assert(trial.Ok && trial.DecodedBits(1)==1);
assert(~trial.AckObserved, ...
    'test:CSIBitMislabelledACK','A decoded CSI bit must never be exported as HARQ ACK.');
assert(~trial.AckObservedValid && ~trial.HARQObservationApplicable && ...
    trial.HARQObservationStatus=="not_applicable_no_harq" && ...
    trial.DecodedHARQBitCount==0);
stage=sixgr.link.pucchReceiverStageEvidence(trial.Receiver,fixture.Assignment);
assert(~stage.AckObservedValid && stage.HARQObservationStatus==trial.HARQObservationStatus && ...
    stage.DecodedHARQBitCount==0, ...
    'Live and receive-only runtime writers must preserve typed HARQ applicability.');
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.outerLoopFlag=true;
cfg.phy.linkAdaptation.deltaMCSPolicy='olla';
[state,event]=sixgr.link.updateOLLAStateFromHARQFeedback(cfg,"DL",trial);
assert(~event.Eligible && ~event.FeedbackKnown && state.OLLAUpdateCount==0, ...
    'A physically decoded CSI-only CRC must not update HARQ OLLA.');

% All receiver decisions below use schema plus decoded fields only, never
% expected TX values. Even an incorrect decoded ACK remains an observation.
context=localContext(1,1,10);
rx=struct('ReceiverUsable',true,'DTX',false,'CRCApplicable',true,'CRCPassed',true, ...
    'DecodedFields',struct('HARQACK',int8(1),'SR',int8(0),'CSIPart1',int8(zeros(10,1))));
e=sixgr.phy.pucch.harqObservationEvidence(context,rx);
assert(e.HARQObservationValid && e.AckObservedValid && e.AckObserved && ...
    e.ObservedHARQACKBitCount==1 && e.ObservedHARQNACKBitCount==0);
rx.DecodedFields.HARQACK=int8(0);
e=sixgr.phy.pucch.harqObservationEvidence(context,rx);
assert(e.AckObservedValid && ~e.AckObserved && e.ObservedHARQNACKBitCount==1);
rx.CRCApplicable=false; rx.CRCPassed=false;
e=sixgr.phy.pucch.harqObservationEvidence(context,rx);
assert(e.AckObservedValid,'A non-applicable CRC must not erase a decoded NACK.');
rx.CRCApplicable=true; rx.DecodedFields.HARQACK=int8(1);
e=sixgr.phy.pucch.harqObservationEvidence(context,rx);
assert(~e.AckObservedValid && ~e.AckObserved && e.HARQObservationStatus=="crc_failed" && ...
    e.DecodedHARQBitVector=="1" && isnan(e.ObservedHARQACKBitCount));
rx.CRCPassed=true; rx.DTX=true;
e=sixgr.phy.pucch.harqObservationEvidence(context,rx);
assert(~e.AckObservedValid && ~e.AckObserved && e.HARQObservationStatus=="receiver_dtx");
rx.DTX=false; rx.ReceiverUsable=false;
assert(~sixgr.phy.pucch.harqObservationEvidence(context,rx).HARQObservationValid);
rx.ReceiverUsable=true; rx.DecodedFields.HARQACK=int8([]);
e=sixgr.phy.pucch.harqObservationEvidence(context,rx);
assert(~e.AckObservedValid && e.HARQObservationStatus=="incomplete_harq_field");
rx.DecodedFields.HARQACK=int8([1;0;1]);
e=sixgr.phy.pucch.harqObservationEvidence(localContext(3,1,10),rx);
assert(e.HARQObservationValid && ~e.AckObservedValid && ~e.AckObserved && ...
    e.ObservedHARQACKBitCount==2 && e.ObservedHARQNACKBitCount==1 && ...
    e.DecodedHARQBitVector=="101" && e.HARQObservationStatus=="decoded_multi_bit_codebook");
rx.DecodedFields.HARQACK=int8([]); rx.DecodedFields.SR=int8(1);
e=sixgr.phy.pucch.harqObservationEvidence(localContext(0,1,0),rx);
assert(~e.HARQObservationApplicable && ~e.AckObservedValid && ~e.AckObserved);
rx.DecodedFields.HARQACK=NaN;
try
    sixgr.phy.pucch.harqObservationEvidence(context,rx);
    error('test:ExpectedInvalidHARQBits','Nonbinary receiver bits must be rejected.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:link:InvalidPUCCHHARQObservation'),'%s',cause.message);
end
ok=true;
fprintf('PASS testPUCCHHARQObservationEvidence: 273PRB CSI waveform and typed HARQ/SR/CRC/DTX contracts\n');
end

function context=localContext(h,s,c)
context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"independent_gnb_test", ...
    'ConfigurationEpoch',1,'Sequence1Length',h+s+c,'Sequence2Length',0, ...
    'HARQACKBits',h,'SRBits',s,'CSIPart1Bits',c,'CSIPart2Bits',0,'PriorityIndex',0));
end
