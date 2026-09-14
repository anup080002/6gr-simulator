function ok=testTransmitPowerEvidence(outputRoot,applyFn,bindFn)
% Numerical/export regression, not an end-to-end radio qualification.
if nargin<1 || strlength(string(outputRoot))==0, outputRoot=tempname; end
if nargin<2, applyFn=@sixgr.rf.applyPowerContext; end
if nargin<3, bindFn=@sixgr.report.bindTransmitPowerEvidence; end
if ~isfolder(outputRoot), mkdir(outputRoot); end
carrier=nrCarrierConfig('NSizeGrid',25);
grid=complex(zeros(300,14)); grid(1:12,:)=1;
[wave,ofdm]=sixgr.phy.waveform.ofdmModulate(carrier,grid);
txInfo=struct('OFDM',ofdm,'PortGrid',grid);
% Same sparse-grid numerical fixture as testRAStagePowerEvidence.
cfg=struct('powerAndRF',struct('bsTxPower_dBm',30,'ueTxPower_dBm',23, ...
    'downlinkPowerNormalizationPolicy',"fixed_epre_over_configured_bwp"));
rows=struct([]);
for normalized=[false,true]
    cfg.integration.run_mode="GEOMETRY_NETWORK";
    cfg.integration.configured_snr_is_link_authority=normalized;
    if normalized, cfg.integration.run_mode="FIXED_SNR_SWEEP"; end
    for direction=["DL","UL"]
        [beforeWave,beforeContext]=sixgr.rf.applyPowerContext(wave,cfg,direction,txInfo,'ApplyPA',false);
        [afterWave,context]=applyFn(wave,cfg,direction,txInfo,'ApplyPA',false);
        assert(isequaln(beforeWave,afterWave),'Waveform samples must be unchanged.');
        oldNames=fieldnames(beforeContext);
        for j=1:numel(oldNames)
            assert(isequaln(beforeContext.(oldNames{j}),context.(oldNames{j})),oldNames{j});
        end
        assert(context.FixedSNRNormalizedReference==normalized);
        assert(context.PhysicalDevicePowerClaim==~normalized);
        contextBefore=context;
        % Deliberately distinct replay-ledger value: do not replace it with
        % a TX-context value when moving it to the relative reference column.
        replayValue=context.TotalTxPower_dBm-3;
        inputRow=struct('Direction',direction,'PowerContextTotalTxPower_dBm',replayValue, ...
            'ReceiverNoiseVariance',0.125,'MeasuredEVM',0.031);
        row=bindFn(inputRow,context);
        assert(isequaln(contextBefore,context));
        assert(row.ReceiverNoiseVariance==inputRow.ReceiverNoiseVariance && row.MeasuredEVM==inputRow.MeasuredEVM);
        assert(row.TransmitPowerEvidenceAvailable && row.TransmitPowerPhysicalApplicable==~normalized);
        targets=["ReferenceInputPower","ReferenceOutputPower","ActualEmittedPower"];
        sources=["ReferenceInputPower_dBm","ReferenceOutputPower_dBm","OutputTotalPower_dBm"];
        for j=1:3
            absolute=row.(targets(j)+"_dBm");
            relative=row.(targets(j)+"_dB_re_UnitOccupiedRE_Es");
            if normalized
                assert(isnan(absolute) && relative==context.(sources(j)));
            else
                assert(isnan(relative) && absolute==context.(sources(j)));
            end
        end
        if normalized
            assert(isequaln(afterWave,wave) && ~context.ScaleApplied);
            assert(isnan(row.PowerContextTotalTxPower_dBm));
            assert(row.PowerContextTotalTxPower_dB_re_UnitOccupiedRE_Es==replayValue);
            assert(row.TransmitPowerReferencePlane=="normalized_fixed_esn0_unit_occupied_re_es");
        else
            assert(row.PowerContextTotalTxPower_dBm==replayValue);
            assert(isnan(row.PowerContextTotalTxPower_dB_re_UnitOccupiedRE_Es));
            measured=sixgr.rf.measureActiveOFDMTotalPower(afterWave,txInfo);
            assert(abs(10*log10(measured)-row.ActualEmittedPower_dBm)<1e-10);
            if direction=="DL"
                assert(abs(row.ReferenceOutputPower_dBm-30)<1e-10);
                assert(abs(row.ActualEmittedPower_dBm-(30+10*log10(1/25)))<1e-10);
            else
                assert(abs(row.ActualEmittedPower_dBm-23)<1e-10);
            end
        end
        if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    end
