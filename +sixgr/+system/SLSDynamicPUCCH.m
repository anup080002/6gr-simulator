classdef SLSDynamicPUCCH < handle
    % Payload-free receive obligations under ideal received-control SLS.
    % Actual installed PUCCH resources/capacity; NOT waveform UCI outcomes.
    properties (SetAccess=private)
        Trace table = table()
        CompletionTrace table = table()
        HARQDecisionTrace table = table()
        ResourceBindings = []
    end
    properties (Access=private)
        Cfg struct
        Grants cell = cell(0,1)
        Cells double = zeros(0,1)
        Digests string = strings(0,1)
        TransportBindings cell = cell(0,1)
        RNTIByUE double = []
        SRProcedures cell = cell(0,1)
    end
    methods
        function obj=SLSDynamicPUCCH(cfg)
            p=cfg.system.linkAbstraction.dynamicPUCCH;
            assert(strcmpi(string(cfg.system.phyBackend),'calibrated_link_abstraction') && ...
                cfg.phy.pucch.enable && any(string(p.transportPolicy)==["dedicated_pucch_no_pusch_multiplexing","causal_native_pusch_multiplexing"]) && ...
                string(p.deliveryAssumption)=="ideal_error_free_delayed_control", ...
                'sixgr:system:DynamicPUCCHPolicy','This SLS ledger requires explicitly ideal delayed control.');
            assert(logical(cfg.phy.pucch.uciOnPUSCHEnabled)== ...
                (string(p.transportPolicy)=="causal_native_pusch_multiplexing"), ...
                'sixgr:system:DynamicPUCCHPolicy','UCI enablement must match the explicit SLS transport policy.');
            assert(~logical(cfg.phy.csi.reportCSI) || cfg.system.linkAbstraction.dlFeedback.enabled, ...
                'sixgr:system:DynamicPUCCHPolicy','CSI obligations require the modeled causal CSI producer.');
            obj.Cfg=cfg;
            mode=string(sixgr.util.structGet(p,'resourceBinding.mode','shared_configured_resources'));
            assert(any(mode==["shared_configured_resources","per_cell_frequency_pool"]), ...
                'sixgr:system:UCIResourceBindingPolicy','Unknown dynamic PUCCH resource binding policy.');
            if mode=="per_cell_frequency_pool"
                obj.ResourceBindings=sixgr.system.SLSUCIResourceBindings(cfg);
            end
        end
        function configureUEIdentities(obj,rntis)
            validateattributes(rntis,{'numeric'},{'vector','finite','integer','positive','<=',65535});
            % SR/CSI-only obligations can be published before any data
            % grant. Their UE indices already refer to this RNTI map; even
            % completed historical rows must not acquire a new identity.
            assert(isempty(obj.Grants) && isempty(obj.TransportBindings) && ...
                isempty(obj.Trace) && isempty(obj.CompletionTrace) && isempty(obj.HARQDecisionTrace) && ...
                isempty(obj.SRProcedures), ...
                'sixgr:system:UCIIdentityAlreadyIssued', ...
                'Install UE identities before issuing grants or publishing UCI obligations.');
            if ~isempty(obj.ResourceBindings), obj.ResourceBindings.configureUEIdentities(rntis); end
            obj.RNTIByUE=double(rntis(:));
        end
        function rnti=rntiForUE(obj,u)
            % Standalone model fixtures retain the explicit index-valued
            % identity convention; the system runner always installs its map.
            if isempty(obj.RNTIByUE), rnti=u; return; end
            assert(u>=1 && u==fix(u) && u<=numel(obj.RNTIByUE), ...
                'sixgr:system:UCIIdentityMissing','UE is not in the installed identity population.');
            rnti=obj.RNTIByUE(u);
        end
        function installSRProcedure(obj,procedure)
            obj.installSRProcedures({procedure});
        end
        function installSRProcedures(obj,procedures)
            % Validate the entire population before publishing any owner.
            % A bad later UE/ID must not leave a partly installed MAC state.
            assert(iscell(procedures) && isvector(procedures) && ~isempty(procedures), ...
                'sixgr:system:MissingSRProcedure','Supply a nonempty population of owned MAC procedures.');
            assert(isempty(obj.Trace) && isempty(obj.CompletionTrace), ...
                'sixgr:system:SRProcedureAlreadyIssued','Install procedures before publishing UCI obligations.');
            configs=obj.Cfg.validation.pucch_resources.scheduling_request_resources;
            pending=obj.SRProcedures(:);
            for procedureIndex=1:numel(procedures)
                procedure=procedures{procedureIndex};
                assert(isa(procedure,'sixgr.system.SLSSchedulingRequestProcedure') && isscalar(procedure), ...
                    'sixgr:system:MissingSRProcedure','Install an owned MAC procedure, not a pending bit.');
                id=procedure.Identity;
                assert(id.RNTI==obj.rntiForUE(id.UEIndex),'sixgr:system:UCIIdentityMismatch', ...
                    'SR procedure RNTI must match the installed UE.');
                assert(any([configs.scheduling_request_id]==id.SchedulingRequestID), ...
                    'sixgr:system:UnconfiguredSRProcedure','SR identity requires an installed RRC resource.');
                for k=1:numel(pending)
                    other=pending{k}.Identity;
                    assert(~(id.UEIndex==other.UEIndex && id.CellID==other.CellID && ...
                        id.SchedulingRequestID==other.SchedulingRequestID), ...
                        'sixgr:system:DuplicateSRProcedure','Each UE/cell/SR identity has one MAC owner.');
                end
                pending{end+1,1}=procedure;
            end
            obj.SRProcedures=pending;
        end
        function payload=srProcedureStatesAtSlotStart(obj,ue,slot0)
            % Installed calendar owns identity/occasion; MAC owns the value.
            % Never turn an absent procedure into a negative SR snapshot.
            validateattributes(slot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(ue.RNTI==obj.rntiForUE(ue.UEID),'sixgr:system:UCIIdentityMismatch', ...
                'Resolve SR snapshots for the installed UE identity.');
            cfg=obj.configForUE(ue);
            calendar=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,slot0+1,slot0+1);
            calendar=calendar(calendar.ULResourceAvailable,:);
            payload=struct('Available',false,'States',[], ...
                'Source',"owned_modeled_MAC_state_and_installed_SR_calendar", ...
                'WaveformBacked',false);
            states=[];
            for rowIndex=1:height(calendar)
                row=calendar(rowIndex,:);
                matches=find(cellfun(@(p)p.Identity.UEIndex==ue.UEID && ...
                    p.Identity.RNTI==ue.RNTI && p.Identity.CellID==ue.ServingCell && ...
                    p.Identity.SchedulingRequestID==row.SchedulingRequestID,obj.SRProcedures));
                if isempty(matches), return; end
                assert(isscalar(matches),'sixgr:system:DuplicateSRProcedure','Ambiguous SR ownership.');
                owned=obj.SRProcedures{matches}.project(slot0);
                assert(~owned.RequiresRandomAccess,'sixgr:system:SRRandomAccessRequired', ...
                    'A recovery requirement is not a negative SR or successful feedback.');
                data=struct('SchedulingRequestID',row.SchedulingRequestID, ...
                    'SRResourceConfigurationID',row.SRResourceConfigurationID, ...
                    'ResourceID',row.PUCCHResourceID,'UEIndex',ue.UEID,'RNTI',ue.RNTI, ...
                    'ServingCell',ue.ServingCell,'ComponentCarrier',ue.ComponentCarrier, ...
                    'ActiveULBWP',ue.ActiveULBWP,'ConfigurationEpoch',row.PUCCHConfigurationEpoch, ...
                    'PeriodSlots',row.PeriodSlots,'OffsetSlots',row.OffsetSlots, ...
                    'AbsoluteSlot',slot0,'Priority',row.PriorityIndex, ...
                    'PendingPositiveSR',owned.Pending, ...
                    'ProhibitTimerActive',slot0<owned.ProhibitUntilSlot0, ...
                    'ProcedureTriggerSequence',owned.TriggerSequence, ...
                    'ProcedureTransmissionCounter',owned.Counter,'Source',payload.Source);
                state=sixgr.phy.pucch.SchedulingRequestState(data);
                assert(state.Data.Transmit==owned.MayTransmit, ...
                    'sixgr:system:SRProcedureSnapshotMismatch','Typed SR must preserve the owned MAC decision.');
                if isempty(states), states=state; else, states(end+1)=state; end %#ok<AGROW>
            end
            payload.Available=true; payload.States=states;
        end
        function payload=srPayloadAtSlotStart(obj,o,asOfAbsoluteSlot0)
            assert(asOfAbsoluteSlot0==o.AbsoluteSlot0 && o.RNTI==obj.rntiForUE(o.UEIndex), ...
                'sixgr:system:SLSRPayloadClock','Resolve SR only at its actual owned transmission occasion.');
            assert(o.SRBits>0 && ~isempty(o.SchedulingRequestIDs) && ...
                numel(unique(o.SchedulingRequestIDs))==numel(o.SchedulingRequestIDs), ...
                'sixgr:system:MissingSRProcedureIdentity','Resolve explicit independently configured SR identities.');
            payload=struct('Available',false,'PositiveSchedulingRequestIDs',zeros(0,1), ...
                'Snapshots',{{}},'ProcedureIndices',zeros(0,1), ...
                'ProcedureStates',[],'CandidatePositiveSchedulingRequestIDs',zeros(0,1), ...
                'SelectedSRResourceConfigurationID',NaN,'SelectionPolicy',"no_positive_SR", ...
                'Source',"modeled_MAC_SR_not_physical_decode");
            identity=obj.Cfg.phy.frame.DefaultIdentity;
            ue=struct('UEID',o.UEIndex,'RNTI',o.RNTI,'ServingCell',o.CellID,'PUCCHCell',o.CellID, ...
                'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
            typed=obj.srProcedureStatesAtSlotStart(ue,asOfAbsoluteSlot0);
            if ~typed.Available, return; end
            assert(~isempty(typed.States),'sixgr:system:MissingSRProcedureIdentity', ...
                'An SR-bearing obligation requires a configured current-slot opportunity.');
            data=arrayfun(@(s)s.Data,typed.States);
            assert(isfield(o,'SRResourceConfigurationIDs') && ~isempty(o.SRResourceConfigurationIDs) && ...
                numel(unique(o.SRResourceConfigurationIDs))==numel(o.SRResourceConfigurationIDs) && ...
                all(ismember(o.SRResourceConfigurationIDs,[data.SRResourceConfigurationID])), ...
                'sixgr:system:MissingSRProcedureIdentity','Preserve exact configured resource occasions, not only SR IDs.');
            keep=ismember([data.SRResourceConfigurationID],o.SRResourceConfigurationIDs);
            states=typed.States(keep); data=data(keep);
            assert(isequal(sort(unique([data.SchedulingRequestID])).',sort(o.SchedulingRequestIDs(:))), ...
                'sixgr:system:MissingSRProcedureIdentity','SR resource and procedure identities disagree.');
            candidates=find([data.Transmit]);
            payload.CandidatePositiveSchedulingRequestIDs=unique([data(candidates).SchedulingRequestID]).';
            if numel(candidates)>1
                policy=string(sixgr.util.structGet(obj.Cfg, ...
                    'system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC.positiveSRSelection', ...
                    'require_explicit_selection'));
                assert(isscalar(policy) && policy=="lowest_scheduling_request_resource_id", ...
                    'sixgr:system:MultiplePositiveSRsRequireSelection', ...
                    'Configure a MAC selection policy; a compact SR indication cannot deliver every pending request.');
                [~,index]=min([data(candidates).SRResourceConfigurationID]);
                chosen=candidates(index); payload.SelectionPolicy=policy;
            else
                chosen=candidates;
                if ~isempty(chosen), payload.SelectionPolicy="sole_positive_resource"; end
            end
            if ~isempty(chosen)
                selected=data(chosen);
                matches=find(cellfun(@(p)p.Identity.UEIndex==o.UEIndex && p.Identity.RNTI==o.RNTI && ...
                    p.Identity.CellID==o.CellID && p.Identity.SchedulingRequestID==selected.SchedulingRequestID,obj.SRProcedures));
                assert(isscalar(matches),'sixgr:system:DuplicateSRProcedure','Resolve one selected MAC owner.');
                payload.PositiveSchedulingRequestIDs=selected.SchedulingRequestID;
                payload.SelectedSRResourceConfigurationID=selected.SRResourceConfigurationID;
                payload.Snapshots={obj.SRProcedures{matches}.project(asOfAbsoluteSlot0)};
                payload.ProcedureIndices=matches;
            end
            payload.Available=true;
            payload.ProcedureStates=states;
        end
        function rows=schedulingRequestTrace(obj)
            rows=table();
            for k=1:numel(obj.SRProcedures), rows=[rows;obj.SRProcedures{k}.Trace]; end %#ok<AGROW>
        end
        function prepared=preparePUCCHAtSlotStart(obj,o,now,csi)
            % Ideal received-control SLS producer; not a physical missing-DCI
            % hypothesis or receive result. Payload values come from owned
            % decisions/procedures, never from o.ContextDigest or RX bits.
            validateattributes(now,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            assert(now==o.AbsoluteSlot0 && o.RNTI==obj.rntiForUE(o.UEIndex), ...
                'sixgr:system:SLSUCIPreparationClock','Prepare at the actual owned transmission slot.');
            prepared=struct('Available',false,'Status',"unprepared",'TransmitterPlan',[], ...
                'HARQEvidence',struct(),'CSIEvidence',struct(),'SREvidence',struct(), ...
                'Source',"modeled_SLS_causal_payload_transmitter_preparation", ...
                'NativeWaveformExecuted',false,'PhysicalReceptionQualified',false);
            if o.Transport=="PUSCH"
                prepared.Status="bound_to_PUSCH_no_dedicated_PUCCH"; return;
            end
            assert(o.Transport=="PUCCH",'sixgr:system:SLSUCITransport','Unknown owned UCI transport.');
            identity=obj.Cfg.phy.frame.DefaultIdentity;
            ue=struct('UEID',o.UEIndex,'RNTI',o.RNTI,'ServingCell',o.CellID,'PUCCHCell',o.CellID, ...
                'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
            cfg=obj.configForUE(ue);
            [~,ulAllowed,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,now+1);
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            ownership=repmat('D',1,carrier.SymbolsPerSlot);
            if ulAllowed
                ul=partition.ULSymbolAllocation; ownership(ul(1)+(1:ul(2)))='U';
            end
            frame=struct('TargetSlot',now+1,'PDSCHEndSlot',now+1,'K1',0, ...
                'K1Source',"configured_SLS_report_occasion",'SlotSymbolOwnership',ownership, ...
                'FlexibleResolutionProvided',false);
            harq=int8([]); part1=int8([]); part2=int8([]);
            if o.HARQBits>0
                h=obj.harqPayloadAtSlotStart(o,now); prepared.HARQEvidence=h;
                if ~h.Available, prepared.Status="missing_causal_HARQ_payload"; return; end
                harq=h.HARQACKBits;
                indices=find(ismember(obj.Digests,h.SourceGrantSHA256));
                controlSlots=cellfun(@(g)g.ControlAbsoluteSlot,obj.Grants(indices));
                [~,last]=max(controlSlots); grant=obj.Grants{indices(last)};
                dci=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
                frame.PDSCHEndSlot=grant.ScheduledAbsoluteSlot+1;
                frame.K1=now-grant.ScheduledAbsoluteSlot;
                frame.K1Source="ideal_received_control_frozen_grant";
                frame.PRIFieldWidth=3; frame.DecodedPRI=double(dci.Fields.pucch_resource_indicator);
                frame.PRIProvenance="ideal_received_control_DCI_not_waveform_decode";
                frame.FirstCCE=sixgr.util.structGet(grant,'PDCCHGrantFirstCCE',NaN);
                frame.NumCCE=sixgr.util.structGet(grant,'PDCCHGrantNumCCE',NaN);
            end
            if o.CSIPart1Bits+o.CSIPart2Bits>0
                assert(isstruct(csi) && isscalar(csi) && ...
                    all(isfield(csi,{'Available','Part1Bits','Part2Bits','SelectedFeedback','WaveformBacked'})), ...
                    'sixgr:system:MissingCSIPayloadProducer','Use the causal CSI buffer output, not configured zero bits.');
                prepared.CSIEvidence=csi;
                if ~csi.Available, prepared.Status="missing_causal_CSI_payload"; return; end
                source=csi.SelectedFeedback;
                assert(~csi.WaveformBacked && source.UEIndex==o.UEIndex && source.RNTI==o.RNTI && ...
                    source.ServingCell==o.CellID && source.ReportAbsoluteSlot0==now && ...
                    source.ReferenceAvailableAtSlot0<=now && source.CapturedAtAbsoluteSlot0<now, ...
                    'sixgr:system:CSIProducerIdentity','Retain the actual UE/cell/report identity and causal clock.');
                part1=csi.Part1Bits; part2=csi.Part2Bits;
            else
                assert(isempty(fieldnames(csi)), 'sixgr:system:UnexpectedCSIPayload', ...
                    'Do not inject CSI into an occasion without its configured reference obligation.');
            end
            if o.SRBits>0
                sr=obj.srPayloadAtSlotStart(o,now); prepared.SREvidence=sr;
                if ~sr.Available, prepared.Status="missing_owned_SR_procedure"; return; end
                frame.SchedulingRequestStates=sr.ProcedureStates;
                if isfinite(sr.SelectedSRResourceConfigurationID)
                    frame.SelectedSRResourceConfigurationID=sr.SelectedSRResourceConfigurationID;
                end
            end
            if isempty(harq) && isempty(part1) && isempty(part2)
                assert(o.SRBits>0,'sixgr:system:EmptyUCIProducer','No payload-bearing procedure for this occasion.');
                if isempty(sr.PositiveSchedulingRequestIDs)
                    prepared.Available=true; prepared.Status="negative_SR_no_transmission"; return;
                end
                data=arrayfun(@(s)s.Data,sr.ProcedureStates);
                state=sr.ProcedureStates([data.SRResourceConfigurationID]==sr.SelectedSRResourceConfigurationID);
                planned=sixgr.phy.pucch.PUCCHConfigBuilder.planSR(cfg,ue,state,frame);
            else
                planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCombined(cfg,ue,harq,part1,part2,frame);
            end
            % Builder's TX-derived context must not become gNB RX authority.
            prepared.TransmitterPlan=rmfield(planned,'ReceiverContext');
            prepared.Available=true; prepared.Status="typed_transmitter_plan_ready_not_executed";
        end
        function [prepared,emission,tx]=generatePUCCHAtSlotStart(obj,o,now,csi,powerReference)
            % Optional native producer, not a replacement for ideal delivery.
            % The caller must commit the returned emission to channel history;
            % generation alone does not complete UCI or advance MAC counters.
            prepared=obj.preparePUCCHAtSlotStart(o,now,csi);
            emission=struct([]); tx=struct();
            if ~prepared.Available || isempty(prepared.TransmitterPlan), return; end
            assert(isstruct(sixgr.util.structGet(obj.Cfg, ...
                'system.linkAbstraction.dynamicPUCCH.spatialVectorCatalog',[])), ...
                'sixgr:abstraction:PUCCHEmissionSpatialBinding', ...
                'Native generation needs the YAML-owned active spatial vector catalog.');
            identity=obj.Cfg.phy.frame.DefaultIdentity;
            ue=struct('UEID',o.UEIndex,'RNTI',o.RNTI,'ServingCell',o.CellID,'PUCCHCell',o.CellID, ...
                'ComponentCarrier',identity.ScheduledCCID,'ActiveULBWP',identity.ULBWPID);
            cfg=obj.configForUE(ue);
            if nargin<5, powerReference=struct(); end
            bound=sixgr.system.abstraction.materializeModeledPUCCH(cfg,prepared.TransmitterPlan,powerReference,now);
            [assignment,spatialBinding]=sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(cfg,bound.Assignment);
            carrier=sixgr.phy.grid.makeCarrier(cfg);
            carrier.NSlot=mod(now,carrier.SlotsPerFrame);
            carrier.NFrame=mod(floor(now/carrier.SlotsPerFrame),1024);
            binding=struct('AbsoluteSlot0',now,'UEIndex',o.UEIndex,'RNTI',o.RNTI, ...
                'ServingCellID',o.CellID,'Precoder',spatialBinding.Precoder, ...
                'SpatialStateDigest',spatialBinding.SpatialStateDigest, ...
                'SourceClassification',"modeled_SLS_ideal_delayed_control");
            binding.Obligation=o;
            [emission,tx]=sixgr.system.abstraction.executePUCCHEmission( ...
                carrier,assignment,bound.Report,binding);
            prepared.NativeWaveformExecuted=true;
            prepared.Status="native_PUCCH_generated_not_committed_or_received";
        end
        function configureServingCells(obj,serving,now)
            validateattributes(now,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(serving,{'numeric'},{'vector','integer','positive','finite'});
            serving=serving(:);
            for procedureIndex=1:numel(obj.SRProcedures)
                procedure=obj.SRProcedures{procedureIndex}; id=procedure.Identity;
                assert(id.UEIndex<=numel(serving) && serving(id.UEIndex)==id.CellID, ...
                    'sixgr:system:SRProcedureHandoverRequiresReconfiguration', ...
                    'Reconfigure SR MAC ownership explicitly when the serving cell changes.');
            end
            % Ownership does not expire when K1 has elapsed. A missed call
            % to completeSlot must not silently release source-cell feedback,
            % including when the non-pooled installed-resource policy is used.
            completedIDs=strings(0,1); completedGrantDigests=strings(0,1);
            if ~isempty(obj.CompletionTrace)
                completedIDs=obj.CompletionTrace.ObligationID;
            end
            if ~isempty(obj.Trace)
                completed=obj.Trace(ismember(obj.Trace.ObligationID,completedIDs),:);
                for k=1:height(completed)
                    hashes=split(completed.HARQSourceGrantSHA256(k),"|");
                    completedGrantDigests=[completedGrantDigests;hashes(strlength(hashes)>0)]; %#ok<AGROW>
                end
            end
            protected=zeros(0,2);
            for k=1:numel(obj.Grants)
                g=obj.Grants{k};
                if ~ismember(obj.Digests(k),completedGrantDigests)
                    protected(end+1,:)=[g.UEIndex obj.Cells(k)]; %#ok<AGROW>
                end
            end
            for k=1:numel(obj.TransportBindings)
                b=obj.TransportBindings{k};
                if ~ismember(b.Obligation.ResourceID,completedIDs)
                    protected(end+1,:)=[b.Obligation.UEIndex b.Obligation.CellID]; %#ok<AGROW>
                end
            end
            if ~isempty(obj.Trace)
                pending=obj.Trace(~ismember(obj.Trace.ObligationID,completedIDs),:);
                protected=[protected;[pending.UEIndex pending.CellID]];
            end
            assert(isempty(protected) || (all(protected(:,1)<=numel(serving)) && ...
                all(serving(protected(:,1))==protected(:,2))), ...
                'sixgr:system:UCIHandoverOutstanding', ...
                'Handover must explicitly drain or cancel outstanding source-cell UCI; do not relabel its ownership.');
            if ~isempty(obj.ResourceBindings)
                obj.ResourceBindings.update(serving,now,unique(protected,'rows'));
            end
        end
        function cfg=configForUE(obj,ue)
            cfg=obj.Cfg;
            if ~isempty(obj.ResourceBindings), cfg=obj.ResourceBindings.configForUE(ue); end
        end
        function yes=multiplexingEnabled(obj)
            yes=string(obj.Cfg.system.linkAbstraction.dynamicPUCCH.transportPolicy)=="causal_native_pusch_multiplexing";
        end
        function blocked=blockedUEsForPUSCH(obj,due,cellID,symbolAllocation)
            % Same-slot but disjoint-symbol PUCCH does not prevent PUSCH.
            % Only one overlapping HARQ/CSI obligation can currently move;
            % preserve SR-only and ambiguous obligations on dedicated PUCCH.
            blocked=zeros(0,1);
            if isempty(due), return; end
            same=due([due.CellID]==cellID);
            same=overlappingObligations(same,symbolAllocation);
            if isempty(same), return; end
            blocked=unique([same.UEIndex]).';
            if ~obj.multiplexingEnabled(), return; end
            keep=true(size(blocked));
            for k=1:numel(blocked)
                obligations=same([same.UEIndex]==blocked(k));
                keep(k)=~(isscalar(obligations) && obligations.Transport=="PUCCH" && ...
                    obligations.HARQBits+obligations.CSIPart1Bits+obligations.CSIPart2Bits>0);
            end
            blocked=blocked(keep);
        end
        function assertPUSCHExecution(obj,grants,cellIDs,due,absoluteSlot0)
            % Recheck actual frozen symbols, not the planning-time budget.
            assert(numel(grants)==numel(cellIDs), ...
                'sixgr:system:UCIIdentityMismatch','Each PUSCH needs its actual serving cell.');
            for k=1:numel(grants)
                g=grants(k);
                assert(g.RNTI==obj.rntiForUE(g.UEIndex), ...
                    'sixgr:system:UCIIdentityMismatch','Executing PUSCH differs from the installed UE identity.');
                assert(g.ScheduledAbsoluteSlot==absoluteSlot0, ...
                    'sixgr:system:ReservationExecutionClock','Check UCI coexistence at the frozen data slot.');
                if isempty(due), continue; end
                same=due([due.UEIndex]==g.UEIndex & [due.CellID]==cellIDs(k) & ...
                    string({due.Transport})=="PUCCH");
                assert(isempty(overlappingObligations(same,g.SymbolAllocation)), ...
                    'sixgr:system:DedicatedPUCCHPUSCHCollision', ...
                    'A frozen PUSCH overlaps dedicated same-UE PUCCH in time; resolve transport before execution.');
            end
        end
        function grants=bindPUSCH(obj,grants,cellID,now,serving,references)
            % Called before issuance/queueing, never on an already issued TB.
            % Conservative supported subset: one same-cell obligation and a
            % single native, data-bearing PUSCH with all UCI known at control.
            if ~obj.multiplexingEnabled() || isempty(grants), return; end
            bound=cell(numel(grants),1); additions=cell(0,1);
            for k=1:numel(grants)
                g=grants(k); g.SLSUCIAllocation=struct(); g.SLSUCIObligationID="";
                g.ServingCell=cellID;
                u=sixgr.system.resolveGrantUEIndex(g,numel(serving));
                assert(g.RNTI==obj.rntiForUE(u), ...
                    'sixgr:system:UCIIdentityMismatch', ...
                    'PUSCH RNTI differs from its installed UE identity; do not bind or release UCI resources.');
                target=g.ScheduledAbsoluteSlot;
                due=obj.snapshot(now,target,serving,references);
                if ~isempty(due), due=due([due.UEIndex]==g.UEIndex & [due.CellID]==cellID); end
                if isempty(due), bound{k}=g; continue; end
                % TS 38.213 9.2.5: same-slot presence is not time overlap.
                % Leave disjoint PUCCH occasions (including SR-only) on
                % their installed resources; only overlapping UCI can be
                % selected for this PUSCH. Frequency separation alone is
                % not sufficient to exclude a time-overlapping PUCCH.
                due=overlappingObligations(due,g.SymbolAllocation);
                if isempty(due), bound{k}=g; continue; end
                assert(isscalar(due) && due.Transport=="PUCCH" && ...
                    due.HARQBits+due.CSIPart1Bits+due.CSIPart2Bits>0 && ...
                    g.ControlAbsoluteSlot==now && target>now && g.PHYGrant.IsFrozen, ...
                    'sixgr:system:SLSUCIUnsupportedOverlap', ...
                    'Multiplex only one causal HARQ/CSI occasion on a future issued PUSCH; retain dedicated SR-only resources.');
                replay=sixgr.phy.grant.applyPHYGrantToConfig(obj.Cfg,g.PHYGrant);
                carrier=sixgr.phy.grid.makeCarrier(replay);
                carrier.NSlot=mod(target,carrier.SlotsPerFrame);
                carrier.NFrame=mod(floor(target/carrier.SlotsPerFrame),1024);
                [~,~,pusch,experimental]=sixgr.phy.grid.allocPUSCHTransport(carrier,replay,'RNTI',g.RNTI);
                assert(isempty(experimental),'sixgr:system:SLSUCIUnsupportedTransport', ...
                    'This transport policy requires native NR PUSCH, not an experimental modulation adapter.');
                [tbs,~]=sixgr.util.resolveGrantTBSBits(g,'SLSDynamicPUCCH');
                g.SLSUCIAllocation=sixgr.phy.ul.pusch.planUCIResources(carrier,pusch, ...
                    g.PHYGrant.CodingLayout.TargetCodeRate,tbs,[due.HARQBits due.CSIPart1Bits due.CSIPart2Bits]);
                g.SLSUCIObligationID=due.ResourceID;
                binding=struct('Obligation',due,'Grant',g,'GrantSHA256',grantDigest(g));
                assert(~any(cellfun(@(b) b.Obligation.ResourceID==due.ResourceID,obj.TransportBindings)) && ...
                    ~any(cellfun(@(b) b.Obligation.ResourceID==due.ResourceID,additions)), ...
                    'sixgr:system:SLSUCIDuplicateBinding','One obligation cannot bind to two grants.');
                additions{end+1}=binding; bound{k}=g; %#ok<AGROW>
            end
            grants=vertcat(bound{:});
            obj.TransportBindings=[obj.TransportBindings;additions(:)];
        end
        function recordHARQDecision(obj,ctx,replay)
            % Retain a real calibrated-PHY decision, NOT an executed CRC.
            % Slot-level decode completion is at the end of that slot. A
            % same-slot waveform producer cannot use this future result.
            required={'Ok','TransportBlockIdentity','TransmissionAbsoluteSlot0', ...
                'ReceiveCompletionAbsoluteSlot0','SourceClassification', ...
                'CalibrationQualified','CalibrationSHA256','CalibrationCurveID', ...
                'CalibrationKeySHA256','WaveformReplayExecuted','PHYDecisionStatus'};
            assert(isstruct(replay) && isscalar(replay) && all(isfield(replay,required)) && ...
                isBinary(replay.Ok) && isBinary(replay.CalibrationQualified) && ...
                isBinary(replay.WaveformReplayExecuted) && ~replay.WaveformReplayExecuted && ...
                string(replay.PHYDecisionStatus)=="OK" && string(ctx.Direction)=="DL", ...
                'sixgr:system:SLSHARQDecisionEvidence','Require a completed labeled calibrated DL decision.');
            source=string(replay.SourceClassification);
            assert(isscalar(source) && ((replay.CalibrationQualified && source=="calibrated_sls_estimate_not_waveform_truth") || ...
                (~replay.CalibrationQualified && source=="development_fixture_not_study_result")), ...
                'sixgr:system:SLSHARQDecisionEvidence','Calibration qualification and decision source must agree.');
            g=ctx.Grant; cellID=ctx.ServingCellID;
            match=find(cellfun(@(x)sixgr.system.abstraction.matchesScheduledGrant(x,ctx),obj.Grants) & obj.Cells==cellID);
            assert(isscalar(match) && g.RNTI==obj.rntiForUE(g.UEIndex), ...
                'sixgr:system:SLSHARQDecisionIdentity','Decision must retain the complete issued DL grant and cell identity.');
            clock=[replay.TransmissionAbsoluteSlot0 replay.ReceiveCompletionAbsoluteSlot0];
            validateattributes(clock,{'numeric'},{'vector','numel',2,'integer','finite','nonnegative'});
            assert(clock(1)==g.ScheduledAbsoluteSlot && clock(2)>=clock(1) && ...
                clock(2)<=g.HARQFeedbackAbsoluteSlot && ...
                isscalar(string(ctx.TransportBlockIdentity)) && strlength(string(ctx.TransportBlockIdentity))>0 && ...
                isequal(string(ctx.TransportBlockIdentity),string(replay.TransportBlockIdentity)), ...
                'sixgr:system:SLSHARQDecisionClock','Retain the original TB and causal transmission/completion clocks.');
            for field=["CalibrationSHA256","CalibrationCurveID","CalibrationKeySHA256"]
                assert(isscalar(string(replay.(field))) && strlength(string(replay.(field)))>0, ...
                    'sixgr:system:SLSHARQDecisionEvidence','Decision requires its calibration identities.');
            end
            row=table(obj.Digests(match),double(cellID),double(g.UEIndex),double(g.RNTI), ...
                double(clock(1)),double(clock(2)),double(g.HARQFeedbackAbsoluteSlot), ...
                string(ctx.TransportBlockIdentity),logical(replay.Ok),source,logical(replay.CalibrationQualified), ...
                string(replay.CalibrationSHA256),string(replay.CalibrationCurveID),string(replay.CalibrationKeySHA256),false, ...
                'VariableNames',{'SourceGrantSHA256','CellID','UEIndex','RNTI', ...
                'TransmissionAbsoluteSlot0','ReceiveCompletionAbsoluteSlot0','FeedbackAbsoluteSlot0', ...
                'TransportBlockIdentity','ACK','SourceClassification','CalibrationQualified', ...
                'CalibrationSHA256','CalibrationCurveID','CalibrationKeySHA256','WaveformBacked'});
            if ~isempty(obj.HARQDecisionTrace)
                previous=obj.HARQDecisionTrace.SourceGrantSHA256==obj.Digests(match);
                if any(previous)
                    assert(nnz(previous)==1 && isequaln(obj.HARQDecisionTrace(previous,:),row), ...
                        'sixgr:system:SLSHARQDecisionMutation','A retained decision cannot change ACK, clock, TB or calibration.');
                    return;
                end
            end
            obj.HARQDecisionTrace=[obj.HARQDecisionTrace;row];
        end
        function payload=harqPayloadAtSlotStart(obj,o,asOfAbsoluteSlot0)
            % Resolves only HARQ fields in an ideal-control obligation. It
            % neither supplies CSI/SR nor asserts physical UCI reception.
            payload=obj.resolveHARQPayload(o,asOfAbsoluteSlot0,true);
        end
        function completeSlot(obj,now,serving,references,issued,executed)
            % Model completion only. Never manufacture a UCI CRC or bit row.
            due=obj.snapshot(now,now,serving,references);
            if ~isempty(due) && ~isempty(obj.CompletionTrace)
                assert(~any(ismember(string({due.ResourceID}),obj.CompletionTrace.ObligationID)), ...
                    'sixgr:system:SLSUCIDuplicateCompletion','Reject duplicate completion before mutating MAC state.');
            end
            rows=table();
            srCommits=cell(0,3);
            for k=1:numel(due)
                o=due(k);
                if o.Transport=="PUSCH"
                    sixgr.system.validateSLSPUSCHUCIReservation(o,struct( ...
                        'AsOfAbsoluteSlot0',now,'IssuedPUSCHGrants',{issued}));
                    hashes=cellfun(@grantDigest,num2cell(executed),'UniformOutput',false);
                    assert(any(string(hashes)==o.PUSCHGrantSHA256), ...
                        'sixgr:system:SLSUCINotExecuted','Do not complete UCI on an unexecuted PUSCH.');
                end
                if o.HARQBits>0
                    % The end-of-slot ideal-control model may deliver a
                    % same-slot completed decision, unlike a slot-start
                    % waveform producer. Neither may complete missing HARQ
                    % fields or release their source-cell ownership.
                    payload=obj.resolveHARQPayload(o,now,false);
                    if ~payload.Available, continue; end
                end
                srKnown=o.SRBits==0; positiveSR=NaN; srClaim=false;
                selectedSRResource=NaN; srSelectionPolicy="not_selected";
                srDisposition="unmodeled_SR_no_delivery_claim";
                if o.SRBits==0, positiveSR=0; srDisposition="no_SR_field";
                elseif o.Transport=="PUSCH"
                    srDisposition="not_carried_on_PUSCH_no_SR_delivery_claim";
                elseif ~isempty(obj.SRProcedures)
                    srPayload=obj.srPayloadAtSlotStart(o,now);
                    if ~srPayload.Available, continue; end
                    srKnown=true; positiveSR=numel(srPayload.PositiveSchedulingRequestIDs);
                    selectedSRResource=srPayload.SelectedSRResourceConfigurationID;
                    srSelectionPolicy=srPayload.SelectionPolicy;
                    assert(positiveSR<=1,'sixgr:system:MultiplePositiveSRsRequireSelection', ...
                        'Select one positive SR indication before claiming delivery or advancing any counter.');
                    srClaim=positiveSR>0;
                    srDisposition="negative_SR_no_positive_delivery";
                    if srClaim, srDisposition="modeled_positive_SR_transmitted_ideal_delivery"; end
                    for srIndex=1:numel(srPayload.ProcedureIndices)
                        srCommits(end+1,:)={srPayload.ProcedureIndices(srIndex), ...
                            srPayload.Snapshots{srIndex},o.ResourceID}; %#ok<AGROW>
                    end
                end
                row=table(o.ResourceID,o.CellID,o.UEIndex,now,o.Transport, ...
                    "ideal_error_free_delayed_control",false,false, ...
                    'VariableNames',{'ObligationID','CellID','UEIndex','CompletionAbsoluteSlot0', ...
                    'Transport','CompletionSource','WaveformBacked','PhysicalDecodeQualified'});
                row.RNTI=o.RNTI;
                row.SRPayloadKnown=srKnown; row.PositiveSRCount=positiveSR;
                row.SRDeliveryClaimed=srClaim; row.SRDisposition=srDisposition;
                row.SelectedSRResourceConfigurationID=selectedSRResource;
                row.SRSelectionPolicy=srSelectionPolicy;
                rows=[rows;row]; %#ok<AGROW>
            end
            if isempty(rows), return; end
            assert(isempty(obj.CompletionTrace) || ~any(ismember(rows.ObligationID,obj.CompletionTrace.ObligationID)), ...
                'sixgr:system:SLSUCIDuplicateCompletion','Feedback must complete exactly once.');
            if ~isempty(srCommits)
                owners=cell2mat(srCommits(:,1));
                assert(numel(unique(owners))==numel(owners), ...
                    'sixgr:system:MultipleSRResourcesRequireSelection', ...
                    'Select one valid resource per SR procedure before committing any transmission.');
                for commitIndex=1:size(srCommits,1)
                    obj.SRProcedures{srCommits{commitIndex,1}}.commitTransmission( ...
                        srCommits{commitIndex,2},srCommits{commitIndex,3});
                end
            end
            obj.CompletionTrace=[obj.CompletionTrace;rows];
        end
        function yes=reportCompleted(obj,ue,cellID,reportSlot)
            yes=false;
            if isempty(obj.CompletionTrace) || isempty(obj.Trace), return; end
            t=obj.Trace;
            ids=t.ObligationID(t.UEIndex==ue & t.CellID==cellID & ...
                t.AbsoluteSlot0==reportSlot & t.CSIPart1Bits>0);
            yes=any(ismember(ids,obj.CompletionTrace.ObligationID));
        end
        function requireHARQCompletion(obj,feedback,cellID,slot)
            for k=1:numel(feedback)
                f=feedback(k);
                matches=find(cellfun(@(g) g.RNTI==f.RNTI && ...
                    g.ScheduledAbsoluteSlot==f.SourceSlot && g.HARQFeedbackAbsoluteSlot==slot, ...
                    obj.Grants) & obj.Cells(:).'==cellID);
                assert(isscalar(matches),'sixgr:system:SLSUCIHARQIdentity', ...
                    'Feedback must refer to exactly one actual issued DL grant.');
                assert(isfield(f,'Ack') && isBinary(f.Ack) && ~isempty(obj.HARQDecisionTrace), ...
                    'sixgr:system:SLSUCIHARQDecisionMissing', ...
                    'An ideal feedback reservation cannot manufacture a decoder ACK/NACK.');
                decision=obj.HARQDecisionTrace(obj.HARQDecisionTrace.SourceGrantSHA256==obj.Digests(matches),:);
                assert(height(decision)==1 && decision.CellID==cellID && decision.RNTI==f.RNTI && ...
                    decision.TransmissionAbsoluteSlot0==f.SourceSlot && decision.FeedbackAbsoluteSlot0==slot && ...
                    decision.ReceiveCompletionAbsoluteSlot0<=slot && decision.ACK==logical(f.Ack), ...
                    'sixgr:system:SLSUCIHARQDecisionMismatch', ...
                    'Delivered ideal feedback must retain the completed decision, original grant and completion clock.');
                issued=obj.Grants{matches};
                for field=["HarqID","RV","NDI","IsRetransmission"]
                    if ~isfield(f,field), continue; end
                    missing=NaN; if field=="IsRetransmission", missing=false; end
                    expected=sixgr.util.structGet(issued,"HARQ."+field,missing);
                    assert(isequaln(double(f.(field)),double(expected)), ...
                        'sixgr:system:SLSUCIHARQDecisionMismatch', ...
                        'Delivered %s differs from the original issued HARQ process.',field);
                end
                if isfield(f,'TBSBits')
                    [bits,~]=sixgr.util.resolveGrantTBSBits(issued,'SLSDynamicPUCCH.requireHARQCompletion');
                    assert(isequal(double(f.TBSBits),double(bits)), ...
                        'sixgr:system:SLSUCIHARQDecisionMismatch','Delivered feedback changed the original transport-block size.');
                end
                assert(~isempty(obj.Trace) && ~isempty(obj.CompletionTrace), ...
                    'sixgr:system:SLSUCINotCompleted','No feedback before its transport completion.');
                u=obj.Grants{matches}.UEIndex;
                t=obj.Trace; ids=t.ObligationID(t.UEIndex==u & t.CellID==cellID & ...
                    t.AbsoluteSlot0==slot & t.HARQBits>0);
                assert(isscalar(ids) && any(obj.CompletionTrace.ObligationID==ids), ...
                    'sixgr:system:SLSUCINotCompleted','No ACK from an absent or uncompleted UCI obligation.');
            end
        end
        function appendDL(obj,grants,cells,now)
            assert(numel(grants)==numel(cells),'sixgr:system:DynamicPUCCHIdentity','Grant/cell ownership mismatch.');
            for k=1:numel(grants)
                g=grants(k);
                u=sixgr.system.resolveGrantUEIndex(g);
                assert(g.RNTI==obj.rntiForUE(u),'sixgr:system:UCIIdentityMismatch','Issued RNTI differs from its installed UE identity.');
                assert(g.PHYGrant.IsFrozen && g.ControlAbsoluteSlot<=now && ...
                    g.HARQFeedbackAbsoluteSlot>g.ScheduledAbsoluteSlot && g.HARQFeedbackAbsoluteSlot>now && ...
                    g.PHYGrant.CodingLayout.NumCodewords==1, ...
                    'sixgr:system:DynamicPUCCHGrant','Require a frozen single-codeword grant and causal K1.');
                digest=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(g)),'UTF-8'))));
                if any(obj.Digests==digest), continue; end
                obj.Grants{end+1}=g; obj.Cells(end+1)=cells(k); obj.Digests(end+1)=digest;
            end
        end
        function obligations=snapshot(obj,now,target,serving,references)
            assert(target>=now,'sixgr:system:DynamicPUCCHClock','No backward reservation query.');
            obj.configureServingCells(serving,now);
            obligations=struct([]); cfg=obj.Cfg;
            carrier=sixgr.phy.grid.makeCarrier(cfg); carrier.NSlot=mod(target,carrier.SlotsPerFrame);
            id=cfg.phy.frame.DefaultIdentity;
            for u=1:numel(serving)
                c=serving(u);
                rnti=obj.rntiForUE(u);
                ue=struct('UEID',u,'RNTI',rnti,'ServingCell',c,'PUCCHCell',c, ...
                    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
                cfg=obj.configForUE(ue);
                rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
                matches=find(cellfun(@(g) g.UEIndex==u && g.RNTI==rnti && g.HARQFeedbackAbsoluteSlot==target && ...
                    g.ControlAbsoluteSlot<=now,obj.Grants) & obj.Cells(:).'==c);
                nh=numel(matches); resource=[]; known=0; last=[];
                if nh>0
                    times=cellfun(@(g) g.ControlAbsoluteSlot,obj.Grants(matches));
                    [known,j]=max(times); last=obj.Grants{matches(j)};
                    resource=harqResource(rrc,last,nh);
                end
                sr=sixgr.truth.buildConfiguredSRCalendar(cfg,ue,target+1,target+1);
                sr=sr(sr.ULResourceAvailable,:); usedSR=false(height(sr),1);
                csi=[]; nc1=0; nc2=0; referenceAt=NaN;
                if cfg.phy.csi.reportCSI
                    [cal,contexts]=sixgr.truth.buildPeriodicCSIReportObligations(cfg,ue,target+1,target+1);
                    for k=1:height(cal)
                        valid=false;
                        for ref=references(:).'
                            if ref.UEIndex==u && ref.ServingCell==c && ref.ReportAbsoluteSlot0==target && ...
                                ref.SourceAbsoluteSlot0<=cal.CSIReferenceSlot(k)-1 && ref.ReferenceAvailableAtSlot0<=now
                                valid=true; referenceAt=ref.ReferenceAvailableAtSlot0;
                            end
                        end
                        if valid && cal.ULResourceAvailable(k)
                            assert(isempty(csi),'sixgr:system:DynamicPUCCHMultiCSI','Multi-report selection needs explicit priority.');
                            csi=rrc.resourceByID(cal.PUCCHResourceID(k));
                            nc1=contexts{k}.CSIPart1Bits; nc2=contexts{k}.CSIPart2Bits;
                        end
                    end
                end
                if ~isempty(resource) && ~isempty(csi) && ~overlap(resource,csi)
                    emit(csi,0,0,nc1,nc2,referenceAt,referenceAt,"configured_csi");
                    csi=[]; nc1=0; nc2=0;
                end
                if isempty(resource) && ~isempty(csi), resource=csi; known=referenceAt; end
                if ~isempty(resource)
                    for k=1:height(sr)
                        usedSR(k)=overlap(resource,rrc.resourceByID(sr.PUCCHResourceID(k)));
                        if ~isempty(csi), usedSR(k)=usedSR(k)||overlap(csi,rrc.resourceByID(sr.PUCCHResourceID(k))); end
                    end
                    ns=ceil(log2(nnz(usedSR)+1));
                    if nh>0
                        count=nh+ns+nc1+nc2;
                        if nh<=2 && nc1+nc2==0, count=nh; end
                        resource=harqResource(rrc,last,count);
                    end
                    procedure="dynamic_harq";
                    if nh==0, procedure="configured_csi";
                    elseif nc1+nc2>0, procedure="dynamic_harq_csi"; end
                    emit(resource,nh,ns,nc1,nc2,known,referenceAt,procedure);
                end
                for k=find(~usedSR).'
                    emit(rrc.resourceByID(sr.PUCCHResourceID(k)),0,1,0,0,0,NaN,"sr_only");
                end
            end
            for bindingIndex=1:numel(obj.TransportBindings)
                binding=obj.TransportBindings{bindingIndex};
                if binding.Grant.ScheduledAbsoluteSlot~=target || binding.Grant.ControlAbsoluteSlot>now, continue; end
                assert(~isempty(obligations) && any(string({obligations.ResourceID})==binding.Obligation.ResourceID), ...
                    'sixgr:system:SLSUCILateObligation','An issued PUSCH UCI obligation disappeared before completion.');
            end
            % No code-domain orthogonality is assumed between different UEs.
            for a=1:numel(obligations)
                for b=a+1:numel(obligations)
                    x=obligations(a); y=obligations(b);
                    if x.CellID==y.CellID && x.UEIndex~=y.UEIndex
                        assert(isempty(intersect(x.Coordinates0Based(:,1:2),y.Coordinates0Based(:,1:2),'rows')), ...
                            'sixgr:system:DynamicPUCCHCollision','Allocate noncolliding per-UE PUCCH resources.');
                    end
                end
            end
            function emit(r,h,s,c1,c2,knownAt,refAt,procedure)
                if c1+c2>0, knownAt=max(knownAt,refAt); end
                knownAt=max(knownAt,sixgr.util.structGet(cfg, ...
                    'validation.pucch_resources.installed_absolute_slot0',0));
                name="sls_pucch_"+c+"_"+u+"_"+target+"_"+r.ID;
                context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',name, ...
                    'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',h+s+c1, ...
                    'Sequence2Length',c2,'HARQACKBits',h,'SRBits',s,'CSIPart1Bits',c1,'CSIPart2Bits',c2,'PriorityIndex',0));
                identity=struct('ObservationID',name,'ResourceID',r.ID,'RNTI',rnti, ...
                    'AbsoluteSlot0',target,'Source',"ideal_control_SLS_receive_obligation", ...
                    'TimingSource',"configured_calendar_and_scheduled_K1");
                if procedure~="sr_only", identity.ResourceSelectionProcedure=procedure; end
                assignment=sixgr.phy.pucch.PUCCHReceptionAssignment(identity,rrc,context);
                mapped=sixgr.phy.frame.ChannelAllocationMaterializer.materializePUCCH(carrier,assignment.Resource.toolboxConfig(),'AbsoluteSlot',target);
                o=struct('ResourceID',name,'CellID',c,'UEIndex',u,'Direction',"UL", ...
                    'AbsoluteSlot0',target,'KnownAtAbsoluteSlot0',knownAt,'Channel',"PUCCH", ...
                    'Coordinates0Based',double(mapped.ActualCoordinates0Based), ...
                    'EvidenceKind',"scheduled_receive_obligation",'Source',"ideal_control_SLS_not_waveform_reception", ...
                    'Transport',"PUCCH",'CSIOnly',h==0 && c1+c2>0,'ReferenceAvailableAtSlot0',refAt, ...
                    'HARQBits',h,'SRBits',s,'CSIPart1Bits',c1,'CSIPart2Bits',c2,'ContextDigest',string(context.Digest), ...
                    'PUCCHConfigurationEpoch',rrc.ConfigurationEpoch,'PUCCHRRCContextDigest',string(rrc.Digest));
                o.RNTI=rnti; o.PUSCHGrant=struct(); o.PUSCHGrantSHA256="";
                o.SchedulingRequestIDs=zeros(0,1);
                o.SRResourceConfigurationIDs=zeros(0,1);
                if s>0
                    selectedSR=usedSR;
                    if procedure=="sr_only", selectedSR=sr.PUCCHResourceID==r.ID; end
                    o.SchedulingRequestIDs=sort(unique(double(sr.SchedulingRequestID(selectedSR))));
                    o.SRResourceConfigurationIDs=sort(double(sr.SRResourceConfigurationID(selectedSR)));
                    assert(~isempty(o.SchedulingRequestIDs),'sixgr:system:MissingSRProcedureIdentity', ...
                        'Typed SR fields must retain independently configured SR identities.');
                end
                o.PUSCHUCIAllocatedRECount=0; o.SRDisposition="dedicated_or_combined_PUCCH";
                o.HARQSourceGrantSHA256="";
                if h>0
                    % Identity of actual issued DL assignments, not ACK
                    % values. This is an ideal-control model, not a claim
                    % of physical Type-2 missing-DCI reconstruction.
                    sourceSlots=cellfun(@(g) g.ScheduledAbsoluteSlot,obj.Grants(matches));
                    [~,order]=sort(sourceSlots);
                    o.HARQSourceGrantSHA256=strjoin(obj.Digests(matches(order)),"|");
                end
                for bindingIndex=1:numel(obj.TransportBindings)
                    binding=obj.TransportBindings{bindingIndex};
                    if binding.Obligation.ResourceID~=name, continue; end
                    assert(isequaln(binding.Obligation,o), ...
                        'sixgr:system:SLSUCILateObligation', ...
                        'The obligation changed after PUSCH issuance; never silently change its frozen UCI allocation.');
                    o.Transport="PUSCH"; o.PUSCHGrant=binding.Grant;
                    o.PUSCHGrantSHA256=binding.GrantSHA256;
                    o.PUSCHUCIAllocatedRECount=binding.Grant.SLSUCIAllocation.AllocatedRECount;
                    o.KnownAtAbsoluteSlot0=max(o.KnownAtAbsoluteSlot0,binding.Grant.ControlAbsoluteSlot);
                    o.SRDisposition="not_carried_on_PUSCH_no_SR_delivery_claim";
                end
                obligations=[obligations o];
                if now==target
                    row=table(name,c,u,target,o.KnownAtAbsoluteSlot0,r.ID,h,s,c1,c2,string(context.Digest), ...
                        o.Transport,"ideal_error_free_delayed_control",false,rrc.ConfigurationEpoch,string(rrc.Digest), ...
                        o.PUSCHGrantSHA256,o.PUSCHUCIAllocatedRECount,o.SRDisposition,o.HARQSourceGrantSHA256, ...
                        'VariableNames',{'ObligationID','CellID','UEIndex','AbsoluteSlot0','KnownAtAbsoluteSlot0', ...
                        'PUCCHResourceID','HARQBits','SRBits','CSIPart1Bits','CSIPart2Bits','ContextDigest', ...
                        'Transport','DeliveryAssumption','WaveformBacked','PUCCHConfigurationEpoch','PUCCHRRCContextDigest', ...
                        'PUSCHGrantSHA256','PUSCHUCIAllocatedRECount','SRDisposition','HARQSourceGrantSHA256'});
                    row.RNTI=o.RNTI;
                    if isempty(obj.Trace) || ~any(obj.Trace.ObligationID==name)
                        obj.Trace=[obj.Trace;row];
                    else
                        ix=find(obj.Trace.ObligationID==name);
                        assert(isscalar(ix) && isequaln(obj.Trace(ix,:),row), ...
                            'sixgr:system:DynamicPUCCHMutation','Current-slot obligation changed after publication.');
                    end
                end
            end
        end
    end
    methods (Access=private)
        function payload=resolveHARQPayload(obj,o,asOfAbsoluteSlot0,atSlotStart)
            validateattributes(asOfAbsoluteSlot0,{'numeric'},{'scalar','integer','finite','nonnegative'});
            assert(asOfAbsoluteSlot0<=o.AbsoluteSlot0 && o.RNTI==obj.rntiForUE(o.UEIndex), ...
                'sixgr:system:SLSHARQPayloadClock','Do not backdate a payload or change its UE identity.');
            matches=find(cellfun(@(g)g.UEIndex==o.UEIndex && g.RNTI==o.RNTI && ...
                g.HARQFeedbackAbsoluteSlot==o.AbsoluteSlot0 && g.ControlAbsoluteSlot<=asOfAbsoluteSlot0, ...
                obj.Grants) & obj.Cells==o.CellID);
            slots=cellfun(@(g)g.ScheduledAbsoluteSlot,obj.Grants(matches));
            [~,order]=sort(slots); digests=obj.Digests(matches(order));
            assert(numel(digests)==o.HARQBits && strjoin(digests,"|")==o.HARQSourceGrantSHA256, ...
                'sixgr:system:SLSHARQPayloadIdentity','Resolve the exact independently scheduled HARQ ownership, not a prefix.');
            payload=struct('Available',false,'HARQACKBits',zeros(0,1,'int8'), ...
                'SourceGrantSHA256',digests,'DecisionRows',table(), ...
                'Status',"missing_or_not_yet_completed_decision", ...
                'OrderingAssumption',"ideal_received_control_scheduled_assignment_order_not_physical_missing_DCI", ...
                'WaveformBacked',false,'PhysicalDecodeQualified',false);
            rows=table();
            for digest=digests(:).'
                if isempty(obj.HARQDecisionTrace), return; end
                ix=find(obj.HARQDecisionTrace.SourceGrantSHA256==digest);
                if isempty(ix), return; end
                row=obj.HARQDecisionTrace(ix,:);
                if row.ReceiveCompletionAbsoluteSlot0>asOfAbsoluteSlot0 || ...
                        (atSlotStart && row.ReceiveCompletionAbsoluteSlot0==asOfAbsoluteSlot0)
                    return;
                end
                rows=[rows;row]; %#ok<AGROW>
            end
            payload.Available=true; payload.Status="causal_modeled_harq_fields_available";
            payload.DecisionRows=rows;
            if ~isempty(rows), payload.HARQACKBits=int8(rows.ACK); end
        end
    end
end
function digest=grantDigest(g)
digest=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(g)),'UTF-8'))));
end
function yes=isBinary(value)
yes=(islogical(value)||isnumeric(value)) && isscalar(value) && isreal(value) && ...
    isfinite(value) && any(value==[0 1]);
