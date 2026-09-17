function ok=testResearchFixedPorts()
% Actual decoding with four physical ports at both ranks and one noise level.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
c=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures','research_fixed_ports.yaml'));
s=c.toStruct(); state=rng; cleanup=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
for d=["DL","UL"]
    if d=="DL", slot=0; else, slot=4; end
    section="research_"+lower(d); variance=[]; commonNoise=[];
    for candidate=1:3
        sc=s;
        if candidate==2
            sc.(section).num_layers=2; sc.(section).dmrs_port_set=[0 1];
        elseif candidate==3
            sc.(section).modulation='256QAM';
        end
        a=sixgr.phy.research.SharedChannelLink.allocation(sc,slot,d);
        assert(a.NumPhysicalPorts==4 && abs(sum(abs(a.Precoder(:)).^2)-1)<1e-12);
        assert(norm(a.Precoder*a.Precoder'-eye(a.NumLayers)/a.NumLayers,'fro')<1e-12);
        tb=int8(randi([0 1],a.TransportBlockSize,1));
        tx=sixgr.phy.research.SharedChannelLink.transmit(sc,slot,tb,d);
        assert(size(tx.Waveform,2)==4 && size(tx.Grid,3)==4);
        nv=sc.research_awgn_mimo.reference_data_re_power/10^(40/10)/tx.OFDM.SampleToGridNoiseVarianceGain;
        if isempty(variance)
            variance=nv;
            commonNoise=sqrt(nv/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
        end
        assert(nv==variance && isequal(size(commonNoise),size(tx.Waveform)));
        rx=sixgr.phy.research.SharedChannelLink.receive(sc,slot,tx.Waveform+commonNoise,d);
        assert(rx.CRCPass && isequal(rx.TransportBlock,tb));
        assert(size(rx.ChannelEstimate,3)==4 && size(rx.ChannelEstimate,4)==a.NumLayers);
        pg=reshape(tx.Grid,[],4); total=mean(sum(abs(pg(a.DataIndices(:,1),:)).^2,2));
        assert(abs(total-1)<0.05);
        if a.NumLayers==2, assert(all(tx.Waveform(:,3:4)==0,'all')); end
        fprintf('FIXED_PORTS_CODED_PASS direction=%s rank=%d modulation=%s ports=4 fixed_noise=%g total_data_RE_power=%g CRC=1 exact=1\n', ...
            d,a.NumLayers,a.Modulation,nv,total);
    end
end
ok=true;
fprintf('RESEARCH_FIXED_PORTS_PASS link_adaptation_qualified=0\n');
end
