function ok=testSLSNetworkSpatialProvider(options)
% Actual NR frequency-domain fading; numerical grants test the network math.
arguments
    options.WaveformNSizeGrid (1,1) double {mustBeInteger,mustBePositive}=6
end
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
g=struct('RNTI',4660,'UEIndex',1,'PRBSet',0:2,'SymbolAllocation',[0 4],'NumLayers',1, ...
    'PHYGrant',struct('PrecodingState',struct('MatrixPorts',[1;0])));
h=g; h.RNTI=4661; h.UEIndex=2;
ctx=struct('TTI',1,'Direction',"DL",'Grant',g,'ServingCellID',1);
s=struct('TTI',1,'GrantsDL',g,'GrantsUL',struct([]),'GrantCellsDL',1, ...
    'GrantCellsUL',[],'LargeScaleState',large);
a=p.evaluate(ctx,s);
assert(~a.ChannelCyclicPrefixSupport.CircularConvolutionSupported && ...
    ~a.StaticUnwindowedCircularConvolutionSupported && ~a.ResidualISIICIIncluded, ...
    'The narrow-grid finite-filter leakage must remain explicitly unmodeled.');
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
localIndependentWaveformCovariance(cfg,large,g,options.WaveformNSizeGrid);
fprintf('SLS_NETWORK_SPATIAL_PROVIDER_PASS resources=%d profile=TDL-A qualification=component_only\n',size(a.Channel,3));
ok=true;
end

function localIndependentWaveformCovariance(cfg,large,base,nSizeGrid)
% Independent signal-domain check of the scheduled-data covariance. Probe
% every independent RE/layer through native time-domain channel filtering;
% do NOT multiply by the modeled H or call nrPerfectChannelEstimate here.
% This is a linear OFDM propagation check, not decoded BLER or qualification
% of the intentionally absent common-control/reference-signal population.
cfg.channel.doppler_Hz=0;
cfg.phy.carrier.NSizeGrid=nSizeGrid;
carrier=nrCarrierConfig('NSizeGrid',cfg.phy.carrier.NSizeGrid, ...
    'SubcarrierSpacing',cfg.phy.carrier.SubcarrierSpacing);
