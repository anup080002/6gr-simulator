function ok=testCarrierPeriodExactClock()
% Carrier-clock arithmetic and actual YAML-builder binding, not RF evidence.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
for scs=[15 30 60 120 240]
    s=struct('frame',struct('scs_khz',scs),'period',struct('milliseconds',20));
    [slots,source]=sixgr.lls6g.config.resolveCarrierPeriodSlots(s,"period.slots","period.milliseconds");
    native=nrCarrierConfig('SubcarrierSpacing',scs);
    assert(slots==2*native.SlotsPerFrame&&source=="period.milliseconds");
    s.run_control=struct('total_slots',7,'total_time_ms',999);
    s.frame_timing.slot_duration_ms=999;
    assert(slots==sixgr.lls6g.config.resolveCarrierPeriodSlots(s,"period.slots","period.milliseconds"));
    s.period.slots=3;
    assert(sixgr.lls6g.config.resolveCarrierPeriodSlots(s,"period.slots","period.milliseconds")==3);
end
base=struct('frame',struct('scs_khz',30));
for value={0,-1,NaN,Inf,true,'20',[10 20],1+1i}
    s=base; s.period.slots=value{1};
    localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(s,"period.slots",strings(0,1)), ...
        'sixgr:lls6g:config:InvalidCarrierPeriod');
end
s=base; s.period.slots=3.25;
localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(s,"period.slots",strings(0,1)), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
s=base; s.period.slots=bitshift(uint64(1),53)+uint64(1);
localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(s,"period.slots",strings(0,1)), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
s=base; s.period.milliseconds=(2^50+0.25)/2;
localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(s,strings(0,1),"period.milliseconds"), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(base,"absent",strings(0,1),complex(NaN,1)), ...
    'sixgr:lls6g:config:InvalidCarrierPeriod');
s=base; s.period.milliseconds=0.6;
localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(s,strings(0,1),"period.milliseconds"), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
s=base; s.frame.scs_khz=25; s.period.milliseconds=20;
localReject(@()sixgr.lls6g.config.resolveCarrierPeriodSlots(s,strings(0,1),"period.milliseconds"), ...
    'sixgr:lls6g:config:PeriodCarrierNumerology');
assert(isnan(sixgr.lls6g.config.resolveCarrierPeriodSlots(base,"absent",strings(0,1))));
assert(sixgr.lls6g.config.resolveCarrierPeriodSlots(base,"absent",strings(0,1),10)==10);
% Integration: mutation of the consumed authored slot field must fail in
% buildInternalConfig rather than round to the inherited valid integer.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
assert(cfg.phy.ssb.periodCarrierSlots==40);
bad=scenario.Data; bad.reference_signals.trs_periodicity_slots=20.25;
localReject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod');
fprintf('CARRIER_PERIOD_EXACT_CLOCK_PASS SCS=15,30,60,120,240 no_horizon_clock no_fractional_rounding\n');
ok=true;
end

function localReject(f,id)
try
    f();
catch cause
    assert(strcmp(cause.identifier,id),'test:WrongPeriodGuard','Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingPeriodGuard','Expected %s.',id);
end
