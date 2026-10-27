classdef ReceivedPUCCHPowerControlState
    % Received, occasion-indexed PUCCH g; TS 38.213 V18.8.0 7.2.1.
    % Value owner: ingest is receipt-only, resolve is read-only, and commit
    % requires the original TX boundary. No waveform/RNG/receiver executes.
    % Scope: dedicated P0, one loop, same-SCS normal CP, C-RNTI 1_0/1_1,
    % one response DCI or autonomous CSI/SR, without repetition/cell switch.
    % Compact supplied clock/TX receipts are validated, NOT independently
    % authenticated here. The shared original owner must bind them. This
    % class alone never qualifies an RF execution or measured power result.
    properties (SetAccess=private)
        Installation struct
        Installations cell = {}
        Commands cell = {}
        History cell = {}
    end
    methods
        function obj=ReceivedPUCCHPowerControlState(installation)
            obj.Installation=localInstallation(installation);
            obj.Installations={obj.Installation};
        end

        function next=install(obj,installation)
            % A new explicit event resets g even when the P0 value is equal.
            % An unrelated CSI/DCI/beam epoch is deliberately not this event.
            n=localInstallation(installation);
            localSameIdentity(obj.Installation,n);
            localClock(obj.Installation,n);
            assert(n.DCIServingCellIndex==obj.Installation.DCIServingCellIndex && ...
                n.DCIComponentCarrierIndex==obj.Installation.DCIComponentCarrierIndex, ...
                'sixgr:power:PUCCHWrongEndpoint','A P0 reinstall cannot remap configured DCI identities.');
            assert(~any(cellfun(@(x)x.InstallationID==n.InstallationID,obj.Installations)), ...
                'sixgr:power:PUCCHDuplicateInstallation','A P0 installation event is consumed once.');
            latest=obj.Installation.EffectiveSample;
            if ~isempty(obj.History), latest=max(latest,obj.History{end}.CommittedAtSample); end
            if ~isempty(obj.Commands), latest=max(latest,obj.Commands{end}.AvailableAtSample); end
            assert(n.EffectiveSample>=latest && ...
                n.EffectiveSymbolBoundary>=obj.Installation.EffectiveSymbolBoundary, ...
                'sixgr:power:PUCCHInstallationClock','Do not reset an already executed history retrospectively.');
            next=obj; next.Installation=n; next.Installations{end+1}=n;
        end

        function [next,command]=ingestReceivedDCI(obj,cfg,a,r)
            % cfg is the ORIGINAL receiver installation, not current TX cfg.
            c=sixgr.phy.pdcch.validateConnectedAssignment(cfg,a);
            assert(string(a.Direction)=="DL" && any(string(a.DCIFormat)==["1_0","1_1"]) && ...
                string(c.Data.RNTIType)=="C-RNTI", ...
                'sixgr:power:PUCCHUnsupportedTPC','Only received C-RNTI DCI 1_0/1_1 is supported.');
            b=obj.Installation;
            % Configured DCI indices, runtime array IDs and PCI are separate
            % domains. Their original installation binds the mapping; do
            % not infer configuredCell=runtimeCell-1 (or use PCI).
            assert(a.RNTI==b.RNTI && c.Data.ControlServingCell==b.DCIServingCellIndex && ...
                c.Data.ScheduledServingCell==b.DCIServingCellIndex && ...
                c.Data.ControlCarrier==b.DCIComponentCarrierIndex && ...
                c.Data.ScheduledCarrier==b.DCIComponentCarrierIndex, ...
                'sixgr:power:PUCCHWrongEndpoint','TPC must belong to this UE and same serving carrier.');
            localFields(r,{'ObservationID','AssignmentDigest','TimingDigest','PDCCHStartSymbolBoundary', ...
                'PDCCHEndSymbolBoundary','PDCCHStartSample','PDCCHEndSampleExclusive', ...
                'AvailableAtSample','SampleRateHz','ClockEpoch','SubcarrierSpacingKHz', ...
                'ReceiverAccepted','ReceiverSelectionSource'});
            r.ObservationID=localText(r.ObservationID); r.TimingDigest=localDigest(r.TimingDigest);
            assert(localDigest(r.AssignmentDigest)==string(a.AssignmentDigest) && ...
                islogical(r.ReceiverAccepted) && isscalar(r.ReceiverAccepted) && r.ReceiverAccepted && ...
                localText(r.ReceiverSelectionSource)=="receiver_installed_context_crc_and_semantic_parse", ...
                'sixgr:power:PUCCHReceivedCommand','Retain the original accepted received assignment.');
            localClock(b,r);
            assert(localNumber(cfg.phy.carrier.SubcarrierSpacing)==b.SubcarrierSpacingKHz && ...
                lower(string(cfg.phy.carrier.CyclicPrefix))=="normal", ...
                'sixgr:power:PUCCHUnsupportedClock','The original control uses the installed normal-CP numerology.');
            for f=["PDCCHStartSymbolBoundary","PDCCHEndSymbolBoundary","PDCCHStartSample", ...
                    "PDCCHEndSampleExclusive","AvailableAtSample"]
                r.(f)=localInteger(r.(f));
            end
            slot=localInteger(a.ControlAbsoluteSlot);
            assert(slot<=(flintmax-14)/14 && r.PDCCHStartSymbolBoundary>=14*slot && ...
                r.PDCCHEndSymbolBoundary<=14*slot+14 && ...
                r.PDCCHEndSymbolBoundary>r.PDCCHStartSymbolBoundary && ...
                r.PDCCHEndSampleExclusive>r.PDCCHStartSample && ...
                r.AvailableAtSample>=r.PDCCHEndSampleExclusive && ...
                r.PDCCHStartSample>=b.EffectiveSample && ...
                r.PDCCHStartSymbolBoundary>=b.EffectiveSymbolBoundary, ...
                'sixgr:power:PUCCHReceivedClock','Retain the physical control interval separately from result availability.');
            field=localInteger(a.Fields.tpc_command_for_pucch);
            assert(field<=3,'sixgr:power:PUCCHInvalidTPC','TPC is the original two-bit command, not a dB value.');
            if ~isempty(obj.Commands)
                assert(r.AvailableAtSample>=obj.Commands{end}.AvailableAtSample, ...
                    'sixgr:power:PUCCHReceivedClock','Receive-completion commits cannot travel backwards.');
            end
            assert(~any(cellfun(@(x)x.AssignmentDigest==string(a.AssignmentDigest),obj.Commands)), ...
                'sixgr:power:PUCCHDuplicateTPC','Do not ingest the same received assignment twice.');
            current=obj.currentHistory();
            for k=current
                h=obj.History{k};
                assert(r.PDCCHEndSymbolBoundary>h.CutoffSymbolBoundary, ...
                    'sixgr:power:PUCCHLateControlAvailability', ...
                    ['A command delivered after an already decided applicable window requires a separate ' ...
                     'processing-latency policy; do not change its physical reception time.']);
            end
            deltas=[-1 0 1 3];
            command=r;
            command.InstallationID=b.InstallationID;
            command.AssignmentDigest=string(a.AssignmentDigest);
            command.ContextDigest=localDigest(a.ContextDigest);
            command.PayloadHash=localDigest(a.PayloadHash);
            command.DCIFormat=string(a.DCIFormat);
            command.DCIConfigurationEpoch=localInteger(a.ConfigurationEpoch);
            command.ControlAbsoluteSlot=slot;
            command.HARQFeedbackAbsoluteSlot=localInteger(a.HARQFeedbackAbsoluteSlot);
            command.TPCField=field; command.Delta_dB=deltas(field+1);
            command.Source="received_connected_DCI_PUCCH_TPC";
            command.Digest=localHash(command);
            next=obj; next.Commands{end+1}=command;
        end

        function proposal=resolveOccasion(obj,o)
            % Final binding is at the SELECTED resource's first symbol.
            % Earlier planning must not freeze g before eligible RX completes.
            o=localOccasion(obj.Installation,o);
            b=obj.Installation; current=obj.currentHistory();
            if ~isempty(current)
                assert(o.StartSample>obj.History{current(end)}.Occasion.StartSample && ...
                    o.StartSymbolBoundary>obj.History{current(end)}.Occasion.StartSymbolBoundary, ...
                    'sixgr:power:PUCCHOccasionOrder','Resolve a new physical PUCCH occasion, not an old receiver completion.');
            end
            cmds=find(cellfun(@(x)x.InstallationID==b.InstallationID,obj.Commands));
            if ~isempty(cmds)
                assert(all(cellfun(@(x)x.AvailableAtSample<=o.DecisionSample,obj.Commands(cmds))), ...
                    'sixgr:power:PUCCHFutureKnowledge','Do not resolve an earlier decision from a future owner snapshot.');
            end
            if o.Procedure=="dci_response"
                hit=cmds(cellfun(@(x)x.AssignmentDigest==o.ResponseAssignmentDigest,obj.Commands(cmds)));
                assert(isscalar(hit),'sixgr:power:PUCCHResponseCommand','One original received response DCI is required.');
                response=obj.Commands{hit};
                assert(floor(o.StartSymbolBoundary/14)==response.HARQFeedbackAbsoluteSlot, ...
                    'sixgr:power:PUCCHResponseCommand','Response timing must retain the received DCI HARQ slot.');
                cutoff=response.PDCCHEndSymbolBoundary;
                kPUCCH=o.StartSymbolBoundary-cutoff;
            else
                assert(logical(sixgr.util.structGet(b,'AutonomousOccasionsSupported',true)), ...
                    'sixgr:power:PUCCHCommonK2Required','Autonomous CSI/SR requires explicit installed common-K2 authority.');
                kPUCCH=14*min(b.CommonK2Slots);
                cutoff=o.StartSymbolBoundary-kPUCCH;
            end
            assert(kPUCCH>=0,'sixgr:power:PUCCHResponseCommand','PUCCH cannot precede its response control.');
            prior=0;
            for k=current
                if obj.History{k}.CutoffSymbolBoundary<cutoff, prior=k; end
            end
            lower=b.EffectiveSymbolBoundary-1; previous=0;
            atMax=false; atMin=false; deferred=strings(1,0);
            if prior>0
                h=obj.History{prior}; lower=h.CutoffSymbolBoundary;
                previous=h.UpdatedG_dB; atMax=h.AtMaximumPower; atMin=h.AtMinimumPower;
                deferred=h.DeferredAssignmentDigests;
            end
            selected=strings(1,0); postponed=strings(1,0); newWindow=strings(1,0);
            net=0; processing=localProcessingSamples(b);
            for k=cmds
                c=obj.Commands{k};
                inWindow=c.PDCCHEndSymbolBoundary>lower && c.PDCCHEndSymbolBoundary<=cutoff;
                carried=any(deferred==c.AssignmentDigest);
                if ~(inWindow||carried), continue; end
                if inWindow, newWindow(end+1)=c.AssignmentDigest; end %#ok<AGROW>
                if o.StartSample-c.PDCCHEndSampleExclusive<processing
                    postponed(end+1)=c.AssignmentDigest; %#ok<AGROW>
                else
                    selected(end+1)=c.AssignmentDigest; net=net+c.Delta_dB; %#ok<AGROW>
                end
            end
            held=(atMax&&net>=0)||(atMin&&net<=0);
            updated=previous+net; if held, updated=previous; end
            proposal=struct('ContractVersion',"sixgr.link.received_PUCCH_g_proposal/v1", ...
                'InstallationID',b.InstallationID,'InstallationDigest',localHash(b), ...
                'OwnerDigest',obj.digest(),'Occasion',o,'KPUCCHSymbols',kPUCCH, ...
                'WindowLowerExclusive',lower,'CutoffSymbolBoundary',cutoff, ...
                'PreviousHistoryIndex',prior,'PreviousG_dB',previous,'NetTPC_dB',net, ...
                'UpdatedG_dB',updated,'TPCAdjustmentHeldAtPowerLimit',held, ...
                'PreviousAtMaximumPower',atMax,'PreviousAtMinimumPower',atMin, ...
                'WindowAssignmentDigests',newWindow,'AppliedOrHeldAssignmentDigests',selected, ...
                'DeferredAssignmentDigests',postponed,'MinimumProcessingSamples',processing, ...
                'Source',"received_PUCCH_commands_occasion_indexed_g", ...
                'Scope',"supplied_original_receipts_not_shared_owner_execution_qualification", ...
                'RuntimeIntegrated',false,'PhysicalExecutionQualified',false);
            proposal.Digest=localHash(proposal);
        end

        function next=commitTransmission(obj,proposal,tx,power)
            % The original owner supplies this ONLY after an active sample.
            % A reservation, negative SR, missing-PL deferral or RX outcome
            % does not commit a transmission/saturation history here.
            assert(isstruct(proposal)&&isscalar(proposal)&&isfield(proposal,'Occasion') && ...
                isequaln(proposal,obj.resolveOccasion(proposal.Occasion)), ...
                'sixgr:power:PUCCHProposalChanged','Retain the exact current owner proposal; never edit g or command membership.');
            localFields(tx,{'TransmissionID','ObservationID','AssignmentDigest','PowerProposalDigest', ...
                'FirstActiveSample','CommittedAtSample','SampleRateHz','ClockEpoch','SubcarrierSpacingKHz','Source'});
            localClock(obj.Installation,tx);
            id=localText(tx.TransmissionID); localDigest(tx.AssignmentDigest);
            assert(localText(tx.Source)=="actual_shared_PUCCH_transmission_started_not_receiver_outcome" && ...
                localText(tx.ObservationID)==proposal.Occasion.ObservationID && ...
                localDigest(tx.PowerProposalDigest)==proposal.Digest, ...
                'sixgr:power:PUCCHTransmissionReceipt','Bind the matching emitted preparation, not a receive result.');
            first=localInteger(tx.FirstActiveSample); committed=localInteger(tx.CommittedAtSample);
            assert(first>=proposal.Occasion.StartSample && first<proposal.Occasion.EndSampleExclusive && ...
                first<flintmax && committed==first+1, ...
                'sixgr:power:PUCCHTransmissionReceipt','Commit after the first original active sample, not at preparation.');
            assert(~any(cellfun(@(x)x.TransmissionID==id,obj.History)), ...
                'sixgr:power:PUCCHDuplicateTransmission','An original PUCCH transmission commits once.');
            localFields(power,{'PowerProposalDigest','ClosedLoopAdjustment_dB','P0_dBm', ...
                'RequestedPower_dBm','AppliedPower_dBm','PCMAX_dBm','MinimumPower_dBm','Source'});
            assert(localDigest(power.PowerProposalDigest)==proposal.Digest && ...
                localNumber(power.ClosedLoopAdjustment_dB)==proposal.UpdatedG_dB && ...
                localNumber(power.P0_dBm)==obj.Installation.P0_dBm && ...
                localText(power.Source)=="original_transmitted_PUCCH_power_state", ...
                'sixgr:power:PUCCHPowerReceipt','Power must use the frozen original g and installed P0.');
            request=localNumber(power.RequestedPower_dBm); applied=localNumber(power.AppliedPower_dBm);
            maximum=localNumber(power.PCMAX_dBm); minimum=power.MinimumPower_dBm;
            assert(isa(minimum,'double') && isreal(minimum) && isscalar(minimum) && ...
                (isfinite(minimum)||minimum==-Inf) && minimum<maximum, ...
                'sixgr:power:PUCCHPowerReceipt','Supply the original minimum bound, or explicit -Inf for no modeled floor.');
            assert(applied==min(maximum,max(minimum,request)), ...
                'sixgr:power:PUCCHPowerReceipt','Do not invent saturation from configured power or a no-TX occasion.');
            h=proposal;
            h.TransmissionID=id; h.TransmissionAssignmentDigest=string(tx.AssignmentDigest);
            h.CommittedAtSample=committed; h.Power=power;
            h.AtMaximumPower=applied==maximum; h.AtMinimumPower=isfinite(minimum)&&applied==minimum;
            h.LowerPowerLimitModeled=isfinite(minimum);
            h.Digest=localHash(rmfield(h,'Digest'));
            next=obj; next.History{end+1}=h;
        end

        function value=digest(obj)
            value=localHash(struct('Installation',obj.Installation, ...
                'Installations',{obj.Installations},'Commands',{obj.Commands},'History',{obj.History}));
        end
    end
    methods (Access=private)
        function indices=currentHistory(obj)
            indices=find(cellfun(@(x)x.InstallationID==obj.Installation.InstallationID,obj.History));
        end
    end
