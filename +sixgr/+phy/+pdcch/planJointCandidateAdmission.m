function plan = planJointCandidateAdmission(requests, policy)
% Joint gNB admission over actual configured PDCCH data and DM-RS resources.
% TS 38.213 clause 10.1 defines the candidate resources, not direction priority.
% This policy is a scheduler choice. No DCI bits, decoded UE values or received
% energy enter the decision. The caller finalizes DAI only after admission.
policy = lower(strtrim(string(policy)));
assert(isscalar(policy) && any(policy == ["dl_then_ul","ul_preschedule_first"]), ...
    'sixgr:phy:pdcch:InvalidJointAdmissionPolicy', ...
    'Joint admission requires dl_then_ul or ul_preschedule_first.');
assert(isstruct(requests), 'sixgr:phy:pdcch:InvalidAdmissionRequest', ...
    'Admission requests must contain installed carrier and monitoring objects.');
n = numel(requests);
plan = repmat(struct('Admitted',false,'Reason',"no_nonoverlapping_candidate", ...
    'Coordinates',zeros(0,2),'ReservedForOtherGrants',zeros(0,2), ...
    'CandidateIndex',NaN,'AggregationLevel',NaN,'Policy',policy),n,1);
if n == 0, return; end
assert(all(isfield(requests,{'ControlSlot','CellID','Direction', ...
    'Carrier','PDCCH','OccupiedRECoordinates'})), ...
    'sixgr:phy:pdcch:InvalidAdmissionRequest','Incomplete physical admission context.');
directions = upper(string({requests.Direction}));
assert(all(ismember(directions,["DL","UL"])), ...
    'sixgr:phy:pdcch:InvalidAdmissionRequest','Direction must be DL or UL.');
for k = 1:n
    validateattributes(requests(k).ControlSlot,{'numeric'},{'scalar','integer','positive','finite'});
    validateattributes(requests(k).CellID,{'numeric'},{'scalar','integer','positive','finite'});
    validateattributes(requests(k).OccupiedRECoordinates,{'numeric'}, ...
        {'real','finite','integer','nonnegative','2d','ncols',2});
    assert(isa(requests(k).Carrier,'nrCarrierConfig') && isa(requests(k).PDCCH,'nrPDCCHConfig'), ...
        'sixgr:phy:pdcch:InvalidAdmissionRequest','Use actual Toolbox resource configurations.');
end
first = "DL";
if policy == "ul_preschedule_first", first = "UL"; end
order = [find(directions == first), find(directions ~= first)];
for k = order
    q = requests(k);
    occupied = double(q.OccupiedRECoordinates);
    for j = 1:n
        if q.ControlSlot ~= requests(j).ControlSlot || q.CellID ~= requests(j).CellID
            continue;
        end
        other = requests(j);
        assert(q.Carrier.SubcarrierSpacing == other.Carrier.SubcarrierSpacing && ...
            strcmp(q.Carrier.CyclicPrefix,other.Carrier.CyclicPrefix), ...
            'sixgr:phy:pdcch:AdmissionNumerologyMismatch', ...
            'Shared-cell admission requires a common time-frequency coordinate system.');
        assert(isequal(unique(q.OccupiedRECoordinates,'rows'), ...
            unique(other.OccupiedRECoordinates,'rows')), ...
            'sixgr:phy:pdcch:AdmissionReservationMismatch', ...
            'Same-occasion requests must see the same pre-existing physical reservations.');
        if plan(j).Admitted, occupied = [occupied;plan(j).Coordinates]; end %#ok<AGROW>
    end
    plan(k).AggregationLevel = double(q.PDCCH.AggregationLevel);
    try
        [selected,coordinates] = sixgr.phy.pdcch.allocateNonoverlappingCandidate( ...
            q.Carrier,q.PDCCH,unique(occupied,'rows'));
    catch exception
        if ~strcmp(exception.identifier,'sixgr:phy:pdcch:NoFreeCandidate'), rethrow(exception); end
        continue;
    end
    plan(k).Admitted = true;
    plan(k).Reason = "admitted_configured_candidate";
    plan(k).Coordinates = coordinates;
    plan(k).CandidateIndex = double(selected.AllocatedCandidate);
end
% Keep reservations separate from the transmitted ledger. During DL-first
% serialization they prevent stealing a future UL grant's planned resource.
for k = 1:n
    for j = 1:n
        if j ~= k && plan(j).Admitted && ...
                requests(k).ControlSlot == requests(j).ControlSlot && ...
                requests(k).CellID == requests(j).CellID
            plan(k).ReservedForOtherGrants = [plan(k).ReservedForOtherGrants;plan(j).Coordinates];
        end
    end
    plan(k).ReservedForOtherGrants = unique(plan(k).ReservedForOtherGrants,'rows');
end
end
