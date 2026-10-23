function [ok, evidence] = testULFrozenPreparationSpatialAuthority(receivedControlPath)
%TESTULFROZENPREPARATIONSPATIALAUTHORITY Replay original admitted grant metadata.
% With no arguments, use a declared native-allocation component fixture with
% no received SRS/DCI. With a path, replay its original item/control. No local
% archive is silently selected and no received SRS or DCI is manufactured.
% The runtime below is a newly initialized metadata-only
% component context, NOT the original runtime/checkpoint. Public trial-context
% normalization and canonical grant finalization run; no waveform, scheduler,
% RF, decoder, HARQ feedback, or data queue is executed. This does not prove
% that the subsequent shared PUSCH or sustained rank transition succeeds.

setup6GRSimToolkit('Verbose',false);
if nargin == 0
    [ok,evidence] = localDeclaredComponent();
    return;
end
assert(nargin == 1 && isscalar(string(receivedControlPath)) && ...
    isfile(receivedControlPath), ...
    'sixgr:test:ULPreparation:OriginalReceiptRequired', ...
    'Supply an original received_srs_ul_control.mat; no synthetic authority is substituted.');
sourcePath = string(receivedControlPath);
sourceSHA = string(sixgr.util.sha256File(sourcePath));
saved = load(sourcePath,'item','control');
assert(isfield(saved,'item') && isfield(saved,'control'), ...
    'sixgr:test:ULPreparation:OriginalReceiptRequired', ...
    'The original completed control item and accepted control are required.');
item = saved.item;
control = saved.control;
c = item.Context;
grant = control.Grant;
assert(item.Kind == "PDCCH" && string(c.Direction) == "UL" && ...
    isequal(control.Allowed,true) && string(control.Key) == string(c.Key), ...
    'sixgr:test:ULPreparation:OriginalAdmissionRequired', ...
    'The source must retain an actually admitted UL control.');
sixgr.phy.pdcch.validateConnectedAssignment(c.Prepared.ReceiverConfig, ...
    control.ReceivedAssignment);
assert(control.ReceivedAssignment.DataAbsoluteSlot == grant.Slot-1 && ...
    control.ReceivedAssignment.ControlAbsoluteSlot == c.Slot-1 && ...
    control.ReceivedAssignment.RNTI == grant.RNTI && ...
    string(control.ReceivedAssignment.PayloadHash) == string(grant.PDCCHGrantDCIId), ...
    'sixgr:test:ULPreparation:OriginalAssignmentMismatch', ...
    'The retained received assignment must bind the original grant and clocks.');
originalPHY = grant.PHYGrant;
assert(originalPHY.IsFrozen && ...
    string(originalPHY.PrecodingState.TransmissionScheme) == "codebook" && ...
    ~isfield(grant,'NumLogicalPorts') && ...
    isfield(grant,'AcceptedSRSSpatialDecision') && ...
    ~isempty(fieldnames(grant.AcceptedSRSSpatialDecision)), ...
    'sixgr:test:ULPreparation:OriginalBoundaryRequired', ...
    'Use the original absent-alias, frozen codebook grant with received SRS authority.');
ports = double(originalPHY.AntennaArchitecture.NumLogicalPorts);
assert(grant.NumLayers == originalPHY.AntennaArchitecture.NumLayers && ...
    grant.Layers == grant.NumLayers && ...
    grant.AcceptedSRSSpatialDecision.RI == grant.NumLayers && ...
    grant.TPMI == originalPHY.PrecodingState.TPMI, ...
    'sixgr:test:ULPreparation:OriginalSpatialMismatch', ...
    'The source must already agree on the accepted and frozen spatial tuple.');

% Preserve the original installed config, including its bootstrap rank/TPMI.
% The received frozen grant, not those mutable aliases, owns this execution.
cfg = c.ScheduledULHARQConfig;
multi = sixgr.truth.resolveMultiUserSpec(cfg);
previousRNG = rng;
rngCleanup = onCleanup(@() rng(previousRNG)); %#ok<NASGU>
work = tempname;
mkdir(work);
workCleanup = onCleanup(@() rmdir(work,'s')); %#ok<NASGU>
state = sixgr.truth.CoupledTruthRuntime.initialize( ...
    cfg,work,multi,struct(),double(grant.Slot));
