function ok=testHARQFeedbackDisposition()
% Declared MAC reducer inputs, not waveform/codebook or 12 dB qualification.
% Actual receiver ACK/NACK/DTX is separately covered by
% testReceivedHARQFeedbackOutcome and the shared-clock receiver tests.
setup6GRSimToolkit('Verbose',false);
for outcome=["ACK","NACK","DTX"]
    [state,row,harq,recorder,soft]=localState("DL");
    observed=struct('DecodeOk',outcome~="DTX",'DTXFlag',outcome=="DTX", ...
        'DecodedBits',int8(outcome=="ACK"),'PhysicalOccasionId',"declared-unit-occasion");
    stats=harq.Stats;
    state=sixgr.truth.CoupledTruthRuntime.applyObservedPUCCHFeedbackRuntime(state,row,observed);
    assert(isequal(harq.getSoftBuffer(321,0),soft) && ...
        isequal(state.DLCombinedLLR{1,1},soft.LLRSum), ...
        'Stale feedback must preserve both current-attempt soft buffers.');
    assert(isempty(recorder.Updates) && harq.Stats.Ack==stats.Ack && ...
        harq.Stats.Nack==stats.Nack && harq.Stats.Dtx==stats.Dtx && ...
        harq.Stats.StaleFeedbackIgnored==stats.StaleFeedbackIgnored+1);
    t=state.PUCCHGrantTraceTable;
    assert(~t.HARQFeedbackApplied(1) && t.StaleFeedbackIgnored(1) && ...
        ~t.RuntimeStateUpdated(1) && ~t.ControlStateChanged(1) && ~t.StateChangeApplied(1));
    assert(t.PUCCHGrantState(1)=="waveform_observed_stale_feedback_ignored" && ...
        isnan(t.HARQFeedbackApplied(2)) && isnan(t.StaleFeedbackIgnored(2)));
    assert(state.PendingFeedbackTable.Processed(1));
    trial=state.ControlTrials.PUCCH;
    assert(trial.HARQFeedbackAppliedCount(1)==0 && trial.StaleHARQFeedbackCount(1)==1 && ...
        ~trial.StateChangeApplied(1) && isnan(trial.HARQFeedbackAppliedCount(2)));

    row.SourceSlot=3; row.DueSlot=4;
    state=sixgr.truth.CoupledTruthRuntime.applyObservedPUCCHFeedbackRuntime(state,row,observed);
    assert(numel(recorder.Updates)==1 && string(recorder.Updates{1}.Outcome)==outcome);
    assert(state.PUCCHGrantTraceTable.HARQFeedbackApplied(1)==1 && ...
        state.PUCCHGrantTraceTable.StateChangeApplied(1));
    assert(state.ControlTrials.PUCCH.HARQFeedbackAppliedCount(1)==1 && ...
        state.ControlTrials.PUCCH.StaleHARQFeedbackCount(1)==0);
    if outcome=="ACK"
        assert(isempty(state.DLCombinedLLR{1,1}) && isempty(fieldnames(harq.getSoftBuffer(321,0))));
    else
        assert(isequal(state.DLCombinedLLR{1,1},soft.LLRSum) && ...
            isequal(harq.getSoftBuffer(321,0),soft));
    end
    state=sixgr.truth.CoupledTruthRuntime.applyObservedPUCCHFeedbackRuntime(state,row,observed);
    assert(numel(recorder.Updates)==1 && state.PUCCHGrantTraceTable.StaleFeedbackIgnored(1)==1, ...
        'Duplicate current-attempt feedback must not update adaptation twice.');
end

% UL decoder boundary must honor the same entity disposition.
for ack=[true,false]
    [state,row,harq,recorder,soft]=localState("UL");
    row.Ack=ack; row.DueSlot=2;
    state=sixgr.truth.CoupledTruthRuntime.applyDecodedULHARQOutcomeRuntime(state,row);
    assert(isempty(recorder.Updates) && isequal(harq.getSoftBuffer(321,0),soft));
    row.SourceSlot=3; row.DueSlot=4;
    state=sixgr.truth.CoupledTruthRuntime.applyDecodedULHARQOutcomeRuntime(state,row);
    assert(numel(recorder.Updates)==1 && recorder.Updates{1}.Ack==ack);
    sixgr.truth.CoupledTruthRuntime.applyDecodedULHARQOutcomeRuntime(state,row);
    assert(numel(recorder.Updates)==1);
