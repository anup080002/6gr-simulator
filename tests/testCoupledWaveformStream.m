function ok=testCoupledWaveformStream()
% The production scheduler's owner, actual TDD CDL/RF samples. This is an
% access-boundary regression, NOT a completed access/data qualification run.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
m=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,m,struct(),9);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
assert(stream.Events.NextSampleIndex==0);
[staleBound,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext( ...
    sixgr.util.structSet(cfg,'lls6g.runtimePowerContext', ...
    sixgr.rf.PowerContext(cfg,'UL')),state,1,'DL');
assert(~isfield(staleBound.lls6g,'runtimePowerContext'), ...
    'Shared DL binding must clear stale UL waveform power context.');

sameCellCfg=cfg;
sameCellCfg.lls6g.resolvedConfig.interference.intra_cell_interference_flag=true;
sameCellCfg.lls6g.resolvedConfig.interference.mu_mimo_interference_flag=true;
sameCellState=sixgr.truth.CoupledTruthRuntime.initialize( ...
    sameCellCfg,tempname,m,struct(),1);
sameCellState.CurrentSlot=1;
sameCellState.CurrentServingIdx(:)=1;
[~,sameCellStream]=sixgr.truth.CoupledWaveformStream.initialize( ...
    sameCellState,sameCellCfg,{sameCellCfg});
assert(isa(sameCellStream,'sixgr.truth.CoupledWaveformStream'), ...
    'Shared serving links must physically represent intra-cell/MU interference.');

interCellCfg=sameCellCfg;
interCellCfg.lls6g.resolvedConfig.interference.inter_cell_interference_flag=true;
interCellState=sixgr.truth.CoupledTruthRuntime.initialize( ...
    interCellCfg,tempname,m,struct(),1);
interCellState.CurrentSlot=1;
interCellState.CurrentServingIdx(:)=1;
caught=false;
try
    sixgr.truth.CoupledWaveformStream.initialize( ...
        interCellState,interCellCfg,{interCellCfg});
catch cause
    caught=strcmp(cause.identifier,'sixgr:truth:SharedInterferenceLinksRequired');
end
assert(caught,'Inter-cell interference without physical cross-links must remain fail-closed.');
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
prototype=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true,'UseRuntimeChannel',true,'RuntimeSlot',0);
assert(isfield(prototype,'PreparedBroadcast'),'%s',prototype.FailureReason);
p=prototype.PreparedBroadcast;
fprintf('SIB1 absolute slot0=%g start sample=%g\n',p.Tx.SIB1AbsoluteSlot,p.Tx.SIB1WaveformStartSample);
disp('ACTUAL_BROADCAST_SAMPLE_POWER_BY_SLOT');
slotSamples=round(state.SlotDuration_s*stream.SampleRateHz);
for k=1:floor(size(p.TransmitSamples,1)/slotSamples)
    fprintf('slot0=%d power=%g\n',k-1,mean(abs(p.TransmitSamples((k-1)*slotSamples+(1:slotSamples),:)).^2,'all'));
