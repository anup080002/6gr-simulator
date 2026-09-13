classdef CommonDLResourcePlan
    % Configured ownership, not measured waveform evidence. Never edits a TB.
    % RA PDSCHs have no dedicated CSI-RS rate-matching authority; choose a
    % nonoverlapping occasion before coding instead of puncturing coded data.
    properties (SetAccess=private)
        Config
        Carrier
        SIB1Slot0 = []
        BroadcastPeriodSlots = []
        SIB1PDSCH
        SIB1PDCCH
        TRS
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
                [obj.SIB1PDCCH,siCfg,siCarrier,~,obj.SIB1Slot0] = ...
                    sixgr.phy.broadcast.resolveSIB1ControlOccasion(obj.Carrier,origin);
                obj.SIB1PDSCH = sixgr.phy.broadcast.configuredSIB1Allocation(siCarrier,siCfg);
                timing = sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
                obj.BroadcastPeriodSlots = double(timing.PeriodicityMs)*obj.Carrier.SlotsPerSubframe;
                validateattributes(obj.BroadcastPeriodSlots,{'numeric'}, ...
                    {'scalar','finite','integer','positive'});
                % Keep the absolute Type-0 offset. It may lie beyond the
                % first SSB period; reducing it modulo the period would
                % reserve a SIB1 transmission that has not started yet.
            end
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
            ssb = sixgr.phy.frame.ssbPRBSymbolReservation(obj.Config,carrier,slot0);
            [owners,counts] = localConflict(owners,counts,re,ssb.ReservedCarrierRE0,"SSB_PRB_symbol_reservation");
            [owners,counts] = localConflict(owners,counts,re,obj.trsRE(slot0),"TRS");
            if obj.hasSIB1(slot0)
                siRE = localRectangle(carrier,obj.SIB1PDSCH.PRBSet, ...
                    obj.SIB1PDSCH.SymbolAllocation(1)+(0:obj.SIB1PDSCH.SymbolAllocation(2)-1));
                [ind,~,dmrs] = nrPDCCHResources(carrier,obj.SIB1PDCCH);
                siRE = unique([siRE;double(ind(:))-1;double(dmrs(:))-1]);
                [owners,counts] = localConflict(owners,counts,re,siRE,"SIB1_PDSCH_and_Type0_PDCCH");
            end
            available = isempty(owners);
            evidence = struct('AbsoluteSlot0',double(slot0),'Available',available, ...
                'ConflictingOwners',owners,'OverlapRECounts',counts, ...
                'Source',"configured_common_DL_resource_ownership_not_measured", ...
                'ControlCandidateValidated',false,'ProxyUsed',false,'FallbackUsed',false);
        end

        function [available,evidence] = checkConnectedPDSCH(obj,allocation,slot0)
            % Dedicated periodic NZP-CSI-RS with trs-Info is excluded at RE
            % granularity by TS 38.211 7.3.1.5. This is NOT the common/RA
            % allocation policy, aperiodic CSI-RS or the TRS-ResourceSet IE.
            % Eligibility here precedes the final rank/MCS-specific PHY
            % feasibility check; it does not freeze capacity or a TB.
            [available,evidence] = obj.checkPDSCH(allocation,slot0);
            isTRS = evidence.ConflictingOwners == "TRS";
            evidence.TRSRateMatchedRECount = 0;
            if ~any(isTRS), return; end
            assert(obj.TRS.TRSInfoEnabled && obj.TRS.CSIRSType == "nzp" && ...
                any(obj.TRS.SlotAuthority == ["periodic_offset","explicit_slot_numbers"]), ...
                'sixgr:phy:frame:MissingDedicatedTRSAuthority', ...
                'Connected TRS sharing requires configured periodic NZP-CSI-RS with trs-Info.');
            cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(obj.Config,slot0+1);
            carrier = obj.carrierAt(slot0);
            prbs = allocation.PRBStart+(0:allocation.NumPRB-1);
            symbols = [allocation.SymbolStart allocation.NumSymbols];
            [data,~,pdsch] = sixgr.phy.grid.allocREsPDSCH(carrier,cfg, ...
                'PRBSet',prbs,'SymbolAllocation',symbols);
            plane = 12*carrier.NSizeGrid*carrier.SymbolsPerSlot;
            trs = intersect(obj.trsRE(slot0),localRectangle(carrier,prbs, ...
                symbols(1)+(0:symbols(2)-1)));
            reserved = unique(mod(double(pdsch.ReservedRE(:)),plane));
            pilots = [reshape(nrPDSCHDMRSIndices(carrier,pdsch),[],1); ...
                reshape(nrPDSCHPTRSIndices(carrier,pdsch),[],1)];
            occupied = unique(mod(double([data(:);pilots(:)])-1,plane));
            assert(all(ismember(trs,reserved)) && isempty(intersect(trs,occupied)), ...
                'sixgr:phy:frame:UnreservedConnectedTRS', ...
                'Dedicated TRS REs must be reserved before PDSCH coding and must not collide with data or pilots.');
            evidence.TRSRateMatchedRECount = numel(trs);
            evidence.ConflictingOwners(isTRS) = [];
            evidence.OverlapRECounts(isTRS) = [];
            available = isempty(evidence.ConflictingOwners);
            evidence.Available = available;
            evidence.Source = "configured_connected_DL_ownership_with_verified_TRS_RE_reservation_not_measured";
        end

        function validateSIB1TRS(obj)
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
        function re = trsRE(obj,slot0)
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
