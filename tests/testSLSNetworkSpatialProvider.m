function ok=testSLSNetworkSpatialProvider()
% Actual NR frequency-domain fading; numerical grants test the network math.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run=struct('seed',113,'executionID','network_provider_component');
cfg.phy.carrier=struct('NSizeGrid',6,'SubcarrierSpacing',30);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9;
cfg.phy.carrier.NCellID=1; cfg.phy.numerology.scs_kHz=30;
cfg.phy.srs=struct('enable',true,'nPorts',2,'period_slots',5,'period_offset',4, ...
    'CSRS',0,'BSRS',0,'BHop',0,'bandwidthRB',4,'expectedNumRB',4, ...
    'SymbolStart',13,'NumSRSSymbols',1,'resourceSetUsage','codebook');
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('D',5,14);
cfg.phy.frameStructure.SlotState.CommonDirection(5,:)='U';
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("DL",5,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection(5,:)="UL";
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=23;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A', ...
    'delaySpread_s',30e-9,'doppler_Hz',5,'normalizeChannelOutputs',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
p=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
large=struct('Pathloss_dB',[80 90;85 80],'TxPower_dBm',30*ones(2));
g=struct('RNTI',1,'PRBSet',0:2,'SymbolAllocation',[0 4],'NumLayers',1, ...
    'PHYGrant',struct('PrecodingState',struct('MatrixPorts',[1;0])));
h=g; h.RNTI=2;
ctx=struct('TTI',1,'Direction',"DL",'Grant',g,'ServingCellID',1);
s=struct('TTI',1,'GrantsDL',g,'GrantsUL',struct([]),'GrantCellsDL',1, ...
    'GrantCellsUL',[],'LargeScaleState',large);
a=p.evaluate(ctx,s);
assert(size(a.Channel,3)==144 && all(a.ActiveInterferersPerRE==0));
assert(max(abs(a.TotalTransmitPower-1/72))<1e-14);
assert(any(abs(diff(a.Channel,1,3))>1e-15,'all'),'TDL frequency response must not be replaced by a scalar.');
s.GrantsDL=[g h]; s.GrantCellsDL=[1 2];
b=p.evaluate(ctx,s);
assert(all(b.ActiveInterferersPerRE==1));
ref=p.channel("DL",1,2,0,large,a.Coordinates0Based);
for k=1:size(ref,3)
    v=ref(:,:,k)*[1;0];
    assert(norm(b.ExternalCovariance(:,:,k)-a.ExternalCovariance(:,:,k)-(v*v')/72,'fro')<1e-20);
end
h.PRBSet=3:5; s.GrantsDL=[g h];
c=p.evaluate(ctx,s); assert(isequal(c.ExternalCovariance,a.ExternalCovariance));
% Same-BS MU grants split, never duplicate the configured per-RE power.
h.PRBSet=0:2; s.GrantsDL=[g h]; s.GrantCellsDL=[1 1];
d=p.evaluate(ctx,s); assert(max(abs(d.TotalTransmitPower-a.TotalTransmitPower/2))<1e-14);
% Reverse direction reuses the same realization without complex conjugation.
ul=p.channel("UL",1,1,0,large,a.Coordinates0Based);
assert(max(abs(ul-permute(a.Channel,[2 1 3])),[],'all')<1e-15);
% Reordered channel queries and another object reproduce the same drop.
p.channel("DL",2,2,4,large,a.Coordinates0Based);
again=p.channel("DL",1,1,0,large,a.Coordinates0Based);
assert(isequal(again,a.Channel));
p2=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
assert(isequal(p2.channel("DL",1,1,0,large,a.Coordinates0Based),a.Channel));
state=struct('AbsoluteSlot0',3,'ServingCells',[1 2],'LargeScaleState',large);
assert(isempty(p.observeSRS(state)),'No modeled SRS may be created outside its configured occasion.');
state.AbsoluteSlot0=4; reports=p.observeSRS(state);
assert(numel(reports)==2 && all([reports.SourceAbsoluteSlot0]==4) && ...
    all([reports.AvailableAbsoluteSlot0]==5));
assert(all(reports(1).Coordinates0Based(:,2)==13) && size(reports(1).ChannelEstimate,1)==2);
bpolicy=cfg.system.linkAbstraction.spatialFeedback; bpolicy.allowedRanks=[1 2];
queue=sixgr.system.abstraction.CausalSpatialFeedbackBuffer(bpolicy);
queue.append(reports(1),4);
assert(isempty(queue.select(1,1,4,5)) && ~isempty(queue.select(1,1,5,5)));
attenuated=large; attenuated.Pathloss_dB=large.Pathloss_dB+20;
assert(max(abs(p.channel("DL",1,1,0,attenuated,a.Coordinates0Based)-.1*a.Channel),[],'all')<1e-15);
bad=cfg; bad.rf.phaseNoise.enable=true;
reject(@()sixgr.system.abstraction.NetworkSpatialGrantProvider(bad),'sixgr:abstraction:NetworkRFUnsupported');
s.GrantsUL=g;
reject(@()p.evaluate(ctx,s),'sixgr:abstraction:CrossLinkUnsupported');
fprintf('SLS_NETWORK_SPATIAL_PROVIDER_PASS resources=%d profile=TDL-A qualification=component_only\n',size(a.Channel,3));
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s',id);
end
