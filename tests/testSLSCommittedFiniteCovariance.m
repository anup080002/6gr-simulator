function ok=testSLSCommittedFiniteCovariance()
% Committed multicell grant populations versus independent native filtering.
% Small numerical grants qualify covariance math, NOT BLER/network studies.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/calibrated_link_abstraction.yaml');
cfg.run=struct('seed',113,'executionID','committed_finite_covariance');
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.scenario.ue.txPower_dBm=23;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',300e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
large=struct('Pathloss_dB',[80 83;87 85],'TxPower_dBm',30*ones(2));
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
for direction=["DL","UL"]
    for rank=1:2
        W=[1;1i]/sqrt(2); if rank==2, W=eye(2)/sqrt(2); end
        desired=struct('RNTI',4660,'UEIndex',1,'PRBSet',0,'SymbolAllocation',[0 1],'NumLayers',rank, ...
            'PHYGrant',struct('PrecodingState',struct('MatrixPorts',W)));
        prior=desired; prior.RNTI=4661; prior.UEIndex=2; prior.SymbolAllocation=[13 1];
        disjoint=prior; disjoint.PRBSet=1; disjoint.SymbolAllocation=[0 1];
        a=struct('TTI',1,'GrantsDL',struct([]),'GrantsUL',struct([]), ...
            'GrantCellsDL',[],'GrantCellsUL',[],'LargeScaleState',large);
        a.("Grants"+direction)=prior; a.("GrantCells"+direction)=2;
        b=a; b.TTI=2; b.("Grants"+direction)=[desired disjoint]; b.("GrantCells"+direction)=[1 2];
        % A measured/configured large-scale state change belongs to the
        % received sample slot, not silently to the transmitting grant.
        b.LargeScaleState.Pathloss_dB=b.LargeScaleState.Pathloss_dB+3;
        ctx=struct('TTI',2,'Direction',direction,'Grant',desired,'ServingCellID',1);
        provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
        provider.commitSlotPopulation(a);
        reject(@()provider.evaluateFiniteWindow(ctx),'sixgr:abstraction:ReceiveWindowNotAvailable');
        provider.commitSlotPopulation(b);
        model=provider.evaluateFiniteWindow(ctx);
        [covariance,useful,other]=nativeReference(cfg,direction,rank,{a b},ctx);
        reconstructed=model.ExternalCovariance-model.NoisePowerPerRE_W*eye(2)+model.DesiredObservation.Covariance;
        error=norm(reconstructed(:)-covariance(:))/norm(covariance(:));
        errorG=norm(model.DesiredObservation.SameResourceEffectiveChannel(:)-useful(:))/norm(useful(:));
        errorOther=norm(model.DesiredObservation.OtherResourceCovariance(:)-other(:))/norm(covariance(:));
        assert(error<1e-10 && errorG<1e-10 && errorOther<1e-10);
        % Reference reception must not invent a desired data grant. Every
        % actual shared-data source is interference at these observation REs,
        % including finite leakage from the prior slot and disjoint PRBs.
        referenceContext=struct('TTI',2,'Direction',direction,'UEIndex',1,'ServingCellID',1);
        reference=provider.evaluateReferenceInterference(referenceContext,model.Coordinates0Based);
        referenceCovariance=reference.ExternalCovariance-reference.NoisePowerPerRE_W*eye(2);
        referenceError=norm(referenceCovariance(:)-covariance(:))/norm(covariance(:));
        assert(referenceError<1e-10 && reference.ReferenceObservationOnly && ...
            isempty(fieldnames(reference.DesiredObservation)) && ...
            ~any([reference.Population.IsDesired]) && numel(reference.Population)==3 && ...
            ~reference.CommonControlInterferenceQualified && ~reference.ReferenceSignalInterferenceQualified && ...
            ~reference.FullNetworkInterferenceQualified && ~reference.PrimaryStudyAccepted);
        assert(numel(model.Population)==3 && nnz([model.Population.IsDesired])==1 && ...
            ~model.WaveformMeasured && ~model.PrimaryStudyAccepted && ~model.DiagonalCalibrationCompatible);
        % Both the preceding slot AND the frequency-disjoint transmitter
        % contribute; a rectangular same-RE overlap filter would miss these.
        assert(norm(model.Population(1).Covariance(:))>0 && norm(model.Population(3).Covariance(:))>0);
        save(fullfile(folder,sprintf('%s_rank%d.mat',direction,rank)), ...
            'model','reference','referenceError','covariance','useful','other','error','errorG','errorOther','-v7.3');
        fprintf('SLS_COMMITTED_FINITE_CASE direction=%s rank=%d covariance_error=%g useful_error=%g reference_error=%g\n', ...
            direction,rank,error,errorG,referenceError);
        % A later committed slot must not alter this already-complete window.
        idle=a; idle.TTI=3; idle.GrantsDL=struct([]); idle.GrantsUL=struct([]);
        idle.GrantCellsDL=[]; idle.GrantCellsUL=[]; provider.commitSlotPopulation(idle);
        replay=provider.evaluateFiniteWindow(ctx);
        assert(isequaln(model.DesiredObservation,replay.DesiredObservation) && ...
            isequaln(model.ExternalCovariance,replay.ExternalCovariance));
    end
