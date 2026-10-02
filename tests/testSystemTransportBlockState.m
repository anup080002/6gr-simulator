function ok=testSystemTransportBlockState()
cfg=sixgr.config.defaultConfig();
p=sixgr.system.WaveformPHY(cfg,struct(),'Seed',1234);
assert(p.Cfg.run.seed==1234 && p.Cfg.channel.seed==1234);
key="unit_test_owned_soft_buffer";
sixgr.system.waveform.harqSoftBufferCache("set",key,[1 2]);
[hit,v]=sixgr.system.waveform.harqSoftBufferCache("get",key); assert(hit && isequal(v,[1 2]));
sixgr.system.waveform.harqSoftBufferCache("clear",key);
[hit,~]=sixgr.system.waveform.harqSoftBufferCache("get",key); assert(~hit);
s=sixgr.system.SystemTransportBlockState(17);
c=struct('Direction',"UL",'ServingCellID',1,'TBSBits',80, ...
    'Grant',struct('RNTI',1,'HARQ',struct('HarqID',0,'NDI',1,'IsRetransmission',false)));
[a,old]=s.bind(c); assert(strlength(old)==0 && numel(a.TransportBlockBits)==80);
c.Grant.HARQ.IsRetransmission=true;
[b,old]=s.bind(c); assert(strlength(old)==0);
assert(a.TransportBlockIdentity==b.TransportBlockIdentity && isequal(a.TransportBlockBits,b.TransportBlockBits));
c.TBSBits=88;
try, s.bind(c); error('test:ExpectedError','Missing immutable TBS guard.');
catch ME, assert(strcmp(ME.identifier,'sixgr:system:TransportBlockMutation')); end
c.TBSBits=80; c.Grant.HARQ.IsRetransmission=false; c.Grant.HARQ.NDI=0;
oldKey="UL|tb="+a.TransportBlockIdentity+"|tbs=80";
sixgr.system.waveform.harqSoftBufferCache("set",oldKey,[1 2 3]);
[d,old]=s.bind(c); assert(old==a.TransportBlockIdentity && d.TransportBlockIdentity~=a.TransportBlockIdentity);
[hit,~]=sixgr.system.waveform.harqSoftBufferCache("get",oldKey); assert(~hit);
s2=sixgr.system.SystemTransportBlockState(17); [e,~]=s2.bind(c);
assert(isequal(e.TransportBlockBits,a.TransportBlockBits) && e.TransportBlockIdentity~=a.TransportBlockIdentity);
L=table("max_retx_drop",0,1,0,0,'VariableNames', ...
    {'Status','AttemptSlot','RNTI','HARQProcessId','ScheduleSlot'});
drops=s.terminalDrops("UL",1,L,1);
assert(numel(drops)==1 && drops.ID==d.TransportBlockIdentity && drops.UEID==1);
L.ScheduleSlot=1;
try, s.terminalDrops("UL",1,L,1); error('test:ExpectedError','Missing drop generation guard.');
catch ME, assert(strcmp(ME.identifier,'sixgr:system:DroppedTBIdentity')); end
ownedKey="UL|tb="+d.TransportBlockIdentity+"|tbs=80";
otherKey="UL|tb="+e.TransportBlockIdentity+"|tbs=80";
sixgr.system.waveform.harqSoftBufferCache("set",ownedKey,1);
sixgr.system.waveform.harqSoftBufferCache("set",otherKey,2);
delete(s);
[hit,~]=sixgr.system.waveform.harqSoftBufferCache("get",ownedKey); assert(~hit);
[hit,~]=sixgr.system.waveform.harqSoftBufferCache("get",otherKey); assert(hit);
delete(s2);
[hit,~]=sixgr.system.waveform.harqSoftBufferCache("get",otherKey); assert(~hit);
abstract=sixgr.system.SystemTransportBlockState(17,false);
[first,~]=abstract.bind(c); c.Grant.HARQ.IsRetransmission=true;
[retry,~]=abstract.bind(c);
assert(isempty(first.TransportBlockBits) && ...
    first.TransportBlockIdentity==retry.TransportBlockIdentity);
delete(abstract);
ok=true;
end
