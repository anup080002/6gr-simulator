function [dlGrants,ulGrants] = resolveJointPDCCHAdmission(state,cfg,userCfg,dlGrants,ulGrants)
% Plan physical control resources before either DL or UL DCI is serialized.
% Does not advance a channel, commit DAI, enqueue IQ or authorize UE reception.
policy = lower(strtrim(string(sixgr.util.structGet(cfg,'phy.pdcch.jointAdmissionPolicy',""))));
groups = {dlGrants,ulGrants};
assert(isscalar(policy) && ~ismissing(policy), ...
    'sixgr:truth:InvalidJointPDCCHAdmissionPolicy', ...
    'Joint PDCCH admission policy must be one configured value.');
if strlength(policy) == 0
    % An absent preference is harmless only when there is no joint admission
    % decision. Do not silently restore DL-first serialization for competing
    % DL/UL or multi-UE candidates on the same cell/control occasion. The
    % priority is scheduler policy, not a direction priority prescribed by NR.
    owners = zeros(numel(dlGrants)+numel(ulGrants),2);
    index = 0;
    for directionIndex = 1:2
        for k = 1:numel(groups{directionIndex})
            grant = groups{directionIndex}(k);
            cellID = double(grant.ServingCell);
            validateattributes(cellID,{'double'},{'scalar','real','finite','integer','positive'});
            index = index+1;
            owners(index,:) = [cellID, ...
                sixgr.truth.resolvePDCCHControlSlot(grant,state.CurrentSlot)];
        end
    end
    assert(size(unique(owners,'rows'),1)==size(owners,1), ...
        'sixgr:truth:MissingJointPDCCHAdmissionPolicy', ...
        ['Competing PDCCH grants require an explicit control.joint_pdcch_admission_policy ' ...
         '(dl_then_ul or ul_preschedule_first) before DAI or waveform preparation.']);
    return;
end
directions = ["DL","UL"];
requests = repmat(struct('ControlSlot',0,'CellID',0,'Direction',"", ...
    'Carrier',[],'PDCCH',[],'OccupiedRECoordinates',zeros(0,2)),0,1);
for directionIndex = 1:2
    for k = 1:numel(groups{directionIndex})
        grant = groups{directionIndex}(k);
        ue = double(grant.UEIndex);
        validateattributes(ue,{'numeric'},{'scalar','integer','positive','<=',numel(userCfg)});
        direction = upper(string(grant.Direction));
        assert(direction == directions(directionIndex), ...
            'sixgr:truth:JointPDCCHDirectionMismatch','Grant direction disagrees with its scheduling group.');
        [cfgControl,~] = sixgr.truth.CoupledTruthRuntime.applyUserContext(userCfg{ue},state,ue,direction);
        slot = sixgr.truth.resolvePDCCHControlSlot(grant,state.CurrentSlot);
        assert(slot == state.CurrentSlot,'sixgr:truth:JointPDCCHControlSlotMismatch', ...
            'Admission must use the current DL control slot, not a future UL data slot.');
        cfgControl.phy.pdcch.aggregationLevel = ...
            sixgr.phy.pdcch.resolveScheduledAggregationLevel(cfgControl,grant);
        cfgControl = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfgControl,slot);
        cfgControl = sixgr.util.structSet(cfgControl,'lls6g.userContext.RuntimeCurrentDirection',"DL");
        cfgControl = sixgr.util.structSet(cfgControl,'lls6g.userContext.Direction',"DL");
        cfgControl = sixgr.util.structSet(cfgControl,'lls6g.userContext.RuntimeSignalFamily',"PDCCH");
        cfgControl = sixgr.util.structSet(cfgControl,'phy.runtimeSignalFamily',"PDCCH");
        [carrier,~] = sixgr.phy.grid.makeCarrier(cfgControl);
        [pdcch,~] = sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build(cfgControl,carrier,grant.RNTI,false);
        [~,occupied] = sixgr.truth.PDCCHSlotResourceLedger.lookup( ...
            sixgr.util.structGet(state,'PDCCHResourceLedger',struct()),slot,grant.ServingCell,carrier);
        occupied=unique([occupied;sixgr.truth.commonPDCCHReservations( ...
            state,cfgControl,slot-1,grant.ServingCell,carrier)],'rows');
        request = struct('ControlSlot',slot,'CellID',double(grant.ServingCell), ...
            'Direction',direction,'Carrier',carrier,'PDCCH',pdcch, ...
            'OccupiedRECoordinates',occupied);
        requests(end+1,1) = request; %#ok<AGROW>
    end
end
plan = sixgr.phy.pdcch.planJointCandidateAdmission(requests,policy);
index = 0;
for directionIndex = 1:2
    for k = 1:numel(groups{directionIndex})
        index = index+1;
        groups{directionIndex}(k).PDCCHAdmissionPolicy = policy;
        groups{directionIndex}(k).PDCCHAdmissionSelected = plan(index).Admitted;
        groups{directionIndex}(k).PDCCHAdmissionCoordinates = plan(index).Coordinates;
        groups{directionIndex}(k).PDCCHAdmissionOtherReservations = plan(index).ReservedForOtherGrants;
        groups{directionIndex}(k).PDCCHAdmissionControlSlot = requests(index).ControlSlot;
        groups{directionIndex}(k).PDCCHAdmissionCell = requests(index).CellID;
        groups{directionIndex}(k).PDCCHPlannedCandidateIndex = plan(index).CandidateIndex;
    end
end
dlGrants = groups{1}; ulGrants = groups{2};
end
