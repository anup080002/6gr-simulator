function ok=testSSBFrequencyTranslationPhase()
% Native SSB TX/acquisition phase-plane regression; no RF/channel execution.
% These are single-port, noiseless component controls, not band-raster,
% fading, receiver-accuracy, shared-stream or full-scenario qualification.
% A nonzero placement is a deterministic frequency translation, not CFO.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng;
restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
parent=fullfile(pwd,'results','validation','ssb_frequency_translation_phase');
if ~isfolder(parent), mkdir(parent); end
folder=tempname(parent); mkdir(folder);
fprintf('SSB_FREQUENCY_TRANSLATION_PHASE artifacts=%s\n',folder);

% Centered controls first; the 30-kHz -150-kHz case has the current n40
% Point-A placement (NCRBSSB=30,KSSB=2), without its 64-element/RF/channel.
cases=[15 0;30 0;30 -150e3;30 150e3;15 -150e3;15 150e3];
rows=struct([]);
for ci=1:size(cases,1)
    scs=cases(ci,1); offset=cases(ci,2);
    cfg=localConfig(scs,offset);
    receiverTiming=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
    [wave,waveInfo,tx]=sixgr.phy.dl.SSB_Tx(cfg,'NumSubframes',2,'SSBIndex',0);
    assert(size(wave,2)==1 && tx.OFDMWindowingSamples==0);
    assert(receiverTiming.Lmax==cfg.phy.ssb.Lmax && ...
        receiverTiming.BandAwareResolution.BandContext==string(cfg.frequency.band_context) && ...
        receiverTiming.BandAwareResolution.Spectrum==string(cfg.frequency.spectrum) && ...
        isequaln(receiverTiming.BandAwareResolution,tx.SSBTiming.BandAwareResolution), ...
        'sixgr:test:SSBBandBinding','TX and RX must use the same explicit NR band/duplex context.');
    fs=double(tx.SampleRate_Hz);
    originalGrid=waveInfo.SSBComposite.TransmitPortResourceGrid;
    firstSymbol=double(tx.SSBTiming.CandidateStartSymbolsWithinHalfFrame(1));
    transmitted=originalGrid(:,firstSymbol+(1:4),1);
    assert(isequal(size(transmitted),[240 4]) && nnz(transmitted)>0);
    n=(0:size(wave,1)-1).';
    for injectedHz=[0 400]
        % Declared deterministic sample rotation, not a simulated RF stage.
        % The receiver receives only samples and its configured search policy.
        received=wave.*exp(2i*pi*injectedHz*n/fs);
        [actual,sync]=sixgr.phy.dl.SSB_Rx(received,cfg, ...
            'SampleRate_Hz',fs,'CandidateSSBIndex',0);
        [pbch,~]=sixgr.phy.dl.PBCH_Recovery(actual,sync,cfg);
        assert(pbch.Ok && pbch.BCHCRCValid && pbch.CandidateIdentityConsistent && ...
            pbch.NCellID==tx.NCellID && pbch.SSBIndex==0 && ...
            sync.SSBCenterFrequencyOffsetHz==offset && ...
            sync.SSBPlacementCorrectionAppliedHz==-offset && ...
            sync.CFOCorrectionApplied && sync.CFOCorrectionSampleOrigin==0 && ...
            sync.CFOCorrectionApplied_Hz==sync.FreqOffset_Hz);

        % Independent native demodulation of the ORIGINAL corrected samples.
        % A continuous translation by -offset changes the symbol-phase
        % reference from f_carrier to f_carrier+offset. No phase/gain fitting,
        % truth-aided acquisition, altered received grid or new waveform.
        [proper,legacy,phase]=localNativeReferences(received,sync);
        residual=sixgr.phy.broadcast.measurePBCHResidualFrequency(actual,sync,pbch);
        properResidual=sixgr.phy.broadcast.measurePBCHResidualFrequency(proper,sync,pbch);
        legacyResidual=sixgr.phy.broadcast.measurePBCHResidualFrequency(legacy,sync,pbch);
        assert(residual.PBCHResidualFrequencyAvailable && ...
            properResidual.PBCHResidualFrequencyAvailable && ...
            legacyResidual.PBCHResidualFrequencyAvailable);
        evidence=jsondecode(residual.PBCHResidualFrequencyEvidenceJSON);

        % Numerical acceptance scales with the native GHz phase argument
        % and FFT arithmetic, not with the observed erroneous residual.
        phaseArgument=2*pi*(abs(tx.CarrierFrequency_Hz)+abs(offset))*size(wave,1)/fs;
        phaseRoundoff=64*eps(max(1,phaseArgument))+ ...
            128*eps*(1+log2(double(sync.Nfft)));
        gridTolerance=8*phaseRoundoff;
        dt=min(double(evidence.PairTimeSeparations_s));
        frequencyTolerance=8*phaseRoundoff/(2*pi*dt);
        actualError=localRelativeError(actual,transmitted);
        nativeError=localRelativeError(proper,transmitted);
        legacyError=localRelativeError(legacy,transmitted);
        pilotIndices=double(nrPBCHDMRSIndices(pbch.NCellID));
        pilotPhase=angle(actual(pilotIndices).*conj(transmitted(pilotIndices)));
        row=struct('SCS_kHz',scs,'SSBCenterOffset_Hz',offset, ...
            'InjectedRotation_Hz',injectedHz,'OriginalCFOEstimate_Hz',sync.FreqOffset_Hz, ...
            'OriginalAppliedCFO_Hz',sync.CFOCorrectionApplied_Hz, ...
            'ActualPhaseReference_Hz',sync.SymbolPhaseCompensationCarrierFrequencyHz, ...
            'RequiredPhaseReference_Hz',tx.CarrierFrequency_Hz+offset, ...
            'GridRelativeError',actualError,'NativeReferenceRelativeError',nativeError, ...
            'UntranslatedPhaseReferenceRelativeError',legacyError, ...
            'PBCHResidualCommonFrequency_Hz',residual.PBCHResidualCommonFrequency_Hz, ...
            'NativeReferenceResidual_Hz',properResidual.PBCHResidualCommonFrequency_Hz, ...
            'UntranslatedPhaseReferenceResidual_Hz',legacyResidual.PBCHResidualCommonFrequency_Hz, ...
            'MaximumPilotPhaseError_rad',max(abs(pilotPhase)), ...
            'GridRoundoffBound',gridTolerance,'FrequencyRoundoffBound_Hz',frequencyTolerance, ...
            'Passed',false,'RFExecuted',false,'ChannelExecuted',false);
        row.Passed=sync.SymbolPhaseCompensationCarrierFrequencyHz==row.RequiredPhaseReference_Hz && ...
            actualError<=gridTolerance && nativeError<=gridTolerance && ...
            localRelativeError(actual,proper)<=gridTolerance && ...
            abs(sync.FreqOffset_Hz-injectedHz)<=frequencyTolerance && ...
            abs(residual.PBCHResidualCommonFrequency_Hz)<=frequencyTolerance && ...
            abs(properResidual.PBCHResidualCommonFrequency_Hz)<=frequencyTolerance;
        if offset~=0
            % A genuine negative control: original-carrier phase reversal
            % must differ after the mixer, while proper reversal restores TX.
            row.Passed=row.Passed && legacyError>100*gridTolerance && ...
                abs(legacyResidual.PBCHResidualCommonFrequency_Hz)>100*frequencyTolerance;
        else
            row.Passed=row.Passed && legacyError<=gridTolerance;
        end
        artifact=fullfile(folder,sprintf('scs_%d_offset_%+d_cfo_%d.mat',scs,offset,injectedHz));
        save(artifact,'row','cfg','tx','wave','received','transmitted','actual', ...
            'proper','legacy','sync','pbch','residual','properResidual', ...
            'legacyResidual','phase','pilotPhase','-v7.3');
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        fprintf('SSB_TRANSLATION_CASE scs=%g offset=%g cfo=%g residual=%g native_residual=%g legacy_residual=%g grid_error=%.9g pass=%d\n', ...
            scs,offset,injectedHz,row.PBCHResidualCommonFrequency_Hz, ...
            row.NativeReferenceResidual_Hz,row.UntranslatedPhaseReferenceResidual_Hz, ...
            row.GridRelativeError,row.Passed);
    end
