function ok=testLLSUniqueTransportGoodput()
% Declared receiver-outcome fixture, not new waveform/BLER observations.
% Two CRC passes of the same TB after ACK loss must credit payload once.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.numerology.scs_kHz=30;
cfg.phy.numerology.symbolsPerSlot=14;
cfg.phy.numerology.slotDuration_ms=.5;
cfg.run.totalSlots=4;
root=fullfile(pwd,'logs','lls_repairs', ...
    ['unique_transport_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
T=table([1;2],ones(2,1),ones(2,1),ones(2,1),["DL";"DL"], ...
    ["tb-a";"tb-a"],["attempt-1";"attempt-2"], ...
    [2;2],[2;2],[800;800],[800;800],[1;1],[0;1], ...
    'VariableNames',{'Slot','Frame','UEIndex','SweepPointIndex','Direction', ...
    'LogicalTBID','TransmissionAttemptID','SymbolStart','NumSymbols', ...
    'TBSize_bits','GoodBits','CRCPass','IsRetransmission'});
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct('DL',T));
S=out.SymbolThroughput;
bits=sum(S.DLGoodput_Mbps.*S.SymbolDuration_s*1e6,'omitnan');
assert(abs(bits-800)<1e-9,'test:RepeatedTBGoodput', ...
    'Expected 800 unique delivered bits; symbol exporter credited %.17g.',bits);
assert(sum(S.ScheduledDLBits,'omitnan')==1600, ...
    'Both real allocations remain scheduled airtime. Do not erase the retry.');
assert(sum(S.GoodDLBits,'omitnan')==1600 && sum(S.UniqueDeliveredDLTBBits,'omitnan')==800);
% Directions and UEs have independent credit even with the same local label.
U=T; U.Direction(:)="UL";
second=T; second.UEIndex(:)=2;
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'both'),struct('DL',[T;second],'UL',U));
S=out.SymbolThroughput;
assert(sum(S.UniqueDeliveredDLTBBits,'omitnan')==1600 && ...
    sum(S.UniqueDeliveredULTBBits,'omitnan')==800);
missing=removevars(T,'LogicalTBID');
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'missing'),struct('DL',missing));
assert(all(isnan(out.SymbolThroughput.DLGoodput_Mbps)), ...
    'Per-attempt CRC successes without stable TB identity do not prove unique goodput.');
fprintf('UNIQUE_TRANSPORT_GOODPUT_PASS folder=%s declared_outcomes_only=1\n',root);
ok=true;
end
