function ok=testResearchPerfectAWGNReceiver()
% Qualify explicit perfect identity CSI; never authorize it on fading paths.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'tests','fixtures', ...
    'research_four_layer_perfect_awgn.yaml'));
s=scfg.toStruct();
state=rng; restore=onCleanup(@()rng(state)); %#ok<NASGU>
rng(s.simulation.random_seed,'twister');
for direction=["DL","UL"]
    if direction=="DL", slot=0; else, slot=4; end
    a=sixgr.phy.research.SharedChannelLink.allocation(s,slot,direction);
    assert(a.NumLayers==4 && a.Qm==10 && a.TargetCodeRate==0.9 && a.CodingLayout.BaseGraph==1);
    tb=int8(randi([0 1],a.TransportBlockSize,1));
    tx=sixgr.phy.research.SharedChannelLink.transmit(s,slot,tb,direction);
    for snr=[40 30]
        variance=(1/a.NumLayers)/10^(snr/10)/tx.OFDM.SampleToGridNoiseVarianceGain;
        waveform=tx.Waveform+sqrt(variance/2)*(randn(size(tx.Waveform))+1j*randn(size(tx.Waveform)));
        rx=sixgr.phy.research.SharedChannelLink.receive(s,slot,waveform,direction);
        assert(rx.PerfectCSI && rx.ChannelEstimateSource=="perfect_configured_identity_AWGN_and_precoder");
        expected=repmat(reshape(a.Precoder.',1,1,4,4),size(rx.Grid,1),size(rx.Grid,2),1,1);
        assert(isequal(rx.ChannelEstimate,expected));
        assert(rx.NoiseVariance>0 && rx.NoiseSource=="received_DMRS_nrChannelEstimate");
        evm=sqrt(mean(abs(rx.EqualizedSymbols(:)-tx.LayerSymbols(:)).^2)/ ...
            mean(abs(tx.LayerSymbols(:)).^2));
        exact=isequal(rx.TransportBlock,tb);
        if snr==40
            assert(rx.CRCPass && exact && evm<0.015);
            % The original default receiver remains DMRS-based, not silently idealized.
            legacy=rmfield(s,'research_receiver');
            measured=sixgr.phy.research.SharedChannelLink.receive(legacy,slot,waveform,direction);
            assert(~measured.PerfectCSI && measured.ChannelEstimateSource=="received_DMRS_nrChannelEstimate");
            assert(measured.CRCPass && isequal(measured.TransportBlock,tb));
            assert(~isequal(measured.ChannelEstimate,expected));
            clear measured
        end
        fprintf('PERFECT_AWGN_COMPONENT direction=%s SNRdB=%g layers=4 rate=0.9 BG=1 TBS=%d CRC=%d exact=%d EVM=%g HARQ=0 integrated_TDD=0\n', ...
            direction,snr,numel(tb),rx.CRCPass,exact,evm);
    end
    bad=s; bad.channels.model_type='CDL'; bad.channels.profile='CDL-C';
    bad.research_link.channel='physical_cdl';
    localThrows(@()sixgr.phy.research.SharedChannelLink.receive(bad,slot,waveform,direction), ...
        'sixgr:research:PerfectCSIRequiresIdentityAWGN');
    bad=s; bad.impairments.cfo_enabled=true;
    localThrows(@()sixgr.phy.research.SharedChannelLink.receive(bad,slot,waveform,direction), ...
        'sixgr:research:PerfectCSIRequiresIdentityAWGN');
    % Enabling perfect CSI must not silently enable the unfinished HARQ path.
    bad=s; bad.("research_"+lower(direction)).harq_enabled=true;
    localThrows(@()sixgr.phy.research.SharedChannelLink.allocation(bad,slot,direction), ...
        'sixgr:research:UnsupportedULProcedure');
end
ok=true;
fprintf('RESEARCH_PERFECT_AWGN_RECEIVER_PASS fading_rejection=1 ideal_RF_guard=1 legacy_DMRS_preserved=1 final_throughput_acceptance=0\n');
end

function localThrows(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedFailure','Expected rejection %s.',id);
end
