function ok=testSharedTRSChannelScoring(mode,queueWhileUL,withQCL)
% Actual shared physical owner: TRS waveform, NR fading, RF and thermal noise.
% Short component execution, not an access/data scheduler qualification.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
if nargin<2, queueWhileUL=false; end
if nargin<3, withQCL=false; end
% Install the same independently decoded control schema required by the
% production shared runtime; do not bypass its DCI-context guard.
file='lls_pdcch_shared_queue_fixture.yaml';
if string(mode)=="FDD", file='lls_trs_shared_scoring_fdd_fixture.yaml'; end
if withQCL
    assert(string(mode)=="TDD" && ~queueWhileUL);
    file='lls_causal_access_to_data_wiring_tdd_short_continuous_iq.yaml';
end
runtimeSlot=8; queueSlot=1;
if queueWhileUL
    assert(string(mode)=="TDD");
    file='lls_trs_future_dl_projection_fixture.yaml';
    runtimeSlot=8; queueSlot=6;
end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',file));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
if withQCL
    cfg.run.rootRunFolder=tempname;
    mkdir(cfg.run.rootRunFolder);
    fprintf('SHARED_TRS_QCL_RUN_ROOT=%s\n',cfg.run.rootRunFolder);
end
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),runtimeSlot+1);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
referenceSNR=sixgr.truth.resolveWaveformOperatingPointMetadata(dl);
p=sixgr.link.prepareTRSTransmission(dl,referenceSNR,'RuntimeSlot',runtimeSlot);
initial=owner.channelState(1,"DL");
array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'bs', ...
    'signal','trs','numPorts',size(p.TransmitSamples,2));