end

function b=localInstallation(b)
autonomous=true; fields=b;
if isfield(b,'AutonomousOccasionsSupported')
    autonomous=b.AutonomousOccasionsSupported;
    assert(islogical(autonomous)&&isscalar(autonomous),'sixgr:power:PUCCHReceiptSchema','Explicit logical procedure policy required.');
    fields=rmfield(b,'AutonomousOccasionsSupported');
end
localFields(fields,{'InstallationID','UEID','RNTI','ServingCell','ComponentCarrier','ActiveULBWP', ...
    'DCIServingCellIndex','DCIComponentCarrierIndex', ...
    'ClosedLoopIndex','P0PUCCHID','P0_dBm','EffectiveSample','EffectiveSymbolBoundary', ...
    'AvailableAtSample','SampleRateHz','ClockEpoch','SubcarrierSpacingKHz','CyclicPrefix', ...
    'CommonK2Slots','ProcessingCapability','Source'});
b.InstallationID=localText(b.InstallationID);
for f=["UEID","RNTI","ServingCell","ComponentCarrier","ActiveULBWP","ClosedLoopIndex", ...
        "DCIServingCellIndex","DCIComponentCarrierIndex", ...
        "P0PUCCHID","EffectiveSample","EffectiveSymbolBoundary","AvailableAtSample","ClockEpoch"]
    b.(f)=localInteger(b.(f));
