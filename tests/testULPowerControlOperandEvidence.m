function ok=testULPowerControlOperandEvidence()
% Exact production arithmetic/binding/CSV checks with declared operands.
% This is not a physical power measurement or a full waveform campaign.
setup6GRSimToolkit('Verbose',false);
cfg=struct();
cfg.phy.pusch.powerControl=struct('enabled',true,'p0PUSCH_dBm',-82.25, ...
    'p0UE_dB',2.5,'alpha',0.7,'deltaTF_dB',1.25,'pcmax_dBm',23, ...
    'adjustmentMode',"accumulated",'closedLoopEnabled',false,'requireMeasuredReferenceRS',true);
cfg.lls6g.userContext=struct('RuntimeServingPathloss_dB',99, ...
    'RuntimeServingPathlossSource',"declared_reference_rs_operand_fixture", ...
    'RuntimeServingPathlossReferenceRS',"SSB-2",'RuntimeServingPathlossMeasurementId',"declared_measurement");
tx=struct('PUSCH',struct('PRBSet',0:5), ...
    'Carrier',struct('SubcarrierSpacing',30,'CyclicPrefix',"normal"));
wave=complex(ones(12,2),ones(12,2)); originalWave=wave; originalCfg=cfg;
state=struct('PreviousF_dB',-2,'UpdateCount',0);
rows=cell(2,1);
for k=1:2
    current=cfg;
    if k==2, current.phy.pusch.powerControl.pcmax_dBm=-10; end
    [after,pc,bound,next]=sixgr.link.bindPUSCHPowerControlContext(wave,current,tx,struct(),state);
    assert(isequal(after,originalWave),'Binding must not scale the waveform.');
    assert(pc.P0Nominal_dBm==-82.25&&pc.P0UE_dB==2.5&&pc.Alpha==0.7&&pc.DeltaTF_dB==1.25);
    assert(pc.Mu==1&&pc.MRB==6&&pc.BandwidthTerm_dB==10*log10(12));
    requested=pc.P0Nominal_dBm+pc.P0UE_dB+pc.BandwidthTerm_dB+pc.Alpha*pc.Pathloss_dB+pc.DeltaTF_dB+pc.UpdatedF_dB;
    assert(pc.RequestedPower_dBm==requested&&pc.TxPower_dBm==min(pc.Pcmax_dBm,requested));
    assert(pc.Clipped==(k==2)&&bound.powerAndRF.ueTxPower_dBm==pc.TxPower_dBm&&next.PreviousF_dB==-2);
    rows{k}=sixgr.link.puschPowerStateEvidence(pc);
    for field=["P0Nominal_dBm","P0UE_dB","Alpha","DeltaTF_dB","MRB","Mu","BandwidthTerm_dB"]
        assert(isequal(rows{k}.("PUSCH"+field),pc.(field)));
    end
end
assert(isequaln(cfg,originalCfg)&&isequal(wave,originalWave));
disabled=cfg; disabled.phy.pusch.powerControl.enabled=false;
[~,pc]=sixgr.link.bindPUSCHPowerControlContext(wave,disabled,tx,struct(),state);
missing=sixgr.link.puschPowerStateEvidence(pc);
legacy=sixgr.link.puschPowerStateEvidence(struct('RequestedPower_dBm',999));
for field=["P0Nominal_dBm","P0UE_dB","Alpha","DeltaTF_dB","MRB","Mu","BandwidthTerm_dB"]
    assert(isnan(missing.("PUSCH"+field))&&isnan(legacy.("PUSCH"+field)));
end
bad=pc; bad.Alpha="0.7";
mustFail(@()sixgr.link.puschPowerStateEvidence(bad),'sixgr:link:PUSCHPowerOperandEvidence');
request=struct('Channel',"SRS",'Mu',2,'MRB',5,'MeasuredPathloss_dB',99, ...
    'PathlossSource',"declared_reference_rs_operand_fixture",'P0_dBm',-81.75, ...
    'Alpha',0.6,'DeltaTF_dB',0,'PCMAX_dBm',-15);
power=sixgr.rf.runtime.SRSPowerController.resolve(sixgr.rf.runtime.UplinkPowerControlState(1),request);
% Same retained request/metadata contract as the production SRS preparation.
power.Request=request; power.MRB=request.MRB; power.Mu=request.Mu;
power.PCMAX_dBm=request.PCMAX_dBm; power.MeasuredPathloss_dB=request.MeasuredPathloss_dB;
originalPower=power; srs=sixgr.link.srsPowerControlEvidence(power);
assert(srs.SRSPowerControlP0_dBm==-81.75&&srs.SRSPowerControlAlpha==0.6&& ...
    srs.SRSPowerControlDeltaTF_dB==0&&srs.SRSPowerControlBandwidthTerm_dB==power.BandwidthTerm_dB&& ...
    srs.SRSPowerControlMRB==5&&srs.SRSPowerControlMu==2&&srs.SRSPowerControlClipped);
assert(isequaln(power,originalPower));
absent=sixgr.link.srsPowerControlEvidence(struct('AppliedPower_dBm',23));
for field=["P0_dBm","Alpha","DeltaTF_dB","MRB","Mu","BandwidthTerm_dB"]
    assert(isnan(absent.("SRSPowerControl"+field)));
end
assert(absent.SRSPowerControlDeltaTFRole=="");
bad=power; bad.Request.DeltaTF_dB=1;
mustFail(@()sixgr.link.srsPowerControlEvidence(bad),'RF:SRSDeltaTFNotApplicable');
bad=power; bad.Request.P0_dBm="-81.75";
mustFail(@()sixgr.link.srsPowerControlEvidence(bad),'sixgr:link:SRSPowerOperandEvidence');
old=getenv('SIXGR_PERSISTENCE_ENABLED');
cleanup=onCleanup(@()setenv('SIXGR_PERSISTENCE_ENABLED',old)); %#ok<NASGU>
setenv('SIXGR_PERSISTENCE_ENABLED','1');
folder=fullfile(pwd,'results','validation','ul_power_operands',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Do not replace historical evidence.');
for channel=["PUSCH","SRS"]
    if channel=="PUSCH", T=struct2table([rows{1};rows{2};legacy]);
    else, T=struct2table([srs;absent]); end
    original=T; path=fullfile(folder,lower(channel)+"_declared_operands.csv");
    sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'RoundTripNumericText',true);
    loaded=sixgr.util.csvReadTable(path);
    if channel=="PUSCH", fields=["PUSCHP0Nominal_dBm","PUSCHP0UE_dB","PUSCHAlpha","PUSCHDeltaTF_dB","PUSCHMRB","PUSCHMu","PUSCHBandwidthTerm_dB"];
    else, fields=["SRSPowerControlP0_dBm","SRSPowerControlAlpha","SRSPowerControlDeltaTF_dB","SRSPowerControlMRB","SRSPowerControlMu","SRSPowerControlBandwidthTerm_dB"]; end
    assert(isequaln(loaded(:,cellstr(fields)),T(:,cellstr(fields)))&&isequaln(T,original));
end
ok=true; fprintf('UL_POWER_OPERAND_EVIDENCE_PASS scope=production_arithmetic_binding_and_declared_CSV_not_PHY\n');
end

function mustFail(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Unexpected error: %s',ME.identifier); return; end
error('sixgr:test:MissingPowerOperandGuard','Expected rejection %s.',id);
end
