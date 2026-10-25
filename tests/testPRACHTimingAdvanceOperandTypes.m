function testPRACHTimingAdvanceOperandTypes()
% Receiver-operand/quantization arithmetic only; no PRACH execution claim.
f=@sixgr.phy.ra.estimateTimingAdvanceFromPRACH;
fs=30.72e6;
for bad={'0',"0",true,false,[],[0 1],complex(2,1),NaN,Inf,-1,struct()}
    d=struct('TimingOffsetSamples',0,'PropagationTimingOffsetSamples',bad{1});
    t=f(d,fs,30);
    assert(~t.Valid && isnan(t.TimingAdvanceCommand) && isnan(t.TimingOffsetSamples));
end
for value={0,24,single(16),int32(32),16.25}
    d=struct('TimingOffsetSamples',value{1},'PropagationTimingOffsetSamples',value{1});
    t=f(d,fs,30); assert(t.Valid && t.TimingOffsetSamples==double(value{1}));
    assert(t.TimingAdvanceCommand==round(double(value{1})/t.StepSamples));
    assert(t.QuantizationResidualSamples==double(value{1})-t.TimingAdvanceSamples);
end
d=struct('TimingOffsetSamples','0','PropagationTimingOffsetSamples',0);
t=f(d,fs,30); assert(t.Valid && isnan(t.RawTimingOffsetSamples));
fprintf('PRACH_TA_OPERAND_TYPES_PASS arithmetic_only PHY=0\n');
end
