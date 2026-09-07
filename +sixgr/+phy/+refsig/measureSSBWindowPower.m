function [measured,evidence]=measureSSBWindowPower(grid,ncellid,ibarSSB,scsKHz)
% Actual antenna-plane sqrt(W) REs, not AGC-normalized decoder amplitudes.
% This is the 240-subcarrier / four-symbol SSB window. It is NOT an entire
% SMTC/higher-layer-configured NR Carrier RSSI report (TS 38.215 5.1.3).
validateattributes(grid,{'single','double'},{'finite','nonempty'});
if ndims(grid)>3 || size(grid,1)~=240 || size(grid,2)~=4
    error('sixgr:phy:refsig:InvalidSSBPowerWindow','Require one actual 240-by-4-by-R received SSB.');
end
validateattributes(scsKHz,{'numeric'},{'real','scalar','finite','positive'});
signals="SSS";
if isfinite(ibarSSB)
    measured=nrSSBMeasurements(grid,ncellid,ibarSSB);
    signals="SSS_and_PBCH_DMRS";
else
    measured=nrSSBMeasurements(grid,ncellid);
end
% Independent Parseval-domain closure. Sum all received RE powers per
% symbol (including unallocated REs, interference and noise), then average
% SYMBOL powers linearly. Do not average dBm or sum receiving branches.
symbolPower=reshape(sum(abs(double(grid)).^2,1),4,size(grid,3));
rssiW=mean(symbolPower,1);
rssiDbm=10*log10(rssiW)+30;
actual=double(measured.RSSIPerAntenna(:).');
if ~isequal(isfinite(actual),isfinite(rssiDbm)) || ...
        any(abs(actual(isfinite(actual))-rssiDbm(isfinite(rssiDbm)))>1e-4)
    error('sixgr:phy:refsig:SSBRSSIPowerClosure','RSSI must close on the actual received per-symbol RE energy.');
end
evidence=struct('Source',"nrSSBMeasurements_actual_antenna_plane_ssb_grid", ...
    'Scope',"ssb_240_subcarrier_four_symbol_window_not_full_carrier_RSSI", ...
    'AmplitudeUnit',"sqrt_W",'CPIncluded',false, ...
    'NumReceiveAntennas',size(grid,3),'NumRB',20,'NumSubcarriers',240, ...
    'SubcarrierSpacing_kHz',double(scsKHz),'Bandwidth_Hz',240*double(scsKHz)*1000, ...
    'SymbolIndicesWithinSSB0Based',[0 1 2 3], ...
    'SymbolPowerPerAntenna_W',symbolPower, ...
    'RSSIPerAntenna_dBm',actual, ...
    'ReferenceRSRPPerAntenna_dBm',double(measured.RSRPPerAntenna(:).'), ...
    'ReferenceRSRQPerAntenna_dB',double(measured.RSRQPerAntenna(:).'), ...
    'RSRPReferenceSignals',signals,'Available',all(isfinite(actual)));
end
