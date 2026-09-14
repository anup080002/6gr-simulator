function ok=testSSBPowerReferenceContract()
% Real production TX samples + real SIB1 receiver; no channel/noise oracle.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_ssb_physical_power_contract_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,fullfile(tempdir,'ssb_power_reference_contract'));
for nrb=[25 52 106]
    c=cfg; c.phy.carrier.NSizeGrid=nrb;
    [bound,p]=sixgr.rf.resolveSSBPowerContract(c);
    assert(p.SSPBCHBlockPower_dBm==floor(30-10*log10(12*nrb)));
    [again,q]=sixgr.rf.resolveSSBPowerContract(bound);
    assert(isequaln(p,q) && isequaln(again,bound),'Resolution must not accumulate SSB boost.');
end
c=cfg; c.phy.ssb.perSSBPower_dB=[0 1 0 0];
localReject(@()sixgr.rf.resolveSSBPowerContract(c),'sixgr:rf:SSBCommonPowerMismatch');
c=cfg; c.lls6g.resolvedConfig.power_and_rf_frontend.downlink_power_normalization_policy='active_ofdm_total_power';
localReject(@()sixgr.rf.resolveSSBPowerContract(c),'sixgr:rf:SSBPowerNormalizationMismatch');
c=cfg; c.lls6g.resolvedConfig.power_and_rf_frontend.ss_pbch_block_power_dbm=5;
localReject(@()sixgr.rf.resolveSSBPowerContract(c),'sixgr:rf:SSBPowerAuthorityConflict');
c.lls6g.resolvedConfig.power_and_rf_frontend.ssb_power_reference_policy='explicit_ss_pbch_block_power';
[~,p]=sixgr.rf.resolveSSBPowerContract(c); assert(p.SSPBCHBlockPower_dBm==5);
c.lls6g.resolvedConfig.power_and_rf_frontend.ss_pbch_block_power_dbm=[];
localReject(@()sixgr.rf.resolveSSBPowerContract(c),'sixgr:rf:MissingSSBPowerDeclaration');
for budget=[30 33]
    c=cfg; c.lls6g.resolvedConfig.power_and_rf_frontend.bs_tx_power_dbm=budget;
    localVerifyActualWaveform(c,floor(budget-10*log10(300)),true);
end
% The production 12 dB scenario remains normalized. Device-budget changes
% must not change its common declaration or actual normalized SSS EPRE.
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_causal_access_to_data_wiring_tdd.yaml'));
normalized=sixgr.lls6g.buildInternalConfig(s,tempname);
for budget=[30 33]
    c=normalized; c.lls6g.resolvedConfig.power_and_rf_frontend.bs_tx_power_dbm=budget;
    [bound,p]=sixgr.rf.resolveSSBPowerContract(c);
    [again,q]=sixgr.rf.resolveSSBPowerContract(bound);
    assert(isequaln(p,q) && isequaln(again,bound));
    carrier=sixgr.phy.grid.makeCarrier(c); info=nrOFDMInfo(carrier);
    expected=floor(-20*log10(double(info.Nfft)));
    assert(p.FixedSNRNormalizedReference && ~p.PhysicalDevicePowerClaim && isnan(p.TxPowerBudget_dBm));
    assert(p.SSPBCHBlockPower_dBm==expected && ...
        abs(p.OFDMUnitReference.UnitREUsefulSamplePower_mW-1/double(info.Nfft)^2)<1e-14);
    localVerifyActualWaveform(c,expected,false);
end
c=normalized; c.lls6g.resolvedConfig.power_and_rf_frontend.ssb_power_reference_policy='explicit_ss_pbch_block_power';
c.lls6g.resolvedConfig.power_and_rf_frontend.ss_pbch_block_power_dbm=5;
localReject(@()sixgr.rf.resolveSSBPowerContract(c),'sixgr:rf:SSBExplicitPowerInNormalizedMode');
ok=true; disp('SSB_POWER_REFERENCE_CONTRACT_PASS');
end

function localVerifyActualWaveform(c,expected,physical)
    prepared=sixgr.link.prepareCellSearchBroadcast(c,true);
    p=prepared.Tx.SSBPowerReferenceContract;
    assert(p.Available && p.SSPBCHBlockPower_dBm==expected);
    assert(p.PhysicalDevicePowerClaim==physical && prepared.PowerContext.PhysicalDevicePowerClaim==physical);
    indices=double(prepared.Tx.SSBBurstPlan.ActiveSSBIndices0Based);
    for index=indices(:).'
        [grid,sync]=sixgr.phy.dl.SSB_Rx(prepared.TransmitSamples,prepared.Config, ...
            'SampleRate_Hz',prepared.SampleRateHz,'CandidateSSBIndex',index);
        % MATLAB OFDM demodulation is the unnormalized FFT. Input is sqrt(mW).
        re=reshape(grid,240*4,[]); re=re(nrSSSIndices,:)/double(sync.Nfft);
        measured=10*log10(mean(sum(abs(double(re)).^2,2)));
        assert(abs(measured-p.SSPBCHBlockPower_dBm)<1e-6, ...
            'Actual SSS EPRE %.12g differs from declared %.12g dBm.',measured,p.SSPBCHBlockPower_dBm);
    end
    received=sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
        prepared.TransmitSamples,prepared.ReceiverConfig,'CandidateSSBIndex',indices(1));
    assert(received.DLSCHCrcPass && received.SIB1ASN1DecodeOk, ...
        'Power-contract test must recover and parse real SIB1 payload.');
    [ue,rows]=sixgr.mac.ra.installDecodedSIB1RACHConfig(c,received);
    assert(ue.UECommonCellConfiguration.SSPBCHBlockPower_dBm==p.SSPBCHBlockPower_dBm);
    assert(ue.random_access.ss_pbch_block_power_dbm==p.SSPBCHBlockPower_dBm);
    row=rows(rows.Parameter=="ss_pbch_block_power_dbm",:);
    assert(height(row)==1 && strlength(row.PayloadHash)>0 && row.Source=="SIB1.servingCellConfigCommon.ss-PBCH-BlockPower");
    fprintf('SSB_POWER_REFERENCE: physical_device_power=%d, actual/decoded SSS=%g dBm, %d beams\n',physical,p.SSPBCHBlockPower_dBm,numel(indices));
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testSSBPowerReferenceContract:MissingRejection','Expected %s.',id);
end
