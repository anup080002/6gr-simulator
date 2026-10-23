function ok=testRFPhysicalChainPower()
% Unequal physical chains, actual nonlinear PA and non-absolute negative path.
setup6GRSimToolkit('Verbose',false);
empty=sixgr.truth.rfChainPowerInterval();
assert(isstring(empty.EndpointID)&&isstring(empty.PostPAPerChainMeanSquareJSON) && ...
    isa(empty.PostPATotalMeanSquare,'double'),'Empty-table schema must preserve field types.');
cfg=struct(); cfg.rf.pa.enable=true; cfg.rf.pa.method='softlimiter';
cfg.rf.pa.backoff_dB=0;
x=exp(1i*(0:100)'*.13)*[.1 .3 .8 0];
before=rng;
out=sixgr.rf.applyRFImpairmentChain(x,cfg,'Endpoint','tx','Direction','DL', ...
    'SampleRateHz',30.72e6,'StrictMutationRequired',false);
assert(isequal(before,rng),'Measurements must not consume RNG.');
p=out.Replay.RFChainPowerEvidence;
expected=mean(abs(out.Waveform).^2,1);
assert(max(abs(p.Output.MeanSquarePerChain-expected))<1e-13);
assert(max(abs(p.Input.MeanSquarePerChain-[.01 .09 .64 0]))<1e-13);
assert(max(abs(p.PostPA.MeanSquarePerChain-expected))<1e-13 && out.Replay.PAApplied);
assert(~isfield(out.Replay,'WaveformAmplitudeUnit'), ...
    'Standalone RF processing cannot establish absolute waveform units.');
r=out.Replay;
t=sixgr.truth.rfChainPowerInterval(r,'gnb','TX','DL',0,101,30.72e6,4);
assert(isnan(t.PostPATotalPower_mW)&&t.PostPAPerChainPower_dBmJSON=="");
r.WaveformAmplitudeUnit='sqrt_mW';
t=sixgr.truth.rfChainPowerInterval(r,'gnb','TX','DL',0,101,30.72e6,4);
assert(abs(t.PostPATotalPower_mW-sum(expected))<1e-13);
v=jsondecode(char(t.PostPAPerChainPower_dBmJSON));
assert(max(abs(v(1:3).'-10*log10(expected(1:3))))<1e-12 && isnan(v(4)));
% Partition-independent statistics, without keeping any second waveform copy.
a=sixgr.rf.measurePhysicalChainPower(x(1:30,:),'rf_input');
b=sixgr.rf.measurePhysicalChainPower(x(31:end,:),'rf_input');
assert(max(abs(a.SquaredMagnitudeSumPerChain+b.SquaredMagnitudeSumPerChain- ...
    p.Input.SquaredMagnitudeSumPerChain))<1e-12);
base=sixgr.truth.RFEndpointExecutionLedger.emptyTable(1);
base.EndpointID="gnb"; base.Role="TX"; base.Direction="DL";
base.StartSample=0; base.EndSampleExclusive=101; base.SampleCount=101;
base.SampleRateHz=30.72e6; base.PhysicalPortCount=4;
base.InputMeanSquare=mean(abs(x(:)).^2); base.OutputMeanSquare=mean(abs(out.Waveform(:)).^2);
assert(sixgr.truth.validateRFChainPowerIntervals(t,base));
bad=t; bad.WaveformAmplitudeUnit="normalized_complex_baseband";
reject(@()sixgr.truth.validateRFChainPowerIntervals(bad,base),'sixgr:truth:RFChainPowerUnit');
bad=t; bad.OutputTotalMeanSquare=99;
reject(@()sixgr.truth.validateRFChainPowerIntervals(bad,base),'sixgr:truth:RFChainPowerClosure');
bad=r; bad.RFChainPowerEvidence.PostPA.MeanSquarePerChain(1)=99;
reject(@()sixgr.truth.rfChainPowerInterval(bad,'gnb','TX','DL',0,101,30.72e6,4), ...
    'sixgr:truth:RFChainPowerClosure');
old=rmfield(r,'RFChainPowerEvidence');
assert(isempty(sixgr.truth.rfChainPowerInterval(old,'gnb','TX','DL',0,101,30.72e6,4)));
% Tiny absolute powers need relative closure, not a one-mW tolerance floor.
tiny=out.Replay;
for stage=["Input","Output","PostPA"]
    v=tiny.RFChainPowerEvidence.(stage);
    v.MeanSquarePerChain=v.MeanSquarePerChain*1e-20;
    v.SquaredMagnitudeSumPerChain=v.SquaredMagnitudeSumPerChain*1e-20;
    v.TotalMeanSquare=v.TotalMeanSquare*1e-20;
    tiny.RFChainPowerEvidence.(stage)=v;
end
tiny.RFChainPowerEvidence.Output.TotalMeanSquare=2*tiny.RFChainPowerEvidence.Output.TotalMeanSquare;
reject(@()sixgr.truth.rfChainPowerInterval(tiny,'gnb','TX','DL',0,101,30.72e6,4), ...
    'sixgr:truth:RFChainPowerClosure');
ok=true; disp('RF_PHYSICAL_CHAIN_POWER_PASS unequal_chains=1 actual_PA=1 no_TRP_inference=1');
end
function reject(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingGuard','Expected %s.',id);
end
