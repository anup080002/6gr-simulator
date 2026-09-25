function [ok,folder]=testDataChannelEstimateScoring()
% Actual DL/UL receivers; independent applied channel, never receiver input.
% Isolated 25-PRB waveform checks, not shared-runtime/export acceptance.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','lls','data_channel_estimate_scoring', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(folder);
Hdl=[.8 0 .6 0;0 .6 0 .8];
rows=struct([]);
resourceRows=table();
for direction=["DL","UL"]
  for layers=[1 2]
    for snr=[-10 20]
      if direction=="DL"
        [estimate,grid,indices,symbols,reference,crc,receiver]=localDL(Hdl,layers,snr);
      else
        [estimate,grid,indices,symbols,reference,crc,receiver]=localUL(Hdl.',layers,snr);
      end
      % Existing independent resource/branch/port scorer; no gain/phase fit.
      score=sixgr.phy.srs.pilotChannelNMSE(estimate,reference,indices);
      context=struct('Channel',"PDSCH",'Slot',1,'UEIndex',1, ...
          'ConfiguredSNR_dB',snr, ...
          'ChannelEstimateSource',"actual_DMRS_receiver_25PRB_component", ...
          'ChannelReferenceSource',"known_executed_fixed_matrix_and_declared_TX_scaling", ...
          'ChannelReferencePlane',"effective_DMRS_layer_channel_on_receiver_FFT_grid");
      if direction=="UL", context.Channel="PUSCH"; end
      [resources,publishedScore]=sixgr.report.buildReceiverChannelEstimateTable( ...
          estimate,reference,indices,context);
      assert(isequaln(publishedScore,score));
      if direction=="UL"
          snapshot=sixgr.phy.ul.capturePUSCHChannelEstimate(receiver);
      else
          snapshot=sixgr.phy.dl.capturePDSCHChannelEstimate(receiver);
      end
      [compactRows,compactScore]=sixgr.report.buildReceiverChannelEstimateTable( ...
          snapshot,reference,snapshot.PilotIndices,context);
      assert(isequaln(compactRows,resources) && isequaln(compactScore,score));
      assert(numel(snapshot.PilotChannelValues)==score.ComparedComplexValueCount && ...
          ~isfield(snapshot,'ChannelEstimate') && ~isfield(snapshot,'RxGrid'));
      resources.Layers=repmat(layers,height(resources),1);
      resourceRows=[resourceRows;resources]; %#ok<AGROW>
      writetable(resourceRows,fullfile(folder,'receiver_channel_estimate_resources.csv'));
      residual=sixgr.phy.rx.referenceSignalMetrics(grid,estimate,indices,symbols);
      if direction=="DL"
          assert(isnan(receiver.Metrics.ChannelEstimateNMSE) && ...
              receiver.Metrics.ChannelEstimateNMSESource=="unavailable_without_independent_channel_reference", ...
              'A pilot reconstruction residual must not be published as independently scored channel NMSE.');
          assert(isfinite(receiver.Metrics.PilotReconstructionResidualRatio));
      end
      exact=sixgr.phy.srs.pilotChannelNMSE(reference,reference,indices);
      noisyPilots=sixgr.phy.rx.referenceSignalMetrics(grid,reference,indices,symbols);
      assert(exact.Linear==0 && noisyPilots.NMSELinear>0, ...
          'An exact channel has zero channel NMSE despite nonzero received noise.');
      assert(isfinite(score.Linear) && score.Linear>=0 && ...
          score.ComparedComplexValueCount==numel(indices)*size(estimate,3));
      if snr==20
          assert(score.dB < -10 && crc, ...
              '%s rank %d high-SNR reference failed: NMSE=%g CRC=%d', ...
              direction,layers,score.dB,crc);
      end
      before=receiver;
      poison=sixgr.phy.srs.pilotChannelNMSE(estimate,100i*reference,indices);
      % At low SNR both normalized ratios can approach one. Test the
      % exact reference-energy scaling, not an arbitrary dB separation.
      assert(isequaln(receiver,before) && ...
          abs(poison.ReferenceEnergy/score.ReferenceEnergy-1e4)<1e-8 && ...
          poison.ErrorEnergy~=score.ErrorEnergy && ...
          ~score.GainOrPhaseFitted && ~score.MissingValuesDiscarded);
      row=struct('Direction',direction,'Layers',layers,'ConfiguredSNR_dB',snr, ...
          'CRCOK',logical(crc),'ChannelNMSE_dB',score.dB, ...
          'PilotReconstructionResidualRatio_dB',residual.NMSEdB, ...
          'ExactChannelNMSELinear',exact.Linear, ...
          'ExactChannelNoisyPilotResidualRatio',noisyPilots.NMSELinear, ...
          'ComparedChannelValues',score.ComparedComplexValueCount, ...
          'ReferenceUsedByReceiver',false, ...
          'Scope',"isolated_actual_25PRB_DMRS_receiver_not_integrated_export");
      if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
      writetable(struct2table(rows),fullfile(folder,'channel_estimate_scoring.csv'));
      save(fullfile(folder,sprintf('%s_rank%d_snr%d.mat',direction,layers,snr)), ...
          'receiver','estimate','reference','indices','symbols','score','residual','row');
      fprintf('DATA_CHANNEL_SCORING direction=%s layers=%d snr=%g nmse=%g pilot_residual=%g crc=%d\n', ...
          direction,layers,snr,score.dB,residual.NMSEdB,crc);
    end
  end
end
T=struct2table(rows);
fig=figure('Visible','off','Color','w'); cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
if isprop(fig,'Theme'), fig.Theme='light'; end
ax=axes(fig); hold(ax,'on');
for direction=["DL","UL"]
    for layers=[1 2]
        selected=T(T.Direction==direction & T.Layers==layers,:);
        plot(ax,selected.ConfiguredSNR_dB,selected.ChannelNMSE_dB,'-o', ...
            'DisplayName',direction+" rank "+layers+" independent channel NMSE");
    end
end
xlabel(ax,'Configured occupied-RE Es/N0 (dB)'); ylabel(ax,'Pilot-channel NMSE (dB)');
title(ax,'Actual 25-PRB receivers; isolated measurement check, not integrated acceptance');
legend(ax,'Location','best'); set(ax,'XGrid','on','YGrid','on');
exportgraphics(fig,fullfile(folder,'channel_estimate_scoring.png'),'Resolution',150);
roundtrip=readtable(fullfile(folder,'receiver_channel_estimate_resources.csv'));
assert(height(roundtrip)==height(resourceRows));
for i=1:height(T)
    channel="PDSCH"; if T.Direction(i)=="UL", channel="PUSCH"; end
    selected=roundtrip(string(roundtrip.Channel)==channel & ...
        roundtrip.Layers==T.Layers(i) & roundtrip.ConfiguredSNR_dB==T.ConfiguredSNR_dB(i),:);
    measured=10*log10(sum(selected.ChannelErrorEnergy)/sum(selected.ReferenceChannelEnergy));
    assert(abs(measured-T.ChannelNMSE_dB(i))<1e-10 && ...
        height(selected)==T.ComparedChannelValues(i), ...
        'CSV round-trip must preserve every measured branch/port/resource and NMSE.');
end
fprintf('DATA_CHANNEL_ESTIMATE_SCORING_PASS cases=%d folder=%s shared_export_verified=0\n',numel(rows),folder);
ok=true;
end

function [estimate,grid,indices,symbols,reference,crc,rx]=localDL(H,layers,snr)
fixture=StrictPDSCHChainFixture.create(layers,'NPRB',25);
fixture.Carrier.SubcarrierSpacing=15;
tx=sixgr.pdsch.PDSCHTransmitter(fixture.TransportBlocks,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
    'PrecoderBundle',fixture.PrecoderBundle);
W=exp(-2i*pi*(0:3)'*(0:layers-1)/4)/2;
amplitude=.5;
physicalTX=amplitude*tx.Waveform*W.';
clean=physicalTX*H.';
[wave,noise]=sixgr.phy.waveform.addOccupiedREAWGN(clean,fixture.Carrier,snr, ...
    'Seed',9242401,'SignalEnergyPerOccupiedRE',.25);
rcfg=rmfield(fixture.ReceiverConfig,'ReferenceChannelGain');
rcfg.ChannelModel='STATIC-MIMO'; rcfg.NPhysicalRxAntennas=2;
rcfg.NoiseVariance=noise.GridNoiseVariance;
rx=sixgr.pdsch.PDSCHReceiver(wave,fixture.Assignment,fixture.ResourcePlan, ...
    fixture.Carrier,fixture.ReferenceConfig,rcfg, ...
    'CodingPlans',tx.CodingPlans,'PrecoderBundle',fixture.PrecoderBundle);
assert(~rx.ChannelEstimationInfo.EstimatorUsesTrueChannel);
estimate=rx.EffectiveLayerChannelEstimate; grid=rx.OFDMGrid;
refs=sixgr.pdsch.PDSCHReferenceSignalGenerator.generate( ...
    fixture.Assignment,fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig);
indices=nrPDSCHDMRSIndices(fixture.Carrier,refs.MaterializedPDSCH);
symbols=nrPDSCHDMRS(fixture.Carrier,refs.MaterializedPDSCH);
reference=repmat(reshape(amplitude*H*W,1,1,2,layers),size(grid,1),size(grid,2),1,1);
crc=rx.CRCPass;
end

function [estimate,grid,indices,symbols,reference,crc,rx]=localUL(H,layers,snr)
cfg=sixgr.config.defaultConfig();
cfg.run.shortRun=true; cfg.run.strictMode=true; cfg.run.noProxyTruthContract=true;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=4;
cfg.channel.nTxAnt=2; cfg.channel.nRxAnt=4;
cfg.scenario.ue.nTxAnt=2; cfg.antenna.ue.numElements=2;
cfg.phy.carrier.NSizeGrid=25; cfg.phy.carrier.SubcarrierSpacing=15;
cfg.phy.pusch.prbSet=0:24; cfg.phy.pusch.symbolAllocation=[0 14];
cfg.phy.pusch.modulation='QPSK'; cfg.phy.pusch.mcsIndex=4;
cfg.phy.pusch.mcsTable='qam64_table1'; cfg.phy.pusch.codeRate=308/1024;
cfg.phy.pusch.targetCodeRate=308/1024;
cfg.phy.pusch.numLayers=layers; cfg.phy.pusch.nLayers=layers;
cfg.phy.pusch.numAntennaPorts=2; cfg.phy.pusch.numPorts=2;
cfg.phy.pusch.dmrs.portSet=0:layers-1; cfg.phy.pusch.dmrs.DMRSPortSet=0:layers-1;
cfg.phy.pusch.transmissionScheme='codebook'; cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.TPMI=0; cfg.phy.pusch.PMI=0;
cfg.phy.pusch.enablePTRS=false; cfg.phy.pusch.equalizer='MMSE';
cfg.phy.channelEstimation.method='LS';
[tx,~]=sixgr.phy.ul.PUSCH_Tx(cfg,'CompactOutput',false);
assert(size(tx.Waveform,2)==2);
amplitude=.5;
clean=amplitude*tx.Waveform*H.';
[wave,noise]=sixgr.phy.waveform.addOccupiedREAWGN(clean,tx.Carrier,snr, ...
    'Seed',9242402,'SignalEnergyPerOccupiedRE',.25);
[rx,~]=sixgr.phy.ul.PUSCH_Rx(wave,cfg,'Carrier',tx.Carrier,'PUSCH',tx.PUSCH, ...
    'PUSCHIndices',tx.PUSCHIndices,'TransportBlockSize',tx.TransportBlockSize, ...
    'TargetCodeRate',tx.TargetCodeRate,'RV',tx.RV,'NoiseVar',noise.SampleNoiseVariance, ...
    'NoiseVarDomain','time','CodingLayout',tx.CodingLayout, ...
    'CompactOutput',false,'SkipTimingEstimate',true);
estimate=rx.ChannelEstimate; grid=rx.RxGrid;
originalPUSCH=rx.PUSCH;
refs=sixgr.phy.ul.puschChannelEstimateReferences(rx);
assert(isequal(rx.PUSCH,originalPUSCH) && refs.LogicalPortCount==layers && ...
    refs.PhysicalTransmitPortCount==2 && refs.NumReceiveBranches==4 && ...
    ~refs.TransmitterPayloadUsed && ~refs.TrueChannelUsed);
indices=refs.Indices; symbols=refs.Symbols;
if layers==1
    assert(any(double(rx.DMRSIndices(:))>size(grid,1)*size(grid,2)), ...
        'Fixture must reproduce the native two-port versus one-layer index distinction.');
end
bad=rx; bad.ChannelEstimate=repmat(rx.ChannelEstimate,1,1,1,2);
caught=false;
try, sixgr.phy.ul.puschChannelEstimateReferences(bad);
catch ex, caught=strcmp(ex.identifier,'sixgr:phy:ul:PUSCHChannelReferenceDomainMismatch'); end
assert(caught,'Do not truncate or silently remap an inconsistent Hest layer count.');
W=sixgr.phy.ul.puschCodebookProjectionMatrix(layers,2,tx.PUSCH.TPMI,false);
reference=repmat(reshape(amplitude*H*W,1,1,4,layers),size(grid,1),size(grid,2),1,1);
crc=~rx.CRCError;
end
