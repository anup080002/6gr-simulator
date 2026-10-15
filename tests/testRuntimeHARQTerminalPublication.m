function ok=testRuntimeHARQTerminalPublication()
% Executed MAC lifecycle plus labelled RX fixtures, not physical UCI tests.
root=tempname; mkdir(root);
cfg.phy.carrier.SubcarrierSpacing_kHz=30;
h=sixgr.l2.mac.HARQEntity(struct(),'Direction','DL','NumProcesses',1,'MaxRetx',0);
for k=1:3
    slot=2*k-1;
    h.allocate(321,slot,100,'NewData',true);
    h.onTx(321,0,uint8(mod((1:800)',2)),localGrant(k),slot);
    if k==1
        assert(h.onFeedback(321,0,"ACK",'SourceSlot',slot,'FeedbackSlot',slot+1));
    elseif k==2
        assert(h.onFeedback(321,0,"NACK",'SourceSlot',slot,'FeedbackSlot',slot+1));
    end
end
L=h.getTransmitterLifecycle(); L.SweepPointIndex=ones(height(L),1);
T=table(repmat("DL",3,1),ones(3,1),repmat(321,3,1),zeros(3,1), ...
    [1;3;5],ones(3,1),repmat(40,3,1),string(L.TBId),string(L.PHYGrantContextId), ...
    [0;1;0],[0;1;0],false(3,1), ...
    'VariableNames',{'Direction','UEIndex','RNTI','HarqID','Slot', ...
    'SweepPointIndex','ConfiguredSNR_dB','TBId','PHYGrantContextId', ...
    'CurrentDecodeOK','CombinedDecodeOK','IsRetransmission'});
runtime=struct('TimelineTable',T,'TransmitterLifecycleTable',L);
out=sixgr.truth.publishRuntimeHARQDiagnostics(cfg,fullfile(root,'air_interface'),runtime);
P=out.PacketTable;
assert(all(P.TransmitterLifecycleBound) && all(P.HARQPacketReceiverPopulationComplete));
assert(isequal(P.TransmitterTerminal,[true;true;false]));
assert(all(isnan(P.ACK)) && isequal(P.CombinedDecodeOK,[0;1;0]), ...
    'Transmitter lifecycle feedback cannot fabricate received UCI or overwrite CRC.');
S=sixgr.truth.summarizeHARQResidualBLER(P);
assert(height(S)==1 && S.ObservedPackets==3 && S.TerminalPackets==2 && ...
    S.QualifiedPackets==2 && S.ResidualErrors==1 && S.UnresolvedPackets==1 && isnan(S.ResidualBLER));
assert(S.InitialTrials==3 && S.InitialErrors==2 && abs(S.InitialBLER-2/3)<eps);
closed=sixgr.truth.summarizeHARQResidualBLER(P(1:2,:));
assert(closed.ResidualBLER==.5, ...
    'False ACK loses one TB; false NACK does not undo an already delivered TB.');
missing=T(1,:); missing.CombinedDecodeOK=NaN; missing.CurrentDecodeOK=NaN;
out=sixgr.truth.publishRuntimeHARQDiagnostics(cfg,fullfile(root,'missing','air_interface'), ...
    struct('TimelineTable',missing,'TransmitterLifecycleTable',L(1,:)));
assert(isnan(out.PacketTable.CombinedDecodeOK) && ~out.PacketTable.HARQPacketReceiverPopulationComplete);
assert(isnan(sixgr.truth.summarizeHARQResidualBLER(out.PacketTable).ResidualBLER));
wrong=L; wrong.RNTI(:)=999;
out=sixgr.truth.publishRuntimeHARQDiagnostics(cfg,fullfile(root,'wrong_owner','air_interface'), ...
    struct('TimelineTable',T,'TransmitterLifecycleTable',wrong));
assert(~any(out.PacketTable.TransmitterLifecycleBound));
failed=false;
try
    sixgr.truth.bindRuntimeHARQTerminalEvidence(P,[L;L(1,:)]);
catch ME
    failed=strcmp(ME.identifier,'sixgr:truth:AmbiguousHARQTerminalAttempt');
end
assert(failed,'An ambiguous terminal join must fail, not choose the first row.');

% Same TB labels across UEs or independent points cannot merge histories.
other=T(1,:); other.RNTI=999; other.UEIndex=2;
later=T(1,:); later.SweepPointIndex=2;
out=sixgr.truth.publishRuntimeHARQDiagnostics(cfg,fullfile(root,'identity','air_interface'), ...
    struct('TimelineTable',[T(1,:);other;later]));
assert(isequal(out.PacketTable.PacketID,[1;2;3]) && all(out.PacketTable.Attempt==1));

% Probe PacketID restarts at each SNR. The report must not pool or splice it.
probe=table(repmat("DL",3,1),repmat("closed_loop",3,1),ones(3,1),[1;2;1], ...
    [0;1;0],["pending";"crc_pass";"max_retx_drop"],[0;0;-10], ...
    'VariableNames',{'Direction','ProbeMode','PacketID','Attempt','CombinedDecodeOK','StopCondition','SNR_dB'});
S=sixgr.truth.summarizeHARQResidualBLER(probe);
assert(height(S)==2 && isequal(S.ConfiguredSNR_dB,[0;-10]) && isequal(S.ResidualBLER,[0;1]));
pending=probe(3,:); pending.StopCondition="pending";
assert(isnan(sixgr.truth.summarizeHARQResidualBLER(pending).ResidualBLER));
left=P(1,:); left.IsRetransmission=true;
S=sixgr.truth.summarizeHARQResidualBLER(left);
assert(S.LeftCensoredPackets==1 && isnan(S.ResidualBLER) && S.InitialTrials==0 && isnan(S.InitialBLER));

% Exercise the final report writer with explicitly labelled table fixtures.
% This launches no PHY scenario and cannot qualify channel performance.
main=fileparts(which('setup6GRSimToolkit'));
scfg=sixgr.lls6g.config.loadScenarioConfig(fullfile(main,'simulator','configs', ...
    'scenarios','h4_100_cdlc100_connected_impaired_40db_short.yaml'));
reportRoot=fullfile(root,'report_fixture');
reportCfg=sixgr.lls6g.buildInternalConfig(scfg,reportRoot);
reportCfg.outputs.saveFigures=false; reportCfg.outputs.savePNG=false;
probeRows=P([1;1;1],:);
probeRows.ProbeMode(:)="closed_loop"; probeRows.SweepPointIndex(:)=NaN;
probeRows.SNR_dB=[0;0;-10]; probeRows.ConfiguredSNR_dB=[0;0;-10];
probeRows.Attempt=[1;2;1]; probeRows.IsRetransmission=[false;true;false];
probeRows.CombinedDecodeOK=[0;1;0]; probeRows.CurrentDecodeOK=[0;1;0];
probeRows.StopCondition=["pending";"crc_pass";"max_retx_drop"];
sixgr.util.csvWriteTable(fullfile(reportRoot,'harq','csv','harq_process_timeline.csv'), ...
    [P;probeRows],'PreserveSchema',true);
manifest=struct('CodeVersion','fixture','CodeDetail','HARQ reporting fixture', ...
    'RandomSeed',1,'GeneratedUTC','fixture','RunnerProfile','fixture', ...
    'RunCompletion','failed','DeterministicMode','fixture');
report=sixgr.truth.exportLLSReportingBundle(reportRoot,scfg,reportCfg, ...
    struct('Ok',false),manifest,struct('StartedUTC','fixture','ElapsedSeconds',0), ...
    struct('RunCompletion','failed','ResultOk',false));
rates=report.CategoryRows(report.CategoryRows.MetricKey=="residual_bler" & ...
    report.CategoryRows.Statistic=="final_harq_tb_error_rate",:);
assert(height(rates)==3 && ~any(ismissing(rates.Entity)));
runtimeRate=rates(contains(rates.Entity,"canonical_slot_runtime_truth"),:);
assert(height(runtimeRate)==1 && isnan(runtimeRate.ValueNumeric) && ...
    ~runtimeRate.CountsTowardCoverage,'An incomplete cohort must not publish a passing residual BLER.');
assert(rates.ValueNumeric(contains(rates.Entity,"@configured_snr_dB=0"))==0);
assert(rates.ValueNumeric(contains(rates.Entity,"@configured_snr_dB=-10"))==1);
fprintf('RUNTIME_HARQ_TERMINAL_PUBLICATION_PASS fixtures=%s\n',root);
ok=true;
end

function g=localGrant(k)
layout=sixgr.phy.phycode.resolveCodingLayout('Direction','DL', ...
    'TransportBlockSize',800,'TargetCodeRate',.3,'RV',0,'Modulation','QPSK', ...
    'NumLayers',1,'RateMatchedBitCount',2748);
g=struct('TBSBits',800,'Direction','DL','Modulation','QPSK', ...
    'NumLayers',1,'TargetCodeRate',.3,'CodingLayout',layout, ...
    'TransportBlockId',"fixture-dl-tb-"+k,'PHYGrantContextId',"fixture-grant-"+k);
end
