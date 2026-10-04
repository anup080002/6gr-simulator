classdef SLSAggregateSRController < handle
    % Aggregate FTP3 SR triggers under EXPLICIT ideal gNB buffer knowledge.
    % Not received-BSR scheduling or MAC CE/subheader overhead qualification.
    properties (SetAccess=private)
        Policy struct
        Procedures cell = cell(0,1)
        ServingCells double = []
    end
    properties (Access=private)
        Ledger
        FileLedger
        RNTIs double
        Installed logical = false
        LastArrivalSlot0 double = -1
        GrantDigests string = strings(0,1)
    end
    methods
        function obj=SLSAggregateSRController(cfg,ledger,fileLedger,rntis)
            policy=sixgr.util.structGet(cfg,'system.linkAbstraction.dynamicPUCCH.schedulingRequestMAC',struct());
            required={'enabled','researchClass','bufferModel','schedulerBufferKnowledge', ...
                'grantPayloadAccounting','positiveSRSelection','trafficSchedulingRequestID','procedures'};
            assert(isstruct(policy) && isscalar(policy) && all(isfield(policy,required)) && ...
                isempty(setdiff(fieldnames(policy),required)), ...
                'sixgr:system:InvalidSRMACPolicy','Supply the complete explicit SLS SR MAC policy.');
            assert(isequal(policy.enabled,true) && string(policy.researchClass)=="optional_research_experiment" && ...
                string(policy.bufferModel)=="single_logical_channel_unallocated_ftp3" && ...
                string(policy.schedulerBufferKnowledge)=="ideal_instantaneous_unallocated_buffer" && ...
                string(policy.grantPayloadAccounting)=="whole_tb_application_budget_no_mac_ce", ...
                'sixgr:system:UnsupportedSRMACModel','Do not mislabel aggregate SR as received-BSR or full MAC execution.');
            assert(isscalar(string(policy.positiveSRSelection)) && ...
                any(string(policy.positiveSRSelection)==["require_explicit_selection","lowest_scheduling_request_resource_id"]), ...
                'sixgr:system:InvalidSRSelectionPolicy','Configure an explicit supported ordinary-traffic SR selection policy.');
            assert(isa(ledger,'sixgr.system.SLSDynamicPUCCH') && ...
                isa(fileLedger,'sixgr.system.FTP3FileLedger'), ...
                'sixgr:system:SRMACRequiresFTP3','Bind actual dynamic UCI and the admitted file ledger.');
            validateattributes(rntis,{'numeric'},{'vector','integer','positive','finite','<=',65535});
            assert(fileLedger.NumUE==numel(rntis),'sixgr:system:SRMACConfigurationMismatch', ...
                'The SR identity population must equal the owned traffic population.');
            validateattributes(policy.trafficSchedulingRequestID,{'numeric'},{'scalar','integer','nonnegative','finite'});
            entries=policy.procedures;
            assert(isstruct(entries) && ~isempty(entries) && all(isfield(entries, ...
                {'SchedulingRequestID','ProhibitTimerSlots','MaxTransmissions'})) && ...
                isempty(setdiff(fieldnames(entries), ...
                {'SchedulingRequestID','ProhibitTimerSlots','MaxTransmissions'})), ...
                'sixgr:system:InvalidSRMACPolicy','Supply all per-ID timer/counter policies.');
            for entry=reshape(entries,1,[])
                validateattributes(entry.SchedulingRequestID,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
                validateattributes(entry.ProhibitTimerSlots,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
                validateattributes(entry.MaxTransmissions,{'numeric'},{'scalar','real','finite','integer','positive'});
            end
            ids=[entries.SchedulingRequestID];
            resources=cfg.validation.pucch_resources.scheduling_request_resources;
            configured=unique([resources.scheduling_request_id]);
            assert(numel(unique(ids))==numel(ids) && isequal(sort(ids(:)),sort(configured(:))) && ...
                ismember(policy.trafficSchedulingRequestID,ids), ...
                'sixgr:system:SRMACConfigurationMismatch','Policy must cover exactly the installed SR identities.');
            obj.Policy=policy; obj.Ledger=ledger; obj.FileLedger=fileLedger; obj.RNTIs=rntis(:);
        end
        function install(obj,serving,slot0)
            validateattributes(slot0,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(serving,{'numeric'},{'vector','integer','positive','finite','numel',numel(obj.RNTIs)});
            if obj.Installed
                assert(isequal(serving(:),obj.ServingCells), ...
                    'sixgr:system:SRProcedureHandoverRequiresReconfiguration', ...
                    'Drain/reconfigure MAC and SR ownership before handover.');
                return;
            end
            procedures=cell(numel(obj.RNTIs)*numel(obj.Policy.procedures),1);
            procedureIndex=0;
            for u=1:numel(obj.RNTIs)
                for policy=reshape(obj.Policy.procedures,1,[])
                    id=struct('UEIndex',u,'RNTI',obj.RNTIs(u),'CellID',serving(u), ...
                        'SchedulingRequestID',policy.SchedulingRequestID);
                    p=sixgr.system.SLSSchedulingRequestProcedure(id,policy);
                    procedureIndex=procedureIndex+1; procedures{procedureIndex}=p;
                end
            end
            obj.Ledger.installSRProcedures(procedures);
            obj.ServingCells=serving(:); obj.Procedures=procedures; obj.Installed=true;
        end
        function before=beforeAdmission(obj)
            assert(obj.Installed,'sixgr:system:SRMACNotInstalled','Install UE/cell owners before traffic.');
            before=zeros(numel(obj.RNTIs),1);
            for u=1:numel(before), before(u)=obj.FileLedger.unallocatedBits(u,"UL"); end
        end
        function afterAdmission(obj,slot0,before)
            validateattributes(slot0,{'numeric'},{'scalar','integer','nonnegative','finite','>',obj.LastArrivalSlot0});
            validateattributes(before,{'numeric'},{'vector','integer','nonnegative','finite','numel',numel(obj.RNTIs)});
            after=obj.beforeAdmission();
            assert(all(after>=before(:)),'sixgr:system:SRAdmissionMutation', ...
                'The admission callback must not include service or tail dropping.');
            obj.LastArrivalSlot0=slot0;
            for u=1:numel(after)
                if before(u)==0 && after(u)>0
                    p=obj.trafficProcedure(u);
                    p.trigger(slot0,"ftp3_empty_to_nonempty_ue_"+u+"_slot_"+slot0);
                end
            end
        end
        function receivedULGrants(obj,grants,cells,slot0)
            % Ideal received control is the existing declared SLS assumption.
            % Compare native frozen-grant capacity with the *unallocated* queue;
            % neither receipt of an arbitrary grant nor retransmission cancels SR.
            assert(numel(grants)==numel(cells),'sixgr:system:SRGrantIdentity','One serving cell per grant.');
            for k=1:numel(grants)
                g=grants(k); u=sixgr.system.resolveGrantUEIndex(g,numel(obj.RNTIs));
                assert(g.RNTI==obj.RNTIs(u) && cells(k)==obj.ServingCells(u) && ...
                    g.ControlAbsoluteSlot==slot0 && g.ScheduledAbsoluteSlot>=slot0 && g.PHYGrant.IsFrozen, ...
                    'sixgr:system:SRGrantIdentity','Retain received-control clock, UE/cell and frozen allocation.');
                if logical(sixgr.util.structGet(g,'HARQ.IsRetransmission',false)), continue; end
                digest=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
                    jsonencode(sixgr.util.jsonSafeValue(g)),'UTF-8'))));
                assert(~ismember(digest,obj.GrantDigests),'sixgr:system:DuplicateSRGrant','Do not consume a received grant twice.');
                [bits,~]=sixgr.util.resolveGrantTBSBits(g,'SLSAggregateSRController');
                pending=obj.FileLedger.unallocatedBits(u,"UL");
                assert(mod(bits,8)==0 && mod(pending,8)==0, ...
                    'sixgr:system:SRBufferByteAlignment','This configured MAC buffer model requires whole bytes.');
                p=obj.trafficProcedure(u);
                if p.Pending && bits>=pending
                    p.cancelForGrant(slot0,bits/8,pending/8,digest);
                end
                obj.GrantDigests(end+1)=digest;
            end
        end
    end
    methods (Access=private)
        function p=trafficProcedure(obj,u)
            matches=cellfun(@(x)x.Identity.UEIndex==u && ...
                x.Identity.SchedulingRequestID==obj.Policy.trafficSchedulingRequestID,obj.Procedures);
            assert(nnz(matches)==1,'sixgr:system:SRMACNotInstalled','Resolve exactly one owned traffic SR.');
            p=obj.Procedures{find(matches,1)};
        end
    end
end