expectedProjection=array.PortToElementMatrix;
if queueWhileUL, assert(initial.NumTxAnt~=initial.NumRxAnt); end
seen=false;
for slot=1:runtimeSlot+1
    state.CurrentSlot=slot;
    if slot==queueSlot
        beforeQueue=owner.channelState(1,"DL");
        if queueWhileUL, assert(string(beforeQueue.Direction)=="UL"); end
        owner.queueDownlink("TRS",1,p,struct('Config',dl,'Slot',runtimeSlot));
        afterQueue=owner.channelState(1,"DL");
        assert(afterQueue.CurrentSampleIndex==beforeQueue.CurrentSampleIndex && ...
            string(afterQueue.Direction)==string(beforeQueue.Direction));
        assert(isequal(owner.Pending(end).Context.Prepared.TransmitProjectionMatrix,expectedProjection));
    end
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
    [state,items]=owner.advanceSlot(state,current);
    for item=items
        if item.Kind~="TRS", continue; end
        assert(~seen); seen=true;
        p=item.Context.Prepared;
        arrival=sixgr.truth.sharedArrivalTimingReference(item.Planes,p.TransmitStartSample);
        assert(~arrival.ReceiverEstimatorInput && arrival.AdditionalChannelExecutions==0 && ...
            arrival.ExpectedArrivalOffset_samples==arrival.TransmitStartSample-arrival.ReceiveStartSample+ ...
            arrival.TXRFDelay_samples+arrival.RXRFDelay_samples+arrival.ChannelEarliestDelay_samples- ...
            arrival.ChannelAlignmentTrim_samples);
        [~,~,~,replay,observation]=sixgr.truth.sharedObservationEvidence(item.Planes);
        replay.PowerContext=p.PowerContext;
        [desiredReference,scoringEvidence,captures]=sixgr.truth.sharedLinkScoringObservation( ...
            item.Planes,p,item.Context.DesiredReferencePlane);
        assert(isempty(captures) && ~scoringEvidence.ChannelReferenceCoverageComplete && ...
            desiredReference.isComplete() && any(scoringEvidence.LinkActive), ...
            ['Scoring must retain the exact executed desired-link waveform ' ...
             'without requesting a full per-sample path-gain tensor.']);
        exportRoot=tempname; mkdir(exportRoot);
        exported=sixgr.truth.exportSharedScoringWaveformObservation( ...
            exportRoot,table(1,'VariableNames',{'Slot'}),item.Planes,p, ...
            item.Context.DesiredReferencePlane);
        assert(height(exported)==1 && ...
            strlength(exported.ChannelObservationID)==70 && ...
            isfile(fullfile(exportRoot,exported.ChannelObservationMATFile)) && ...
            isfile(fullfile(exportRoot,exported.ChannelObservationSegmentsCSV)), ...
            'Same-execution scoring IQ must publish one scalar provenance row.');
        before=owner.Events.NextSampleIndex;
        ch=owner.directionalChannelState(1,"DL");
        out=sixgr.link.completeTRSReception(p,observation,replay,ch, ...
            'DesiredReferenceObservation',desiredReference);
        assert(~out.Crash,'%s',out.FailureReason);
        occupancy=out.ObservedREAllocationTable;
        assert(all(occupancy.port_domain=="physical_antenna_ports_after_executed_projection") && ...
            all(occupancy.grid_port_count==size(p.TransmitProjectionMatrix,1)) && ...
            all(isnan(occupancy.layer_count)));
        for gs=p.Tx.GridSlots(:).'
            grid=gs.Grid; n=size(grid,3); W=p.TransmitProjectionMatrix;
            actual=reshape(reshape(grid,[],n)*W.',size(grid,1),size(grid,2),size(W,1));
            rows=occupancy(occupancy.absolute_slot==gs.Slot,:);
            assert(sum(rows.re_count)==nnz(actual),'TRS physical occupancy must equal its applied map.');
            [~,~,ports]=ind2sub(size(actual),find(actual~=0));
            assert(isequal(sort(unique(rows.port_index)),sort(unique(ports-1))));
        end
        assert(out.NoiseVariance==mean(out.ChannelEstimationTable.NoiseEstimate) && ...
            out.NoiseVarianceDomain=="resource_grid_pre_equalization" && ...
            contains(out.NoiseVarianceSource,"nrChannelEstimate"));
        assert(out.InjectedSampleNoiseVariance==replay.InjectedNoiseVariance && ...
            out.InjectedSampleNoiseVarianceDomain==string(replay.InjectedNoiseVarianceDomain));
        metadata=sixgr.truth.bindSharedRFExecutionEvidence( ...
            table(referenceSNR,out.NoiseVariance,string(out.NoiseVarianceSource), ...
            'VariableNames',{'ConfiguredSNR_dB','NoiseVariance','NoiseVarianceSource'}),item.Planes,true);
        assert(metadata.NoiseVariance==out.NoiseVariance && ...
            metadata.NoiseVarianceSource==string(out.NoiseVarianceSource) && ...
            metadata.InjectedSampleNoiseVariance==replay.InjectedNoiseVariance && ...
            isequaln(metadata.ReferenceAWGNGridNoiseVariance,replay.ReferenceAWGNGridNoiseVariance), ...
            'TRS export must distinguish the executed noise reference from its measured disturbance.');
        assert(out.Ok && out.NMSEScoringAvailable && out.NMSE_dB<=p.StrictConfig.ChannelNMSEThresholddB, ...
            'Actual independent NMSE=%g; %s',out.NMSE_dB,out.FailureReason);
        assert(out.ChannelNMSEComparedComplexValues== ...
            sum(p.Tx.SlotTable.NRE)*observation.NumReceiveAntennas);
        assert(out.ChannelNMSEPilotResourceCount==sum(p.Tx.SlotTable.NRE) && ...
            out.ChannelNMSEQualificationMode=="independent_complex_pilot_resources_no_gain_or_phase_fit" && ...
            abs(10*log10(out.ChannelNMSEErrorEnergy/out.ChannelNMSEReferenceEnergy)-out.NMSE_dB)<1e-10);
        assert(isnan(out.QCLAccuracy) && isnan(out.MeasuredTrialSINR_dB));
        assert(out.IndependentPilotSNDRAvailable && isfinite(out.IndependentPilotSNDR_dB) && ...
            out.IndependentPilotComparedComplexValues==out.ChannelNMSEComparedComplexValues && ...
            abs(out.IndependentPilotSNDR_dB-10*log10(out.IndependentPilotSignalEnergy/ ...
            out.IndependentPilotDisturbanceEnergy))<1e-10);
        assert(out.ChannelNMSEReferenceIncludesRFImpairments==1);
        absent=sixgr.link.completeTRSReception(p,observation,replay,ch);
        assert(~absent.Ok && ~absent.NMSEScoringAvailable && isnan(absent.NMSE_dB));
        assert(absent.DetectionMetric==out.DetectionMetric && absent.EstimatedCFO_Hz==out.EstimatedCFO_Hz);
        assert(absent.TRSRuntimeEvidenceUsable && ~absent.StrictOk);
        assert(~absent.IndependentPilotSNDRAvailable && isnan(absent.IndependentPilotSNDR_dB));
        assert(out.ChannelNMSEComparedComplexValues>0 && ...
            contains(string(out.NMSEReferenceSource),'same_executed_desired_link_waveform'), ...
            'TRS NMSE must be scored from same-execution IQ, not regenerated channel coefficients.');
        assert(owner.Events.NextSampleIndex==before);
        assert(out.TrackingTable.ProducerSlot==max(p.Tx.SlotTable.Slot));
        samplesPerSlot=p.SampleRateHz*1e-3/(double(p.StrictConfig.ToolboxCarrier.SubcarrierSpacing)/15);
        assert(out.TrackingTable.AvailableSlot==ceil(observation.EndSampleExclusive/samplesPerSlot));
        assert(out.TrackingTable.AvailableSlot>out.TrackingTable.ProducerSlot);
        if withQCL
            state=sixgr.truth.recordSharedQCLTimingReference(state,p,observation,out,1,1);
            reference=state.SharedQCLTimingReferences{1};
            dciContext=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(p.ReceiverConfig,'1_1');
            assert(reference.RRCServingCellIndex==dciContext.Data.ScheduledServingCell && ...
                reference.ServingCellIndex==1 && reference.UEIndex==1 && ...
                reference.AvailableAtSample==observation.EndSampleExclusive && ...
                reference.SourceResourceID==cfg.phy.pdsch.qclTCI.source_resource_id);
            nominal=sixgr.phy.frame.slotStartSample(p.Tx.GridSlots(1).Carrier, ...
                p.Tx.FirstSlot0Based,observation.SampleRateHz);
            assert(reference.TimingPhaseSamples==observation.StartSample+out.EstimatedTimingOffset_samples-nominal);
            captureFile=[tempname '.mat']; receivedWaveform=observation.readComplete();
            save(captureFile,'p','out','reference','replay','receivedWaveform');
            fprintf('SHARED_TRS_QCL_REFERENCE_PASS rrc_cell=%g simulator_cell=%g phase=%g available=%g capture=%s\n', ...
                reference.RRCServingCellIndex,reference.ServingCellIndex,reference.TimingPhaseSamples, ...
                reference.AvailableAtSample,captureFile);
        end
        fileCSV=[tempname '.csv']; writetable(out.ChannelEstimationTable,fileCSV);
        saved=readtable(fileCSV,'TextType','string');
        assert(height(saved)==2 && all(saved.NMSEScoringAvailable) && ...
            all(saved.NMSEReferenceSource==out.NMSEReferenceSource));
fprintf('SHARED_TRS_CHANNEL_SCORING: %s NMSE=%g dB, %g compared pilot/branch values.\n', ...
            mode,out.NMSE_dB,out.ChannelNMSEComparedComplexValues);
    end
end
assert(seen && ~owner.hasPending("TRS",1));
if queueWhileUL, fprintf('FUTURE_DL_TRS_PROJECTION_PASS: unequal arrays, queue during UL, no channel mutation.\n'); end
ok=true;
end
