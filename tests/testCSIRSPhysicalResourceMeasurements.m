function ok=testCSIRSPhysicalResourceMeasurements()
% Generated NR pilot grids with explicitly analytic powers/interference.
% Check RSSI bandwidth/symbol/branch semantics, not field qualification.
setup6GRSimToolkit('Verbose',false);
for scs=[15 30 60]
    carrier=nrCarrierConfig('NSizeGrid',48,'NStartGrid',10,'SubcarrierSpacing',scs);
    csirs=nrCSIRSConfig('RowNumber',2,'Density','one','NumRB',24, ...
        'RBOffset',6,'SymbolLocations',6,'SubcarrierLocations',0,'CSIRSPeriod','on');
    indices=nrCSIRSIndices(carrier,csirs);
    symbols=nrCSIRS(carrier,csirs);
    grid=nrResourceGrid(carrier,2);
    watts=[1e-11 1e-10];
    for branch=1:2
        plane=complex(ones(size(grid,1),size(grid,2))*sqrt(3e-12));
        plane(indices)=symbols*sqrt(watts(branch));
        grid(:,:,branch)=plane;
    end
    measured=sixgr.phy.refsig.measureCSIRSPhysicalResource(carrier,csirs,grid);
    assert(measured.Available && measured.NumReceiveAntennas==2);
    assert(measured.NumRB==24 && measured.FirstPRB0Based==16 && ...
        measured.Bandwidth_Hz==24*12*scs*1000 && measured.SymbolIndices0Based==6);
    for branch=1:2
        expectedRSRP=10*log10(watts(branch))+30;
        % Sum all 12 subcarriers per measurement PRB, not CSI pilot REs
        % alone, and only the configured CSI-RS measurement symbols.
        power=abs(grid(6*12+(1:24*12),7,branch)).^2;
        expectedRSSI=10*log10(sum(power(:)))+30;
        assert(abs(measured.RSRPPerAntenna_dBm(branch)-expectedRSRP)<1e-10);
        assert(abs(measured.RSSIPerAntenna_dBm(branch)-expectedRSSI)<1e-10);
        expectedRSRQ=10*log10(24)+expectedRSRP-expectedRSSI;
        assert(abs(measured.RSRQPerAntenna_dB(branch)-expectedRSRQ)<1e-10);
    end
    % Energy outside the measurement bandwidth/symbol window is not RSSI.
    changed=grid; changed(1:72,:,:)=100; changed(:,1:6,:)=100;
    other=sixgr.phy.refsig.measureCSIRSPhysicalResource(carrier,csirs,changed);
    assert(isequaln(measured,other));
    csirs.CSIRSPeriod=[4 1];
    absent=sixgr.phy.refsig.measureCSIRSPhysicalResource(carrier,csirs,grid);
    assert(~absent.Available && isempty(absent.SymbolIndices0Based));
end
ok=true;
disp('CSIRS_PHYSICAL_RESOURCE_MEASUREMENTS_PASS');
end
