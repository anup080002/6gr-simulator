function result=runPUCCHDetectorPilot(configPath,outputRoot)
% Actual shared-clock TDD detector development episodes, not qualification.
% Payload vectors and initial TAG are declared test inputs, not fabricated
% decoded DL outcomes. No transmitted object is supplied to the PUCCH RX.
assert(~isfolder(outputRoot),'test:EvidenceExists','Use a new pilot output folder.');
v=sixgr.lls6g.config.readConfigFile(configPath);
validatePUCCHDetectorPilotPolicy(v);
cases=v.cases;
mkdir(outputRoot); mkdir(fullfile(outputRoot,'meta'));
copyfile(configPath,fullfile(outputRoot,'meta','pilot_config.yaml'));
scenario=sixgr.lls6g.config.loadScenarioConfig(v.scenario_path);
sixgr.util.jsonWrite(fullfile(outputRoot,'meta','base_resolved_scenario.json'),scenario.toStruct());
sixgr.util.jsonWrite(fullfile(outputRoot,'meta','pilot_policy.json'),v);
[code,revision]=system('git rev-parse HEAD'); assert(code==0);
[code,before]=system('git status --porcelain'); assert(code==0 && isempty(strtrim(before)));
sixgr.util.jsonWrite(fullfile(outputRoot,'meta','environment.json'), ...
    struct('GitRevision',strtrim(revision),'MATLABVersion',version,'Platform',computer, ...
    'Scope','development pilot; initial TAG preconfigured; not access or detector qualification'));
