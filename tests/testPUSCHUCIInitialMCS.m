function ok=testPUSCHUCIInitialMCS()
cfg=struct('phy',struct('pusch',struct('mcsTable','qam64_table1')));
grant=struct('Direction','UL','ServingCell',1,'UEIndex',1,'RNTI',101, ...
    'MCSIndex',10,'TargetCodeRate',340/1024,'TBSBits',1160, ...
    'Modulation','16QAM','NumLayers',1,'Rank',1,'PRBSet',3:8, ...
    'SymbolAllocation',[2 12],'Slot',1,'HARQ',struct('HarqID',2,'NDI',true,'NDIEpoch',1));
layout=sixgr.phy.phycode.resolveCodingLayout('Direction','UL','TransportBlockSize',1160, ...
    'TargetCodeRate',340/1024,'RV',0,'Modulation','16QAM','NumLayers',1,'RateMatchedBitCount',3600);
meta=struct('Direction','UL','Grant',grant,'CodingLayout',layout,'IsRetransmission',false);
initial=sixgr.harq.createTBContext(meta);
grant.MCSIndex=31; grant.Modulation='64QAM'; grant.TargetCodeRate=.75;
grant.NumLayers=2; grant.Rank=2; grant.Slot=3;
meta.Grant=grant; meta.IsRetransmission=true; meta.PreviousContext=initial;
retained=sixgr.harq.createTBContext(meta);
assert(retained.OriginalMCS==10 && retained.OriginalTargetCodeRate==340/1024 && ...
    string(retained.OriginalModulation)=="16QAM" && retained.OriginalQm==4 && ...
    retained.OriginalNumLayers==1 && retained.OriginalRank==1);
h=struct('TransportBlockContext',retained);
ref=sixgr.link.resolvePUSCHUCIInitialMCS(cfg,grant,h,true,31);
assert(ref.MCS==10 && ref.Source=="gnb_retained_original_tb_context");
localReject(@()sixgr.link.resolvePUSCHUCIInitialMCS(cfg,grant,struct(),true,31), ...
    'sixgr:link:PUSCHUCIHARQReferenceMissing');
wrong=h; wrong.TransportBlockContext.OriginalMCS=31;
localReject(@()sixgr.link.resolvePUSCHUCIInitialMCS(cfg,grant,wrong,true,31), ...
    'sixgr:link:PUSCHUCIInitialMCSUndefined');
for field=["RNTI","HARQProcessId","NDIEpoch","CellId","UeId","TBSBits"]
    wrong=h; wrong.TransportBlockContext.(field)=wrong.TransportBlockContext.(field)+1;
    localReject(@()sixgr.link.resolvePUSCHUCIInitialMCS(cfg,grant,wrong,true,31), ...
        'sixgr:link:PUSCHUCIHARQReferenceMismatch');
end
wrong=h; wrong.TransportBlockContext.OriginalTargetCodeRate=.75;
localReject(@()sixgr.link.resolvePUSCHUCIInitialMCS(cfg,grant,wrong,true,31), ...
    'sixgr:link:PUSCHUCIHARQReferenceMismatch');
grant.HARQ.NDI=false; grant.HARQ.NDIEpoch=2; grant.MCSIndex=20;
meta.Grant=grant; meta.IsRetransmission=false;
fresh=sixgr.harq.createTBContext(meta);
assert(fresh.OriginalMCS==20 && fresh.OriginalTargetCodeRate==.75 && ...
    string(fresh.OriginalModulation)=="64QAM" && fresh.OriginalNumLayers==2);
ref=sixgr.link.resolvePUSCHUCIInitialMCS(cfg,grant,struct(),false,20);
assert(ref.MCS==20 && ref.Source=="current_new_tb_mcs");
ok=true;
end
function localReject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Expected %s got %s: %s',id,ME.identifier,ME.message); return; end
error('test:MissingRejection','Expected %s.',id);
end
