function ok=testSLSExplicitPilotInterference()
% Fixed pilot interference must retain RE/port phases, including ISI/ICI.
% Independent reference: aggregate native pilot grid -> nrOFDMModulate ->
% sample-domain FIR -> nrOFDMDemodulate. No receiver estimate or BLER claim.
stream=RandStream('mt19937ar','Seed',91731);
maxError=0; changed=0;
for scs=[30 120]
    carrier=nrCarrierConfig('NSizeGrid',6,'SubcarrierSpacing',scs,'NSlot',3);
    sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
    N=sampling.Nfft; fs=sampling.SampleRateHz; K=72; L=14; ports=2; nt=4; nr=2;
    [W,~]=qr(randn(stream,nt,ports)+1i*randn(stream,nt,ports),0);
    W=W/sqrt(ports);
    for kind=["CSI-RS","SRS","PDSCH-DMRS"]
        grid=complex(zeros(K,L,ports));
        if kind=="CSI-RS"
            c=nrCSIRSConfig('RowNumber',3,'NumRB',6,'RBOffset',0, ...
                'SymbolLocations',10,'SubcarrierLocations',0,'Density','one','CSIRSPeriod','on');
            grid(nrCSIRSIndices(carrier,c))=nrCSIRS(carrier,c);
        elseif kind=="SRS"
            c=nrSRSConfig('NumSRSPorts',2,'SymbolStart',10,'NumSRSSymbols',2, ...
                'CSRS',0,'BSRS',0,'BHop',0,'KTC',2,'SRSPeriod','on');
            grid(nrSRSIndices(carrier,c))=nrSRS(carrier,c);
        else
            c=nrPDSCHConfig('NumLayers',2,'PRBSet',0:5,'SymbolAllocation',[0 14]);
            c.DMRS.DMRSAdditionalPosition=1;
            grid(nrPDSCHDMRSIndices(carrier,c))=nrPDSCHDMRS(carrier,c);
        end
        occupied=find(any(grid~=0,3));
        [k,l]=ind2sub([K L],occupied);
        source=[k-1 l-1]; flat=reshape(grid,K*L,ports); symbols=flat(occupied,:);
        power=.2+rand(stream,numel(occupied),1);
        grid(:)=0; flat=reshape(grid,K*L,ports);
        flat(occupied,:)=symbols.*sqrt(power);
        antennaGrid=reshape(flat*W.',K,L,nt); % no conjugation in transmit precoding
        waveform=nrOFDMModulate(carrier,antennaGrid,'Nfft',N,'SampleRate',fs,'Windowing',0);
        filters=zeros(27,2); filters(1,1)=1; filters(end,2)=.8;
        trim=3; samples=size(waveform,1)+trim; t=(0:samples-1)'/fs;
        base=randn(stream,1,2,nt,nr)+1i*randn(stream,1,2,nt,nr);
        gains=base.*exp(1i*2*pi*t.*reshape([700 -1200],1,2,1,1));
        realization=struct('PathFilters',filters,'PathGains',gains,'SampleTimes',t, ...
            'SampleRateHz',fs,'TrimSamples',trim,'NumberOfSymbols',L,'Nfft',N, ...
            'CyclicPrefixFraction',.5);
        receiveSymbols=unique([source(:,2);min(13,source(:,2)+1)]);
        [rk,rl]=ndgrid(0:K-1,receiveSymbols); receive=[rk(:) rl(:)];
        result=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
            carrier,source,W,power,receive,realization,'Algorithm','fft_transfer','SourceSymbols',symbols);
        received=sixgr.phy.waveform.applySampledFadingChannel( ...
            [waveform;zeros(trim,nt)],filters,gains,complex(zeros(26,nt,2)));
        demod=nrOFDMDemodulate(carrier,received(trim+(1:size(waveform,1)),:), ...
            'Nfft',N,'SampleRate',fs,'CyclicPrefixFraction',.5);
        demod=reshape(demod,K*L,nr);
        expected=demod(sub2ind([K L],receive(:,1)+1,receive(:,2)+1),:).';
        error=norm(result.ExplicitSymbolResponse-expected,'fro')/norm(expected,'fro');
        maxError=max(maxError,error);
        assert(error<2e-11,'test:ExplicitPilotTransfer','Native %s waveform differs by %g.',kind,error);
        for q=1:size(receive,1)
            v=expected(:,q);
            assert(norm(result.ExplicitSymbolSecondMoment(:,:,q)-v*v','fro')<1e-10*max(1,norm(v)^2));
        end
        difference=norm(result.Covariance(:)-result.ExplicitSymbolSecondMoment(:))/norm(result.Covariance(:));
        changed=changed+(difference>1e-3);
        assert(~result.FullNetworkInterferenceQualified && ~result.PrimaryStudyAccepted);
        % Phase inversion leaves a population's power unchanged, but changes
        % its coherent sum with another emitter. Never add second moments
        % as though deterministic populations were independent symbols.
        inverted=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
            carrier,source,W,power,receive,realization,'Algorithm','fft_transfer','SourceSymbols',-symbols);
        assert(norm(result.ExplicitSymbolResponse+inverted.ExplicitSymbolResponse,'fro')==0);
        assert(isequal(result.Covariance,inverted.Covariance));
        fprintf('SLS_EXPLICIT_PILOT kind=%s scs=%g resources=%d relative_error=%g independent_covariance_difference=%g\n', ...
            kind,scs,size(source,1),error,difference);
    end
end
assert(changed==6,'The regression must expose coherent-pilot versus random-data interference.');
% Small public native-probe comparison also covers the new API's validation.
source=source(1:2,:); power=power(1:2); symbols=symbols(1:2,:); receive=receive(1:3,:);
a=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source,W,power,receive,realization,'SourceSymbols',symbols);
b=sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
    carrier,source,W,power,receive,realization,'Algorithm','fft_transfer','SourceSymbols',symbols);
assert(norm(a.ExplicitSymbolResponse-b.ExplicitSymbolResponse,'fro')<1e-11);
for algorithm=["native_probes","fft_transfer"]
    try
        sixgr.system.abstraction.sampledOFDMInterferenceCovariance( ...
            carrier,source,W,power,receive,realization,'Algorithm',algorithm,'SourceSymbols',symbols(:,1));
        error('test:MissingRejection','Malformed symbol population accepted.');
    catch cause
        assert(strcmp(cause.identifier,'sixgr:abstraction:FiniteOFDMSymbolPopulation'));
    end
end
fprintf('SLS_EXPLICIT_PILOT_PASS six_native_grid_cases=1 max_relative_error=%g network_integration_qualified=0\n',maxError);
ok=true;
end
