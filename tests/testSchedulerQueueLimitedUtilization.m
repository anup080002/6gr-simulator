function ok = testSchedulerQueueLimitedUtilization()
% A nonempty short queue must not collapse to the smallest positive TB.
setup6GRSimToolkit('Verbose',false);
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.phy.linkAdaptation.queueAwareRankMCSReductionEnable = false;
cfg.phy.linkAdaptation.minPRBForWidebandCQIGrant = 1;
cases = 0;
for direction = ["DL","UL"]
    for schedulerClass = ["sixgr.l2.mac.SchedulerPF","sixgr.l2.mac.SchedulerRR"]
        scheduler = feval(schedulerClass,cfg,'Direction',direction);
        for rank = [1 2]
            ue = struct('RNTI',1,'CQI',15,'RI',rank, ...
                'DLBufferBytes',1414,'ULBufferBytes',1414);
            [modulation,layers,rate,amc] = scheduler.selectAMC(ue);
            assert(layers == rank,'Fixture must exercise the requested rank.');
            for symbols = {[2 12],[2 8]}
                allocation = symbols{1};
                bits = zeros(1,25);
                for n = 1:25
                    [bits(n),~,nre,info] = scheduler.estimateTBS( ...
                        modulation,layers,n,allocation,rate,'ForceExact',true);
                    assert(bits(n) == nrTBS(char(modulation),layers,n,nre,rate,info.XOverhead));
                end
                for queueBytes = [1414 1541 1]
                    plan = scheduler.buildNewDataGrantPlan( ...
                        ue,0:24,allocation,queueBytes);
                    fits = bits <= 8*queueBytes & bits > 0;
                    if any(fits)
                        expectedBits = max(bits(fits));
                    else
                        % Only queues below the minimum legal TB need padding.
                        expectedBits = min(bits(bits > 0));
                    end
                    expectedPRBs = find(bits == expectedBits,1,'first');
                    fprintf('QUEUE_FIT %s %s rank=%d symbols=%d queue=%d PRBs=%d expected=%d TBS=%d expectedBits=%d\n', ...
                        direction,schedulerClass,rank,allocation(2),queueBytes, ...
                        numel(plan.PRBSet),expectedPRBs,plan.TBSBits,expectedBits);
                    assert(plan.Valid && plan.TBSBits == expectedBits && ...
                        numel(plan.PRBSet) == expectedPRBs, ...
                        'test:QueueLimitedUnderallocation', ...
                        'Preserve AMC but maximize real payload fitting the queue; do not choose minimum positive TBS.');
                    assert(plan.MCSIndex == amc.MCSIndex && plan.NumLayers == layers);
                    assert(plan.QueuePaddingBytes == max(0,plan.TBSBytes-queueBytes));
                    cases = cases+1;
                end
            end
        end
    end
end
fprintf('QUEUE_UTILIZATION_CASES=%d\n',cases);
ok = true;
end