end
context=struct('Config',dl,'Slot',1,'Frame',1,'RNTI',1,'ServingCell',1,'SNR',12);
stream.queueDownlink("PBCH",1,p,context);
assert(stream.hasPending("PBCH",1) && stream.Events.NextSampleIndex==0);
seen=strings(0,1); receivedTRS=struct(); receivedPBCH=struct();
trsRuntimeSlot=double(cfg.phy.trs.slotNumbers(1))+1;
for slot=1:9
    state.CurrentSlot=slot;
    if slot==trsRuntimeSlot
        [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        trs=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',slot);
        context.Config=dl; context.Slot=slot;
        stream.queueDownlink("TRS",1,trs,context);
    end
    [state,completed]=stream.advanceSlot(state,cfg);
    assert(stream.Events.NextSampleIndex==round(slot*state.SlotDuration_s*stream.SampleRateHz));
    for item=completed
        seen(end+1,1)=item.Kind; %#ok<AGROW>
        [rawPost,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        ch=stream.channelState(1,"DL"); before=ch.CurrentSampleIndex;
        assert(post.EndSampleExclusive==stream.Events.NextSampleIndex);
        assert(all(isfinite(post.readComplete()),'all') && replay.RuntimeChannelStateUsed);
        if item.Kind=="PBCH"
            out=prototype; out.RuntimeChannelReplay=replay; out.RuntimeDLChannelState=ch;
            out.PowerContext=p.PowerContext; out.RuntimeChannelStateUsed=true;
            options=struct('UseRuntimeChannel',true,'RuntimeSlot',0, ...
                'CandidateSSBIndices',cfg.phy.ssb.activeCandidateIndices0Based,'SSBIndex',[], ...
                'WriteArtifacts',false,'RunFolder','','RunId','stream_boundary_regression', ...
                'PhysicalMeasurementObservation',pre,'TransmitObservation',tx);
            receivedPBCH=sixgr.link.completeCellSearchBroadcast(p,post,out,options,tic);
            for candidate=receivedPBCH.CandidateResults
                a=candidate{1};
                fixedNormalized=strcmpi(string(cfg.integration.run_mode),'FIXED_SNR_SWEEP') && ...
                    logical(cfg.integration.configured_snr_is_link_authority);
                if fixedNormalized
                    assert(strlength(string(a.SSBWindowPowerMeasurementJSON))==0 && ...
                        isfinite(a.SS_RSRP_dB_re_UnitOccupiedRE_Es) && isnan(a.SS_RSRP_dBm), ...
                        'Configured-Es/N0 LLS must not invent absolute SSB connector power.');
                    displayedRSRP=a.SS_RSRP_dB_re_UnitOccupiedRE_Es;
                else
                    rss=jsondecode(a.SSBWindowPowerMeasurementJSON);
                    assert(rss.Available && numel(rss.RSSIPerAntenna_dBm)==size(pre.readComplete(),2));
                    assert(all(abs(rss.ReferenceRSRQPerAntenna_dB - ...
                        (10*log10(rss.NumRB)+rss.ReferenceRSRPPerAntenna_dBm-rss.RSSIPerAntenna_dBm))<1e-6));
                    displayedRSRP=a.SS_RSRP_dBm;
                end
                fprintf('ssb=%g pbch=%d sib1=%d rsrp=%g sinr=%g failure=%s\n', ...
                    a.SSBIndex,a.PBCH.Ok,a.Ok,displayedRSRP,a.MeasuredTrialSINR_dB,a.FailureReason);
            end
            if ~all(cellfun(@(x)x.Ok,receivedPBCH.CandidateResults))
                actualPost=rawPost.readComplete(); actualPre=pre.readComplete(); actualTX=tx.readComplete();
                save(fullfile('logs','coupled_stream_failure_capture.mat'), ...
                    'actualPost','actualPre','actualTX','receivedPBCH','p','trs','cfg','replay');
            end
            assert(all(cellfun(@(x)x.Ok,receivedPBCH.CandidateResults)), ...
                'Actual shared SSB reception failed: %s',receivedPBCH.FailureReason);
        else
            receivedPrepared=item.Context.Prepared;
            [~,~,channelReferences]=sixgr.truth.sharedLinkScoringObservation( ...
                item.Planes,receivedPrepared,item.Context.DesiredReferencePlane);
            receivedTRS=sixgr.link.completeTRSReception( ...
                receivedPrepared,post,replay,ch,'ScoringChannelReferences',channelReferences);
            assert(receivedTRS.Ok && receivedTRS.StrictOk && ~receivedTRS.Crash, ...
                'Actual shared TRS reception failed: %s',receivedTRS.FailureReason);
        end
        after=stream.channelState(1,"DL"); assert(after.CurrentSampleIndex==before);
    end
end
assert(isequal(sort(seen),["PBCH";"TRS"]) && isempty(stream.Pending));
if strcmpi(string(cfg.integration.run_mode),'FIXED_SNR_SWEEP') && ...
        logical(cfg.integration.configured_snr_is_link_authority)
    ssPowerAvailable=all(cellfun(@(x)isfinite( ...
        x.SS_RSRP_dB_re_UnitOccupiedRE_Es),receivedPBCH.CandidateResults));
else
    ssPowerAvailable=all(cellfun(@(x)isfinite(x.SS_RSRP_dBm),receivedPBCH.CandidateResults));
end
assert(isnan(receivedTRS.MeasuredTrialSINR_dB) && ...
    receivedTRS.NMSEScoringAvailable && isfinite(receivedTRS.NMSE_dB) && ...
    ssPowerAvailable, ...
    'Shared TRS must expose independent channel-NMSE scoring without inventing pilot SINR.');
try
    sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl(state,cfg,1,'UL');
    error('TEST:MissingGuard','Legacy execution was allowed to acquire an owned channel.');
catch e
    assert(strcmp(e.identifier,'sixgr:truth:LegacyExecutionOnSharedStream'));
end
disp('COUPLED_WAVEFORM_STREAM_PASS'); ok=true;
end
