function folder=diagnoseH4100ImpairedULData(retainedFolder)
% Three full-band UL receiver cases on the exact H4 impairment configuration.
% Rank/TPMI enter as declared SRS-boundary fixtures, NOT physical sounding or
% adaptive selection. The gNB owns its frozen grant before transmission.
% Independent episodes start the channel/RF clocks at zero; this does not
% claim preceding access, continuous TDD reciprocity or physical UCI/HARQ.
setup6GRSimToolkit('Verbose',false);
if nargin<1, retainedFolder=''; end
folder=fullfile(pwd,'results','diagnostics','h4_impaired_ul', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'test:EvidenceExists'); mkdir(folder);
scenario='simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_gate.yaml';
rows=table();
fprintf('H4_IMPAIRED_UL_ROOT=%s\n',folder);
testH4100AdaptiveDataMapping(@receive,scenario);
assert(height(rows)==3 && isequal(rows.Rank,[1;2;4]));
disp(rows);

    function receive(cfg,direction,grant,frozen,tx,txInfo)
        if direction~="UL", return; end
        rank=grant.NumLayers;
        fprintf('H4_IMPAIRED_UL_START rank=%d PRBs=273 physical_link=4x64\n',rank);
        if strlength(string(retainedFolder))>0
            prior=load(fullfile(retainedFolder,sprintf('rank%d_input.mat',rank)), ...
                'cfg','frozen','waveform');
            bits=load(fullfile(retainedFolder,sprintf('rank%d_output.mat',rank)), ...
                'originalBits');
            cfg=prior.cfg; frozen=prior.frozen;
            [tx,txInfo]=sixgr.phy.ul.PUSCH_Tx(cfg,'PHYGrant',frozen, ...
                'TransportBlockBits',bits.originalBits,'CompactOutput',false);
        end
        cfg=sixgr.truth.attachFixedLinkRuntimeAntennaContext(cfg,1,1);
        cfg.run.rootRunFolder=folder;
        cfg.lls6g.runtimePowerContext=struct( ...
            'WaveformAmplitudeUnit','normalized_unit_es','PhysicalDevicePowerClaim',false);
        user=cfg.lls6g.userContext;
        fs=double(txInfo.OFDM.SampleRate);
        assert(fs==122.88e6 && size(tx.Waveform,2)==4);
        epoch=cfg.rf.configurationEpoch; margin=256;
        samples=[tx.Waveform;zeros(margin,4,'like',tx.Waveform)];
        txRF=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','UL',fs,4,0,epoch,false);
        emitted=txRF.apply(sixgr.phy.waveform.WaveformChunk(samples,0),epoch);
        assert(emitted.Replay.DACQuantizationApplied && emitted.Replay.PAApplied && ...
            emitted.Replay.PhaseNoiseApplied);
        channel=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'UL', ...
            'UEIndex',1,'ServingCell',1,'Seed',5101351);
        channel=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
            channel,cfg,emitted.Waveform,txInfo,'NumTxAnt',4,'NumRxAnt',64, ...
            'TransmitAntennaRuntime',user.RuntimeUEAntenna, ...
            'ReceiveAntennaRuntime',user.RuntimeServingBSAntenna, ...
            'TransmitAntennaMeta',user.RuntimeUEAntennaMeta, ...
            'ReceiveAntennaMeta',user.RuntimeServingBSAntennaMeta);
        [propagated,replay]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
            channel,emitted.Waveform,'OutputSampleAlignment','continuous_raw_samples');
        assert(replay.ChannelFadingApplied && size(propagated,2)==64);
        [antenna,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
            propagated,tx.Carrier,cfg.channel.snr_dB,'Seed',5101352, ...
            'SignalEnergyPerOccupiedRE',sixgr.link.resolveAWGNReferenceEnergy(cfg));
        rxRF=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',fs,64,0,epoch,false);
        frontend=rxRF.apply(sixgr.phy.waveform.WaveformChunk(antenna,0),epoch);
        assert(frontend.Replay.ADCQuantizationApplied && frontend.Replay.PhaseNoiseApplied && ...
            frontend.Replay.TimingOffsetApplied);
        rawWaveform=frontend.Waveform;
        if strlength(string(retainedFolder))>0
            assert(isequal(rawWaveform,prior.waveform), ...
                'test:H4ReplayInputChanged','Retained post-RF capture must reproduce exactly.');
            clear prior bits
        end
        % The production shared receiver removes its known per-sample AGC
        % controls after ADC, not an amplitude fitted to transmitted data.
        % Omitting this boundary turns OFDM pilot/data occupancy changes
        % into artificial channel-gain mismatch in the standalone diagnostic.
        dispatcher=sixgr.phy.waveform.WaveformReceiveDispatcher(fs,64,0);
        dispatcher.register('h4_ul',0,size(rawWaveform,1));
        completed=dispatcher.dispatch( ...
            sixgr.phy.waveform.WaveformChunk(rawWaveform,0),fs);
        segment=struct('StartSample',0,'EndSampleExclusive',size(rawWaveform,1), ...
            'Execution',struct('RX',struct('ID','gnb','Replay',frontend.Replay)));
        [received,gain]=sixgr.phy.rx.compensateReceivedAGC( ...
            completed.Observation,{segment},'gnb');
        waveform=received.readComplete();
        rfReplay=struct('TX',emitted.Replay,'RX',frontend.Replay);
        % Retain the exact call before execution, including a future failure.
        % No TX bits, injected timing/CFO or channel truth enters PUSCH_Rx.
        save(fullfile(folder,sprintf('rank%d_input.mat',rank)), ...
            'cfg','frozen','waveform','rawWaveform','gain','rfReplay', ...
            'noise','replay','margin','-v7.3');
        [rx,info]=sixgr.phy.ul.PUSCH_Rx(waveform,cfg,'PHYGrant',frozen, ...
            'TimingSearchWindowSamples',[0 margin]);
        originalBits=tx.TransportBlock;
        save(fullfile(folder,sprintf('rank%d_output.mat',rank)), ...
            'rx','info','originalBits','-v7.3');
        crc=all(rx.CRCPass);
        if crc, assert(isequal(rx.TransportBlock,originalBits),'test:H4WrongDecodedTB'); end
        row=table(rank,273,double(cfg.channel.snr_dB),crc,numel(originalBits), ...
            double(rx.TimingOffset),double(rx.AppliedTimingCorrection_samples), ...
            double(rx.EstimatedCFO_Hz),string(mat2str(rx.PostEqSINRPerLayer_dB)), ...
            string(rx.PostEqSINRValueStatus),false,false, ...
            'VariableNames',{'Rank','NumPRB','ConfiguredSNR_dB','CRCPass','TBSBits', ...
            'TimingEstimateSamples','AppliedTimingSamples','EstimatedCFO_Hz', ...
            'LayerSINR_dB','SINRStatus','ScenarioAccepted','StatisticallyQualified'});
        row.Scope="actual_impaired_CDL_UL_receiver_declared_SRS_boundary_independent_episode";
        rows=[rows;row]; %#ok<AGROW>
        sixgr.util.csvWriteTable(fullfile(folder,'received_ul.csv'),rows, ...
            'PreserveSchema',true,'RoundTripNumericText',true);
        fprintf('H4_IMPAIRED_UL_RESULT rank=%d CRC=%d timing=%g CFO=%g SINR=%s\n', ...
            rank,crc,row.TimingEstimateSamples,row.EstimatedCFO_Hz,row.LayerSINR_dB);
    end
end