end
assert(b.UEID>0 && b.RNTI>0 && b.RNTI<=65535 && b.ServingCell>0 && b.ClosedLoopIndex==0 && ...
    localText(b.Source)=="installed_dedicated_p0_configuration" && ...
    localText(b.ProcessingCapability)=="capability1" && lower(localText(b.CyclicPrefix))=="normal", ...
    'sixgr:power:PUCCHUnsupportedInstallation','Use explicit dedicated P0, loop0, normal CP and capability1; no RAR fallback.');
b.P0_dBm=localNumber(b.P0_dBm); b.SampleRateHz=localNumber(b.SampleRateHz);
b.SubcarrierSpacingKHz=localNumber(b.SubcarrierSpacingKHz);
mu=log2(b.SubcarrierSpacingKHz/15);
assert(b.SampleRateHz>0 && ismember(mu,[0 1 2 3]) && b.AvailableAtSample<=b.EffectiveSample, ...
    'sixgr:power:PUCCHUnsupportedClock','Initial scope is same-SCS 15/30/60/120-kHz normal CP with a causal install.');
v=b.CommonK2Slots;
assert(isa(v,'double') && isreal(v) && ((autonomous && isvector(v) && ~isempty(v)) || ...
    (~autonomous && isequal(size(v),[1 0]))) && ...
    all(isfinite(v)&v>=0&v==fix(v)&v<=(flintmax-14)/14), ...
    'sixgr:power:PUCCHCommonK2Required','Autonomous PUCCH uses explicit installed PUSCH-ConfigCommon K2 values.');
