function ok=testSLSMultiBeamMapping(fullBand)
% Real configured 64-TXRU/eight-beam mapping; not RF or BLER qualification.
if nargin<1, fullBand=false; end
sc=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/h4_100_tdla30_connected_adaptive.yaml');
cfg=sixgr.lls6g.buildInternalConfig(sc,tempname);
fragment=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg=sixgr.util.mergeStruct(cfg,fragment);
cfg.run.executionID='multibeam_component';
cfg.system.linkAbstraction.dlFeedback.enabled=true;
cfg.system.linkAbstraction.dlFeedback.allowedRanks=1;
cfg.system.linkAbstraction.networkSpatial.dlAntennaBasis='configured_csirs_elements';
cfg.rf=struct(); cfg.phy.impairments=struct(); % explicit ideal-RF component arm
cfg.phy.csi.allowUncalibratedBLERLUT=true;
q=sixgr.system.abstraction.CausalDLCSIFeedback(cfg);
B=cfg.phy.csirs.precoderMatrices;
assert(isequal(size(B),[64 4 8]));
% Deliberately stronger earlier beam in one sweep/report occasion. The
% later source slot must not automatically override the better CRI.
for k=1:8
    H=repmat(eye(4)/(k*k),1,1,3);
    o=struct('ObservationID',"beam_"+k,'ExecutionID',string(cfg.run.executionID), ...
        'UEIndex',1,'ServingCell',1,'SourceAbsoluteSlot0',k-1, ...
        'AvailableAbsoluteSlot0',14,'ReportAbsoluteSlot0',13,'CRI',k-1, ...
        'ChannelEstimate',H,'ExternalCovariance',eye(4),'TotalTransmitPower',100, ...
        'PortToElementMatrix',B(:,:,k),'RFProfileID',"ideal_rf_no_impairments", ...
        'SourceClassification',"modeled_csi_not_waveform_measurement");
    q.append(o,k-1);
end
assert(isempty(q.select(1,1,13,20)));
r=q.select(1,1,14,20); assert(r.CRI==0 && r.SourceAbsoluteSlot0==0);
assert(norm(r.MatrixElements-B(:,:,1)*r.MatrixPorts,'fro')<1e-12);
assert(abs(norm(r.MatrixElements,'fro')-1)<1e-12);
cfg.phy.csi.selectedCRI=r.CRI; cfg.phy.beamManagement.selectedCRI=r.CRI;
g=sixgr.link.resolveWaveformGrant(cfg,'DL',21);
r=q.select(1,1,g.ControlAbsoluteSlot,g.ScheduledAbsoluteSlot);
g.RNTI=1; g.ServingCell=1; g.NumLayers=r.RI; g.NumCodewords=1;
g.PMI=r.PMI; g.CRI=r.CRI;
g.PrecodingMatrixLogicalPorts=r.MatrixPorts; g.PrecodingMatrix=[];
r.RNTI=1;
r.BindingSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(r)),'UTF-8'))));
g.ModeledCSIFeedback=r;
g.PHYGrant=struct();
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,'DL',g);
assert(isequal(size(g.PHYGrant.PrecodingState.MatrixPorts),[64 r.RI]));
assert(norm(g.PHYGrant.PrecodingState.MatrixPorts-r.MatrixElements,'fro')<1e-12);
% Exercise the real planner-to-producer resource identity, not a fabricated
% calendar. Resource hashes/order must not choose the physical beam basis.
cfg.channel.normalizeChannelOutputs=false;
% Keep the real 64-TXRU/eight-beam matrix while bounding the component
% response tensor. This is not a 100-MHz performance/array campaign.
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=0;
cfg.channel.bandwidth_Hz=10e6; cfg.phy.channelBandwidth_MHz=10;
cfg.frequency.bandwidth_hz=10e6; cfg.frequency.n_size_grid=24;
cfg.phy.bwp.dl.NSizeBWP=24; cfg.phy.bwp.dl.NStartBWP=0;
cfg.phy.bwp.ul.NSizeBWP=24; cfg.phy.bwp.ul.NStartBWP=0;
cfg.phy.ssb.enable=false; cfg.phy.prach.enable=false; % no access waveforms in this component check
cfg.phy.csirs.numRBsByResource=24*ones(1,8);
cfg.phy.csirs.rbOffsetsByResource=zeros(1,8);
cfg.phy.csirs.numRB=24;
if fullBand
    cfg.phy.carrier.NSizeGrid=273;
    cfg.channel.bandwidth_Hz=100e6; cfg.phy.channelBandwidth_MHz=100;
    cfg.frequency.bandwidth_hz=100e6; cfg.frequency.n_size_grid=273;
    cfg.phy.bwp.dl.NSizeBWP=273; cfg.phy.bwp.ul.NSizeBWP=273;
    cfg.phy.csirs.numRBsByResource=273*ones(1,8);
    cfg.phy.csirs.numRB=273;
    cfg.system.linkAbstraction.networkSpatial.channelResponseSampling='static_exact';
    cfg.channel.doppler_Hz=0; cfg.channel.fading.maxDoppler_Hz=0;
