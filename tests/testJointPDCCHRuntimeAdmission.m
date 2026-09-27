function [ok,cfg] = testJointPDCCHRuntimeAdmission(scenarioPath)
% Installed target-scenario control allocation fixture, not a received grant.
if nargin<1, scenarioPath='simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml'; end
bad = struct('control',struct('joint_pdcch_admission_policy','lower_al_to_fit'));
rejected = false;
try, sixgr.lls6g.config.validateScenarioConfig(bad,'AllowPartial',true);
catch exception, rejected = strcmp(exception.identifier,'sixgr:lls6g:config:BadEnumValue'); end
assert(rejected,'Malformed admission policy must be rejected by the configuration schema.');
s = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
root = tempname(fullfile(pwd,'logs')); mkdir(root);
cfg = sixgr.lls6g.buildInternalConfig(s,root);
assert(string(cfg.phy.pdcch.jointAdmissionPolicy) == "ul_preschedule_first", ...
    'The scenario must inherit and map the explicit joint admission policy.');
installed = sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,'1_1');
rnti = double(installed.Data.RNTIValue);
multi = struct('Enabled',true,'NumUsers',1,'RNTIStart',rnti,'ExecutionModel','slot_coupled_truth');
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),58);
state.CurrentSlot = 34; state.CurrentFrame = 4; state.CurrentCanonicalSlot = 34;
state.CurrentServingIdx(:) = 1;
dl = struct('UEIndex',1,'ServingCell',1,'RNTI',rnti, ...
    'Direction',"DL",'ControlSlot',34,'ControlAbsoluteSlot',33,'Slot',34, ...
    'PDCCHAggregationLevel',8);
ul = dl; ul.Direction = "UL"; ul.Slot = 35;
[d,u] = sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg},dl,ul);
assert(~d.PDCCHAdmissionSelected && u.PDCCHAdmissionSelected);
assert(d.PDCCHAggregationLevel == 8 && u.PDCCHAggregationLevel == 8);
assert(u.PDCCHAdmissionControlSlot == 34 && u.Slot == 35 && ...
    size(u.PDCCHAdmissionCoordinates,1) == 576);
assert(~isfield(state,'PDCCHResourceLedger') || isempty(fieldnames(state.PDCCHResourceLedger)), ...
    'Planning cannot commit the transmitted-resource ledger.');
[blocked,~] = sixgr.truth.CoupledTruthRuntime.blockPDCCHGrantTrial( ...
    state,d,'DL',"control_blocked_no_nonoverlapping_pdcch_candidate");
assert(isequal(blocked.PDCCHFailureCount,state.PDCCHFailureCount), ...
    'Pre-transmission candidate exhaustion is not a receiver failure.');
for name = string(fieldnames(dl)).'
    assert(isequaln(d.(name),dl.(name)) && isequaln(u.(name),ul.(name)), ...
        'Admission must not rewrite an existing grant field.');
end
dl.DCI.Bits = uint8([1;0;1]); ul.DCI.Bits = uint8([0;1]);
[poisonDL,poisonUL] = sixgr.truth.resolveJointPDCCHAdmission(state,cfg,{cfg},dl,ul);
assert(isequal(poisonDL.PDCCHAdmissionCoordinates,d.PDCCHAdmissionCoordinates) && ...
    isequal(poisonUL.PDCCHAdmissionCoordinates,u.PDCCHAdmissionCoordinates), ...
    'Admission must not depend on a transmitted payload hypothesis.');
cfgLegacy = rmfield(cfg.phy.pdcch,'jointAdmissionPolicy');
unchanged = cfg; unchanged.phy.pdcch = cfgLegacy;
[d,u] = sixgr.truth.resolveJointPDCCHAdmission(state,unchanged,{unchanged},dl,ul);
assert(isequaln(d,dl) && isequaln(u,ul),'Absent optional policy must preserve legacy behavior.');
code = fileread(which('sixgr.truth.runWaveformLinkBundle'));
joint = strfind(code,'sixgr.truth.resolveJointPDCCHAdmission(');
enqueue = strfind(code,'[runtimeState, dlGrants, queuedDL] = localQualifyCoupledGrantsWithPDCCH');
assert(isscalar(joint) && isscalar(enqueue) && joint < enqueue, ...
    'The production runner must resolve joint admission before DAI finalization/enqueue.');
assert(contains(code,'sixgr:truth:PDCCHAdmissionExecutionMismatch'), ...
    'Actual PDCCH preparation must verify the planned physical allocation.');
fprintf('JOINT_PDCCH_RUNTIME_ADMISSION_PASS target YAML, AL8 UL protection, grant identity; no PHY acceptance claim.\n');
ok = true;
end
