function ok=testConnectedReceiverReplayCapture()
% Exact connected RX invocation, including pre-decode UE-owned soft state.
% Isolated received-control cases, not whole-scenario/control qualification.
setup6GRSimToolkit('Verbose',false);
originalRNG=rng; cleanup=onCleanup(@()rng(originalRNG)); %#ok<NASGU>
root=fullfile(pwd,'results','lls','connected_receiver_replay', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_received_ul_shared_queue_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.rootRunFolder=root;
cfg.outputs.receiverReplayCapturePolicy='all';
cfg.outputs.receiverReplayCaptureMaxTrials=1;
rng(790113,'twister');
[captured,~,a]=receivedDLFeedbackFixture(cfg,3,0,1e-13);
T=captured.TrialTable;
assert(height(T)==1 && ~T.Crash && T.CRCPass && ...
    T.ReceiverReplayCaptureStatus=="captured_exact_receiver_input");
c=localLoad(root,T.ReceiverReplayMATFile,T.ReceiverReplayMATSHA256);
state=localArg(c.ReceiverArguments,'ReceiverHARQState');
assert(isa(state,'sixgr.link.ReceivedDLHARQState') && all(cellfun(@isempty,state.Processes)));
assert(localArg(c.ReceiverArguments,'ExecutionProfile')=="connected_strict");
received=localArg(c.ReceiverArguments,'ReceivedAssignment');
assert(received.AssignmentDigest==a.AssignmentDigest);
assert(~c.Context.ScoringReferenceReceiverInput && ...
    ~isfield(c.Context,'ScoringOnlyDesiredWaveform') && ...
    c.Context.ScoringOnlyDesiredWaveformSource=="separate_shared_link_scoring_artifact_not_part_of_receiver_invocation");
assert(~any(ismember(string(c.ReceiverArguments(1:2:end)), ...
    ["TransportBlockBits","TransportBlockSize","PHYGrant","SchedulerGrantContext","NoiseVar"])));
localReplay(c);
off=cfg; off.outputs.receiverReplayCapturePolicy='none';
rng(790113,'twister'); baseline=receivedDLFeedbackFixture(off,3,0,1e-13);
for name=["CRCPass","BitErrors","BitsCompared","TBSize_bits","GoodBits","EVM_rms"]
    assert(isequaln(T.(name),baseline.TrialTable.(name)), ...
        'sixgr:test:CaptureChangedReception','Capture changed actual connected %s.',name);
end
assert(isequaln(captured.ReceivedHARQState,baseline.ReceivedHARQState) && ...
    isequaln(captured.ReceivedHARQDecision,baseline.ReceivedHARQDecision));
% Retained physical first-attempt NACK, combined retransmission ACK,
% protocol-only repeated ACK, and a new-NDI decode. No channel rerun.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/fixtures/received_dl_harq_calendar_20260913.yaml');
installed=sixgr.lls6g.buildInternalConfig(s,root);
installed.run.rootRunFolder=fullfile(root,'retained_harq'); mkdir(installed.run.rootRunFolder);
installed.outputs.receiverReplayCapturePolicy='all';
installed.outputs.receiverReplayCaptureMaxTrials=3;
source=fullfile('docs','lls','evidence_20260913','received_dl_harq_calendar_03');
for k=1:4
    saved=load(fullfile(source,sprintf('attempt_%d.mat',k)));
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(installed,saved.a.ControlAbsoluteSlot+1);
    before=saved.before; originalState=before;
    [rx,decision,after,protocol,args]=before.receive(cfg,saved.a,saved.delayed, ...
        'TimingSearchWindowSamples',[0 60]);
    assert(isequaln(before,originalState),'The diagnostic must preserve the prior UE entity.');
    assert(decision.ACK==saved.decision.ACK && decision.DecodeAttempted==saved.decision.DecodeAttempted);
    if k==3
        assert(isempty(rx) && isempty(args) && protocol.ACK && ...
            ~decision.DeliverTransportBlock,'A protocol-only ACK must not invent an RX invocation.');
        continue;
    end
    assert(isequaln(localArg(args,'ReceiverHARQState'),originalState));
    if k==2
        assert(~isempty(before.Processes{3}.SoftBuffer) && ~before.Processes{3}.Decoded && ...
            rx.Decode.HARQCombineInfo.Applied && ~rx.Decode.HARQCombineInfo.ResetPrior);
        assert(after.Processes{3}.Decoded && isequal(rx.TransportBlock,saved.bits));
    end
    e=sixgr.link.captureReceiverReplay(cfg,'DL',saved.delayed,args,rx, ...
        struct('RetainedSource',string(fullfile(source,sprintf('attempt_%d.mat',k)))));
    c=localLoad(cfg.run.rootRunFolder,e.MATFile,e.SHA256);
    assert(isequaln(localArg(c.ReceiverArguments,'ReceiverHARQState'),originalState));
    localReplay(c);
    % A post-decode state is not a substitute for pre-reception soft state.
    invalid=c.ReceiverArguments;
    idx=find(string(invalid(1:2:end))=="ReceiverHARQState"); invalid{2*idx}=after;
    rejected=false;
    try, feval(c.ReceiverFunction,c.Waveform,c.Config,invalid{:});
    catch cause, rejected=strcmp(cause.identifier,'sixgr:link:ReceivedDLHARQNoncausalAssignment'); end
    assert(rejected,'Post-reception state must remain rejected during replay.');
end
assert(numel(dir(fullfile(installed.run.rootRunFolder,'air_interface','mat','receiver_replay','dl','capture_*.mat')))==3);
fprintf('CONNECTED_RECEIVER_REPLAY_PASS actual_runner=1 retained_soft_combining=1 no_phantom_decode=1 root=%s\n',root);
ok=true;
end

function c=localLoad(root,path,sha)
path=fullfile(root,path);
assert(string(sixgr.util.sha256File(path))==string(sha));
v=load(path,'ReceiverReplay'); c=v.ReceiverReplay;
assert(c.WaveformSHA256==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(c.Waveform)));
assert(~c.CaptureUsedByReceiver && c.AdditionalChannelExecutions==0);
end

function localReplay(c)
again=feval(c.ReceiverFunction,c.Waveform,c.Config,c.ReceiverArguments{:});
for name=["TransportBlock","TBCRCPass","EstimatedCFO_Hz", ...
        "AppliedTimingCorrection_samples","DescrambledLLR"]
    assert(isequaln(again.(name),c.ReceiverResult.(name)), ...
        'sixgr:test:ConnectedReplayMismatch','Exact connected replay changed %s.',name);
end
assert(isequaln(again.Decode.SoftBuffer,c.ReceiverResult.Decode.SoftBuffer));
end

function value=localArg(args,name)
idx=find(string(args(1:2:end))==string(name)); assert(isscalar(idx));
value=args{2*idx};
end
