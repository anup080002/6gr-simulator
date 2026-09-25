function ok=testSchedulerAdaptiveTinyQueue
% Short queues require real legal TBs, even with adaptive rank/MCS search.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
cfg.phy.linkAdaptation.queueAwareRankMCSReductionEnable=true;
cfg.phy.linkAdaptation.minPRBForWidebandCQIGrant=4;
count=0;
for schedulerClass=["sixgr.l2.mac.SchedulerPF","sixgr.l2.mac.SchedulerRR"]
    for direction=["DL","UL"]
        for bound=[false true]
            if direction=="UL" && bound, continue; end
            scheduler=feval(schedulerClass,cfg,'Direction',direction);
            ue=struct('RNTI',1,'CQI',12,'RI',2,'DLBufferBytes',1,'ULBufferBytes',1);
            if bound
                % Scheduler unit fixture only; physical report deserialization
                % is covered independently by testTypeIIRuntimeCSIReportBinding.
                ue.ReceivedCSIReport=struct('RI',2);
            end
            for bytes=[1 2 512]
                p=scheduler.buildNewDataGrantPlan(ue,0:24,[2 12],bytes);
                assert(p.Valid,'Nonempty queue must yield a legal grant when resources exist.');
                expected=nrTBS(p.Modulation,p.NumLayers,numel(p.PRBSet), ...
                    p.NREPerPRB,p.TargetCodeRate,p.XOverhead);
                assert(p.TBSBits==expected && p.QueuePaddingBits==max(0,expected-8*bytes));
                assert(~p.PlanningOnlyApproximation);
                if bound, assert(p.NumLayers==2 && p.LayerReductionSteps==0); end
                if numel(p.PRBSet)<4
                    assert(p.NumLayers==1 && p.MCSIndex<10, ...
                        'Tiny-queue padding must not bypass the small-PRB CSI guard.');
                end
                fprintf('ADAPTIVE_TINY_QUEUE %s %s bound=%d bytes=%d rank=%d PRBs=%d TBS=%d padding=%d\n', ...
                    schedulerClass,direction,bound,bytes,p.NumLayers,numel(p.PRBSet),p.TBSBits,p.QueuePaddingBits);
                count=count+1;
            end
            empty=scheduler.buildNewDataGrantPlan(ue,0:24,[2 12],0);
            assert(~empty.Valid,'An empty queue must not generate a padding-only grant.');
        end
    end
end
fprintf('ADAPTIVE_TINY_QUEUE_PASS cases=%d\n',count);
ok=true;
end
