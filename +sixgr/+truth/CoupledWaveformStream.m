classdef CoupledWaveformStream < handle
    % Scheduler-owned physical clock. Preparation registers actual samples;
    % only advanceSlot consumes RF/channel/noise and completes observations.
    % No completed decoder result is queued in place of a transmission.
    properties (SetAccess=private)
        Physical
        Events
        SampleRateHz
        Pending = struct('ID',{},'Kind',{},'UE',{},'Context',{},'Planes',{})
        DataTransmissions = struct('Identity',{},'FirstActiveSample',{},'CommittedAtSample',{},'WaveformToElementMatrix',{},'TransmitOccupancy',{})
        SIB1Transmissions = struct('ComponentID',{},'ServingCell',{},'SSBIndex',{}, ...
            'AbsoluteSlot',{},'StartSample',{},'EndSampleExclusive',{}, ...
            'SampleRateHz',{},'PhysicalConfigurationEpoch',{},'CommittedAtSample',{}, ...
            'TransmitSampleSHA256',{},'PreparedSampleSHA256',{},'SIB1PayloadHash',{}, ...
            'PrecoderMatrixSHA256',{},'PDCCHDataIndicesOneBased',{},'PDCCHDMRSIndicesOneBased',{}, ...
            'PDSCHDataREIndicesZeroBased',{},'PDSCHDMRSREIndicesZeroBased',{},'ExecutionProof',{})
        SSBTransmissions = struct('ComponentID',{},'ServingCell',{},'AbsoluteSlot',{}, ...
            'StartSample',{},'EndSampleExclusive',{},'SampleRateHz',{}, ...
            'PhysicalConfigurationEpoch',{},'CommittedAtSample',{}, ...
            'PreparedSampleSHA256',{},'TransmitSampleSHA256',{},'ExecutionProof',{})
        CSIRSTransmissions = struct('ComponentID',{},'SignalFamily',{}, ...
            'ServingCell',{},'Slot',{},'FirstActiveSample',{}, ...
            'CommittedAtSample',{},'EndSampleExclusive',{}, ...
            'SampleRateHz',{},'PhysicalConfigurationEpoch',{}, ...
            'ResourceSetID',{},'ResourceIDs',{},'WaveformMappedRE',{}, ...
            'ReferenceConfiguration',{},'ReportConfiguration',{}, ...
            'FrameIdentity',{},'ExecutedResourceMaps',{},'TXAmplitudeScale',{}, ...
            'TransmitterID',{},'TransmitStartSample',{},'TransmitObservationSHA256',{}, ...
            'CarrierIdentity',{},'PopulationIdentity',{})
        PUCCHTransmissions = struct('Identity',{},'FirstActiveSample',{},'CommittedAtSample',{},'WaveformToElementMatrix',{},'TransmitOccupancy',{})
        ControlObservationDispositions = struct('ID',{},'UE',{},'Reason',{},'CompletedAtSample',{},'TransferProof',{})
        SRSSuppressionLedger = struct('SRSObservationID',{},'PUCCHObservationID',{},'UE',{},'Decision',{},'Cancellation',{})
        PUSCHReceiveOnlyRegistrations = struct('ID',{},'UE',{},'GrantContextID',{},'StartSample',{},'EndSampleExclusive',{})
        ContentionWindows = struct('UE',{},'RunId',{},'StartTicks',{})
    end
    properties (Access=private)
        Nodes = struct('ID',{},'Direction',{},'NumAntennas',{},'RF',{})
        Links = struct('ID',{},'UE',{},'Cell',{},'Direction',{},'DLConfig',{},'ULConfig',{})
        Components = struct('ID',{},'TX',{},'Start',{},'Samples',{})
        Serial = 0
        TxIQRecorder = []
        Decisions = struct('ID',{},'Kind',{},'UE',{},'Context',{})
        PDCCHResourceLedger = struct()
        CommonRAReservations = sixgr.truth.CommonRAResourceCalendar()
        PUSCHReceiveOnlyCompletions = cell(0,1)
        PUSCHReceiveOnlyArchives = cell(0,1)
        ScheduledControlRegistrations = cell(0,1)
        SIB1Registrations = struct('ComponentID',{},'ContractSHA256',{})
        SIB1ReceiveRegistrations = struct('ID',{},'UE',{},'GenerationID',{}, ...
            'AbsoluteMonitoringSlot',{},'StartSample',{},'EndSampleExclusive',{}, ...
            'ReceiverConfigSHA256',{},'BindingSHA256',{},'DeliverySHA256',{})
        BroadcastCompletions = cell(0,1)
        CellBroadcasts = struct('Cell',{},'Config',{},'ConfigSHA256',{},'Plan',{}, ...
            'PeriodSlots',{},'LastSSBSlot',{},'Prepared',{},'Prototype',{})
        CellBroadcastSchedule = struct('Slot',{},'Bursts',{},'SIComponents',{})
        CellSSBRegistrations = struct('ComponentID',{},'PreparedSHA256',{})
        CellSSBObservers = struct('Cell',{},'UE',{},'Slot',{},'ID',{},'ContextSHA256',{})
        CellBroadcastSchedulingActive = false
        UnselectedPUCCHRegistrations = cell(0,1)
        UnselectedPUCCHProducers = cell(0,1)
        Msg1TXRegistrations = cell(0,1)
        Msg1TXCompletions = cell(0,1)
    end
    methods (Static)
        function [state,obj]=initialize(state,cfg,userCfg)
            % Materialization does not execute a waveform. Zero-duration
            % layout probes below only bind the configured antenna mapping.
            if state.CurrentSlot~=1
                error('sixgr:truth:SharedStreamOriginRequired', ...
                    'Initialize the physical owner at the first canonical slot, not at a later observation.');
            end
            % Validate every UE before materializing any RF/channel owner.
            % Otherwise legacy grant construction can run through access and
            % fail only at the first independently scheduled HARQ occasion.
            for ue=1:numel(userCfg)
                sixgr.truth.validateSharedDCIConfiguration(userCfg{ue});
            end
            sixgr.truth.validateCoupledNoisePowerAuthority(cfg);
            for ue=1:numel(userCfg)
                sixgr.truth.validateCoupledNoisePowerAuthority(userCfg{ue});
            end
            obj=sixgr.truth.CoupledWaveformStream();
            % Intra-cell and MU-MIMO interference are represented by the
            % shared serving-link composite. Inter-cell interference still
            % requires explicit source-cell-to-victim cross-links.
            if logical(sixgr.util.structGet(cfg, ...
                    "lls6g.resolvedConfig.interference.inter_cell_interference_flag",false))
                error('sixgr:truth:SharedInterferenceLinksRequired', ...
                    'Enabled inter-cell interference requires explicit cross-links in the shared physical owner; serving links alone are insufficient.');
            end
            carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
            obj.SampleRateHz=double(info.SampleRate);
            epoch=sixgr.util.structGet(cfg,'rf.configurationEpoch',[]);
            obj.Physical=sixgr.truth.SharedWaveformPhysicalRuntime(obj.SampleRateHz,0,epoch);
            obj.Events=sixgr.phy.waveform.WaveformEventRuntime(obj.SampleRateHz,0, ...
                @(inputs,first,stop,owner)owner.process(inputs,first,stop,[]),obj.Physical);
            mode=sixgr.phy.frame.resolveDuplexMode(cfg);
            % Use the canonical duplex resolver, not a scenario-name guess.
            [dlAllowed,ulAllowed,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,1);
            if isfield(partition,'DuplexMode'), mode=upper(string(partition.DuplexMode)); end
            if ~any(mode==["TDD","FDD"])
                error('sixgr:truth:SharedStreamDuplexAuthority','Explicit TDD or FDD authority is required.');
            end
            for ue=1:numel(userCfg)
                [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(userCfg{ue},state,ue,'DL');
                [ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(userCfg{ue},state,ue,'UL');
                cellID=double(state.CurrentServingIdx(ue));
                validateattributes(cellID,{'numeric'},{'scalar','integer','positive','finite'});
                [state,ch]=sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl(state,dl,ue,'DL');
                ch=localMaterialize(dl,ch,info);
                if ch.CurrentSampleIndex~=0 || ch.SampleRate_Hz~=obj.SampleRateHz
                    error('sixgr:truth:SharedStreamChannelOrigin','Channel materialization must not consume samples.');
                end
                obj.registerNode("gnb_"+cellID,dl,'DL',ch.NumTxAnt,true);
                obj.registerNode("ue_"+ue,ul,'UL',ch.NumRxAnt,true);
                obj.registerNode("ue_"+ue+"_rx",dl,'DL',ch.NumRxAnt,false);
                obj.registerNode("gnb_"+cellID+"_rx",ul,'UL',ch.NumTxAnt,false);
                id="link_"+cellID+"_"+ue;
                obj.Physical.addLink(id,"gnb_"+cellID,"ue_"+ue+"_rx",ch,dl);
                obj.Links(end+1)=struct('ID',id,'UE',ue,'Cell',cellID, ...
                    'Direction',"DL",'DLConfig',dl,'ULConfig',ul);
                state=sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state,ch);
                if mode=="FDD"
                    [state,uch]=sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl(state,ul,ue,'UL');
                    uch=localMaterialize(ul,uch,info);
                    obj.Physical.addLink(id+"_ul","ue_"+ue,"gnb_"+cellID+"_rx",uch,ul);
                    obj.Links(end+1)=struct('ID',id+"_ul",'UE',ue,'Cell',cellID, ...
                        'Direction',"UL",'DLConfig',dl,'ULConfig',ul);
                    state=sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state,uch);
                end
            end
            obj.Physical.attach(obj.Events,'double');
            if logical(sixgr.util.structGet(cfg,'lls6g.energy_efficiency.enabled',false)) || ...
                    logical(sixgr.util.structGet(cfg,'rf.txSpatialPowerEnabled',false)) || ...
                    logical(sixgr.util.structGet(cfg,'rf.modeledRadiatedPower.Enabled',false)) || ...
                    logical(sixgr.util.structGet(cfg,'rf.txLinearReference.Enabled',false))
                obj.Physical.enableRFExecutionLedger();
            end
            if logical(sixgr.util.structGet(cfg, ...
                    'outputs.continuousRawIQCaptureEnabled',false))
                rootRunFolder=string(sixgr.util.structGet( ...
                    cfg,'run.rootRunFolder',''));
                if strlength(strtrim(rootRunFolder))==0
                    error('sixgr:truth:ContinuousTxIQRunFolderMissing', ...
                        'Continuous shared-clock Tx-IQ requires run.rootRunFolder.');
                end
                obj.TxIQRecorder=sixgr.truth.RuntimeTxIQStreamRecorder( ...
                    rootRunFolder,cfg,obj.SampleRateHz);
            end
            if mode=="TDD" && ~dlAllowed && ulAllowed
                error('sixgr:truth:SharedStreamInitialULBinding', ...
                    'An initially uplink TDD pattern needs initial UL channel binding, not a pre-execution reciprocal swap.');
            end
            state.SharedWaveformStream=obj;
        end
        function rejectLegacy(state,family)
            if isfield(state,'SharedWaveformStream') && ...
                    isa(state.SharedWaveformStream,'sixgr.truth.CoupledWaveformStream')
                error('sixgr:truth:LegacyExecutionOnSharedStream', ...
                    '%s must enqueue its prepared TX and consume actual RX completion; eager execution would advance the stream-owned channel twice.',family);
            end
        end
        function assertULTransmitTime(cfg,sample,fs)
            validateattributes(sample,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            validateattributes(fs,{'numeric'},{'scalar','real','finite','positive'});
            if localFixedDLAtSample(cfg,sample,fs)
                error('sixgr:truth:PhysicalTDDDirectionCollision', ...
                    'A real advanced UL transmission overlaps a fixed DL symbol.');
            end
        end
    end
    methods
        function coordinates=commonRAResources(obj,cellID,slot0,direction,carrier)
            coordinates=obj.CommonRAReservations.lookup(cellID,slot0,direction,carrier);
        end
        function tf=hasPending(obj,kind,ue)
            tf=any(string({obj.Pending.Kind})==string(kind) & [obj.Pending.UE]==ue);
        end
        function [id,enqueueReceipt]=queueRA(obj,ue,prepared,context,transmitOnly)
            if nargin<5, transmitOnly=false; end
            link=obj.linkForUE(ue,string(prepared.Direction));
            cfg=link.DLConfig;
            if prepared.Direction=="UL", cfg=link.ULConfig; end
            unit=sixgr.rf.appliedWaveformAmplitudeUnit(cfg,prepared.PowerContext);
            if prepared.SampleRate_Hz~=obj.SampleRateHz || ~prepared.RFExecutionDeferred || ...
                    prepared.PhysicalWaveformPlane~="physical_antenna_"+unit+"_before_shared_tx_rf"
                error('sixgr:truth:SharedRAPreparationAuthority','RA samples need physical antenna/power authority on the shared clock.');
            end
            first=sixgr.phy.ra.preparedStageTransmitStartSample(prepared);
            samples=prepared.PhysicalWaveform;
            if prepared.Direction=="UL"
                tx="ue_"+ue; rx="gnb_"+link.Cell+"_rx";
            else
                tx="gnb_"+link.Cell; rx="ue_"+ue+"_rx";
            end
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            if size(samples,2)~=node.NumAntennas || size(samples,1)~=prepared.SampleCount
                error('sixgr:truth:SharedRAAntennaLayout','Prepared RA must match its registered physical radio and complete sample extent.');
            end
            if obj.hasPending("RA",ue) || obj.hasPending("Msg1TX",ue)
                error('sixgr:truth:DuplicatePendingRAStage','One UE cannot queue a second stage before the prior received stage completes.');
            end
            obj.Serial=obj.Serial+1; id="ra_observation_"+obj.Serial;
            reservations=sixgr.util.structGet(prepared,'CommonResourceReservations',struct([]));
            if any(prepared.StageName==["Msg2","Msg4"])
                assert(~isempty(reservations) && all([reservations.CellID]==link.Cell), ...
                    'sixgr:truth:MissingCommonRAReservations','Freeze common DL and consequent UL ownership before enqueue.');
                if prepared.StageName=="Msg4"
                    peers=obj.Links([obj.Links.Cell]==link.Cell & [obj.Links.UE]~=ue);
                    for peer=reshape(peers,1,[])
                        sixgr.truth.CommonRAResourceCalendar.assertPeriodicSRSDisjoint(reservations,peer.ULConfig);
                        uc=peer.ULConfig;
                        identity=struct('UEID',peer.UE,'RNTI',uc.phy.pusch.RNTI, ...
                            'ServingCell',peer.Cell,'PUCCHCell',peer.Cell, ...
                            'ComponentCarrier',uc.phy.frame.DefaultIdentity.ScheduledCCID, ...
                            'ActiveULBWP',uc.phy.frame.DefaultIdentity.ULBWPID);
                        sixgr.truth.CommonRAResourceCalendar.assertInstalledPUCCHDisjoint(reservations,uc,identity);
                    end
                end
                obj.CommonRAReservations=obj.CommonRAReservations.reserve(reservations);
            end
            if nargout>1
                enqueueReceipt=obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,first));
            else
                obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,first));
            end
            if prepared.Direction=="UL"
                active=find(any(samples~=0,2),1,'first');
                if ~isempty(active)
                    boundary=id+"_ul_start";
                    obj.Events.decisionBoundary(boundary,first+active-1);
                    obj.Decisions(end+1)=struct('ID',boundary,'Kind',"ULTransmitBoundary", ...
                        'UE',ue,'Context',struct());
                end
            end
            if transmitOnly, return; end
            % Observe actual subsequent physical samples, including the
            % filter tail. No zeros are appended to a received waveform.
            ch=obj.channelState(ue,string(prepared.Direction));
            stop=first+size(samples,1)+double(ch.ChannelPadSamples);
            if prepared.Direction=="UL"
                first=prepared.ReceiveStartSample;
                stop=prepared.ReceiveEndSampleExclusive;
            end
            for plane=[tx+":tx",rx+":pre_rf",rx+":post_rf"]
                obj.Events.observe(plane,id,first,stop);
            end
            context.Prepared=prepared;
            obj.Pending(end+1)=struct('ID',id,'Kind',"RA",'UE',ue,'Context',context, ...
                'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
        end
        function id=queueMsg1Transmission(obj,ue,prepared,checkpoint)
            % Explicit TX-only API. Main access remains on queueRA until the
            % independent cell detector/response chain is activated together.
            err='sixgr:truth:Msg1TransmissionContract';
            assert(isstruct(checkpoint) && isscalar(checkpoint) && ...
                all(isfield(checkpoint,{'RAConfig','Result','NextStage','ResumePhase','Runtime','RARReceiver'})) && ...
                checkpoint.NextStage==1 && checkpoint.ResumePhase=="prepared" && ...
                string(checkpoint.Runtime.Mode)=="shared_physical_waveform_stream" && ...
                isa(checkpoint.RARReceiver,'sixgr.phy.ra.RARReceiveWindow') && ...
                isequaln(prepared,checkpoint.Result.PreparedTransmission) && ...
                prepared.StageName=="Msg1" && prepared.Direction=="UL", ...
                err,'Retain one original shared Msg1 preparation and its frozen UE RAR window.');
            ra=checkpoint.RAConfig; link=obj.linkForUE(ue,"UL");
            assert(ra.UEId==ue && ra.ServingCell==link.Cell && ...
                isa(ra.PRACHActiveEndTicksExclusive,'int64') && isscalar(ra.PRACHActiveEndTicksExclusive), ...
                err,'The original attempt and physical UE/cell must agree.');
            tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/obj.SampleRateHz;
            assert(tc==fix(tc) && rem(ra.PRACHActiveEndTicksExclusive,int64(tc))==0, ...
                err,'The actual emitted CP/useful end must lie exactly on the shared sample clock.');
            stop=double(ra.PRACHActiveEndTicksExclusive/int64(tc));
            first=sixgr.phy.ra.preparedStageTransmitStartSample(prepared);
            key=string(ra.RunId)+"/ue="+ue+"/attempt="+ra.AttemptId;
            assert(~any(cellfun(@(r)r.Key==key,obj.Msg1TXRegistrations)), ...
                'sixgr:truth:DuplicateMsg1Transmission','An original attempt can enqueue Msg1 only once.');
            native=sixgr.rach.prachSampleTiming(checkpoint.Msg1Tx.Carrier,checkpoint.Msg1Tx.PRACH);
            assert(stop>first && stop<=first+prepared.SampleCount && first>=obj.Events.NextSampleIndex, ...
                err,'Do not use padding, receiver completion, or a committed-past interval as the TX boundary.');
            assert(native.SampleRateHz==obj.SampleRateHz && ...
                int64(stop-first)*int64(tc)==native.ActiveEndTicksExclusive-native.WaveformStartTicks && ...
                ~any(prepared.PhysicalWaveform(stop-first+1:end,:)~=0,'all'), ...
                err,'Retain exact native CP/useful support; only original zero padding may follow its end.');
            [id,enqueueReceipt]=obj.queueRA(ue,prepared,struct(),true);
            tx="ue_"+ue;
            context=struct('Prepared',prepared,'RAConfig',ra,'ComponentID',id, ...
                'CheckpointSHA256',sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(checkpoint)), ...
                'TransmitterPlane',tx+":tx",'ServingCell',link.Cell, ...
                'ActiveEndSample',stop,'PhysicalConfigurationEpoch',obj.Physical.ConfigurationEpoch, ...
                'EnqueueReceipt',enqueueReceipt);
            registration=struct('ID',id,'UE',ue,'Key',key, ...
                'ContextSHA256',sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(context)));
            obj.Events.observe(tx+":tx",id,first,stop);
            obj.Msg1TXRegistrations{end+1,1}=registration;
            obj.Pending(end+1)=struct('ID',id,'Kind',"Msg1TX",'UE',ue,'Context',context, ...
                'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
        end
        function registration=originalMsg1TransmissionContract(obj,id)
            found=find(cellfun(@(r)r.ID==string(id),obj.Msg1TXRegistrations));
            assert(isscalar(found),'sixgr:truth:Msg1TransmissionContract','Require an original registered Msg1 component.');
            registration=obj.Msg1TXRegistrations{found};
        end
        function validateCompletedMsg1Transmission(obj,receipt)
            found=find(cellfun(@(r)r.ComponentID==receipt.ComponentID,obj.Msg1TXCompletions));
            assert(isscalar(found) && isequaln(receipt,obj.Msg1TXCompletions{found}), ...
                'sixgr:truth:Msg1TransmissionNotCompleted','Require the physical owner''s original committed TX completion.');
        end
        function armRARWindow(obj,ue,ra)
            % Arm from the UE's transmitted occasion/broadcast information,
            % before any gNB detection. Silent gNB samples are still received.
            if obj.hasPending("RAR",ue)
                error('sixgr:truth:DuplicateRARWindow','A UE response window is already armed.');
            end
            link=obj.linkForUE(ue,"DL"); ch=obj.channelState(ue,"DL");
            window=ra.RARMonitoringWindow; fs=obj.SampleRateHz;
            expiry=localTicksSample(window.ExpiryTicksExclusive,fs);
            for slot=reshape(window.MonitoringSlots,1,[])
                start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,0,window.Numerology);
                finish=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot+1,0,window.Numerology);
                clockOffset=sixgr.util.structGet(window,'ClockOffsetTicks',int64(0));
                first=localTicksSample(start.Ticks+clockOffset,fs);
                stop=min(localTicksSample(finish.Ticks+clockOffset,fs)+double(ch.ChannelPadSamples),expiry);
                obj.Serial=obj.Serial+1; id="rar_monitor_"+obj.Serial;
                for plane=["gnb_"+link.Cell+":tx","ue_"+ue+"_rx:pre_rf","ue_"+ue+"_rx:post_rf"]
                    obj.Events.observe(plane,id,first,stop);
                end
                context=struct('AbsoluteSlot',slot,'RunId',ra.RunId,'ExpiryTicks',window.ExpiryTicksExclusive);
                obj.Pending(end+1)=struct('ID',id,'Kind',"RAR",'UE',ue,'Context',context, ...
                    'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            end
            obj.Serial=obj.Serial+1; id="rar_expiry_"+obj.Serial;
            obj.Events.decisionBoundary(id,expiry);
            obj.Decisions(end+1)=struct('ID',id,'Kind',"RARExpiry",'UE',ue, ...
                'Context',struct('RunId',ra.RunId,'ExpiryTicks',window.ExpiryTicksExclusive));
        end
        function armContentionWindow(obj,ue,receiver)
            assert(isa(receiver,'sixgr.phy.ra.Msg4ReceiveWindow'), ...
                'sixgr:truth:ContentionReceiverRequired','Use the independent UE contention receiver.');
            duplicate=any([obj.ContentionWindows.UE]==ue & ...
                string({obj.ContentionWindows.RunId})==string(receiver.RAConfig.RunId));
            assert(~duplicate, ...
                'sixgr:truth:DuplicateContentionWindow','Arm the UE window once from its Msg3 transmission.');
            % A decoded identity mismatch may end the previous attempt
            % before its old observations drain. Those retain their RunId
            % and must not prevent arming a different, causally retried UE
            % attempt. The completion dispatcher ignores retired RunIds.
            link=obj.linkForUE(ue,"DL"); ch=obj.channelState(ue,"DL");
            w=receiver.Window; fs=obj.SampleRateHz;
            obj.ContentionWindows(end+1)=struct('UE',ue,'RunId',receiver.RAConfig.RunId, ...
                'StartTicks',w.StartTicks);
            for slot=reshape(w.MonitoringSlots,1,[])
                first=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,0,w.Numerology);
                last=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot+1,0,w.Numerology);
                a=localTicksSample(first.Ticks+w.ClockOffsetTicks,fs);
                b=min(localTicksSample(last.Ticks+w.ClockOffsetTicks,fs)+double(ch.ChannelPadSamples), ...
                    localTicksSample(w.ExpiryTicksExclusive,fs));
                obj.Serial=obj.Serial+1; id="contention_monitor_"+obj.Serial;
                for plane=["gnb_"+link.Cell+":tx","ue_"+ue+"_rx:pre_rf","ue_"+ue+"_rx:post_rf"]
                    obj.Events.observe(plane,id,a,b);
                end
                context=struct('RunId',receiver.RAConfig.RunId,'AbsoluteSlot',slot);
                obj.Pending(end+1)=struct('ID',id,'Kind',"Contention",'UE',ue,'Context',context, ...
                    'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            end
            for kind=["ContentionStart","ContentionExpiry"]
                ticks=w.StartTicks;
                if kind=="ContentionExpiry", ticks=w.ExpiryTicksExclusive; end
                obj.Serial=obj.Serial+1; id=lower(kind)+"_"+obj.Serial;
                obj.Events.decisionBoundary(id,localTicksSample(ticks,fs));
                obj.Decisions(end+1)=struct('ID',id,'Kind',kind,'UE',ue, ...
                    'Context',struct('RunId',receiver.RAConfig.RunId,'EventTicks',ticks));
            end
        end
        function queueUplinkControl(obj,ue,prepared,context)
            assert(isa(prepared,'sixgr.link.PreparedUplinkControlTransmission') && ...
                prepared.SampleRateHz==obj.SampleRateHz && prepared.PhysicalTiming.WaveformTimingApplied, ...
                'sixgr:truth:SharedULControlPreparationAuthority', ...
                'Shared UL needs a typed preparation with received clock/TA authority.');
            armed=[];
            if isfield(context,'ObservationID')
                armed=find(string({obj.Pending.ID})==string(context.ObservationID));
                assert(isscalar(armed) && obj.Pending(armed).UE==ue && ...
                    obj.Pending(armed).Kind=="PUCCH" && obj.Pending(armed).Context.AwaitingPreparation, ...
                    'sixgr:truth:SharedPUCCHObservationOwnership','Bind encoding to its previously armed physical observation exactly once.');
            else
                assert(~obj.hasPending(prepared.Channel,ue), ...
                    'sixgr:truth:DuplicatePendingULControl','Receive the prior UE control observation first.');
            end
            link=obj.linkForUE(ue,"UL");
            if prepared.Channel=="SRS"
                % The SRS completion context owns a frozen association.
                % Reject it before mapping/enqueue, never infer a cell at RX.
                assert(isstruct(context)&&isscalar(context)&&isfield(context,'ServingCell')&& ...
                    isnumeric(context.ServingCell)&&isreal(context.ServingCell)&& ...
                    isscalar(context.ServingCell)&&isfinite(context.ServingCell)&& ...
                    context.ServingCell>=1&&context.ServingCell==fix(context.ServingCell)&& ...
                    context.ServingCell==link.Cell, ...
                    'sixgr:truth:SharedSRSCellContext', ...
                    'SRS requires the original positive-integer ServingCell matching the installed UL link before enqueue.');
            end
            tx="ue_"+ue; rx="gnb_"+link.Cell+"_rx";
            array=sixgr.rf.AntennaArrayFactory.build(prepared.ReceiverConfig,'ue', ...
                'signal',lower(prepared.Channel),'numPorts',size(prepared.Tx.Waveform,2));
            samples=prepared.Tx.Waveform*cast(array.PortToElementMatrix.','like',prepared.Tx.Waveform);
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(size(samples,2)==node.NumAntennas, ...
                'sixgr:truth:SharedULControlAntennaLayout','Prepared ports must map to the actual physical UE radio.');
            active=find(any(samples~=0,2),1,'first');
            assert(~isempty(active),'sixgr:truth:EmptySharedULControl','A scheduled SRS/PUCCH must contain actual transmit energy.');
            if isempty(armed)
                id=lower(prepared.Channel)+"_observation_"+(obj.Serial+1);
            else
                id=obj.Pending(armed).ID;
            end
            if prepared.Channel=="PUCCH"
                identity=sixgr.truth.preparedPUCCHTransmissionIdentity(prepared,ue,id);
                assignment=prepared.RequestBinding.Assignment;
                c=prepared.Tx.Carrier;
                obj.CommonRAReservations.assertPUCCHDisjoint(link.Cell,assignment.DueSlot-1,c,assignment.Resource);
                assert(identity.RFConfigurationEpoch==obj.Physical.ConfigurationEpoch, ...
                    'sixgr:truth:SharedPUCCHTXIdentityMismatch','The preparation must use the physical owner epoch.');
            end
            if isempty(armed)
                obj.Serial=obj.Serial+1;
                chunk=sixgr.phy.waveform.WaveformChunk(samples,prepared.StartSample);
                obj.Events.enqueue(tx,id,chunk);
                if prepared.Channel=="SRS"
                    % Original emitted component identity, before composition/RF.
                    % A later permitted power replacement updates this from its
                    % actual replacement receipt, never from desired-link IQ.
                    context.SRSComponentBinding=struct( ...
                        'ContractVersion',"sixgr.truth.emitted_SRS_component/v1", ...
                        'ComponentID',id,'ComponentSHA256',chunk.SHA256, ...
                        'TransmitterID',tx,'UE',ue,'StartSample',chunk.StartSample, ...
                        'EndSampleExclusive',chunk.EndSample+1,'SampleRateHz',obj.SampleRateHz, ...
                        'ConfigurationEpoch',obj.Physical.ConfigurationEpoch);
                end
            else
                id=obj.Pending(armed).ID; plan=obj.Pending(armed).Context;
                appliedTiming=plan.PhysicalTiming;
                appliedTiming.WaveformTimingApplied=true;
                assert(isequaln(appliedTiming,prepared.PhysicalTiming) && ...
                    prepared.EndSampleExclusive==plan.TXEndSampleExclusive, ...
                    'sixgr:truth:SharedPUCCHClockChanged','Received timing authority cannot change after capture registration.');
                consumed=obj.Events.NextSampleIndex-prepared.StartSample;
                assert(consumed>=0 && consumed<size(samples,1) && ...
                    ~any(samples(1:consumed,:)~=0,'all'), ...
                    'sixgr:truth:LateSharedPUCCHEncoding','Never discard or rewrite any nonzero sample before encoding became available.');
                % Only an exactly zero contribution prefix has already passed.
                % Its actual node TX/RX samples were captured, including RF,
                % noise and any other contributors. No receive padding/replay.
                obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk( ...
                    samples(consumed+1:end,:),obj.Events.NextSampleIndex));
            end
            boundary=id+"_ul_start";
            obj.Events.decisionBoundary(boundary,prepared.StartSample+active-1);
            obj.Decisions(end+1)=struct('ID',boundary,'Kind',"ULTransmitBoundary", ...
                'UE',ue,'Context',struct());
            if prepared.Channel=="SRS" && string(sixgr.util.structGet( ...
                    prepared.Metadata,'PowerEvidence.AdjustmentState',''))=="same_as_pusch"
                boundary=id+"_power_binding";
                resourceStart=sixgr.link.srsResourceStartSample( ...
                    prepared.Tx,prepared.StartSample,prepared.SampleRateHz);
                obj.Events.decisionBoundary(boundary,resourceStart);
                obj.Decisions(end+1)=struct('ID',boundary,'Kind',"BindSRSPower", ...
                    'UE',ue,'Context',struct('ObservationID',id));
            end
            if prepared.Channel=="PUCCH"
                txContext=struct('Prepared',prepared,'TransmissionIdentity',identity, ...
                    'FirstActiveSample',prepared.StartSample+active-1, ...
                    'WaveformToElementMatrix',cast(array.PortToElementMatrix,'like',prepared.Tx.Waveform));
                occupancyIdentity=struct('Channel',"PUCCH",'TransmissionID',identity.TransmissionID, ...
                    'ObservationID',id,'UEIndex',ue,'RNTI',identity.RNTI,'ServingCell',link.Cell, ...
                    'TransmitterID',tx,'ClockDomain',"shared_physical_sample_clock/v1", ...
                    'ClockEpoch',obj.Physical.ConfigurationEpoch);
                txContext.TransmitOccupancy=sixgr.truth.captureTransmitOccupancy( ...
                    samples,prepared.StartSample,obj.SampleRateHz,occupancyIdentity);
                % The pre-sample boundary above only switches the RF link.
                % Commit after one active sample has actually been consumed.
                boundary=id+"_tx_committed";
                obj.Events.decisionBoundary(boundary,txContext.FirstActiveSample+1);
                obj.Decisions(end+1)=struct('ID',boundary,'Kind',"PUCCHTX", ...
                    'UE',ue,'Context',txContext);
            end
            if isempty(armed)
                obj.Events.observe(tx+":tx",id,prepared.StartSample,prepared.EndSampleExclusive);
            end
            ch=obj.channelState(ue,"UL");
            if isempty(armed)
                for plane=[rx+":pre_rf",rx+":post_rf"]
                    obj.Events.observe(plane,id,prepared.ReceiveStartSample, ...
                        prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
                end
            end
            if prepared.Channel=="SRS"
                context.DesiredReferencePlane=obj.Physical.registerLinkScoringPlane(obj.Events,link.ID,rx);
                obj.Events.observe(context.DesiredReferencePlane,id,prepared.ReceiveStartSample, ...
                    prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
                % Retain coefficients from the same physical execution and
                % receive window for SRS measurement qualification. These
                % references are audit evidence, never receiver estimates.
                obj.Physical.requestLinkChannelReference(obj.Events,link.ID,rx, ...
                    prepared.ReceiveStartSample, ...
                    prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
            end
            context.Prepared=prepared;
            if isempty(armed)
                obj.Pending(end+1)=struct('ID',id,'Kind',prepared.Channel,'UE',ue, ...
                    'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            else
                context.AwaitingPreparation=false;
                obj.Pending(armed).Context=context;
            end
            obj.resolvePreparedSRSPUCCHPriority(ue);
        end
        function bindSRSPower(obj,ue,id,owner)
            hit=find(string({obj.Pending.ID})==string(id));
            assert(isscalar(hit) && obj.Pending(hit).UE==ue, ...
                'sixgr:truth:SRSPowerObservationMismatch','Bind exactly the pending UE SRS observation.');
            if obj.Pending(hit).Kind=="SuppressedSRSObservation", return; end
            assert(obj.Pending(hit).Kind=="SRS",'sixgr:truth:SRSPowerObservationMismatch','SRS power cannot modify another channel.');
            context=obj.Pending(hit).Context;
            [prepared,~]=context.Prepared.bindSRSPowerAtEmission(owner,obj.Events.NextSampleIndex);
            array=sixgr.rf.AntennaArrayFactory.build(prepared.ReceiverConfig,'ue', ...
                'signal','srs','numPorts',size(prepared.Tx.Waveform,2));
            samples=prepared.Tx.Waveform*cast(array.PortToElementMatrix.','like',prepared.Tx.Waveform);
            chunk=sixgr.phy.waveform.WaveformChunk(samples,prepared.StartSample);
            receipt=obj.Events.replaceUnemittedComponent("ue_"+ue,id,chunk);
            assert(isfield(context,'SRSComponentBinding') && ...
                context.SRSComponentBinding.ComponentSHA256==receipt.OriginalSampleSHA256 && ...
                chunk.SHA256==receipt.ReplacementSampleSHA256 && ...
                ~receipt.PreviouslyConsumedSamplesChanged, ...
                'sixgr:truth:SRSComponentReplacementIdentity', ...
                'Bind the original SRS component to this permitted actual replacement.');
            context.SRSComponentBinding.ComponentSHA256=receipt.ReplacementSampleSHA256;
            context.SRSComponentBinding.PowerReplacementReceipt=receipt;
            context.Prepared=prepared; context.Config=prepared.InputConfig;
            context.PowerBindingReceipt=receipt;
            obj.Pending(hit).Context=context;
        end

        function resolvePreparedSRSPUCCHPriority(obj,ue)
            % Do this only after actual UE encoding. A gNB receive-only
            % PUCCH window (e.g. missed DCI) must not suppress a UE's SRS.
            srsIndices=find(string({obj.Pending.Kind})=="SRS" & [obj.Pending.UE]==ue);
            pucchIndices=find(string({obj.Pending.Kind})=="PUCCH" & [obj.Pending.UE]==ue);
            for si=srsIndices
                for pi=pucchIndices
                    if ~isfield(obj.Pending(pi).Context,'Prepared'), continue; end
                    s=obj.Pending(si); p=obj.Pending(pi);
                    decision=sixgr.phy.frame.resolvePreparedSRSPUCCHPriority( ...
                        s.Context.Prepared,p.Context.Prepared);
                    if ~decision.Collision, continue; end
                    assert(isempty(decision.RetainedSymbols0Based), ...
                        'sixgr:truth:PartialSRSSymbolSuppressionRequired', ...
                        'Do not cancel a whole SRS resource when some symbols must still transmit.');
                    receipt=obj.Events.cancelUnemittedComponent("ue_"+ue,s.ID);
                    proof=struct('SRSObservationID',s.ID,'PUCCHObservationID',p.ID, ...
                        'UE',ue,'Decision',decision,'Cancellation',receipt);
                    obj.SRSSuppressionLedger(end+1)=proof;
                    obj.Pending(si).Context.SuppressionProof=proof;
                    obj.Pending(si).Kind="SuppressedSRSObservation";
                    % Keep its registered physical observation windows. They
                    % still capture real noise/other signals, not a decoded SRS.
                    break;
                end
            end
        end
        function id=queuePDCCH(obj,ue,prepared,context)
            % Both DL assignments and UL grants use the same DL radio/RE
            % pool. A queued waveform is NOT a received DCI or a data grant.
            link=obj.linkForUE(ue,"DL");
            unit=sixgr.rf.appliedWaveformAmplitudeUnit( ...
                prepared.ReceiverConfig,prepared.PowerContext);
            assert(isstruct(prepared) && isscalar(prepared) && ...
                prepared.ExecutionStage=="pdcch_waveform_prepared_not_received" && ...
                prepared.SampleDomain=="physical_antenna_"+unit+"_before_shared_tx_rf" && ...
                prepared.RFExecutionDeferred && prepared.ChannelExecutionDeferred && ...
                ~prepared.PowerExecutionDeferred && prepared.SampleRateHz==obj.SampleRateHz, ...
                'sixgr:truth:SharedPDCCHPreparationAuthority', ...
                'Queue actual power-scaled physical-port PDCCH IQ before RF execution.');
            first=prepared.RuntimeStartSample;
            validateattributes(first,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(first>=obj.Events.NextSampleIndex, ...
                'sixgr:truth:LatePDCCHPreparation','Cannot enqueue a DCI into already received samples.');
            carrier=prepared.Tx.Carrier;
            slot0=sixgr.util.structGet(prepared.ReceiverConfig,'lls6g.runtime.AbsoluteSlotIndex0',NaN);
            validateattributes(slot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(first==sixgr.phy.frame.slotStartSample(carrier,slot0,obj.SampleRateHz), ...
                'sixgr:truth:PDCCHSharedSlotMismatch','Frozen control slot and sample origin must agree.');
            [allowed,~,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition( ...
                prepared.ReceiverConfig,slot0+1);
            symbols=prepared.ReceiveExtent.MonitoredSymbols0Based;
            dl=partition.DLSymbolAllocation;
            assert(allowed && all(symbols>=dl(1) & symbols<sum(dl)), ...
                'sixgr:truth:PDCCHOutsideDLSymbols','All monitored PDCCH symbols require DL authority.');
            tx="gnb_"+link.Cell; rx="ue_"+ue+"_rx";
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            samples=prepared.TransmitSamples;
            assert(size(samples,2)==node.NumAntennas && size(samples,1)==prepared.NumSamples && ...
                all(isfinite(samples),'all') && any(samples~=0,'all'), ...
                'sixgr:truth:SharedPDCCHAntennaLayout','Retain the complete nonempty physical radio contribution.');
            [ledger,occupied]=sixgr.truth.PDCCHSlotResourceLedger.lookup( ...
                obj.PDCCHResourceLedger,slot0+1,link.Cell,carrier);
            occupied=unique([occupied;sixgr.truth.commonPDCCHReservations( ...
                struct('SharedWaveformStream',obj),prepared.ReceiverConfig,slot0,link.Cell,carrier)],'rows');
            allocated=prepared.TxInfo.AllocatedRECoordinates;
            assert(isempty(intersect(occupied,allocated,'rows')), ...
                'sixgr:truth:SharedPDCCHResourceCollision', ...
                'DL and UL DCI cannot occupy the same physical control REs.');
            ledger=sixgr.truth.PDCCHSlotResourceLedger.reserve( ...
                ledger,slot0+1,link.Cell,carrier,allocated);
            % Use the configured receiver search margin and actual filter
            % memory. All tail samples are consumed on the shared clock;
            % there is no appended RX padding or full-slot wait for DCI.
            [margin,marginSource]=sixgr.phy.sync.resolveTimingSearchGuard( ...
                prepared.ReceiverConfig,obj.SampleRateHz);
            assert(startsWith(marginSource,"configured_receiver_timing_uncertainty"), ...
                'sixgr:truth:PDCCHTimingSearchAuthorityRequired', ...
                'Resolve the declared uncertainty in samples or microseconds; do not assume an exact clock.');
            ch=obj.channelState(ue,"DL");
            receiveFirst=first;
            reference=sixgr.util.structGet(context,'ReceivedDLTimingReference',struct());
            if ~isempty(fieldnames(reference))
                alignment=sixgr.phy.frame.pdcchReceivedClockAlignment( ...
                    reference,carrier,first,obj.SampleRateHz,ch.ChannelTrimSamples);
                receiveFirst=alignment.ReceiveStartSample;
                assert(receiveFirst>=obj.Events.NextSampleIndex, ...
                    'sixgr:truth:LatePDCCHObservation','The measured UE receive clock precedes the retained stream.');
                prepared.ReceivedTimingAlignment=alignment;
                stop=receiveFirst+prepared.MinimumReceiveSamples;
            else
                assert(~logical(sixgr.util.structGet(prepared.ReceiverConfig,'phy.pdcch.blindSearch',false)), ...
                    'sixgr:truth:SharedPDCCHTimingReferenceRequired', ...
                    'Blind PDCCH on the shared stream requires a previously received DL clock, not silent zero timing.');
                stop=first+prepared.MinimumReceiveSamples+double(ch.ChannelPadSamples)+double(margin);
            end
            binding=sixgr.truth.scheduledPDCCHGrantBinding(prepared,context,ue);
            if isfield(context,'ScheduledULHARQConfig')
                assert(~isempty(fieldnames(binding)) && string(binding.Grant.Direction)=="UL" && ...
                    sixgr.phy.frame.resolveDuplexMode(context.ScheduledULHARQConfig)=="TDD", ...
                    'sixgr:truth:ScheduledULHARQCommandContext', ...
                    'The shared UL scheduling lifecycle requires an explicit TDD UL command.');
            end
            if ~isempty(fieldnames(binding))
                assert(~any(cellfun(@(r)r.Binding.GrantContextID==binding.GrantContextID, ...
                    obj.ScheduledControlRegistrations)), ...
                    'sixgr:truth:DuplicateScheduledPDCCHGrant','One frozen grant cannot be registered as two control transmissions.');
            end
            obj.Serial=obj.Serial+1; id="pdcch_observation_"+obj.Serial;
            obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,first));
            % Retain the transmitted control prefix on the transmitter
            % clock. A received SS/PBCH phase must never shift TX evidence.
            % This is the monitored prefix, not a full-slot IQ export; the
            % complete generated waveform remains queued above.
            prepared.TransmitObservationStartSample=first;
            prepared.TransmitObservationEndSampleExclusive=first+prepared.MinimumReceiveSamples;
            if ~isempty(fieldnames(binding))
                obj.ScheduledControlRegistrations{end+1,1}=struct('ObservationID',id, ...
                    'Binding',binding,'TransmitterID',tx+":tx", ...
                    'StartSample',first,'EndSampleExclusive',prepared.TransmitObservationEndSampleExclusive, ...
                    'TransmitObservation',[],'AvailableAtSample',NaN);
            end
            obj.Events.observe(tx+":tx",id,first,prepared.TransmitObservationEndSampleExclusive);
            for plane=[rx+":pre_rf",rx+":post_rf"]
                obj.Events.observe(plane,id,receiveFirst,stop);
            end
            % Independent scoring only: retain the actually executed serving
            % contribution, including prehistory before the shifted RX clock.
            % Do not run the channel twice or feed this plane to the decoder.
            context.DesiredReferencePlane=obj.Physical.registerLinkScoringPlane(obj.Events,link.ID,rx);
            obj.Events.observe(context.DesiredReferencePlane,id,min(first,receiveFirst),stop);
            obj.PDCCHResourceLedger=ledger;
            context.Prepared=prepared;
            obj.Pending(end+1)=struct('ID',id,'Kind',"PDCCH",'UE',ue, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
        end
        function id=queueData(obj,ue,prepared,context)
            % A complete frozen PDSCH/PUSCH contribution, not a link replay.
            % DL can be prepared before DCI reception; UL preparation has
            % already required a decoded grant. Receiver authorization and
            % HARQ commits remain the coordinator's receive-time decisions.
            assert(isa(prepared,'sixgr.link.PreparedDataTransmission') && ...
                prepared.SampleRateHz==obj.SampleRateHz, ...
                'sixgr:truth:SharedDataPreparationAuthority', ...
                'Shared data requires retained coded TX on the physical sample clock.');
            direction=prepared.Direction;
            if direction=="UL"
                assert(prepared.PhysicalTiming.WaveformTimingApplied, ...
                    'sixgr:truth:SharedDataReceivedULTimingRequired', ...
                    'An aligned component fixture is not received UE timing authority.');
            end
            assert(min(prepared.StartSample,prepared.ReceiveStartSample)>=obj.Events.NextSampleIndex, ...
                'sixgr:truth:LateSharedDataPreparation', ...
                'Register complete TX and RX intervals before either origin is consumed.');
            link=obj.linkForUE(ue,direction);
            tx="gnb_"+link.Cell; rx="ue_"+ue+"_rx"; role="bs"; family="PDSCH";
            if direction=="UL"
                tx="ue_"+ue; rx="gnb_"+link.Cell+"_rx"; role="ue"; family="PUSCH";
            end
            identity=sixgr.truth.preparedDataTransmissionIdentity(prepared,ue);
            dataSlot=sixgr.util.structGet(prepared.ReceiverConfig,'lls6g.runtime.AbsoluteSlotIndex0',NaN);
            coordinates=sixgr.truth.CommonRAResourceCalendar.transmissionRectangle(prepared.Tx,direction);
            reserved=obj.commonRAResources(link.Cell,dataSlot,direction,prepared.Tx.Carrier);
            assert(isempty(intersect(reserved,coordinates,'rows')), ...
                'sixgr:truth:SharedDataCommonRACollision', ...
                'A frozen connected grant cannot overwrite Msg2/Msg3/Msg4/SRB1 resources.');
            assert(~any(string({obj.PUSCHReceiveOnlyRegistrations.GrantContextID})==identity.PHYGrantContextId), ...
                'sixgr:truth:ConflictingPUSCHReceiveOnlyTransmission', ...
                'A receive-only grant cannot subsequently acquire a UE transmission.');
            pending=obj.Pending(string({obj.Pending.Kind})==family & [obj.Pending.UE]==ue);
            duplicate=any(arrayfun(@(x) ...
                x.Context.TransmissionIdentity.TransmissionID==identity.TransmissionID,pending));
            assert(~duplicate, ...
                'sixgr:truth:DuplicatePendingData', ...
                'The same immutable data transmission cannot be queued twice.');
            % The frozen transmitter can emit either logical NR ports or
            % already-precoded physical element IQ.  Never infer that
            % domain from the column count: a 64-element hybrid PDSCH has
            % 64 waveform columns but only four logical ports.  Treating
            % those columns as 64 ports applies the RF map twice and also
            % makes a valid 64x4 frozen matrix look dimensionally invalid.
            [samples,projection,mappingEvidence]= ...
                sixgr.truth.mapDataWaveformToPhysicalElements( ...
                prepared.Tx.Waveform,prepared.ReceiverConfig, ...
                prepared.RequestBinding.PHYGrant,role,lower(family));
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(size(samples,2)==node.NumAntennas && ...
                size(samples,2)==prepared.NumPhysicalTransmitAntennas && ...
                all(isfinite(samples),'all') && any(samples~=0,'all'), ...
                'sixgr:truth:SharedDataAntennaLayout', ...
                'Coded logical ports must map to the frozen physical radio without changing power.');
            sixgr.rf.appliedWaveformAmplitudeUnit( ...
                prepared.ReceiverConfig,prepared.Tx.PowerContext);
            ch=obj.directionalChannelState(ue,direction);
            obj.Serial=obj.Serial+1; id=lower(family)+"_observation_"+obj.Serial;
            obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,prepared.StartSample));
            active=find(any(samples~=0,2),1,'first');
            firstActive=prepared.StartSample+active-1;
            if direction=="UL"
                boundary=id+"_ul_start";
                obj.Events.decisionBoundary(boundary,firstActive);
                obj.Decisions(end+1)=struct('ID',boundary,'Kind',"ULTransmitBoundary", ...
                    'UE',ue,'Context',struct());
            end
            % Report a TX start only AFTER the physical owner consumed an
            % active contribution sample. Merely preparing/enqueueing IQ
            % must not count a transmitted TB or advance HARQ state.
            context.TransmissionIdentity=identity;
            context.TransmitOccupancy=struct();
            if direction=="UL"
                occupancyIdentity=struct('Channel',"PUSCH",'TransmissionID',identity.TransmissionID, ...
                    'ObservationID',id,'UEIndex',ue,'RNTI',identity.RNTI,'ServingCell',link.Cell, ...
                    'TransmitterID',tx,'ClockDomain',"shared_physical_sample_clock/v1", ...
                    'ClockEpoch',obj.Physical.ConfigurationEpoch);
                context.TransmitOccupancy=sixgr.truth.captureTransmitOccupancy( ...
                    samples,prepared.StartSample,obj.SampleRateHz,occupancyIdentity);
            end
            % Retain the exact applied mapping, including its execution
            % precision. Rebuilding an array later is not applied evidence.
            context.WaveformToElementMatrix=projection;
            context.WaveformToElementMappingEvidence=mappingEvidence;
            context.FirstActiveSample=firstActive;
            context.Prepared=prepared;
            boundary=id+"_tx_committed";
            obj.Events.decisionBoundary(boundary,firstActive+1);
            obj.Decisions(end+1)=struct('ID',boundary,'Kind',"DataTX", ...
                'UE',ue,'Context',context);
            % Observe the already executed serving-link contribution for
            % independent sample-domain power accounting. Never pass this
            % noiseless plane to channel estimation or decoding.
            context.DesiredReferencePlane=obj.Physical.registerLinkScoringPlane(obj.Events,link.ID,rx);
            receiveObservationStop=prepared.ReceiveEndSampleExclusive+ ...
                double(ch.ChannelPadSamples);
            obj.Events.observe(context.DesiredReferencePlane,id, ...
                prepared.ReceiveStartSample,receiveObservationStop);
            % Capture the coefficients from this same channel execution and
            % exact observation interval.  Merely registering the scoring
            % plane retains noiseless desired-link samples but cannot prove
            % the per-sample fading/channel-estimation reference used by
            % scientific validation.
            obj.Physical.requestLinkChannelReference(obj.Events,link.ID,rx, ...
                prepared.ReceiveStartSample,receiveObservationStop);
            obj.Events.observe(tx+":tx",id,prepared.StartSample,prepared.EndSampleExclusive);
            for plane=[rx+":pre_rf",rx+":post_rf"]
                obj.Events.observe(plane,id,prepared.ReceiveStartSample, ...
                    prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
            end
            context.Prepared=prepared;
            context.ReceiveEndSampleExclusive=prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples);
            obj.Pending(end+1)=struct('ID',id,'Kind',family,'UE',ue, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
        end
        function id=queuePUSCHReceiveOnly(obj,ue,cfg,grant,first,stop)
            % Physical capture only. Scheduling supplies the gNB window;
            % this does not establish failed DCI, decode bits, or apply HARQ.
            % No UE preparation, timing advance, IQ, power or TB is consumed.
            validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
            validateattributes(first,{'numeric'},{'scalar','real','finite','integer','>=',obj.Events.NextSampleIndex});
            validateattributes(stop,{'numeric'},{'scalar','real','finite','integer','>',first});
            sixgr.phy.grant.assertGrantTimingIdentity(grant,'UL');
            sixgr.phy.grant.assertPHYGrantDimensions(grant.PHYGrant,'pusch_receive_only_registration');
            assert(grant.UEIndex==ue && grant.RNTI==cfg.phy.pusch.RNTI, ...
                'sixgr:truth:PUSCHReceiveOnlyIdentityMismatch','Use the scheduled UE and installed RNTI.');
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            info=nrOFDMInfo(carrier);
            slot0=grant.TimingDecision.DataAbsoluteSlot;
            nominal=sixgr.phy.frame.slotStartSample(carrier,slot0,obj.SampleRateHz);
            nominalStop=sixgr.phy.frame.slotStartSample(carrier,slot0+1,obj.SampleRateHz);
            assert(double(info.SampleRate)==obj.SampleRateHz && first<=nominal && stop>=nominalStop, ...
                'sixgr:truth:IncompleteScheduledPUSCHWindow', ...
                'The gNB window must contain the scheduled slot on the physical clock; no padding is created.');
            [~,~,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot0+1);
            symbols=grant.SymbolAllocation(1)+(0:grant.SymbolAllocation(2)-1);
            ul=partition.ULSymbolAllocation;
            assert(~isempty(symbols) && all(symbols>=ul(1) & symbols<sum(ul)), ...
                'sixgr:truth:ScheduledPUSCHOutsideUL','The scheduled allocation must occupy actual UL symbols.');
            grantID=string(grant.PHYGrant.GrantContextId);
            assert(isscalar(grantID) && ~ismissing(grantID) && strlength(grantID)>0, ...
                'sixgr:truth:PUSCHReceiveOnlyIdentityMismatch','Retain a nonempty frozen grant identity.');
            assert(~any(string({obj.PUSCHReceiveOnlyRegistrations.GrantContextID})==grantID), ...
                'sixgr:truth:DuplicatePUSCHReceiveOnlyObservation','One scheduled grant has one receive-only registration.');
            pending=obj.Pending(string({obj.Pending.Kind})=="PUSCH");
            transmitted=obj.DataTransmissions;
            assert(~any(arrayfun(@(x)x.Context.TransmissionIdentity.PHYGrantContextId==grantID,pending)) && ...
                ~any(arrayfun(@(x)x.Identity.PHYGrantContextId==grantID,transmitted)), ...
                'sixgr:truth:ConflictingPUSCHReceiveOnlyTransmission', ...
                'An already prepared or executed UE transmission is not receive-only.');
            link=obj.linkForUE(ue,"UL");
            obj.Serial=obj.Serial+1; id="pusch_receive_only_"+obj.Serial;
            for plane=["gnb_"+link.Cell+"_rx:pre_rf","gnb_"+link.Cell+"_rx:post_rf"]
                obj.Events.observe(plane,id,first,stop);
            end
            context=struct('Grant',grant,'Config',cfg,'ObservationID',id, ...
                'Source',"scheduled_gnb_capture_without_UE_transmission", ...
                'ReceiveEndSampleExclusive',stop);
            obj.Pending(end+1)=struct('ID',id,'Kind',"PUSCHReceiveOnly",'UE',ue, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            obj.PUSCHReceiveOnlyRegistrations(end+1)=struct('ID',id,'UE',ue, ...
                'GrantContextID',grantID,'StartSample',first,'EndSampleExclusive',stop);
        end
        function item=readPUSCHReceiveOnlyCompletion(obj,id)
            id=string(id);
            assert(isscalar(id) && ~ismissing(id) && strlength(id)>0, ...
                'sixgr:truth:InvalidPUSCHReceiveOnlyObservationID','Use one retained receive-only observation identity.');
            hits=find(cellfun(@(x)x.Context.ObservationID==id,obj.PUSCHReceiveOnlyCompletions));
            if isempty(hits)
                archived=find(cellfun(@(x)x.ObservationID==id,obj.PUSCHReceiveOnlyArchives));
                if isscalar(archived)
                    item=sixgr.truth.SharedReceiveOnlyEvidence.read(obj.PUSCHReceiveOnlyArchives{archived},"Item");
                    return;
                end
            end
            assert(isscalar(hits),'sixgr:truth:PUSCHReceiveOnlyObservationNotCompleted', ...
                'Only this physical owner''s completed observation can enter the receiver.');
            item=obj.PUSCHReceiveOnlyCompletions{hits};
        end
        function receipt=archivePUSCHReceiveOnlyCompletion(obj,id,root,result)
            id=string(id);
            assert(~any(cellfun(@(x)x.ObservationID==id,obj.PUSCHReceiveOnlyArchives)), ...
                'sixgr:truth:ReceiveOnlyAlreadyArchived','A completed observation is archived once.');
            hit=find(cellfun(@(x)x.Context.ObservationID==id,obj.PUSCHReceiveOnlyCompletions));
            assert(isscalar(hit),'sixgr:truth:PUSCHReceiveOnlyObservationNotCompleted', ...
                'Only the physical owner can retire its completed capture.');
            receipt=sixgr.truth.SharedReceiveOnlyEvidence.write(root,obj.PUSCHReceiveOnlyCompletions{hit},result);
            % Publish the verified durable owner before releasing any raw
            % capture. Disk/validation failure leaves the original intact.
            obj.PUSCHReceiveOnlyArchives{end+1,1}=receipt;
            % Delete a row, preserving the N-by-1 queue shape. Linear
            % deletion of the only cell leaves 1-by-0; the next {end+1,1}
            % append would then create an empty phantom completion.
            obj.PUSCHReceiveOnlyCompletions(hit,:)=[];
        end
        function evidence=receiveOnlyEvidenceStorage(obj)
            evidence=struct('InMemoryCompletionCount',numel(obj.PUSCHReceiveOnlyCompletions), ...
                'ArchivedCompletionCount',numel(obj.PUSCHReceiveOnlyArchives), ...
                'ArchiveBytes',sum(cellfun(@(r)r.EvidenceBytes,obj.PUSCHReceiveOnlyArchives)));
        end
        function controls=readTransmittedSchedulingControls(obj)
            % Read-only gNB scheduling authority for pre-DCI joint planning.
            % Do not expose queued commands as transmitted constraints or
            % borrow UE decoding/ACK state to fill a missing TX observation.
            controls=obj.ScheduledControlRegistrations;
            for k=1:numel(controls)
                r=controls{k}; observation=r.TransmitObservation;
                assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && ...
                    observation.isComplete() && observation.SampleRateHz==obj.SampleRateHz && ...
                    observation.StartSample==r.StartSample && ...
                    observation.EndSampleExclusive==r.EndSampleExclusive && ...
                    r.AvailableAtSample==r.EndSampleExclusive && r.AvailableAtSample<=obj.Events.NextSampleIndex, ...
                    'sixgr:truth:JointTimingAfterControlEnqueue', ...
                    'Joint planning must precede current DCI enqueue; prior commands need complete physical gNB TX evidence.');
            end
        end
        function controls=readTransmittedULControls(obj,ue,targetSlot)
            % Independent gNB schedule: no UE accepted-command, pending UCI,
            % transmitted PUSCH payload or ACK state participates.
            validateattributes(ue,{'numeric'},{'scalar','integer','positive','finite'});
            validateattributes(targetSlot,{'numeric'},{'scalar','integer','positive','finite'});
            assert(any([obj.Links.UE]==ue),'sixgr:truth:ScheduledULControlUEUnknown','Require a configured physical UE.');
            registered=obj.ScheduledControlRegistrations;
            ul=registered(cellfun(@(r)r.Binding.Direction=="UL" && r.Binding.UEIndex==ue,registered));
            ids=string(cellfun(@(r)r.Binding.GrantContextID,ul,'UniformOutput',false));
            % Missing control provenance cannot masquerade as an empty UL
            % occasion merely because an execution/receive record survived.
            actual=obj.DataTransmissions;
            actual=actual(arrayfun(@(r)r.Identity.Direction=="UL" && r.Identity.UEIndex==ue,actual));
            for tx=reshape(actual,1,[])
                assert(any(ids==tx.Identity.PHYGrantContextId), ...
                    'sixgr:truth:MissingScheduledULControlLedger','Every actual ordinary UL attempt needs its retained gNB command.');
            end
            pending=obj.Pending(string({obj.Pending.Kind})=="PUSCH" & [obj.Pending.UE]==ue);
            for p=reshape(pending,1,[])
                assert(any(ids==p.Context.TransmissionIdentity.PHYGrantContextId), ...
                    'sixgr:truth:MissingScheduledULControlLedger','A prepared ordinary PUSCH cannot lose its scheduled control.');
            end
            captures=obj.PUSCHReceiveOnlyRegistrations;
            for capture=reshape(captures([captures.UE]==ue),1,[])
                assert(any(ids==capture.GrantContextID), ...
                    'sixgr:truth:MissingScheduledULControlLedger','Receive-only ordinary UL also requires its real scheduled command.');
            end
            controls=cell(0,1);
            for k=1:numel(ul)
                r=ul{k}; g=r.Binding.Grant;
                if double(g.TimingDecision.DataAbsoluteSlot)+1~=targetSlot, continue; end
                observation=r.TransmitObservation;
                assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && observation.isComplete() && ...
                    observation.SampleRateHz==obj.SampleRateHz && observation.StartSample==r.StartSample && ...
                    observation.EndSampleExclusive==r.EndSampleExclusive && ...
                    r.AvailableAtSample==r.EndSampleExclusive && r.AvailableAtSample<=obj.Events.NextSampleIndex, ...
                    'sixgr:truth:ScheduledULControlNotTransmitted', ...
                    'A queued or incomplete control is not a physically transmitted UL command.');
                controls{end+1,1}=r; %#ok<AGROW>
            end
        end
        function queueULDataPreparation(obj,ue,first,context)
            validateattributes(first,{'numeric'},{'scalar','real','finite','integer','>=',obj.Events.NextSampleIndex});
            obj.Serial=obj.Serial+1; id="ul_data_preparation_"+obj.Serial;
            obj.Events.decisionBoundary(id,first);
            obj.Decisions(end+1)=struct('ID',id,'Kind',"PrepareULData", ...
                'UE',ue,'Context',context);
        end
        function queuePUCCHPreparation(obj,ue,timing,cfg,context)
            assert(min(timing.TransmitStartSample,timing.ReceiveStartSample)>=obj.Events.NextSampleIndex, ...
                'sixgr:truth:LateSharedPUCCHObservation','Arm complete observations before their first actual sample.');
            resources=sixgr.util.structGet(cfg,'validation.pucch_resources.resources',struct([]));
            assert(~isempty(resources) && all(isfield(resources,'starting_symbol')), ...
                'sixgr:truth:MissingPUCCHSymbolAuthority','Configured PUCCH resources must declare their active symbols.');
            firstSymbol=min(double([resources.starting_symbol]));
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            validateattributes(firstSymbol,{'numeric'},{'scalar','integer','nonnegative','<',double(carrier.SymbolsPerSlot)});
            % PUCCHTransmitter uses the canonical explicit zero-window plan.
            % Binding below verifies that no already consumed prefix is nonzero.
            info=nrOFDMInfo(carrier,'Windowing',0);
            offset=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe))*double(carrier.SymbolsPerSlot);
            first=timing.TransmitStartSample+sum(double(info.SymbolLengths(offset+(1:firstSymbol))));
            link=obj.linkForUE(ue,"UL"); ch=obj.channelState(ue,"UL");
            obj.Serial=obj.Serial+1; observationID="pucch_observation_"+obj.Serial;
            obj.Events.observe("ue_"+ue+":tx",observationID,timing.TransmitStartSample,timing.TransmitEndSampleExclusive);
            for plane=["gnb_"+link.Cell+"_rx:pre_rf","gnb_"+link.Cell+"_rx:post_rf"]
                obj.Events.observe(plane,observationID,timing.ReceiveStartSample, ...
                    timing.ReceiveEndWithoutChannelTail+double(ch.ChannelPadSamples));
            end
            context.ObservationID=observationID; context.AwaitingPreparation=true;
            context.PhysicalTiming=timing; context.TXEndSampleExclusive=timing.TransmitEndSampleExclusive;
            obj.Pending(end+1)=struct('ID',observationID,'Kind',"PUCCH",'UE',ue, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            obj.Serial=obj.Serial+1; id="pucch_preparation_"+obj.Serial;
            obj.Events.decisionBoundary(id,first);
            obj.Decisions(end+1)=struct('ID',id,'Kind',"PreparePUCCH", ...
                'UE',ue,'Context',context);
        end
        function transferPUCCHObservation(obj,id,proof)
            k=find(string({obj.Pending.ID})==string(id));
            assert(isscalar(k) && obj.Pending(k).Context.AwaitingPreparation, ...
                'sixgr:truth:InvalidPUCCHObservationTransfer','Only an unencoded PUCCH observation can transfer to PUSCH UCI.');
            assert(nargin==3 && isstruct(proof) && isscalar(proof) && ...
                all(isfield(proof,{'Key','FeedbackGrantIDs','PUSCHGrantContextIDs','Source'})) && ...
                proof.Key==obj.Pending(k).Context.Key && ...
                ~isempty(proof.FeedbackGrantIDs) && ...
                numel(proof.FeedbackGrantIDs)==numel(proof.PUSCHGrantContextIDs) && ...
                proof.Source=="pending_UCI_reservation_not_PUSCH_execution", ...
                'sixgr:truth:PUCCHTransferEvidenceMissing', ...
                'Retain exact pending-UCI reservation lineage before disposing this capture.');
            obj.Pending(k).Context.TransferProof=proof;
            obj.Pending(k).Kind="TransferredPUCCHObservation";
        end
        function bindUnselectedPUCCHObservation(obj,id,cfg,hypothesis)
            k=find(string({obj.Pending.ID})==string(id));
            assert(isscalar(k) && obj.Pending(k).Kind=="PUCCH" && ...
                hypothesis.SelectedTransport=="PUSCH", ...
                'sixgr:truth:InvalidUnselectedPUCCHBinding','Bind one observation to the scheduled PUSCH receiver.');
            p=obj.Pending(k); g=hypothesis.ScheduledULControl.Binding.Grant;
            producer=struct(); txID="";
            if ~p.Context.AwaitingPreparation
                assert(isfield(p.Context,'Prepared') && isfield(p.Context,'UEHARQCodebook') && ...
                    ~isempty(p.Context.UEHARQCodebook.Events), ...
                    'sixgr:truth:UnselectedPUCCHProducerRequired', ...
                    'A prepared PUCCH must retain its independently received UE HARQ events.');
                rows=p.Context.FeedbackRows;
                types=lower(string(rows.UCIType));
                harq=contains(types,"harq");
                assert(all(harq | types=="csi_part1_part2"), ...
                    'sixgr:truth:UnsupportedPUCCHPayloadOwnership','Retain explicit HARQ/CSI producer ownership.');
                sixgr.truth.bindReceivedPUCCHCodebookRows(p.Context.UEHARQCodebook,rows(harq,:));
                txIdentity=sixgr.truth.preparedPUCCHTransmissionIdentity(p.Context.Prepared,p.UE,id);
                txID=txIdentity.TransmissionID;
                producer=p.Context;
            end
            controls=obj.readTransmittedULControls(p.UE,p.Context.Slot);
            identity=hypothesis.Mapping; digest="";
            if isempty(identity), identity=hypothesis; else, digest=hypothesis.PUSCHMapping.Digest; end
            assert(identity.UEIndex==p.UE && identity.TargetSlot==p.Context.Slot && ...
                hypothesis.Assignment.Data.ObservationID==string(id) && ...
                nnz(cellfun(@(r)isequaln(r,hypothesis.ScheduledULControl),controls))==1, ...
                'sixgr:truth:UnselectedPUCCHAuthorityMismatch','Retain this actual gNB command and DL occasion.');
            record=struct('PUCCHObservationID',string(id),'UEIndex',p.UE,'TargetSlot',p.Context.Slot, ...
                'ULGrantContextID',string(g.PHYGrant.GrantContextId), ...
                'GNBControlObservationID',hypothesis.ScheduledULControl.ObservationID, ...
                'HARQMappingDigest',digest, ...
                'PUCCHTransmissionID',txID, ...
                'SelectedAtSample',obj.Events.NextSampleIndex,'Source',"gnb_scheduled_PUSCH_not_UE_transport_transfer");
            assert(~any(cellfun(@(r)r.UEIndex==record.UEIndex && r.TargetSlot==record.TargetSlot, ...
                obj.UnselectedPUCCHRegistrations)), ...
                'sixgr:truth:DuplicateUnselectedPUCCHBinding','Select the receiver once per physical occasion.');
            obj.UnselectedPUCCHRegistrations{end+1,1}=record;
            obj.UnselectedPUCCHProducers{end+1,1}=producer;
            obj.Pending(k).Context.Config=cfg;
            obj.Pending(k).Context.TransportSelection=record;
            obj.Pending(k).Context.AwaitingPreparation=false;
            obj.Pending(k).Kind="PUCCHNotSelected";
            % Any independently prepared UE samples stay queued. Selection
            % changes only which gNB decoder owns feedback, never UE TX.
        end
        function [selection,producer]=readUnselectedPUCCHForPUSCH(obj,grant)
            records=obj.UnselectedPUCCHRegistrations;
            hits=find(cellfun(@(r)r.ULGrantContextID==string(grant.PHYGrant.GrantContextId) && ...
                r.UEIndex==grant.UEIndex && r.TargetSlot==double(grant.Slot),records));
            assert(isscalar(hits),'sixgr:truth:MissingScheduledPUSCHReceiverSelection', ...
                'Receive-only HARQ must own the physical occasion before feedback completion.');
            selection=records{hits};
            producer=obj.UnselectedPUCCHProducers{hits};
        end
        function bindPUCCHReceiveOnly(obj,id,cfg,hypothesis)
            k=find(string({obj.Pending.ID})==string(id));
            assert(isscalar(k) && obj.Pending(k).Kind=="PUCCH" && ...
                obj.Pending(k).Context.AwaitingPreparation, ...
                'sixgr:truth:InvalidPUCCHReceiveOnlyBinding','Bind one actual unencoded registered receive window.');
            identity=hypothesis.Mapping; if isempty(identity), identity=hypothesis; end
            assert(isa(hypothesis.Assignment,'sixgr.phy.pucch.PUCCHReceptionAssignment') && ...
                hypothesis.Assignment.Data.ObservationID==string(id) && ...
                identity.UEIndex==obj.Pending(k).UE && ...
                identity.TargetSlot==obj.Pending(k).Context.Slot, ...
                'sixgr:truth:PUCCHReceiveOnlyIdentityMismatch','The gNB hypothesis must own this exact receiver window.');
            obj.Pending(k).Context.Config=cfg;
            obj.Pending(k).Context.GNBReception=hypothesis;
            obj.Pending(k).Context.AwaitingPreparation=false;
            obj.Pending(k).Kind="PUCCHReceiveOnly";
            % No contributor, waveform, power state or TX reference is added.
        end
        function ch=directionalChannelState(obj,ue,direction)
            % Metadata view only: never swap, clone or execute the owned
            % fading object to prepare a future opposite-direction signal.
            link=obj.linkForUE(ue,direction); ch=obj.channelState(ue,direction);
            cfg=link.DLConfig; if direction=="UL", cfg=link.ULConfig; end
            ch.Direction=char(direction);
            ch.LinkKey=char(sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,direction, ...
                'UEIndex',ue,'ServingCell',link.Cell));
        end
        function identity=broadcastReceiveIdentity(obj,ue)
            % Installed physical endpoints, independent of current TDD
            % direction. This is metadata access, not channel evolution.
            link=obj.linkForUE(ue,"DL");
            identity=struct('UEIndex',double(link.UE),'ServingCell',double(link.Cell), ...
                'LinkID',string(link.ID),'ReceiverID',"ue_"+link.UE+"_rx", ...
                'TransmitterID',"gnb_"+link.Cell,'SampleRateHz',obj.SampleRateHz, ...
                'PhysicalConfigurationEpoch',double(obj.Physical.ConfigurationEpoch));
        end
        function validateCompletedBroadcastObservation(obj,item)
            % Compare against the ORIGINAL buffer hash recorded inside the
            % event owner before delivery to any completion callback. Same
            % bounds and copied execution metadata do not authenticate IQ.
            receipt=localBroadcastCompletionReceipt(item);
            found=find(cellfun(@(r)r.ID==receipt.ID,obj.BroadcastCompletions));
            assert(isscalar(found) && isequaln(obj.BroadcastCompletions{found},receipt), ...
                'sixgr:truth:BroadcastCompletedCaptureMismatch', ...
                'The received buffer/identity must match its original physical completion.');
        end
        function [ids,plan]=armSIB1ReceiveOnly(obj,state,ue,endSampleExclusive)
            % An RX obligation is independent from cell SI emission. The
            % caller supplies only a horizon, never TX samples/resources or
            % a selected transmit occasion. Recompute current authority here.
            assert(isfield(state,'SharedWaveformStream') && isequal(state.SharedWaveformStream,obj), ...
                'sixgr:truth:ReceivedMIBOwnerMismatch','Arm observations on their original shared owner.');
            plan=sixgr.truth.planReceivedMIBSIMonitoring(state,ue,endSampleExclusive);
            ids=strings(0,1);
            if ~plan.Available, return; end
            binding=plan.ReceivedMIBBinding;
            identity=obj.broadcastReceiveIdentity(ue);
            assert(binding.ReceiverID==identity.ReceiverID && binding.SampleRateHz==obj.SampleRateHz && ...
                plan.PlanningSample==obj.Events.NextSampleIndex, ...
                'sixgr:truth:ReceivedMIBOwnerMismatch','Planning and arming must use the same original receiver clock.');
            cfgHash=sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(plan.ReceiverConfig));
            rows=plan.Windows;
            % Preflight every repeated registration before creating any
            % observation; a changed decoder configuration is never silently
            % attached to an already armed capture.
            found=zeros(height(rows),1);
            for k=1:height(rows)
                prior=find([obj.SIB1ReceiveRegistrations.UE]==ue & ...
                    string({obj.SIB1ReceiveRegistrations.GenerationID})==binding.GenerationID & ...
                    [obj.SIB1ReceiveRegistrations.AbsoluteMonitoringSlot]==rows.AbsoluteSlot(k));
                if isempty(prior), continue; end
                assert(isscalar(prior),'sixgr:truth:DuplicateSIReceiveRegistration','One original receiver/generation/slot has one observation.');
                r=obj.SIB1ReceiveRegistrations(prior);
                assert(r.StartSample==rows.ReceiveStartSample(k) && ...
                    r.EndSampleExclusive==rows.ReceiveEndSampleExclusive(k) && ...
                    r.ReceiverConfigSHA256==cfgHash && r.BindingSHA256==binding.BindingSHA256 && ...
                    r.DeliverySHA256==binding.DeliverySHA256, ...
                    'sixgr:truth:ChangedSIReceiveRegistration','A repeated SI receive obligation changed its original operands.');
                found(k)=prior;
            end
            for k=1:height(rows)
                if found(k)>0
                    ids(end+1,1)=obj.SIB1ReceiveRegistrations(found(k)).ID; %#ok<AGROW>
                    continue;
                end
                first=rows.ReceiveStartSample(k); stop=rows.ReceiveEndSampleExclusive(k);
                obj.Serial=obj.Serial+1; id="sib1_rx_"+obj.Serial;
                context=struct('ReceiverConfig',plan.ReceiverConfig,'ServingCell',binding.ServingCell, ...
                    'ReceivedMIBBinding',binding,'AbsoluteMonitoringSlot',rows.AbsoluteSlot(k), ...
                    'ReceiveStartSample',first,'ReceiveEndSampleExclusive',stop, ...
                    'MonitoringOccasion',table2struct(rows(k,:)), ...
                    'MonitoringWindowSHA256',plan.Type0MonitoringWindowSHA256, ...
                    'MonitoringPlanSHA256',plan.PlanSHA256,'ArmedAtSample',obj.Events.NextSampleIndex, ...
                    'ReceiveOnly',true,'TransmissionScheduled',false);
                for plane=[identity.ReceiverID+":pre_rf",identity.ReceiverID+":post_rf"]
                    obj.Events.observe(plane,id,first,stop);
                end
                obj.Pending(end+1)=struct('ID',id,'Kind',"SIB1",'UE',double(ue), ...
                    'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
                obj.SIB1ReceiveRegistrations(end+1)=struct('ID',id,'UE',double(ue), ...
                    'GenerationID',binding.GenerationID,'AbsoluteMonitoringSlot',rows.AbsoluteSlot(k), ...
                    'StartSample',first,'EndSampleExclusive',stop,'ReceiverConfigSHA256',cfgHash, ...
                    'BindingSHA256',binding.BindingSHA256,'DeliverySHA256',binding.DeliverySHA256);
                ids(end+1,1)=id; %#ok<AGROW>
            end
        end
        function digest=originalSIB1PreparedContract(obj,component)
            % Read-only original producer registration. A copied pending
            % structure cannot redefine the resources behind completed IQ.
            assert(isstring(component) && isscalar(component), ...
                'sixgr:truth:SIB1TransmissionCompletionMismatch', ...
                'Require the original scalar SI component identity.');
            found=find(string({obj.SIB1Registrations.ComponentID})==component);
            assert(isscalar(found),'sixgr:truth:SIB1TransmissionCompletionMismatch', ...
                'SI preparation was not registered by this shared owner.');
            digest=string(obj.SIB1Registrations(found).ContractSHA256);
        end
        function [bursts,siComponents]=queueDueCellBroadcasts(obj,slot0)
            % Cell TX is decided before, and independently of, UE observers.
            % Installation is lazy so legacy composite callers are unchanged.
            validateattributes(slot0,{'double'},{'scalar','real','finite','integer','nonnegative','<',flintmax});
            if ~obj.CellBroadcastSchedulingActive
                assert(slot0==0 && obj.Events.NextSampleIndex==0 && ...
                    ~any(startsWith(string({obj.Components.ID}),"PBCH_")) && isempty(obj.SIB1Registrations), ...
                    'sixgr:truth:CellBroadcastOriginRequired', ...
                    'Install independent cell broadcast scheduling at the untouched physical origin.');
                cells=unique([obj.Links.Cell]);
                installed=obj.CellBroadcasts;
                for cellID=reshape(cells,1,[])
                    links=obj.Links([obj.Links.Cell]==cellID);
                    cfg=links(1).DLConfig;
                    [digest,plan,period]=localCellBroadcastContract(cfg);
                    for k=2:numel(links)
                        peer=localCellBroadcastContract(links(k).DLConfig);
                        assert(peer==digest,'sixgr:truth:CellBroadcastConfigurationMismatch', ...
                            'All links sharing a gNB must install the same broadcast TX policy.');
                    end
                    installed(end+1)=struct('Cell',cellID,'Config',cfg,'ConfigSHA256',digest, ...
                        'Plan',plan,'PeriodSlots',period,'LastSSBSlot',NaN, ...
                        'Prepared',struct(),'Prototype',struct()); %#ok<AGROW>
                end
                obj.CellBroadcasts=installed;
                obj.CellBroadcastSchedulingActive=true;
            end
            for k=1:numel(obj.CellBroadcasts)
                carrier=sixgr.phy.grid.makeCarrier(obj.CellBroadcasts(k).Config);
                assert(obj.Events.NextSampleIndex==sixgr.phy.frame.slotStartSample(carrier,slot0,obj.SampleRateHz), ...
                    'sixgr:truth:CellBroadcastSchedulingClock', ...
                    'Schedule original broadcasts only at the current physical slot boundary.');
            end
            prior=find([obj.CellBroadcastSchedule.Slot]==slot0);
            if ~isempty(prior)
                bursts=obj.CellBroadcastSchedule(prior).Bursts;
                siComponents=obj.CellBroadcastSchedule(prior).SIComponents;
                return;
            end
            assert(slot0==numel(obj.CellBroadcastSchedule), ...
                'sixgr:truth:CellBroadcastSchedulingGap','Do not skip an installed cell transmission calendar.');
            bursts=struct('ServingCell',{},'ComponentID',{},'AbsoluteSlot',{}, ...
                'StartSample',{},'EndSampleExclusive',{});
            siComponents=strings(0,1);
            for k=1:numel(obj.CellBroadcasts)
                cellOwner=obj.CellBroadcasts(k); cfg=cellOwner.Config;
                if ~logical(sixgr.util.structGet(cfg,'phy.ssb.enable',false)), continue; end
                if mod(slot0,cellOwner.PeriodSlots)==0
                    captureSubframes=localCellSSBCaptureSubframes(cfg);
                    prototype=sixgr.link.runCellSearch_MIB_SIB1(cfg,'PrepareOnly',true, ...
                        'UseRuntimeChannel',true,'RuntimeSlot',slot0,'Content','SSB_MIB', ...
                        'NumSubframes',captureSubframes);
                    assert(isfield(prototype,'PreparedBroadcast'), ...
                        'sixgr:truth:CellSSBPreparationFailed','Original cell SSB preparation failed: %s',prototype.FailureReason);
                    p=prototype.PreparedBroadcast; prototype=rmfield(prototype,'PreparedBroadcast');
                    first=p.BroadcastStartSample; stop=first+p.NumSamples;
                    assert(p.Content=="SSB_MIB" && p.Tx.SSBEmissionIncluded && ...
                        ~p.Tx.SIB1EmissionIncluded && isempty(p.Tx.SIB1Transmissions) && ...
                        p.BroadcastStartAbsoluteSlot==slot0 && first==obj.Events.NextSampleIndex && ...
                        p.SampleRateHz==obj.SampleRateHz && p.RFExecutionDeferred && ...
                        ~p.PowerContext.PAApplied, ...
                        'sixgr:truth:CellSSBPreparationAuthority','Use the original SSB-only, power-bound, deferred-RF preparation.');
                    carrier=sixgr.phy.grid.makeCarrier(p.Config);
                    assert(stop<=sixgr.phy.frame.slotStartSample(carrier,slot0+cellOwner.PeriodSlots,obj.SampleRateHz), ...
                        'sixgr:truth:CellSSBBurstOverlap','One prepared SSB buffer must not cover a later scheduled burst.');
                    tx="gnb_"+cellOwner.Cell;
                    obj.Physical.validateTransmitterInstallation(tx,p.Config,'DL',size(p.TransmitSamples,2));
                    component="SSB_"+tx+"_"+first;
                    receipt=obj.Events.enqueue(tx,component,sixgr.phy.waveform.WaveformChunk(p.TransmitSamples,first));
                    obj.Serial=obj.Serial+1; id="ssb_tx_"+obj.Serial;
                    obj.Events.observe(tx+":tx",id,first,stop);
                    context=struct('ComponentID',component,'ServingCell',cellOwner.Cell, ...
                        'TransmitterPlane',tx+":tx",'Prepared',p,'EnqueueReceipt',receipt, ...
                        'Slot',slot0+1,'Frame',floor(slot0/double(carrier.SlotsPerFrame))+1, ...
                        'SNR',sixgr.truth.resolveWaveformOperatingPointMetadata(cfg,p.RequestedSNR_dB), ...
                        'CellBroadcastConfigurationSHA256',cellOwner.ConfigSHA256);
                    obj.Pending(end+1)=struct('ID',id,'Kind',"CellSSBTX",'UE',0, ...
                        'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
                    obj.CellSSBRegistrations(end+1)=struct('ComponentID',component, ...
                        'PreparedSHA256',sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(p)));
                    obj.Components(end+1)=struct('ID',component,'TX',tx,'Start',first,'Samples',p.TransmitSamples);
                    cellOwner.LastSSBSlot=slot0; cellOwner.Prepared=p; cellOwner.Prototype=prototype;
                    obj.CellBroadcasts(k)=cellOwner;
                    bursts(end+1)=struct('ServingCell',cellOwner.Cell,'ComponentID',component, ...
                        'AbsoluteSlot',slot0,'StartSample',first,'EndSampleExclusive',stop); %#ok<AGROW>
                end
                occasions=cellOwner.Plan.sib1TransmissionOccasions(slot0,slot0+1);
                if isempty(occasions), continue; end
                assert(~isempty(fieldnames(cellOwner.Prepared)), ...
                    'sixgr:truth:MissingOriginalCellSSBAssociation','SI needs an original generated cell SSB association.');
                for row=1:height(occasions)
                    associated=cfg;
                    associated.phy.ssb.runtimeSSBIndex=occasions.SSBIndex(row);
                    associated.phy.sib1.transmissionScope="selected_ssb_occasion";
                    info=cellOwner.Prepared.Tx.SSBInfo;
                    % Same original burst/matrix; select its exact active beam.
                    info.SSBTiming=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig( ...
                        associated,'SSBIndex',occasions.SSBIndex(row));
                    p=sixgr.link.prepareSIB1Transmission(associated,info,'AbsoluteSlot',slot0);
                    siComponents(end+1,1)=obj.queueSIB1Transmission(cellOwner.Cell,p); %#ok<AGROW>
                end
            end
            obj.CellBroadcastSchedule(end+1)=struct('Slot',slot0,'Bursts',bursts,'SIComponents',siComponents);
        end
        function [id,context]=armCellSSBObservation(obj,ue,context)
            % Attaching an observer never creates/replaces a TX component.
            assert(obj.CellBroadcastSchedulingActive && isstruct(context) && isscalar(context) && ...
                all(isfield(context,{'Config','Slot','Frame','RNTI','ServingCell','SNR','TrackingOnly'})), ...
                'sixgr:truth:CellSSBObservationContext','Use a current per-UE receiver context after cell scheduling.');
            link=obj.linkForUE(ue,"DL"); slot0=context.Slot-1;
            hit=find([obj.CellBroadcasts.Cell]==link.Cell);
            assert(isscalar(hit) && context.ServingCell==link.Cell, ...
                'sixgr:truth:CellSSBObservationContext','The observer must belong to this installed cell.');
            cellOwner=obj.CellBroadcasts(hit); p=cellOwner.Prepared;
            assert(cellOwner.LastSSBSlot==slot0 && ~isempty(fieldnames(p)) && ...
                obj.Events.NextSampleIndex==p.BroadcastStartSample, ...
                'sixgr:truth:LateCellSSBObservation','Arm only before original burst samples are consumed.');
            % RX tracking, RNTI, measured pathloss and dedicated-resource
            % overlays are not cell TX policy. Only its installed tuning and
            % physical receiver must match; no observer can redefine TX.
            originalCarrier=sixgr.phy.grid.makeCarrier(cellOwner.Config);
            receiverCarrier=sixgr.phy.grid.makeCarrier(context.Config);
            for field=["NCellID","NSizeGrid","NStartGrid","SubcarrierSpacing","CyclicPrefix"]
                assert(isequal(receiverCarrier.(field),originalCarrier.(field)), ...
                    'sixgr:truth:CellBroadcastReceiverMismatch','Receiver changed the installed cell %s.',field);
            end
            a=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cellOwner.Config);
            b=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(context.Config);
            assert(isequaln(a.GridRelationship,b.GridRelationship) && isequal(string(a.Case),string(b.Case)) && ...
                a.SSBSubcarrierSpacingKHz==b.SSBSubcarrierSpacingKHz, ...
                'sixgr:truth:CellBroadcastReceiverMismatch','Receiver tuning must retain the original SSB geometry.');
            node=obj.Nodes(string({obj.Nodes.ID})=="ue_"+ue+"_rx");
            obj.Physical.validateReceiverInstallation("ue_"+ue+"_rx",context.Config,'DL',node.NumAntennas);
            context.Config=sixgr.phy.grid.applyRuntimeCarrierTimeline(context.Config,slot0+1);
            p.ReceiverConfig=sixgr.util.structSet(context.Config,'lls6g.runtimePowerContext',p.PowerContext);
            context.Prepared=p; context.Prototype=cellOwner.Prototype;
            context.CellOwnedBroadcast=true;
            context.CellBroadcastConfigurationSHA256=cellOwner.ConfigSHA256;
            context.ComponentID="SSB_gnb_"+link.Cell+"_"+p.BroadcastStartSample;
            if ~context.TrackingOnly
                context.AcquisitionWindowContract=sixgr.phy.frame.SSBAcquisitionWindow.create( ...
                    p.ReceiverConfig,obj.SampleRateHz,double(p.BroadcastStartSample),double(p.NumSamples));
            end
            context=sixgr.truth.compactBroadcastReceiveContext(context);
            digest=sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(context));
            prior=find([obj.CellSSBObservers.Cell]==link.Cell & [obj.CellSSBObservers.UE]==ue & ...
                [obj.CellSSBObservers.Slot]==slot0);
            if ~isempty(prior)
                assert(obj.CellSSBObservers(prior).ContextSHA256==digest, ...
                    'sixgr:truth:ChangedCellSSBObservation','An armed original receiver context is immutable.');
                id=obj.CellSSBObservers(prior).ID;
                original=find(string({obj.Pending.ID})==id);
                assert(isscalar(original),'sixgr:truth:LateCellSSBObservation','The original observer has already completed.');
                context=obj.Pending(original).Context; return;
            end
            obj.Serial=obj.Serial+1; id="observation_"+obj.Serial;
            first=p.BroadcastStartSample; stop=first+p.NumSamples;
            archiveStop=stop;
            if ~context.TrackingOnly
                stop=context.AcquisitionWindowContract.EndSampleExclusive;
            end
            tx="gnb_"+link.Cell; rx="ue_"+ue+"_rx";
            planes=[tx+":tx",rx+":pre_rf",rx+":post_rf"];
            for plane=planes, obj.Events.observe(plane,id,first,stop); end
            context.DesiredReferencePlane=obj.Physical.registerLinkScoringPlane(obj.Events,link.ID,rx);
            obj.Events.observe(context.DesiredReferencePlane,id,first,stop);
            obj.Pending(end+1)=struct('ID',id,'Kind',"PBCH",'UE',ue,'Context',context, ...
                'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            obj.CellSSBObservers(end+1)=struct('Cell',link.Cell,'UE',ue,'Slot',slot0, ...
                'ID',id,'ContextSHA256',digest);
            if ~context.TrackingOnly && stop<archiveStop
                % Archive completion is not another PHY acquisition. Both
                % observers consume the same original physical execution;
                % neither truncates Prepared nor replays the channel/RF.
                obj.Serial=obj.Serial+1; archiveID="observation_"+obj.Serial;
                archive=context; archive.AcquisitionObservationID=id;
                for plane=[planes,context.DesiredReferencePlane]
                    obj.Events.observe(plane,archiveID,first,archiveStop);
                end
                obj.Pending(end+1)=struct('ID',archiveID,'Kind',"SSBArchive",'UE',ue, ...
                    'Context',archive,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            end
            if context.TrackingOnly
                horizons=sixgr.phy.frame.ssbObservationHorizons(context.Config,obj.SampleRateHz);
                assert(all(horizons.ObservationEndSampleExclusive<=p.NumSamples), ...
                    'sixgr:truth:SSBOccasionOutsideBroadcast','Retain the configured original SSB observation extent.');
                for n=1:height(horizons)
                    obj.Serial=obj.Serial+1; occasionID="observation_"+obj.Serial;
                    occasion=context; occasion.SSBOccasionHorizon=horizons(n,:);
                    occasion.BroadcastStartSample=first;
                    for plane=[planes,context.DesiredReferencePlane]
                        obj.Events.observe(plane,occasionID,first,first+horizons.ObservationEndSampleExclusive(n));
                    end
                    obj.Pending(end+1)=struct('ID',occasionID,'Kind',"SSBOccasion",'UE',ue, ...
                        'Context',occasion,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
                end
            end
        end
        function component=queueSIB1Transmission(obj,cellID,prepared)
            % Cell TX is independent of the number/state of UE observers.
            % Only advanceSlot executes RF/channel/noise and commits it.
            validateattributes(cellID,{'numeric'},{'scalar','real','finite','integer','positive'});
            tx="gnb_"+cellID;
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(isscalar(node),'sixgr:truth:UnknownSIB1Transmitter', ...
                'An independently scheduled SI must use a registered gNB endpoint.');
            required={'Tx','TransmitSamples','TransmitStartSample','NumSamples', ...
                'SampleRateHz','RFExecutionDeferred','PowerContext','Config'};
            assert(isstruct(prepared) && isscalar(prepared) && all(isfield(prepared,required)), ...
                'sixgr:truth:SharedSIB1PreparationAuthority','Use the original independent SI preparation.');
            si=prepared.Tx; samples=prepared.TransmitSamples;
            first=prepared.TransmitStartSample; fs=prepared.SampleRateHz;
            carrier=sixgr.phy.grid.makeCarrier(prepared.Config);
            installed=obj.Links([obj.Links.Cell]==cellID);
            assert(~isempty(installed),'sixgr:truth:UnknownSIB1Transmitter','No installed cell configuration.');
            installedCfg=installed(1).DLConfig;
            installedCarrier=sixgr.phy.grid.makeCarrier(installedCfg);
            for name=["NCellID","NSizeGrid","NStartGrid","SubcarrierSpacing","CyclicPrefix"]
                assert(isequal(carrier.(name),installedCarrier.(name)), ...
                    'sixgr:truth:SIB1CellConfigurationMismatch', ...
                    'SI preparation changed the registered cell %s.',name);
            end
            sixgr.rf.appliedWaveformAmplitudeUnit(installedCfg,prepared.PowerContext);
            assert(isequaln(sixgr.util.structGet(prepared.Config,'rf',struct()),node.RF), ...
                'sixgr:truth:SIB1PhysicalEpochMismatch','SI cannot replace the installed TX RF configuration.');
            obj.Physical.validateTransmitterInstallation(tx,prepared.Config,'DL',size(samples,2));
            assert(isequal(sixgr.util.structGet(prepared.PowerContext,'PAApplied',[]),false), ...
                'sixgr:truth:SharedSIB1PreparationAuthority', ...
                'The original SI preparation must not apply the shared transmitter PA a second time.');
            validateattributes(first,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(fs==obj.SampleRateHz && isequal(prepared.RFExecutionDeferred,true) && ...
                string(si.WaveformContent)=="si_rnti_pdcch_pdsch_only" && ~si.SSBEmissionIncluded && ...
                first==si.WaveformStartAbsoluteSample && ...
                first==sixgr.phy.frame.slotStartSample(carrier,si.SIB1AbsoluteSlot,fs) && ...
                isnumeric(samples) && ~isempty(samples) && all(isfinite(samples),'all') && ...
                any(samples~=0,'all') && size(samples,1)==prepared.NumSamples && ...
                size(samples,2)==node.NumAntennas, ...
                'sixgr:truth:SharedSIB1PreparationAuthority', ...
                'SI requires exact physical-port samples, radio origin and deferred RF on the shared clock.');
            ssb=si.SIB1SpatialMapping.SSBIndex;
            validateattributes(ssb,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            component="SIB1_"+tx+"_"+first+"_ssb_"+ssb;
            % Compare complete prepared contracts, not only length or payload.
            % A changed power/grid/clock cannot silently reuse old samples.
            contract=sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(prepared));
            prior=find(string({obj.SIB1Registrations.ComponentID})==component);
            if ~isempty(prior)
                assert(isscalar(prior) && obj.SIB1Registrations(prior).ContractSHA256==contract, ...
                    'sixgr:truth:InconsistentCellSIB1','One cell/beam/occasion cannot have conflicting SI producers.');
                return;
            end
            assert(first>=obj.Events.NextSampleIndex,'sixgr:truth:LateSIB1Preparation', ...
                'Do not emit SI into samples already processed by the shared owner.');
            epoch=sixgr.util.structGet(prepared.Config,'rf.configurationEpoch',[]);
            assert(isequal(double(epoch),double(obj.Physical.ConfigurationEpoch)), ...
                'sixgr:truth:SIB1PhysicalEpochMismatch','SI preparation must belong to the registered physical epoch.');
            obj.Serial=obj.Serial+1; id="sib1_tx_"+obj.Serial;
            enqueueReceipt=obj.Events.enqueue(tx,component,sixgr.phy.waveform.WaveformChunk(samples,first));
            obj.Events.observe(tx+":tx",id,first,first+prepared.NumSamples);
            context=struct('ComponentID',component,'ServingCell',double(cellID), ...
                'TransmitterPlane',tx+":tx",'Prepared',prepared,'EnqueueReceipt',enqueueReceipt);
            obj.Pending(end+1)=struct('ID',id,'Kind',"CellSIB1TX",'UE',0, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            obj.SIB1Registrations(end+1)=struct('ComponentID',component,'ContractSHA256',contract);
        end
        function queueDownlink(obj,kind,ue,prepared,context)
            assert(kind~="PBCH" || ~obj.CellBroadcastSchedulingActive, ...
                'sixgr:truth:MixedCellBroadcastOwnership', ...
                'Independent cell scheduling must not also enqueue a legacy/composite PBCH producer.');
            if kind=="PBCH" && ...
                    sixgr.util.structGet(context.Config,'phy.ssb.halfFrameIndex',0)~=0
                % This owner currently anchors the complete local broadcast
                % buffer at a selected SSB slot. A phased whole-frame SSB
                % buffer would apply that phase twice. Standalone SSB_Tx
                % supports the phase; coupled broadcast-origin reconciliation
                % must be implemented before admitting it to this owner.
                error('sixgr:truth:UnsupportedSharedSSBPhaseOrigin', ...
                    ['Nonzero SSB half-frame phase requires an explicit shared ' ...
                     'broadcast-buffer origin; the current slot-anchored ' ...
                     'composite cannot be enqueued without duplicating the phase.']);
            end
            link=obj.linkForUE(ue,"DL");
            fs=double(prepared.SampleRateHz);
            if fs~=obj.SampleRateHz || ~prepared.RFExecutionDeferred
                error('sixgr:truth:SharedPreparationAuthority', ...
                    'Contributors must use the physical clock and defer component RF processing.');
            end
            carrier=sixgr.phy.grid.makeCarrier(context.Config);
            first=sixgr.phy.frame.slotStartSample(carrier,context.Slot-1,fs);
            if kind=="PBCH"
                % The waveform was encoded at this radio origin. Enqueue
                % may not transplant frame-zero PBCH/SI into a later frame.
                originSlot=context.Slot-1;
                assert(isfield(prepared,'BroadcastStartAbsoluteSlot') && ...
                    isfield(prepared,'BroadcastStartSample') && ...
                    isfield(prepared.Tx,'BroadcastStartAbsoluteSlot') && ...
                    isfield(prepared.Tx,'BroadcastStartSample') && ...
                    originSlot>=0 && originSlot==fix(originSlot) && ...
                    mod(originSlot,double(carrier.SlotsPerFrame))==0 && ...
                    isequal(prepared.BroadcastStartAbsoluteSlot,originSlot) && ...
                    isequal(prepared.BroadcastStartSample,first) && ...
                    isequal(prepared.Tx.BroadcastStartAbsoluteSlot,originSlot) && ...
                    isequal(prepared.Tx.BroadcastStartSample,first), ...
                    'sixgr:truth:SharedBroadcastOriginMismatch', ...
                    'Bind the original encoded broadcast frame to the same shared sample origin exactly once.');
                preparedCarrier=sixgr.phy.grid.makeCarrier(prepared.Config);
                assert(preparedCarrier.NSlot==0 && ...
                    double(preparedCarrier.NFrame)*double(preparedCarrier.SlotsPerFrame)==originSlot && ...
                    preparedCarrier.SubcarrierSpacing==carrier.SubcarrierSpacing, ...
                    'sixgr:truth:SharedBroadcastOriginMismatch', ...
                    'Prepared radio clocks must retain the original broadcast origin and numerology.');
            end
            samples=prepared.TransmitSamples;
            if kind=="TRS"
                % Future DL may be queued while the reciprocal channel is
                % currently UL. Resolve the signal's configured gNB map,
                % not the current UE TX dimensions or a different signal's
                % logical ports. This does not execute or swap a channel.
                array=sixgr.rf.AntennaArrayFactory.build(prepared.ReceiverConfig,'bs', ...
                    'signal','trs','numPorts',size(samples,2));
                matrix=array.PortToElementMatrix;
                assert(all(isfinite(matrix),'all') && ...
                    norm(matrix'*matrix-eye(size(samples,2)),'fro')<=1e-9*size(samples,2), ...
                    'sixgr:truth:SharedTRSProjectionPower','TRS projection must preserve logical-port power.');
                prepared.TransmitProjectionMatrix=matrix;
                prepared.TransmitStartSample=first;
                samples=samples*cast(matrix.','like',samples);
            elseif kind=="CSIRS"
                assert(isstruct(prepared) && isscalar(prepared) && ...
                    string(sixgr.util.structGet(prepared,'ExecutionStage',''))== ...
                    "csirs_waveform_prepared_not_received" && ...
                    prepared.NumSamples==size(samples,1) && ...
                    prepared.NumPhysicalTransmitAntennas==size(samples,2), ...
                    'sixgr:truth:SharedCSIRSPreparationAuthority', ...
                    ['Queue the independently prepared cell-common CSI-RS ' ...
                     'physical-port waveform, never a PDSCH-derived substitute.']);
                prepared.TransmitStartSample=first;
                prepared.ReceiveStartSample=first;
                % Capture actual future samples for every configured timing
                % hypothesis. A one-slot RX window forces [0,0] regardless
                % of the physical delay; never fix that with zero padding.
                guard=double(prepared.ReceiveTimingSearchGuardSamples);
                validateattributes(guard,{'numeric'}, ...
                    {'scalar','finite','integer','nonnegative'});
                prepared.ReceiveEndSampleExclusive=first+prepared.NumSamples+guard;
            elseif kind~="PBCH"
                error('sixgr:truth:UnsupportedSharedDownlinkPreparation','No sample-domain adapter for %s.',kind);
            end
            tx="gnb_"+link.Cell;
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(size(samples,2)==node.NumAntennas, ...
                'sixgr:truth:SharedDLPhysicalAntennaLayout','Queued DL must match the registered physical gNB radio.');
            component=string(kind)+"_"+tx+"_"+first;
            referenceEnabled=false;
            if kind=="CSIRS"
                referenceEnabled=obj.Physical.assertCSIRSPortReferenceSupport( ...
                    obj.Events,link.ID,tx,prepared);
            end
            prior=find(string({obj.Components.ID})==component,1);
            if isempty(prior)
                if kind=="CSIRS"
                    enqueueReceipt=obj.Events.enqueue(tx,component, ...
                        sixgr.phy.waveform.WaveformChunk(samples,first)); %#ok<NASGU>
                else
                    obj.Events.enqueue(tx,component,sixgr.phy.waveform.WaveformChunk(samples,first));
                end
                obj.Components(end+1)=struct('ID',component,'TX',tx,'Start',first,'Samples',samples);
            elseif ~isequal(obj.Components(prior).Samples,samples)
                error('sixgr:truth:InconsistentCellBroadcast', ...
                    'One cell transmission cannot have different physical samples for different receiving UEs.');
            end
            obj.Serial=obj.Serial+1; id="observation_"+obj.Serial;
            context.Prepared=prepared;
            if kind=="CSIRS"
                context.ComponentID=component;
                context.TransmitterPlane=tx+":tx";
                context.ServingCell=double(link.Cell);
                if referenceEnabled
                    [context.CSIRSPortReferencePlanes,context.CSIModelAggregatePlane, ...
                        context.CSIModelResidualPlane]=obj.Physical.registerCSIRSPortReferences( ...
                        obj.Events,link.ID,tx,"ue_"+ue+"_rx",component,prepared);
                    context.CSIPortReferenceScope="optional_fixed_linear_model_not_actual_nonlinear_port_truth";
                end
            end
            if kind=="PBCH"
                context=sixgr.truth.compactBroadcastReceiveContext(context);
            end
            planes=[tx+":tx","ue_"+ue+"_rx:pre_rf","ue_"+ue+"_rx:post_rf"];
            receiveEnd=first+prepared.NumSamples;
            if kind=="CSIRS", receiveEnd=prepared.ReceiveEndSampleExclusive; end
            if referenceEnabled
                modelPlanes=[string({context.CSIRSPortReferencePlanes.PlaneID}), ...
                    context.CSIModelAggregatePlane,context.CSIModelResidualPlane];
                for plane=modelPlanes, obj.Events.observe(plane,id,first,receiveEnd); end
            end
            for plane=planes
                last=receiveEnd;
                if plane==tx+":tx", last=first+prepared.NumSamples; end
                obj.Events.observe(plane,id,first,last);
            end
            if any(kind==["TRS","PBCH","CSIRS"])
                rx="ue_"+ue+"_rx";
                context.DesiredReferencePlane=obj.Physical.registerLinkScoringPlane(obj.Events,link.ID,rx);
                obj.Events.observe(context.DesiredReferencePlane,id,first,receiveEnd);
                if kind=="CSIRS"
                    obj.Physical.requestLinkChannelReference(obj.Events,link.ID,rx, ...
                        first,receiveEnd);
                end
            end
            obj.Pending(end+1)=struct('ID',id,'Kind',string(kind),'UE',ue, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
            if kind=="PBCH" && logical(sixgr.util.structGet(context,'TrackingOnly',false))
                horizons=sixgr.phy.frame.ssbObservationHorizons(context.Config,fs);
                assert(all(horizons.ObservationEndSampleExclusive<=prepared.NumSamples), ...
                    'sixgr:truth:SSBOccasionOutsideBroadcast','Configured SSB timing guard exceeds the retained broadcast extent.');
                for k=1:height(horizons)
                    obj.Serial=obj.Serial+1; id="observation_"+obj.Serial;
                    occasion=context; occasion.SSBOccasionHorizon=horizons(k,:);
                    occasion.BroadcastStartSample=first;
                    for plane=planes
                        obj.Events.observe(plane,id,first,first+horizons.ObservationEndSampleExclusive(k));
                    end
                    obj.Events.observe(context.DesiredReferencePlane,id,first, ...
                        first+horizons.ObservationEndSampleExclusive(k));
                    obj.Pending(end+1)=struct('ID',id,'Kind',"SSBOccasion",'UE',ue, ...
                        'Context',occasion,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
                end
            end
        end
        function compactBroadcastContexts(obj)
            % Also migrate legacy checkpoints in memory, never rewrite their
            % immutable state files. Equality guards preserve frozen IQ.
            for k=1:numel(obj.Pending)
                if any(obj.Pending(k).Kind==["PBCH","SSBOccasion","SSBArchive"])
                    obj.Pending(k).Context=sixgr.truth.compactBroadcastReceiveContext(obj.Pending(k).Context);
                end
            end
        end
        function archiveCompletedSampleOwners(obj,root)
            % Retire completed sample owners only. Do not change pending
            % sample coverage, channel/filter/RF/RNG state, retained scoring
            % segments, grant identity, soft buffers or receiver decisions.
            scope=sixgr.runtime.ExecutionStageProfiler.scope("checkpoint","archive_completed_samples"); %#ok<NASGU>
            for k=1:numel(obj.Pending)
                for j=1:numel(obj.Pending(k).Planes)
                    observation=obj.Pending(k).Planes(j).Observation;
                    if observation.isComplete(), observation.archiveCompleted(root); end
                end
            end
            for k=1:numel(obj.ScheduledControlRegistrations)
                observation=obj.ScheduledControlRegistrations{k}.TransmitObservation;
                if isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && observation.isComplete()
                    observation.archiveCompleted(root);
                end
            end
            for k=1:numel(obj.PUSCHReceiveOnlyCompletions)
                for j=1:numel(obj.PUSCHReceiveOnlyCompletions{k}.Planes)
                    observation=obj.PUSCHReceiveOnlyCompletions{k}.Planes(j).Observation;
                    if observation.isComplete(), observation.archiveCompleted(root); end
                end
            end
        end
        function [state,completed]=drainDataReceiveTail(obj,state,cfg,onReceived)
            % Scheduling is closed, but a transmitted allocation's channel/
            % receive-clock tail is not padding and still needs real RF/noise.
            % Bound this drain by already registered data windows. Do not run
            % startSlot, create grants, or extend the scheduled TX-IQ export.
            if nargin<4, onReceived=[]; end
            completed=struct('ID',{},'Kind',{},'UE',{},'Context',{},'Planes',{});
            selected=ismember(string({obj.Pending.Kind}),["PDSCH","PUSCH","PUSCHReceiveOnly"]);
            if ~any(selected), return; end
            pending=obj.Pending(selected);
            first=obj.Events.NextSampleIndex;
            scheduledSlot=state.CurrentSlot;
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            assert(first==sixgr.phy.frame.slotStartSample(carrier,scheduledSlot,obj.SampleRateHz), ...
                'sixgr:truth:ReceiveTailHorizonClockMismatch', ...
                'Close the scheduled slot before draining registered receive tails.');
            for p=pending
                if any(p.Kind==["PDSCH","PUSCH"])
                    assert(p.Context.Prepared.EndSampleExclusive<=first, ...
                        'sixgr:truth:ReceiveTailContainsFutureDataTX', ...
                        'A future data transmission is not the receive tail of the closed horizon.');
                else
                    assert(sixgr.truth.runtimeULGrantSlot(p.Context.Grant)<=scheduledSlot, ...
                        'sixgr:truth:ReceiveTailContainsFutureDataTX', ...
                        'Only already scheduled source-slot receive-only windows may drain.');
                end
            end
            last=max(arrayfun(@(p)p.Context.ReceiveEndSampleExclusive,pending));
            validateattributes(last,{'numeric'},{'scalar','real','finite','integer','>',first});
            while obj.Events.NextSampleIndex<last
                state.CurrentSlot=state.CurrentSlot+1;
                if nargout>1
                    [state,items]=obj.advanceSlot(state,cfg,onReceived,last);
                    completed=[completed,items]; %#ok<AGROW>
                else
                    state=obj.advanceSlot(state,cfg,onReceived,last);
                end
            end
            assert(~any(ismember(string({obj.Pending.Kind}),["PDSCH","PUSCH","PUSCHReceiveOnly"])), ...
                'sixgr:truth:SharedDataReceiveTailNotDrained', ...
                'Every registered data receive window must complete on actual samples.');
            state.CurrentSlot=scheduledSlot;
            state.SharedReceiveTailTable=table(double(scheduledSlot),first,last,last-first, ...
                obj.SampleRateHz,numel(pending), ...
                "actual_shared_channel_noise_RF_after_scheduling_horizon", ...
                'VariableNames',{'ScheduledSlotCount','StartSample','EndSampleExclusive', ...
                'SampleCount','SampleRateHz','PendingDataObservationCount','Source'});
        end
        function [state,completed]=advanceSlot(obj,state,cfg,onReceived,receiveTailEndSample)
            if nargin<4, onReceived=[]; end
            if logical(sixgr.util.structGet(cfg,'lls6g.energy_efficiency.enabled',false)) || ...
                    logical(sixgr.util.structGet(cfg,'rf.txSpatialPowerEnabled',false)) || ...
                    logical(sixgr.util.structGet(cfg,'rf.modeledRadiatedPower.Enabled',false)) || ...
                    logical(sixgr.util.structGet(cfg,'rf.txLinearReference.Enabled',false))
                % Idempotent for current owners; legacy checkpoint owners
                % begin their new record here, not retroactively at zero.
                obj.Physical.enableRFExecutionLedger();
            end
            drainingTail=nargin>=5;
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            % Received grant ordinals may retain an integer MATLAB class.
            % OFDM vector indexing must not mix integer scalars and double
            % index arrays (or saturate unsigned subtraction at slot zero).
            validateattributes(state.CurrentSlot,{'numeric'}, ...
                {'scalar','real','finite','integer','positive','<=',flintmax});
            carrier.NSlot=double(state.CurrentSlot)-1;
            info=nrOFDMInfo(carrier);
            first=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,obj.SampleRateHz);
            stop=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot,obj.SampleRateHz);
            nominalStop=stop;
            if drainingTail
                validateattributes(receiveTailEndSample,{'numeric'}, ...
                    {'scalar','real','finite','integer','>',first});
                stop=min(stop,receiveTailEndSample);
            end
            if obj.Events.NextSampleIndex~=first
                error('sixgr:truth:SchedulerPhysicalClockMismatch','Slot scheduling and physical sample consumption are not contiguous.');
            end
            symbols=double(carrier.SymbolsPerSlot);
            localSlot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
            lengths=double(info.SymbolLengths(localSlot*symbols+(1:symbols)));
            if sum(lengths)~=nominalStop-first
                error('sixgr:truth:SlotSampleExtentMismatch','Actual OFDM symbol lengths must cover the scheduler slot.');
            end
            if ~isempty(obj.TxIQRecorder) && ~drainingTail
                txNodes=obj.Nodes(~endsWith(string({obj.Nodes.ID}),"_rx"));
                for node=txNodes
                    obj.Serial=obj.Serial+1;
                    id="continuous_tx_iq_"+obj.Serial;
                    obj.Events.observe(node.ID+":tx",id,first,stop);
                    context=struct('EndpointID',string(node.ID), ...
                        'Direction',string(node.Direction),'NumPorts',double(node.NumAntennas));
                    obj.Pending(end+1)=struct('ID',id,'Kind',"ContinuousTxIQ", ...
                        'UE',NaN,'Context',context, ...
                        'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
                end
            end
            boundaries=min([first first+cumsum(lengths)],stop);
            [~,~,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,state.CurrentSlot);
            dl=double(partition.DLSymbolAllocation); ul=double(partition.ULSymbolAllocation);
            duplexMode=upper(strtrim(string(sixgr.util.structGet( ...
                partition,'DuplexMode',''))));
            completed=struct('ID',{},'Kind',{},'UE',{},'Context',{},'Planes',{});
            % A slot is committed only after every producer has prepared its
            % contributions. Symbol boundaries preserve TDD guard intervals.
            for symbol=0:symbols-1
                if obj.Events.NextSampleIndex>=stop, break; end
                % A same-direction region may have been consumed in one
                % batch through several OFDM symbols (and through the TDD
                % guard interval).  A decision at that region boundary can
                % also retarget the reciprocal link before control returns
                % here.  Never revisit the direction associated with a
                % symbol whose complete sample interval is already in the
                % past: doing so can reverse the link a second time without
                % any newly consumed guard samples.
                if obj.Events.NextSampleIndex>=boundaries(symbol+2)
                    continue;
                end
                inDL=symbol>=dl(1) && symbol<sum(dl);
                inUL=symbol>=ul(1) && symbol<sum(ul);
                if xor(inDL,inUL)
                    direction="DL"; if inUL, direction="UL"; end
                    obj.retarget(direction);
                end
                % The physical channel/RF/noise owners are retained stream
                % processors and are exactly chunk invariant.  Do not split
                % a same-direction TDD region at every OFDM symbol: the
                % event runtime below already stops at every observation or
                % decision deadline.  Keep the DL-to-UL boundary explicit
                % (including its guard symbols) so reciprocal retargeting
                % still occurs at the first authorized symbol.
                regionStop=localPhysicalDirectionRegionStop( ...
                    symbol,boundaries,dl,ul,duplexMode);
                while obj.Events.NextSampleIndex<regionStop
                    % A received DCI or HARQ result can change contributions
                    % after a boundary inside this symbol. Committing the
                    % entire symbol first falsely locks that future interval.
                    next=obj.Events.nextEventSample(regionStop);
                    for node=obj.Nodes
                        if ~endsWith(node.ID,"_rx")
                            obj.Events.commitTransmissionsThrough(node.ID,next);
                        end
                    end
                    event=obj.Events.advanceUntilEvent(regionStop);
                    for item=event.Completed
                        k=find(string({obj.Pending.ID})==item.ID,1);
                        if isempty(k), error('sixgr:truth:UnknownSharedObservation','No prepared receiver owns this completion.'); end
                        obj.Pending(k).Planes(end+1)=rmfield(item,'ID');
                        if obj.Pending(k).Kind=="PDCCH"
                            control=find(cellfun(@(r)r.ObservationID==item.ID && ...
                                r.TransmitterID==item.ReceiverID,obj.ScheduledControlRegistrations));
                            if ~isempty(control)
                                assert(isscalar(control),'sixgr:truth:DuplicateScheduledPDCCHGrant','A transmitted prefix has one owner.');
                                r=obj.ScheduledControlRegistrations{control};
                                assert(isempty(r.TransmitObservation) && item.Observation.isComplete() && ...
                                    item.Observation.StartSample==r.StartSample && ...
                                    item.Observation.EndSampleExclusive==r.EndSampleExclusive && ...
                                    r.EndSampleExclusive==obj.Events.NextSampleIndex, ...
                                    'sixgr:truth:ScheduledPDCCHTransmitClockMismatch','Retain the actual complete gNB TX prefix once.');
                                r.TransmitObservation=item.Observation;
                                r.AvailableAtSample=obj.Events.NextSampleIndex;
                                obj.ScheduledControlRegistrations{control}=r;
                                commandContext=obj.Pending(k).Context;
                                if isfield(commandContext,'ScheduledULHARQConfig')
                                    state=sixgr.truth.commitSharedULHARQCommand( ...
                                        state,commandContext.ScheduledULHARQConfig,r.Binding.Grant);
                                end
                            end
                        end
                        if obj.Pending(k).Kind=="CSIRS" && ...
                                string(item.ReceiverID)==string(obj.Pending(k).Context.TransmitterPlane)
                            % A gNB knows its own completed reference TX at
                            % the TX boundary. A UE may need additional RX
                            % samples for timing acquisition; neither that
                            % later window nor UE decoding success can
                            % determine whether the reference was emitted.
                            p=obj.Pending(k);
                            componentID=string(p.Context.ComponentID);
                            prior=find(string({obj.CSIRSTransmissions.ComponentID})==componentID);
                            txObservation=item.Observation;
                            prepared=p.Context.Prepared;
                            assert(txObservation.isComplete() && ...
                                txObservation.StartSample==prepared.TransmitStartSample && ...
                                txObservation.EndSampleExclusive==prepared.TransmitStartSample+prepared.NumSamples && ...
                                txObservation.EndSampleExclusive==obj.Events.NextSampleIndex, ...
                                'sixgr:truth:InvalidPhysicalCSIRSTransmissionClock', ...
                                'Commit CSI-RS TX evidence at its actual completed shared-clock TX boundary.');
                            if isempty(prior)
                                txSamples=txObservation.readComplete();
                                firstActive=find(any(txSamples~=0,2),1,'first');
                                assert(~isempty(firstActive), ...
                                    'sixgr:truth:IncompletePhysicalCSIRSTransmission', ...
                                    'CSI-RS TX evidence requires an executed nonzero gNB observation.');
                                reference=prepared.ReferenceIdentity;
                                csirsEvent=prepared.Tx.CSIRSRuntimeEvent;
                                config=p.Context.Config;
                                resourceMaps=csirsEvent.ResourceEvents;
                                logicalResources=sixgr.util.structGet(prepared.Tx.CSIRSInfo,'Resources',struct([]));
                                if isempty(logicalResources)
                                    % The singleton producer retains these original
                                    % arrays directly, rather than a Resources list.
                                    logicalResources=struct('ResourceID',prepared.Tx.CSIRSInfo.ResourceID, ...
                                        'Indices',prepared.Tx.CSIRSIndices,'Symbols',prepared.Tx.CSIRSSymbols);
                                end
                                for resourceOrdinal=1:numel(resourceMaps)
                                    logicalResource=logicalResources([logicalResources.ResourceID]==resourceMaps(resourceOrdinal).ResourceID);
                                    assert(isscalar(logicalResource), ...
                                        'sixgr:truth:CSIRSExecutedResourceIdentity', ...
                                        'Every executed CSI-RS map needs its original logical pilot identity.');
                                    resourceMaps(resourceOrdinal).LogicalPilotIndices=logicalResource.Indices;
                                    resourceMaps(resourceOrdinal).LogicalPilotSymbols=logicalResource.Symbols;
                                end
                                carrier=prepared.Carrier;
                                carrierIdentity=struct('NSizeGrid',carrier.NSizeGrid,'NStartGrid',carrier.NStartGrid, ...
                                    'SubcarrierSpacing',carrier.SubcarrierSpacing,'CyclicPrefix',string(carrier.CyclicPrefix), ...
                                    'NSlot',carrier.NSlot,'NFrame',carrier.NFrame);
                                obj.CSIRSTransmissions(end+1)=struct( ...
                                    'ComponentID',componentID,'SignalFamily',"CSI-RS", ...
                                    'ServingCell',double(p.Context.ServingCell), ...
                                    'Slot',double(p.Context.Slot), ...
                                    'FirstActiveSample',double(txObservation.StartSample+firstActive-1), ...
                                    'CommittedAtSample',double(obj.Events.NextSampleIndex), ...
                                    'EndSampleExclusive',double(txObservation.EndSampleExclusive), ...
                                    'SampleRateHz',double(obj.SampleRateHz), ...
                                    'PhysicalConfigurationEpoch',double(obj.Physical.ConfigurationEpoch), ...
                                    'ResourceSetID',double(reference.ResourceSetID), ...
                                    'ResourceIDs',string(reference.ResourceIDs), ...
                                    'WaveformMappedRE',double(csirsEvent.NRE), ...
                                    'ReferenceConfiguration',config.phy.csirs, ...
                                    'ReportConfiguration',config.phy.csi.reportConfiguration, ...
                                    'FrameIdentity',config.phy.frame.DefaultIdentity, ...
                                    'ExecutedResourceMaps',resourceMaps, ...
                                    'TXAmplitudeScale',prepared.PowerContext.AmplitudeScale, ...
                                    'TransmitterID',extractBefore(string(item.ReceiverID),':tx'), ...
                                    'TransmitStartSample',txObservation.StartSample, ...
                                    'TransmitObservationSHA256',txObservation.sampleHash(), ...
                                    'CarrierIdentity',carrierIdentity, ...
                                    'PopulationIdentity',sixgr.util.structGet(p.Context,'PopulationIdentity',struct()));
                            else
                                assert(isscalar(prior) && ...
                                    obj.CSIRSTransmissions(prior).CommittedAtSample==obj.Events.NextSampleIndex && ...
                                    obj.CSIRSTransmissions(prior).EndSampleExclusive==txObservation.EndSampleExclusive, ...
                                    'sixgr:truth:DuplicatePhysicalCSIRSTransmission', ...
                                    'UE observations of one cell-common CSI-RS must share the same actual TX completion.');
                            end
                        end
                    end
                    previousCount=numel(completed);
                    done=find(arrayfun(@(x)numel(x.Planes)== ...
                        localExpectedSharedPlaneCount(x),obj.Pending));
                    captureDone=done(string({obj.Pending(done).Kind})=="ContinuousTxIQ");
                    if ~isempty(captureDone)
                        if obj.Events.NextSampleIndex~=stop
                            error('sixgr:truth:ContinuousTxIQPrematureCompletion', ...
                                'A full-slot transmitter capture completed before the slot boundary.');
                        end
                        obj.appendContinuousTxIQ(obj.Pending(captureDone),first,stop);
                    end
                    for k=done
                        p=obj.Pending(k);
                        if p.Kind=="ContinuousTxIQ"
                            continue;
                        end
                        if p.Kind=="Msg1TX"
                            proof=sixgr.truth.validateMsg1TransmissionCompletion(obj,p);
                            assert(~any(cellfun(@(r)r.ComponentID==p.ID,obj.Msg1TXCompletions)), ...
                                'sixgr:truth:DuplicateMsg1Transmission','Commit original Msg1 active support only once.');
                            obj.Msg1TXCompletions{end+1,1}=proof;
                        end
                        if p.Kind=="CellSSBTX"
                            found=find(string({obj.CellSSBRegistrations.ComponentID})==p.Context.ComponentID);
                            assert(isscalar(found),'sixgr:truth:CellSSBCompletionMismatch', ...
                                'A cell SSB completion requires its original registration.');
                            proof=localVerifyCellSSBCompletion(obj,p,obj.CellSSBRegistrations(found).PreparedSHA256);
                            prepared=p.Context.Prepared; observation=p.Planes.Observation;
                            assert(~any(string({obj.SSBTransmissions.ComponentID})==p.Context.ComponentID), ...
                                'sixgr:truth:CellSSBCompletionMismatch','Commit each original cell SSB once.');
                            obj.SSBTransmissions(end+1)=struct('ComponentID',p.Context.ComponentID, ...
                                'ServingCell',p.Context.ServingCell,'AbsoluteSlot',p.Context.Slot-1, ...
                                'StartSample',observation.StartSample,'EndSampleExclusive',observation.EndSampleExclusive, ...
                                'SampleRateHz',obj.SampleRateHz,'PhysicalConfigurationEpoch',obj.Physical.ConfigurationEpoch, ...
                                'CommittedAtSample',obj.Events.NextSampleIndex, ...
                                'PreparedSampleSHA256',sixgr.phy.waveform.WaveformHash.runtimeArray(prepared.TransmitSamples), ...
                                'TransmitSampleSHA256',observation.sampleHash(),'ExecutionProof',proof);
                            completed(end+1)=struct('ID',p.ID,'Kind',p.Kind,'UE',0, ...
                                'Context',p.Context,'Planes',p.Planes); %#ok<AGROW>
                            continue;
                        end
                        if p.Kind=="CellSIB1TX"
                            assert(numel(p.Planes)==1 && ...
                                string(p.Planes.ReceiverID)==p.Context.TransmitterPlane, ...
                                'sixgr:truth:SIB1TransmitObservationIdentity', ...
                                'A cell transmission commits from its own TX observation, not any UE result.');
                            observation=p.Planes.Observation;
                            prepared=p.Context.Prepared; si=prepared.Tx;
                            proof=sixgr.truth.verifySIB1TransmissionCompletion(obj,p);
                            assert(isa(si.PDSCHTx.ResourcePlan,'sixgr.pdsch.PDSCHResourcePlan') && ...
                                string(si.PDSCHTx.ContractVersion)=="ExplicitPDSCHTransmitter/v1", ...
                                'sixgr:truth:SIB1CanonicalTXRequired', ...
                                'Retain the exact canonical SI data/resource indices, not legacy aliases.');
                            assert(observation.isComplete() && ...
                                observation.StartSample==prepared.TransmitStartSample && ...
                                observation.EndSampleExclusive==prepared.TransmitStartSample+prepared.NumSamples && ...
                                observation.SampleRateHz==obj.SampleRateHz && ...
                                observation.EndSampleExclusive==obj.Events.NextSampleIndex && ...
                                ~any(string({obj.SIB1Transmissions.ComponentID})==p.Context.ComponentID), ...
                                'sixgr:truth:SIB1TransmitCompletionClock', ...
                                'Commit each actual SI TX once at its physical completed boundary.');
                            obj.SIB1Transmissions(end+1)=struct( ...
                                'ComponentID',p.Context.ComponentID, ...
                                'ServingCell',p.Context.ServingCell, ...
                                'SSBIndex',si.SIB1SpatialMapping.SSBIndex, ...
                                'AbsoluteSlot',si.SIB1AbsoluteSlot, ...
                                'StartSample',observation.StartSample, ...
                                'EndSampleExclusive',observation.EndSampleExclusive, ...
                                'SampleRateHz',obj.SampleRateHz, ...
                                'PhysicalConfigurationEpoch',double(obj.Physical.ConfigurationEpoch), ...
                                'CommittedAtSample',obj.Events.NextSampleIndex, ...
                                'TransmitSampleSHA256',observation.sampleHash(), ...
                                'PreparedSampleSHA256',sixgr.phy.waveform.WaveformHash.runtimeArray(prepared.TransmitSamples), ...
                                'SIB1PayloadHash',string(si.SIB1PayloadHash), ...
                                'PrecoderMatrixSHA256',string(si.SIB1SpatialMapping.PrecoderMatrixSHA256), ...
                                'PDCCHDataIndicesOneBased',si.PDCCHTx.PDCCHInd, ...
                                'PDCCHDMRSIndicesOneBased',si.PDCCHTx.DMRSInd, ...
                                'PDSCHDataREIndicesZeroBased',si.PDSCHTx.ResourcePlan.DataIndices, ...
                                'PDSCHDMRSREIndicesZeroBased',si.PDSCHTx.DMRSIndices,'ExecutionProof',proof);
                            % Preserve original TX buffers/segments for the
                            % publication callback; no receiver is invented.
                            completed(end+1)=struct('ID',p.ID,'Kind',p.Kind,'UE',p.UE, ...
                                'Context',p.Context,'Planes',p.Planes); %#ok<AGROW>
                            continue;
                        end
                        if p.Kind=="TransferredPUCCHObservation"
                            obj.ControlObservationDispositions(end+1)=struct('ID',p.ID,'UE',p.UE, ...
                                'Reason',"feedback_transferred_to_PUSCH_no_PUCCH_transmitted", ...
                                'CompletedAtSample',obj.Events.NextSampleIndex, ...
                                'TransferProof',p.Context.TransferProof);
                            continue;
                        end
                        if p.Kind=="PUCCH"
                            assert(isfield(p.Context,'Prepared'),'sixgr:truth:UnencodedPUCCHObservation', ...
                                'A received PUCCH window cannot become a trial without actual prior encoding.');
                        end
                        if p.Kind=="CSIRS"
                            componentID=string(p.Context.ComponentID);
                            prior=find(string({obj.CSIRSTransmissions.ComponentID})==componentID);
                            assert(isscalar(prior) && ...
                                obj.CSIRSTransmissions(prior).CommittedAtSample== ...
                                    obj.CSIRSTransmissions(prior).EndSampleExclusive && ...
                                obj.CSIRSTransmissions(prior).CommittedAtSample<=obj.Events.NextSampleIndex, ...
                                'sixgr:truth:IncompletePhysicalCSIRSTransmission', ...
                                'CSI-RS reception requires the earlier actual TX-boundary commit; do not backdate it at RX completion.');
                        end
                        % Preserve the registered physical observation ID.
                        % Exporters and receiver dispositions must not invent
                        % an identity after completion or borrow a TX ID.
                        if any(p.Kind==["PBCH","SIB1"])
                            receipt=localBroadcastCompletionReceipt(p);
                            assert(~any(cellfun(@(r)r.ID==receipt.ID,obj.BroadcastCompletions)), ...
                                'sixgr:truth:DuplicateBroadcastCompletion','A capture completes exactly once.');
                            obj.BroadcastCompletions{end+1,1}=receipt;
                        end
                        completed(end+1)=struct('ID',p.ID,'Kind',p.Kind,'UE',p.UE,'Context',p.Context,'Planes',p.Planes); %#ok<AGROW>
                        if p.Kind=="PUSCHReceiveOnly"
                            obj.PUSCHReceiveOnlyCompletions{end+1,1}=completed(end);
                        end
                    end
                    obj.Pending(done)=[];
                    % Receiver completions at the deadline precede expiry.
                    for id=reshape(event.Decisions,1,[])
                        k=find(string({obj.Decisions.ID})==id,1);
                        if isempty(k), error('sixgr:truth:UnknownSharedDecision','No receiver owns this timer.'); end
                        d=obj.Decisions(k); obj.Decisions(k)=[];
                        if d.Kind=="ULTransmitBoundary"
                            sixgr.truth.CoupledWaveformStream.assertULTransmitTime( ...
                                cfg,obj.Events.NextSampleIndex,obj.SampleRateHz);
                            obj.retarget("UL",d.UE);
                            continue;
                        end
                        if d.Kind=="DataTX"
                            assert(~drainingTail,'sixgr:truth:ReceiveTailContainsFutureDataTX', ...
                                'Receive-tail draining cannot count a new data transmission.');
                            assert(obj.Events.NextSampleIndex==d.Context.FirstActiveSample+1, ...
                                'sixgr:truth:DataTXCommitClockMismatch', ...
                                'TX evidence belongs to the first actually consumed active sample.');
                            obj.DataTransmissions(end+1)=struct( ...
                                'Identity',d.Context.TransmissionIdentity, ...
                                'FirstActiveSample',d.Context.FirstActiveSample, ...
                                'CommittedAtSample',obj.Events.NextSampleIndex, ...
                                'WaveformToElementMatrix',d.Context.WaveformToElementMatrix, ...
                                'TransmitOccupancy',d.Context.TransmitOccupancy);
                        end
                        if d.Kind=="PUCCHTX"
                            assert(~drainingTail,'sixgr:truth:ReceiveTailContainsFuturePUCCHTX', ...
                                'Receive-tail draining cannot start a future PUCCH transmission.');
                            assert(obj.Events.NextSampleIndex==d.Context.FirstActiveSample+1, ...
                                'sixgr:truth:PUCCHTXCommitClockMismatch', ...
                                'PUCCH TX evidence belongs to the first consumed active sample.');
                            assert(~any(arrayfun(@(r)r.Identity.TransmissionID== ...
                                d.Context.TransmissionIdentity.TransmissionID,obj.PUCCHTransmissions)), ...
                                'sixgr:truth:DuplicatePhysicalPUCCHTX','A physical PUCCH starts once.');
                            obj.PUCCHTransmissions(end+1)=struct( ...
                                'Identity',d.Context.TransmissionIdentity, ...
                                'FirstActiveSample',d.Context.FirstActiveSample, ...
                                'CommittedAtSample',obj.Events.NextSampleIndex, ...
                                'WaveformToElementMatrix',d.Context.WaveformToElementMatrix, ...
                                'TransmitOccupancy',d.Context.TransmitOccupancy);
                        end
                        completed(end+1)=struct('ID',d.ID,'Kind',d.Kind,'UE',d.UE,'Context',d.Context,'Planes',struct([])); %#ok<AGROW>
                    end
                    if ~isempty(onReceived) && numel(completed)>previousCount
                        states=obj.Physical.channelStates();
                        for index=1:numel(states)
                            state=sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state,states{index});
                        end
                        % React before the next physical interval. A receiver
                        % callback never runs after future samples have been
                        % consumed, even if its window ends within a slot.
                        state=onReceived(state,completed(previousCount+1:end));
                        if nargout<2
                            % The callback has consumed/exported the exact
                            % observations. Do not pin their IQ, prepared
                            % waveforms and full channel coefficients until
                            % slot end when no completion output was asked
                            % for. Explicit two-output callers keep the
                            % original capture contract unchanged.
                            completed=completed([]);
                        end
                    end
                    % These loop temporaries otherwise survive while the
                    % next (potentially full-slot) physical interval is
                    % allocated. Pending observations, state and requested
                    % returned completions retain their own ownership.
                    clear event item p d r commandContext prepared txObservation txSamples
                end
            end
            states=obj.Physical.channelStates();
            for k=1:numel(states)
                state=sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(state,states{k});
            end
            % Completed components no longer need a second copy of their IQ.
            keep=arrayfun(@(x)x.Start+size(x.Samples,1)>stop,obj.Components);
            obj.Components=obj.Components(keep);
        end
        function state=channelState(obj,ue,direction)
            link=obj.linkForUE(ue,direction); states=obj.Physical.channelStates();
            state=states{find(string({obj.Links.ID})==link.ID,1)};
        end

        function result=finalizeContinuousTxIQCapture(obj,expectedEndSample,expectedSlotCount)
            if isempty(obj.TxIQRecorder)
                error('sixgr:truth:ContinuousTxIQRecorderMissing', ...
                    'Continuous Tx-IQ capture was not enabled for this shared stream.');
            end
            result=obj.TxIQRecorder.finalize(expectedEndSample,expectedSlotCount);
        end
    end
    methods (Access=private)
        function appendContinuousTxIQ(obj,captures,first,stop)
            txNodes=obj.Nodes(~endsWith(string({obj.Nodes.ID}),"_rx"));
            if numel(captures)~=numel(txNodes)
                error('sixgr:truth:ContinuousTxIQEndpointCoverage', ...
                    'Every physical transmitter requires one complete slot observation.');
            end
            waveforms=cell(numel(txNodes),1);
            replayEvidence=repmat(struct('Replay',struct()),numel(txNodes),1);
            captureIDs=string(arrayfun(@(x)string(x.Context.EndpointID),captures));
            for index=1:numel(txNodes)
                node=txNodes(index);
                hit=find(captureIDs==string(node.ID));
                if numel(hit)~=1
                    error('sixgr:truth:ContinuousTxIQEndpointCoverage', ...
                        'Endpoint %s has %d full-slot captures.',string(node.ID),numel(hit));
                end
                plane=captures(hit).Planes;
                if numel(plane)~=1 || string(plane.ReceiverID)~=string(node.ID)+":tx" || ...
                        plane.Observation.StartSample~=first || ...
                        plane.Observation.EndSampleExclusive~=stop
                    error('sixgr:truth:ContinuousTxIQObservationScope', ...
                        'Endpoint %s capture does not match its exact TX observation plane.', ...
                        string(node.ID));
                end
                samples=plane.Observation.readComplete();
                localAssertContinuousTxRFSegments( ...
                    samples,plane.Segments,string(node.ID),first,stop);
                waveforms{index}=samples;
                replayEvidence(index).Replay=struct( ...
                    'RFOutputWaveformSHA256',char(sixgr.rf.waveformSHA256(samples)));
            end
            nodes=repmat(struct('ID',"",'Direction',"",'NumPorts',NaN), ...
                numel(txNodes),1);
            for index=1:numel(txNodes)
                nodes(index).ID=string(txNodes(index).ID);
                nodes(index).Direction=string(txNodes(index).Direction);
                nodes(index).NumPorts=double(txNodes(index).NumAntennas);
            end
            obj.TxIQRecorder.appendBatch(nodes,waveforms,replayEvidence,first,stop);
        end

        function registerNode(obj,id,cfg,direction,nAnt,isTX)
            k=find(string({obj.Nodes.ID})==id,1);
            rf=sixgr.util.structGet(cfg,'rf',struct());
            if ~isempty(k)
                if obj.Nodes(k).NumAntennas~=nAnt || ~isequaln(obj.Nodes(k).RF,rf)
                    error('sixgr:truth:InconsistentPhysicalNode','Every link sharing a radio must agree on its RF and antenna layout.');
                end
                if isTX
                    obj.Physical.validateTransmitterInstallation(id,cfg,direction,nAnt);
                else
                    obj.Physical.validateReceiverInstallation(id,cfg,direction,nAnt);
                end
                return;
            end
            if isTX, obj.Physical.addTransmitter(id,cfg,direction,nAnt,false);
            else, obj.Physical.addReceiver(id,cfg,direction,nAnt,false); end
            obj.Nodes(end+1)=struct('ID',id,'Direction',string(direction),'NumAntennas',nAnt,'RF',rf);
        end
        function link=linkForUE(obj,ue,direction)
            choices=find([obj.Links.UE]==ue);
            if numel(choices)>1
                choices=choices(string({obj.Links(choices).Direction})==direction);
            end
            if numel(choices)~=1, error('sixgr:truth:AmbiguousSharedLink','The prepared receiver needs one physical serving link.'); end
            link=obj.Links(choices);
        end
        function retarget(obj,direction,ue)
            if nargin<3, ue=[]; end
            for k=1:numel(obj.Links)
                link=obj.Links(k);
                if ~isempty(ue) && link.UE~=ue, continue; end
                if sum([obj.Links.UE]==link.UE)>1 || link.Direction==direction, continue; end
                if direction=="UL"
                    obj.Physical.retargetTDDLink(link.ID,"ue_"+link.UE,"gnb_"+link.Cell+"_rx",link.ULConfig);
                else
                    obj.Physical.retargetTDDLink(link.ID,"gnb_"+link.Cell,"ue_"+link.UE+"_rx",link.DLConfig);
                end
                obj.Links(k).Direction=direction;
            end
        end
    end
end

function stop=localPhysicalDirectionRegionStop(symbol,boundaries,dl,ul,duplexMode)
% Batch only contiguous TDD samples that keep the same physical direction.
% Observation and decision boundaries are still enforced by
% WaveformEventRuntime.nextEventSample inside the caller.
stop=boundaries(symbol+2);
if duplexMode~="TDD"
    return;
end
inDL=symbol>=dl(1) && symbol<sum(dl);
inUL=symbol>=ul(1) && symbol<sum(ul);
if ~xor(inDL,inUL)
    return;
end
direction="DL";
if inUL
    direction="UL";
end
numSymbols=numel(boundaries)-1;
for nextSymbol=symbol+1:numSymbols-1
    nextDL=nextSymbol>=dl(1) && nextSymbol<sum(dl);
    nextUL=nextSymbol>=ul(1) && nextSymbol<sum(ul);
    if xor(nextDL,nextUL)
        nextDirection="DL";
        if nextUL
            nextDirection="UL";
        end
        if nextDirection~=direction
            % Stop at the beginning of the opposite-direction symbol.  Any
            % intervening guard symbols remain actual zero-input samples on
            % the outgoing reciprocal channel, as before.
            stop=boundaries(nextSymbol+1);
            return;
        end
    end
    stop=boundaries(nextSymbol+2);
end
end

function count=localExpectedSharedPlaneCount(pending)
if any(string(pending.Kind)==["ContinuousTxIQ","CellSIB1TX","CellSSBTX","Msg1TX"])
    count=1;
elseif any(string(pending.Kind)==["PUSCHReceiveOnly","SIB1"])
    count=2; % Actual pre/post RF only: no invented UE transmitter plane.
else
    count=3+double(isfield(pending.Context,'DesiredReferencePlane'));
    if isfield(pending.Context,'CSIRSPortReferencePlanes')
        count=count+numel(pending.Context.CSIRSPortReferencePlanes)+2;
    end
end
end

function receipt=localBroadcastCompletionReceipt(item)
assert(any(string(item.Kind)==["PBCH","SIB1"]),'sixgr:truth:BroadcastCompletedCaptureMismatch', ...
    'Only original acquisition/SI captures use this completion contract.');
planes=item.Planes; hit=find(endsWith(string({planes.ReceiverID}),':post_rf'));
assert(isscalar(hit),'sixgr:truth:BroadcastCompletedCaptureMismatch','Exactly one original post-RF plane is required.');
observation=planes(hit).Observation;
assert(observation.isComplete(),'sixgr:truth:BroadcastCompletedCaptureMismatch','A partial capture cannot be committed.');
binding="";
if string(item.Kind)=="SIB1"
    assert(all(isfield(item.Context,{'ReceiverConfig','ReceivedMIBBinding', ...
        'AbsoluteMonitoringSlot','ReceiveStartSample','ReceiveEndSampleExclusive', ...
        'MonitoringOccasion','MonitoringWindowSHA256','MonitoringPlanSHA256','ArmedAtSample', ...
        'ReceiveOnly','TransmissionScheduled'})) && ...
        islogical(item.Context.ReceiveOnly) && isscalar(item.Context.ReceiveOnly) && item.Context.ReceiveOnly && ...
        islogical(item.Context.TransmissionScheduled) && isscalar(item.Context.TransmissionScheduled) && ~item.Context.TransmissionScheduled, ...
        'sixgr:truth:BroadcastCompletedCaptureMismatch','SI completion requires its original receive-only obligation.');
    receiverContext=struct('ServingCell',sixgr.util.structGet(item.Context,'ServingCell',[]), ...
        'ReceiverConfig',item.Context.ReceiverConfig, ...
        'AbsoluteMonitoringSlot',item.Context.AbsoluteMonitoringSlot, ...
        'ReceiveStartSample',item.Context.ReceiveStartSample, ...
        'ReceiveEndSampleExclusive',item.Context.ReceiveEndSampleExclusive, ...
        'MonitoringOccasion',item.Context.MonitoringOccasion, ...
        'MonitoringWindowSHA256',item.Context.MonitoringWindowSHA256, ...
        'MonitoringPlanSHA256',item.Context.MonitoringPlanSHA256, ...
        'ArmedAtSample',item.Context.ArmedAtSample, ...
        'ReceivedMIBDeliverySHA256',item.Context.ReceivedMIBBinding.DeliverySHA256);
else
    receiverContext=struct('ServingCell',sixgr.util.structGet(item.Context,'ServingCell',[]), ...
        'ReceiverConfig',sixgr.util.structGet(item.Context,'Prepared.ReceiverConfig',struct()), ...
        'TrackingOnly',sixgr.util.structGet(item.Context,'TrackingOnly',false), ...
        'AcquisitionMIBBinding',sixgr.util.structGet(item.Context,'AcquisitionMIBBinding',[]));
    if isfield(item.Context,'AcquisitionWindowContract')
        contract=item.Context.AcquisitionWindowContract;
        p=item.Context.Prepared;
        sixgr.phy.frame.SSBAcquisitionWindow.validate(contract,p.ReceiverConfig, ...
            p.SampleRateHz,double(p.BroadcastStartSample),double(p.NumSamples));
        assert(observation.StartSample==contract.StartSample && ...
            observation.EndSampleExclusive==contract.EndSampleExclusive, ...
            'sixgr:truth:BroadcastCompletedCaptureMismatch', ...
            'Initial MIB authority belongs to its original complete receiver search window.');
        receiverContext.AcquisitionWindowContract=contract;
    end
    % Authenticate the original armed acquisition generation as well as IQ.
    % Comparing two caller-supplied copies at completion is not sufficient:
    % both could have been replaced after reacquisition. Hash the complete
    % retained binding, not just its caller-supplied digest fields.
end
if isfield(item.Context,'ReceivedMIBBinding')
    binding=string(item.Context.ReceivedMIBBinding.BindingSHA256);
end
receipt=struct('ID',string(item.ID),'UE',double(item.UE),'Kind',string(item.Kind), ...
    'ReceiverID',string(planes(hit).ReceiverID),'StartSample',observation.StartSample, ...
    'EndSampleExclusive',observation.EndSampleExclusive,'SampleRateHz',observation.SampleRateHz, ...
    'NumReceiveAntennas',observation.NumReceiveAntennas,'OriginalSampleSHA256',observation.sampleHash(), ...
    'ReceivedMIBBindingSHA256',binding, ...
    'OriginalReceiverContextSHA256', ...
    sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(receiverContext)));
end

function localAssertContinuousTxRFSegments(samples,segments,nodeID,first,stop)
if isempty(segments)
    error('sixgr:truth:ContinuousTxIQRFSegmentsMissing', ...
        'Endpoint %s has no physical TX-RF execution segments.',nodeID);
end
if isstruct(segments)
    segments=num2cell(segments);
end
starts=zeros(numel(segments),1);
stops=zeros(numel(segments),1);
for index=1:numel(segments)
    segment=segments{index};
    starts(index)=double(segment.StartSample);
    stops(index)=double(segment.EndSampleExclusive);
    if starts(index)<first || stops(index)>stop || stops(index)<=starts(index)
        error('sixgr:truth:ContinuousTxIQRFSegmentScope', ...
            'Endpoint %s has a TX-RF segment outside [%d,%d).',nodeID,first,stop);
    end
    executions=sixgr.util.structGet(segment,'Execution.TX',struct([]));
    hit=find(string({executions.ID})==nodeID);
    if numel(hit)~=1
        error('sixgr:truth:ContinuousTxIQRFSegmentIdentity', ...
            'Endpoint %s lacks one exact TX-RF replay for [%d,%d).', ...
            nodeID,starts(index),stops(index));
    end
    expected=string(sixgr.util.structGet( ...
        executions(hit).Replay,'RFOutputWaveformSHA256',''));
    indices=(starts(index)-first+1):(stops(index)-first);
    observed=string(sixgr.rf.waveformSHA256(samples(indices,:)));
    if strlength(expected)~=64 || observed~=expected
        error('sixgr:truth:ContinuousTxIQRFSegmentHashMismatch', ...
            'Endpoint %s samples differ from TX-RF replay on [%d,%d).', ...
            nodeID,starts(index),stops(index));
    end
end
if starts(1)~=first || stops(end)~=stop || ...
        any(starts(2:end)~=stops(1:end-1))
    error('sixgr:truth:ContinuousTxIQRFSegmentGap', ...
        'Endpoint %s TX-RF replay does not cover [%d,%d) contiguously.', ...
        nodeID,first,stop);
end
end

function tf=localFixedDLAtSample(cfg,sample,fs)
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
assert(tc==fix(tc),'sixgr:truth:NonIntegralSchedulerSample','The physical sample clock must preserve integer Tc.');
carrier=sixgr.phy.grid.makeCarrier(cfg);
t=sixgr.phy.frame.AbsoluteTime.fromTicks(int64(sample)*int64(tc));
% An advanced transmission may begin inside a symbol. Inspect the actual
% containing symbol; the three-output overload requires exact alignment.
[frame,slot,symbol,~]=t.toNumerology(log2(double(carrier.SubcarrierSpacing)/15));
absoluteSlot=double(frame)*carrier.SlotsPerFrame+double(slot);
[~,~,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,absoluteSlot+1);
dl=partition.DLSymbolAllocation; ul=partition.ULSymbolAllocation;
inDL=double(symbol)>=dl(1) && double(symbol)<sum(dl);
inUL=double(symbol)>=ul(1) && double(symbol)<sum(ul);
tf=inDL && ~inUL;
end

function sample=localTicksSample(ticks,fs)
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/fs;
if tc~=fix(tc) || rem(ticks,int64(tc))~=0
    error('sixgr:truth:NonIntegralSchedulerSample','Receiver boundary is off the physical sample clock.');
end
sample=double(idivide(ticks,int64(tc)));
end

function ch=localMaterialize(cfg,ch,info)
% The owner sums already projected physical-element IQ, not signal ports.
% A one-column layout probe can suppress a rectangular port-to-element map
% and incorrectly bind the CDL endpoint to a CSI port/layer count.
u=cfg.lls6g.userContext;
tx=u.RuntimeServingBSAntenna; txMeta=u.RuntimeServingBSAntennaMeta;
rx=u.RuntimeUEAntenna; rxMeta=u.RuntimeUEAntennaMeta;
if string(ch.Direction)=="UL"
    [tx,rx]=deal(rx,tx); [txMeta,rxMeta]=deal(rxMeta,txMeta);
end
nt=double(tx.NumElements); nr=double(rx.NumElements);
validateattributes(nt,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(nr,{'numeric'},{'scalar','integer','positive','finite'});
[tx,txMeta]=localPhysicalArrayView(tx,txMeta,nt);
[rx,rxMeta]=localPhysicalArrayView(rx,rxMeta,nr);
ch=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    ch,cfg,complex(zeros(1,nt)),struct('OFDM',info), ...
    'NumTxAnt',nt,'NumRxAnt',nr, ...
    'TransmitAntennaRuntime',tx,'TransmitAntennaMeta',txMeta, ...
    'ReceiveAntennaRuntime',rx,'ReceiveAntennaMeta',rxMeta);
end

function [digest,plan,period]=localCellBroadcastContract(cfg)
% Resolve actual TX policy; never hash UE pathloss, RNTI, received tracking
% state or traffic as if these were cell-common broadcast configuration.
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
carrier=sixgr.phy.grid.makeCarrier(cfg);
enabled=logical(sixgr.util.structGet(cfg,'phy.ssb.enable',false));
plan=sixgr.phy.frame.CommonDLResourcePlan(cfg); period=Inf;
carrierFields=struct();
for name=["NCellID","NSizeGrid","NStartGrid","SubcarrierSpacing","CyclicPrefix"]
    carrierFields.(name)=carrier.(name);
end
contract=struct('SSBEnabled',enabled,'Carrier',carrierFields, ...
    'Frequency',sixgr.util.structGet(cfg,'frequency',struct()), ...
    'RF',sixgr.util.structGet(cfg,'rf',struct()));
if enabled
    assert(sixgr.util.structGet(cfg,'phy.ssb.halfFrameIndex',0)==0, ...
        'sixgr:truth:UnsupportedSharedSSBPhaseOrigin','Cell scheduling retains the supported frame-aligned phase-zero domain.');
    [resolved,power]=sixgr.rf.resolveSSBPowerContract(cfg);
    timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(resolved);
    period=double(timing.PeriodicityMs)*double(carrier.SlotsPerSubframe);
    assert(isfinite(period) && period>=double(carrier.SlotsPerFrame) && ...
        period==fix(period) && mod(period,double(carrier.SlotsPerFrame))==0, ...
        'sixgr:truth:UnsupportedSharedSSBPeriodOrigin', ...
        'This cell owner requires full-frame burst origins; half-frame scheduling is not silently approximated.');
    contract.SSB=sixgr.util.structGet(resolved,'phy.ssb',struct());
    contract.MIB=sixgr.util.structGet(resolved,'phy.mib',struct());
    contract.PBCH=sixgr.util.structGet(resolved,'phy.pbch',struct());
    contract.Power=power;
    contract.Burst=sixgr.phy.ia.SSBBurstPlan.fromConfig(resolved,timing);
    contract.InitialAccess=sixgr.util.structGet(resolved,'initial_access',struct());
    contract.PowerAndRF=sixgr.util.structGet(resolved,'powerAndRF',struct());
    contract.Integration=sixgr.util.structGet(resolved,'integration',struct());
    contract.SIB1=sixgr.util.structGet(resolved,'phy.sib1',struct());
    if logical(sixgr.util.structGet(resolved,'phy.sib1.enable',false))
        % Canonical semantic builder covers its actual RACH/RRC aliases,
        % without re-encoding a waveform or borrowing a UE's received tree.
        contract.SIB1Tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(resolved);
        contract.SIB1Occasions=plan.sib1TransmissionOccasions(0, ...
            max([plan.SIB1Slot0+plan.SIB1PeriodSlots,period])+1);
    end
end
digest=sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(contract));
end

function value=localCellSSBCaptureSubframes(cfg)
value=sixgr.util.structGet(cfg,'phy.ssb.pbchObservationSubframes', ...
    sixgr.util.structGet(cfg,'lls6g.control.pbchObservationSubframes',5));
validateattributes(value,{'numeric'},{'scalar','real','finite','integer','positive'});
value=double(value);
end

function proof=localVerifyCellSSBCompletion(owner,item,preparedHash)
id='sixgr:truth:CellSSBCompletionMismatch'; c=item.Context; p=c.Prepared;
assert(preparedHash==sixgr.phy.waveform.WaveformHash.bytes(getByteStreamFromArray(p)) && ...
    numel(item.Planes)==1 && string(item.Planes.ReceiverID)==c.TransmitterPlane, ...
    id,'Retain the original cell SSB preparation and TX plane.');
r=owner.Events.originalEnqueueReceipt("gnb_"+c.ServingCell,c.ComponentID);
assert(isequaln(r,c.EnqueueReceipt) && r.StartSample==p.BroadcastStartSample && ...
    r.EndSampleExclusive==p.BroadcastStartSample+p.NumSamples && ...
    r.ContractVersion=="sixgr.waveform.enqueued_component/v1" && ...
    r.Source=="original_event_runtime_accepted_component_not_physical_execution" && ...
    isequal(r.PhysicalExecutionPerformed,false) && r.ComponentID==c.ComponentID && ...
    r.SampleRateHz==p.SampleRateHz && r.NumTransmitAntennas==size(p.TransmitSamples,2) && ...
    r.NumericClass==string(class(p.TransmitSamples)) && ...
    r.OriginalSampleSHA256==sixgr.phy.waveform.WaveformHash.numeric(p.TransmitSamples), ...
    id,'Bind the original SSB component, not merely a completed aggregate window.');
o=item.Planes.Observation; segments=item.Planes.Segments;
assert(o.isComplete() && o.StartSample==r.StartSample && o.EndSampleExclusive==r.EndSampleExclusive && ...
    o.SampleRateHz==owner.SampleRateHz && owner.Events.NextSampleIndex==r.EndSampleExclusive && ...
    iscell(segments) && ~isempty(segments),id,'The original SSB transmit interval must complete on its physical clock.');
samples=o.readComplete(); cursor=r.StartSample; nonzero=0;
for n=1:numel(segments)
    s=segments{n}; e=s.Execution;
    found=find(cellfun(@(v)v.StartSample==s.StartSample && ...
        v.EndSampleExclusive==s.EndSampleExclusive,owner.Events.ExecutionTrace));
    assert(isscalar(found) && s.StartSample==cursor && s.EndSampleExclusive>cursor && ...
        s.EndSampleExclusive<=r.EndSampleExclusive && e.StartSample==s.StartSample && ...
        e.EndSampleExclusive==s.EndSampleExclusive && e.SampleRateHz==owner.SampleRateHz && ...
        e.ConfigurationEpoch==owner.Physical.ConfigurationEpoch && ...
        string(e.Source)=="composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf" && ...
        string(e.ApproximationMode)=="none",id,'Require original contiguous physical SSB execution.');
    original=owner.Events.ExecutionTrace{found}.Execution;
    assert(isequaln(e.ExecutedContributors,original.ExecutedContributors) && ...
        isequaln(e.TX,original.TX),id,'Do not substitute original contributor or RF receipts.');
    node=e.ExecutedContributors(string({e.ExecutedContributors.TransmitterID})==r.TransmitterID);
    assert(isscalar(node) && isequal(node.Receipt.CompleteContributorList,true) && ...
        node.Receipt.Schema=="consumed_waveform_components/v1" && ...
        node.Receipt.NonzeroIntervalSchema=="exact_absolute_component_nonzero_runs/v1" && ...
        node.Receipt.StartSample==cursor && node.Receipt.EndSampleExclusive==s.EndSampleExclusive && ...
        node.Receipt.SampleRateHz==p.SampleRateHz && node.CommittedThroughSample>=s.EndSampleExclusive, ...
        id,'An original complete contributor population is required.');
    components=node.Receipt.Components;
    component=components(string({components.ComponentID})==c.ComponentID);
    rows=(cursor-r.StartSample+1):(s.EndSampleExclusive-r.StartSample);
    part=p.TransmitSamples(rows,:); active=any(part~=0,2); edge=diff([false;active;false]);
    runs=[find(edge==1)-1 find(edge==-1)-1]+cursor;
    assert(isscalar(component) && component.OriginalSampleSHA256==r.OriginalSampleSHA256 && ...
        component.StartSample==cursor && component.EndSampleExclusive==s.EndSampleExclusive && ...
        component.NonzeroSampleCount==nnz(part) && component.NonzeroTimeSampleCount==nnz(active) && ...
        isequal(component.NonzeroIntervals,runs),id,'The original SSB component was cancelled, replaced or truncated.');
    tx=e.TX(string({e.TX.ID})==r.TransmitterID);
    assert(isscalar(tx) && string(tx.Replay.RFOutputWaveformSHA256)== ...
        string(sixgr.rf.waveformSHA256(samples(rows,:))),id,'Bind exact original aggregate post-TX-RF samples.');
    nonzero=nonzero+component.NonzeroSampleCount; cursor=s.EndSampleExclusive;
end
assert(cursor==r.EndSampleExclusive && nonzero==nnz(p.TransmitSamples) && nonzero>0, ...
    id,'A partial or absent SSB is not a completed original transmission.');
proof=struct('ContractVersion',"sixgr.truth.executed_cell_SSB_component/v1", ...
    'Source',"original_enqueued_SSB_component_and_successful_shared_TX_execution", ...
    'ComponentID',c.ComponentID,'TransmitterID',r.TransmitterID, ...
    'EnqueueReceiptSHA256',r.ReceiptSHA256,'OriginalPreparedContractSHA256',preparedHash, ...
    'OriginalSampleSHA256',r.OriginalSampleSHA256,'TransmitObservationSHA256',o.sampleHash(), ...
    'StartSample',r.StartSample,'EndSampleExclusive',r.EndSampleExclusive, ...
    'PhysicalConfigurationEpoch',owner.Physical.ConfigurationEpoch, ...
    'PhysicalTransmissionVerified',true,'ReceiverExecutionClaimed',false, ...
    'TransmitObservationScope',"aggregate_post_TX_RF_not_isolated_SSB_power");
end

function [array,meta]=localPhysicalArrayView(array,meta,count)
% Preserve logical/RF architecture and geometry; declare only the actual
% shared-channel interface (after TX projection, before RX combining).
array.SourceLogicalWaveformColumns=array.NumWaveformColumns;
meta.SourceLogicalWaveformColumns=array.NumWaveformColumns;
array.NumWaveformColumns=count; meta.NumWaveformColumns=count;
array.WaveformDomain="element"; meta.WaveformDomain="element";
array.WaveformInterfaceSource="shared_owner_physical_element_IQ";
meta.WaveformInterfaceSource="shared_owner_physical_element_IQ";
end
