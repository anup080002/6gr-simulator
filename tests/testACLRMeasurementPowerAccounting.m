function ok=testACLRMeasurementPowerAccounting()
% Pure-waveform measurement unit test, not RF conformance qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
fs=4096; t=(0:4095)'/fs;
p=struct('FilterID',"explicit_rectangular_test",'AssignedCenter_Hz',0, ...
    'AdjacentOffset_Hz',1024,'MeasurementBandwidth_Hz',512);
x=ones(size(t))+.1*exp(-1j*2*pi*1024*t)+.2*exp(1j*2*pi*1024*t);
r=sixgr.rf.runtime.ACLRMeasurement.measure([x 2*x],fs,p);
assert(r.NumPorts==2 && r.CaptureSampleCount==4096);
assert(max(abs(r.AssignedPower-[1 4]))<1e-12);
assert(max(abs(r.AdjacentLowerPower-[.01 .04]))<1e-12);
assert(max(abs(r.AdjacentUpperPower-[.04 .16]))<1e-12);
assert(max(abs(r.ACLRLower_dB-20))<1e-10 && ...
    max(abs(r.ACLRUpper_dB-10*log10(25)))<1e-10);
assert(abs(r.SumPortACLRLower_dB-20)<1e-10 && ...
    abs(r.SumPortACLRUpper_dB-10*log10(25))<1e-10);
assert(max(abs(r.TotalCapturedPower-r.IntegratedSpectrumPower))<1e-12);
% Deliberately short capture: the old nfft^2 divisor loses 3.0103 dB.
short=x(1:2048);
a=sixgr.rf.runtime.ACLRMeasurement.measure(short,fs,p);
assert(a.Nfft==4096 && a.CaptureSampleCount==2048);
assert(abs(a.TotalCapturedPower-a.IntegratedSpectrumPower)<1e-12);
f=(-2048:2047)'; mask=f>=-256 & f<256;
X=fftshift(fft(short,4096));
expected=sum(abs(X(mask)).^2)/(4096*numel(short));
assert(abs(a.AssignedPower-expected)<1e-12 && a.AssignedPower>.99);
reference=sixgr.rf.runtime.oracle.ACLRFilterSpec.measure(short,fs,0,1024,512);
assert(abs(reference.AssignedPower-a.AssignedPower)<1e-12 && ...
    abs(reference.AdjacentLowerPower-a.AdjacentLowerPower)<1e-12 && ...
    abs(reference.AdjacentUpperPower-a.AdjacentUpperPower)<1e-12);
b=sixgr.rf.runtime.ACLRMeasurement.measure(short.',fs,p);
assert(isequaln(a,b),'Row and column vectors describe the same single port.');
assert(a.PowerUnit=="input_amplitude_squared_not_implicitly_watts");
silent=sixgr.rf.runtime.ACLRMeasurement.measure(zeros(4096,1),fs,p);
assert(~silent.HasAssignedPower && isnan(silent.ACLRLower_dB) && ...
    isnan(silent.ACLRUpper_dB),'No signal cannot be turned into a finite ACLR by numerical floors.');
bad=p; bad.AdjacentOffset_Hz=1900;
reject(@()sixgr.rf.runtime.ACLRMeasurement.measure(short,fs,bad));
reject(@()sixgr.rf.runtime.ACLRMeasurement.measure(short,[fs fs],p));
reject(@()sixgr.rf.runtime.ACLRMeasurement.measure(nan(16,1),fs,p));
reject(@()sixgr.rf.runtime.ACLRMeasurement.measure(ones(2,2,2),fs,p));
fprintf('ACLR_POWER_ACCOUNTING_PASS ports=2 zero_padding_parseval=1 clipped_filters_rejected=1 conformance_claim=0\n');
ok=true;
end

function reject(action)
try
    action();
catch err
    assert(strcmp(err.identifier,'RF:ACLRFilterInvalid'),err.message);
    return
end
error('test:ACLRInvalidMeasurementAccepted','Invalid waveform/filter accepted.');
end
