classdef SLSDynamicPUCCH < handle
    % Payload-free receive obligations under ideal received-control SLS.
    % Actual installed PUCCH resources/capacity; NOT waveform UCI outcomes.
    properties (SetAccess=private)
        Trace table = table()
        CompletionTrace table = table()
    end
    properties (Access=private)
        Cfg struct
        Grants cell = cell(0,1)
        Cells double = zeros(0,1)
        Digests string = strings(0,1)
        TransportBindings cell = cell(0,1)
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
        end
        function yes=multiplexingEnabled(obj)
            yes=string(obj.Cfg.system.linkAbstraction.dynamicPUCCH.transportPolicy)=="causal_native_pusch_multiplexing";
        end
        function grants=bindPUSCH(obj,grants,cellID,now,serving,references)
            % Called before issuance/queueing, never on an already issued TB.
            % Conservative supported subset: one same-cell obligation and a
            % single native, data-bearing PUSCH with all UCI known at control.
            if ~obj.multiplexingEnabled() || isempty(grants), return; end
            bound=cell(numel(grants),1); additions=cell(0,1);
            for k=1:numel(grants)
                g=grants(k); g.SLSUCIAllocation=struct(); g.SLSUCIObligationID="";
                g.ServingCell=cellID; g.UEIndex=g.RNTI;
                target=g.ScheduledAbsoluteSlot;
                due=obj.snapshot(now,target,serving,references);
                if ~isempty(due), due=due([due.UEIndex]==g.RNTI & [due.CellID]==cellID); end
                if isempty(due), bound{k}=g; continue; end
                assert(isscalar(due) && due.Transport=="PUCCH" && ...
                    due.HARQBits+due.CSIPart1Bits+due.CSIPart2Bits>0 && ...
                    g.ControlAbsoluteSlot==now && target>now && g.PHYGrant.IsFrozen, ...
                    'sixgr:system:SLSUCIUnsupportedOverlap', ...
                    'Multiplex only one causal HARQ/CSI occasion on a future issued PUSCH; retain dedicated SR-only resources.');
                a=double(g.SymbolAllocation);
                assert(any(due.Coordinates0Based(:,2)>=a(1) & due.Coordinates0Based(:,2)<sum(a)), ...
                    'sixgr:system:SLSUCIUnsupportedOverlap','The selected PUSCH must overlap the PUCCH in symbols.');
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
        function completeSlot(obj,now,serving,references,issued,executed)
            % Model completion only. Never manufacture a UCI CRC or bit row.
            due=obj.snapshot(now,now,serving,references);
            rows=table();
            for k=1:numel(due)
                o=due(k);
                if o.Transport=="PUSCH"
                    sixgr.system.validateSLSPUSCHUCIReservation(o,struct( ...
                        'AsOfAbsoluteSlot0',now,'IssuedPUSCHGrants',{issued}));
                    hashes=cellfun(@grantDigest,num2cell(executed),'UniformOutput',false);
                    assert(any(string(hashes)==o.PUSCHGrantSHA256), ...
                        'sixgr:system:SLSUCINotExecuted','Do not complete UCI on an unexecuted PUSCH.');
                end
                row=table(o.ResourceID,o.CellID,o.UEIndex,now,o.Transport, ...
                    "ideal_error_free_delayed_control",false,false, ...
                    'VariableNames',{'ObligationID','CellID','UEIndex','CompletionAbsoluteSlot0', ...
                    'Transport','CompletionSource','WaveformBacked','PhysicalDecodeQualified'});
                rows=[rows;row]; %#ok<AGROW>
            end
            if isempty(rows), return; end
            assert(isempty(obj.CompletionTrace) || ~any(ismember(rows.ObligationID,obj.CompletionTrace.ObligationID)), ...
                'sixgr:system:SLSUCIDuplicateCompletion','Feedback must complete exactly once.');
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
                assert(~isempty(obj.Trace) && ~isempty(obj.CompletionTrace), ...
                    'sixgr:system:SLSUCINotCompleted','No feedback before its transport completion.');
                t=obj.Trace; ids=t.ObligationID(t.UEIndex==f.RNTI & t.CellID==cellID & ...
                    t.AbsoluteSlot0==slot & t.HARQBits>0);
                assert(isscalar(ids) && any(obj.CompletionTrace.ObligationID==ids), ...
                    'sixgr:system:SLSUCINotCompleted','No ACK from an absent or uncompleted UCI obligation.');
            end
        end
        function appendDL(obj,grants,cells,now)
            assert(numel(grants)==numel(cells),'sixgr:system:DynamicPUCCHIdentity','Grant/cell ownership mismatch.');
            for k=1:numel(grants)
                g=grants(k);
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
            obligations=struct([]); cfg=obj.Cfg;
            carrier=sixgr.phy.grid.makeCarrier(cfg); carrier.NSlot=mod(target,carrier.SlotsPerFrame);
            id=cfg.phy.frame.DefaultIdentity;
            for u=1:numel(serving)
                c=serving(u); ue=struct('UEID',u,'RNTI',u,'ServingCell',c,'PUCCHCell',c, ...
                    'ComponentCarrier',id.ScheduledCCID,'ActiveULBWP',id.ULBWPID);
                rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
                matches=find(cellfun(@(g) g.RNTI==u && g.HARQFeedbackAbsoluteSlot==target && ...
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
                name="sls_pucch_"+c+"_"+u+"_"+target+"_"+r.ID;
                context=sixgr.phy.pucch.UCIReportContext(struct('ReportID',name, ...
                    'ConfigurationEpoch',rrc.ConfigurationEpoch,'Sequence1Length',h+s+c1, ...
                    'Sequence2Length',c2,'HARQACKBits',h,'SRBits',s,'CSIPart1Bits',c1,'CSIPart2Bits',c2,'PriorityIndex',0));
                identity=struct('ObservationID',name,'ResourceID',r.ID,'RNTI',u, ...
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
                    'HARQBits',h,'SRBits',s,'CSIPart1Bits',c1,'CSIPart2Bits',c2,'ContextDigest',string(context.Digest));
                o.RNTI=u; o.PUSCHGrant=struct(); o.PUSCHGrantSHA256="";
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
                        o.Transport,"ideal_error_free_delayed_control",false, ...
                        o.PUSCHGrantSHA256,o.PUSCHUCIAllocatedRECount,o.SRDisposition,o.HARQSourceGrantSHA256, ...
                        'VariableNames',{'ObligationID','CellID','UEIndex','AbsoluteSlot0','KnownAtAbsoluteSlot0', ...
                        'PUCCHResourceID','HARQBits','SRBits','CSIPart1Bits','CSIPart2Bits','ContextDigest', ...
                        'Transport','DeliveryAssumption','WaveformBacked', ...
                        'PUSCHGrantSHA256','PUSCHUCIAllocatedRECount','SRDisposition','HARQSourceGrantSHA256'});
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
end
function digest=grantDigest(g)
digest=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(g)),'UTF-8'))));
end
function yes=overlap(a,b)
yes=a.Data.StartSymbol<b.Data.StartSymbol+b.Data.NumSymbols && b.Data.StartSymbol<a.Data.StartSymbol+a.Data.NumSymbols;
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
