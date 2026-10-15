function ok=testPBCHResidualFrequency()
% Independent OFDM modulation/injected-frequency check, not BLER qualification.
setup6GRSimToolkit('Verbose',false);
rows=struct([]);
for nfft=[512 4096]
    for firstSymbol=[2 8 12] % Include unequal CP and a slot boundary.
        carrier=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',30,'NCellID',17,'NSlot',1);
        fs=nfft*30e3;
        columns=firstSymbol+(1:4);
        grid=complex(zeros(240,14*ceil(columns(end)/14)));
        block=complex(zeros(240,4));
        block(nrPBCHDMRSIndices(17))=nrPBCHDMRS(17,3);
        grid(:,columns)=block;
        wave=nrOFDMModulate(carrier,grid,'Nfft',nfft,'SampleRate',fs,'Windowing',0);
        % Actual sample-wise frequency injection and compensation. No
        % injected frequency is passed to the receiver measurement.
        time=(0:size(wave,1)-1).'/fs;
        sync=struct('NCellID',17,'SCS_SSB_kHz',30,'SampleRate_Hz',fs, ...
            'Nfft',nfft,'DemodulationSlot',1,'SSBSymbolColumnsOneBased',columns, ...
            'CFOCorrectionApplied_Hz',300);
        pbch=struct('Ok',true,'ErrFlag',0,'NCellID',17,'iBar_SSB',3);
        for injected=[0 400 600]
            corrected=(wave.*exp(2i*pi*injected*time)).*exp(-2i*pi*300*time);
            received=[corrected .7i*corrected];
            rx=nrOFDMDemodulate(carrier,received,'Nfft',nfft,'SampleRate',fs);
            evidence=sixgr.phy.broadcast.measurePBCHResidualFrequency(rx(:,columns,:),sync,pbch);
            assert(evidence.PBCHResidualFrequencyAvailable && ...
                abs(evidence.PBCHResidualCommonFrequency_Hz-(injected-300))<1, ...
                'sixgr:test:PBCHResidualFrequency', ...
                'Expected residual %g Hz; measured %g Hz.',injected-300,evidence.PBCHResidualCommonFrequency_Hz);
            assert(~evidence.PBCHResidualFrequencyIndependentCapture && ...
                contains(evidence.PBCHResidualFrequencyRole,'not_oscillator_only'));
            clock=jsondecode(evidence.PBCHResidualFrequencyEvidenceJSON);
            assert(clock.SampleRate_Hz==fs && clock.NumReferenceRE==144 && ...
                clock.NumSymbolPairsUsed==3 && clock.NumCommonRESamplesUsed==216);
            % Poisoned simulation metadata and a calibrated amplitude
            % change cannot become frequency-estimation authority.
            poisoned=sync; poisoned.InjectedCFO_Hz=1e6;
            poisoned.CFOCorrectionApplied_Hz=-9999;
            repeated=sixgr.phy.broadcast.measurePBCHResidualFrequency(rx(:,columns,:)*1e-9,poisoned,pbch);
            assert(abs(repeated.PBCHResidualCommonFrequency_Hz-evidence.PBCHResidualCommonFrequency_Hz)<1e-8);
            row=struct('Nfft',nfft,'SampleRateHz',fs, ...
                'FirstSymbolZeroBased',firstSymbol,'InjectedCFO_Hz',injected, ...
                'AppliedCorrection_Hz',300,'MeasuredResidualCommonFrequency_Hz', ...
                evidence.PBCHResidualCommonFrequency_Hz);
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
        rejected=pbch; rejected.Ok=false; rejected.ErrFlag=1;
        failed=sixgr.phy.broadcast.measurePBCHResidualFrequency(rx(:,columns,:),sync,rejected);
        assert(~failed.PBCHResidualFrequencyAvailable && isnan(failed.PBCHResidualCommonFrequency_Hz));
        noEnergy=sixgr.phy.broadcast.measurePBCHResidualFrequency(zeros(240,4,2),sync,pbch);
        assert(~noEnergy.PBCHResidualFrequencyAvailable && isnan(noEnergy.PBCHResidualCommonFrequency_Hz));
    end
end
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
sixgr.util.csvWriteTable(fullfile(folder,'pbch_residual_frequency.csv'),struct2table(rows),'PreserveSchema',true);
fprintf('PBCH_RESIDUAL_FREQUENCY_PASS waveform_cases=%d evidence=%s\n',numel(rows),folder);
ok=true;
end
