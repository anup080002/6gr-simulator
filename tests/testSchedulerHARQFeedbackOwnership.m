function ok=testSchedulerHARQFeedbackOwnership()
% Declared MAC feedback, real PF/RR and HARQ objects; no PHY/run qualification.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.linkAdaptation.mode="amc";
cfg.phy.linkAdaptation.dlPolicy="baseline";
cfg.phy.linkAdaptation.ulPolicy="baseline";
cfg.phy.linkAdaptation.outerLoopFlag=true;
cfg.phy.linkAdaptation.deltaMCSPolicy="olla";
cfg.phy.linkAdaptation.ollaStepDown=.9;
cfg.phy.linkAdaptation.ollaStepUp=.1;
cfg.phy.linkAdaptation.ollaMarginMinDb=-10;
cfg.phy.linkAdaptation.ollaMarginMaxDb=10;
cfg.phy.linkAdaptation.targetBLER=.1;
cases=0;
for schedulerName=["PF","RR"]
    cfg.mac.scheduler.type=schedulerName;
    for direction=["DL","UL"]
        for outcome=["ACK","NACK","DTX"]
            % Coupled UL feedback is local CRC ACK/NACK, never UE PUCCH DTX.
            if direction=="DL" || outcome~="DTX"
                [h,row,soft]=localProcess(cfg,direction);
                schedulers=sixgr.truth.CoupledTruthRuntime.createSchedulersRuntime(cfg,1,direction,h);
                scheduler=schedulers{1};
                state=struct('CfgMobility',struct(),'DLHarq',h,'ULHarq',h, ...
                    'DLSchedulers',{schedulers},'ULSchedulers',{schedulers}, ...
                    'DLCombinedLLR',{{soft.LLRSum}},'ULCombinedLLR',{{soft.LLRSum}}, ...
                    'PUCCHGrantTraceTable',table(),'PendingFeedbackTable',table(), ...
                    'ControlTrials',struct('PUCCH',table()));
                observed=struct('DecodeOk',outcome~="DTX",'DTXFlag',outcome=="DTX", ...
                    'DecodedBits',int8(outcome=="ACK"));
                row.Ack=outcome=="ACK";
                state=localApply(state,row,observed,direction);
                assert(h.Stats.StaleFeedbackIgnored==0, ...
                    'test:DuplicateHARQCallback','One accepted feedback must not create a second stale HARQ callback.');
                assert(scheduler.HARQFeedbackOwner=="coupled_runtime");
                localAssertAccepted(h,scheduler,outcome);
                before=scheduler.getUEStats();
                state=localApply(state,row,observed,direction);
                assert(h.Stats.StaleFeedbackIgnored==1 && isequaln(before,scheduler.getUEStats()));
                row.SourceSlot=1; row.DueSlot=2;
                localApply(state,row,observed,direction);
                assert(h.Stats.StaleFeedbackIgnored==2 && isequaln(before,scheduler.getUEStats()));
                cases=cases+1;
            end

            % Standalone scheduler is the owner: reject stale feedback before
            % changing PF throughput or local first-transmission OLLA.
            [h,row,soft]=localProcess(cfg,direction);
            constructor=str2func("sixgr.l2.mac.Scheduler"+schedulerName);
            scheduler=constructor(cfg,'Direction',direction,'HARQ',h);
            feedback=table2struct(row);
            feedback.Outcome=outcome; feedback.Ack=outcome=="ACK";
            feedback.SourceSlot=1;
            before=scheduler.getUEStats();
            scheduler.updateAfterRx(feedback);
            assert(h.Stats.StaleFeedbackIgnored==1 && isequaln(before,scheduler.getUEStats()), ...
                'test:StaleSchedulerMutation','Stale process feedback must not update scheduler statistics.');
            assert(isequaln(h.getSoftBuffer(321,0),soft));
            assert(scheduler.HARQFeedbackOwner=="scheduler");
            feedback.SourceSlot=3;
            % Cover both supported input representations.
            if schedulerName=="RR", feedback=struct2table(feedback); end
            scheduler.updateAfterRx(feedback);
            localAssertAccepted(h,scheduler,outcome);
            before=scheduler.getUEStats();
            scheduler.updateAfterRx(feedback);
            assert(h.Stats.StaleFeedbackIgnored==2 && isequaln(before,scheduler.getUEStats()));
            cases=cases+1;
        end
    end
end
localProposedGrantHistory(cfg);
try
    sixgr.l2.mac.SchedulerPF(cfg,'HARQFeedbackOwner','unknown');
    error('test:ExpectedError','Unknown feedback owner must be rejected.');
catch cause
    assert(string(cause.identifier)=="sixgr:SchedulerBase:InvalidHARQFeedbackOwner");
end
ok=true;
fprintf('SCHEDULER_HARQ_FEEDBACK_OWNERSHIP_PASS cases=%d declared_MAC_only=1\n',cases);
end

function localProposedGrantHistory(cfg)
% Real scheduling and tentative HARQ allocation, with declared MAC feedback.
cfg=withCanonicalSchedulerTiming(cfg);
cfg.mac.scheduler.alpha=.9;
cfg.mac.scheduler.maxUEPerSlot=1;
cfg.mac.scheduler.minPRBPerUE=4;
cfg.mac.scheduler.maxPRBAllocationPerUE=12;
ue=struct('RNTI',321,'UEIndex',1,'ServingCell',1,'CQI',8,'RI',1, ...
    'DLBufferBytes',50000,'ULBufferBytes',50000, ...
    'ControlEligible',true,'GrantControlState','ok');
