classdef CommonRAResourceCalendar
    % Future cell/slot ownership from prepared Msg2/Msg4 and their UL grants.
    % This is a scheduling reservation, NOT transmitted/received evidence.
    % Keep future slots: a single-current-slot CCE ledger loses these plans.
    properties (SetAccess=private)
        Entries = struct('CellID',{},'Slot0',{},'Direction',{},'SCS',{}, ...
            'CP',{},'Owner',{},'Coordinates',{})
    end
    methods
        function obj=reserve(obj,entries)
            for e=reshape(entries,1,[])
                validateattributes(e.Coordinates,{'numeric'}, ...
                    {'real','finite','integer','nonnegative','2d','ncols',2,'nonempty'});
                same=strcmp(string({obj.Entries.Owner}),e.Owner) & [obj.Entries.CellID]==e.CellID;
                if any(same)
                    assert(nnz(same)==1 && isequaln(obj.Entries(same),e), ...
                        'sixgr:truth:CommonRAReservationChanged','A frozen access allocation cannot change.');
                    continue;
                end
                hit=[obj.Entries.CellID]==e.CellID & [obj.Entries.Slot0]==e.Slot0 & ...
                    string({obj.Entries.Direction})==e.Direction;
                for old=reshape(obj.Entries(hit),1,[])
                    assert(old.SCS==e.SCS && old.CP==e.CP, ...
                        'sixgr:truth:CommonRANumerologyMismatch','Resolve cross-numerology overlap explicitly.');
                    assert(isempty(intersect(old.Coordinates,e.Coordinates,'rows')), ...
                        'sixgr:truth:CommonRAResourceCollision','Two access plans overlap before transmission.');
                end
                obj.Entries(end+1)=e;
            end
        end

        function coordinates=lookup(obj,cellID,slot0,direction,carrier)
            validateattributes(slot0,{'numeric'},{'scalar','finite','integer','nonnegative'});
            hit=[obj.Entries.CellID]==cellID & [obj.Entries.Slot0]==slot0 & ...
                string({obj.Entries.Direction})==string(direction);
            coordinates=zeros(0,2);
            for e=reshape(obj.Entries(hit),1,[])
                assert(e.SCS==carrier.SubcarrierSpacing && e.CP==string(carrier.CyclicPrefix), ...
                    'sixgr:truth:CommonRANumerologyMismatch','Do not compare unlike slot/frequency coordinates.');
                coordinates=[coordinates;e.Coordinates]; %#ok<AGROW>
            end
            coordinates=unique(coordinates,'rows');
        end

        function assertPUCCHDisjoint(obj,cellID,slot0,carrier,resource)
            access=obj.lookup(cellID,slot0,"UL",carrier);
            occupied=sixgr.truth.CommonRAResourceCalendar.pucchCoordinates(carrier,resource);
            assert(isempty(intersect(access,occupied,'rows')), ...
                'sixgr:truth:CommonRAPUCCHCollision', ...
                'The actual PUCCH must not overlap a frozen Msg3/SRB1 allocation.');
        end
    end
    methods (Static)
        function entries=fromTransmission(tx,ra,stage)
            entries=struct('CellID',{},'Slot0',{},'Direction',{},'SCS',{}, ...
                'CP',{},'Owner',{},'Coordinates',{});
            stage=string(stage);
            if ~any(stage==["Msg2","Msg4"]), return; end
            c=tx.Carrier;
            slot=ra.Msg2Slot; id=ra.RARNTI;
            if stage=="Msg4", slot=ra.Msg4Slot; id=ra.TempCRNTI; end
            owner=stage+"_slot0_"+slot+"_rnti_"+id;
            ind=double([tx.PDCCH.PDCCHInd(:);tx.PDCCH.DMRSInd(:)])-1;
            k=12*c.NSizeGrid;
            control=[mod(ind,k)+12*c.NStartGrid,mod(floor(ind/k),c.SymbolsPerSlot)];
            data=sixgr.truth.CommonRAResourceCalendar.transmissionRectangle(tx.PDSCH,"DL");
            entries(end+1)=sixgr.truth.CommonRAResourceCalendar.entry( ...
                c,ra.ServingCell,slot,"DL",owner,unique([control;data],'rows'));
            if stage=="Msg2"
                responses=sixgr.util.structGet(tx.RAR,'Responses',tx.RAR);
                for r=reshape(responses,1,[])
                    p=sixgr.phy.ra.localPUSCHConfigFromGrant(ra,r.ULGrant);
                    coordinates=sixgr.truth.CommonRAResourceCalendar.channelRectangle(c,p);
                    entries(end+1)=sixgr.truth.CommonRAResourceCalendar.entry( ...
                        c,ra.ServingCell,ra.Msg3Slot,"UL", ...
                        "Msg3_slot0_"+ra.Msg3Slot+"_rnti_"+r.TemporaryCRNTI,coordinates); %#ok<AGROW>
                end
            elseif ra.RequireRRCSetupComplete
                s=ra.SetupCompletePUSCH; p=nrPUSCHConfig;
                p.PRBSet=s.PRBStart+(0:s.NumPRB-1);
                p.SymbolAllocation=[s.SymbolStart s.NumSymbols];
                coordinates=sixgr.truth.CommonRAResourceCalendar.channelRectangle(c,p);
                entries(end+1)=sixgr.truth.CommonRAResourceCalendar.entry( ...
                    c,ra.ServingCell,ra.SetupCompleteSlot,"UL", ...
                    "SRB1_slot0_"+ra.SetupCompleteSlot+"_rnti_"+id,coordinates);
            end
        end

        function coordinates=channelRectangle(carrier,channel)
            first=channel.NStartBWP;
            if isempty(first), first=carrier.NStartGrid; end
            symbols=channel.SymbolAllocation(1)+(0:channel.SymbolAllocation(2)-1);
            sc=reshape(12*(first+double(channel.PRBSet(:).'))+(0:11).',[],1);
            [x,y]=ndgrid(sc,symbols);
            coordinates=unique([x(:) y(:)],'rows');
        end

        function coordinates=transmissionRectangle(tx,direction)
            % Canonical PDSCH has an immutable assignment, not a legacy
            % tx.PDSCH object. Both adapters use the transmitted allocation.
            if string(direction)=="DL" && isfield(tx,'Assignment')
                a=tx.Assignment.toStruct(); channel=nrPDSCHConfig;
                channel.PRBSet=a.PRBSetCarrierRelative;
                channel.SymbolAllocation=a.SymbolAllocation;
            elseif string(direction)=="DL"
                channel=tx.PDSCH;
            else
                channel=tx.PUSCH;
            end
            coordinates=sixgr.truth.CommonRAResourceCalendar.channelRectangle(tx.Carrier,channel);
        end

        function assertPeriodicSRSDisjoint(entries,cfg)
            % A different UE cannot cancel its installed periodic SRS just
            % because this UE received a Msg4/SRB1 allocation. Reject the
            % conflicting plan before transmitting, without muting pilots.
            if ~logical(sixgr.util.structGet(cfg,'phy.srs.enable',false)), return; end
            s=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
            if string(s.ResourceType)~="periodic", return; end
            c=s.ToolboxCarrier;
            for e=reshape(entries,1,[])
                if e.Direction~="UL", continue; end
                assert(e.SCS==c.SubcarrierSpacing && e.CP==string(c.CyclicPrefix), ...
                    'sixgr:truth:CommonRANumerologyMismatch','SRS/access overlap needs a common coordinate plane.');
                c.NFrame=floor(e.Slot0/c.SlotsPerFrame); c.NSlot=mod(e.Slot0,c.SlotsPerFrame);
                ind=double(nrSRSIndices(c,s.ToolboxSRS))-1;
                k=12*c.NSizeGrid;
                coords=[mod(ind(:),k)+12*c.NStartGrid,mod(floor(ind(:)/k),c.SymbolsPerSlot)];
                assert(isempty(intersect(e.Coordinates,coords,'rows')), ...
                    'sixgr:truth:CommonRAPeriodicSRSCollision', ...
                    'Configure disjoint SRB1 PUSCH/SRS resources; do not silently cancel another UE''s periodic SRS.');
            end
        end

        function assertInstalledPUCCHDisjoint(entries,cfg,ue)
            % Reserve configured PUCCH capacity before sending another UE's
            % Msg4: future dynamic ACK obligations cannot yet be enumerated.
            % This is admission policy, not evidence that every resource TXs.
            section=sixgr.phy.pucch.resolveUEReportResources(cfg,ue);
            if ~logical(sixgr.util.structGet(section,'enabled',false)), return; end
            rrc=sixgr.phy.pucch.PUCCHConfigBuilder.receiverConfiguration(cfg,ue);
            c=sixgr.phy.grid.makeCarrier(cfg);
            for e=reshape(entries,1,[])
                if e.Direction~="UL", continue; end
                assert(e.SCS==c.SubcarrierSpacing && e.CP==string(c.CyclicPrefix), ...
                    'sixgr:truth:CommonRANumerologyMismatch','PUCCH/access overlap needs a common coordinate plane.');
                c.NFrame=floor(e.Slot0/c.SlotsPerFrame); c.NSlot=mod(e.Slot0,c.SlotsPerFrame);
                for r=reshape(rrc.Resources,1,[])
                    coords=sixgr.truth.CommonRAResourceCalendar.pucchCoordinates(c,r);
                    assert(isempty(intersect(e.Coordinates,coords,'rows')), ...
                        'sixgr:truth:CommonRAPUCCHCollision', ...
                        'Configure SRB1 resources disjoint from another UE''s installed PUCCH resources.');
                end
            end
        end

        function coords=pucchCoordinates(carrier,resource)
            p=resource.toolboxConfig();
            ind=double([nrPUCCHIndices(carrier,p);nrPUCCHDMRSIndices(carrier,p)])-1;
            k=12*carrier.NSizeGrid;
            coords=unique([mod(ind(:),k)+12*carrier.NStartGrid, ...
                mod(floor(ind(:)/k),carrier.SymbolsPerSlot)],'rows');
        end

        function e=entry(c,cellID,slot0,direction,owner,coordinates)
            validateattributes(cellID,{'numeric'},{'scalar','finite','integer','positive'});
            validateattributes(slot0,{'numeric'},{'scalar','finite','integer','nonnegative'});
            assert(any(string(direction)==["DL","UL"]),'sixgr:truth:InvalidCommonRADirection','Require DL/UL.');
            e=struct('CellID',double(cellID),'Slot0',double(slot0),'Direction',string(direction), ...
                'SCS',double(c.SubcarrierSpacing),'CP',string(c.CyclicPrefix), ...
                'Owner',string(owner),'Coordinates',unique(double(coordinates),'rows'));
        end

        function budget=excludeFromBudget(budget,coordinates,bwpOriginCRB)
            % Exclude only PRBs whose scheduled symbols intersect an access
            % allocation. Other cells/slots and disjoint symbols stay usable.
            symbols=budget.SymbolAllocation(1)+(0:budget.SymbolAllocation(2)-1);
            blocked=unique(floor(coordinates(ismember(coordinates(:,2),symbols),1)/12)-bwpOriginCRB);
            budget.ReservedCommonRAPRBSet=intersect(budget.PRBSet,blocked,'stable');
            budget.PRBSet=setdiff(budget.PRBSet,blocked,'stable');
            budget.NPRB=numel(budget.PRBSet);
        end
    end
end
