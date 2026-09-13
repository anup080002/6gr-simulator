function ok=testReceivedHARQFeedbackOutcome(outputRoot)
% Actual isolated Format-0 RX; MAC payload/clock are declared unit inputs.
% This does not qualify main failed-DCI observation or the shared retx chain.
if nargin<1, outputRoot=tempname; end
setup6GRSimToolkit('Verbose',false);
if ~isfolder(outputRoot), mkdir(outputRoot); end
random=RandStream('Threefry','Seed',1800);
% Retain every noise-only outcome, including false alarms. One random
% no-signal observation is not guaranteed to be DTX at a finite threshold.
rows=cell(66,1);
seenDTX=false;
for index=1:66
    txBit=int8(index==1);
    f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(0,txBit);
    tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,f.Assignment,f.Report);
    noise=sqrt(1e-9/2)*(randn(random,size(tx.Waveform))+1i*randn(random,size(tx.Waveform)));
    waveform=noise;
    if index<3, waveform=waveform+tx.Waveform; end
    rx=sixgr.phy.pucch.PUCCHReceiver.receive(waveform,f.Carrier,f.Assignment,f.Context, ...
        'NoiseVariance',NaN,'NoiseVarianceMode','noncoherent_correlation');
    observed=struct('DecodeOk',rx.ReceiverUsable,'DTXFlag',rx.DTX, ...
        'DecodedBits',rx.DecodedSequence1);
    bit=sixgr.truth.resolveReceivedHARQBit(observed,1,true);
    caseName="NO_SIGNAL_"+string(index-2);
    if index<3
        expected=["ACK","NACK"];
        caseName=expected(index);
        assert(bit.FeedbackOutcome==expected(index));
    end
    assert(~rx.OraclePayloadBitsUsed && bit.MissedFeedback==rx.DTX);
    opposite=sixgr.truth.resolveReceivedHARQBit(observed,1,false);
    assert(opposite.FeedbackOutcome==bit.FeedbackOutcome && ...
        opposite.ObservedAck==bit.ObservedAck,'Scoring truth must not drive the receiver outcome.');
    if index<3
        assert(bit.FalseNack==(index==2) && opposite.FalseAck==(index==1));
        localMACOutcome(bit.FeedbackOutcome);
    elseif bit.FeedbackOutcome=="DTX" && ~seenDTX
        localMACOutcome(bit.FeedbackOutcome);
        seenDTX=true;
    end
    rows{index}=struct('Case',caseName,'SignalPresent',index<3, ...
        'DetectionMetric',rx.DetectionMetric,'DetectionThreshold',rx.DetectionThreshold, ...
        'ReceiverDTX',rx.DTX,'FeedbackOutcome',bit.FeedbackOutcome, ...
        'FeedbackOutcomeReason',bit.FeedbackOutcomeReason, ...
        'FalseAck',bit.FalseAck,'FalseNack',bit.FalseNack,'MissedFeedback',bit.MissedFeedback, ...
        'ReceiverFalseAlarm',index>=3 && rx.ReceiverUsable, ...
        'Source',"isolated_pucch_rx_and_declared_mac_unit_fixture");
    save(fullfile(outputRoot,"pucch_"+lower(caseName)+".mat"), ...
        'f','tx','noise','waveform','rx','observed','bit');
end
assert(seenDTX,'test:NoDTXObservation','Noise-only receiver trials yielded no usable DTX coverage.');
% Invalid/absent receiver bits cannot turn into a NACK or a false NACK.
declared=struct('DecodeOk',true,'DTXFlag',false,'DecodedBits',int8(1));
missing=sixgr.truth.resolveReceivedHARQBit(declared,2,true);
assert(missing.FeedbackOutcome=="DTX" && ~missing.FalseNack && ~missing.DecodeOk);
declared.DecodeOk=false;
invalid=sixgr.truth.resolveReceivedHARQBit(declared,1,false);
assert(invalid.FeedbackOutcome=="DTX" && ~invalid.FalseAck);
declared.DecodeOk=true; declared.DTXFlag=true;
invalid=sixgr.truth.resolveReceivedHARQBit(declared,1,false);
assert(invalid.FeedbackOutcome=="DTX" && ~invalid.FalseAck);
declared.DTXFlag=false; declared.DecodedBits=NaN;
try
    sixgr.truth.resolveReceivedHARQBit(declared,1,true);
    error('test:ExpectedError','A nonbinary usable bit must be rejected.');
catch cause
    assert(string(cause.identifier)=="sixgr:truth:InvalidReceivedHARQBit");
end
writetable(struct2table(vertcat(rows{:})),fullfile(outputRoot,'received_harq_outcomes.csv'));
fprintf('NO_SIGNAL_FALSE_ALARMS %d/64 (component observation, not threshold qualification)\n', ...
    sum(cellfun(@(row)row.ReceiverFalseAlarm,rows)));
ok=true; disp('RECEIVED_HARQ_ACK_NACK_DTX_PASS');
end

function localMACOutcome(outcome)
cfg=sixgr.config.defaultConfig();
harq=sixgr.l2.mac.HARQEntity(cfg,'Direction','DL');
layout=sixgr.phy.phycode.resolveCodingLayout('Direction','DL', ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',0,'Modulation','QPSK', ...
    'NumLayers',1,'RateMatchedBitCount',2748);
grant=struct('TBSBits',800,'Direction','DL','Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout);
allocation=harq.allocate(321,1,100,'NewData',true);
harq.onTx(321,allocation.HARQ.HarqID,uint8(ones(800,1)),grant,1);
harq.onFeedback(321,allocation.HARQ.HarqID,outcome,'SourceSlot',1,'FeedbackSlot',2);
assert(harq.Stats.Ack==double(outcome=="ACK") && ...
    harq.Stats.Nack==double(outcome=="NACK") && harq.Stats.Dtx==double(outcome=="DTX"));
next=harq.allocate(321,3,100,'NewData',false);
if outcome=="ACK"
    assert(isempty(next.HARQ.HarqID) && isempty(next.ProcessIndex) && ~next.NoFreeProcess);
else
    assert(next.HARQ.IsRetransmission && next.HARQ.HarqID==allocation.HARQ.HarqID && ...
        next.HARQ.NDI==allocation.HARQ.NDI && next.HARQ.RV==2);
end
harq.reset(); assert(harq.Stats.Dtx==0);
end
