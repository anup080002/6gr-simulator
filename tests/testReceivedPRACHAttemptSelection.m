function ok=testReceivedPRACHAttemptSelection()
% Actual native RO/Msg1 geometry and RAConfig integration. Delivery receipts
% below are DECLARED boundary inputs, not decoded MIB/SI or runtime authority.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
cfg=raStrictAnchorConfig(); original=sixgr.mac.ra.RAConfig(cfg);
cfg.lls6g.userContext.RuntimeServingCell=1;
n=original.PRACHOccasionResolution; cfg.phy.prach.timing=n;
a=sixgr.mac.ra.resolveSSBPRACHAssociation(n,[0 1 2 3],1,64,64,true(height(n.Occasions),1));
rows=find(a.Mapping.SSBIndex0==2); assert(~isempty(rows));
m=a.Mapping(rows(1),:); nativeRow=n.Occasions(m.SourceOccasionRow,:);
periodIndex=m.ConfigurationPeriodIndex0;
assert(periodIndex>=1,'Fixture must exercise a later native frame, not frame zero.');
row=m;
s=struct('Available',true,'SelectedSSBIndex0',2,'PreambleIndex0',7, ...
    'SelectedSSBReferenceSHA256',string(repmat('a',1,64)),'SIB1TreeSHA256',string(repmat('b',1,64)), ...
    'SelectedNativeOccasion',nativeRow,'SelectedAssociationRow',row, ...
    'NativePeriodIndex0',periodIndex, ...
    'PRACHOccasionOrdinal',periodIndex*height(n.Occasions)+nativeRow.Ordinal);
t=struct('BindingSHA256',s.SelectedSSBReferenceSHA256,'AcquisitionGenerationID',"declared_generation", ...
    'SSBIndex',2,'OriginalBCHBinding',struct('UEIndex',1,'ServingCell',1));
v=struct('SIB1TreeSHA256',s.SIB1TreeSHA256,'NativeResolutionSHA256',evidenceHash(n), ...
    'MIBContextSHA256',string(repmat('c',1,64)),'RepeatedValidity',true(height(n.Occasions),1));
% Declared table-valued evidence exercises the actual producer's recursive
% canonical serialization, including records beyond a preview-sized prefix.
v.DeclaredCandidateEvidence=table((1:257).',repmat("declared_not_received",257,1), ...
    'VariableNames',{'SourceRow','Scope'});