end
planning=cfg; planning.run.totalSlots=26;
planning.outputs.plannedAllocationEncoding='exact_periodic_templates';
calendar=sixgr.truth.buildPlannedREAllocation(planning,'TargetChannels',"CSI_RS");
assert(isequal(sort(unique(calendar.csi_resource_index)).',0:7));
fullProvider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
observed=struct([]);
large=struct('Pathloss_dB',80,'TxPower_dBm',30);
for slot=0:25
    st=struct('AbsoluteSlot0',slot,'ServingCells',1,'LargeScaleState',large,'CommonChannelAllocations',calendar);
    rows=fullProvider.observeCSI(st); observed=[observed rows]; %#ok<AGROW>
    if ~isempty(observed) && numel(unique([observed.CRI]))==8, break; end
end
assert(~isempty(observed) && isequal(sort(unique([observed.CRI])),0:7));
for row=observed
    raw=fullProvider.channel("DL",1,1,row.SourceAbsoluteSlot0,large,row.Coordinates0Based);
    assert(isequal(row.PortToElementMatrix,B(:,:,row.CRI+1)));
    for z=1:size(raw,3)
        assert(norm(row.ChannelEstimate(:,:,z)-raw(:,:,z)*B(:,:,row.CRI+1),'fro')<1e-12);
    end
end
% The actual frequency-selective provider executes this physical matrix.
cfg.phy.carrier.NSizeGrid=6; cfg.phy.carrier.NStartGrid=0;
cfg.channel.normalizeChannelOutputs=false;
p=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
g.PRBSet=0:1; g.SymbolAllocation=[0 2];
s=struct('TTI',21,'GrantsDL',g,'GrantsUL',struct([]),'GrantCellsDL',1, ...
    'GrantCellsUL',[],'LargeScaleState',large);
ctx=struct('TTI',21,'Direction',"DL",'Grant',g,'ServingCellID',1);
a=p.evaluate(ctx,s);
assert(size(a.Channel,2)==64 && norm(a.Precoder-r.MatrixElements,'fro')<1e-12);
assert(max(abs(a.TotalTransmitPower-1/72))<1e-12);
% A changed installed beam must invalidate the binding, even if shape fits.
bad=cfg; bad.phy.csirs.precoderMatrices(:,:,r.CRI+1)=-B(:,:,r.CRI+1);
reject(@()sixgr.system.abstraction.CausalDLCSIFeedback.validateGrant(bad,g), ...
    'sixgr:abstraction:DLCSIBinding');
bad=cfg; bad.phy.csirs.precoderMatrices=2*B;
reject(@()sixgr.system.abstraction.NetworkSpatialGrantProvider(bad), ...
    'sixgr:abstraction:DLCSIPortBasis');
fprintf('SLS_MULTIBEAM_64TXRU_MAPPING_PASS beams=8 ports=4 fullband_static=%d qualification=component_only\n',fullBand);
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'%s: %s',ME.identifier,ME.message); return; end
error('test:NoRejection','Expected %s',id);
end
