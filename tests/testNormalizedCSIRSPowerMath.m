function ok=testNormalizedCSIRSPowerMath()
% Independent OFDM/unit-grid oracle: no channel, fitted offset or SNR target.
setup6GRSimToolkit('Verbose',false);
cfg.integration.run_mode="FIXED_SNR_SWEEP";
cfg.integration.configured_snr_is_link_authority=true;
for nRB=[25 52]
    carrier=nrCarrierConfig('NSizeGrid',nRB,'SubcarrierSpacing',15);
    csirs=nrCSIRSConfig('RowNumber',2,'Density','one','NumRB',nRB, ...
        'RBOffset',0,'SymbolLocations',6,'SubcarrierLocations',0,'CSIRSPeriod','on');
    index=nrCSIRSIndices(carrier,csirs); symbols=nrCSIRS(carrier,csirs);
    for amplitude=[0.25 1]
        grid=nrResourceGrid(carrier,2);
        branchGain=amplitude*[0.5 1];
        for branch=1:2
            plane=complex(ones(size(grid,1),size(grid,2))*amplitude/16);
            plane(index)=symbols*branchGain(branch);
            grid(:,:,branch)=plane;
        end
        [wave,info]=nrOFDMModulate(carrier,grid,'Windowing',0);
        received=nrOFDMDemodulate(carrier,wave);
        assert(max(abs(received(:)-grid(:)))<1e-10);
        scale=double(info.Nfft)*sqrt(1000);
        raw=nrCSIRSMeasurements(carrier,csirs,received/scale);
        [rsrp,selected]=max(raw.RSRPPerAntenna);
        input=struct('PhysicalMeasurementStatus',"available", ...
            'MeasurementRSRP_dBm',rsrp,'MeasurementRSSI_dBm',raw.RSSIPerAntenna(selected), ...
            'MeasurementRSRQ_dB',raw.RSRQPerAntenna(selected), ...
            'MeasurementRSRQNumeratorRSRP_dBm',rsrp, ...
            'MeasurementRSRQDenominatorRSSI_dBm',raw.RSSIPerAntenna(selected), ...
            'MeasurementRSRPPerReceiveAntenna_dBm',token(raw.RSRPPerAntenna), ...
            'MeasurementRSRPPerResource_dBm',token(rsrp), ...
            'MeasurementRSSIPerReceiveAntenna_dBm',token(raw.RSSIPerAntenna), ...
            'MeasurementFFTSize',double(info.Nfft),'MeasurementGridScaleToSqrtW',scale);
        actual=sixgr.phy.refsig.normalizeCSIRSPowerReference(input,cfg);
        % Prove the primary DL evidence selects this reference plane, not
        % an unrelated post-front-end diagnostic carrying a different gain.
        actual.MeasurementRelativeRSRP_dB=123;
        bound=sixgr.link.deriveMeasuredPHYEvidence(struct('CSIRSObservation',actual));
        assert(bound.MeasuredCSIRSRPRelative_dB==actual.MeasurementRSRP_dB_re_UnitOccupiedRE_Es);
        expectedRSRP=20*log10(max(branchGain));
        % Independent RSSI: all subcarriers in the selected CSI symbol.
        expectedRSSI=10*log10(sum(abs(grid(:,7,selected)).^2));
        fprintf('CSIRS_UNIT_GRID Nfft=%d amplitude=%g RSRP_actual=%g expected=%g RSSI_actual=%g expected=%g\n', ...
            info.Nfft,amplitude,actual.MeasurementRSRP_dB_re_UnitOccupiedRE_Es, ...
            expectedRSRP,actual.MeasurementRSSI_dB_re_UnitOccupiedRE_Es,expectedRSSI);
        assert(abs(actual.MeasurementRSRP_dB_re_UnitOccupiedRE_Es-expectedRSRP)<1e-9, ...
            'test:NormalizedCSIRSPowerScale','Unit-RE RSRP must match the independently authored resource-grid energy.');
        assert(abs(actual.MeasurementRSSI_dB_re_UnitOccupiedRE_Es-expectedRSSI)<1e-9);
        assert(abs(actual.MeasurementRSRQ_dB-(10*log10(nRB)+expectedRSRP-expectedRSSI))<1e-9);
        assert(actual.MeasurementRSRQ_dB==input.MeasurementRSRQ_dB && ...
            abs(actual.MeasurementRSRQNumeratorRSRP_dB_re_UnitOccupiedRE_Es-expectedRSRP)<1e-9 && ...
            abs(actual.MeasurementRSRQDenominatorRSSI_dB_re_UnitOccupiedRE_Es-expectedRSSI)<1e-9);
        branches=sscanf(char(erase(actual.MeasurementRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es,["[","]"])), '%f');
        assert(max(abs(branches(:)-20*log10(branchGain(:))))<1e-9);
        tx=sixgr.phy.refsig.measureCSIRSRPFromWaveform(carrier,csirs,wave, ...
            'PhysicalIndices',[double(index(:));double(index(:))+size(grid,1)*size(grid,2)]);
        assert(tx.Available);
        txUnit=sixgr.phy.refsig.convertCSIRSPowerToUnitRE(tx.RSRP_dBm,tx.Nfft,tx.GridScaleToSqrtW);
        assert(abs(txUnit-10*log10(sum(branchGain.^2)))<1e-9, ...
            'Actual TX connector powers must use the same unit-RE reference as the RX measurement.');
        physical=cfg; physical.integration.configured_snr_is_link_authority=false;
        assert(isequaln(input,sixgr.phy.refsig.normalizeCSIRSPowerReference(input,physical)));
    end
end
ok=true;
disp('NORMALIZED_CSIRS_POWER_MATH_PASS independent_OFDM_grid_RSRP_RSSI_RSRQ=1');
end
function value=token(values)
value="["+strjoin(compose('%.15g',double(values(:).')),' ')+"]";
end