% Explicit component calendar coordinates from the retained command. No
% access/feedback/scheduling eligibility flag is authored or bypassed here.
state.CurrentSlot = double(c.Slot);
state.CurrentCanonicalSlot = double(c.Slot);
state.CurrentFrame = double(c.Frame);
state.CurrentServingIdx(item.UE) = double(c.ServingCell);
assert(sixgr.truth.CoupledRadioIdentity.resolve(state,item.UE,c.ServingCell) == grant.RNTI, ...
    'sixgr:test:ULPreparation:MetadataIdentityMismatch', ...
    'The initialized metadata identity must match the original admitted command.');

[originalContext, originalRow] = localContext(state,cfg,item.UE,grant);
assert(~isfield(originalContext.GrantSnapshot,'NumLogicalPorts') && ...
    isnan(originalRow.NumLogicalPorts), ...
    'sixgr:test:ULPreparation:InventedExecutableAlias', ...
    'Only the reporting row may use unavailable NaN; the request stays absent.');
[finalized,bits] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext( ...
    cfg,'UL',originalContext);
localUnchangedAuthority(finalized,grant,originalPHY,bits);
assert(~isfield(finalized.GrantSnapshot,'NumLogicalPorts'), ...
    'sixgr:test:ULPreparation:InventedExecutableAlias', ...
    'Canonical hydration must not manufacture an optional request operand.');

positiveValues = {ports,[]};
% Explicit [] is covered only at this preparation boundary; downstream
% completion/reporting is deliberately outside this no-waveform regression.
for k = 1:numel(positiveValues)
    request = grant;
    request.NumLogicalPorts = positiveValues{k};
    [context,~] = localContext(state,cfg,item.UE,request);
    assert(isequaln(context.GrantSnapshot.NumLogicalPorts,request.NumLogicalPorts));
    [again,bits] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfg,'UL',context);
    localUnchangedAuthority(again,grant,originalPHY,bits);
end

% Every explicit malformed/conflicting operand survives the normalization
% boundary verbatim and is rejected by the existing frozen-grant guard.
% In particular [ports ports] must not be scalarized into a passing value.
invalidValues = {NaN,Inf,0,-1,ports+1,ports+0.25,[ports ports]};
for k = 1:numel(invalidValues)
    request = grant;
    request.NumLogicalPorts = invalidValues{k};
    [context,~] = localContext(state,cfg,item.UE,request);
    assert(isequaln(context.GrantSnapshot.NumLogicalPorts,request.NumLogicalPorts), ...
        'sixgr:test:ULPreparation:MalformedOperandHidden', ...
        'Normalization must not erase, repair, or scalarize an explicit operand.');
    localReject(@() sixgr.truth.GrantPreparation.finalizeGrantTrialContext( ...
        cfg,'UL',context),'sixgr:phy:grant:FrozenULSpatialMismatch');
end
assert(string(sixgr.util.sha256File(sourcePath)) == sourceSHA, ...
    'sixgr:test:ULPreparation:OriginalReceiptChanged', ...
    'The retained original receipt must remain byte-identical.');
evidence = struct('Scope',"original_received_grant_metadata_preparation_replay", ...
    'SourceReceipt',sourcePath,'SourceSHA256',sourceSHA, ...
    'MetadataRuntimeReconstructed',true,'NewWaveformExecuted',false, ...
    'SharedPUSCHQualified',false,'PositiveChecks',3, ...
    'NegativeChecks',numel(invalidValues),'NumLayers',double(grant.NumLayers), ...
    'NumLogicalPorts',ports,'TPMI',double(grant.TPMI), ...
    'PHYGrantContextId',string(originalPHY.GrantContextId), ...
    'ReceivedAssignmentDigest',string(control.ReceivedAssignment.AssignmentDigest));
fprintf('UL_FROZEN_PREPARATION_AUTHORITY_PASS positives=%d negatives=%d rank=%d ports=%d TPMI=%d new_waveform=0\n', ...
    evidence.PositiveChecks,evidence.NegativeChecks,evidence.NumLayers,ports,evidence.TPMI);
ok = true;
end

function [context,row] = localContext(state,cfg,ue,grant)
[~,context,row] = sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant( ...
    state,cfg,ue,'UL',grant);
