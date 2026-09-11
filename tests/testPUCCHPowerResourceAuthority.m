function ok=testPUCCHPowerResourceAuthority()
% Analytical resource/numerology vectors, not campaign PHY measurements.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_tdd_connected_feedback_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.validation.pucch_resources.power_control.require_measured_reference_rs=false;
if isfield(cfg.lls6g,'userContext'), cfg.lls6g=rmfield(cfg.lls6g,'userContext'); end
ue=struct('UEID',1,'RNTI',1,'ServingCell',1,'PUCCHCell',1, ...
    'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
    'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
pri=sixgr.phy.pucch.resolveConfiguredPRI(cfg,1,1,NaN,'csi');
frame=struct('K1',1,'K1Source','decoded_dci','PDSCHEndSlot',3, ...
    'TargetSlot',4,'DecodedPRI',pri.PRIValue,'PRIFieldWidth',3, ...
    'PRIProvenance',pri.Source,'FirstCCE',0,'NumCCE',8, ...
    'SlotSymbolOwnership',"UUUUUUUUUUUUUU", ...
    'FlexibleResolutionProvided',false,'TriggeringEventID',"power_resource_fixture");
for scs=[15 30 60]
    for prbs=[1 2 4]
        c=cfg;
        c.phy.carrier.SubcarrierSpacing=scs;
        c.phy.carrier.SubcarrierSpacing_kHz=scs;
        index=find([c.validation.pucch_resources.resources.id]==10);
        c.validation.pucch_resources.resources(index).nrof_prbs=prbs;
        % Keep the stale calibration fields unchanged deliberately.
        c.validation.pucch_resources.power_control.mu=0;
        c.validation.pucch_resources.power_control.m_rb=1;
        planned=sixgr.phy.pucch.PUCCHConfigBuilder.planCSI( ...
            c,ue,int8([1;0;1;0]),int8([]),frame);
        tx=sixgr.phy.pucch.PUCCHConfigBuilder.materialize(c,planned);
        d=tx.Assignment.PowerControlState.Data;
        assert(d.MRB==prbs && d.Mu==log2(scs/15), ...
            'PUCCH power bandwidth must use the selected resource and actual carrier numerology.');
        p=sixgr.phy.pucch.PUCCHPowerController.resolve(tx.Assignment.PowerControlState);
        expectedBandwidth=10*log10(prbs*scs/15);
        assert(abs(p.BandwidthTermdB-expectedBandwidth)<1e-12);
        expected=d.P0dBm+d.PathlossdB+expectedBandwidth+d.DeltaFdB+ ...
            d.DeltaTFdB+d.ClosedLoopAdjustmentdB;
        assert(abs(p.RequestedPowerdBm-expected)<1e-12);
    end
end
ok=true; disp('PUCCH_POWER_RESOURCE_AUTHORITY_PASS: 9 PRB/numerology vectors.');
end
