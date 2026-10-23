function reference=resolveAbsoluteEndpointReference(cfg,raw,direction)
% Fixed RF operating reference in sqrt(mW), independent of current payload.
% This is a declared hardware-study operating point, NOT a 3GPP requirement.
% Never derive converter/PA range from received samples, rank, grant power,
% occupied RE count or a desired SINR.
if sixgr.rf.isNormalizedFixedSNRPowerReference(cfg)
    error('RF:AbsoluteEndpointReferenceDomain', ...
        'Absolute RF reference requires physical sqrt(mW) samples.');
end
direction=upper(string(direction));
if any(direction==["DL","DOWNLINK"])
    key='reference_total_power_dl_dbm'; role='bs';
elseif any(direction==["UL","UPLINK"])
    key='reference_total_power_ul_dbm'; role='ue';
else
    error('RF:AbsoluteEndpointReferenceDirection','Declare one DL or UL endpoint.');
end
power=sixgr.util.structGet(raw,key,NaN);
headroom=sixgr.util.structGet(raw,'reference_headroom_db',NaN);
ports=sixgr.util.structGet(cfg,"scenario."+role+".nTxAnt",NaN);
validateattributes(power,{'numeric'},{'real','finite','scalar'});
validateattributes(headroom,{'numeric'},{'real','finite','scalar','nonnegative'});
validateattributes(ports,{'numeric'},{'real','finite','scalar','integer','positive'});
rms=sqrt(10^(double(power)/10)/double(ports));
reference=struct('Domain',"absolute_endpoint_rms", ...
    'WaveformUnitsPerReferenceUnit',rms*10^(double(headroom)/20), ...
    'ReferenceRMS',rms,'ReferenceTotalPower_dBm',double(power), ...
    'Headroom_dB',double(headroom),'NumTransmitPorts',double(ports), ...
    'AmplitudeUnit',"sqrt_mW",'PayloadDependent',false, ...
    'Source',"declared_endpoint_total_power_shared_over_physical_TX_ports");
end