assert(isequaln(context.GrantSnapshot.PHYGrant,grant.PHYGrant), ...
    'sixgr:test:ULPreparation:FrozenAuthorityChanged', ...
    'The public context adapter must retain the complete original frozen authority.');
localOriginalOnly(context.GrantSnapshot,grant,'AcceptedSRSSpatialDecision');
if isfield(context,'ChannelState')
    assert(context.ChannelState.CurrentSampleIndex == 0, ...
        'sixgr:test:ULPreparation:UnexpectedChannelExecution', ...
        'Metadata-only preparation must not advance physical samples.');
end
end

function localUnchangedAuthority(context,original,phy,bits)
assert(isequaln(context.PHYGrant,phy) && ...
    isequaln(context.GrantSnapshot.PHYGrant,phy) && ...
    isequaln(context.GrantSnapshot.PRBSet,original.PRBSet) && ...
    isequaln(context.GrantSnapshot.SymbolAllocation,original.SymbolAllocation) && ...
    bits == original.TBSBits && numel(context.TransportBlockBits) == bits, ...
    'sixgr:test:ULPreparation:FrozenAuthorityChanged', ...
    'Finalization must retain the complete frozen PHY/SRS/DCI/resource/TBS contract.');
for name = ["AcceptedSRSSpatialDecision","AcceptedSRSDecisionContext","DCI"]
    localOriginalOnly(context.GrantSnapshot,original,char(name));
end
fields = sixgr.truth.receivedPDCCHGrantEvidenceFields();
for k = 1:numel(fields)
    name = fields{k};
    if ~isfield(original,name), continue; end
    expected = original.(name);
    actual = context.GrantSnapshot.(name);
    % The normalizer already canonicalizes textual aliases to char. Check
    % their exact content; all nontext receiver evidence stays type-exact.
    if ischar(expected) || isstring(expected)
        same = isequaln(string(actual),string(expected));
    else
        same = isequaln(actual,expected);
    end
    assert(same,'sixgr:test:ULPreparation:ReceivedControlChanged', ...
        'Preparation must not replace original received control evidence %s.',name);
end
end

function localOriginalOnly(actual,original,name)
if isfield(original,name)
    same = isfield(actual,name) && isequaln(actual.(name),original.(name));
else
    same = ~isfield(actual,name);
end
assert(same,'sixgr:test:ULPreparation:FrozenAuthorityChanged', ...
    'Preparation must preserve original %s and must not create absent authority.',name);
end

function [ok,evidence] = localDeclaredComponent()
% The resolved fixture supplies complete configuration/runtime schema only.
% This lower-PHY component explicitly does not install accepted sounding or
% decoded control. As in testPUSCHFrozenCodebookAuthority, non-strict MIMO
% permits a declared native codebook request; it is not connected admission.
previousRNG = rng;
rngCleanup = onCleanup(@() rng(previousRNG)); %#ok<NASGU>
work = tempname;
mkdir(work);
workCleanup = onCleanup(@() rmdir(work,'s')); %#ok<NASGU>
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_tdd_four_port_received_rank_transition_fixture.yaml'));
cfg = sixgr.lls6g.buildInternalConfig(scenario,work);
cfg.mimo.strict = false;
cfg.phy.mimo.strict = false;
cfg.run.strictMode = false;
cfg.phy.pusch.numLayers = 4;
cfg.phy.pusch.nLayers = 4;
cfg.phy.pusch.TPMI = 4;
cfg.phy.pusch.PMI = 4;
mcs = sixgr.phy.ul.pusch.PUSCHMCSResolver.resolve('qam64',4,false);
cfg.phy.pusch.mcsTable = char(mcs.MCSTable);
cfg.phy.pusch.mcsIndex = mcs.MCSIndex;
cfg.phy.pusch.modulation = char(mcs.Modulation);
cfg.phy.pusch.codeRate = mcs.TargetCodeRate;
cfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,20,2);
multi = sixgr.truth.resolveMultiUserSpec(cfg);
grant = struct('Direction','UL','UEIndex',1,'RNTI',double(cfg.phy.pusch.RNTI), ...
    'ServingCell',1,'Frame',2,'Slot',20,'PRBSet',0:5, ...
    'SymbolAllocation',double(cfg.phy.pusch.symbolAllocation), ...
    'NumLayers',4,'Layers',4,'RI',4,'RIUsed',4, ...
    'Modulation',char(mcs.Modulation),'TargetCodeRate',mcs.TargetCodeRate, ...
    'MCSIndex',mcs.MCSIndex,'MCS',mcs.MCSIndex,'MCSTable',mcs.MCSTable, ...
    'TransmissionScheme','codebook','TPMI',4,'PMI',4, ...
    'TransformPrecoding',false,'GrantContextId','declared_UL_preparation_ports_4', ...
    'HARQ',struct('HarqID',0,'HARQProcess',0,'NDI',true,'RV',0,'IsRetransmission',false));
