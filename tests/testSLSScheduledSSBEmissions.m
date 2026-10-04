function ok=testSLSScheduledSSBEmissions()
% Native source/clock/MIB checks only. No network or acquisition acceptance.
cfg=sixgr.config.defaultConfig();
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/native_ssb_emission.yaml'));
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',30, ...
    'NCellID',1,'centerFrequency_Hz',4e9);
cfg.phy.frequencyRange='FR1'; cfg.frequency.band_context='n77';
cfg.frequency.spectrum='unpaired'; cfg.initial_access.enabled=false;
cfg.phy.duplex.mode='TDD';
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('D',10,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("DL",10,14);
cfg.phy.ssb=struct('enable',true,'blockPattern','Case C','Lmax',8, ...
    'scs_kHz',30,'periodicity_ms',5,'halfFrameIndex',0, ...
    'NCRBSSB',0,'KSSB',0,'activeBitmap',[1 1 1 1 0 0 0 0], ...
    'perSSBPower_dB',[0 -3 0 -3 0 0 0 0], ...
    'precoderMatrices',repmat([1 1;1 -1]/sqrt(2),4,1));
cfg.phy.pbch.enable=true;
cfg.phy.mib=struct('pdcchConfigSIB1',17,'dmrsTypeAPosition',2, ...
    'cellBarred',true,'intraFreqReselection',false);
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.ssbCellIDs=[11 37];
state=struct('TTI',1,'AbsoluteSlot0',0, ...
    'LargeScaleState',struct('TxPower_dBm',[30 27;30 27]));
base=sixgr.system.abstraction.buildScheduledSSBEmissions(cfg,state);
assert(numel(base)==4 && isequal([base.SSBIndex0],[0 1 0 1]));
for slot=[0 1 10 320 20480]
    state.TTI=slot+1; state.AbsoluteSlot0=slot;
    emitted=sixgr.system.abstraction.buildScheduledSSBEmissions(cfg,state);
    assert(numel(emitted)==4);
    for e=emitted
        expectedSFN=mod(floor(slot/20),1024); expectedHalf=mod(floor(slot/10),2);
        assert(e.SystemFrameNumber==expectedSFN && e.HalfFrameBit==expectedHalf);
        assert(~e.ReceptionQualified && isequal(e.BlockSymbols0Based,0:3));
        assert(numel(e.Symbols)==830 && isequal(e.Precoder.',cfg.phy.ssb.precoderMatrices(e.SSBIndex0+1,:)));
        % Restore the actual emitted source block, then independently decode
        % PBCH. The expected payload is not supplied to either decoder.
        localSymbols=mod(2+6*mod(e.SSBIndex0,2)+(0:3),14);
        block=complex(zeros(240,4));
        [found,col]=ismember(e.Coordinates0Based(:,2),localSymbols);
        assert(all(found));
        ix=sub2ind([240 4],e.Coordinates0Based(:,1)+1,col);
        block(ix)=e.Symbols;
        assert(isequal(block(nrPSSIndices),nrPSS(mod(e.NCellID,3))) && ...
            isequal(block(nrSSSIndices),nrSSS(e.NCellID)));
        soft=nrPBCHDecode(block(nrPBCHIndices(e.NCellID)),e.NCellID,mod(e.SSBIndex0,8),1);
        [~,crc,bits,lsb,half]=nrBCHDecode(soft,8,e.Lmax,e.NCellID);
        assert(crc==0 && isequal(double(bits(:)),double(e.MIBTransportBits(:))) && half==expectedHalf);
        decoded=sixgr.phy.ia.MIBSemanticValidator.decodeBits(bits(2:end));
        assert(decoded.SystemFrameNumberMSB6==floor(expectedSFN/16) && ...
            sum(double(lsb(:)).*2.^(3:-1:0).')==mod(expectedSFN,16) && ...
            decoded.PDCCHConfigSIB1==17 && decoded.CellBarred=="notbarred");
        physical=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
        expectedEPRE=10^((state.LargeScaleState.TxPower_dBm(1,e.ServingCellID)-30)/10)/288 * ...
            10^(cfg.phy.ssb.perSSBPower_dB(e.SSBIndex0+1)/10);
        assert(max(abs(sum(abs(physical).^2,2)-expectedEPRE))<1e-14);
    end
end
state.TTI=3; state.AbsoluteSlot0=2;
assert(isempty(sixgr.system.abstraction.buildScheduledSSBEmissions(cfg,state)));
state.TTI=11; state.AbsoluteSlot0=10;
slow=cfg; slow.phy.ssb.periodicity_ms=20;
assert(isempty(sixgr.system.abstraction.buildScheduledSSBEmissions(slow,state)));
off=cfg; off.phy.ssb.enable=false;
assert(isempty(sixgr.system.abstraction.buildScheduledSSBEmissions(off,state)));
state.TTI=1; state.AbsoluteSlot0=0;
shifted=cfg; shifted.phy.ssb.halfFrameIndex=1;
assert(isempty(sixgr.system.abstraction.buildScheduledSSBEmissions(shifted,state)));
bad=cfg; bad.phy.mib=rmfield(bad.phy.mib,'pdcchConfigSIB1');
reject(@()sixgr.system.abstraction.buildScheduledSSBEmissions(bad,state),'sixgr:abstraction:SSBEmissionMIB');
bad=cfg; bad.system.linkAbstraction.networkSpatial.ssbCellIDs=[11 1008];
reject(@()sixgr.system.abstraction.buildScheduledSSBEmissions(bad,state),'sixgr:abstraction:SSBEmissionIdentity');
bad=cfg; bad.system.linkAbstraction.networkSpatial.bsPorts=3;
reject(@()sixgr.system.abstraction.buildScheduledSSBEmissions(bad,state),'sixgr:abstraction:SSBEmissionBeam');
bad=cfg; bad.phy.pbch.enable=false;
reject(@()sixgr.system.abstraction.buildScheduledSSBEmissions(bad,state),'sixgr:abstraction:SSBEmissionPBCH');
fprintf('SLS_SSB_SOURCE_PASS native_BCH_decode=1 SFN_wrap=1 half_frame=1 beams_power=1 network_qualified=0\n');
ok=true;
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'%s',cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
