function ok=testSRSReceiverNoiseDespreading()
% Receiver regression, not a full 5/400-MHz coordinator acceptance test.
% Independently generated grid noise is a fixture/scoring input only: neither
% its realization nor its variance is passed to SRS_Rx.
setup6GRSimToolkit('Verbose',false);
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_5mhz_four_port_shared_awgn_12db.yaml'));
folder=fullfile('results','lls','srs_receiver_noise_despreading', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(source,folder);
strict=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
variance=sixgr.link.resolveAWGNReferenceEnergy(cfg)/10^(cfg.channel.snr_dB/10);
rows=struct([]);
for geometry=[25 15;264 120].'
    carrier=nrCarrierConfig('NSizeGrid',geometry(1),'SubcarrierSpacing',geometry(2));
    for ports=[1 2 4]
        for comb=[2 4]
          for hopping=[false true]
            srs=strict.ToolboxSRS;
            srs.NumSRSPorts=ports; srs.SRSPeriod='on'; srs.KTC=comb;
            srs.BSRS=double(hopping); srs.BHop=0;
            srs.NumSRSSymbols=4; srs.SymbolStart=10; srs.Repetition=1;
            widths=srs.BandwidthConfigurationTable{:,'m_SRS_0'};
            ids=srs.BandwidthConfigurationTable{:,'C_SRS'};
            srs.CSRS=ids(find(widths<=carrier.NSizeGrid,1,'last'));
            % Also cover four-port frequency-separated port groups, not
            % merely four co-located cyclic shifts.
            if comb==4, srs.CyclicShift=6; else, srs.CyclicShift=0; end
            indices=nrSRSIndices(carrier,srs); symbols=nrSRS(carrier,srs);
            grid=nrResourceGrid(carrier,ports); grid(indices)=symbols;
            noise=sqrt(variance/2)*(randn(size(grid))+1i*randn(size(grid)));
            % OFDM loopback exercises the actual receiver, with declared
            % aligned timing. This is not acquired shared-stream timing.
            waveform=nrOFDMModulate(carrier,grid+noise,'Windowing',0);
            [rx,info]=sixgr.phy.ul.SRS_Rx(waveform,cfg,'Carrier',carrier,'SRS',srs);
            % Declared identity channel is an independent scoring reference
            % only. It must not be supplied to the practical receiver.
            reference=complex(zeros(size(grid,1),size(grid,2),ports,ports));
            for port=1:ports, reference(:,:,port,port)=1; end
            channelScore=sixgr.phy.srs.pilotChannelNMSE(rx.Hest,reference,indices);
            row=struct('NSizeGrid',carrier.NSizeGrid,'SCS_kHz',carrier.SubcarrierSpacing, ...
                'Ports',ports,'Comb',comb,'CyclicShift',srs.CyclicShift, ...
                'FrequencyHoppingEnabled',hopping, ...
                'FrequencyHoppingHandled',sixgr.util.structGet(info, ...
                    'ChannelEstimation.FrequencyHoppingHandled',false), ...
                'DeclaredGridNoiseVariance',variance,'EstimatedGridNoiseVariance',rx.NoiseVar, ...
                'NoiseError_dB',10*log10(rx.NoiseVar/variance), ...
                'PilotChannelNMSE_dB',channelScore.dB, ...
                'NoiseVarianceSource',string(rx.NoiseVarSource), ...
                'Source',"controlled_grid_noise_OFDM_loopback_not_integrated_run");
            rows=[rows;row]; %#ok<AGROW>
            save(fullfile(folder,sprintf('rx_%dprb_%dports_comb%d_hop%d.mat', ...
                carrier.NSizeGrid,ports,comb,hopping)),'carrier','srs','rx','info','variance','channelScore');
          end
        end
    end
end
results=struct2table(rows);
writetable(results,fullfile(folder,'receiver_noise.csv'));
disp(results);
assert(all(results.FrequencyHoppingHandled==results.FrequencyHoppingEnabled), ...
    'test:SRSReceiverHoppingConfiguration', ...
    'Receiver did not respect native BHop/BSRS hopping configuration; evidence: %s',folder);
% Fixed engineering regression bound, not a statistical qualification gate.
% A factor-of-two tolerance still rejects classifying other SRS ports as
% approximately unit-power noise at this declared ~0.016 grid variance.
assert(all(isfinite(results.NoiseError_dB) & abs(results.NoiseError_dB)<3), ...
    'test:SRSReceiverNoiseDespreading', ...
    'Receiver noise estimate differs by >=3 dB; retained evidence: %s',folder);
assert(all(isfinite(results.PilotChannelNMSE_dB) & results.PilotChannelNMSE_dB < -10), ...
    'test:SRSReceiverChannelDespreading', ...
    'Per-resource channel estimate exceeds the fixed -10 dB engineering NMSE bound: %s',folder);
assert(all(results.NoiseVarianceSource=="runtime_channel_estimate"), ...
    'test:SRSReceiverNoiseAuthority','Noise must come from the practical received-reference estimator.');
ok=true;
fprintf('SRS_RECEIVER_NOISE_DESPREADING_PASS cases=%d evidence=%s\n',height(results),folder);
end