b.CommonK2Slots=reshape(v,1,[]);
end

function o=localOccasion(b,o)
localFields(o,{'ObservationID','ResourceID','ResourceDigest','ReportDigest','TimingDigest', ...
    'UEID','RNTI','ServingCell','ComponentCarrier','ActiveULBWP','ClosedLoopIndex','P0PUCCHID', ...
    'StartSample','EndSampleExclusive','StartSymbolBoundary','DecisionSample','SampleRateHz', ...
    'ClockEpoch','SubcarrierSpacingKHz','RepetitionCount','Procedure','ResponseAssignmentDigest'});
localSameIdentity(b,o); localClock(b,o);
for f=["ResourceID","StartSample","EndSampleExclusive","StartSymbolBoundary","DecisionSample","RepetitionCount","P0PUCCHID"]
    o.(f)=localInteger(o.(f));
end
o.ObservationID=localText(o.ObservationID);
for f=["ResourceDigest","ReportDigest","TimingDigest"], o.(f)=localDigest(o.(f)); end
o.Procedure=localText(o.Procedure);
assert(o.RepetitionCount==1 && any(o.Procedure==["dci_response","autonomous_csi","autonomous_sr"]) && ...
    o.P0PUCCHID==b.P0PUCCHID,'sixgr:power:PUCCHUnsupportedOccasion', ...
    'Initial scope excludes repetition, multiple response DCIs, cell switching and loop changes.');
