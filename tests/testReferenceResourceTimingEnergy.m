function ok=testReferenceResourceTimingEnergy()
% Native NR reference/OFDM component; fixed channels are declared fixtures.
% No CDL, integrated receiver, noise or statistical qualification is claimed.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30,'NCellID',17,'NSlot',1);
reference=nrCSIRSConfig('CSIRSType','nzp','RowNumber',2,'Density','one', ...
    'SubcarrierLocations',0,'NumRB',24,'RBOffset',0,'NID',17);
indices=[]; symbols=[]; groups=[];
for n=1:2
    reference.SymbolLocations=3+7*(n-1);
    ind=nrCSIRSIndices(carrier,reference); sym=nrCSIRS(carrier,reference);
    indices=[indices;ind(:)]; symbols=[symbols;sym(:)]; %#ok<AGROW>
    groups=[groups;repmat(7+12*(n-1),numel(ind),1)]; %#ok<AGROW>
end
delay=7; searchWindow=[0 33];
for phase=[0 pi]
    grid=nrResourceGrid(carrier,1);
    grid(indices)=symbols.*exp(1i*phase*(groups==19));
    tx=nrOFDMModulate(carrier,grid,'Windowing',0);
    % Separate RX phases must not be summed coherently either.
    received=tx*[1,exp(1i*.73)];
    capture=[zeros(delay,2);received;zeros(searchWindow(2)-delay,2)];
    [energy,evidence]=sixgr.phy.sync.referenceResourceTimingEnergy( ...
        carrier,capture,indices,symbols,searchWindow,groups);
    [~,peak]=max(energy);
    assert(peak-1==delay && evidence.ResourceCount==2 && ...
        isequal(evidence.ResourceIDs,[7;19]) && ...
        evidence.NativeCorrelationCalls==2 && ~evidence.OracleTimingUsed && ...
        ~evidence.ReceiverZeroPaddingUsed);
    % Independently sum the two native resource correlations, without
    % reusing any returned per-resource diagnostic values.
    expected=zeros(size(energy));
    for id=[7 19]
        take=groups==id;
        [~,mag]=nrTimingEstimate(carrier,capture,indices(take),symbols(take));
        expected=expected+sum(abs(mag(1:34,:)).^2,2);
    end
    assert(isequal(energy,expected),'Every resource/RX energy must be retained exactly.');
    % One resource is the existing reference-correlation contract, not a
    % different normalization or a separately synthesized observation.
    one=ones(size(groups));
    singleEnergy=sixgr.phy.sync.referenceResourceTimingEnergy( ...
        carrier,capture,indices,symbols,searchWindow,one);
    [~,mag]=nrTimingEstimate(carrier,capture,indices,symbols);
    assert(isequal(singleEnergy,sum(abs(mag(1:34,:)).^2,2)));
    perm=numel(indices):-1:1;
    permuted=sixgr.phy.sync.referenceResourceTimingEnergy( ...
        carrier,capture,indices(perm),symbols(perm),searchWindow,groups(perm));
    assert(isequal(permuted,energy),'Reference ordering must not change the two-resource measurement.');
end
expectFailure(@()sixgr.phy.sync.referenceResourceTimingEnergy( ...
    carrier,capture,indices,symbols,searchWindow,groups(1:end-1)), ...
    'sixgr:phy:sync:InvalidReferenceResourceTiming');
duplicated=indices; duplicated(end)=duplicated(1);
expectFailure(@()sixgr.phy.sync.referenceResourceTimingEnergy( ...
    carrier,capture,duplicated,symbols,searchWindow,groups), ...
    'sixgr:phy:sync:InvalidReferenceResourceTiming');
expectFailure(@()sixgr.phy.sync.referenceResourceTimingEnergy( ...
    carrier,capture(1:end-1,:),indices,symbols,searchWindow,groups), ...
    'sixgr:phy:sync:IncompleteULReferenceObservation');
expectFailure(@()sixgr.phy.sync.referenceResourceTimingEnergy( ...
    carrier,capture,indices,zeros(size(symbols)),searchWindow,groups), ...
    'sixgr:phy:sync:InvalidReferenceResourceTiming');
fprintf('REFERENCE_RESOURCE_TIMING_PASS phases=2 resources=2 rx=2 negative_cases=4 integrated_qualification=0\n');
ok=true;
end

function expectFailure(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier),'Unexpected failure: %s',cause.identifier);
    return;
end
error('test:ExpectedTimingContractFailure','Expected invalid reference/capture to be rejected.');
end