end

% Reject ambiguous physical-trial ownership before any handle mutation.
[state,row,harq,~,~]=localState("DL");
state.ControlTrials.PUCCH.PhysicalPUCCHOccasionId(:)="declared-unit-occasion";
stats=harq.Stats;
try
    sixgr.truth.CoupledTruthRuntime.applyObservedPUCCHFeedbackRuntime(state,row,observed);
    error('test:ExpectedError','Expected ambiguous ownership rejection.');
catch cause
    assert(string(cause.identifier)=="sixgr:truth:AmbiguousPUCCHDispositionTrial");
end
assert(isequal(harq.Stats,stats));
ok=true;
disp('HARQ_FEEDBACK_DISPOSITION_PASS declared_MAC_reducer_only=1');
end

function [state,row,harq,recorder,soft]=localState(direction)
cfg=sixgr.config.defaultConfig();
harq=sixgr.l2.mac.HARQEntity(cfg,'Direction',direction);
layout=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',0,'Modulation','QPSK', ...
    'NumLayers',1,'RateMatchedBitCount',2748);
grant=struct('TBSBits',800,'Direction',direction,'Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout);
allocation=harq.allocate(321,1,100,'NewData',true);
assert(allocation.HARQ.HarqID==0);
tb=uint8(ones(800,1));
harq.onTx(321,0,tb,grant,1);
assert(harq.onFeedback(321,0,"NACK",'SourceSlot',1,'FeedbackSlot',2));
allocation=harq.allocate(321,3,100,'NewData',false);
assert(allocation.HARQ.IsRetransmission && allocation.HARQ.HarqID==0);
grant.CodingLayout=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',allocation.HARQ.RV, ...
    'Modulation','QPSK','NumLayers',1,'RateMatchedBitCount',2748);
harq.onTx(321,0,tb,grant,3);
soft=struct('LLRSum',[1;-2;3],'ObservationWeight',1);
harq.storeSoftBuffer(321,0,soft);
recorder=FeedbackDispositionRecorder();
state=struct();
% Empty configuration intentionally limits this unit fixture to scheduler
% call disposition; it does not claim receiver-owned OLLA qualification.
state.CfgMobility=struct();
state.DLHarq=harq; state.ULHarq=harq;
state.DLSchedulers={recorder}; state.ULSchedulers={recorder};
state.DLCombinedLLR={soft.LLRSum}; state.ULCombinedLLR={soft.LLRSum};
row=struct2table(struct('RNTI',321,'UEIndex',1,'HarqID',0,'Direction',direction, ...
    'FeedbackForDirection',direction,'SourceSlot',1,'DueSlot',4,'ServingCell',1, ...
    'TBSBits',800,'RV',0,'IsRetransmission',false,'Ack',true, ...
    'Processed',false,'PUCCHGrantId',"declared-unit-grant",'UCIType',"harq_ack"));
state.PendingFeedbackTable=row;
t=table(["declared-unit-grant";"unprocessed-unit-grant"], ...
    'VariableNames',{'PUCCHGrantId'});
for name=["ObservedAck","PUCCHDecodeOk","DTXFlag","CurrentDecodeOK", ...
        "CombinedDecodeOK","GrantExecutedFlag","RuntimeStateUpdated", ...
        "ControlStateChanged","StateChangeApplied"]
    t.(name)=false(2,1);
end
state.PUCCHGrantTraceTable=t;
% No PUCCHGrantId on these declared physical records: no PHY metric copied.
trials=table(["declared-unit-occasion";"unprocessed-unit-occasion"], ...
    'VariableNames',{'PhysicalPUCCHOccasionId'});
trials.RuntimeStateUpdated=false(2,1);
trials.ControlStateChanged=false(2,1);
trials.StateChangeApplied=false(2,1);
state.ControlTrials=struct('PUCCH',trials);
end
