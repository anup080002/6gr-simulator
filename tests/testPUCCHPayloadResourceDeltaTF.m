function ok=testPUCCHPayloadResourceDeltaTF()
% Independent formulas against actual selected UCI encoding and TX power.
setup6GRSimToolkit('Verbose',false);
count=0;
for format=0:4
    populations=[1 2]; if format>=2, populations=[4 20]; end
    for n=populations
        f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(format,int8(mod((0:n-1).',2)));
        plan=sixgr.phy.pucch.PUCCHResourcePlan(f.Report,f.UEContext.Data,f.RRCContext,f.FrameState,"combined_uci");
        p=struct('Plan',plan,'Report',plan.TransmittedReport);
        [delta,e]=sixgr.phy.pucch.resolvePUCCHDeltaTF(f.Carrier,p);
        if format==0
            expected=10*log10(2/plan.Resource.Data.NumSymbols);
        elseif format==1
            expected=10*log10(14/plan.Resource.Data.NumSymbols)+10*log10(n);
        else
            native=plan.Resource.toolboxConfig();
            dmrs=nrPUCCHDMRSIndices(f.Carrier,native);
            physical=12*plan.Resource.Data.NumPRBs*plan.Resource.Data.NumSymbols-numel(unique(dmrs));
            assert(e.PhysicalDataREs==physical);
            if n<=11, expected=10*log10(6*n/physical);
            else, expected=10*log10(2^(2.4*(n+11)/physical)-1); end
        end
        assert(abs(delta-expected)<1e-12);
        data=f.Assignment.PowerControlState.Data; data.DeltaTFdB=delta; data.DeltaTFEvidence=e;
        power=sixgr.phy.pucch.PUCCHPowerControlState(data);
        assignment=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromResourcePlan(plan,power,f.Assignment.SpatialRelationState);
        tx=sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,assignment,p.Report);
        assert(abs(tx.Power.PowerError_dB)<1e-10 && tx.Assignment.PowerControlState.Data.DeltaTFEvidence.SHA256==e.SHA256);
        bad=data; bad.DeltaTFEvidence.InformationBits=n+1;
        rejected=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromResourcePlan(plan, ...
            sixgr.phy.pucch.PUCCHPowerControlState(bad),f.Assignment.SpatialRelationState);
        reject(@()sixgr.phy.pucch.PUCCHTransmitter.transmit(f.Carrier,rejected,p.Report));
        count=count+1;
    end
end
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(1,int8(1),'PayloadType','SR');
plan=sixgr.phy.pucch.PUCCHResourcePlan(f.Report,f.UEContext.Data,f.RRCContext,f.FrameState,"combined_uci");
[delta,e]=sixgr.phy.pucch.resolvePUCCHDeltaTF(f.Carrier,struct('Plan',plan,'Report',plan.TransmittedReport));
assert(e.Format1ModulationBits==1 && abs(delta-10*log10(14/plan.Resource.Data.NumSymbols))<1e-12);
fprintf('PUCCH_DELTA_TF_PASS ordinary_cases=%d SR_only=1 original_TX_closure=1\n',count);
ok=true;
end
function reject(fn)
try, fn(); catch failure
    assert(strcmp(failure.identifier,'sixgr:phy:pucch:DeltaTFBinding')); return;
end
error('test:MissingDeltaTFGuard','Altered payload-power proof was accepted.');
end
