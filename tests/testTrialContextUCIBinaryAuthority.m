function ok=testTrialContextUCIBinaryAuthority()
% Exercise the real runtime grant-to-trial boundary, not a codec shortcut.
% These are explicit component grants; no on-air transmission is claimed.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
root=tempname; mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),10);
state.CurrentSlot=5; state.CurrentFrame=1; state.CurrentCanonicalSlot=5;
state.CurrentServingIdx(:)=1;
grant=struct('Direction','UL','UEIndex',1,'RNTI',1,'ServingCell',1, ...
    'Slot',5,'Frame',1,'PRBSet',0:3,'SymbolAllocation',[0 12], ...
    'Modulation','QPSK','TargetCodeRate',.1884765625,'NumLayers',1,'Layers',1, ...
    'TransportBlockSize',256,'TBSBits',256,'TBSBytes',32, ...
    'HARQ',struct('HarqID',0,'HARQProcess',0,'NDI',true,'RV',0));
valid=grant; valid.ExpectedUCIBits=int8([0;1;0]);
[~,context]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(state,cfg,1,'UL',valid);
assert(isequal(context.ExpectedUCIBits,int8([0;1;0])));
assert(isequal(context.HARQContext.ExpectedUCIBits,context.ExpectedUCIBits));

aliases=["ExpectedUCIBits","MultiplexedUCIBits","HARQACKBits","MultiplexedHARQACKBits"];
for name=aliases
    for value={.2,2,-1,NaN,Inf,1+1i,{0,1},[0 1;1 0],"012",["0","1"]}
        bad=grant; bad.(name)=value{1};
        reject(@()sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant( ...
            state,cfg,1,'UL',bad),'sixgr:truth:InvalidGrantUCIBits');
    end
end
for value={int8([0;1;0]),[0 1 0],logical([0 1 0]),'010',"010"}
    consistent=grant;
    for name=aliases, consistent.(name)=value{1}; end
    [~,context]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(state,cfg,1,'UL',consistent);
    assert(isequal(context.ExpectedUCIBits,int8([0;1;0])));
end
conflict=valid; conflict.MultiplexedHARQACKBits=int8([1;1;0]);
reject(@()sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant( ...
    state,cfg,1,'UL',conflict),'sixgr:truth:ConflictingGrantUCIBits');
typed=grant; typed.ExpectedUCIPayload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',[0;1;0]);
[~,context]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(state,cfg,1,'UL',typed);
assert(isequal(context.ExpectedUCIBits,int8([0;1;0])));
typed.ExpectedUCIBits=int8([1;0;1]);
reject(@()sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant( ...
    state,cfg,1,'UL',typed),'sixgr:truth:ConflictingGrantUCIBits');
csiOnly=grant; csiOnly.ExpectedUCIPayload=sixgr.phy.ul.pusch.PUSCHUCIPayload('CSIPart1',[1;0]);
[~,context]=sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant(state,cfg,1,'UL',csiOnly);
assert(isempty(context.ExpectedUCIBits),'CSI bits must never become the HARQ-ACK alias.');
csiOnly.ExpectedUCIBits=int8(1);
reject(@()sixgr.truth.CoupledTruthRuntime.buildTrialContextFromGrant( ...
    state,cfg,1,'UL',csiOnly),'sixgr:truth:ConflictingGrantUCIBits');
ok=true; disp('TRIAL_CONTEXT_UCI_BINARY_AUTHORITY_PASS');
end
function reject(fn,id)
before=rng;
try, fn(); catch ex
    assert(string(ex.identifier)==string(id),ex.message);
    assert(isequal(rng,before),'Rejected UCI must not consume payload/channel randomness.');
    return;
end
error('test:MissingUCIRejection','Malformed or conflicting UCI reached the runtime trial context.');
end
