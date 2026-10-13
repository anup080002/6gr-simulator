function measurement=measureCSIRSPhysicalResource(carrier,csirs,receivedGrid,cfg,execution,powerUnit)
% Retain TS 38.215 measurements from one declared received-grid plane.
% Unit-RE samples do not establish watts, even when the same Toolbox
% estimator is used. No waveform power is changed by this measurement.
% One identified CSI-RS resource per call; callers loop over resource IDs.
if nargin<4, cfg=struct(); end
if nargin<5, execution=struct(); end
if nargin<6, powerUnit="W_resource_grid"; end
powerUnit=string(powerUnit);
assert(isscalar(powerUnit) && any(powerUnit== ...
    ["W_resource_grid","relative_to_unit_occupied_RE_Es"]), ...
    'sixgr:phy:CSIRSMeasurementPowerUnit','Declare an absolute-W or normalized unit-RE measurement grid.');
relative=powerUnit=="relative_to_unit_occupied_RE_Es";
raw=nrCSIRSMeasurements(carrier,csirs,receivedGrid);
sinr=sixgr.phy.refsig.measureCSISINRFromResourceGrid(carrier,csirs,receivedGrid,cfg,execution);
sinr.PowerUnit=powerUnit;
nRx=size(receivedGrid,3);
% RSRP is a linear average of received reference-RE powers, not the
% squared coherent average of pilot phasors over the full bandwidth.
% The native measurement's default (phase correction disabled) can cancel
% a frequency-selective channel or residual timing phase ramp by tens of
% dB. Reuse the independently received, CDM-aware port-3000 powers already
% used by CSI-SINR. This requires no channel truth, TX payload, injected
% noise or release-specific phase-correction option. Native RSSI retains
% its resource-bandwidth/OFDM-symbol measurement window unchanged.
rsrpSource="unavailable_no_reference_occasion";
raw.RSRPPerAntenna=nan(nRx,1);
raw.RSRQPerAntenna=nan(nRx,1);
if isfield(sinr,'DesiredPowerPerReceiveAntenna')
    power=double(sinr.DesiredPowerPerReceiveAntenna(:));
    assert(numel(power)==nRx && all(isfinite(power)), ...
        'sixgr:phy:CSIRSMeasurementPowerDimensions', ...
        'Each received branch must retain its port-3000 reference-RE power.');
    % The flat-AWGN estimator retains signed noise-debiased estimates.
    % Nonpositive estimates have no finite logarithmic RSRP; do not clip
    % them upward or replace them with configured signal power.
    positive=power>0;
    raw.RSRPPerAntenna(positive)=10*log10(power(positive))+30;
    raw.RSRQPerAntenna=10*log10(double(csirs.NumRB))+ ...
        raw.RSRPPerAntenna-raw.RSSIPerAntenna;
    rsrpSource=string(sinr.Source);
end
for field=["RSRPPerAntenna","RSSIPerAntenna","RSRQPerAntenna"]
    if ~isequal(size(raw.(field)),[nRx 1])
        error('sixgr:phy:AmbiguousCSIRSMeasurementResource', ...
            'Each runtime resource identity must bind one CSI-RS configuration resource.');
    end
end
indices=nrCSIRSIndices(carrier,csirs,'IndexStyle','subscript','IndexBase','0based');
symbols=unique(double(indices(indices(:,3)==0,2))).';
measurement=struct('RSRPPerAntenna_dBm',double(raw.RSRPPerAntenna(:).'), ...
    'PowerUnit',powerUnit, ...
    'SINR',sinr, ...
    'RSSIPerAntenna_dBm',double(raw.RSSIPerAntenna(:).'), ...
    'RSRQPerAntenna_dB',double(raw.RSRQPerAntenna(:).'), ...
    'NumReceiveAntennas',nRx,'NumRB',double(csirs.NumRB), ...
    'FirstPRB0Based',double(carrier.NStartGrid)+double(csirs.RBOffset), ...
    'SymbolIndices0Based',symbols,'SubcarrierSpacing_kHz',double(carrier.SubcarrierSpacing), ...
    'Bandwidth_Hz',12*double(csirs.NumRB)*double(carrier.SubcarrierSpacing)*1000, ...
    'Source',"received_port3000_linear_RSRP_and_nrCSIRSMeasurements_RSSI", ...
    'RSRPSource',rsrpSource,'RSRPReferencePort',3000, ...
    'RSRPAveraging',"linear_reference_RE_power_after_CDM_channel_estimation", ...
    'Available',~isempty(symbols) && all(isfinite(raw.RSRPPerAntenna(:))) && ...
        all(isfinite(raw.RSSIPerAntenna(:))) && all(isfinite(raw.RSRQPerAntenna(:))));
if relative
    % nrCSIRSMeasurements reports 10log10(grid power)+30 (1 mW reference).
    % Remove that numerical unit reference, not channel loss or noise.
    measurement.RSRPPerAntenna_dB_re_UnitOccupiedRE_Es=measurement.RSRPPerAntenna_dBm-30;
    measurement.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es=measurement.RSSIPerAntenna_dBm-30;
    measurement.RSRPPerAntenna_dBm=nan(1,nRx);
    measurement.RSSIPerAntenna_dBm=nan(1,nRx);
    measurement.Source="received_port3000_linear_RSRP_and_native_RSSI_normalized_unit_RE_grid";
end
end