allRows=table(); failures=struct('Episode',{},'Identifier',{},'Message',{});
oldRNG=rng; cleanup=onCleanup(@()rng(oldRNG)); %#ok<NASGU>
for episode=1:v.episodes
    folder=fullfile(outputRoot,sprintf('episode_%06d',episode)); mkdir(folder);
    s=scenario.toStruct(); seed=v.seed_base+(episode-1)*v.seed_stride;
    for path=string(v.scenario_seed_paths(:)).'
        assert(~isempty(sixgr.util.structGet(s,path,[])),'test:MissingSeedPath','Missing authored seed path %s.',path);
        s=sixgr.util.structSet(s,path,seed);
    end
    sixgr.lls6g.config.validateScenarioConfig(s,'Kind','scenario','AllowPartial',false);
    cfg=sixgr.lls6g.buildInternalConfig(s,folder);
    assert(cfg.run.seed==seed && cfg.channel.seed==seed,'test:SeedAuthority','Episode seed must reach noise and fading.');
    rng(seed,'twister');
    sixgr.util.jsonWrite(fullfile(folder,'resolved_scenario.json'),s);
    save(fullfile(folder,'configuration.mat'),'cfg','v','seed');
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),v.last_slot);
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,v.last_slot,cfg.channel.snr_dB);
    state.CurrentServingIdx(:)=1;
    state.DetectorPilot=struct('Policy',v,'Folder',folder,'Episode',episode,'Seed',seed,'Rows',table());
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
    try
        for slot=1:v.last_slot
            state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
            state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
            if ismember(slot,v.broadcast_slots)
                [dl,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
                dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
                p=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
                    'UseRuntimeChannel',true,'RuntimeSlot',slot-1);
                assert(isfield(p,'PreparedBroadcast'),'test:BroadcastPreparation','%s',p.FailureReason);
                owner.queueDownlink('PBCH',1,p.PreparedBroadcast, ...
                    struct('Config',dl,'Slot',slot,'ServingCell',1,'TrackingOnly',true));
            end
            % A timing-advanced SRS capture starts before its nominal slot.
            % Queue the complete contribution before advancing that prefix;
            % never rewrite an already committed transmitter interval.
            srsSlot=slot+1;
            if ismember(srsSlot,v.srs_slots)
                [ul,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
                ul=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,srsSlot);
                ul.lls6g.userContext.RuntimeSlotStartTime_s=(srsSlot-1)*state.SlotDuration_s;
                args={'SlotIndex',srsSlot,'SNR_dB',cfg.channel.snr_dB, ...
                    'TimingAdvanceSamples',ul.SharedULTimingContext.ReceivedRARTiming.Samples};
                p=sixgr.link.runSRSChannelEstimation(ul,args{:},'PrepareOnly',true);
                assert(p.PreparedTransmission.StartSample>=owner.Events.NextSampleIndex, ...
                    'test:PilotLateSRSPreparation','SRS must be queued before its actual timing-advanced TX start.');
                fprintf('DETECTOR_PILOT_SRS_ARM slot=%d clock=%.0f tx_start=%.0f rx_start=%.0f\n', ...
                    srsSlot,owner.Events.NextSampleIndex,p.PreparedTransmission.StartSample, ...
                    p.PreparedTransmission.ReceiveStartSample);
                owner.queueUplinkControl(1,p.PreparedTransmission,struct('Config',ul,'Arguments',{args}));
            end
            % Arm at the preceding boundary, before the timing-advanced TX.
            hit=find([cases.slot]==slot+1);
            if ~isempty(hit)
                state=localArm(state,cfg,cases(hit));
            end
            [state,~]=owner.advanceSlot(state,cfg,@localEvents);
        end
        assert(height(state.DetectorPilot.Rows)==numel(cases),'test:IncompletePilot','Every case requires actual receive evidence.');
        assert(isequal(sort(string(state.DetectorPilot.Rows.CaseID)),sort(string({cases.id}).')), ...
            'test:IncompletePilot','Duplicate receive rows cannot replace a missing case.');
    catch err
        [diagnosticText,diagnostic]=sixgr.util.formatExceptionDiagnostic(err);
        fprintf('%s\n',diagnosticText);
        sixgr.util.jsonWrite(fullfile(folder,'failure_diagnostic.json'),diagnostic);
        save(fullfile(folder,'episode_failure.mat'),'diagnosticText','diagnostic','state','-v7.3');
        failures(end+1)=struct('Episode',episode,'Identifier',err.identifier,'Message',err.message); %#ok<AGROW>
        fprintf('DETECTOR_PILOT_EPISODE_FAILED episode=%d id=%s message=%s\n',episode,err.identifier,err.message);
    end
    if ~isempty(state.DetectorPilot.Rows)
        if isempty(allRows), allRows=state.DetectorPilot.Rows; else, allRows=[allRows;state.DetectorPilot.Rows]; end %#ok<AGROW>
        sixgr.util.csvWriteTable(fullfile(outputRoot,'physical_trials.csv'),allRows,'PreserveSchema',true);
    end
    clear owner state;
end
% Missing physical episodes are a separate failure, never invented RF rows.
summary=cell(numel(cases),1);
for k=1:numel(cases)
    c=cases(k); t=table();
    if ~isempty(allRows), t=allRows(string(allRows.CaseID)==string(c.id),:); end
    executed=height(t); errors=0;
    if executed>0, errors=sum(t.EventError); end
    unavailable=v.episodes-executed; upper=1;
    if errors+unavailable<v.episodes
        upper=betaincinv(1-v.family_alpha/numel(cases),errors+unavailable+1,v.episodes-errors-unavailable);
    end
    summary{k}=struct('CaseID',string(c.id),'PlannedEpisodes',v.episodes,'ExecutedEpisodes',executed, ...
        'UnavailableEpisodes',unavailable,'ObservedEventErrors',errors, ...
        'ConservativeFailureUpperBound',upper,'EventErrorLimit',v.event_error_limit, ...
        'ConfidenceGatePassed',unavailable==0 && upper<=v.event_error_limit, ...
        'DetectorQualified',false,'Scope',"development_pilot_not_held_out_qualification");
end
summary=struct2table(vertcat(summary{:}));
sixgr.util.csvWriteTable(fullfile(outputRoot,'case_summary.csv'),summary,'PreserveSchema',true);
result=struct('PhysicalPilotComplete',isempty(failures) && all(summary.UnavailableEpisodes==0), ...
    'DetectorQualified',false,'GitRevision',strtrim(revision),'Summary',summary,'Failures',failures);
save(fullfile(outputRoot,'pilot_result.mat'),'result');
sixgr.util.jsonWrite(fullfile(outputRoot,'receipt.json'),rmfield(result,'Summary'));
[code,afterRevision]=system('git rev-parse HEAD'); assert(code==0 && strcmp(revision,afterRevision));
[code,after]=system('git status --porcelain'); assert(code==0 && strcmp(before,after));
fprintf('DETECTOR_PILOT_COMPLETE physical_complete=%d detector_qualified=0\n',result.PhysicalPilotComplete);
end

function state=localArm(state,cfg,c)
owner=state.SharedWaveformStream;
[ul,state]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
ul=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,c.slot);
ul.lls6g.userContext.RuntimeSlotStartTime_s=(c.slot-1)*state.SlotDuration_s;
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
first=sixgr.phy.frame.slotStartSample(carrier,c.slot-1,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,c.slot,fs);
timing=sixgr.link.resolveConnectedULTransmissionTiming(ul,first/fs,fs,stop-first);
assert(isfield(state,'ReceivedULTimingReferences') && ~isempty(state.ReceivedULTimingReferences{1}));
owner.queuePUCCHPreparation(1,timing,ul,struct('Config',ul,'Slot',c.slot,'PilotCase',c));
end

function state=localEvents(state,items)
owner=state.SharedWaveformStream; v=state.DetectorPilot.Policy;
for item=items
    if item.Kind=="PreparePUCCH"
        c=item.Context.PilotCase; cfg=item.Context.Config;
        ue=struct('UEID',1,'RNTI',cfg.phy.pusch.RNTI,'ServingCell',1,'PUCCHCell',1, ...
            'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID,'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
        rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
        authority=sixgr.phy.pucch.resolveConfiguredPRI(cfg,ue.UEID,ue.RNTI);
        context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',"pilot-"+string(c.id), ...
            'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',c.harq_bits,'Sequence2Length',0, ...
            'HARQACKBits',c.harq_bits,'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0,'PriorityIndex',0));
        assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(struct('ObservationID',item.Context.ObservationID, ...
            'ResourceID',authority.ResourceId,'RNTI',ue.RNTI,'AbsoluteSlot0',c.slot-1, ...
            'Source','configured_detector_test_receive_hypothesis','TimingSource','prior_received_SRS'),rrc,context);
        assert(assignment.Format==0,'test:PilotFormat','Pilot is Format 0 only.');
        hypothesis=struct('Assignment',assignment,'Context',context,'Mapping',struct('UEIndex',1,'TargetSlot',c.slot));
        if ~c.signal_present
            owner.bindPUCCHReceiveOnly(item.Context.ObservationID,cfg,hypothesis);
        else
            ue.ConfigurationEpoch=rrc.ConfigurationEpoch;
            report=sixgr.phy.pucch.UCIReport(struct('ReportID',context.ReportID,'RNTI',ue.RNTI, ...
                'ServingCell',ue.ServingCell,'ComponentCarrier',ue.ComponentCarrier,'ULBWP',ue.ActiveULBWP, ...
                'ConfigurationEpoch',rrc.ConfigurationEpoch,'TargetSlot',c.slot,'PriorityIndex',0, ...
                'HARQACKReport',struct('Bits',int8(c.payload(:))),'SchedulingRequestReports',struct([]), ...
                'CSIReports',struct([]),'ReportSource','declared_detector_test_vector_not_decoded_DL', ...
                'TriggeringEventIDs',"detector-pilot-"+string(c.id)));
            % K1=0 is an explicit detector test occasion, not a scheduled DL
            % ACK timing claim. Actual TDD symbol legality remains enforced.
            frame=struct('K1',0,'K1Source','configured_detector_test_occasion', ...
                'PDSCHEndSlot',c.slot,'TargetSlot',c.slot,'DecodedPRI',authority.PRIValue, ...
                'PRIFieldWidth',3,'PRIProvenance',authority.Source,'FlexibleResolutionProvided',false);
            plan=sixgr.phy.pucch.PUCCHResourcePlan(report,ue,rrc,frame,'declared_detector_test_vector');
            tx=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(cfg,struct('Plan',plan,'Report',report));
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            p=sixgr.link.runPUCCHWaveformTrial(cfg,'Assignment',tx.Assignment,'Report',report, ...
                'Carrier',carrier,'ChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
                'SNR_dB',cfg.channel.snr_dB,'Seed',state.DetectorPilot.Seed, ...
                'TimingAdvanceSamples',cfg.SharedULTimingContext.ReceivedRARTiming.Samples,'PrepareOnly',true);
            cxt=item.Context; cxt.GNBReception=hypothesis;
            owner.queueUplinkControl(1,p.PreparedTransmission,cxt);
        end
        continue;
    end
    if item.Kind=="PBCH", continue; end
    if item.Kind=="SSBOccasion"
        [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes);
        p=item.Context.Prepared; h=item.Context.SSBOccasionHorizon;
        r=sixgr.phy.broadcast.recoverSIB1FromWaveform(post,p.ReceiverConfig, ...
            'RecoveryScope','SSB_MIB','CandidateSSBIndex',h.SSBIndex,'PhysicalMeasurementObservation',pre);
        fixedNormalizedEsN0=strcmpi(string(sixgr.util.structGet( ...
            item.Context.Config,'integration.run_mode','')),'FIXED_SNR_SWEEP') && ...
            logical(sixgr.util.structGet(item.Context.Config, ...
            'integration.configured_snr_is_link_authority',false));
        % This partial-SSB receiver does not go through the full broadcast
        % completion's power-domain labelling. Preserve its actual numeric
        % measurement, but never publish normalized samples as physical dBm.
        measuredRSRP=double(r.SS_RSRP_dBm);
        if fixedNormalizedEsN0
            r.SS_RSRP_dB_re_NormalizedIFFTSample=measuredRSRP;
            r.SS_RSRPPerReceiveAntenna_dB_re_NormalizedIFFTSample=r.SS_RSRPPerReceiveAntenna_dBm;
            r.SS_RSRPRawObserved_dB_re_NormalizedIFFTSample=r.SS_RSRPRawObserved_dBm;
            r.SS_RSRPRawObservedPerReceiveAntenna_dB_re_NormalizedIFFTSample=r.SS_RSRPRawObservedPerReceiveAntenna_dBm;
            r.SSBWindowRSSIPerReceiveAntenna_dB_re_NormalizedIFFTSample=r.SSBWindowRSSIPerReceiveAntenna_dBm;
            r.SSBWindowPowerMeasurementJSON_NormalizedIFFTSample=r.SSBWindowPowerMeasurementJSON;
            r.SS_RSRP_dBm=NaN; r.SS_RSRPPerReceiveAntenna_dBm="";
            r.SS_RSRPRawObserved_dBm=NaN; r.SS_RSRPRawObservedPerReceiveAntenna_dBm="";
            r.SSBWindowRSSIPerReceiveAntenna_dBm=""; r.SSBWindowPowerMeasurementJSON="";
            r.PowerReferencePlane="normalized_IFFT_sample_unit_mapping_not_device_budget";
            r.SSPhysicalMeasurementStatus="available_normalized_not_absolute_dbm";
        end
        save(fullfile(state.DetectorPilot.Folder,sprintf('ssb_%06d.mat',state.CurrentSlot)), ...
            'r','item','pre','post','tx','replay','-v7.3');
        assert(r.BCHCrcPass && r.MIBDecoded && isfinite(measuredRSRP), ...
            'test:PilotSSB','Actual SSB acquisition/measurement failed.');
        ch=owner.channelState(1,'DL');
        reference=sixgr.phy.frame.receivedDLTimingReference(p.ReceiverConfig,r,post,ch.ChannelTrimSamples);
        % This component pilot preconfigures common power; it does not decode
        % SIB1 on air. Bind that input to the resolved scenario, and separately
        % verify agreement with the actual broadcast transmitter contract.
        % Neither an arbitrary dBm constant nor a measured pathloss is injected.
        [~,configuredPower]=sixgr.rf.resolveSSBPowerContract(item.Context.Config);
        actualPower=p.Tx.SSBPowerReferenceContract;
        assert(configuredPower.Available && actualPower.Available && ...
            configuredPower.SSPBCHBlockPower_dBm==actualPower.SSPBCHBlockPower_dBm && ...
            configuredPower.ReferencePlane==actualPower.ReferencePlane, ...
            'test:PilotSSBPowerAuthority','Preconfigured SSB declaration must match actual configured TX EPRE.');
        if ~isfield(state,'ConnectedULTimingByUE') || isempty(state.ConnectedULTimingByUE{1})
            carrier=sixgr.phy.grid.makeCarrier(p.ReceiverConfig); fs=owner.SampleRateHz;
            common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
            state.ConnectedULTimingByUE={struct('DLReference',reference, ...
                'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
                'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(v.initial_tag.command,carrier.SubcarrierSpacing,fs), ...
                'TimingAdvanceAvailableAtSample',post.EndSampleExclusive,'TimingAdvanceEffectiveAtSample',post.EndSampleExclusive, ...
                'TimeAlignmentExpirySampleExclusive',round(v.initial_tag.validity_ms*1e-3*fs))};
            state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(state.CfgMobility, ...
                configuredPower.SSPBCHBlockPower_dBm,item.Context.ServingCell,state.CurrentSlot)};
            state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;
            sixgr.util.jsonWrite(fullfile(state.DetectorPilot.Folder,'preconfigured_common_power.json'), ...
                struct('Source','explicit_component_configuration_not_on_air_SIB1_reception', ...
                'ConfiguredContract',configuredPower,'ActualTransmitterContract',actualPower, ...
                'InstalledSSPBCHBlockPower_dBm',state.UECommonCellConfigurationByUE{1}.SSPBCHBlockPower_dBm));
        end
        assert(state.UECommonCellConfigurationByUE{1}.SSPBCHBlockPower_dBm== ...
            configuredPower.SSPBCHBlockPower_dBm,'test:PilotSSBPowerChanged', ...
            'Every SSB refresh must match the installed common power declaration.');
        if fixedNormalizedEsN0
            % Actual samples/timing and every normalized measurement remain
            % in this occasion's MAT. The absolute-RSRP ledger must not gain
            % an invented dBm row merely to satisfy a power-control shape.
            assert(isnan(r.SS_RSRP_dBm) && isfinite(r.SS_RSRP_dB_re_NormalizedIFFTSample));
            continue;
        end
        row=table(double(item.Context.ServingCell),double(r.SSBIndex),double(r.SS_RSRP_dBm),double(r.SS_SINR_dB), ...
            'VariableNames',{'ServingCell','ReferenceSignalId','SS_RSRP_dBm','SS_SINR_dB'});
        state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime(state, ...
            'SSB','UE',1,row,'ProducerSlot',state.CurrentSlot,'AvailableSlot',state.CurrentSlot, ...
            'Valid',true,'Direction','DL','SourceSignal','SSB', ...
            'MeasurementSource','actual_shared_SSB_pre_rx_rf_measurement');
        continue;
    end
    if item.Kind=="SRS"
        c=item.Context; p=c.Prepared;
        [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        [~,~,refs]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        input=struct('Prepared',p,'Observation',post,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{refs}, ...
            'ChannelState',owner.directionalChannelState(1,'UL'));
        out=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
        assert(out.Ok,'test:PilotSRS','Actual SRS acquisition failed.');
        state.ReceivedULTimingReferences={sixgr.phy.sync.ReceivedULTimingReference(p,post,out.ReceiveTiming)};
        save(fullfile(state.DetectorPilot.Folder,sprintf('srs_%06d.mat',state.CurrentSlot)), ...
            'item','out','pre','post','tx','replay','-v7.3');
        continue;
    end
    assert(any(item.Kind==["PUCCH","PUCCHReceiveOnly"]),'test:PilotUnexpectedEvent','Unexpected event %s.',item.Kind);
    c=item.Context; testCase=c.PilotCase;
    if testCase.signal_present
        [~,pre,tx,replay,post]=sixgr.truth.sharedObservationEvidence(item.Planes,c.Prepared);
    else
        % No fake prepared transmitter merely to fit the TX/RX helper API.
        ids=string({item.Planes.ReceiverID});
        ri=find(endsWith(ids,':post_rf')); pi=find(endsWith(ids,':pre_rf')); ti=find(endsWith(ids,':tx'));
        assert(isscalar(ri) && isscalar(pi) && isscalar(ti));
        post=item.Planes(ri).Observation; pre=item.Planes(pi).Observation; tx=item.Planes(ti).Observation;
        assert(post.isComplete() && pre.isComplete() && tx.isComplete() && ...
            pre.StartSample==post.StartSample && pre.EndSampleExclusive==post.EndSampleExclusive);
        replay=item.Planes(ri).Segments; % Preserve every physical execution segment.
    end
    hypothesis=c.GNBReception;
    out=sixgr.link.receivePUCCHObservation(c.Config,hypothesis.Assignment,hypothesis.Context, ...
        post,state.ReceivedULTimingReferences{1});
    assert(out.IndependentReceiverAssignment && ~out.PreparedTransmitterConsumed && ~out.InjectedNoiseVarianceConsumed);
    if ~testCase.signal_present
        assert(item.Kind=="PUCCHReceiveOnly" && ~isfield(c,'Prepared') && ...
            ~any(tx.readComplete()~=0,'all'),'test:PilotNoiseTX','Noise-only case cannot contain a transmitter contribution.');
    end
    counts=countPUCCHDetectorPilotErrors(testCase,out.DecodedSequence1, ...
        out.ReceiverUsable,out.DTX);
    decoded=int8(out.DecodedSequence1(:));
    eventError=counts.EventError;
    path=fullfile(state.DetectorPilot.Folder,string(testCase.id)+".mat");
    save(path,'item','out','pre','post','tx','replay','hypothesis','testCase','-v7.3');
    row=table(state.DetectorPilot.Episode,state.DetectorPilot.Seed,string(testCase.id), ...
        testCase.slot,logical(testCase.signal_present),testCase.harq_bits,string(jsonencode(testCase.payload)), ...
        string(jsonencode(decoded)),logical(out.DTX),double(out.DetectionMetric),double(out.DetectionThreshold), ...
        logical(eventError),post.StartSample,post.EndSampleExclusive,post.SampleRateHz, ...
        string(out.ReceiveTiming.TimingSource),out.ReceiveTiming.ReferenceAgeSlots,string(path), ...
        string(sixgr.util.sha256File(path)), ...
        'VariableNames',{'Episode','Seed','CaseID','Slot','SignalPresent','HARQBits','DeclaredPayloadJSON', ...
        'DecodedPayloadJSON','DTX','DetectionMetric','DetectionThreshold','EventError', ...
        'ObservationStartSample','ObservationEndSampleExclusive','SampleRateHz','TimingSource', ...
        'TimingReferenceAgeSlots','EvidencePath','EvidenceSHA256'});
    row=[row struct2table(rmfield(counts,'EventError'),'AsArray',true)];
    assert(isempty(state.DetectorPilot.Rows) || ...
        ~any(string(state.DetectorPilot.Rows.CaseID)==string(testCase.id)), ...
        'test:DuplicatePilotReception','One physical case cannot be counted twice in an episode.');
    if isempty(state.DetectorPilot.Rows), state.DetectorPilot.Rows=row; else, state.DetectorPilot.Rows=[state.DetectorPilot.Rows;row]; end
    fprintf('DETECTOR_PILOT_CASE episode=%d case=%s metric=%.9g error=%d\n',state.DetectorPilot.Episode,testCase.id,out.DetectionMetric,eventError);
end
end