ofdm=nrOFDMInfo(carrier);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
audit=table();
for direction=["DL","UL"]
    for rank=1:2
        g=base; g.NumLayers=rank;
        W=[1;1i]/sqrt(2);
        if rank==2, W=[1 1i;1i 1]/2; end
        g.PHYGrant.PrecodingState.MatrixPorts=W;
        h=g; h.RNTI=4661; h.UEIndex=2; h.PRBSet=1:3; h.SymbolAllocation=[1 2];
        provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
        state=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
            'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',large);
        state.("Grants"+direction)=g; state.("GrantCells"+direction)=1;
        ctx=struct('TTI',1,'Direction',direction,'Grant',g,'ServingCellID',1);
        alone=provider.evaluate(ctx,state);
        state.("Grants"+direction)=[g h]; state.("GrantCells"+direction)=[1 2];
        modeled=provider.evaluate(ctx,state);
        assert(isfield(modeled,'ChannelCyclicPrefixSupport') && ...
            ~modeled.ResidualISIICIIncluded);
        if nSizeGrid==273
            assert(modeled.ChannelCyclicPrefixSupport.CircularConvolutionSupported && ...
                modeled.StaticUnwindowedCircularConvolutionSupported, ...
                'The static 100 MHz comparison must satisfy the finite-filter CP contract.');
        end
        diagonalExpected=modeled.ExternalCovariance-alone.ExternalCovariance;
        % The six-PRB native filter exceeds the circular-convolution domain.
        % Preserve that discrepancy; compare native filtering against the
        % committed finite model instead of relaxing the numerical tolerance.
        finiteCfg=cfg;
        finiteCfg.system.linkAbstraction.networkSpatial.sinrPredictorModel='finite_committed_shared_data';
        finiteProvider=sixgr.system.abstraction.NetworkSpatialGrantProvider(finiteCfg);
        idle=state; idle.GrantsDL=struct([]); idle.GrantsUL=struct([]);
        idle.GrantCellsDL=[]; idle.GrantCellsUL=[];
        finiteProvider.commitSlotPopulation(idle);
        state.TTI=2; ctx.TTI=2;
        finiteProvider.commitSlotPopulation(state);
        finite=finiteProvider.evaluateFiniteWindow(ctx);
        expected=finite.ExternalCovariance- ...
            finite.NoisePowerPerRE_W*eye(size(finite.ExternalCovariance,1));
        assert(finite.WithinWindowISIICIIncluded && ~finite.DiagonalCalibrationCompatible);
        receiverUE=1; transmitterCell=2;
        q=10^((large.TxPower_dBm(2,2)-30)/10)/(12*carrier.NSizeGrid);
        if direction=="UL"
            receiverUE=2; transmitterCell=1;
            q=10^((cfg.scenario.ue.txPower_dBm-30)/10)/(12*numel(h.PRBSet));
        end
        seedKey=string(cfg.run.seed)+"_network_link_"+receiverUE+"_"+transmitterCell;
        hash=char(sixgr.util.sha256Hex(uint8(char(seedKey))));
        seed=mod(hex2dec(hash(1:8)),2^32-1);
        measured=zeros(size(expected)); captures=cell(1,rank);
        [sourceSC,sourceSymbol]=ndgrid(reshape(12*h.PRBSet+(0:11).',[],1), ...
            carrier.SymbolsPerSlot+h.SymbolAllocation(1)+(0:h.SymbolAllocation(2)-1));
        sourceCoordinates=[sourceSC(:) sourceSymbol(:)];
        physical=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,direction,seed);
        channel=physical.Object; channel.ChannelFiltering=true; channel.InitialTime=0;
        native=info(channel); trim=double(native.ChannelFilterDelay);
        padding=trim+ceil(max(double(native.PathDelays))*ofdm.SampleRate);
        for source=1:size(sourceCoordinates,1)
          for excitation=1:rank
            grid=complex(zeros(12*carrier.NSizeGrid,2*carrier.SymbolsPerSlot,size(W,1)));
            grid(sourceCoordinates(source,1)+1,sourceCoordinates(source,2)+1,:)= ...
                reshape(sqrt(q)*W(:,excitation),1,1,[]);
            [txWaveform,txInfo]=nrOFDMModulate(carrier,grid,'Windowing',0, ...
                'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate);
            reset(channel);
            [filtered,pathGains,sampleTimes]=channel([txWaveform;zeros(padding,size(W,1))]);
            filtered=filtered*10^(-large.Pathloss_dB(receiverUE,transmitterCell)/20);
            rxGrid=nrOFDMDemodulate(carrier,filtered(trim+(1:size(txWaveform,1)),:), ...
                'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'CyclicPrefixFraction',0.5);
            coords=finite.Coordinates0Based; coords(:,2)=coords(:,2)+carrier.SymbolsPerSlot;
            for k=1:size(coords,1)
                v=reshape(rxGrid(coords(k,1)+1,coords(k,2)+1,:),[],1);
                measured(:,:,k)=measured(:,:,k)+(v*v');
            end
            captures{excitation}=struct('TxWaveform',txWaveform,'TxOFDM',txInfo, ...
                'FilteredReceivedWaveform',filtered,'RxGrid',rxGrid, ...
                'PathGains',pathGains,'SampleTimes',sampleTimes,'ChannelSeed',seed, ...
                'TrimSamples',trim,'TransmitPowerPerOccupiedRE_W',q, ...
                'SourceRE',sourceCoordinates(source,:), ...
                'Source',"last_independent_RE_layer_probe_actual_filter_not_coded_BLER");
          end
        end
        relative=norm(measured(:)-expected(:))/norm(expected(:));
        diagonalRelative=norm(measured(:)-diagonalExpected(:))/norm(expected(:));
        artifact=fullfile(folder,char(lower(direction)+"_rank"+rank+".mat"));
        save(artifact,'cfg','finiteCfg','g','h','modeled','finite','measured','expected','relative', ...
            'diagonalExpected','diagonalRelative','sourceCoordinates','captures','-v7.3');
        assert(relative<1e-8,'Signal-domain %s rank-%d interference covariance mismatch: %.12g; evidence %s', ...
            direction,rank,relative,artifact);
        if modeled.StaticUnwindowedCircularConvolutionSupported
            assert(diagonalRelative<1e-8,'Circular-domain diagonal/native covariance mismatch.');
        elseif nSizeGrid==6
            assert(diagonalRelative>1e-8, ...
                'Retain the narrow-grid counterexample: diagonal covariance omits finite-filter leakage.');
        end
        row=table(direction,rank,relative,diagonalRelative,false,false,string(artifact), ...
            'VariableNames',{'Direction','Rank','RelativeCovarianceError', ...
            'DiagonalRelativeCovarianceError', ...
            'ControlRSInterferenceQualified','StatisticalBLERQualified','EvidenceMAT'});
        audit=[audit;row]; %#ok<AGROW>
        fprintf('SLS_SIGNAL_DOMAIN_COVARIANCE_PASS direction=%s rank=%d relative_error=%g\n',direction,rank,relative);
    end
end
writetable(audit,fullfile(folder,'waveform_covariance_audit.csv'));
fprintf('SLS_SIGNAL_DOMAIN_COVARIANCE_EVIDENCE=%s\n',folder);
end

function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s',id);
end