end
function yes=overlap(a,b)
yes=a.Data.StartSymbol<b.Data.StartSymbol+b.Data.NumSymbols && b.Data.StartSymbol<a.Data.StartSymbol+a.Data.NumSymbols;
end
function due=overlappingObligations(due,symbolAllocation)
% Half-open OFDM-symbol intervals: an adjacent boundary is not overlap.
a=double(symbolAllocation);
validateattributes(a,{'numeric'},{'vector','numel',2,'integer','finite','nonnegative'});
assert(a(2)>0,'sixgr:system:SLSUCIInvalidAllocation','PUSCH must occupy at least one symbol.');
if isempty(due), return; end
inTime=arrayfun(@(o)any(o.Coordinates0Based(:,2)>=a(1) & ...
    o.Coordinates0Based(:,2)<sum(a)),due);
due=due(inTime);
end
function r=harqResource(rrc,g,count)
set=sixgr.phy.pucch.PUCCHResourceSetResolver.resolveBitCount(count,rrc,rrc.ConfigurationEpoch);
packed=sixgr.phy.pdcch.decodeDCIPayload(g.DCI.Bits,g.DCI.Format,g.DCI.ContextData);
pri=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(struct( ...
    'ResourceSetID',set.ID,'ResourceListSize',numel(set.ResourceIDs),'PRIFieldWidth',3, ...
    'PRIValue',double(packed.Fields.pucch_resource_indicator), ...
    'FirstCCE',sixgr.util.structGet(g,'PDCCHGrantFirstCCE',NaN),'NumCCE',sixgr.util.structGet(g,'PDCCHGrantNumCCE',NaN), ...
    'RequiresSet0CCEFormula',set.ID==0 && numel(set.ResourceIDs)>8));
assert(pri.Valid,'sixgr:system:DynamicPUCCHPRI','Scheduled DCI must resolve a valid PRI.');
r=rrc.resourceByID(set.ResourceIDs(pri.Ordinal));
end