% The exact allocation/TBS inputs come from the same native hydrator used by
% production, not authored transport-block sizes or faux scheduling rows.
grant = sixgr.truth.GrantPreparation.hydrateGrantSnapshot(cfg,'UL',grant);
phy = sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant,'Frame',2,'Slot',20);
grant.PHYGrant = phy;
grant.PHYGrantContextId = char(string(phy.GrantContextId));
assert(phy.AntennaArchitecture.NumLogicalPorts == 4 && ...
    phy.AntennaArchitecture.NumElements == 4 && ...
    phy.AntennaArchitecture.NumLayers == 4 && ...
    ~isfield(grant,'NumLogicalPorts') && ~isfield(grant,'AcceptedSRSSpatialDecision') && ...
    ~isfield(grant,'DCI'),'sixgr:test:ULPreparation:DeclaredScope', ...
    'The declared component requires real four-port native geometry, without received authority.');
state = sixgr.truth.CoupledTruthRuntime.initialize(cfg,work,multi,struct(),20);
state.CurrentSlot = 19;
state.CurrentCanonicalSlot = 19;
state.CurrentFrame = 2;
state.CurrentServingIdx(1) = 1;
[context,row] = localContext(state,cfg,1,grant);
assert(~isfield(context.GrantSnapshot,'NumLogicalPorts') && isnan(row.NumLogicalPorts));
[finalized,bits] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfg,'UL',context);
localUnchangedAuthority(finalized,grant,phy,bits);
assert(~isfield(finalized.GrantSnapshot,'NumLogicalPorts'));
for value = {4,[]}
    request = grant;
    request.NumLogicalPorts = value{1};
    [context,~] = localContext(state,cfg,1,request);
    assert(isequaln(context.GrantSnapshot.NumLogicalPorts,value{1}));
    [finalized,bits] = sixgr.truth.GrantPreparation.finalizeGrantTrialContext(cfg,'UL',context);
    localUnchangedAuthority(finalized,grant,phy,bits);
end
invalidValues = {NaN,Inf,0,-1,5,4.25,[4 4]};
for k = 1:numel(invalidValues)
    request = grant;
    request.NumLogicalPorts = invalidValues{k};
    [context,~] = localContext(state,cfg,1,request);
    assert(isequaln(context.GrantSnapshot.NumLogicalPorts,invalidValues{k}));
    localReject(@() sixgr.truth.GrantPreparation.finalizeGrantTrialContext( ...
        cfg,'UL',context),'sixgr:phy:grant:FrozenULSpatialMismatch');
end
evidence = struct('Scope',"declared_native_grant_metadata_component", ...
    'NewWaveformExecuted',false,'ReceivedSRSEvidence',false, ...
    'ReceivedDCIEvidence',false,'SharedPUSCHQualified',false, ...
    'PositiveChecks',3,'NegativeChecks',numel(invalidValues), ...
    'NumLayers',4,'NumLogicalPorts',4,'TPMI',4);
fprintf('UL_FROZEN_PREPARATION_COMPONENT_PASS positives=3 negatives=%d rank=4 ports=4 TPMI=4 received_authority=0 new_waveform=0\n',numel(invalidValues));
ok = true;
end

function localReject(operation,expected)
try
    operation();
catch cause
    assert(string(cause.identifier) == string(expected), ...
        'sixgr:test:ULPreparation:WrongRejection', ...
        'Expected %s, got %s: %s',char(expected),cause.identifier,cause.message);
    return;
end
error('sixgr:test:ULPreparation:MissingRejection', ...
    'The existing frozen-grant guard must reject %s.',char(expected));
end
