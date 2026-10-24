function ok=testPHYDiagnosticClockContract()
% Declared metadata/native-object fixtures only; no waveform execution,
% standards qualification or integration with existing consumers claimed.
setup6GRSimToolkit('Verbose',false);
groups=0;
T=fixture("DL","capture_a",0,0,30,0);
original=T; state=sixgr.truth.PHYDiagnosticClockContract.initialize();
before=state;
result=check(T);
assert(result.RadioClockSourceContractConsistent && result.Groups.Status=="consistent");
assert(isequaln(T,original)&&isequaln(state,before));
groups=groups+1;

% Use actual native property access for the input contract, not a struct
% pretending to be nrCarrierConfig. NFrame wraps while absolute epoch does not.
for absolute=[0,20479,20480]
    carrier=nrCarrierConfig('SubcarrierSpacing',30, ...
        'NFrame',mod(floor(absolute/20),1024),'NSlot',mod(absolute,20));
    row=fixture("DL","native_"+absolute,carrier.NFrame,carrier.NSlot, ...
        carrier.SubcarrierSpacing,absolute);
    row.Frame=777; % independent trial ordinal, deliberately not radio frame
    result=check(row);
    assert(result.RadioClockSourceContractConsistent && row.Frame==777 && ...
        row.SFN==mod(floor(absolute/20),1024));
end
carrier=nrCarrierConfig('SubcarrierSpacing',15,'NFrame',0,'NSlot',15);
row=fixture("UL","native_non_frame_bounded_slot",carrier.NFrame,carrier.NSlot,15,5);
result=check(row);
assert(result.RadioClockSourceContractConsistent && row.CarrierNSlot==15);
groups=groups+1;

% Multiple snapshots within the SAME direction are legal merged evidence.
% Repeated grid/panel rows are not new physical observations or corruption.
multi=[repmat(T,3,1);repmat(fixture("DL","capture_b",1,2,30,22),2,1); ...
    fixture("UL","capture_a",0,4,30,4)];
result=check(multi);
assert(result.RadioClockSourceContractConsistent && numel(result.Groups)==3 && ...
    result.RepeatedIdentityRows==3 && result.ConflictingIdentityRows==0);
groups=groups+1;

% Legacy wrong-looking values remain untouched, not reconstructed from
% Frame or guessed origin. Known conflicting explicit claims still fail.
legacy=table("DL","legacy",1,6,1,16, ...
    'VariableNames',{'Direction','SnapshotID','Frame','Slot','SFN','AbsoluteSlot'});
copy=legacy; result=check(legacy);
assert(result.Groups.Status=="unavailable" && ...
    ~result.RadioClockSourceContractConsistent && isequaln(legacy,copy));
unknown=T;
for name=["SFN","CarrierNFrame","CarrierNSlot","AbsoluteSlot","RuntimeAbsoluteSlotIndex0"]
    unknown.(name)=NaN;
end
result=check(unknown);
assert(result.Groups.Status=="unavailable" && all(isnan(unknown.SFN)));
partial=T; partial.AbsoluteSlot=NaN; partial.RuntimeAbsoluteSlotIndex0=NaN;
result=check(partial);
assert(result.Groups.Status=="unavailable" && result.Groups.CarrierClockConsistentRows==1);
groups=groups+1;

% Numeric/string CSV imports must mean the same thing, including explicit
% zero and NaN. Strings are parsed strictly; malformed is not unavailable.
stringsT=T;
names=["SFN","CarrierNFrame","CarrierNSlot","SCS_kHz","SlotsPerFrame", ...
    "AbsoluteSlot","RuntimeAbsoluteSlotIndex0","Slot"];
for name=names, stringsT.(name)=string(stringsT.(name)); end
result=check(stringsT); assert(result.RadioClockSourceContractConsistent);
for value=["garbage","Inf","-1","1.25","1+2i","9007199254740993","9007199254740994"]
    bad=stringsT; bad.AbsoluteSlot=value; expect(bad,"invalid");
end
for value={-1,Inf,1.25,1+2i,[0 1],struct('value',0)}
    bad=T; bad.AbsoluteSlot=repmat(value{1},height(T),1); expect(bad,"invalid");
