function ok=testCSIRSCDMPortPowerGeometry()
% Native TS 38.211 resource mappings, noiseless analytical receiver fixtures.
% Verify CDM power extraction for all 18 rows; this is not RF qualification.
setup6GRSimToolkit('Verbose',false);
c=nrCarrierConfig('NSizeGrid',24,'NStartGrid',7,'SubcarrierSpacing',30);
% Number of distinct frequency locations in Table 7.4.1.5.3-1.
locationCounts=[1 1 1 1 1 4 2 2 6 3 4 4 3 3 3 4 4 4];
cases=0;
for row=1:18
    symbols=2; if ismember(row,[13 14 16 17]), symbols=[2 8]; end
    density="one";
    if row==1
        density="three";
    elseif ismember(row,[2 3 11:18])
        density=["one","dot5even","dot5odd"];
    end
    for d=density
        rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',row, ...
            'Density',d,'SymbolLocations',symbols, ...
            'SubcarrierLocations',2*(0:locationCounts(row)-1),'RBOffset',3,'NumRB',9);
        X=nrResourceGrid(c,rs.NumCSIRSPorts);
        X(nrCSIRSIndices(c,rs))=nrCSIRS(c,rs);
        cdm=sixgr.phy.refsig.csirsCDMLengths(rs.CDMType);
        coefficients=10*exp(1i*(1:rs.NumCSIRSPorts)); coefficients(1)=.9+.3i;
        phase=repelem(exp(2i*pi*(0:23)'/24),12);
        received=sum(X.*reshape(coefficients,1,1,[]),3).*phase;
        grid=cat(3,received,.1i*received);
        power=sixgr.phy.refsig.measureCSIRSCDMPortPower(c,X,grid,cdm,[0 0]);
        expected=abs(coefficients(1))^2*[1 .01];
        assert(max(abs(power.SignedPort3000PowerPerBranch-expected))<1e-12 && ...
            power.PilotCount==nnz(X(:,:,1)) && ...
            power.CDMGroupCount*prod(cdm)==power.PilotCount && ...
            abs(power.UnitDisturbancePowerBias-1/prod(cdm))<1e-12, ...
            'Row %d density %s lost CDM orthogonality or reference-RE power.',row,d);
        cases=cases+1;
    end
end
assert(isequal(sixgr.phy.refsig.csirsCDMLengths("CDM4"),[2 2]) && ...
    isequal(sixgr.phy.refsig.csirsCDMLengths("CDM4-FD2-TD2"),[2 2]) && ...
    isequal(sixgr.phy.refsig.csirsCDMLengths("CDM8"),[2 4]) && ...
    isequal(sixgr.phy.refsig.csirsCDMLengths("CDM8-FD2-TD4"),[2 4]));
reject(@()sixgr.phy.refsig.csirsCDMLengths("CDM16"),'sixgr:phy:csirs:UnsupportedCDMType');
bad=X; first=find(bad(:,:,1)~=0,1); bad(first)=0;
reject(@()sixgr.phy.refsig.measureCSIRSCDMPortPower(c,bad,grid,cdm,[0 0]), ...
    'sixgr:refsig:CSICDMPowerTile');
fprintf('CSI_CDM_POWER_GEOMETRY_PASS native_rows=18 cases=%d partial_BWP_density_and_invalid_tile_guards=1\n',cases);
ok=true;
end

function reject(fn,id)
try, fn(); catch e, assert(strcmp(e.identifier,id),'Unexpected error: %s',e.identifier); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
