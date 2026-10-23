function ok=testCoupledWaveformStream()
% The production scheduler's owner, actual TDD CDL/RF samples. This is an
% access-boundary regression, NOT a completed access/data qualification run.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','validation', ...
    'lls_tdd_coupled_access_boundary.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
m=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,m,struct(),9);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,stream]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
assert(stream.Events.NextSampleIndex==0);
assert(logical(cfg.lls6g.energy_efficiency.enabled) && ...
    ~isempty(stream.Physical.readRFExecutionLedger()), ...
    'Enabled energy diagnostics must initialize the actual RF execution producer.');
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
transmittedSI=reshape(double(p.Tx.SIB1TransmitSSBIndices0Based),1,[]);
assert(~isempty(transmittedSI) && ...
    numel(p.Tx.SIB1Transmissions)==numel(transmittedSI), ...
    'The test must use the actual configured SI transmit set, not receiver hypotheses.');
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
        assert(replay.RuntimeChannelAlignmentLookaheadSamples==0 && ...
            ~replay.RuntimeChannelAlignmentLookaheadExecutedOnFork && ...
            replay.RuntimeChannelAppliedAlignmentTrimSamples==0 && ...
            string(replay.RuntimeChannelOutputSampleAlignment)=="continuous_raw_samples", ...
            'Observed shared-stream metadata must retain the executed no-lookahead/no-trim channel alignment.');
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
            % This fixture transmits SIB1 for its selected SSB occasion,
            % not for every PBCH search hypothesis. Require every actual
            % SI transmission and PBCH candidate to decode; do not assert
            % successful SI decoding where no SI waveform was emitted.
            observedIndices=cellfun(@(x)double(x.SSBIndex),receivedPBCH.CandidateResults);
            siObserved=ismember(observedIndices,transmittedSI);
            allPBCH=all(cellfun(@(x)x.PBCH.Ok,receivedPBCH.CandidateResults));
            allTransmittedSI=all(ismember(transmittedSI,observedIndices)) && ...
                all(cellfun(@(x)x.Ok,receivedPBCH.CandidateResults(siObserved)));
            if ~(allPBCH && allTransmittedSI)
                actualPost=rawPost.readComplete(); actualPre=pre.readComplete(); actualTX=tx.readComplete();
                failureFolder=tempname(fullfile(pwd,'logs')); mkdir(failureFolder);
                save(fullfile(failureFolder,'coupled_stream_failure_capture.mat'), ...
                    'actualPost','actualPre','actualTX','receivedPBCH','p','receivedTRS','cfg','replay','-v7.3');
            end
            assert(allPBCH && allTransmittedSI, ...
                'Actual transmitted shared PBCH/SIB1 reception failed: %s',receivedPBCH.FailureReason);
            assert(~any(cellfun(@(x)x.Ok,receivedPBCH.CandidateResults(~siObserved))), ...
                'A nontransmitted SI occasion must not be promoted into successful SIB1 evidence.');
        else
            receivedPrepared=item.Context.Prepared;
            desiredReference=sixgr.truth.sharedLinkScoringObservation( ...
                item.Planes,receivedPrepared,item.Context.DesiredReferencePlane);
            receivedTRS=sixgr.link.completeTRSReception( ...
                receivedPrepared,post,replay,ch,'DesiredReferenceObservation',desiredReference);
            fprintf('TRS_CHANNEL_SCORE nmse_db=%g threshold_db=%g available=%d mode=%s reason=%s\n', ...
                receivedTRS.NMSE_dB,receivedTRS.ChannelNMSEThreshold_dB, ...
                receivedTRS.NMSEScoringAvailable,string(receivedTRS.ChannelNMSEQualificationMode), ...
                string(receivedTRS.FailureReason));
            assert(receivedTRS.Ok && receivedTRS.StrictOk && ~receivedTRS.Crash, ...
                'Actual shared TRS reception failed: %s',receivedTRS.FailureReason);
        end
        after=stream.channelState(1,"DL"); assert(after.CurrentSampleIndex==before);
    end
end
assert(isequal(sort(seen),["PBCH";"TRS"]) && isempty(stream.Pending));
executionRecord=stream.Physical.readRFExecutionLedger();
assert(executionRecord.CompleteFromSampleZero && ...
    all(executionRecord.Coverage.ExecutedSamples==stream.Events.NextSampleIndex) && ...
    height(executionRecord.Inventory)==4 && ...
    any(executionRecord.Intervals.InputIsAllZero) && ...
    ~executionRecord.HardwareOperatingStateAvailable, ...
    'Production TDD execution must retain all four RF endpoint clocks, not just published SSB/TRS windows.');
published=sixgr.truth.publishRFEndpointExecutionLedger(cfg,fullfile(tempname,'air_interface'), ...
    struct('CoupledRuntime',state));
assert(published.Available && published.Evidence.CompleteFromSampleZero && ...
    published.Evidence.EndSampleExclusive==stream.Events.NextSampleIndex, ...
    'The normal production owner must reach the compact execution exporter.');
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