end
save(fullfile(folder,'case_summary.mat'),'rows');
assert(numel(rows)==12 && all([rows.Passed]), ...
    'sixgr:test:SSBFrequencyTranslationPhase', ...
    'The original SSB receiver must restore the translated symbol-phase plane; see %s.',folder);
ok=true;
fprintf('PASS testSSBFrequencyTranslationPhase: six native TX/twelve actual acquisitions; no RF/channel/accuracy qualification.\n');
end

function cfg=localConfig(scs,offset)
cfg=sixgr.config.defaultConfig();
cfg.run.strictMode=true;
if scs==15
    nrb=25; bandwidth=5; frequency=2.14e9; pattern='Case A'; lmax=4;
    band='n1'; spectrum='paired'; duplex='FDD';
else
    nrb=51; bandwidth=20; frequency=2.35e9; pattern='Case C'; lmax=8;
    band='n40'; spectrum='unpaired'; duplex='TDD';
end
% resolveFromConfig deliberately ignores disabled initial-access defaults.
% Declare the same active band authority for the direct TX and RX APIs;
% neither may fall back to paired-spectrum frequency-only compatibility.
cfg.initial_access.enabled=true;
cfg.initial_access.band_context=band; cfg.initial_access.spectrum=spectrum;
cfg.frequency.band_name=band; cfg.frequency.band_context=band;
cfg.frequency.spectrum=spectrum; cfg.frequency.range_name='FR1';
cfg.phy.frequencyRange='FR1'; cfg.phy.duplex.mode=duplex;
cfg.phy.carrier.NCellID=17;
cfg.phy.carrier.NStartGrid=0; cfg.phy.carrier.NSizeGrid=nrb;
cfg.phy.carrier.SubcarrierSpacing=scs; cfg.phy.carrier.SubcarrierSpacing_kHz=scs;
cfg.phy.carrier.CyclicPrefix='normal'; cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.carrier.centerFrequency_Hz=frequency;
cfg.phy.bwp.dl.NStartBWP=0; cfg.phy.bwp.dl.NSizeBWP=nrb;
cfg.phy.channelBandwidth_MHz=bandwidth; cfg.frequency.bandwidth_hz=bandwidth*1e6;
cfg.phy.ssb.enable=true; cfg.phy.pbch.enable=true;
cfg.phy.ssb.scs_kHz=scs; cfg.phy.ssb.blockPattern=pattern; cfg.phy.ssb.Lmax=lmax;
cfg.phy.ssb.activeBitmap=[true false(1,lmax-1)];
cfg.phy.ssb.halfFrameIndex=0; cfg.phy.ssb.periodicity_ms=20;
lowUnits=(6*nrb*scs*1e3-120*scs*1e3+offset)/15e3;
assert(lowUnits>=0 && lowUnits==fix(lowUnits));
cfg.phy.ssb.NCRBSSB=floor(lowUnits/12); cfg.phy.ssb.KSSB=mod(lowUnits,12);
cfg.phy.sync.cfoHypothesesHz=0;
cfg.phy.sync.fineCFOEnabled=true; cfg.phy.sync.fineCFOMethod='cyclic_prefix';
cfg.phy.sync.fineCFOMaxResidualHz=1000; cfg.phy.sync.fineCFOMinimumSymbols=4;
end

