function ok=testH4100CSIIMMeasurement()
% Exact H4 configuration and independent full-band received-grid fixtures.
% This verifies resource/receiver authority, not CDL waveform, UCI delivery,
% statistical estimator qualification or complete scenario acceptance.
setup6GRSimToolkit('Verbose',false); rng(73512,'twister');
source=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml');
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,6);
c=sixgr.phy.grid.makeCarrier(cfg);
assert(c.NSizeGrid==273 && c.SubcarrierSpacing==30 && cfg.phy.csiim.enabled);
plan=sixgr.phy.refsig.csiIMResource(c,cfg);
assert(plan.Scheduled && plan.NumRE==1092 && ...
    all(plan.Symbols0Based==13) && isequal(unique(mod(plan.Subcarriers0Based,12)),(4:7).'));
[~,~,info]=sixgr.phy.refsig.csirs(c,cfg);
assert(numel(info.Resources)==8);
K=12*c.NSizeGrid; L=c.SymbolsPerSlot; grid=complex(zeros(K,L,4));
for k=1:numel(info.Resources)
    resource=info.Resources(k);
    reference=nrResourceGrid(c,resource.NumPorts);
    reference(resource.Indices)=resource.Symbols;
    gain=1+.04*(k-1);
    H=gain*diag([1 .8 .6 .4]);
    y=reshape(reshape(reference,[],4)*H.',K,L,4);
    phase=exp(-1i*2*pi*(0:K-1)'/600);
    grid=grid+y.*phase;
end
physical=reshape(grid,[],4);
assert(all(physical(plan.PhysicalIndices1Based,:)==0,'all'));
variance=10^(-12/10);
grid=grid+sqrt(variance/2)*complex(randn(size(grid)),randn(size(grid)));
received=struct('OFDMGrid',grid,'OFDMInfo',nrOFDMInfo(c), ...
    'InterferenceCovariance',[],'InterferenceCovarianceIncludesNoise',false);
options=struct('PhysicalMeasurementGrid',grid,'PhysicalMeasurementOFDMInfo',nrOFDMInfo(c), ...
    'PhysicalMeasurementGridStatus',"available_exact_pre_front_end_grid", ...
    'PhysicalMeasurementReferencePlane',"normalized_received_grid_fixture", ...
    'PhysicalMeasurementSource',"independent_frequency_selective_received_grid_fixture");
rx=sixgr.phy.refsig.receiveCSIRSFromGrid(c,cfg,received,options);
assert(rx.CSIRSChannelEstimation.Available && ~isempty(rx.CSIMeasurementState));
im=sixgr.phy.refsig.measureCSIIM(c,cfg,grid);
assert(im.Available && im.SampleCount==1092 && ...
    abs(10*log10(im.MeanPower/variance))<.5);
assert(rx.CSIRSNoiseVar==im.MeanPower && ...
    rx.CSIMeasurementState.NoiseVariance==im.MeanPower, ...
    'CSI/PMI input must consume the independently measured muted-RE disturbance.');
measurements=rx.CSIRSChannelEstimation.ResourceMeasurements;
for k=1:numel(measurements)
    assert(measurements(k).NoiseVariance==im.MeanPower);
    sinr=sixgr.phy.refsig.measureCSISINRFromResourceGrid( ...
        c,info.Resources(k).Configuration,grid,cfg);
    expected=12+20*log10(1+.04*(k-1));
    assert(sinr.Available && abs(sinr.CSI_SINR_dB-expected)<1.5 && ...
        sinr.DisturbanceSource=="configured_CSI_IM_received_RE_second_moment");
end
poison=cfg; poison.channel.snr_dB=-120;
poisonOptions=options;
poisonOptions.ReceivedExecutionEvidence=struct('InjectedNoiseVariance',1e9, ...
    'ReferenceAWGNGridNoiseVariance',1e9,'AppliedAWGNSNR_dB',-120);
again=sixgr.phy.refsig.receiveCSIRSFromGrid(c,poison,received,poisonOptions);
assert(isequaln(rx.CSIRSChannelEstimate,again.CSIRSChannelEstimate) && ...
    rx.CSIMeasurementState.Digest==again.CSIMeasurementState.Digest);
% A coherent interferer is not removed as a sample mean on the muted REs.
contaminated=reshape(grid,[],4);
contaminated(plan.PhysicalIndices1Based,:)= ...
    contaminated(plan.PhysicalIndices1Based,:)+sqrt(.2)*[1 1i -1 -1i];
contaminated=reshape(contaminated,size(grid));
observed=sixgr.phy.refsig.measureCSIIM(c,cfg,contaminated);
assert(abs(10*log10(observed.MeanPower/(variance+.2)))<.5);
% The exact planner must publish both periodic muted-resource ownership
% and its lack of a transmit port. No synthetic observation is created.
[planned,checks]=sixgr.truth.buildPlannedREAllocation(cfg,'TargetChannels',"CSI_IM");
check=checks(checks.feature=="CSI_IM",:);
assert(check.resolved && check.exact_re_count==10920);
muted=planned(planned.channel=="CSI_IM",:);
assert(height(muted)==273 && all(muted.component=="MUTED") && ...
    all(isnan(muted.port_index)) && all(muted.occurrence_count==10) && ...
    all(muted.occurrence_slots==join(string(5:20:185),'|')));
% Every supported data rank reserves those same REs before TBS/coding.
for rank=[1 2 4]
    current=cfg; current.phy.pdsch.numLayers=rank;
    current.phy.pdsch.DMRSPortSet=0:rank-1;
    [indices,allocation]=sixgr.phy.grid.allocREsPDSCH(c,current);
    assert(all(ismember(plan.PhysicalIndices1Based-1,allocation.CSIIMReservation.PhysicalIndices1Based-1)) && ...
        isempty(intersect(mod(double(indices(:))-1,K*L)+1,plan.PhysicalIndices1Based)));
end
% Reject genuinely colliding or non-DL measurement resources.
bad=cfg; bad.phy.csiim.subcarrier=0;
localReject(@()sixgr.phy.grid.allocREsPDSCH(c,bad),'sixgr:phy:csiim:PTRSCollision');
bad=cfg; bad.phy.csiim.offset_slots=9;
[~,badChecks]=sixgr.truth.buildPlannedREAllocation(bad,'TargetChannels',"CSI_IM");
badCheck=badChecks(badChecks.feature=="CSI_IM",:);
assert(~badCheck.resolved && badCheck.error_id=="sixgr:truth:CSIIMNotDLAvailable");
bad=cfg; bad.phy.csiim.offset_slots=4;
localReject(@()sixgr.link.prepareCSIRSTransmission(bad,40,'RuntimeSlot',6), ...
    'sixgr:link:CSIRSCSIIMCalendarMismatch');
fprintf('H4_CSIIM_MEASUREMENT_PASS ports=4 resources=8 muted_RE=1092 noise=%g expected_noise=%g\n', ...
    im.MeanPower,variance);
ok=true;
end

function localReject(fn,id)
try, fn(); catch err, assert(strcmp(err.identifier,id),'Unexpected error: %s',err.identifier); return; end
error('test:MissingCSIIMGuard','Expected %s.',id);
end
