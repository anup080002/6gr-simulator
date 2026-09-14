function ok=testDCIFeedbackTiming(outputRoot)
% Protocol/codec regression, not RF, mobile-runtime or 12 dB qualification.
if nargin<1, outputRoot=tempname(fullfile(pwd,'logs')); end
assert(~isfolder(outputRoot),'Use a new evidence directory.');
mkdir(outputRoot);
tables={1:8,1:8,1:8,1:8,[7 8 12 16 20 24 28 32],[13 16 24 32 40 48 56 64]};
mus=[0 1 2 3 5 6];
rows=struct('Format',{},'Mu',{},'Slots',{},'Indicator',{},'Width',{});
for k=1:numel(mus)
    d=struct('DCIFormat',"1_0",'PUCCHSubcarrierSpacingKHz',15*2^mus(k));
    for i=1:8
        [indicator,width]=sixgr.phy.pdcch.HARQFeedbackTiming.encode(d,tables{k}(i));
        assert(indicator==i-1 && width==3);
        assert(sixgr.phy.pdcch.HARQFeedbackTiming.decode(d,i-1)==tables{k}(i));
        rows(end+1)=struct('Format',"1_0",'Mu',mus(k),'Slots',tables{k}(i),'Indicator',indicator,'Width',width); %#ok<AGROW>
    end
end
for values={8,[8 4],[8 0 4],[8 4 7 2 6],[8 4 7 2 6 1 5 3]}
    d=struct('DCIFormat',"1_1",'DLDataToULACK',values{1});
    for i=1:numel(values{1})
        [indicator,width]=sixgr.phy.pdcch.HARQFeedbackTiming.encode(d,values{1}(i));
        assert(indicator==i-1 && width==ceil(log2(numel(values{1}))));
        assert(sixgr.phy.pdcch.HARQFeedbackTiming.decode(d,i-1)==values{1}(i));
        rows(end+1)=struct('Format',"1_1",'Mu',NaN,'Slots',values{1}(i),'Indicator',indicator,'Width',width); %#ok<AGROW>
    end
end
one=struct('DCIFormat',"1_1",'DLDataToULACK',8);
assert(sixgr.phy.pdcch.HARQFeedbackTiming.decode(one,[])==8);
d=struct('DCIFormat',"1_0",'PUCCHSubcarrierSpacingKHz',30);
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.encode(d,0),'FeedbackTimingNotConfigured');
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.encode(d,9),'FeedbackTimingNotConfigured');
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.decode(d,8),'InvalidFeedbackTimingIndicator');
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.decode(d,[]),'MissingFeedbackTimingIndicator');
for bad={NaN,Inf,1.5,[1 2],1i,'8'}
    localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.encode(d,bad{1}),'InvalidFeedbackTimingValue');
end
for mu=[-1 4 7]
    bad=d; bad.PUCCHSubcarrierSpacingKHz=15*2^mu;
    if mu==-1, id='InvalidFeedbackTimingValue'; else, id='UnsupportedFeedbackTimingNumerology'; end
    localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.table(bad),id);
end
for list={[],[4 4],NaN,[1 2;3 4],-1,0:8,1.5,'8'}
    bad=one; bad.DLDataToULACK=list{1};
    localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.table(bad),'InvalidFeedbackTimingList');
end
bad=one; bad.DLDataToULACK=[8 4 2];
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.decode(bad,3),'InvalidFeedbackTimingIndicator');

% Use the complete candidate factory/schema/packer/parser copies, with
% production immutable-context/hash/field-definition dependencies unchanged.
fixture=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',25),'1_0');
data=fixture.Data; data.DLTimeDomainAllocations=[0 2 12 0];
data.MonitoredFormats=["1_0","1_1"];
cfg=struct('phy',struct('carrier',struct('SubcarrierSpacing',120), ...
    'bwp',struct('ul',struct('SubcarrierSpacing_kHz',30)), ...
    'pucch',struct('dlDataToULACK',[8 4 2])));
bound=sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(cfg,data);
assert(bound.PUCCHSubcarrierSpacingKHz==30 && isequal(cfg.phy.pucch.dlDataToULACK,[8 4 2]));
% All explicit frame-builder BWP spellings must retain the UL numerology,
% even when DL runs on a different clock. No carrier fallback for missing UL.
for alias=["SCSKHz","SubcarrierSpacingKHz","SubcarrierSpacing_kHz","scs_khz"]
    same=cfg; same.phy.bwp.ul=struct(alias,cfg.phy.bwp.ul.SubcarrierSpacing_kHz);
    observed=sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(same,data);
    assert(isequaln(observed,bound));
    same.phy.bwp.ul.SubcarrierSpacing_kHz=cfg.phy.bwp.ul.SubcarrierSpacing_kHz;
    observed=sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(same,data);
    assert(isequaln(observed,bound));
