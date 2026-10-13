function ok=testCSIRSFrequencySelectivePower()
% Independent full-band received-pilot fixtures; not campaign measurements.
% A delay/phase ramp changes no per-RE power. Wideband coherent averaging
% must not turn that finite port-3000 power into an apparent path loss.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30);
rows=struct([]);
for rowNumber=[2 3 4]
    csirs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on', ...
        'RowNumber',rowNumber,'Density','one','SymbolLocations',6, ...
        'SubcarrierLocations',0,'NumRB',273);
    reference=nrResourceGrid(carrier,csirs.NumCSIRSPorts);
    indices=nrCSIRSIndices(carrier,csirs);
    reference(indices)=nrCSIRS(carrier,csirs);
    % Distinct port amplitudes make averaging ports the wrong answer.
    gains=1./(1:csirs.NumCSIRSPorts);
    base=sum(reference.*reshape(gains,1,1,[]),3);
    for delaySamples=[0 4 16]
        phase=exp(-1i*2*pi*(0:size(base,1)-1)'*delaySamples/4096);
        grid=cat(3,base.*phase,.5*base.*phase);
        measured=sixgr.phy.refsig.measureCSIRSPhysicalResource( ...
            carrier,csirs,grid,struct(),struct(),"relative_to_unit_occupied_RE_Es");
        expected=10*log10([1 .25]);
        errorDB=measured.RSRPPerAntenna_dB_re_UnitOccupiedRE_Es-expected;
        row=struct('Ports',csirs.NumCSIRSPorts,'DelaySamples',delaySamples, ...
            'RSRP1',measured.RSRPPerAntenna_dB_re_UnitOccupiedRE_Es(1), ...
            'RSRP2',measured.RSRPPerAntenna_dB_re_UnitOccupiedRE_Es(2), ...
            'MaxError_dB',max(abs(errorDB)));
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        fprintf('CSIRS_POWER ports=%d delay=%d max_error_dB=%g\n', ...
            row.Ports,row.DelaySamples,row.MaxError_dB);
        assert(measured.Available && row.MaxError_dB<0.5, ...
            'test:CSIRSWidebandCoherentCancellation', ...
            'Port-3000 linear RE power was corrupted by a pure phase ramp: %g dB.',row.MaxError_dB);
        assert(all(isnan(measured.RSRPPerAntenna_dBm)), ...
            'Normalized evidence must never claim absolute calibrated dBm.');
    end
end
disp(struct2table(rows));
ok=true;
end
