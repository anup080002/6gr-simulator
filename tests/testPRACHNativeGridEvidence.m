function ok=testPRACHNativeGridEvidence()
% Actual PRACH generation/FFT/export; not a main access/receiver qualification.
setup6GRSimToolkit('Verbose',false);
root=tempname; mkdir(root);
cases={"TDD",157,30,25; "FDD",16,1.25,25};
for ci=1:size(cases,1)
    mode=cases{ci,1}; index=cases{ci,2}; scs=cases{ci,3}; nrb=cases{ci,4};
    resolved=sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
        'FrequencyRange','FR1','DuplexMode',mode,'ConfigurationIndex',index, ...
        'CarrierSubcarrierSpacingKHz',15,'NSizeGrid',nrb,'PRACHSubcarrierSpacingKHz',scs, ...
        'SequenceIndex',0,'PreambleIndex',0,'RestrictedSet','UnrestrictedSet', ...
        'ZeroCorrelationZone',0,'Msg1FDM',1);
    row=resolved.Occasions(1,:);
    originSlot=double(row.AbsoluteSlot);
    occasion=struct('Carrier',struct('SubcarrierSpacing',15,'NSizeGrid',nrb, ...
        'NSlot',row.SlotWithinFrame,'NCellID',1,'NStartGrid',0,'CyclicPrefix','normal'), ...
        'PRACH',struct('FrequencyRange','FR1','DuplexMode',mode,'ConfigurationIndex',index, ...
        'SubcarrierSpacing',scs,'SequenceIndex',0,'PreambleIndex',0,'RestrictedSet','UnrestrictedSet', ...
        'ZeroCorrelationZone',0,'FrequencyStart',0,'NPRACHSlot',row.PRACHSlot, ...
        'ActivePRACHSlot',row.ActivePRACHSlot,'TimeIndex',row.TimeIndex,'FrequencyIndex',row.FrequencyIndex));
    for ports=[1 2]
        tx=sixgr.rach.generatePRACHWaveform(struct('NumTxAntennas',ports),'Occasion',occasion);
        T=sixgr.truth.buildObservedREAllocation(tx,'Channel','PRACH','Direction','UL', ...
            'AbsoluteSlot',originSlot,'CellID',1,'UEID',1);
        assert(all(T.grid_domain=="prach_native_ofdm") && all(T.active_flag) && all(isnan(T.layer_count)));
        assert(all(T.waveform_hash_plane=="prach_generator_before_preamble_power_control_spatial_mapping_and_rf") && ...
            all(T.waveform_sha256==string(sixgr.phy.waveform.WaveformHash.numeric(tx.Waveform))));
        assert(sum(T.re_count)==nnz(tx.WaveformPortResourceGrid) && numel(unique(T.port_index))==ports);
        assert(all(T.absolute_slot==originSlot) && all(T.frequency_first_hz== ...
            (T.subcarrier_start-size(tx.Grid,1)/2)*scs*1000));
        [carrierRows,native]=sixgr.truth.splitREAllocationDomains(T);
        assert(isempty(carrierRows) && height(native)==height(T) && ...
            ~ismember('symbol_index',native.Properties.VariableNames));
        % Independently inspect FFT bins at the exported useful intervals.
        for s=unique(T.symbol_index).'
            one=T(find(T.symbol_index==s,1),:); nfft=tx.OFDMInfo.Nfft;
            samples=tx.Waveform(one.useful_start_sample_relative+(1:nfft),:);
            spectrum=fftshift(fft(samples,nfft,1),1);
            active=abs(spectrum)>max(abs(spectrum),[],'all')*1e-9;
            expected=false(nfft,ports); k=size(tx.Grid,1);
            assert(mod(k,2)==0,'This FFT fixture uses even native-grid sizes.');
            expected((nfft-k)/2+(1:k),:)=reshape(tx.WaveformPortResourceGrid(:,s+1,:)~=0,k,ports);
            assert(isequal(active,expected),'Exported native bins disagree with actual useful-symbol FFT support.');
        end
        folder=fullfile(root,sprintf('%s_ports%d',mode,ports)); mkdir(folder);
        % Explicit component identity hashes the actual generator inputs.
        inputs=struct('GeneratorConfig',struct('NumTxAntennas',ports),'Occasion',occasion);
        context=struct('run',struct('scenarioID',sprintf('native_PRACH_%s_%d_ports_component',mode,ports)), ...
            'meta',struct('configHash',sixgr.lls6g.config.hashResolvedScenario(inputs)));
        layout=verifyObservedREPublication(T,context,folder);
        [status,message]=system(sprintf('python "%s" "%s"', ...
            fullfile(pwd,'tests','verify_native_prach_publication.py'),layout.ReportCSVDir));
        assert(status==0,'Native producer/CSV/PNG failed: %s',message); fprintf('%s',message);
        bad=tx; bad.OFDMInfo.SymbolLengths(1)=bad.OFDMInfo.SymbolLengths(1)+1;
        localReject(@()sixgr.truth.buildObservedREAllocation(bad,'Channel','PRACH','Direction','UL','AbsoluteSlot',originSlot), ...
            'sixgr:truth:PRACHNativeTimingMismatch');
        bad=rmfield(tx,'WaveformHashPlane');
        localReject(@()sixgr.truth.buildObservedREAllocation(bad,'Channel','PRACH','Direction','UL','AbsoluteSlot',originSlot), ...
            'sixgr:truth:MissingPRACHWaveformHashPlane');
        bad=tx; bad.Indices=double(bad.Indices); bad.Indices(1)=bad.Indices(1)+.5;
        localReject(@()sixgr.truth.executedPRACHNativeGrid(bad),'sixgr:truth:InvalidPRACHNativeIndices');
        bad=tx; bad.WaveformPortResourceGrid(1)=1;
        localReject(@()sixgr.truth.executedPRACHNativeGrid(bad),'sixgr:truth:PRACHWaveformPortMappingMismatch');
        if ports==2
            % Declared spatial-mapping component input; not a main beam or
            % propagation measurement. Check the retained applied mapping,
            % including an explicitly unexcited physical output port.
            mapped=tx; matrix=[1 0;0 1i;0 0];
            mapped.TransmitProjectionMatrix=matrix;
            mapped.TransmitProjectionMatrixSHA256=sixgr.phy.mimo.MatrixContract.digest(matrix);
            g=tx.WaveformPortResourceGrid;
            mapped.TransmitPortResourceGrid=reshape(reshape(g,[],2)*cast(matrix,'like',g).',size(g,1),size(g,2),3);
            [physical,domain]=sixgr.truth.executedPRACHNativeGrid(mapped);
            assert(isequaln(physical,mapped.TransmitPortResourceGrid) && ...
                ~any(physical(:,:,3),'all') && startsWith(domain,'physical_antenna'));
            bad=mapped; bad.TransmitProjectionMatrixSHA256=repmat('0',1,64);
            localReject(@()sixgr.truth.executedPRACHNativeGrid(bad),'sixgr:truth:PRACHSpatialAuthorityMismatch');
            bad=mapped; bad.TransmitPortResourceGrid(1)=1;
            localReject(@()sixgr.truth.executedPRACHNativeGrid(bad),'sixgr:truth:PRACHSpatialGridMismatch');
        end
    end
end
ok=true; fprintf('PRACH_NATIVE_GRID_EVIDENCE_PASS: %s\n',root);
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier); return;
end
error('test:MissingNativePRACHRejection','Invalid native evidence was accepted.');
end