end
bad=T; bad.AbsoluteSlotSource=7; expect(bad,"invalid");
bad=T; bad.SFNSource=["source1" "source2"]; expect(bad,"invalid");
bad=T; bad.AbsoluteSlot=reshape([0 1],[1 1 2]); expect(bad,"invalid");
bad=T; bad.AbsoluteSlot=uint64(9007199254740992)+uint64(1); expect(bad,"invalid");
bad=T; bad.AbsoluteSlotSource="unknown"; expect(bad,"unavailable");
bad=T; bad.AbsoluteSlotSource="legacy"; expect(bad,"unavailable");
row=T; row.AbsoluteSlotSource="bound_runtime_AbsoluteSlotIndex0";
result=check(row); assert(result.RadioClockSourceContractConsistent);
bad=T; bad.Slot=NaN; expect(bad,"unavailable");
groups=groups+1;

% Validate finite contradictions even with other missing fields/provenance.
bad=T; bad.SFN=1; bad.AbsoluteSlotSource=""; expect(bad,"conflict");
bad=T; bad.SFN=1024; expect(bad,"invalid");
bad=T; bad.SlotsPerFrame=10; expect(bad,"conflict");
bad=T; bad.SlotsPerFrame=0; expect(bad,"invalid");
bad=T; bad.SCS_kHz=20; result=check(bad);
assert(result.Groups.Status=="unavailable" && ...
    any(contains(result.Groups.Reasons,"unsupported_NR_clock_numerology")));
bad=T; bad.RuntimeAbsoluteSlotIndex0=1; expect(bad,"conflict");
bad=T; bad.CarrierNSlot=1; expect(bad,"conflict");
bad=T; bad.AbsoluteSlotConvention="one_based_absolute_slot"; expect(bad,"invalid");
bad=T; bad.Slot=0; expect(bad,"invalid");
bad=T; bad.Slot=2; expect(bad,"conflict");
bad=T; bad.SlotConvention="ambiguous"; expect(bad,"invalid");
bad=T; bad.SlotsPerFrame=NaN; bad.CarrierNSlot=1; expect(bad,"conflict");
bad=T; bad.SFN=NaN; bad.AbsoluteSlot=20; bad.RuntimeAbsoluteSlotIndex0=NaN;
bad.Slot=NaN; expect(bad,"conflict");
bad=T; bad.SnapshotID=""; result=check(bad);
assert(result.Groups.Status=="unavailable" && result.MissingSnapshotIDRows==1);
anonymous=[T;fixture("DL","different",1,2,30,22)]; anonymous.SnapshotID(:)="";
result=check(anonymous);
assert(result.Groups.Status=="unavailable" && result.ConflictingIdentityRows==0 && ...
    result.RepeatedIdentityRows==0 && result.MissingSnapshotIDRows==2);
anonymous=[T;fixture("UL","capture_a",1,2,30,22)]; anonymous.Direction(:)="";
result=check(anonymous);
assert(result.Groups.Status=="unavailable" && result.ConflictingIdentityRows==0);
bad=T; bad.Direction="SIDEWAYS"; result=check(bad);
assert(result.Groups.Status=="invalid" && result.InvalidDirectionRows==1);
groups=groups+1;

% Explicit within-frame origins are valid and independently checked.
row=fixture("DL","within_frame",2,6,30,46);
row.Slot=7; row.SlotConvention="one_based_slot_within_frame";
result=check(row); assert(result.RadioClockSourceContractConsistent);
row.Slot=6; row.SlotConvention="zero_based_slot_within_frame";
result=check(row); assert(result.RadioClockSourceContractConsistent);
row.Slot=20; expect(row,"invalid");
row=T; row.Slot=0; row.SlotConvention="zero_based_absolute_slot";
result=check(row); assert(result.RadioClockSourceContractConsistent);
groups=groups+1;

% Last-row corruption exceeds the standard 8192-row import block. All
% chunks are consumed, and retained state contains no per-coefficient rows.
n=9007; many=repmat(T,n,1); many.Notes=repmat("quoted, field"+newline+"same record",n,1);
original=many; state=sixgr.truth.PHYDiagnosticClockContract.initialize();
for first=1:127:n
    state=sixgr.truth.PHYDiagnosticClockContract.observe(state,many(first:min(n,first+126),:));
end
summary=sixgr.truth.PHYDiagnosticClockContract.summarize(state);
assert(summary.RadioClockSourceContractConsistent && summary.RowsChecked==n && ...
    summary.MaxChunkRows<=127 && summary.RepeatedIdentityRows==n-1 && numel(summary.Groups)==1);
