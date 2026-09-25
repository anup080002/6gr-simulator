function ok=testPAPRPortPowerAccounting()
% Numerical waveform unit tests, not statistical campaign qualification.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
x=[1;1;1;3];
T=sixgr.phy.waveform.PAPRMeasurement.measure([x 10*x zeros(4,1)],[1 2]);
assert(height(T)==6 && isequal(T.PortIndex,[1;2;3;1;2;3]));
assert(abs(T.PAPR_dB(1)-10*log10(3))<1e-12 && abs(T.PAPR_dB(2)-T.PAPR_dB(1))<1e-12);
assert(T.PeakPower_InputAmplitudeSquared(1)==9 && T.MeanPower_InputAmplitudeSquared(1)==3);
assert(all(isnan(T.PAPR_dB([3 6]))) && all(T.MeasurementStatus([3 6])=="undefined_zero_power"));
small=sixgr.phy.waveform.PAPRMeasurement.measure(x*1e-20,1);
assert(abs(small.PAPR_dB-T.PAPR_dB(1))<1e-12,'PAPR must be invariant under finite amplitude scaling.');
row=sixgr.phy.waveform.PAPRMeasurement.measure(x.',1);
assert(row.PAPR_dB==T.PAPR_dB(1));
c=sixgr.phy.waveform.PAPRMeasurement.ccdf([1;2;2],2,.95);
assert(c.Exceedances==0 && c.Trials==3 && c.CCDF==0 && c.UpperCI>0);
reject(@()sixgr.phy.waveform.PAPRMeasurement.measure([1;NaN],1),'WAVEFORM:PAPRInvalidSamples');
reject(@()sixgr.phy.waveform.PAPRMeasurement.ccdf([1;NaN],1,.95),'WAVEFORM:PAPRInvalidCCDF');
reject(@()sixgr.phy.waveform.PAPRMeasurement.ccdf([],1,.95),'WAVEFORM:PAPRInvalidCCDF');
fprintf('PAPR_PORT_POWER_ACCOUNTING_PASS ports=3 scale_invariance=1 silent_port_undefined=1\n');
ok=true;
end

function reject(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),err.message); return;
end
error('test:PAPRInvalidEvidenceAccepted','Invalid PAPR evidence accepted.');
end