assert(o.StartSample>=b.EffectiveSample && o.StartSymbolBoundary>=b.EffectiveSymbolBoundary && ...
    o.EndSampleExclusive>o.StartSample && o.DecisionSample==o.StartSample, ...
    'sixgr:power:PUCCHFinalBindingClock','Bind at the selected resource first symbol; do not freeze power at an earlier resource.');
if o.Procedure=="dci_response"
    o.ResponseAssignmentDigest=localDigest(o.ResponseAssignmentDigest);
else
    assert((ischar(o.ResponseAssignmentDigest)&&isempty(o.ResponseAssignmentDigest)) || ...
        (isstring(o.ResponseAssignmentDigest)&&isscalar(o.ResponseAssignmentDigest)&& ...
        ~ismissing(o.ResponseAssignmentDigest)&&strlength(o.ResponseAssignmentDigest)==0), ...
        'sixgr:power:PUCCHResponseCommand','An autonomous occasion has no invented triggering DCI.');
    o.ResponseAssignmentDigest="";
end
end

function localSameIdentity(a,b)
for f=["UEID","RNTI","ServingCell","ComponentCarrier","ActiveULBWP","ClosedLoopIndex"]
    assert(localInteger(b.(f))==a.(f),'sixgr:power:PUCCHWrongEndpoint','Do not change the installed UE/cell/carrier/BWP/loop.');
