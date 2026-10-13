function ok = testDataReceiverSynchronizationAuthority(direction,cpObservation)
% Identical RX samples and installed policy must ignore injection audit truth.
arguments
    direction (1,1) string = "both"
    cpObservation (1,1) struct = struct()
end
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior));
rng(510102,'twister');
directions=["DL","UL"];
if direction~="both", directions=direction; end
checked=0;
for link=directions
    assert(any(link==["DL","UL"]));
    cfg=localConfig();
    if ~isempty(fieldnames(cpObservation))
        cfg.phy.impairments.cfoCPObservation=cpObservation;
    end
    if link=="DL"
        tx=sixgr.phy.dl.PDSCH_Tx(cfg,'NumTxAnt',1,'ExecutionProfile','phy_calibration');
        args={'Carrier',tx.Carrier,'PDSCH',tx.PDSCH, ...
            'PDSCHIndices',tx.PDSCHIndices,'CodingPlan',tx.CodingPlans, ...
            'ExecutionProfile','phy_calibration'};
        receive=@sixgr.phy.dl.PDSCH_Rx;
    else
        tx=sixgr.phy.ul.PUSCH_Tx(cfg,'NumTxAnt',1);
        args={'Carrier',tx.Carrier,'PUSCH',tx.PUSCH, ...
            'PUSCHIndices',tx.PUSCHIndices,'CodingLayout',tx.CodingLayout};
        receive=@sixgr.phy.ul.PUSCH_Rx;
    end
    args=[args,{'TransportBlockSize',tx.TransportBlockSize, ... %#ok<AGROW>
        'TargetCodeRate',tx.TargetCodeRate,'RV',tx.RV, ...
        'NoiseVar',1e-8,'NoiseVarDomain','time'}];
    fs=tx.OFDMInfo.SampleRate;
    cfo=430;
    for aligned=[false true]
        delay=16*double(~aligned);
        wave=[zeros(delay,size(tx.Waveform,2));tx.Waveform; ...
            zeros(48-delay,size(tx.Waveform,2))];
        wave=wave.*exp(1i*2*pi*cfo*(0:size(wave,1)-1)'/fs);
        cfg.lls6g.receiverSync.RuntimeWaveformSampleAligned=aligned;
        baseline=[];
        for audit=["zero","incorrect","absent"]
            probe=cfg;
            if audit=="absent"
                probe.phy.impairments=rmfield(probe.phy.impairments, ...
                    intersect(fieldnames(probe.phy.impairments), ...
                    {'cfoHz','timingOffsetSamples'}));
            else
                probe.phy.impairments.cfoHz=-4321*double(audit=="incorrect");
                probe.phy.impairments.timingOffsetSamples=91*double(audit=="incorrect");
            end
            rx=receive(wave,probe,args{:});
            assert(rx.Ok && ~rx.CRCError,'%s must decode the measured synchronized samples.',link);
            assert(rx.TimingEstimateUsed==~aligned && ...
                rx.AppliedTimingCorrection_samples==delay, ...
                '%s timing action changed with audit metadata %s (aligned=%d).',link,audit,aligned);
            assert(rx.CFOCorrectionApplied && abs(rx.EstimatedCFO_Hz-cfo)<15, ...
                '%s CFO correction must use the received estimate even when injected CFO is labelled zero.',link);
            assert(rx.SynchronizationState.ResidualCFOReusesAcquisitionObservation && ...
                rx.ResidualCFOEstimateRole=="same_observation_estimator_consistency_not_independent_residual" && ...
                rx.ResidualCFOEstimatorConsistency_Hz==rx.ResidualCFO_EstimatedPostCorrection_Hz, ...
                '%s must identify repeated same-capture CFO estimation as a consistency check.',link);
            if ~isempty(fieldnames(cpObservation))
                assert(string(rx.CFOObservation.ObservationPolicy)==string(cpObservation.Policy) && ...
                    rx.CFOObservation.ObservationPairCount>0, ...
                    '%s must execute and expose the configured CP observation policy.',link);
            end
            if link=="DL", grid=rx.OFDMGrid; else, grid=rx.RxGrid; end
            snapshot=struct('TimingUsed',rx.TimingEstimateUsed, ...
                'TimingApplied',rx.AppliedTimingCorrection_samples, ...
                'CFOApplied',rx.CFOCorrectionApplied_Hz, ...
                'EstimatedCFO',rx.EstimatedCFO_Hz, ...
                'Grid',grid,'Decoded',rx.TransportBlock,'CRCError',rx.CRCError);
            if isempty(baseline), baseline=snapshot; else
                assert(isequaln(snapshot,baseline), ...
                    '%s measured synchronization/decoding changed with hidden injection metadata.',link);
            end
            checked=checked+1;
        end
    end
    % A supplied valid receiver tracking estimate must not override an
    % explicitly disabled frequency-correction policy.
    cfg.phy.rx.cfoCorrectionEnabled=false;
    tracking=struct('TRSProcessed',true,'CFOEstimateAvailable',true,'EstimatedCFO_Hz',cfo, ...
        'TrackingMeasurementDirection',link,'TrackingConsumerDirection',link, ...
        'TrackingDirectionCompatible',true,'TrackingEstimateSource','declared_receiver_tracking_fixture');
    rx=receive(wave,cfg,args{:},'ReceiverTrackingState',tracking);
    assert(~rx.CFOCorrectionApplied, ...
        '%s applied supplied CFO tracking despite disabled receiver correction.',link);
    cfg.lls6g.receiverSync.RuntimeWaveformSampleAligned=false;
    tracking.TimingEstimateAvailable=true; tracking.TimingEstimate_samples=16;
    rx=receive(wave,cfg,args{:},'ReceiverTrackingState',tracking,'SkipTimingEstimate',true);
    assert(~rx.TimingEstimateUsed && rx.AppliedTimingCorrection_samples==0, ...
        '%s applied supplied timing tracking despite explicit timing bypass.',link);
end
fprintf('DATA_RX_SYNC_AUTHORITY_PASS physical_decodes=%d disabled_policy_checks=%d\n', ...
    checked,2*numel(directions));
ok=true;
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig();
cfg.run.pdschExecutionProfile='phy_calibration';
cfg.phy.pdsch.executionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=6; cfg.phy.carrier.SubcarrierSpacing=60; cfg.phy.carrier.NSlot=1;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
for name=["pdsch","pusch"]
    p=cfg.phy.(name);
    p.PRBSet=0:5; p.prbSet=0:5; p.SymbolAllocation=[2 10]; p.symbolAllocation=[2 10];
    p.MappingType='A'; p.mappingType='A'; p.numLayers=1; p.nLayers=1;
    p.mcsTable='qam64_table1'; p.mcsIndex=4; p.modulation='QPSK';
    p.codeRate=308/1024; p.targetCodeRate=308/1024;
    p.dmrs.additionalPositions=1; p.dmrs.portSet=0; p.dmrs.DMRSPortSet=0;
    cfg.phy.(name)=p;
end
cfg.phy.pusch.numAntennaPorts=1; cfg.phy.pusch.numPorts=1;
cfg.phy.pusch.transmissionScheme='codebook'; cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.TPMI=0; cfg.phy.pusch.PMI=0;
cfg.scenario.ue.nTxAnt=1; cfg.antenna.ue.numElements=1;
cfg.phy.pdsch.UECapability1024QAM=false; cfg.phy.pdsch.RRCEnabled1024QAM=false;
cfg.phy.pdsch.DCIEnabled1024QAM=false; cfg.phy.pdsch.DeploymentAllows1024QAM=false;
cfg.phy.pdsch.FrequencyRangeAllows1024QAM=false; cfg.phy.pdsch.BandAllows1024QAM=false;
cfg.phy.pdsch.FrequencyRange='FR1'; cfg.phy.pdsch.OperatingBand='n77';
cfg.phy.pdsch.DeploymentClass='macro'; cfg.phy.pdsch.DCIFormat='1_1';
cfg.phy.rx.useIdealTimingSync=false; cfg.phy.rx.cfoCorrectionEnabled=true;
cfg.phy.impairments.cfoEstimationMethod='cyclic_prefix';
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
end
