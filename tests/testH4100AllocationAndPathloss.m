function ok=testH4100AllocationAndPathloss()
% Exact H4 allocation/config and deterministic loss-operator checks only.
% No receiver, access, throughput or full-scenario acceptance is implied.
setup6GRSimToolkit('Verbose',false);
root=fullfile('simulator','configs','scenarios');
reference=sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    'h4_100_cdlc100_connected_impaired_40db_short.yaml'));
physical=sixgr.lls6g.config.loadScenarioConfig(fullfile(root, ...
    'h4_100_cdlc100_connected_impaired_pathloss_short.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(reference,tempname);
budgetCfg=sixgr.lls6g.buildInternalConfig(physical,tempname);
assert(sixgr.rf.isNormalizedFixedSNRPowerReference(cfg) && ...
    ~cfg.channel.pathlossEnabled && cfg.channel.snr_dB==40);
assert(~sixgr.rf.isFixedSNRLinkAuthority(budgetCfg) && ...
    sixgr.rf.fixedSNRPowerReferenceMode(budgetCfg)=="absolute_calibrated_sqrt_mw" && ...
    string(budgetCfg.run.noiseOperatingMode)=="receiver_noise_figure_thermal_noise" && ...
    budgetCfg.channel.pathlossEnabled && ~budgetCfg.channel.shadowFadingEnabled && ...
    string(budgetCfg.channel.complianceMode)=="strict_38901");
sixgr.truth.validateCoupledNoisePowerAuthority(budgetCfg);
% Regression for the actual scenario strictness source. An absent, unused
% run_control.strict_mode must not downgrade logging.strict_validation.
assert(cfg.run.strictMode && string(cfg.channel.complianceMode)=="strict_38901");
nonStrict=physical.toStruct(); nonStrict.logging.strict_validation=false;
nonStrict=sixgr.lls6g.buildInternalConfig(nonStrict,tempname);
assert(~nonStrict.run.strictMode && ...
    string(nonStrict.channel.complianceMode)=="approximate_38901_plus");
assert(budgetCfg.phy.fc_Hz==4e9 && budgetCfg.phy.carrier.NSizeGrid==273 && ...
    budgetCfg.phy.carrier.SubcarrierSpacing==30 && budgetCfg.run.totalSlots==60 && ...
    budgetCfg.phy.nTxAnt==64 && budgetCfg.phy.nRxAnt==4 && ...
    budgetCfg.phy.pdsch.maxRankDefault==4 && budgetCfg.phy.pusch.maxRankDefault==4);

% Reproduce the retained slots' reduced bandwidth via the production
% scheduler. SSB starts half a common PRB into PRB 126, covering 21 PRBs.
% The next ordinary DL slot must not inherit that exclusion or a 126 cap.
for slot=[41 42 43]
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    sch=sixgr.l2.mac.SchedulerPF(current,'Direction','DL');
    budget=struct('ControlAbsoluteSlot',slot-1,'ControlSymbolAllocation',[0 2]);
    [available,evidence]=sch.ssbSafePRBSet(slot,budget,0:272,[2 12]);
    [chunk,~]=sixgr.l2.mac.contiguousPRBChunk(available,1,273,1);
    if slot<43
        assert(isequal(available,[0:125 147:272]) && isequal(chunk,0:125));
        assert(height(evidence)==1 && evidence.Reason== ...
            "common_dl_resource_frequency_exclusion:SSB_PRB_symbol_reservation");
    else
        assert(isequal(available,0:272) && isequal(chunk,0:272) && isempty(evidence));
    end
    carrier=sixgr.phy.grid.makeCarrier(current);
    [data,info,pdsch]=sixgr.phy.grid.allocREsPDSCH(carrier,current, ...
        'PRBSet',chunk,'SymbolAllocation',[2 12]);
    ssb=sixgr.phy.frame.ssbPRBSymbolReservation(current,carrier,slot-1);
    pilots=nrPDSCHDMRSIndices(carrier,pdsch);
    plane=12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
    occupied=unique(mod(double([data(:);pilots(:)])-1,plane));
    assert(isempty(intersect(occupied,ssb.ReservedCarrierRE0)));
    assert(isequal(info.PRBSet,chunk) && isequal(info.SymbolAllocation,[2 12]));
    fprintf('H4_ALLOCATION_CHECK slot=%d PRBs=%d data_RE=%d\n',slot,numel(chunk),numel(data));
end

% Independently compare the core large-scale model to the toolbox model
% and the explicit Table 7.4.1-1 NLOS formula in its low-UE-height domain.
model=sixgr.channel.TR38901Plus(budgetCfg,'Scenario','UMa','Seed',121);
bs=[0;0;25]; distances=[20 85 200];
ue=[distances;zeros(size(distances));1.5*ones(size(distances))];
[loss,los,meta]=model.pathloss(bs,ue,'LOS',false,'IndoorRx',false);
independent=nrPathLoss(nrPathLossConfig('Scenario','UMa'),4e9,false,bs,ue);
d3=sqrt(distances.^2+(25-1.5)^2);
formula=max(28+22*log10(d3)+20*log10(4), ...
    13.54+39.08*log10(d3)+20*log10(4));
assert(max(abs(loss(:)-independent(:)))<1e-10 && ...
    max(abs(loss(:)-formula(:)))<1e-10 && ~any(los) && ...
    meta.pathlossEnabled && ~meta.fallbackUsedForPathloss);
% Check the actual common waveform-loss operator, not a second report-time
% calculation. RF is deliberately deferred here as in shared resolveLoss.
for direction=["DL","UL"]
    actual=budgetCfg;
    actual.lls6g.userContext=struct('RuntimeCurrentDirection',direction, ...
        'RuntimeServingBasePathloss_dB',loss(2),'RuntimeServingPathloss_dB',loss(2), ...
        'RuntimeServingShadowFading_dB',0,'RuntimeServingO2I_dB',0, ...
        'RuntimePathlossModelSource',meta.pathlossModelSource, ...
        'RuntimePathlossComplianceStatus',meta.pathlossComplianceStatus, ...
        'RuntimeFallbackUsedForPathloss',false);
    samples=complex(ones(32,4)); % Declared unit-amplitude operator probe.
    [received,ledger]=sixgr.link.applyWaveformImpairments( ...
        samples,actual,122.88e6,'ApplyRFChain',false);
    measuredLoss=-10*log10(sum(abs(received(:)).^2)/sum(abs(samples(:)).^2));
    assert(abs(ledger.AppliedLargeScaleLoss_dB-loss(2))<1e-10 && ...
        abs(measuredLoss-loss(2))<1e-10 && ~ledger.FallbackUsedForPathloss);
end
ok=true;
disp('H4_ALLOCATION_AND_PATHLOSS_PASS receiver_and_scenario_qualification=0');
end