budget=struct('PRBSet',0:11,'SymbolAllocation',[0 14]);
cases=0;
for kind=["PF","RR"]
    for direction=["DL","UL"]
        for owner=["scheduler","coupled_runtime"]
            for outcome=["ACK","NACK","DTX"]
                if owner=="coupled_runtime" && direction=="UL" && outcome=="DTX", continue; end
                h=sixgr.l2.mac.HARQEntity(cfg,'Direction',direction);
                constructor=str2func("sixgr.l2.mac.Scheduler"+kind);
                scheduler=constructor(cfg,'Direction',direction,'HARQ',h,'HARQFeedbackOwner',owner);
                scheduler.prewarmUEAverage(ue,1);
                before=scheduler.getUEStats();
                [g,~]=scheduler.schedule(3,ue,budget);
                assert(isscalar(g),'One active UE must receive exactly one tentative grant.');
                state=struct('DLHarq',h,'ULHarq',h);
                state=sixgr.truth.CoupledTruthRuntime.cancelUnexecutedHARQGrantRuntime( ...
                    state,g,direction,'DCINotIssued',true);
                after=scheduler.getUEStats();
                assert(after.AvgThroughput_bps==before.AvgThroughput_bps ...
                    && after.NumScheduledSlots==0 && ~after.LastAck && after.LastTBSBits==0, ...
                    'test:ProposedGrantCredited','A rejected proposal must not be credited as successful service.');
                [g,~]=scheduler.schedule(5,ue,budget);
                assert(isscalar(g));
                after=scheduler.getUEStats();
                assert(after.AvgThroughput_bps==before.AvgThroughput_bps && after.NumScheduledSlots==0);
                harqID=double(g.HARQ.HarqID);
                h.onTx(321,harqID,ones(g.TBSBits,1,'uint8'),g,5);
                row=struct2table(struct('RNTI',321,'UEIndex',1,'HarqID',harqID, ...
                    'Direction',direction,'FeedbackForDirection',direction, ...
                    'SourceSlot',5,'DueSlot',6,'ServingCell',1,'TBSBits',g.TBSBits, ...
                    'RV',0,'IsRetransmission',false,'Ack',outcome=="ACK", ...
                    'Processed',false,'PUCCHGrantId',"declared-scheduled-owner",'UCIType',"harq_ack"));
                if owner=="coupled_runtime"
                    state.CfgMobility=struct();
                    state.DLSchedulers={scheduler}; state.ULSchedulers={scheduler};
                    state.DLCombinedLLR={[]}; state.ULCombinedLLR={[]};
                    state.PUCCHGrantTraceTable=table(); state.PendingFeedbackTable=table();
                    state.ControlTrials=struct('PUCCH',table());
                    observed=struct('DecodeOk',outcome~="DTX",'DTXFlag',outcome=="DTX", ...
                        'DecodedBits',int8(outcome=="ACK"));
                    state=localApply(state,row,observed,direction);
                else
                    feedback=table2struct(row); feedback.Outcome=outcome;
                    scheduler.updateAfterRx(feedback);
                end
                after=scheduler.getUEStats();
                expected=.9*before.AvgThroughput_bps + .1*double(outcome=="ACK")*g.TBSBits/scheduler.SlotDuration_s;
                assert(abs(after.AvgThroughput_bps-expected)<1e-7 && after.NumScheduledSlots==1, ...
                    'test:DoubleServiceCredit','Exactly one accepted feedback must update service history.');
                if owner=="coupled_runtime"
                    localApply(state,row,observed,direction);
                else
                    scheduler.updateAfterRx(feedback);
                end
                assert(isequaln(after,scheduler.getUEStats()),'Duplicate feedback must not update history.');
                cases=cases+1;
            end
        end
    end
end
fprintf('SCHEDULE_CANCEL_TX_FEEDBACK_HISTORY_PASS cases=%d declared_MAC_only=1\n',cases);
end

function state=localApply(state,row,observed,direction)
if direction=="UL"
    state=sixgr.truth.CoupledTruthRuntime.applyDecodedULHARQOutcomeRuntime(state,row);
else
    state=sixgr.truth.CoupledTruthRuntime.applyObservedPUCCHFeedbackRuntime(state,row,observed);
end
end

function localAssertAccepted(h,scheduler,outcome)
assert(h.Stats.Ack==double(outcome=="ACK") && h.Stats.Nack==double(outcome=="NACK") && ...
    h.Stats.Dtx==double(outcome=="DTX"));
stats=scheduler.getUEStats();
assert(isscalar(stats) && stats.NumScheduledSlots==1);
[delta,count]=scheduler.getOLLAMCSDelta(321);
expected=.1*double(outcome=="ACK")-.9*double(outcome=="NACK");
assert(count==double(outcome~="DTX") && abs(delta-expected)<1e-12);
end

function [h,row,soft]=localProcess(cfg,direction)
h=sixgr.l2.mac.HARQEntity(cfg,'Direction',direction);
allocation=h.allocate(321,3,100,'NewData',true);
assert(allocation.HARQ.HarqID==0);
layout=sixgr.phy.phycode.resolveCodingLayout('Direction',direction, ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',0,'Modulation','QPSK', ...
    'NumLayers',1,'RateMatchedBitCount',2748);
grant=struct('TBSBits',800,'Direction',direction,'Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout);
h.onTx(321,0,ones(800,1,'uint8'),grant,3);
soft=struct('LLRSum',[1;-2;3],'ObservationWeight',1);
h.storeSoftBuffer(321,0,soft);
row=struct2table(struct('RNTI',321,'UEIndex',1,'HarqID',0,'Direction',direction, ...
    'FeedbackForDirection',direction,'SourceSlot',3,'DueSlot',4,'ServingCell',1, ...
    'TBSBits',800,'RV',0,'IsRetransmission',false,'Ack',true, ...
    'Processed',false,'PUCCHGrantId',"declared-owner-test",'UCIType',"harq_ack"));
end
