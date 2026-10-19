function ok=testSlotSymbolRoleEvidence()
setup6GRSimToolkit('Verbose',false);
pattern=struct('PeriodicityMilliseconds',2.5,'NumDownlinkSlots',3, ...
    'NumDownlinkSymbols',10,'NumUplinkSlots',1,'NumUplinkSymbols',2);
state=sixgr.phy.frame.SlotFormatResolver.resolve( ...
    'ReferenceSubcarrierSpacingKHz',30,'ActiveSubcarrierSpacingKHz',30, ...
    'CyclicPrefix','normal','Pattern1',pattern,'Pattern2',struct(), ...
    'DedicatedOverrides',struct([]));
p=sixgr.phy.FrameStructureEngine.SlotPartitionFromState(state,3);
e=sixgr.truth.summarizeSlotSymbolRoles(p);
roles=string(jsondecode(e.SymbolRolesJSON));
assert(e.ClassifiedNumSymbols==14 && e.FlexibleNumSymbols==2 && ...
    e.ExplicitGuardNumSymbols==0 && nnz(roles=="DL")==10 && nnz(roles=="UL")==2);
assert(all(roles(11:12)=="FLEXIBLE"), ...
    'Unresolved common symbols must not silently become guard or schedulable UL.');
p.ResolvedDirection(11:12)="GUARD";
e=sixgr.truth.summarizeSlotSymbolRoles(p);
assert(e.ExplicitGuardNumSymbols==2 && e.FlexibleNumSymbols==0);
p.ResolvedDirection(11:12)=["UNUSED","RESERVED"];
e=sixgr.truth.summarizeSlotSymbolRoles(p);
assert(e.UnusedNumSymbols==1 && e.ReservedNumSymbols==1);
p.ResolvedDirection(11)="mystery";
try
    sixgr.truth.summarizeSlotSymbolRoles(p);
    error('test:MissingRejection','Unknown symbol role was accepted.');
catch err
    assert(strcmp(err.identifier,'sixgr:truth:UnknownSlotRole'));
end
ok=true;
end