end
fprintf('SLS_COMMITTED_FINITE_COVARIANCE_PASS cases=4 statistical_qualification=0 evidence=%s\n',folder);
ok=true;
end

function [covariance,useful,other]=nativeReference(cfg,direction,rank,states,ctx)
% Independent unit impulses through nrTDLChannel, not the finite predictor.
carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',30);
ofdm=nrOFDMInfo(carrier); cp=reshape(ofdm.CyclicPrefixLengths,14,[]);
slotSamples=sum(ofdm.Nfft+cp,1);
covariance=complex(zeros(2,2,12)); useful=complex(zeros(2,rank,12)); other=covariance;
for slot=1:2
    grants=states{slot}.("Grants"+direction); cells=states{slot}.("GrantCells"+direction);
    for j=1:numel(grants)
        grant=grants(j); isDesired=slot==2 && j==1;
        if direction=="DL", u=ctx.Grant.UEIndex; c=cells(j); power=1/72;
        else, u=grant.UEIndex; c=ctx.ServingCellID; power=10^((cfg.scenario.ue.txPower_dBm-30)/10)/12; end
        seedText=string(cfg.run.seed)+"_network_link_"+u+"_"+c;
        hash=char(sixgr.util.sha256Hex(uint8(char(seedText))));
        native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,direction, ...
            mod(hex2dec(hash(1:8)),2^32-1));
        channel=native.Object;
        infoChannel=info(channel); trim=double(infoChannel.ChannelFilterDelay);
        pad=trim+ceil(max(double(infoChannel.PathDelays))*ofdm.SampleRate);
        W=grant.PHYGrant.PrecodingState.MatrixPorts;
        for source=0:11
            for layer=1:rank
                grid=complex(zeros(72,28,2));
                sourceSC=12*grant.PRBSet+source;
                sourceSymbol=(slot-1)*14+grant.SymbolAllocation(1);
                grid(sourceSC+1,sourceSymbol+1,:)=reshape(W(:,layer)*sqrt(power),1,1,2);
                tx=nrOFDMModulate(carrier,grid,'Windowing',0);
                reset(channel); rx=channel([tx;zeros(pad,2)]);
                start=0;
                for k=1:2
                    count=slotSamples(k); if k==2, count=count+pad; end
                    ix=start+(1:count);
                    rx(ix,:)=rx(ix,:)*10^(-states{k}.LargeScaleState.Pathloss_dB(u,c)/20);
                    start=start+count;
                end
                y=nrOFDMDemodulate(carrier,rx(trim+(1:size(tx,1)),:),'CyclicPrefixFraction',.5);
                for target=0:11
                    value=reshape(y(target+1,15,:),2,1);
                    covariance(:,:,target+1)=covariance(:,:,target+1)+value*value';
                    if isDesired
                        if sourceSC==target
                            useful(:,layer,target+1)=value;
                        else
                            other(:,:,target+1)=other(:,:,target+1)+value*value';
                        end
                    end
                end
            end
        end
    end
end
end

function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
