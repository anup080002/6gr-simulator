function ok=testULReferencePortUnion()
% Algebraic measurement regression using native PUSCH DM-RS positions.
% H is a declared fixture, not a practical channel-estimation result.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.csi.reportCQI=false;
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(926190,'twister');
variance=0.25/10^1.2;
for geometry=[25 15;264 120].'
    carrier=nrCarrierConfig('NSizeGrid',geometry(1),'SubcarrierSpacing',geometry(2));
    for layers=[1 2 4]
        pusch=nrPUSCHConfig('NumLayers',layers,'PRBSet',0:carrier.NSizeGrid-1);
        pusch.DMRS.NumCDMGroupsWithoutData=2;
        indices=nrPUSCHDMRSIndices(carrier,pusch);
        symbols=nrPUSCHDMRS(carrier,pusch);
        tx=nrResourceGrid(carrier,layers); tx(indices)=symbols;
        K=size(tx,1); L=size(tx,2); R=4;
        % Non-symmetric channel also detects accidental coherent averaging
        % or reshaping of the two disjoint DM-RS CDM resource groups.
        matrix=exp(1i*(0:R-1).'*(0:layers-1)*2*pi/R)/sqrt(R);
        matrix=diag([1 .9 .8 .7])*matrix;
        h=repmat(reshape(matrix,1,1,R,layers),K,L,1,1);
        signal=reshape(reshape(tx,K*L,layers)*matrix.',K,L,R);
        noise=sqrt(variance/2)*(randn(size(signal))+1i*randn(size(signal)));
        received=signal+noise;
        actual=sixgr.phy.ul.measureULLinkState(h,variance,cfg, ...
            'ReceivedGrid',received,'ReferenceIndices',indices, ...
            'ReferenceSymbols',symbols,'ChannelEstimateDomain', ...
            'pusch_dmrs_effective_layer_domain');
        physical=unique(mod(double(indices(:))-1,K*L)+1);
        flatSignal=reshape(signal,K*L,R); flatNoise=reshape(noise,K*L,R);
        expected=10*log10(mean(abs(flatSignal(physical,:)).^2,'all')/ ...
            max(variance,mean(abs(flatNoise(physical,:)).^2,'all')));
        assert(isfinite(actual.PilotSINR_dB) && abs(actual.PilotSINR_dB-expected)<1e-9, ...
            'test:ULReferencePortUnion', ...
            'Port/resource union reconstruction failed for %d PRB, rank %d: measured=%g expected=%g.', ...
            carrier.NSizeGrid,layers,actual.PilotSINR_dB,expected);
        % Port/RE ordering is not a power policy. Permuting paired reference
        % entries must preserve the result; flattening must not invent a
        % different port layout for disjoint DM-RS CDM groups.
        order=randperm(numel(indices));
        reordered=sixgr.phy.ul.measureULLinkState(h,variance,cfg, ...
            'ReceivedGrid',received,'ReferenceIndices',indices(order), ...
            'ReferenceSymbols',symbols(order),'ChannelEstimateDomain', ...
            'pusch_dmrs_effective_layer_domain');
        assert(abs(reordered.PilotSINR_dB-expected)<1e-9, ...
            'Reference measurement must not depend on paired-entry ordering.');
        % A real factor-four signal-energy reduction at unchanged noise
        % must lower the measurement by 6.0206 dB. No configured SNR anchor
        % may renormalize that loss away.
        lower=sixgr.phy.ul.measureULLinkState(h/2,variance,cfg, ...
            'ReceivedGrid',signal/2+noise,'ReferenceIndices',indices, ...
            'ReferenceSymbols',symbols,'ChannelEstimateDomain', ...
            'pusch_dmrs_effective_layer_domain');
        assert(abs(lower.PilotSINR_dB-(expected-10*log10(4)))<1e-9, ...
            'Reference measurement erased the physical factor-four signal-energy change.');
    end
end
ok=true;
fprintf('UL_REFERENCE_PORT_UNION_PASS geometries_and_ranks=6 measurements=18 declared_channel_algebra=1 integrated=0\n');
end
