classdef CoupledWaveformStream < handle
    % Scheduler-owned physical clock. Preparation registers actual samples;
    % only advanceSlot consumes RF/channel/noise and completes observations.
    % No completed decoder result is queued in place of a transmission.
    properties (SetAccess=private)
        Physical
        Events
        SampleRateHz
        Pending = struct('ID',{},'Kind',{},'UE',{},'Context',{},'Planes',{})
        DataTransmissions = struct('Identity',{},'FirstActiveSample',{},'CommittedAtSample',{})
        ControlObservationDispositions = struct('ID',{},'UE',{},'Reason',{},'CompletedAtSample',{})
    end
    properties (Access=private)
        Nodes = struct('ID',{},'Direction',{},'NumAntennas',{},'RF',{})
        Links = struct('ID',{},'UE',{},'Cell',{},'Direction',{},'DLConfig',{},'ULConfig',{})
        Components = struct('ID',{},'TX',{},'Start',{},'Samples',{})
        Serial = 0
        Decisions = struct('ID',{},'Kind',{},'UE',{},'Context',{})
        PDCCHResourceLedger = struct()
    end
    methods (Static)
        function [state,obj]=initialize(state,cfg,userCfg)
            % Materialization does not execute a waveform. Zero-duration
            % layout probes below only bind the configured antenna mapping.
            if state.CurrentSlot~=1
                error('sixgr:truth:SharedStreamOriginRequired', ...
                    'Initialize the physical owner at the first canonical slot, not at a later observation.');
            end
            obj=sixgr.truth.CoupledWaveformStream();
            for flag=["inter_cell_interference_flag","intra_cell_interference_flag","mu_mimo_interference_flag"]
                if logical(sixgr.util.structGet(cfg,"lls6g.resolvedConfig.interference."+flag,false))
                    error('sixgr:truth:SharedInterferenceLinksRequired', ...
                        'Enabled interference requires explicit cross-links in the shared physical owner; serving links alone are insufficient.');
                end
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
        function tf=hasPending(obj,kind,ue)
            tf=any(string({obj.Pending.Kind})==string(kind) & [obj.Pending.UE]==ue);
        end
        function queueRA(obj,ue,prepared,context,transmitOnly)
            if nargin<5, transmitOnly=false; end
            link=obj.linkForUE(ue,string(prepared.Direction));
            if prepared.SampleRate_Hz~=obj.SampleRateHz || ~prepared.RFExecutionDeferred || ...
                    prepared.PhysicalWaveformPlane~="physical_antenna_sqrt_mW_before_shared_tx_rf"
                error('sixgr:truth:SharedRAPreparationAuthority','RA samples need physical antenna/power authority on the shared clock.');
            end
            first=prepared.StartTime_s*obj.SampleRateHz;
            if ~isfinite(first)||abs(first-round(first))>8*eps(max(1,abs(first)))
                error('sixgr:truth:SharedRAOriginOffClock','Prepared RA starts off the physical sample clock.');
            end
            first=round(first); samples=prepared.PhysicalWaveform;
            if prepared.Direction=="UL"
                tx="ue_"+ue; rx="gnb_"+link.Cell+"_rx";
            else
                tx="gnb_"+link.Cell; rx="ue_"+ue+"_rx";
            end
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            if size(samples,2)~=node.NumAntennas || size(samples,1)~=prepared.SampleCount
                error('sixgr:truth:SharedRAAntennaLayout','Prepared RA must match its registered physical radio and complete sample extent.');
            end
            if obj.hasPending("RA",ue)
                error('sixgr:truth:DuplicatePendingRAStage','One UE cannot queue a second stage before the prior received stage completes.');
            end
            obj.Serial=obj.Serial+1; id="ra_observation_"+obj.Serial;
            obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,first));
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
            tx="ue_"+ue; rx="gnb_"+link.Cell+"_rx";
            array=sixgr.rf.AntennaArrayFactory.build(prepared.ReceiverConfig,'ue', ...
                'signal',lower(prepared.Channel),'numPorts',size(prepared.Tx.Waveform,2));
            samples=prepared.Tx.Waveform*cast(array.PortToElementMatrix.','like',prepared.Tx.Waveform);
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(size(samples,2)==node.NumAntennas, ...
                'sixgr:truth:SharedULControlAntennaLayout','Prepared ports must map to the actual physical UE radio.');
            if isempty(armed)
                obj.Serial=obj.Serial+1; id=lower(prepared.Channel)+"_observation_"+obj.Serial;
                obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,prepared.StartSample));
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
            active=find(any(samples~=0,2),1,'first');
            assert(~isempty(active),'sixgr:truth:EmptySharedULControl','A scheduled SRS/PUCCH must contain actual transmit energy.');
            boundary=id+"_ul_start";
            obj.Events.decisionBoundary(boundary,prepared.StartSample+active-1);
            obj.Decisions(end+1)=struct('ID',boundary,'Kind',"ULTransmitBoundary", ...
                'UE',ue,'Context',struct());
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
                obj.Physical.requestLinkChannelReference(obj.Events,link.ID,rx, ...
                    prepared.ReceiveStartSample,prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
                obj.Events.observe(context.DesiredReferencePlane,id,prepared.ReceiveStartSample, ...
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
        end
        function id=queuePDCCH(obj,ue,prepared,context)
            % Both DL assignments and UL grants use the same DL radio/RE
            % pool. A queued waveform is NOT a received DCI or a data grant.
            link=obj.linkForUE(ue,"DL");
            assert(isstruct(prepared) && isscalar(prepared) && ...
                prepared.ExecutionStage=="pdcch_waveform_prepared_not_received" && ...
                prepared.SampleDomain=="physical_antenna_sqrt_mW_before_shared_tx_rf" && ...
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
            obj.Serial=obj.Serial+1; id="pdcch_observation_"+obj.Serial;
            obj.Events.enqueue(tx,id,sixgr.phy.waveform.WaveformChunk(samples,first));
            % Retain the transmitted control prefix on the transmitter
            % clock. A received SS/PBCH phase must never shift TX evidence.
            % This is the monitored prefix, not a full-slot IQ export; the
            % complete generated waveform remains queued above.
            prepared.TransmitObservationStartSample=first;
            prepared.TransmitObservationEndSampleExclusive=first+prepared.MinimumReceiveSamples;
            obj.Events.observe(tx+":tx",id,first,prepared.TransmitObservationEndSampleExclusive);
            for plane=[rx+":pre_rf",rx+":post_rf"]
                obj.Events.observe(plane,id,receiveFirst,stop);
            end
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
            pending=obj.Pending(string({obj.Pending.Kind})==family & [obj.Pending.UE]==ue);
            duplicate=any(arrayfun(@(x) ...
                x.Context.TransmissionIdentity.TransmissionID==identity.TransmissionID,pending));
            assert(~duplicate, ...
                'sixgr:truth:DuplicatePendingData', ...
                'The same immutable data transmission cannot be queued twice.');
            array=sixgr.rf.AntennaArrayFactory.build(prepared.ReceiverConfig,role, ...
                'signal',lower(family),'numPorts',size(prepared.Tx.Waveform,2));
            samples=prepared.Tx.Waveform*cast(array.PortToElementMatrix.','like',prepared.Tx.Waveform);
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(size(samples,2)==node.NumAntennas && ...
                size(samples,2)==prepared.NumPhysicalTransmitAntennas && ...
                all(isfinite(samples),'all') && any(samples~=0,'all'), ...
                'sixgr:truth:SharedDataAntennaLayout', ...
                'Coded logical ports must map to the frozen physical radio without changing power.');
            assert(string(prepared.Tx.PowerContext.WaveformAmplitudeUnit)=="sqrt_mW", ...
                'sixgr:truth:SharedDataPhysicalPowerUnit','Shared IQ must retain its physical power reference.');
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
            if logical(ch.UseFading) && logical(sixgr.util.structGet( ...
                    prepared.ReceiverConfig,'outputs.phySignalDiagnosticEnabled',false))
                % Capture this actual receive interval, including its tail,
                % on the retained channel's one execution. Never reuse the
                % automatic first-interval preview as this grant's channel.
                obj.Physical.requestLinkChannelReference(obj.Events,link.ID,rx, ...
                    prepared.ReceiveStartSample, ...
                    prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
            end
            obj.Events.observe(context.DesiredReferencePlane,id,prepared.ReceiveStartSample, ...
                prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
            obj.Events.observe(tx+":tx",id,prepared.StartSample,prepared.EndSampleExclusive);
            for plane=[rx+":pre_rf",rx+":post_rf"]
                obj.Events.observe(plane,id,prepared.ReceiveStartSample, ...
                    prepared.ReceiveEndSampleExclusive+double(ch.ChannelPadSamples));
            end
            context.Prepared=prepared;
            obj.Pending(end+1)=struct('ID',id,'Kind',family,'UE',ue, ...
                'Context',context,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
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
        function transferPUCCHObservation(obj,id)
            k=find(string({obj.Pending.ID})==string(id));
            assert(isscalar(k) && obj.Pending(k).Context.AwaitingPreparation, ...
                'sixgr:truth:InvalidPUCCHObservationTransfer','Only an unencoded PUCCH observation can transfer to PUSCH UCI.');
            obj.Pending(k).Kind="TransferredPUCCHObservation";
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
        function queueDownlink(obj,kind,ue,prepared,context)
            link=obj.linkForUE(ue,"DL");
            fs=double(prepared.SampleRateHz);
            if fs~=obj.SampleRateHz || ~prepared.RFExecutionDeferred
                error('sixgr:truth:SharedPreparationAuthority', ...
                    'Contributors must use the physical clock and defer component RF processing.');
            end
            carrier=sixgr.phy.grid.makeCarrier(context.Config);
            first=sixgr.phy.frame.slotStartSample(carrier,context.Slot-1,fs);
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
            elseif kind~="PBCH"
                error('sixgr:truth:UnsupportedSharedDownlinkPreparation','No sample-domain adapter for %s.',kind);
            end
            tx="gnb_"+link.Cell;
            node=obj.Nodes(string({obj.Nodes.ID})==tx);
            assert(size(samples,2)==node.NumAntennas, ...
                'sixgr:truth:SharedDLPhysicalAntennaLayout','Queued DL must match the registered physical gNB radio.');
            component=string(kind)+"_"+tx+"_"+first;
            prior=find(string({obj.Components.ID})==component,1);
            if isempty(prior)
                obj.Events.enqueue(tx,component,sixgr.phy.waveform.WaveformChunk(samples,first));
                obj.Components(end+1)=struct('ID',component,'TX',tx,'Start',first,'Samples',samples);
            elseif ~isequal(obj.Components(prior).Samples,samples)
                error('sixgr:truth:InconsistentCellBroadcast', ...
                    'One cell transmission cannot have different physical samples for different receiving UEs.');
            end
            obj.Serial=obj.Serial+1; id="observation_"+obj.Serial;
            context.Prepared=prepared;
            planes=[tx+":tx","ue_"+ue+"_rx:pre_rf","ue_"+ue+"_rx:post_rf"];
            for plane=planes
                obj.Events.observe(plane,id,first,first+prepared.NumSamples);
            end
            if kind=="TRS"
                rx="ue_"+ue+"_rx";
                context.DesiredReferencePlane=obj.Physical.registerLinkScoringPlane(obj.Events,link.ID,rx);
                obj.Physical.requestLinkChannelReference(obj.Events,link.ID,rx,first,first+prepared.NumSamples);
                obj.Events.observe(context.DesiredReferencePlane,id,first,first+prepared.NumSamples);
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
                    obj.Pending(end+1)=struct('ID',id,'Kind',"SSBOccasion",'UE',ue, ...
                        'Context',occasion,'Planes',struct('ReceiverID',{},'Observation',{},'Segments',{}));
                end
            end
        end
        function [state,completed]=advanceSlot(obj,state,cfg,onReceived)
            if nargin<4, onReceived=[]; end
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            carrier.NSlot=state.CurrentSlot-1;
            info=nrOFDMInfo(carrier);
            first=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot-1,obj.SampleRateHz);
            stop=sixgr.phy.frame.slotStartSample(carrier,state.CurrentSlot,obj.SampleRateHz);
            if obj.Events.NextSampleIndex~=first
                error('sixgr:truth:SchedulerPhysicalClockMismatch','Slot scheduling and physical sample consumption are not contiguous.');
            end
            symbols=carrier.SymbolsPerSlot;
            localSlot=mod(carrier.NSlot,carrier.SlotsPerSubframe);
            lengths=double(info.SymbolLengths(localSlot*symbols+(1:symbols)));
            if sum(lengths)~=stop-first
                error('sixgr:truth:SlotSampleExtentMismatch','Actual OFDM symbol lengths must cover the scheduler slot.');
            end
            boundaries=[first first+cumsum(lengths)];
            [~,~,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,state.CurrentSlot);
            dl=double(partition.DLSymbolAllocation); ul=double(partition.ULSymbolAllocation);
            completed=struct('Kind',{},'UE',{},'Context',{},'Planes',{});
            % A slot is committed only after every producer has prepared its
            % contributions. Symbol boundaries preserve TDD guard intervals.
            for symbol=0:symbols-1
                inDL=symbol>=dl(1) && symbol<sum(dl);
                inUL=symbol>=ul(1) && symbol<sum(ul);
                if xor(inDL,inUL)
                    direction="DL"; if inUL, direction="UL"; end
                    obj.retarget(direction);
                end
                while obj.Events.NextSampleIndex<boundaries(symbol+2)
                    % A received DCI or HARQ result can change contributions
                    % after a boundary inside this symbol. Committing the
                    % entire symbol first falsely locks that future interval.
                    next=obj.Events.nextEventSample(boundaries(symbol+2));
                    for node=obj.Nodes
                        if ~endsWith(node.ID,"_rx")
                            obj.Events.commitTransmissionsThrough(node.ID,next);
                        end
                    end
                    event=obj.Events.advanceUntilEvent(boundaries(symbol+2));
                    for item=event.Completed
                        k=find(string({obj.Pending.ID})==item.ID,1);
                        if isempty(k), error('sixgr:truth:UnknownSharedObservation','No prepared receiver owns this completion.'); end
                        obj.Pending(k).Planes(end+1)=rmfield(item,'ID');
                    end
                    previousCount=numel(completed);
                    done=find(arrayfun(@(x)numel(x.Planes)== ...
                        3+double(isfield(x.Context,'DesiredReferencePlane')),obj.Pending));
                    for k=done
                        p=obj.Pending(k);
                        if p.Kind=="TransferredPUCCHObservation"
                            obj.ControlObservationDispositions(end+1)=struct('ID',p.ID,'UE',p.UE, ...
                                'Reason',"feedback_transferred_to_PUSCH_no_PUCCH_transmitted", ...
                                'CompletedAtSample',obj.Events.NextSampleIndex);
                            continue;
                        end
                        if p.Kind=="PUCCH"
                            assert(isfield(p.Context,'Prepared'),'sixgr:truth:UnencodedPUCCHObservation', ...
                                'A received PUCCH window cannot become a trial without actual prior encoding.');
                        end
                        completed(end+1)=struct('Kind',p.Kind,'UE',p.UE,'Context',p.Context,'Planes',p.Planes); %#ok<AGROW>
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
                            assert(obj.Events.NextSampleIndex==d.Context.FirstActiveSample+1, ...
                                'sixgr:truth:DataTXCommitClockMismatch', ...
                                'TX evidence belongs to the first actually consumed active sample.');
                            obj.DataTransmissions(end+1)=struct( ...
                                'Identity',d.Context.TransmissionIdentity, ...
                                'FirstActiveSample',d.Context.FirstActiveSample, ...
                                'CommittedAtSample',obj.Events.NextSampleIndex);
                        end
                        completed(end+1)=struct('Kind',d.Kind,'UE',d.UE,'Context',d.Context,'Planes',struct([])); %#ok<AGROW>
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
                    end
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
    end
    methods (Access=private)
        function registerNode(obj,id,cfg,direction,nAnt,isTX)
            k=find(string({obj.Nodes.ID})==id,1);
            rf=sixgr.util.structGet(cfg,'rf',struct());
            if ~isempty(k)
                if obj.Nodes(k).NumAntennas~=nAnt || ~isequaln(obj.Nodes(k).RF,rf)
                    error('sixgr:truth:InconsistentPhysicalNode','Every link sharing a radio must agree on its RF and antenna layout.');
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