end
T=struct2table(rows);
csvPath=fullfile(outputRoot,'numerical_power_export.csv');
writetable(T,csvPath);
R=readtable(csvPath,'TextType','string');
assert(height(R)==4 && isequal(R.Properties.VariableNames,T.Properties.VariableNames));
for name=string(T.Properties.VariableNames)
    if isnumeric(T.(name)) || islogical(T.(name))
        actual=double(R.(name)); expected=double(T.(name));
        assert(isequal(isnan(actual),isnan(expected)),name);
        finite=isfinite(expected);
        assert(all(abs(actual(finite)-expected(finite))<1e-10),name);
    else
        assert(isequal(string(R.(name)),string(T.(name))),name);
    end
end
emptyRow=bindFn(struct(),struct());
assert(~emptyRow.TransmitPowerEvidenceAvailable && ~emptyRow.TransmitPowerPhysicalApplicable);
assert(emptyRow.TransmitPowerReferencePlane=="unavailable");
emptyTable=struct2table(repmat(emptyRow,0,1));
assert(height(emptyTable)==0 && width(emptyTable)==numel(fieldnames(emptyRow)));
localReject(@()bindFn(struct(),rmfield(context,'PhysicalDevicePowerClaim')), ...
    'sixgr:report:MissingTransmitPowerDomain');
bad=context; bad.PhysicalDevicePowerClaim=NaN;
localReject(@()bindFn(struct(),bad),'sixgr:report:InvalidTransmitPowerDomain');
bad=context; bad.PhysicalDevicePowerClaim=true;
localReject(@()bindFn(struct(),bad),'sixgr:report:ConflictingTransmitPowerDomain');
bad=context; bad.PowerNormalizationPolicy="fixed_epre_over_configured_bwp";
localReject(@()bindFn(struct(),bad),'sixgr:report:ConflictingTransmitPowerDomain');
bad=context; bad.FixedSNRReferenceEnergyPerOccupiedRE=2;
localReject(@()bindFn(struct(),bad),'sixgr:report:UnsupportedNormalizedPowerReference');
bad=context; bad.OutputTotalPower_dBm=Inf;
localReject(@()bindFn(struct(),bad),'sixgr:report:InvalidTransmitPowerValue');
bad=context; bad.ReferenceInputPower_dBm=[1,2];
localReject(@()bindFn(struct(),bad),'sixgr:report:InvalidTransmitPowerValue');
bad=context; bad.OutputTotalPower_dBm=NaN;
missing=bindFn(struct(),bad);
assert(~missing.TransmitPowerEvidenceAvailable && isnan(missing.ActualEmittedPower_dB_re_UnitOccupiedRE_Es));
cfg.rf.pa.enable=true;
localReject(@()applyFn(wave,cfg,"UL",txInfo),'sixgr:rf:FixedSNRAbsolutePAReferenceUnsupported');
save(fullfile(outputRoot,'numerical_power_export.mat'),'rows','wave','afterWave','context','cfg','txInfo');
fprintf('TRANSMIT_POWER_EXPORT_PASS: physical/normalized DL/UL, unchanged samples/context fields, CSV, empty schema and negative guards.\n');
ok=true;
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier),'Unexpected error: %s',cause.identifier);
    return;
end
error('test:MissingError','Expected %s.',identifier);
end
