function ok=testResearchPUSCHUCIResourceAdapter()
% Native differential resource-map checks, not physical feedback acceptance.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
s=sixgr.lls6g.config.readConfigFile('simulator/configs/coding/research_pusch_uci.yaml');
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(20260918,'twister');
profiles=[25 15;264 120]; lengths=[0 0 0;1 7 0;2 7 20;7 20 7;20 0 0];
mods=["QPSK","16QAM","64QAM","256QAM","1024QAM"];
count=0;
for profile=1:2
 for layers=[2 4]
    p=nrPUSCHConfig('NSizeBWP',profiles(profile,1),'NStartBWP',0, ...
        'PRBSet',0:profiles(profile,1)-1,'NumLayers',layers, ...
        'TransmissionScheme','nonCodebook','SymbolAllocation',[0 14]);
    p.DMRS.DMRSPortSet=0:layers-1;
    p.DMRS.NumCDMGroupsWithoutData=2;
    carrier=nrCarrierConfig('NSizeGrid',profiles(profile,1), ...
        'SubcarrierSpacing',profiles(profile,2));
    [~,allocation]=nrPUSCHIndices(carrier,p);
    for modIndex=1:numel(mods)
      qm=2*modIndex; modulation=mods(modIndex);
      tbs=nrTBS(char(modulation),layers,profiles(profile,1),allocation.NREPerPRB,.5);
      for row=1:size(lengths,1)
        n=lengths(row,:);
        plan=sixgr.phy.research.PUSCHUCIResourceAdapter.resolve(s,p,.5,tbs,n,modulation);
        assert(plan.Qm==qm && plan.G==allocation.G*qm/2 && ~plan.StandardNR);
        llr=sin((1:plan.G).');
        [u,a,c1,c2]=sixgr.phy.research.PUSCHUCIResourceAdapter.demultiplex(plan,llr);
        if qm<=8
            native=p; native.Modulation=char(modulation);
            info=nrULSCHInfo(native,.5,tbs,n(1),n(2),n(3));
            assert(isequal([plan.GULSCH plan.GACK plan.GCSI1 plan.GCSI2], ...
                [info.GULSCH info.GACK info.GCSI1 info.GCSI2]));
            [un,an,c1n,c2n]=nrULSCHDemultiplex(native,.5,tbs,n(1),n(2),n(3),llr);
            assert(isequal(u,un) && isequal(a,an) && isequal(c1,c1n) && isequal(c2,c2n));
            ub=int8(randi([0 1],plan.GULSCH,1));
            ab=encode(n(1),plan.GACK,modulation);
            c1b=encode(n(2),plan.GCSI1,modulation);
            c2b=encode(n(3),plan.GCSI2,modulation);
            actual=sixgr.phy.research.PUSCHUCIResourceAdapter.multiplex(plan,ub,ab,c1b,c2b);
            expected=nrULSCHMultiplex(native,.5,tbs,ub,ab,c1b,c2b);
            assert(isequal(actual,expected),'Native coded-bit map differs.');
        else
            streams={u,a,c1,c2};
            for k=1:4
                map=plan.StreamIndices{k}; present=map>0;
                assert(all(streams{k}(~present)==0) && isequal(streams{k}(present),llr(map(present))));
            end
        end
        count=count+1;
      end
    end
 end
end
bad=p; bad.TransformPrecoding=true;
reject(@()sixgr.phy.research.PUSCHUCIResourceAdapter.resolve(s,bad,.5,tbs,[1 7 0],"1024QAM"), ...
    'sixgr:research:UnsupportedUCIGeometry');
badPolicy=s; badPolicy.meta.research_class='baseline_benchmark';
reject(@()sixgr.phy.research.PUSCHUCIResourceAdapter.resolve(badPolicy,p,.5,tbs,[1 7 0],"1024QAM"), ...
    'sixgr:research:ExplicitUCIAdapterRequired');
ok=true;
fprintf('RESEARCH_PUSCH_UCI_RESOURCE_ADAPTER_PASS cases=%d native_differential=80 experimental_Qm10=20 bandwidths=5MHz,400MHz physical_integration=0\n',count);
end

function coded=encode(n,g,modulation)
if n==0, coded=int8([]); else, coded=int8(nrUCIEncode(int8(randi([0 1],n,1)),g,char(modulation))); end
end

function reject(action,id)
try
    action();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s',id,ME.identifier);
    return;
end
error('test:ExpectedRejection','Expected rejection: %s',id);
end
