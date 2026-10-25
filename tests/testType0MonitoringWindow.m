function ok=testType0MonitoringWindow()
% Independent table anchors, clipping, rollover and negative-domain checks.
ctx=struct('FrequencyRange',"FR1",'SSBSCSKHz',15,'PDCCHSCSKHz',15, ...
    'ChannelBandwidthMHz',20,'SharedSpectrum',false,'KSSB',0, ...
    'CORESET0Index',0,'SearchSpaceZero',6,'SSBIndex',2, ...
    'InitialDLBWPStart',0,'InitialDLBWPSize',106,'SSBFirstCommonRB',0, ...
    'NCellID',17,'SSBFrameNumber',0,'ConfigurationEpoch',1);
original=ctx;
r=sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,10,11);
assert(isequal(r.MonitoringOccasions.AbsoluteSlot,10));
assert(r.MonitoringOccasions.PairStartAbsoluteSlot==9 && ...
    r.MonitoringOccasions.PairMember0Based==1 && ~r.TransmissionScheduled);
r=sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,29,31);
assert(isequal(r.MonitoringOccasions.AbsoluteSlot,[29;30]));
assert(isequal(r.MonitoringOccasions.Slot,[9;0]));
edge=ctx;edge.SearchSpaceZero=9;edge.SSBIndex=7;
r=sixgr.phy.pdcch.resolveType0MonitoringWindow(edge,0,1);
assert(isequal(r.MonitoringOccasions.AbsoluteSlot,0) && ...
    r.MonitoringOccasions.PairStartAbsoluteSlot==-1 && ...
    r.MonitoringOccasions.PairMember0Based==1 && r.MonitoringOccasions.SFN==0);
for scs=[15 30]
    cfg=ctx;cfg.SSBSCSKHz=scs;cfg.PDCCHSCSKHz=scs;
    cfg.InitialDLBWPSize=51;F=10*scs/15;
    for search=0:15
        cfg.SearchSpaceZero=search;
        for ssb=0:7
            cfg.SSBIndex=ssb;
            base=sixgr.phy.pdcch.Type0PDCCHResolver(cfg,'MonitoringFrameCount',6);
            window=sixgr.phy.pdcch.resolveType0MonitoringWindow(cfg,0,6*F+1);
            expected=base.MonitoringOccasions.AbsoluteSlot;
            assert(all(ismember(expected,window.MonitoringOccasions.AbsoluteSlot)));
            for start=[0 1 F-1 F F+1 2*F-1 3*F]
                finish=start+F;
                part=sixgr.phy.pdcch.resolveType0MonitoringWindow(cfg,start,finish);
                wanted=window.MonitoringOccasions.AbsoluteSlot;
                wanted=wanted(wanted>=start & wanted<finish);
                assert(isequal(part.MonitoringOccasions.AbsoluteSlot,wanted));
            end
        end
    end
end
ctx.SSBIndex=2;ctx.SearchSpaceZero=6;
r=sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,10239,10241);
assert(isequal(r.MonitoringOccasions.AbsoluteSlot,zeros(0,1))); % parity: pair is 10229/10230
r=sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,10249,10251);
assert(isequal(r.MonitoringOccasions.AbsoluteFrameNumber,[1024;1025]) && ...
    isequal(r.MonitoringOccasions.SFN,[0;1]));
assert(isempty(sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,10,10).MonitoringOccasions));
assert(isequal(ctx,original),'The configured context must remain unchanged.');
for value={true,'10',NaN,Inf,-1,0.5,1+1i,intmax('uint64')}
    localReject(@()sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,value{1},20), ...
        'sixgr:phy:pdcch:InvalidMonitoringWindow');
end
localReject(@()sixgr.phy.pdcch.resolveType0MonitoringWindow(ctx,11,10), ...
    'sixgr:phy:pdcch:InvalidMonitoringWindow');
bad=ctx;bad.SSBIndex=8;
localReject(@()sixgr.phy.pdcch.resolveType0MonitoringWindow(bad,0,40), ...
    'sixgr:phy:pdcch:UnsupportedMonitoringWindow');
ok=true;
end
function localReject(action,id)
try,action();catch e,assert(strcmp(e.identifier,id),'Unexpected error: %s',e.identifier);return;end
error('test:MissingRejection','Expected %s',id);
end
