function ok=testSharedNoiseReferenceEvidence()
% Actual noise-owner/RF execution, not a decoded-channel or qualification claim.
setup6GRSimToolkit('Verbose',false);
root=fullfile(pwd,'results','lls','shared_noise_reference', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))); mkdir(root);
for mode=["fixed","thermal"]
    name='lls_causal_access_to_data_wiring_tdd.yaml';
    if mode=="thermal", name='lls_trs_shared_scoring_fdd_fixture.yaml'; end
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',name));
    cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
    cfg.channel.snr_dB=12;
    carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier); fs=info.SampleRate;
    for direction=["DL","UL"]
        owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,1);
        owner.addTransmitter('tx',cfg,direction,2,false);
        owner.addReceiver('rx',cfg,direction,2,false);
        different=cfg; different.channel.snr_dB=20;
        owner.addReceiver('other_rx',different,direction,2,false);
        event=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
        owner.attach(event,'double');
        % An explicitly idle transmitter: exercise the actual noise generator
        % and RF chain without inventing a signal or a successful PHY trial.
        event.commitTransmissionsThrough('tx',4096);
        for id=["tx:tx","rx:pre_rf","rx:post_rf","other_rx:post_rf"]
            event.observe(id,id,0,4096);
        end
        event.advanceUntilEvent(1024);
        result=event.advanceUntilEvent(4096);
        planes=result.Completed(~startsWith(string({result.Completed.ReceiverID}),'other_rx'));
        T=table([1;2],[12;12],[.123;.456],[6;7],[8;9], ...
            ["receiver_DMRS";"receiver_DMRS"],["measured_grid";"measured_grid"], ...
            'VariableNames',{'Slot','ConfiguredSNR_dB','NoiseVariance','SINRdB', ...
            'RSRP_dB','NoiseVarianceSource','SNRReferencePlane'});
        before=rng;
        out=sixgr.truth.bindSharedRFExecutionEvidence(T,planes,true);
        assert(isequal(rng,before) && owner.NextSampleIndex==4096 && ...
            isequaln(out(:,T.Properties.VariableNames),T), ...
            'Export must neither execute PHY/RNG again nor overwrite practical receiver measurements.');
        p=find(endsWith(string({planes.ReceiverID}),':post_rf'));
        nodes=planes(p).Segments{1}.Execution.RX;
        ledger=nodes(string({nodes.ID})=="rx").Replay;
        for field=["SignalEnergyPerOccupiedRE","ReferenceAWGNGridNoiseVariance", ...
                "ReferenceAWGNSampleNoiseVariance","SampleToGridNoiseVarianceGain", ...
                "AppliedAWGNSNR_dB","NoiseOperatingMode"]
            assert(isequaln(out.(field),repmat(ledger.(field),height(T),1)) || ...
                isequaln(out.(field),repmat(string(ledger.(field)),height(T),1)));
        end
        assert(all(out.NoiseReferenceReceiverID=="rx") && ...
            all(out.NoiseReferenceStartSample==0) && all(out.NoiseReferenceEndSampleExclusive==4096));
        if mode=="fixed"
            assert(all(abs(out.AppliedAWGNSNR_dB-12)<1e-10) && ...
                all(abs(out.ReferenceAWGNGridNoiseVariance./out.SignalEnergyPerOccupiedRE-10^(-1.2))<1e-12));
            other=result.Completed(startsWith(string({result.Completed.ReceiverID}),'other_rx'));
            otherOut=sixgr.truth.bindSharedNoiseReferenceEvidence(table(20,'VariableNames',{'ConfiguredSNR_dB'}),other);
            assert(abs(otherOut.AppliedAWGNSNR_dB-20)<1e-10 && ...
                otherOut.NoiseStreamSeed~=out.NoiseStreamSeed(1));
            wrong=T; wrong.ConfiguredSNR_dB(:)=20;
            localError(@()sixgr.truth.bindSharedNoiseReferenceEvidence(wrong,planes), ...
                'sixgr:truth:FixedAWGNOperatingPointMismatch');
        else
            assert(all(isnan(out.AppliedAWGNSNR_dB)) && ...
                all(out.NoiseReferenceWaveformAmplitudeUnit=="sqrt_mW") && ...
                all(abs(out.InjectedSampleNoiseVariance-out.ThermalNoisePSD_mWPerHz.* ...
                out.ThermalSampleNoiseBandwidth_Hz)<1e-10*out.InjectedSampleNoiseVariance));
        end
        bad=planes;
        bad(p).Segments{1}.Execution.RX(1).Replay=rmfield(ledger,'InjectedNoiseVariance');
        localError(@()sixgr.truth.bindSharedNoiseReferenceEvidence(T,bad), ...
            'sixgr:truth:IncompleteNoiseReference');
        bad=planes;
        bad(p).Segments{1}.Execution.RX(1).Replay.InjectedNoiseVariance=ledger.InjectedNoiseVariance*2;
        id='sixgr:truth:SharedFixedSNRNoiseClosure';
        if mode=="thermal", id='sixgr:truth:SharedThermalNoiseClosure'; end
        localError(@()sixgr.truth.bindSharedNoiseReferenceEvidence(T,bad),id);
        bad=planes;
        bad(p).Segments{end}.Execution.RX(1).Replay.NoiseStreamSeed=ledger.NoiseStreamSeed+1;
        localError(@()sixgr.truth.bindSharedNoiseReferenceEvidence(T,bad), ...
            'sixgr:truth:NoiseReferenceChangedWithinCapture');
        bad=planes;
        bad(p).Segments{end}.Execution.StartSample=1025;
        localError(@()sixgr.truth.bindSharedNoiseReferenceEvidence(T,bad), ...
            'sixgr:truth:NoiseReferenceCoverageGap');
        bad=planes;
        bad(p).Segments{end}.Execution.RX(1).ID="foreign_receiver";
        localError(@()sixgr.truth.bindSharedNoiseReferenceEvidence(T,bad), ...
            'sixgr:truth:NoiseReferenceReceiverScope');
        % CSV serialization must retain both rows and the actual reference.
        path=fullfile(root,mode+"_"+direction+".csv"); writetable(out,path);
        saved=readtable(path,'TextType','string','Delimiter',',', ...
            'NumHeaderLines',0,'VariableNamingRule','preserve');
        assert(height(saved)==2 && all(saved.NoiseReferenceReceiverID=="rx") && ...
            all(abs(saved.InjectedSampleNoiseVariance./out.InjectedSampleNoiseVariance-1)<1e-12));
    end
end
ok=true; fprintf('SHARED_NOISE_REFERENCE_EVIDENCE_PASS fixed_thermal_DL_UL=4 receiver_identity=1 physical_variance_closure=1 no_receiver_overwrite=1 negative_guards=1\n');
fprintf('OUTPUT_FOLDER=%s\n',root);
end

function localError(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedError','Expected %s.',id);
end
