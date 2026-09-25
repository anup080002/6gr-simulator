function assertMeasuredPAPRTrialEvidence(T)
% Verify raw trial serialization against its retained per-port power terms.
assert(istable(T) && ~isempty(T) && ...
    all(ismember(["PAPR_dB","PAPRMeasurementJSON"],string(T.Properties.VariableNames))), ...
    'Physical trials must retain PAPR and its measurement terms.');
measured=isfinite(double(T.PAPR_dB));
assert(any(measured),'The physical trial fixture did not measure any waveform PAPR.');
for row=find(measured).'
    e=jsondecode(string(T.PAPRMeasurementJSON(row)));
    assert(isfield(e,'MeasurementPoint') && strlength(string(e.MeasurementPoint))>0, ...
        'PAPR evidence must declare its supplied or runtime-bound measurement point.');
    assert(string(e.ContractVersion)=="tx_papr/v1" && ...
        string(e.AggregateRule)=="maximum_finite_per_port_PAPR");
    ports=e.PerPort;
    assert(~isempty(ports) && all([ports.MeasuredSampleCount]>0));
    peak=[ports.PeakPower_InputAmplitudeSquared];
    average=[ports.MeanPower_InputAmplitudeSquared];
    ratio=10*log10(peak./average);
    valid=isfinite(ratio);
    assert(any(valid) && abs(max(ratio(valid))-T.PAPR_dB(row))<1e-10);
    assert(all(abs(ratio(valid)-[ports(valid).PAPR_dB])<1e-10));
    assert(all([ports.OversamplingFactor]==1) && ...
        all([ports.MeasuredSampleCount]<=e.InputWaveformSampleCount));
end
% Test the actual quoted CSV representation of the nested measurement terms.
path=[tempname '.csv']; cleanup=onCleanup(@()delete(path)); %#ok<NASGU>
retained=T(:,{'PAPR_dB','PAPRMeasurementJSON'});
writetable(retained,path);
roundtrip=readtable(path,'Delimiter',',','ReadVariableNames',true, ...
    'NumHeaderLines',0,'VariableNamingRule','preserve','TextType','string');
assert(isequaln(retained.PAPR_dB,roundtrip.PAPR_dB) || ...
    all(abs(retained.PAPR_dB(measured)-roundtrip.PAPR_dB(measured))<1e-10));
assert(isequal(string(retained.PAPRMeasurementJSON),roundtrip.PAPRMeasurementJSON));
end
