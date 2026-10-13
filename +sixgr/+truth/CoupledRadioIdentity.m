classdef CoupledRadioIdentity
% Cell-scoped received radio identity; logical UE indices never change.
% Configured identities are bootstrap/preconnected installation, not the
% identity assigned by a completed random-access procedure. Frozen grants,
% HARQ keys and received histories must never be renamed by this class.
methods (Static)
    function rnti=dataRNTI(cfg,ue,direction)
        % Read the configuration frozen for this operation, not the latest
        % mutable access state or an arithmetic function of the UE ordinal.
        direction=upper(string(direction));
        assert(isscalar(direction) && any(direction==["DL","UL"]), ...
            'sixgr:truth:InvalidDataRadioDirection','A data identity requires DL or UL.');
        validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
        channel='pdsch'; if direction=="UL", channel='pusch'; end
        rnti=sixgr.util.structGet(cfg,['phy.' channel '.RNTI'],NaN);
        validateattributes(rnti,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',65535});
        user=sixgr.util.structGet(cfg,'lls6g.userContext',struct());
        assert(isequal(double(sixgr.util.structGet(user,'UEIndex',ue)),double(ue)), ...
            'sixgr:truth:DataRadioIdentityMismatch','The frozen configuration belongs to another UE.');
        if isfield(user,'RuntimeUEIndex')
            assert(isequal(double(user.RuntimeUEIndex),double(ue)) && ...
                isequal(double(sixgr.util.structGet(user,'RNTI',NaN)),double(rnti)), ...
                'sixgr:truth:DataRadioIdentityMismatch', ...
                'The physical channel and frozen coupled UE context must retain the same radio identity.');
        end
        rnti=double(rnti);
    end

    function T=annotateDataEvidence(T,cfg,ue,direction)
        % Only annotate actual rows. Populated identities are evidence and
        % must agree, never be overwritten with a bootstrap or newer RNTI.
        if ~istable(T) || isempty(T), return; end
        rnti=sixgr.truth.CoupledRadioIdentity.dataRNTI(cfg,ue,direction);
        for field=["UEIndex","UEID","RNTI"]
            expected=double(ue); if field=="RNTI", expected=rnti; end
            if ismember(field,string(T.Properties.VariableNames))
                values=T.(field);
                assert(isnumeric(values) && isreal(values) && size(values,2)==1 && ...
                    all(isnan(values) | values==expected), ...
                    'sixgr:truth:DataEvidenceRadioIdentityMismatch', ...
                    'Received %s conflicts with its frozen physical execution identity.',field);
                values(isnan(values))=expected;
                T.(field)=values;
            else
                T.(field)=repmat(expected,height(T),1);
            end
        end
    end

    function ue=grantUEIndex(grant,maxUsers)
        % A decoded C-RNTI is not an array index. Only explicit scheduler
        % ownership or the immutable physical grant key can identify a UE.
        ue=double(sixgr.util.structGet(grant,'UEIndex',NaN));
        frozen=sixgr.util.structGet(grant,'PHYGrant.ChannelStateKey',struct());
        retained=double(sixgr.util.structGet(frozen,'UEIndex',NaN));
        assert(isscalar(ue) && isscalar(retained), ...
            'sixgr:truth:InvalidGrantUEIdentity','Grant UE identity must be scalar.');
        if isnan(ue), ue=retained; end
        assert(isreal(ue) && isfinite(ue) && ue==fix(ue) && ue>=1 && ue<=maxUsers, ...
            'sixgr:truth:MissingGrantUEIdentity','A grant must retain its logical UE owner; RNTI arithmetic is forbidden.');
        assert(isnan(retained) || retained==ue, ...
            'sixgr:truth:GrantUEIdentityMismatch','A frozen grant cannot change its logical UE owner.');
        if ~isempty(fieldnames(frozen))
            assert(isequal(double(sixgr.util.structGet(frozen,'RNTI',NaN)), ...
                double(sixgr.util.structGet(grant,'RNTI',NaN))), ...
                'sixgr:truth:GrantUEIdentityMismatch','A frozen grant cannot change its radio identity.');
        end
    end

    function rnti=resolve(state,ue,cellID)
        validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
        start=double(sixgr.util.structGet(state,'MultiUser.RNTIStart',NaN));
        count=double(sixgr.util.structGet(state,'NumUsers', ...
            sixgr.util.structGet(state,'MultiUser.NumUsers', ...
            numel(sixgr.util.structGet(state,'CurrentServingIdx',[])))));
        assert(ue<=count && isscalar(start) && isfinite(start) && start==fix(start) && ...
            start>=1 && start+count-1<=65535,'sixgr:truth:InvalidRuntimeUEIdentity', ...
            'Require an exact installed UE index and bootstrap RNTI allocation.');
        if nargin<3
            cells=sixgr.util.structGet(state,'CurrentServingIdx',[]);
            cellID=NaN;
            if numel(cells)>=ue, cellID=cells(ue); end
        end
        rnti=start+ue-1;
        rows=sixgr.util.structGet(state,'RadioIdentityBindings',struct([]));
        if isempty(rows), return; end
        hit=[rows.UEIndex]==ue & [rows.ServingCell]==cellID;
        assert(nnz(hit)<=1,'sixgr:truth:AmbiguousRuntimeRadioIdentity', ...
            'Only one active radio identity may own a UE/cell.');
        if any(hit), rnti=rows(hit).RNTI; end
    end

    function cfg=configuration(cfg,state,restoreBootstrap)
        if nargin<3, restoreBootstrap=false; end
        bindings=sixgr.util.structGet(state,'RadioIdentityBindings',struct([]));
        paths=["validation.pucch_resources.ue_report_bindings", ...
            "phy.srs.ueResourceBindings","lls6g.reference_signals.srs.ue_resource_bindings"];
        for path=paths
            rows=sixgr.util.structGet(cfg,path,struct([]));
            if isempty(rows), continue; end
            for b=reshape(bindings,1,[])
                hit=[rows.ue_index]==b.UEIndex & [rows.serving_cell_id]==b.ServingCell;
                for k=find(hit)
                    assert(ismember(rows(k).rnti,[b.ConfiguredRNTI b.RNTI]), ...
                        'sixgr:truth:RadioIdentityResourceConflict', ...
                        'Do not steal a resource installation from another radio identity.');
                    if restoreBootstrap, rows(k).rnti=b.ConfiguredRNTI;
                    else, rows(k).rnti=b.RNTI; end
                end
            end
            cfg=sixgr.util.structSet(cfg,path,rows);
        end
    end

    function ready=connectedReady(state,ue)
        ready=true;
        if logical(sixgr.util.structGet(state,'ControlGating.PRACHRequired',false))
            access=sixgr.util.structGet(state,'AccessState',strings(0,1));
            ready=numel(access)>=ue && string(access(ue))=="succeeded";
        end
    end

    function state=resetAccess(state)
        % Independent points retain history, not the previous access binding.
        if isfield(state,'CfgMobility')
            state.CfgMobility=sixgr.truth.CoupledRadioIdentity.configuration(state.CfgMobility,state,true);
        end
        for name=["DLSchedulers","ULSchedulers"]
            cells=sixgr.util.structGet(state,name,{});
            for k=1:numel(cells)
                if isempty(cells{k}), continue; end
                cells{k}.Cfg=sixgr.truth.CoupledRadioIdentity.configuration(cells{k}.Cfg,state,true);
            end
        end
        state.RadioIdentityBindings=struct([]);
        if isfield(state,'GNBTemporaryCRNTIAllocator')
            state=rmfield(state,'GNBTemporaryCRNTIAllocator');
        end
        if isfield(state,'GNBContentionReservations')
            state=rmfield(state,'GNBContentionReservations');
        end
        if isfield(state,'UEConfiguredSRProcedures')
            state.UEConfiguredSRProcedures=sixgr.truth.initializeUEConfiguredSRProcedures( ...
                state.CfgMobility,state.NumUsers,size(state.UEConfiguredSRProcedures,2),state.MultiUser.RNTIStart);
        end
    end

    function state=adopt(state,ue,row,msg4Slot)
        % Caller has validated the complete successful RA/RRC result. Check
        % decoded ownership again at the boundary that changes radio identity.
        assert(istable(row) && height(row)==1,'sixgr:truth:MissingReceivedCRNTI', ...
            'Use one completed received access result.');
        flags=["RACompleted","RAPIDMatches","Msg2DCICrcPass","Msg2PDSCHCrcPass", ...
            "RARULGrantValid","Msg3PUSCHCrcPass","Msg4PDCCHCrcPass", ...
            "Msg4PDSCHCrcPass","ContentionIdentityMatches"];
        names=string(row.Properties.VariableNames);
        if ismember("UEIndex",names)
            assert(isequal(double(row.UEIndex),double(ue)), ...
                'sixgr:truth:ReceivedCRNTIOwnerMismatch','Received access belongs to another logical UE.');
        end
        assert(all(ismember([flags,"TemporaryCRNTI","FinalCRNTI", ...
            "FinalCRNTISource","FinalCRNTIEncodingProfile"],names)), ...
            'sixgr:truth:MissingReceivedCRNTI','Retain decoded RAR and contention-resolution identity evidence.');
        for flag=flags
            value=row.(flag);
            assert((isnumeric(value)||islogical(value)) && isscalar(value) && ...
                isreal(value) && isfinite(value) && value==1, ...
                'sixgr:truth:UnacceptedReceivedCRNTI', ...
                'An unaccepted %s cannot assign a connected C-RNTI.',flag);
        end
        if ismember("RequireRRCSetupComplete",names) && logical(row.RequireRRCSetupComplete)
            required=["RRCSetupRequestDecoded","RRCSetupDecoded","SRB1Installed", ...
                "RRCSetupCompleteCRC","RRCSetupCompleteDecoded","RRCConnected"];
            assert(all(ismember([required,"RRCSetupCompletePayloadSHA256"],names)), ...
                'sixgr:truth:MissingRRCSetupCompleteEvidence','Retain required received RRC completion.');
            for flag=required
                assert(isequal(double(row.(flag)),1),'sixgr:truth:MissingRRCSetupCompleteEvidence', ...
                    'A failed RRC completion cannot install connected runtime identity.');
            end
            assert(~isempty(regexp(char(string(row.RRCSetupCompletePayloadSHA256)), ...
                '^[0-9a-fA-F]{64}$','once')), ...
                'sixgr:truth:MissingRRCSetupCompleteEvidence','Retain the decoded RRC payload hash.');
        end
        rnti=double(row.FinalCRNTI); temporary=double(row.TemporaryCRNTI);
        assert(isreal(rnti) && isfinite(rnti) && rnti==fix(rnti) && ...
            rnti>=1 && rnti<=65522 && rnti==temporary, ...
            'sixgr:truth:InvalidReceivedCRNTI', ...
            'Successful CCCH contention resolution adopts the received temporary C-RNTI (0001..FFF2).');
        source=string(row.FinalCRNTISource); profile=string(row.FinalCRNTIEncodingProfile);
        assert(source=="decoded_msg4_payload_after_contention_match" && ...
            profile=="legacy_bounded_not_NR_MAC_RRC", ...
            'sixgr:truth:UnacceptedReceivedCRNTI', ...
            'Require the supported received codec provenance; do not claim NR MAC/RRC qualification.');
        now=double(sixgr.util.structGet(state,'CurrentSlot',NaN));
        validateattributes(msg4Slot,{'numeric'},{'scalar','real','finite','integer','positive'});
        assert(isfinite(now) && msg4Slot<=now, ...
            'sixgr:truth:PrematureRadioIdentity','Contention resolution is not yet available.');
        if ismember("RequireRRCSetupComplete",names) && logical(row.RequireRRCSetupComplete)
            assert(all(ismember(["SetupCompleteScheduledSlot","RASlotTimeBase"],names)), ...
                'sixgr:truth:MissingRRCSetupCompleteEvidence','Retain the required RRC receive clock.');
            base=string(row.RASlotTimeBase);
            last=double(row.SetupCompleteScheduledSlot)+double(base=="absolute_zero_based");
            assert(any(base==["absolute_zero_based","absolute_one_based"]) && ...
                isfinite(last) && last==fix(last) && last>=msg4Slot && last<=now, ...
                'sixgr:truth:PrematureRadioIdentity','Required RRC completion must have actually occurred.');
        end
        cellID=double(state.CurrentServingIdx(ue));
        validateattributes(cellID,{'numeric'},{'scalar','real','finite','integer','positive'});
        configured=double(state.MultiUser.RNTIStart)+ue-1;
        old=sixgr.truth.CoupledRadioIdentity.resolve(state,ue,cellID);
        evidence=struct('UEIndex',ue,'ServingCell',cellID,'RNTI',rnti, ...
            'ConfiguredRNTI',configured,'Msg4CanonicalSlot',msg4Slot, ...
            'Source',source,'EncodingProfile',profile,'MACRRCStandardsQualified',false);
        evidence.EvidenceSHA256=string(sixgr.util.sha256Hex( ...
            uint8(unicode2native(jsonencode(evidence),'UTF-8'))));
        bindings=sixgr.util.structGet(state,'RadioIdentityBindings',struct([]));
        if ~isempty(bindings)
            own=[bindings.UEIndex]==ue & [bindings.ServingCell]==cellID;
            if any(own)
                assert(nnz(own)==1 && bindings(own).EvidenceSHA256==evidence.EvidenceSHA256, ...
                    'sixgr:truth:ConflictingRadioIdentity', ...
                    'Do not replace a received identity with stale or conflicting completion evidence.');
                return; % Exact replay is idempotent, not another installation.
            end
            assert(~any([bindings.UEIndex]~=ue & [bindings.ServingCell]==cellID & ...
                [bindings.RNTI]==rnti),'sixgr:truth:RadioIdentityCollision', ...
                'The received C-RNTI is already assigned to another UE in this cell.');
        end
        for other=1:state.NumUsers
            if other~=ue && state.CurrentServingIdx(other)==cellID
                assert(sixgr.truth.CoupledRadioIdentity.resolve(state,other,cellID)~=rnti, ...
                    'sixgr:truth:RadioIdentityCollision','C-RNTI conflicts with another installed UE.');
            end
        end
        if old~=rnti
            for name=["DLHarq","ULHarq"]
                harq=sixgr.util.structGet(state,name,[]);
                if isempty(harq), continue; end
                idx=find(harq.UEList==old);
                assert(isempty(idx) || ~any([harq.UEProcs{idx}.Active]), ...
                    'sixgr:truth:RadioIdentityWithActiveHARQ', ...
                    'An initial-access identity cannot rename live connected HARQ processes.');
            end
        end
        evidence.InstalledAtCanonicalSlot=now;
        if isempty(bindings), bindings=evidence; else, bindings(end+1)=evidence; end
        candidate=state; candidate.RadioIdentityBindings=bindings;
        history=sixgr.util.structGet(state,'RadioIdentityHistory',struct([]));
        if isempty(history), history=evidence; else, history(end+1)=evidence; end
        candidate.RadioIdentityHistory=history;
        if isfield(candidate,'CfgMobility')
            candidate.CfgMobility=sixgr.truth.CoupledRadioIdentity.configuration(candidate.CfgMobility,candidate);
        end
        % SR procedure state is UE-owned. Preserve pending/timer decisions;
        % only future snapshots acquire the received radio identity. Existing
        % value-class snapshots held in prepared transmissions are untouched.
        if isfield(candidate,'UEConfiguredSRProcedures') && ...
                size(candidate.UEConfiguredSRProcedures,1)>=ue && ...
                size(candidate.UEConfiguredSRProcedures,2)>=cellID
            sr=candidate.UEConfiguredSRProcedures{ue,cellID};
            for k=1:numel(sr)
                data=sr(k).Data;
                assert(data.RNTI==old,'sixgr:truth:RadioIdentityResourceConflict', ...
                    'Retain the original SR procedure owner.');
                data.RNTI=rnti;
                sr(k)=sixgr.phy.pucch.SchedulingRequestState(data);
            end
            candidate.UEConfiguredSRProcedures{ue,cellID}=sr;
        end
        % Validate every future scheduler config before mutating any handle.
        updates={}; schedulers={};
        for name=["DLSchedulers","ULSchedulers"]
            cells=sixgr.util.structGet(candidate,name,{});
            for k=1:numel(cells)
                if isempty(cells{k}), continue; end
                schedulers{end+1}=cells{k}; %#ok<AGROW>
                updates{end+1}=sixgr.truth.CoupledRadioIdentity.configuration(cells{k}.Cfg,candidate); %#ok<AGROW>
            end
        end
        for k=1:numel(schedulers), schedulers{k}.Cfg=updates{k}; end
        state=candidate;
    end
end
end
