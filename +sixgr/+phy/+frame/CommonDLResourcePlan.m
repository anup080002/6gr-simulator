classdef CommonDLResourcePlan
    % Configured ownership, not measured waveform evidence. Never edits a TB.
    % RA PDSCHs have no dedicated CSI-RS rate-matching authority; choose a
    % nonoverlapping occasion before coding instead of puncturing coded data.
    properties (SetAccess=private)
        Config
        Carrier
        SIB1Slot0 = []
        BroadcastPeriodSlots = []
        SIB1PeriodSlots = []
        SSBPeriodSlots = []
        SIB1SSBIndex = []
        SIB1FirstSymbol = []
        SIB1PDSCH
        SIB1PDCCH
        SIB1AdditionalPlans = {}
        TRS
        PreparedSlot0 = NaN
        PreparedSSBRE0 = []
        PreparedTRSRE0 = []
        PreparedCSIRSRE0 = []
        PreparedSIB1RE0 = []
    end
    methods
        function obj = CommonDLResourcePlan(cfg)
            obj.Config = cfg;
            obj.Carrier = sixgr.phy.grid.makeCarrier(cfg);
            obj.Carrier.NSlot = 0; obj.Carrier.NFrame = 0;
            if logical(sixgr.util.structGet(cfg,'phy.trs.enable',false))
                obj.TRS = sixgr.phy.trs.buildTRSConfigFromScenario(cfg);
            end
            if logical(sixgr.util.structGet(cfg,'phy.sib1.enable',false))
                assert(logical(sixgr.util.structGet(cfg,'phy.ssb.enable',false)), ...
                    'sixgr:phy:frame:MissingBroadcastTimeline', ...
                    'The executed SSB/SIB1 composite requires an enabled SSB timeline.');
                origin = cfg;
                origin.phy.carrier.NSlot = 0; origin.phy.carrier.NFrame = 0;
                indices=sixgr.phy.broadcast.resolveSIB1TransmitSSBIndices(origin);
                origin.phy.ssb.runtimeSSBIndex=indices(1);
                origin.phy.sib1.transmissionScope="selected_ssb_occasion";
                [obj.SIB1PDCCH,siCfg,siCarrier,resolution,obj.SIB1Slot0] = ...
                    sixgr.phy.broadcast.resolveSIB1ControlOccasion(obj.Carrier,origin);
                obj.SIB1PDSCH = sixgr.phy.broadcast.configuredSIB1Allocation(siCarrier,siCfg);
                obj.SIB1SSBIndex=indices(1);
                obj.SIB1FirstSymbol=double(resolution.SelectedMonitoringOccasion.FirstSymbol);
                obj.SIB1PeriodSlots=double(resolution.SelectedMonitoringOccasion.PeriodSlots);
                assert(resolution.MultiplexingPattern==1 && ...
                    ~resolution.Context.SharedSpectrum && ...
                    any(resolution.Context.PDCCHSCSKHz==[15 30]) && ...
                    obj.SIB1PeriodSlots==2*double(obj.Carrier.SlotsPerFrame), ...
                    'sixgr:phy:broadcast:UnsupportedSIB1TransmissionCalendar', ...
                    'Common SI ownership requires the supported non-shared FR1 pattern-1 calendar.');
                for ordinal=2:numel(indices)
                    child=origin;
                    child.phy.ssb.runtimeSSBIndex=indices(ordinal);
                    obj.SIB1AdditionalPlans{end+1}=sixgr.phy.frame.CommonDLResourcePlan(child);
                end
                timing = sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
                obj.SSBPeriodSlots = double(timing.PeriodicityMs)*obj.Carrier.SlotsPerSubframe;
                validateattributes(obj.SSBPeriodSlots,{'numeric'}, ...
                    {'scalar','finite','integer','positive'});
                % Compatibility name consumed by the planned RE exporter:
                % this is the SI recurrence, NOT the SS/PBCH burst period.
                obj.BroadcastPeriodSlots=obj.SIB1PeriodSlots;
                % Keep the absolute Type-0 offset. It may lie beyond the
                % first SSB period; reducing it modulo the period would
                % reserve a SIB1 transmission that has not started yet.
            end
        end

        function rows=sib1TransmissionOccasions(obj,firstSlot0,endSlot0)
            % Configured TX subset, not the full two-slot monitoring set and
            % not evidence of emitted/received samples. Half-open horizon.
            for value={firstSlot0,endSlot0}
                v=value{1};
                assert(isnumeric(v) && isreal(v) && isscalar(v) && isfinite(v) && ...
                    v>=0 && v==fix(v) && v<flintmax/160, ...
                    'sixgr:phy:frame:InvalidSIB1CalendarWindow', ...
                    'Use exact nonnegative numeric absolute slot boundaries.');
            end
            assert(endSlot0>=firstSlot0,'sixgr:phy:frame:InvalidSIB1CalendarWindow', ...
                'The SI calendar window must be half-open [first,end), end >= first.');
            rows=table(zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
                'VariableNames',{'SSBIndex','AbsoluteSlot','FirstConfiguredAbsoluteSlot', ...
                'PeriodSlots','RecurrenceIndex0Based','FirstSymbol'});
            if ~isempty(obj.SIB1Slot0) && endSlot0>firstSlot0
                k=max(0,ceil((double(firstSlot0)-obj.SIB1Slot0)/obj.SIB1PeriodSlots));
                first=obj.SIB1Slot0+k*obj.SIB1PeriodSlots;
                slots=(first:obj.SIB1PeriodSlots:double(endSlot0)-1).';
                n=numel(slots);
                rows=table(repmat(obj.SIB1SSBIndex,n,1),slots,repmat(obj.SIB1Slot0,n,1), ...
                    repmat(obj.SIB1PeriodSlots,n,1),(k:k+n-1).',repmat(obj.SIB1FirstSymbol,n,1), ...
                    'VariableNames',rows.Properties.VariableNames);
            end
            for ordinal=1:numel(obj.SIB1AdditionalPlans)
                rows=[rows;obj.SIB1AdditionalPlans{ordinal}.sib1TransmissionOccasions(firstSlot0,endSlot0)]; %#ok<AGROW>
            end
            rows=sortrows(rows,{'AbsoluteSlot','SSBIndex'});
        end

        function obj = prepareSlot(obj,slot0)
            % Value-object snapshot of this immutable configuration and
            % absolute slot only. No global cache, RNG, or receiver state.
            % Native generators and every collision guard still execute.
            obj.PreparedSlot0=NaN;
            carrier=obj.carrierAt(slot0);
            ssb=sixgr.phy.frame.ssbPRBSymbolReservation(obj.Config,carrier,slot0);
            obj.PreparedSSBRE0=ssb.ReservedCarrierRE0;
            obj.PreparedTRSRE0=obj.trsRE(slot0);
            obj.PreparedCSIRSRE0=obj.csirsRE(slot0);
            obj.PreparedSIB1RE0=obj.sib1ReservedRE(slot0);
            obj.PreparedSlot0=double(slot0);
        end

        function coordinates = controlReservations(obj,slot0)
            % Configured ownership, never a claim that reception occurred.
            % Connected DL assignments AND UL grants share this DL grid.
            % Include payload and pilots of cell-common signals; a distinct
            % search-space/CORESET ID does not make colliding REs orthogonal.
            carrier=obj.carrierAt(slot0);
            ssb=obj.ssbRE(slot0);
            re=unique([ssb(:);obj.sib1ReservedRE(slot0); ...
                obj.trsRE(slot0);obj.csirsRE(slot0)]);
            k=12*carrier.NSizeGrid;
            coordinates=[mod(re,k)+12*carrier.NStartGrid,floor(re/k)];
        end

        function [available,evidence] = checkPDSCH(obj,allocation,slot0)
            % Reserve the entire signalled PRB/symbol allocation, including
            % DM-RS/CDM no-data REs; unused REs are not another common grant.
            carrier = obj.carrierAt(slot0);
            required = {'PRBStart','NumPRB','SymbolStart','NumSymbols'};
            assert(isstruct(allocation) && all(isfield(allocation,required)), ...
                'sixgr:phy:frame:MissingCommonPDSCHAllocation', ...
                'Common-PDSCH eligibility requires the transmitter allocation.');
            values = [allocation.PRBStart allocation.NumPRB allocation.SymbolStart allocation.NumSymbols];
            validateattributes(values,{'numeric'},{'real','finite','integer','nonnegative','numel',4});
            assert(values(2)>0 && values(4)>0 && values(1)+values(2)<=carrier.NSizeGrid && ...
                values(3)+values(4)<=carrier.SymbolsPerSlot, ...
                'sixgr:phy:frame:CommonPDSCHOutsideCarrier','Common PDSCH allocation exceeds the carrier.');
            re = localRectangle(carrier,values(1)+(0:values(2)-1),values(3)+(0:values(4)-1));
            owners = strings(0,1); counts = zeros(0,1);
            [owners,counts] = localConflict(owners,counts,re,obj.ssbRE(slot0),"SSB_PRB_symbol_reservation");
            [owners,counts] = localConflict(owners,counts,re,obj.trsRE(slot0),"TRS");
            [owners,counts] = localConflict(owners,counts,re,obj.csirsRE(slot0),"CSI-RS");
            [owners,counts] = localConflict(owners,counts,re,obj.sib1ReservedRE(slot0), ...
                "SIB1_PDSCH_and_Type0_PDCCH");
            available = isempty(owners);
            evidence = struct('AbsoluteSlot0',double(slot0),'Available',available, ...
                'ConflictingOwners',owners,'OverlapRECounts',counts, ...
                'Source',"configured_common_DL_resource_ownership_not_measured", ...
                'ControlCandidateValidated',false,'ProxyUsed',false,'FallbackUsed',false);
        end

        function [available,evidence] = checkConnectedPDSCH(obj,allocation,slot0)
            % Installed periodic CSI-RS (including NZP resources with
            % trs-Info) is excluded at exact RE granularity. This is NOT
            % common/RA authority, aperiodic CSI-RS or the TRS-ResourceSet IE.
            % Eligibility here precedes the final rank/MCS-specific PHY
            % feasibility check; it does not freeze capacity or a TB.
            [available,evidence] = obj.checkPDSCH(allocation,slot0);
            isTRS = evidence.ConflictingOwners == "TRS";
            isCSI = evidence.ConflictingOwners == "CSI-RS";
            isReference = isTRS | isCSI;
            evidence.TRSRateMatchedRECount = 0;
            evidence.CSIRSRateMatchedRECount = 0;
            if ~any(isReference), return; end
            % SSB and common SI remain hard exclusions. Do not attempt
            % dedicated TRS sharing on an already unavailable candidate:
            % the exact PDSCH allocator correctly rejects an SSB/DM-RS
            % collision, but that is not a fatal scheduling error when
            % another PRB region can be selected before grant freeze.
            % Retain all owners/counts for the rejected candidate.
            if any(~isReference), return; end
            if any(isTRS)
                assert(obj.TRS.TRSInfoEnabled && obj.TRS.CSIRSType == "nzp" && ...
                    any(obj.TRS.SlotAuthority == ["periodic_offset","explicit_slot_numbers"]), ...
                    'sixgr:phy:frame:MissingDedicatedTRSAuthority', ...
                    'Connected TRS sharing requires configured periodic NZP-CSI-RS with trs-Info.');
            end
            cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(obj.Config,slot0+1);
            carrier = obj.carrierAt(slot0);
            prbs = allocation.PRBStart+(0:allocation.NumPRB-1);
            symbols = [allocation.SymbolStart allocation.NumSymbols];
            [data,~,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,cfg, ...
                'PRBSet',prbs,'SymbolAllocation',symbols);
            plane = 12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
            rectangle = localRectangle(carrier,prbs,symbols(1)+(0:symbols(2)-1));
            trs = intersect(obj.trsRE(slot0),rectangle);
            csi = intersect(obj.csirsRE(slot0),rectangle);
            reserved = unique(mod(double(pdsch.ReservedRE(:)),plane));
            pilots = [reshape(nrPDSCHDMRSIndices(carrier,pdsch),[],1); ...
                reshape(nrPDSCHPTRSIndices(carrier,pdsch),[],1)];
            occupied = unique(mod(double([data(:);pilots(:)])-1,plane));
            assert(all(ismember(trs,reserved)) && isempty(intersect(trs,occupied)), ...
                'sixgr:phy:frame:UnreservedConnectedTRS', ...
                'Dedicated TRS REs must be reserved before PDSCH coding and must not collide with data or pilots.');
            assert(all(ismember(csi,reserved)) && isempty(intersect(csi,occupied)), ...
                'sixgr:phy:frame:UnreservedConnectedCSIRS', ...
                'Dedicated CSI-RS REs must be reserved before PDSCH coding and must not collide with data or pilots.');
            evidence.TRSRateMatchedRECount = numel(trs);
            evidence.CSIRSRateMatchedRECount = numel(csi);
            evidence.ConflictingOwners(isReference) = [];
            evidence.OverlapRECounts(isReference) = [];
            available = isempty(evidence.ConflictingOwners);
            evidence.Available = available;
            evidence.Source = "configured_connected_DL_ownership_with_verified_reference_RE_reservation_not_measured";
        end

        function validateSIB1References(obj)
            % Broadcast allocations cannot silently inherit a dedicated
            % receiver's CSI-RS puncturing configuration. Check the actual
            % common data/control REs throughout the complete calendar cycle.
            for ordinal=1:numel(obj.SIB1AdditionalPlans)
                obj.SIB1AdditionalPlans{ordinal}.validateSIB1References();
            end
            obj.validateSIB1TRS();
            obj.validateSIB1SSB();
            obj.validateSIB1BeamCollisions();
            if isempty(obj.SIB1Slot0) || ...
                    ~logical(sixgr.util.structGet(obj.Config,'phy.csirs.enable',false))
                return;
            end
            sixgr.phy.refsig.csirsOccasion(obj.Config,0); % Validate calendar.
            period = lcm(double(obj.Config.phy.csirs.period_slots),obj.BroadcastPeriodSlots);
            for slot0 = obj.SIB1Slot0:obj.BroadcastPeriodSlots:obj.SIB1Slot0+period-1
                reference = obj.csirsRE(slot0);
                if isempty(reference), continue; end
                carrier = obj.carrierAt(slot0);
                data = nrPDSCHIndices(carrier,obj.SIB1PDSCH);
                pilots = nrPDSCHDMRSIndices(carrier,obj.SIB1PDSCH);
                [control,~,controlPilots] = nrPDCCHResources(carrier,obj.SIB1PDCCH);
                plane = 12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
                siRE = unique(mod(double([data(:);pilots(:);control(:);controlPilots(:)])-1,plane));
                collision = intersect(siRE,reference);
                assert(isempty(collision),'sixgr:phy:frame:SIB1CSIRSCollision', ...
                    ['Configured SIB1/Type0 and CSI-RS overlap on %d carrier REs in absolute slot0 %d. ' ...
                    'Correct reference_signals.csi_rs_offset_slots or the authored reference allocation; ' ...
                    'common SI cannot inherit dedicated CSI-RS puncturing.'],numel(collision),slot0);
            end
        end

        function validateSIB1SSB(obj)
            for ordinal=1:numel(obj.SIB1AdditionalPlans)
                obj.SIB1AdditionalPlans{ordinal}.validateSIB1SSB();
            end
            if isempty(obj.SIB1Slot0), return; end
            % Native index support only. No encoding, sample generation or
            % reception is performed by this configured collision proof.
            timing=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(obj.Config);
            burst=sixgr.phy.ia.SSBBurstPlan.fromConfig(obj.Config,timing);
            sourcePeriod=double(timing.PeriodicityMs)*(double(timing.SSBSubcarrierSpacingKHz)/15)*14;
            starts=mod(double(timing.CandidateStartSymbols(double(burst.ActiveSSBIndices0Based)+1)),sourcePeriod);
            indices=unique(double([nrPSSIndices();nrSSSIndices(); ...
                nrPBCHIndices(obj.Carrier.NCellID);nrPBCHDMRSIndices(obj.Carrier.NCellID)]));
            native=false(240,max(starts)+4);
            for first=reshape(starts,1,[])
                native(indices+240*first)=true;
            end
            info=struct('SSBTiming',timing,'SSBGridValidation',timing.GridRelationship);
            support=sixgr.phy.broadcast.mixedSSBGridOccupancy(double(native),info,obj.Carrier);
            cycle=lcm(obj.SIB1PeriodSlots,obj.SSBPeriodSlots);
            for slot=obj.SIB1Slot0:obj.SIB1PeriodSlots:obj.SIB1Slot0+cycle-1
                carrier=obj.carrierAt(slot);
                first=mod(slot,obj.SSBPeriodSlots)*double(carrier.SymbolsPerSlot);
                columns=first+(1:double(carrier.SymbolsPerSlot));
                ssb=false(12*carrier.NSizeGrid,carrier.SymbolsPerSlot);
                valid=columns<=size(support,2);
                ssb(:,valid)=support(:,columns(valid));
                re=obj.sib1NativeRE(slot);
                assert(~any(ssb(re+1)), 'sixgr:phy:frame:SIB1SSBCollision', ...
                    'Configured SI/Type0 overlaps native SS/PBCH support at absolute slot %d.',slot);
            end
        end

        function validateSIB1BeamCollisions(obj)
            plans=[{obj},obj.SIB1AdditionalPlans];
            for a=1:numel(plans)
                for b=a+1:numel(plans)
                    left=plans{a}; right=plans{b};
                    assert(left.SIB1PeriodSlots==right.SIB1PeriodSlots, ...
                        'sixgr:phy:frame:SIB1BeamCalendarMismatch','Cell SI associations must use one native Type-0 period.');
                    if mod(left.SIB1Slot0-right.SIB1Slot0,left.SIB1PeriodSlots)~=0, continue; end
                    slot=max(left.SIB1Slot0,right.SIB1Slot0);
                    assert(isempty(intersect(left.sib1NativeRE(slot),right.sib1NativeRE(slot))), ...
                        'sixgr:phy:broadcast:SIB1BeamResourceCollision', ...
                        'Distinct configured SI beam codewords collide at recurring slot %d.',slot);
                end
            end
        end

        function validateSIB1TRS(obj)
            for ordinal=1:numel(obj.SIB1AdditionalPlans)
                obj.SIB1AdditionalPlans{ordinal}.validateSIB1TRS();
            end
            if isempty(obj.SIB1Slot0) || isempty(obj.TRS), return; end
            slots = sixgr.util.structGet(obj.Config,'phy.trs.slotNumbers', ...
                sixgr.util.structGet(obj.Config,'lls6g.reference_signals.trs.slot_numbers',[]));
            if isempty(slots)
                trsPeriod = sixgr.util.structGet(obj.Config,'phy.trs.period_slots',NaN);
            else
                trsPeriod = obj.Carrier.SlotsPerFrame;
            end
            validateattributes(trsPeriod,{'numeric'},{'scalar','finite','integer','positive'});
            period = lcm(double(trsPeriod),obj.BroadcastPeriodSlots);
            for slot0 = obj.SIB1Slot0:obj.BroadcastPeriodSlots:obj.SIB1Slot0+period-1
                carrier = obj.carrierAt(slot0);
                data = nrPDSCHIndices(carrier,obj.SIB1PDSCH);
                pilots = nrPDSCHDMRSIndices(carrier,obj.SIB1PDSCH);
                [control,~,controlPilots] = nrPDCCHResources(carrier,obj.SIB1PDCCH);
                siRE = unique(double([data(:);pilots(:);control(:);controlPilots(:)])-1);
                collision = intersect(siRE,obj.trsRE(slot0));
                assert(isempty(collision),'sixgr:phy:frame:SIB1TRSCollision', ...
                    ['Configured SIB1/Type0 and TRS overlap on %d carrier REs in slot %d. ' ...
                    'Change authored resource occasions; common SI cannot inherit dedicated CSI-RS puncturing.'], ...
                    numel(collision),slot0);
            end
        end
    end
    methods (Access=private)
        function re=sib1NativeRE(obj,slot0)
            carrier=obj.carrierAt(slot0);
            data=nrPDSCHIndices(carrier,obj.SIB1PDSCH);
            pilots=nrPDSCHDMRSIndices(carrier,obj.SIB1PDSCH);
            [control,~,controlPilots]=nrPDCCHResources(carrier,obj.SIB1PDCCH);
            re=unique(mod(double([data(:);pilots(:);control(:);controlPilots(:)])-1, ...
                12*carrier.NSizeGrid*carrier.SymbolsPerSlot));
        end
        function carrier = carrierAt(obj,slot0)
            validateattributes(slot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            carrier = obj.Carrier;
            carrier.NFrame = floor(slot0/carrier.SlotsPerFrame);
            carrier.NSlot = mod(slot0,carrier.SlotsPerFrame);
        end
        function tf = hasSIB1(obj,slot0)
            tf = ~isempty(obj.SIB1Slot0) && slot0>=obj.SIB1Slot0 && ...
                mod(slot0-obj.SIB1Slot0,obj.BroadcastPeriodSlots)==0;
        end
        function re = sib1ReservedRE(obj,slot0)
            if isequal(slot0,obj.PreparedSlot0), re=obj.PreparedSIB1RE0; return; end
            re=zeros(0,1);
            if obj.hasSIB1(slot0)
                carrier=obj.carrierAt(slot0);
                re=localRectangle(carrier,obj.SIB1PDSCH.PRBSet, ...
                    obj.SIB1PDSCH.SymbolAllocation(1)+(0:obj.SIB1PDSCH.SymbolAllocation(2)-1));
                [ind,~,dmrs]=nrPDCCHResources(carrier,obj.SIB1PDCCH);
                re=unique([re;double(ind(:))-1;double(dmrs(:))-1]);
            end
            for ordinal=1:numel(obj.SIB1AdditionalPlans)
                re=union(re,obj.SIB1AdditionalPlans{ordinal}.sib1ReservedRE(slot0));
            end
        end
        function re = trsRE(obj,slot0)
            if isequal(slot0,obj.PreparedSlot0), re=obj.PreparedTRSRE0; return; end
            re = zeros(0,1);
            if isempty(obj.TRS) || ~sixgr.truth.isActiveTRSOccasion(obj.Config,slot0+1), return; end
            carrier = obj.carrierAt(slot0);
            for k = 1:numel(obj.TRS.ToolboxResources)
                indices = nrCSIRSIndices(carrier,obj.TRS.ToolboxResources{k},'IndexBase','0based');
                re = [re;double(indices(:))]; %#ok<AGROW>
            end
            assert(~isempty(re),'sixgr:phy:frame:EmptyTRSReservation', ...
                'An active TRS resource must resolve actual CSI-RS indices.');
            re = unique(mod(re,12*carrier.NSizeGrid*carrier.SymbolsPerSlot));
        end
        function re = csirsRE(obj,slot0)
            if isequal(slot0,obj.PreparedSlot0), re=obj.PreparedCSIRSRE0; return; end
            re = zeros(0,1);
            if ~sixgr.phy.refsig.csirsOccasion(obj.Config,slot0), return; end
            cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(obj.Config,slot0+1);
            carrier = obj.carrierAt(slot0);
            indices = sixgr.phy.refsig.csirs(carrier,cfg);
            assert(~isempty(indices),'sixgr:phy:frame:EmptyCSIRSReservation', ...
                'An active CSI-RS resource must resolve actual indices at absolute slot0 %d.',slot0);
            re = unique(mod(double(indices(:))-1,12*carrier.NSizeGrid*carrier.SymbolsPerSlot));
        end
        function re = ssbRE(obj,slot0)
            if isequal(slot0,obj.PreparedSlot0), re=obj.PreparedSSBRE0; return; end
            ssb=sixgr.phy.frame.ssbPRBSymbolReservation(obj.Config,obj.carrierAt(slot0),slot0);
            re=ssb.ReservedCarrierRE0;
        end
    end
end

function re = localRectangle(carrier,prbs,symbols)
[k,l] = ndgrid(reshape(12*double(prbs(:).')+(0:11).',1,[]),double(symbols));
re = k(:)+12*carrier.NSizeGrid*l(:);
end

function [owners,counts] = localConflict(owners,counts,allocation,reserved,owner)
overlap = intersect(allocation,reserved);
if ~isempty(overlap)
    owners(end+1,1) = owner; counts(end+1,1) = numel(overlap);
end
end
