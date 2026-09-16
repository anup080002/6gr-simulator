function ok=testNormalizedSSBPowerMath()
% Independent generated SSB-grid powers; no scenario or detector retuning.
setup6GRSimToolkit('Verbose',false);
cfg.integration.run_mode='FIXED_SNR_SWEEP';
cfg.integration.configured_snr_is_link_authority=true;
ncell=17; sss=nrSSSIndices;
stream=RandStream('mt19937ar','Seed',1987);
for nfft=[512 1024]
    carrier=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',15,'NCellID',ncell);
    for amplitude=[0.25 1]
        grid=complex(zeros(240,4,2));
        for branch=1:2
            plane=complex(zeros(240,4));
            plane(nrPSSIndices)=nrPSS(ncell);
            plane(sss)=nrSSS(ncell);
            plane(nrPBCHIndices(ncell))=nrPBCH(zeros(864,1),ncell,0);
            plane(nrPBCHDMRSIndices(ncell))=nrPBCHDMRS(ncell,0);
            grid(:,:,branch)=plane*amplitude*branch/2;
        end
        noise=amplitude*sqrt(0.01/2)*complex(randn(stream,size(grid)),randn(stream,size(grid)));
        grid=grid+noise;
        [wave,info]=nrOFDMModulate(carrier,grid,'Nfft',nfft,'Windowing',0);
        received=nrOFDMDemodulate(carrier,wave,'Nfft',nfft);
        assert(max(abs(received(:)-grid(:)))<1e-10);
        scale=double(info.Nfft)*sqrt(1000);
        measured=sixgr.phy.refsig.measureSSSINRFromSSBGrid(received/scale,ncell,0);
        unitMeasured=sixgr.phy.refsig.measureSSSINRFromSSBGrid(received,ncell,0);
        [window,windowEvidence]=sixgr.phy.refsig.measureSSBWindowPower(received/scale,ncell,0,15);
        assert(measured.Available && unitMeasured.Available);
        raw=struct('SSPhysicalMeasurementStatus',"available_rsrp_and_sinr", ...
            'SSMeasurementFFTSize',nfft,'SSMeasurementGridScaleToSqrtW',scale, ...
            'SS_RSRP_dBm',measured.NoiseDebiasedSS_RSRP_dBm, ...
            'SS_RSRPRawObserved_dBm',measured.RawObservedSS_RSRP_dBm, ...
            'SS_RSRPPerReceiveAntenna_dBm',token(measured.NoiseDebiasedSS_RSRPPerReceiveAntenna_dBm), ...
            'SS_RSRPRawObservedPerReceiveAntenna_dBm',token(measured.RawObservedSS_RSRPPerReceiveAntenna_dBm), ...
            'SSBWindowRSSIPerReceiveAntenna_dBm',token(window.RSSIPerAntenna), ...
            'SSBWindowPowerMeasurementJSON',string(jsonencode(windowEvidence)), ...
            'SSSINRDesiredPowerPerReceiveAntenna_W',token(measured.DesiredPowerPerReceiveAntenna_W), ...
            'SSSINRNoiseInterferencePowerPerReceiveAntenna_W',token(measured.NoiseInterferencePowerPerReceiveAntenna_W), ...
            'SS_SINR_dB',measured.SS_SINR_dB,'BCHCrcPass',true);
        out=sixgr.link.normalizeReceivedSSBPowerReference(raw,cfg);
        expectedRaw=zeros(1,2);
        for branch=1:2
            plane=received(:,:,branch); expectedRaw(branch)=10*log10(mean(abs(plane(sss)).^2));
        end
        fprintf('SSB_UNIT_GRID Nfft=%d amplitude=%g raw_RSRP_actual=%g expected=%g\n', ...
            nfft,amplitude,out.SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es,max(expectedRaw));
        assert(abs(out.SS_RSRPRawObserved_dB_re_UnitOccupiedRE_Es-max(expectedRaw))<1e-9, ...
            'test:NormalizedSSBPowerScale','SSB raw RSRP must match actual normalized SSS RE energy.');
        assert(abs(out.SS_RSRP_dB_re_UnitOccupiedRE_Es-(unitMeasured.NoiseDebiasedSS_RSRP_dBm-30))<1e-9);
        actualRSSI=values(out.SSBWindowRSSIPerReceiveAntenna_dB_re_UnitOccupiedRE_Es);
        expectedRSSI=10*log10(reshape(mean(sum(abs(received).^2,1),2),1,[]));
        assert(max(abs(actualRSSI-expectedRSSI))<1e-9);
        relativeWindow=jsondecode(out.SSBWindowRelativePowerMeasurementJSON);
        assert(out.SSBWindowPowerMeasurementJSON=="" && ...
            string(relativeWindow.Scope)==string(windowEvidence.Scope) && ...
            string(relativeWindow.AmplitudeUnit)=="sqrt_UnitOccupiedRE_Es");
        assert(~isfield(relativeWindow,'RSSIPerAntenna_dBm') && ...
            ~isfield(relativeWindow,'SymbolPowerPerAntenna_W'));
        assert(max(abs(relativeWindow.ReferenceRSRQPerAntenna_dB(:)-window.RSRQPerAntenna(:)))<1e-12);
        ratio=10*log10(relativeWindow.NumRB)+ ...
            relativeWindow.ReferenceRSRPPerAntenna_dB_re_UnitOccupiedRE_Es(:)- ...
            relativeWindow.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es(:);
        assert(max(abs(ratio-relativeWindow.ReferenceRSRQPerAntenna_dB(:)))<1e-4);
        assert(max(abs(relativeWindow.RSSIPerAntenna_dB_re_UnitOccupiedRE_Es(:)-expectedRSSI(:)))<1e-9);
        assert(max(abs(relativeWindow.SymbolPowerPerAntenna_UnitOccupiedRE_Es(:)- ...
            windowEvidence.SymbolPowerPerAntenna_W(:)*scale^2))<1e-9);
        assert(isequaln(relativeWindow.SymbolIndicesWithinSSB0Based(:),windowEvidence.SymbolIndicesWithinSSB0Based(:)));
        evidence=sixgr.link.ssbPowerReferenceEvidence(out);
        assert(evidence.SSBWindowRelativePowerMeasurementJSON==out.SSBWindowRelativePowerMeasurementJSON && ...
            max(abs(values(evidence.SSBWindowReferenceRSRQPerReceiveAntenna_dB)-window.RSRQPerAntenna(:).'))<1e-10);
        assert(out.SS_SINR_dB==raw.SS_SINR_dB && out.BCHCrcPass==raw.BCHCrcPass);
        desired=values(out.SSSINRDesiredPowerPerReceiveAntenna_UnitOccupiedRE_Es);
        disturbance=values(out.SSSINRNoiseInterferencePowerPerReceiveAntenna_UnitOccupiedRE_Es);
        assert(max(abs(desired-unitMeasured.DesiredPowerPerReceiveAntenna_W))<1e-10 && ...
            max(abs(disturbance-unitMeasured.NoiseInterferencePowerPerReceiveAntenna_W))<1e-10);
        assert(abs(max(10*log10(desired./disturbance))-out.SS_SINR_dB)<1e-9 && ...
            out.SSSINRDesiredPowerPerReceiveAntenna_W=="" && out.SSSINRNoiseInterferencePowerPerReceiveAntenna_W=="");
        assert(isnan(out.ReferenceSignalTxEPRE_dB_re_UnitOccupiedRE_Es) && ...
            string(sixgr.util.structGet(out,'ReferenceSignalTxMeasurementSource',""))=="");
        physical=cfg; physical.integration.configured_snr_is_link_authority=false;
        assert(isequaln(raw,sixgr.link.normalizeReceivedSSBPowerReference(raw,physical)));
    end
end
missing=raw; missing.SSBWindowPowerMeasurementJSON="";
missing=sixgr.link.normalizeReceivedSSBPowerReference(missing,cfg);
assert(missing.SSBWindowRelativePowerMeasurementJSON=="",'Missing window evidence must not be manufactured.');
broken=raw; invalid=windowEvidence; invalid.ReferenceRSRQPerAntenna_dB(1)=invalid.ReferenceRSRQPerAntenna_dB(1)+1;
broken.SSBWindowPowerMeasurementJSON=string(jsonencode(invalid));
rejected=false;
try, sixgr.link.normalizeReceivedSSBPowerReference(broken,cfg);
catch cause, rejected=string(cause.identifier)=="sixgr:link:SSBWindowRSRQClosure"; end
assert(rejected,'Mismatched RSRQ operands must fail instead of being copied as valid evidence.');
ok=true; disp('NORMALIZED_SSB_POWER_MATH_PASS RSRP_RSSI_linear_disturbance_and_SINR=1');
end
function out=token(input)
out=strjoin(compose('%.15g',double(input(:).')),'|');
end
function out=values(input)
out=str2double(split(string(input),'|')).';
end
