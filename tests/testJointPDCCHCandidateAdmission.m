function ok = testJointPDCCHCandidateAdmission()
% Actual resource mapping and OFDM/decoder checks; not a full scenario claim.
carrier = nrCarrierConfig('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',15);
core = nrCORESETConfig('FrequencyResources',ones(1,4),'Duration',2, ...
    'CCEREGMapping','noninterleaved');
search = nrSearchSpaceConfig('CORESETID',core.CORESETID, ...
    'SearchSpaceType','ue','NumCandidates',[8 4 2 1 0]);
pdcch = nrPDCCHConfig('CORESET',core,'SearchSpace',search,'RNTI',101, ...
    'AggregationLevel',8,'NSizeBWP',24,'NStartBWP',0);
q = struct('ControlSlot',34,'CellID',1,'Direction',"DL", ...
    'Carrier',carrier,'PDCCH',pdcch,'OccupiedRECoordinates',zeros(0,2));
requests = [q q]; requests(2).Direction = "UL";
before = requests;
plan = sixgr.phy.pdcch.planJointCandidateAdmission(requests,"ul_preschedule_first");
assert(isequal([plan.Admitted],[false true]) && all([plan.AggregationLevel] == 8));
assert(size(plan(2).Coordinates,1) == 8*6*12);
legacy = sixgr.phy.pdcch.planJointCandidateAdmission(requests,"dl_then_ul");
assert(isequal([legacy.Admitted],[true false]));
assert(isequaln(before,requests),'Admission must not mutate caller configurations.');
for mapping = ["noninterleaved","interleaved"]
    for dlAL = [1 2 4 8]
        for ulAL = [1 2 4 8]
            requests = before;
            for k = 1:2, requests(k).PDCCH.CORESET.CCEREGMapping = mapping; end
            requests(1).PDCCH.AggregationLevel = dlAL;
            requests(2).PDCCH.AggregationLevel = ulAL;
            plan = sixgr.phy.pdcch.planJointCandidateAdmission(requests,"ul_preschedule_first");
            assert(plan(2).Admitted && isequal([plan.AggregationLevel],[dlAL ulAL]));
            occupied = zeros(0,2); waveform = [];
            transmitted = cell(1,2); bits = cell(1,2);
            for k = 1:2
                if ~plan(k).Admitted, continue; end
                cfg = struct('phy',struct('carrier',struct('NSizeGrid',24, ...
                    'SubcarrierSpacing',15,'NStartGrid',0,'NCellID',1)));
                cfg.phy.pdcch = struct('enable',true,'dmrs',struct('enable',true), ...
                    'blindSearch',false,'rnti',101);
                bits{k} = int8(mod((0:31).'+k,2));
                [tx,info] = sixgr.phy.dl.PDCCH_Tx(cfg,'Carrier',carrier, ...
                    'PDCCH',requests(k).PDCCH,'RNTI',101,'DCIBits',bits{k}, ...
                    'ReservedRECoordinates',unique([occupied;plan(k).ReservedForOtherGrants],'rows'));
                assert(isequal(info.AllocatedRECoordinates,plan(k).Coordinates));
                assert(isempty(intersect(occupied,info.AllocatedRECoordinates,'rows')));
                occupied = [occupied;info.AllocatedRECoordinates]; %#ok<AGROW>
                transmitted{k} = tx;
                if isempty(waveform), waveform = tx.Waveform; else, waveform = waveform+tx.Waveform; end
            end
            for k = 1:2
                if ~plan(k).Admitted, continue; end
                rx = sixgr.phy.dl.PDCCH_Rx(waveform,cfg,'Carrier',carrier, ...
                    'PDCCH',transmitted{k}.PDCCH,'K',32,'NoiseVar',1e-12);
                assert(rx.Ok && isequal(int8(rx.DCIBits),bits{k}), ...
                    'Composite decode failed: mapping=%s DL_AL=%d UL_AL=%d direction_index=%d CRC_error=%g.', ...
                    mapping,dlAL,ulAL,k,double(rx.ErrFlag));
            end
        end
    end
end
requests = before; requests(2).CellID = 2;
plan = sixgr.phy.pdcch.planJointCandidateAdmission(requests,"ul_preschedule_first");
assert(all([plan.Admitted]),'Separate cells do not share a resource ledger.');
requests = before; requests(2).ControlSlot = 35;
plan = sixgr.phy.pdcch.planJointCandidateAdmission(requests,"ul_preschedule_first");
assert(all([plan.Admitted]),'Separate control slots do not share a resource ledger.');
requests = before;
allRE = legacy(1).Coordinates;
for k = 1:2, requests(k).OccupiedRECoordinates = allRE; end
plan = sixgr.phy.pdcch.planJointCandidateAdmission(requests,"ul_preschedule_first");
assert(~any([plan.Admitted]),'Existing transmissions cannot be displaced.');
localReject(@()sixgr.phy.pdcch.planJointCandidateAdmission(before,"lower_al_to_fit"), ...
    'sixgr:phy:pdcch:InvalidJointAdmissionPolicy');
requests = before; requests(2).OccupiedRECoordinates = allRE;
localReject(@()sixgr.phy.pdcch.planJointCandidateAdmission(requests,"ul_preschedule_first"), ...
    'sixgr:phy:pdcch:AdmissionReservationMismatch');
ok = true;
fprintf('JOINT_PDCCH_ADMISSION_PASS: AL8 contention plus 32 mapped DL/UL composite cases; not full runtime acceptance.\n');
end

function localReject(call,identifier)
try, call(); catch exception, assert(strcmp(exception.identifier,identifier),exception.message); return; end
error('testJointPDCCHCandidateAdmission:MissingRejection','Expected %s.',identifier);
end