end
end

function localClock(a,b)
assert(localNumber(b.SampleRateHz)==a.SampleRateHz && localInteger(b.ClockEpoch)==a.ClockEpoch && ...
    localNumber(b.SubcarrierSpacingKHz)==a.SubcarrierSpacingKHz, ...
    'sixgr:power:PUCCHClockMismatch','Retain the original sample-clock epoch, rate and same-SCS symbol domain.');
end

function samples=localProcessingSamples(b)
mu=log2(b.SubcarrierSpacingKHz/15);
p=sixgr.phy.frame.TimingPolicyCatalog.capability1(mu);
ticks=sixgr.phy.frame.TimingPolicyCatalog.processingSymbolTicks(p.PUSCHN2Symbols,mu);
samples=ceil(double(ticks)*b.SampleRateHz/double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond));
assert(isfinite(samples)&&samples>0&&samples<=flintmax,'sixgr:power:PUCCHUnsupportedClock','Unsafe processing interval.');
end

function localFields(s,fields)
assert(isstruct(s)&&isscalar(s)&&all(isfield(s,fields))&&numel(fieldnames(s))==numel(fields), ...
    'sixgr:power:PUCCHReceiptSchema','Use the exact compact receipt schema; no arbitrary IQ or omitted authority.');
end

function v=localNumber(v)
assert(isnumeric(v)&&~islogical(v)&&isreal(v)&&isscalar(v)&&isfinite(v), ...
    'sixgr:power:PUCCHNumericType','Require an original finite numeric scalar, not coerced text/logical.');
v=double(v);
end

function v=localInteger(v)
assert(isa(v,'double')&&isreal(v)&&isscalar(v)&&isfinite(v)&&v>=0&&v<=flintmax&&v==fix(v), ...
    'sixgr:power:PUCCHClockInteger','Coordinates/identities require exactly representable nonnegative double integers.');
end

function v=localText(v)
assert((ischar(v)&&isrow(v)||isstring(v)&&isscalar(v)) && ...
    ~ismissing(string(v))&&strlength(string(v))>0, ...
    'sixgr:power:PUCCHTextType','Require explicit scalar text.');
v=string(v);
end

function v=localDigest(v)
v=localText(v);
assert(~isempty(regexp(char(v),'^[0-9a-fA-F]{64}$','once')), ...
    'sixgr:power:PUCCHDigest','Retain an original SHA-256 digest.');
end

function d=localHash(s)
d=string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(orderfields(s)),'UTF-8'))));
end
