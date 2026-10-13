function ok=testConnectedPDCCHFrequencyAuthority()
% H4 configured frequency coordinates, independently checked in Toolbox REs.
% This is a control-resource component test, not a connected-run acceptance.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_adaptive.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg);
context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
assert(carrier.NSizeGrid==273 && carrier.SubcarrierSpacing==30);
assert(context.Data.CORESETID==1 && cfg.phy.pdcch.coreset.rbStart==112);
% Literal expected PRBs: do not derive expectations from the same factory.
starts=[0 6 112 225];
for start=starts
    trial=cfg; trial.phy.pdcch.coreset.rbStart=start;
    localCoordinates(trial,carrier,context,start+(0:47));
end
leading=cfg;
leading.phy.pdcch.coreset.frequencyResources=[0 0 ones(1,8)];
localCoordinates(leading,carrier,context,124:171);
bad=cfg; bad.phy.pdcch.coreset.rbStart=226;
localReject(@()localBuild(bad,carrier,context), ...
    'sixgr:phy:pdcch:CORESETOutsideBWP');
bad=cfg; bad.phy.pdcch.coreset.rbOffsetR16Supported=false;
localReject(@()localBuild(bad,carrier,context), ...
    'sixgr:phy:pdcch:MissingCORESETRBOffsetCapability');
for start=[-1 .5 NaN]
    bad=cfg; bad.phy.pdcch.coreset.rbStart=start;
    localReject(@()localBuild(bad,carrier,context), ...
        'sixgr:phy:pdcch:invalid_coreset_frequency_resources');
end
bad=cfg;
bad.phy.pdcch.operatorControl.connected_dci.coreset_id=0;
bad.phy.pdcch.coreset.id=0;
zeroContext=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(bad,'1_1');
localReject(@()localBuild(bad,carrier,zeroContext), ...
    'sixgr:phy:pdcch:CORESETZeroOffsetUnsupported');
% Width alone is insufficient: leading unallocated groups still occupy
% frequency-coordinate span before the final allocated group.
data=s.toStruct(); data.control.coreset_rb_start=220;
data.control.coreset_frequency_resources=[0 ones(1,8)];
localReject(@()sixgr.lls6g.buildInternalConfig(data,tempname), ...
    'sixgr:lls6g:CORESETPlacementOutsideBWP');
data=s.toStruct(); data.control.coreset_rb_offset_r16_capability=false;
localReject(@()sixgr.lls6g.buildInternalConfig(data,tempname), ...
    'sixgr:phy:pdcch:MissingCORESETRBOffsetCapability');
[planned,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels',"PDCCH");
sixgr.truth.assertAllocationPreflight(checks);
rows=planned(planned.channel=="PDCCH",:);
assert(~isempty(rows) && all(rows.subcarrier_start>=112*12) && ...
    all(rows.subcarrier_start+rows.subcarrier_count<=160*12), ...
    'Planned connected PDCCH must use the actual configured PRB interval.');
fprintf('CONNECTED_PDCCH_FREQUENCY_AUTHORITY_PASS geometry_cases=5 negative_cases=8 H4_PRBs=112:159\n');
ok=true;
end

function localCoordinates(cfg,carrier,context,expectedPRBs)
for receiver=[false true]
    p=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build( ...
        cfg,carrier,context.Data.RNTIValue,receiver);
    % Cover the whole CORESET with DM-RS, independent of the selected CCE.
    p.CORESET.PrecoderGranularity='allContiguousRBs';
    [data,~,dmrs]=nrPDCCHResources(carrier,p,'IndexStyle','subscript');
    measured=unique(floor((double(dmrs(:,1))-1)/12)).';
    assert(isequal(measured,expectedPRBs), ...
        'Configured CORESET placement was ignored, rounded or shifted twice.');
    assert(all(ismember(floor((double(data(:,1))-1)/12),expectedPRBs)));
    offset=mod(expectedPRBs(1),6);
    assert(p.CORESET.NCCE==16 && ...
        ((offset==0 && isempty(p.CORESET.RBOffset)) || isequal(p.CORESET.RBOffset,offset)));
end
end

function p=localBuild(cfg,carrier,context)
p=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfg,carrier,context.Data.RNTIValue,false);
end

function localReject(fn,id)
try
    fn();
catch err
    assert(strcmp(err.identifier,id),'Expected %s, received %s: %s',id,err.identifier,err.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
