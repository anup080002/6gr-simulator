function ok=testSLSNativePUSCHUCIResources()
% Deterministic native resource math, not a statistical UCI qualification.
c=nrCarrierConfig('NSizeGrid',25,'SubcarrierSpacing',30);
for layers=[1 2 4]
    p=nrPUSCHConfig('PRBSet',0:11,'NumLayers',layers,'Modulation','16QAM');
    p.DMRS.DMRSPortSet=0:layers-1;
    [~,gi]=nrPUSCHIndices(c,p);
    tbs=nrTBS(p.Modulation,layers,numel(p.PRBSet),gi.NREPerPRB,.4);
    for h=[1 2 3 4]
        x=sixgr.phy.ul.pusch.planUCIResources(c,p,.4,tbs,[h 10 0]);
        ref=nrULSCHInfo(p,.4,tbs,h,10,0);
        assert(x.GULSCH==ref.GULSCH && x.GACK==ref.GACK && x.GCSI1==ref.GCSI1);
        assert(x.GULSCH<x.G && x.AllocatedRECount>0 && ~x.WaveformBacked);
        assert(size(unique(x.Coordinates0Based,'rows'),1)==x.AllocatedRECount);
        [dmrs]=nrPUSCHDMRSIndices(c,p,'IndexStyle','subscript','IndexBase','0based');
        assert(isempty(intersect(x.Coordinates0Based,double(dmrs(:,1:2)),'rows')));
        % A changed UCI allocation must change the calibrated link key.
        g=struct('PRBSet',p.PRBSet,'SymbolAllocation',p.SymbolAllocation, ...
            'Modulation',p.Modulation,'NumLayers',layers,'TBSBits',tbs);
        ctx=struct('Grant',g,'TBSBits',tbs,'Direction',"UL",'TargetCodeRate',.4, ...
            'NumLayers',layers,'SCS_kHz',30,'ChannelModel',"TDL-A");
        o=struct('Channel',zeros(4,4,1),'RFProfileID',"ideal", ...
            'ReceiverProfileID',"lmmse",'ChannelProfileID',"test");
        a=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,o);
        ctx.Grant.SLSUCIAllocation=x;
        b=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,o);
        assert(a.AllocationSHA256~=b.AllocationSHA256);
        bad=ctx; bad.Grant.SLSUCIAllocation.GULSCH=x.GULSCH+1;
        reject(@()sixgr.system.CalibratedLinkPHY.calibrationKey(bad,o));
        bad=ctx; bad.Grant.PRBSet=1:12;
        reject(@()sixgr.system.CalibratedLinkPHY.calibrationKey(bad,o));
    end
end
fprintf('SLS_NATIVE_PUSCH_UCI_RESOURCE_PASS cases=12 qualification=resource_math_only\n'); ok=true;
end
function reject(fn)
try, fn(); catch ME, assert(strcmp(ME.identifier,'sixgr:abstraction:UCIAllocationIdentity')); return; end
error('test:NoRejection','Expected UCI allocation identity rejection.');
end
