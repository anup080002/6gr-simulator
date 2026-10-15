function ok=testDetectorConstellationLayerCoordinates()
% Received codeword streams must align with exported layer coordinates.
% Deterministic symbol-domain fixtures; not waveform or BLER qualification.
setup6GRSimToolkit('Verbose',false);
count=0;
for direction=["DL","UL"]
    for rank=[1 2 4 5 8]
        ref=nrSymbolModulate(int8(mod((0:16*rank*4-1).',2)),'16QAM');
        ref=reshape(ref,16,rank);
        % Distinct values expose both interleaving and missing-codeword bugs.
        detector=reshape((1:numel(ref)).',size(ref))*(.001+.002i)+ref;
        codewords=nrLayerDemap(detector);
        cfg=struct();
        tx=struct('LayerSymbolDomain','layer');
        rx=struct('LayerEqualizedSymbolsForEvidence',ref, ...
            'EqualizedSymbolDomain','layer');
        if direction=="DL"
            tx.PDSCH=struct('Modulation','16QAM');
            tx.PDSCHLayerSymbolsForEvidence=ref;
            rx.PDSCHRxSymbols=codewords{1};
            if rank>4, rx.DemappedCodewordSymbolsForEvidence=codewords; end
        else
            tx.PUSCH=struct('Modulation','16QAM');
            tx.PUSCHLayerSymbolsForEvidence=ref;
            rx.PUSCHRxSymbolsForEvidence=codewords;
        end
        [metrics,samples]=sixgr.link.deriveModulationTrackingMetrics(tx,rx,cfg,direction);
        assert(metrics.EVM_rms==0, 'Detector reordering must not change the equalizer/EVM plane.');
        actual=complex(samples.DetectorOutputReal,samples.DetectorOutputImag);
        assert(isequal(actual,detector(:)) && all(samples.DetectorOutputInputDomain=="codeword") && ...
            all(samples.DetectorOutputStatus=="received_codeword_symbols_mapped_to_layer_coordinates"));
        if direction=="DL" && rank>4
            legacy=rmfield(rx,'DemappedCodewordSymbolsForEvidence');
            [~,old]=sixgr.link.deriveModulationTrackingMetrics(tx,legacy,cfg,direction);
            assert(all(isnan(old.DetectorOutputReal)) && ...
                all(old.DetectorOutputStatus=="unavailable_legacy_capture_missing_second_codeword"));
        end
        broken=rx;
        bad=codewords; bad{end}=bad{end}(1:end-1);
        broken.DemappedCodewordSymbolsForEvidence=bad;
        localReject(@()sixgr.link.deriveModulationTrackingMetrics(tx,broken,cfg,direction), ...
            'sixgr:link:DetectorSymbolCountMismatch');
        bad=codewords; bad{1}(end)=NaN;
        broken.DemappedCodewordSymbolsForEvidence=bad;
        localReject(@()sixgr.link.deriveModulationTrackingMetrics(tx,broken,cfg,direction), ...
            'sixgr:link:InvalidDetectorSymbolEvidence');
        count=count+1;
    end
end
ok=true;
fprintf('DETECTOR_CONSTELLATION_LAYER_COORDINATES_PASS cases=%d\n',count);
end

function localReject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