s.ValiditySHA256=evidenceHash(v); s.NativeResolutionSHA256=evidenceHash(n); s.MIBContextSHA256=v.MIBContextSHA256;
origin=nativeRow.PRACHWaveformStartTicks+int64(periodIndex*n.BasePeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame;
spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(struct('SCSKHz',30,'CyclicPrefix',"normal"));
time=sixgr.phy.frame.AbsoluteTime(origin); [~,f,sl]=time.floorToSlot(spec);
prep=double(f)*spec.SlotsPerFrame+double(sl);
cfg.random_access.associated_ssb_index=2; cfg.SharedRATimingBinding=t;
choice=sixgr.mac.ra.resolveCBPreambleOffset(struct( ...
    'cb_preamble_selection_policy','fixed_partition_offset','cb_preamble_offset',7),1,64);
cfg.SharedReceivedPRACHSelection=seal(struct('ContractVersion',"received_prach_attempt/v1", ...
    'UEIndex',1,'ServingCell',1,'AcquisitionGenerationID',t.AcquisitionGenerationID, ...
    'SelectedSSBTimingBindingSHA256',t.BindingSHA256,'SIB1TreeSHA256',s.SIB1TreeSHA256, ...
    'PreparationSlot',prep,'NativeResolution',n,'Validity',v,'Selection',s,'CBPreambleChoice',choice));
before=rng;
[actualNative,actualRow,actualSelection]=sixgr.mac.ra.receivedPRACHAttemptSelection(cfg,prep);
assert(isequaln(actualNative,n) && isequaln(actualRow,nativeRow) && isequaln(actualSelection,s));
ra=sixgr.mac.ra.RAConfig(cfg,'RuntimeSlot',prep);
assert(ra.PRACHAbsoluteSlot==row.AbsoluteSlot && ra.PRACHOccasionOrdinal==s.PRACHOccasionOrdinal && ...
    ra.PRACHOccasionFrame==floor(row.AbsoluteSlot/spec.SlotsPerFrame) && ...
    ra.PRACHOccasionSlot==mod(row.AbsoluteSlot,spec.SlotsPerFrame) && ra.PreambleIndex==7 && ...
    ra.PRACHFrequencyIndex==nativeRow.FrequencyIndex && ra.PRACHOccasionSymbol==nativeRow.StartSymbol);
assert(ra.PRACHActiveEndTicksExclusive==nativeRow.PRACHActiveEndTicksExclusive+ ...
    int64(periodIndex*n.BasePeriodFrames)*sixgr.phy.frame.AbsoluteTime.TicksPerFrame);
% Actual materialization must retain original native reference clock/RA-RNTI,
% not reinterpret occupied carrier slots as NPRACHSlot.
[tx,occasion]=sixgr.phy.ra.generateMsg1PRACHWaveform(cfg,ra);
assert(tx.PRACHOccasionOrdinal==s.PRACHOccasionOrdinal && ...
    occasion.SlotIndex0==ra.PRACHAbsoluteSlot && tx.RARNTI==ra.RARNTI && ...
    size(tx.Waveform,1)>0 && isequal(before,rng));
fcn=@(c,k)sixgr.mac.ra.receivedPRACHAttemptSelection(c,k);
reject(@()fcn(cfg,prep+1),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.SharedRATimingBinding.AcquisitionGenerationID="new_generation";
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.random_access.associated_ssb_index=0;
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.SharedRATimingBinding.OriginalBCHBinding.ServingCell=2;
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.SharedReceivedPRACHSelection.Selection.PreambleIndex0=9;
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.SharedReceivedPRACHSelection.Selection.PreambleIndex0=9;
bad.SharedReceivedPRACHSelection=seal(rmfield(bad.SharedReceivedPRACHSelection,'SHA256'));
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.SharedReceivedPRACHSelection.Validity.DeclaredCandidateEvidence.SourceRow(257)=999;
% Even a newly sealed outer container must not bless altered ORIGINAL
% inner producer evidence. Keep its original selection/validity digest.
bad.SharedReceivedPRACHSelection=seal(rmfield(bad.SharedReceivedPRACHSelection,'SHA256'));
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=cfg; bad.phy.prach.timing.Occasions.Frame(1)=999;
reject(@()fcn(bad,prep),'InvalidReceivedPRACHAttempt');
bad=rmfield(cfg,'SharedReceivedPRACHSelection');
reject(@()sixgr.mac.ra.RAConfig(bad,'RuntimeSlot',prep),'MissingReceivedPRACHAssociation');
% Authored occasion and absolute preamble are not authority after admission.
poison=cfg; poison.random_access.occasion.slot=999; poison.random_access.preamble_index=3;
same=sixgr.mac.ra.RAConfig(poison,'RuntimeSlot',prep);
assert(same.PRACHAbsoluteSlot==ra.PRACHAbsoluteSlot && same.PreambleIndex==ra.PreambleIndex);
fprintf('RECEIVED_PRACH_ATTEMPT_NATIVE_PASS declared_delivery_boundary=1 native_Msg1=1 runtime_delivery=0\n');
ok=true;
end
function r=seal(r)
r.SHA256=hash(r);
end
function h=hash(r)
h=sixgr.rrc.asn1.asn1SHA256Hex(uint8(unicode2native(jsonencode(r),'UTF-8')));
end
function h=evidenceHash(r)
h=sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(r)));
end
function reject(f,suffix)
try, f(); catch e, assert(endsWith(string(e.identifier),suffix),e.message); return; end
error('sixgr:test:ExpectedFailure','Expected %s.',suffix);
end
