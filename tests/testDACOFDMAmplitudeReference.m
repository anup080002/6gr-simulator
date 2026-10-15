function ok=testDACOFDMAmplitudeReference()
% Actual NR OFDM samples, independent quantizer math and frozen stream range.
% Not a link BLER, RF conformance or hardware qualification campaign.
setup6GRSimToolkit('Verbose',false);
source=RandStream('Threefry','Seed',141026);
base=struct();
base.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true,'power_reference_mode','normalized_unit_es');
base.scenario.bs.nTxAnt=64; base.scenario.ue.nTxAnt=4;
base.rf.frontend.dac=struct('enabled',true,'profile_id','ofdm_reference_component', ...
    'version','2','bits',12,'full_scale',1,'convention','signed_midtread', ...
    'dither_enabled',false,'dither_rms',0,'aperture_jitter_seconds',0, ...
    'reference_domain','normalized_nr_ofdm_full_carrier', ...
    'reference_re_energy',1,'reference_headroom_db',12);
cases=[25 15;106 15;273 30;264 120];
for k=1:size(cases,1)
    cfg=base;
    cfg.phy.carrier=struct('NSizeGrid',cases(k,1),'SubcarrierSpacing',cases(k,2));
    carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
    for direction=["DL","UL"]
        ports=64; if direction=="UL", ports=4; end
        grid=exp(1j*(pi/4+pi/2*randi(source,[0 3],12*carrier.NSizeGrid,2,ports)))/sqrt(ports);
        [x,ofdm]=nrOFDMModulate(carrier,grid,'Windowing',0);
        assert(ofdm.Nfft==info.Nfft);
        ref=sixgr.rf.resolveDACAmplitudeReference(cfg,cfg.rf.frontend.dac,ofdm.SampleRate,direction);
        range=sqrt(12*carrier.NSizeGrid/ports)/ofdm.Nfft*10^(12/20);
        assert(abs(ref.WaveformUnitsPerReferenceUnit/range-1)<1e-14);
        out=sixgr.rf.applyRFImpairmentChain(x,cfg,'Endpoint','tx','Direction',direction, ...
            'SampleRateHz',ofdm.SampleRate,'UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
        step=range/(2^11-1);
        expected=complex(round(min(max(real(x),-range),range)/step), ...
            round(min(max(imag(x),-range),range)/step))*step;
        assert(isequal(out.Waveform,expected),'Quantizer must use the exact declared waveform-unit step.');
        assert(out.Replay.DACClippingRatio==0);
        evm=sqrt(sum(abs(out.Waveform(:)-x(:)).^2)/sum(abs(x(:)).^2));
        assert(evm<.002,'Full-carrier 12-bit component error exceeds the frozen test bound.');
        assert(abs(sum(abs(out.Waveform(:)).^2)/sum(abs(x(:)).^2)-1)<.002, ...
            'No transmit gain or power restoration may be introduced.');
        assert(~out.Replay.DACReferencePayloadDependent && out.Replay.DACReferenceTxPorts==ports);
        % Parseval on useful samples excludes the CP energy, not a fitted gain.
        stop=0;
        for symbol=1:2
            first=stop+ofdm.CyclicPrefixLengths(symbol)+1; stop=first+ofdm.Nfft-1;
            waveEnergy=sum(abs(x(first:stop,:)).^2,'all');
            gridEnergy=sum(abs(grid(:,symbol,:)).^2,'all');
            assert(abs(waveEnergy*ofdm.Nfft/gridEnergy-1)<1e-12);
        end
        % Sparse signals, zeros and chunk boundaries do not retune full scale.
        stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx',direction,ofdm.SampleRate,ports,0,1,false);
        split=zeros(size(x),'like',x); start=0;
        for stop=unique([1 257 size(x,1)])
            part=stream.apply(sixgr.phy.waveform.WaveformChunk(x(start+1:stop,:),start),1);
            assert(part.Replay.DACFullScale==range);
            split(start+1:stop,:)=part.Waveform; start=stop;
        end
        assert(isequal(split,out.Waveform));
        quiet=stream.apply(sixgr.phy.waveform.WaveformChunk(zeros(17,ports),start),1);
        assert(all(quiet.Waveform==0,'all') && quiet.Replay.DACFullScale==range);
        sparse=grid; sparse(241:end,:,:)=0;
        sparseWave=nrOFDMModulate(carrier,sparse,'Windowing',0);
        sparseOut=sixgr.rf.applyRFImpairmentChain(sparseWave,cfg,'Endpoint','tx','Direction',direction, ...
            'SampleRateHz',ofdm.SampleRate,'UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
        assert(sparseOut.Replay.DACFullScale==out.Replay.DACFullScale);
        % Deliberate overload remains clipped, never rescued by peak scaling.
        overloaded=sixgr.rf.applyRFImpairmentChain(complex(2*range*ones(2,ports)),cfg, ...
            'Endpoint','tx','Direction',direction,'SampleRateHz',ofdm.SampleRate, ...
            'UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
        assert(overloaded.Replay.DACClippingRatio==1);
        fprintf('DAC_OFDM_REFERENCE nrb=%d scs=%g direction=%s ports=%d range=%.15g evm=%.9g\n', ...
            carrier.NSizeGrid,carrier.SubcarrierSpacing,direction,ports,range,evm);
    end
end
bad=cfg; bad.integration.configured_snr_is_link_authority=false;
localError(@()sixgr.rf.resolveDACAmplitudeReference(bad,bad.rf.frontend.dac,ofdm.SampleRate,'DL'),'RF:DACReferencePowerDomain');
bad=cfg; bad.rf.frontend.dac=rmfield(bad.rf.frontend.dac,'reference_headroom_db');
localError(@()sixgr.rf.resolveDACAmplitudeReference(bad,bad.rf.frontend.dac,ofdm.SampleRate,'DL'),'RF:DACReferenceProfile');
localError(@()sixgr.rf.applyRFImpairmentChain(x(:,1),cfg,'Endpoint','tx','Direction','UL', ...
    'SampleRateHz',ofdm.SampleRate,'UseLegacyGlobalConfig',false),'RF:DACReferencePorts');
legacy=cfg; legacy.rf.frontend.dac.reference_domain='waveform_samples';
legacyRef=sixgr.rf.resolveDACAmplitudeReference(legacy,legacy.rf.frontend.dac,ofdm.SampleRate,'UL');
assert(legacyRef.WaveformUnitsPerReferenceUnit==1);
localH4PRACHReference();
ok=true; disp('DAC_OFDM_AMPLITUDE_REFERENCE_PASS');
end
function localH4PRACHReference()
% Prepare the exact H4 Msg1 waveform, including its fixed-Es physical port
% projection. The timing context here is an explicit preparation fixture,
% not a claim that initial access has completed.
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_short.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
common=struct('Source','decoded_sib1','TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset','');
cfg.SharedULTimingContext=struct('DLReference',struct( ...
    'Source','received_SSB_timing_and_decoded_BCH','SampleRateHz',info.SampleRate, ...
    'DLPhaseOffsetSamples',0,'AvailableAtSample',0), ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'));
[prepared,~]=sixgr.phy.ra.runFourStepRA(cfg,'WriteArtifacts',false, ...
    'RuntimeIntegrationMode','shared_physical_waveform_stream', ...
    'UseRuntimeChannel',true,'RequireRuntimeStageWaveforms',true, ...
    'AllowRuntimeStageWaveformComposition',false,'StageAction','prepare_next_stage');
tx=prepared.PreparedTransmission; x=tx.PhysicalWaveform;
assert(size(x,2)==4 && tx.SampleRate_Hz==info.SampleRate);
% Isolate the converter, without changing the production RF profile.
converter=cfg; converter.rf=struct('frontend',struct('dac',cfg.rf.frontend.dac));
converted=sixgr.rf.applyRFImpairmentChain(x,converter,'Endpoint','tx','Direction','UL', ...
    'SampleRateHz',tx.SampleRate_Hz,'UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
evm=norm(converted.Waveform(:)-x(:))/norm(x(:));
fprintf('H4_PRACH_DAC peak=%.12g range=%.12g clipping=%.12g sample_evm=%.12g\n', ...
    max([abs(real(x(:)));abs(imag(x(:)))]),converted.Replay.DACFullScale, ...
    converted.Replay.DACClippingRatio,evm);
assert(converted.Replay.DACClippingRatio==0 && evm<.01, ...
    'The fixed converter operating point must also preserve the actual H4 PRACH waveform.');
end
function localError(fn,id)
try, fn(); catch cause, assert(string(cause.identifier)==id,'%s',cause.message); return; end
error('sixgr:test:ExpectedError','Expected %s.',id);
end
