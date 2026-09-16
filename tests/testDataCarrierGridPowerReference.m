function ok=testDataCarrierGridPowerReference()
% Independent grid-energy/unit fixture, not an RF or full-run qualification.
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP','configured_snr_is_link_authority',true);
grid=reshape(complex(sin(1:240*14*2),cos((1:240*14*2)/3)),240,14,2);
original=grid; symbols=[2 3 4];
expected=zeros(3,2);
for r=1:2
    for s=1:3
        for k=1:240
            expected(s,r)=expected(s,r)+real(grid(k,symbols(s)+1,r))^2+imag(grid(k,symbols(s)+1,r))^2;
        end
    end
end
for nfft=[512 1024]
    relative=sixgr.truth.measureDataCarrierGridPower(grid,nfft,symbols,cfg);
    assert(relative.PowerReferencePlane=="normalized_fixed_esn0_unit_occupied_re_es" && ...
        ~isfield(relative,'RSSIPerAntenna_dBm') && ~isfield(relative,'SymbolPowerPerAntenna_W'));
    assert(max(abs(relative.SymbolPowerPerAntenna_UnitOccupiedRE_Es-expected),[],'all')<1e-10);
    assert(max(abs(relative.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es-10*log10(mean(expected,1))))<1e-10);
    absolute=cfg; absolute.integration.configured_snr_is_link_authority=false;
    physical=sixgr.truth.measureDataCarrierGridPower(grid,nfft,symbols,absolute);
    assert(physical.PowerReferencePlane=="receiver_antenna_connector_pre_composite_front_end" && ...
        ~isfield(physical,'RSSIPerAntenna_dB_re_UnitOccupiedRE_Es'));
    assert(max(abs(physical.SymbolPowerPerAntenna_W-expected/(nfft^2*1000)),[],'all')<1e-16);
    assert(max(abs(relative.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es-physical.RSSIPerAntenna_dBm-20*log10(nfft)))<1e-10);
end
assert(isequal(grid,original),'Power reporting must not change received samples.');
rejected=false;
try, sixgr.truth.measureDataCarrierGridPower(zeros(size(grid)),512,symbols,cfg);
catch cause, rejected=string(cause.identifier)=="sixgr:truth:UnavailablePhysicalCarrierPower"; end
assert(rejected,'Zero-energy observations must not manufacture finite RSSI.');
ok=true; disp('DATA_CARRIER_GRID_POWER_REFERENCE_PASS independent_energy_units_no_IQ_mutation');
end