function [proper,legacy,phase]=localNativeReferences(received,sync)
fs=double(sync.SampleRate_Hz); n=(0:size(received,1)-1).';
corrected=received.*exp(-2i*pi*double(sync.SSBCenterFrequencyOffsetHz)*n/fs);
corrected=corrected.*exp(-2i*pi*double(sync.CFOCorrectionApplied_Hz)*n/fs);
columns=double(sync.SSBSymbolColumnsOneBased);
prefix=sum(double(sync.Nfft)+double(sync.CyclicPrefixLengthsPerSlot(1:columns(1)-1)));
first=1+double(sync.AppliedTimingCorrection_samples)-prefix;
assert(first>=1 && first==fix(first),'This zero-delay component has no missing capture prefix.');
carrier=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',sync.SCS_SSB_kHz, ...
    'NSlot',sync.DemodulationSlot,'NCellID',sync.NCellID);
base=double(sync.SSBTiming.CarrierFrequencyHz);
properFrequency=base+double(sync.SSBCenterFrequencyOffsetHz);
proper=nrOFDMDemodulate(carrier,corrected(first:end,:), ...
    'Nfft',sync.Nfft,'SampleRate',fs,'CarrierFrequency',properFrequency, ...
    'CyclicPrefixFraction',0.5);
legacy=nrOFDMDemodulate(carrier,corrected(first:end,:), ...
    'Nfft',sync.Nfft,'SampleRate',fs,'CarrierFrequency',base, ...
    'CyclicPrefixFraction',0.5);
proper=proper(:,columns,:); legacy=legacy(:,columns,:);
phase=struct('Source',"independent_native_demodulation_of_original_corrected_samples", ...
    'OriginalCarrierFrequency_Hz',base,'TranslatedCarrierFrequency_Hz',properFrequency, ...
    'FirstSample1Based',first,'AcquiredSymbolColumns1Based',columns, ...
    'GainOrPhaseFitted',false,'TransmittedReferenceUsedByReceiver',false);
end

function value=localRelativeError(actual,expected)
assert(isequal(size(actual),size(expected)));
value=norm(double(actual(:))-double(expected(:)))/norm(double(expected(:)));
end