end
conflict=cfg; conflict.phy.bwp.ul.SCSKHz=cfg.phy.carrier.SubcarrierSpacing;
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(conflict,data),'InvalidFeedbackTimingContext');
absent=cfg; absent.phy.bwp.ul=struct('BWPID',0);
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(absent,data),'InvalidFeedbackTimingValue');
malformed=cfg; malformed.phy.bwp.ul.SCSKHz=[];
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(malformed,data),'InvalidFeedbackTimingValue');
bound.DCIFormat="1_1";
for values={8,[8 4],[8 4 2],[8 4 2 7 3]}
    bound.DLDataToULACK=values{1};
    for fmt=["1_0","1_1"]
        bound.DCIFormat=fmt; context=sixgr.phy.pdcch.DCIContext(bound);
        schema=sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
        fields=struct();
        for definition=schema.Definitions(:).'
            fields.(definition.Name)=definition.ValueMin;
        end
        [indicator,width]=sixgr.phy.pdcch.HARQFeedbackTiming.encode(context,8);
        if width>0, fields.pdsch_to_harq_feedback_timing=indicator; end
        packed=sixgr.phy.pdcch.DCIPacker.pack(fields,context);
        decoded=sixgr.phy.pdcch.DCIParser.parse(packed.Bits,context);
        assert(decoded.Fields.pdsch_to_harq_feedback_timing_slots==8);
        if width>0
            assert(decoded.Fields.pdsch_to_harq_feedback_timing==indicator);
            field=packed.FieldTable(packed.FieldTable.FieldName=="pdsch_to_harq_feedback_timing",:);
            actual=packed.Bits(field.BitStart+1:field.BitEnd+1);
            expected=int8(bitget(uint32(indicator),width:-1:1).');
            assert(isequal(actual,expected),'Exact encoded indicator bits differ.');
        else
            assert(~isfield(decoded.Fields,'pdsch_to_harq_feedback_timing'));
        end
    end
end
% No RRC timing list is synthesized from scheduler candidates.
missing=cfg; missing.phy.pucch.dlDataToULACK=[];
localReject(@()sixgr.phy.pdcch.HARQFeedbackTiming.bindRuntime(missing,data),'InvalidFeedbackTimingList');

% The actual reproduced scenario receives an explicit RRC list in YAML.
scenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator','configs', ...
    'scenarios','lls_mobile_2ue_100kmh_1sector_full_capture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(scenario,fullfile(outputRoot,'configured_run'));
save(fullfile(outputRoot,'resolved_config_before_assertions.mat'),'cfg','-v7.3');
fprintf('Configured dl-DataToUL-ACK: class=%s size=%s values=%s\n', ...
    class(cfg.phy.pucch.dlDataToULACK),mat2str(size(cfg.phy.pucch.dlDataToULACK)), ...
    mat2str(cfg.phy.pucch.dlDataToULACK));
assert(isequal(double(cfg.phy.pucch.dlDataToULACK(:).'),[4 5 6 7 8]));
for fmt=["1_0","1_1"]
    grant=struct('Direction',"DL",'RNTI',1, ...
        'SymbolAllocation',cfg.phy.pdsch.symbolAllocation);
    context=sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,grant,fmt);
    [indicator,~]=sixgr.phy.pdcch.HARQFeedbackTiming.encode(context,8);
    if fmt=="1_0", assert(indicator==7); else, assert(indicator==4); end
    assert(sixgr.phy.pdcch.HARQFeedbackTiming.decode(context,indicator)==8);
end
localCheckScheduler(cfg,outputRoot);
% Separate declared strict-context config fixture with a non-eight-entry
% RRC list proves cache refresh uses the final installed PUCCH policy.
strictScenario=sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd,'simulator', ...
    'configs','scenarios','master_sinr_sweep.yaml'));
strictRaw=strictScenario.toStruct();
strictRaw.pucch_resources.dl_data_to_ul_ack=[8 4 2];
strictCfg=sixgr.lls6g.buildInternalConfig(strictRaw,fullfile(outputRoot,'strict_config_fixture'));
for fmt=["1_0","1_1"]
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(strictCfg,fmt);
    index=find(string(strictCfg.phy.pdcch.dciFormats)==fmt);
    aligned=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
    assert(strictCfg.phy.pdcch.dciPayloadSizesByFormat(index)==aligned.Selected.AlignedBits);
    assert(isequal(strictCfg.phy.pdcch.dciContextData{index},context.Data));
    assert(strictCfg.phy.pdcch.dciContextDigests(index)==context.Digest);
    if fmt=="1_1"
        [indicator,width]=sixgr.phy.pdcch.HARQFeedbackTiming.encode(context,8);
        assert(indicator==0 && width==2);
    end
end
writetable(struct2table(rows),fullfile(outputRoot,'literal_timing_vectors.csv'));
save(fullfile(outputRoot,'configuration_and_vectors.mat'),'cfg','rows','-v7.3');
ok=true;
disp('PASS DCI_FEEDBACK_TIMING: literal maps, invalid inputs, exact packed indicators, decoder slots and YAML context sizes. No RF execution.');
end

function localReject(fn,suffix)
try, fn(); catch cause
    assert(strcmp(cause.identifier,['sixgr:phy:pdcch:' suffix]), ...
        'Expected %s, got %s: %s',suffix,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',suffix);
end

function localCheckScheduler(cfg,outputRoot)
% Declared protocol fixture through the public method; not RF/TBS evidence.
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','DL');
seed=struct('Direction',"DL",'RNTI',1,'SymbolAllocation',cfg.phy.pdsch.symbolAllocation);
context=sixgr.phy.pdcch.DCIContextFactory.fromScheduledGrant(cfg,seed,'1_0');
allocations=context.Data.DLTimeDomainAllocations;
row=allocations(find(all(allocations(:,2:3)==seed.SymbolAllocation,2),1),:);
assert(numel(row)>=4,'Fixture requires an explicit TDRA timing offset.');
controlSlot=1; dataSlot=controlSlot+row(4); feedbackSlot=dataSlot+8;
data=struct('Valid',true,'TargetStartSymbol',row(2),'TargetNumSymbols',row(3), ...
    'TargetAbsoluteSlot',dataSlot,'SourceNumSymbols',2, ...
    'TargetTick',dataSlot*100,'TargetEndTick',dataSlot*100+14);
ack=struct('Valid',true,'TimingAdvanceTicks',0,'TargetStartSymbol',10, ...
    'TargetNumSymbols',4,'SourceTick',data.TargetTick,'SourceEndTick',data.TargetEndTick, ...
    'TargetAbsoluteSlot',feedbackSlot);
timing=struct('Valid',true,'Direction',"DL",'DataDecision',data, ...
    'ControlAbsoluteSlot',controlSlot,'DataAbsoluteSlot',dataSlot, ...
    'FeedbackAbsoluteSlot',feedbackSlot,'K0',row(4),'K1',8,'K2',NaN, ...
    'CarrierIndicator',0,'ControlSymbolAllocation',[0 2], ...
    'HARQACKRequired',true,'HARQACKDecision',ack);
grant=seed; grant.TimingDecision=timing; grant.PRBSet=0;
grant.ScheduledAbsoluteSlot=dataSlot; grant.ControlAbsoluteSlot=controlSlot;
grant.K0=row(4); grant.K1=8; grant.K2=NaN; grant.NumLayers=1;
grant.TCIState=NaN; grant.MCSIndex=0; grant.DAI=0;
grant.Frame=1; grant.Slot=dataSlot+1;
grant.HARQ=struct('NDI',true,'RV',0,'HarqID',0);
original=grant;
packed=scheduler.buildDCIBitfield(grant);
context=sixgr.phy.pdcch.DCIContext(packed.ContextData);
decoded=sixgr.phy.pdcch.DCIParser.parse(packed.Bits,context);
[expected,~]=sixgr.phy.pdcch.HARQFeedbackTiming.encode(context,8);
assert(decoded.Fields.pdsch_to_harq_feedback_timing==expected && ...
    decoded.Fields.pdsch_to_harq_feedback_timing_slots==8);
assert(isequaln(grant,original) && packed.FieldValues.K1==8);
assert(~packed.ExactPHYFeasibilityChecked && ~packed.FinalizedGrant && isnan(packed.SourceGrantTBSBits));
save(fullfile(outputRoot,'scheduler_codec_fixture.mat'),'grant','packed','decoded','-v7.3');
end
