function ok=testLLSSymbolClockEvidence(retainedRun)
% Numerical export contract; optional read-only replay of retained PHY rows.
setup6GRSimToolkit('Verbose',false);
for scs=[15 30 60 120]
    cpList="normal"; if scs==60, cpList=["normal","extended"]; end
    for cp=cpList
        cfg=configuration(scs,cp);
        [~,spec]=sixgr.time.slotDurationSec(cfg);
        cfg.run.totalSlots=2*spec.SlotsPerFrame;
        clock=sixgr.truth.resolveLLSSymbolClock(cfg,table(),table());
        % Independent toolbox dimensions, not a second call to our clock.
        info=nrOFDMInfo(25,scs,'CyclicPrefix',char(cp),'Nfft',4096,'Windowing',0);
        lengths=repmat(double(info.SymbolLengths(:)),20,1);
        expected=[0;cumsum(lengths(1:end-1))]/info.SampleRate;
        assert(height(clock)==numel(lengths) && ...
            max(abs(clock.SymbolStartTime_s-expected))<1e-13 && ...
            max(abs(clock.SymbolDuration_s-lengths/info.SampleRate))<1e-13 && ...
            abs(sum(clock.SymbolDuration_s)-.020)<1e-13);
        assert(all(clock.SlotIndexBase==0) && all(clock.SymbolTimePlane=="nominal_carrier_grid_CP_OFDM"));
    end
end
cfg=configuration(30,"normal"); cfg.run.totalSlots=3;
row=table(2,1,1,2,2,200,100,"DL", ...
    'VariableNames',{'Slot','Frame','UEIndex','SymbolStart','NumSymbols','TBSize_bits','GoodBits','Direction'});
root=fullfile(pwd,'results','lls','symbol_clock_export_fixture', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,root,struct('DL',row));
S=out.SymbolThroughput;
hit=S.TotalGrantCount>0;
assert(nnz(hit)==2 && all(S.Slot(hit)==1) && ...
    sum(S.ScheduledDLBits(hit))==200 && sum(S.GoodDLBits(hit))==100);
assert(all(isnan(S.TotalGoodput_Mbps(~hit))) && ...
    all(S.ValueStatus(~hit)=="unavailable_no_observed_grant"), ...
    'No observed grant is not evidence of zero throughput, including future symbols.');
assert(all(contains(S.ValueRole(hit),'not_symbolwise_decoding')));
explicit=row; explicit.Slot=1; explicit.SlotIndexBase=0;
[a,aSlots]=sixgr.truth.resolveLLSSymbolClock(cfg,row,table());
[b,bSlots]=sixgr.truth.resolveLLSSymbolClock(cfg,explicit,table());
assert(isequaln(a,b) && isequal(aSlots,bSlots));
bad=row; bad.Slot=0;
reject(@()sixgr.truth.resolveLLSSymbolClock(cfg,bad,table()),'sixgr:truth:InvalidTrialSlotIndex');
bad=row; bad.ScheduledAbsoluteSlot=2;
reject(@()sixgr.truth.resolveLLSSymbolClock(cfg,bad,table()),'sixgr:truth:TrialSymbolClockMismatch');
e=struct('ContractVersion',"received_data_symbol_timing/v1",'Direction',"DL", ...
    'DataAbsoluteSlot',1,'SymbolAllocation',[2 2]);
bound=row; bound.DataReceiveTimingEvidenceJSON=string(jsonencode(e));
[~,slot]=sixgr.truth.resolveLLSSymbolClock(cfg,bound,table()); assert(slot==1);
e.DataAbsoluteSlot=2; bound.DataReceiveTimingEvidenceJSON=string(jsonencode(e));
reject(@()sixgr.truth.resolveLLSSymbolClock(cfg,bound,table()),'sixgr:truth:TrialSymbolClockMismatch');
% Neither offered traffic nor a CRC flag can supply missing TB/good-bit evidence.
unknown=removevars(row,{'TBSize_bits','GoodBits'}); unknown.OfferedBits=1e6; unknown.CRCPass=1;
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'unknown_TBS'),struct('DL',unknown));
assert(all(out.SymbolThroughput.TotalGrantCount==0) && all(isnan(out.SymbolThroughput.ScheduledTotalBits)));
unknown=row; unknown.GoodBits=NaN; unknown.CRCPass=1;
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'unknown_good_bits'),struct('DL',unknown));
assert(nnz(out.SymbolThroughput.TotalGrantCount)==2 && all(isnan(out.SymbolThroughput.GoodTotalBits)));
unknown=removevars(row,'NumSymbols');
out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'unknown_allocation'),struct('DL',unknown));
assert(all(out.SymbolThroughput.TotalGrantCount==0),'Never replace unknown allocation with a whole slot.');
bad=row; bad.SymbolStart=13;
reject(@()sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'bad'),struct('DL',bad)), ...
    'sixgr:truth:InvalidSymbolThroughputAllocation');
if nargin>0
    source=fullfile(retainedRun,'air_interface','csv','dl_pdsch_trials.csv');
    hash=string(sixgr.util.sha256File(source));
    raw=sixgr.util.csvReadTable(source,'TextType','string');
    cfg.run.totalSlots=200;
    out=sixgr.truth.exportLLSLiveDerivedTables(cfg,fullfile(root,'retained'),struct('DL',raw));
    S=out.SymbolThroughput;
    for k=1:height(raw)
        e=jsondecode(raw.DataReceiveTimingEvidenceJSON(k));
        hit=S.Slot==e.DataAbsoluteSlot & S.SymbolInSlot==e.SymbolAllocation(1);
        assert(nnz(hit)==1 && abs(S.SymbolStartTime_s(hit)*e.SampleRateHz-e.TransmittedSymbolStartSample)<1e-6);
    end
    assert(string(sixgr.util.sha256File(source))==hash);
    fprintf('RETAINED_DL_SYMBOL_CLOCK_MATCH rows=%d raw_SHA256_unchanged=1\n',height(raw));
end
fprintf('LLS_SYMBOL_CLOCK_EVIDENCE_PASS numerologies=5 folder=%s\n',root);
ok=true;
end
function cfg=configuration(scs,cp)
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.SubcarrierSpacing_kHz=scs;
cfg.phy.carrier.SubcarrierSpacing=scs;
cfg.phy.carrier.CyclicPrefix=char(cp);
cfg.phy.numerology.scs_kHz=scs;
cfg.phy.numerology.symbolsPerSlot=14;
if cp=="extended", cfg.phy.numerology.symbolsPerSlot=12; end
cfg.phy.numerology.slotDuration_ms=15/scs;
end
function reject(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