assert(isequaln(many,original)); bytes=whos('state');
assert(bytes.bytes<65536,'Clock summary must not retain raw grid rows.');
bad=many; bad.SFN(end)=1;
state=sixgr.truth.PHYDiagnosticClockContract.initialize();
for first=1:127:n
    state=sixgr.truth.PHYDiagnosticClockContract.observe(state,bad(first:min(n,first+126),:));
end
summary=sixgr.truth.PHYDiagnosticClockContract.summarize(state);
assert(summary.Groups.Status=="conflict" && summary.Groups.FirstIssueRow==n && ...
    summary.Groups.ConflictRows==1 && summary.ConflictingIdentityRows==1);
groups=groups+1;

% Carrier/absolute claims cannot disagree between chunks even if each row
% by itself forms a consistent clock tuple (same snapshot, different epoch).
other=fixture("DL","capture_a",1,2,30,22);
summary=check([T;other]); assert(summary.Groups.Status=="conflict");
% Complementary partial claims under one explicit snapshot are still
% contradictory; neither missingness nor chunk boundaries mask the fault.
partialA=T; partialA.AbsoluteSlot=NaN; partialA.RuntimeAbsoluteSlotIndex0=NaN;
partialA.Slot=NaN;
partialB=T; partialB.SFN=NaN; partialB.CarrierNFrame=NaN;
partialB.AbsoluteSlot=20; partialB.RuntimeAbsoluteSlotIndex0=20; partialB.Slot=21;
expect(partialA,"unavailable"); expect(partialB,"unavailable");
summary=check([partialA;partialB]); assert(summary.Groups.Status=="conflict");
state=sixgr.truth.PHYDiagnosticClockContract.initialize();
state=sixgr.truth.PHYDiagnosticClockContract.observe(state,partialA);
state=sixgr.truth.PHYDiagnosticClockContract.observe(state,partialB);
summary=sixgr.truth.PHYDiagnosticClockContract.summarize(state);
assert(summary.Groups.Status=="conflict");
% A bad UL clock must not falsely invalidate an independent DL clock group.
badUL=fixture("UL","bad_ul",0,1,30,1); badUL.SFN=3;
summary=check([T;badUL]);
dl=summary.Groups(string({summary.Groups.Direction})=="DL");
ul=summary.Groups(string({summary.Groups.Direction})=="UL");
assert(dl.Status=="consistent"&&ul.Status=="conflict"&&~summary.RadioClockSourceContractConsistent);
groups=groups+1;

empty=sixgr.truth.PHYDiagnosticClockContract.initialize();
empty=sixgr.truth.PHYDiagnosticClockContract.observe(empty,T([],:));
summary=sixgr.truth.PHYDiagnosticClockContract.summarize(empty);
assert(summary.RowsChecked==0 && ~summary.RadioClockSourceContractConsistent);
fprintf('PHY_DIAGNOSTIC_CLOCK_CONTRACT_PASS groups=%d rows=%d chunk=127 scope=declared_metadata_no_consumer_wiring_no_PHY\n',groups,n);
ok=true;
end

function summary=check(T)
state=sixgr.truth.PHYDiagnosticClockContract.initialize();
state=sixgr.truth.PHYDiagnosticClockContract.observe(state,T);
summary=sixgr.truth.PHYDiagnosticClockContract.summarize(state);
end

function expect(T,status)
before=T; summary=check(T);
assert(summary.Groups.Status==status && ~summary.RadioClockSourceContractConsistent, ...
    'Expected %s, obtained %s.',status,summary.Groups.Status);
assert(isequaln(T,before),'The clock validator changed its input evidence.');
end

function T=fixture(direction,snapshot,nframe,nslot,scs,absolute)
T=table(string(direction),string(snapshot),777,absolute+1,mod(nframe,1024), ...
    nframe,nslot,scs,10*scs/15,absolute,absolute, ...
    "executed_nrCarrierConfig_NFrame_mod1024","one_based_absolute_slot", ...
    "zero_based_absolute_slot","executed_runtime_absolute_slot_index0", ...
    'VariableNames',{'Direction','SnapshotID','Frame','Slot','SFN','CarrierNFrame', ...
    'CarrierNSlot','SCS_kHz','SlotsPerFrame','AbsoluteSlot','RuntimeAbsoluteSlotIndex0', ...
    'SFNSource','SlotConvention','AbsoluteSlotConvention','AbsoluteSlotSource'});
end
