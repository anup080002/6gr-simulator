function [grant,next]=prepareScheduledDLDAI(ledger,cfg,grant)
% Finalize ordinary connected DL DAI before physical PDCCH preparation.
% Return a candidate ledger; caller commits it only on accepted TX enqueue
% or actual control execution, independent of whether the UE decodes DCI.
next=ledger;
policy=sixgr.util.structGet(cfg,'phy.pdcch.operatorControl.connected_dci',struct());
if upper(string(grant.Direction))~="DL" || isempty(fieldnames(policy)), return; end
sixgr.phy.pdcch.ConnectedDCIProfile.validatePolicy(policy);
sixgr.phy.grant.assertGrantTimingIdentity(grant,'DL');
t=grant.TimingDecision;
assert(isequal(t.Valid,true) && isequal(t.HARQACKRequired,true) && ...
    isequal(t.HARQACKDecision.Valid,true) && ...
    sixgr.phy.pdcch.normalizeDCIFormat(grant.DCI.Format)=="1_1", ...
    'sixgr:truth:UnsupportedScheduledDAIPolicy', ...
    'Connected DL Type-2 DAI requires a valid ordinary DCI 1_1 HARQ feedback timing.');
assert(isscalar(grant.PHYGrant.CodingLayout.TBSBits) && grant.PHYGrant.CodingLayout.TBSBits>0 && ...
    grant.PHYGrant.CodingLayout.NumCodewords==1 && ...
    grant.NumLayers<=4 && grant.NumLayers>=1, ...
    'sixgr:truth:UnsupportedScheduledDAIPolicy','This connected DAI path requires one real transport block.');
context=sixgr.phy.pdcch.DCIContext(grant.DCI.ContextData);
assert(context.Data.ConfigurationEpoch==policy.configuration_epoch && ...
    context.Data.RNTIValue==grant.RNTI && context.Data.DAIWidth==2 && ...
    string(context.Data.ExecutionProfile)=="configured_connected_dci_r18", ...
    'sixgr:truth:ScheduledDAIContextMismatch','Packed DCI must match the installed two-bit connected context.');
assignment=struct('GrantID',string(grant.PHYGrant.GrantContextId), ...
    'RNTI',grant.RNTI,'PhysicalServingCell',grant.ServingCell, ...
    'ScheduledCCID',string(t.ScheduledCCID),'FeedbackAbsoluteSlot',double(t.FeedbackAbsoluteSlot), ...
    'ControlAbsoluteSlot',double(t.ControlAbsoluteSlot), ...
    'ControlStartSymbol',double(t.ControlSymbolAllocation(1)), ...
    'ConfigurationEpoch',double(policy.configuration_epoch));
[next,entry]=sixgr.truth.nextScheduledType2DAI(ledger,assignment);
old=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,'1_1',context);
% Parser Fields also includes derived semantics. Repack only schema fields.
fields=struct();
for definition=old.Schema.Definitions(:).'
    name=char(definition.Name); fields.(name)=old.Fields.(name);
end
fields.dai=entry.RawDAI;
packed=sixgr.phy.pdcch.encodeDCIPayload(fields,'1_1',context);
grant.DAI=entry.RawDAI; % Existing grant/DCI field representation is on-wire.
grant.DAIOrdinal=entry.Ordinal;
grant.DAICounterValue=entry.CounterDAI;
grant.DAISource=entry.Source;
grant.DAIAssignmentDigest=entry.AssignmentDigest;
grant.DCI.Bits=uint8(packed.Bits(:));
grant.DCI.Hex=char(packed.PayloadHex);
grant.DCI.PayloadHex=char(packed.PayloadHex);
grant.DCI.PayloadHash=char(packed.PayloadHash);
grant.DCI.FieldTable=packed.FieldTable;
grant.DCI.FieldValues.dai=entry.RawDAI;
grant.DCI.FieldValues.DAI=entry.RawDAI;
end
