function ok=testPUSCHTransmitterPrecoderEvidence()
% Analytical metadata contract; actual waveform coverage is a separate test.
for ports=[1 2 4]
    pusch=nrPUSCHConfig('TransmissionScheme','codebook','NumLayers',1, ...
        'NumAntennaPorts',ports,'TPMI',0,'TransformPrecoding',false);
    W=nrPUSCHCodebook(1,ports,0,false).';
    prec=struct('Source',"analytic_contract_fixture_not_runtime_output", ...
        'Mode',"ul_codebook_tpmi",'ApplicationStage',"unit_contract", ...
        'Active',true,'ExplicitBeamWeightsApplied',false,'TransformPrecodingApplied',false, ...
        'BeamformingApplied',true,'NativeCodebookApplied',true, ...
        'PMI',0,'PMIType',"pusch_codebook",'CodebookMode',string(pusch.CodebookType), ...
        'MatrixPorts',W,'MatrixLogicalPorts',W,'NumPorts',ports,'NumLogicalPorts',ports,'NumLayers',1, ...
        'MatrixRows',ports,'MatrixCols',1,'BeamIndices',[], ...
        'CodebookPortIndices1Based',find(sum(abs(W).^2,2)>0).', ...
        'CodebookPortIndexDefinition',"one_based_logical_antenna_port_support_not_spatial_beam_ID");
    tx=struct('PUSCH',pusch,'PrecodeInfo',prec);
    good=sixgr.phy.ul.validatePUSCHPrecoderEvidence(tx);
    assert(good.AppliedMatrixSHA256==string(sixgr.phy.mimo.MatrixContract.digest(W)));
    assert(isempty(good.BeamIndices) && ~isempty(good.CodebookPortIndices1Based));
    bad=tx; bad.PrecodeInfo.PMI=1;
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:TransmitterPrecoderMismatch');
    bad=tx; bad.PrecodeInfo.MatrixLogicalPorts=2*W;
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:TransmitterPrecoderMismatch');
    bad=tx; bad.PrecodeInfo.CodebookPortIndices1Based=[];
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:TransmitterPrecoderMismatch');
    bad=tx; bad.PrecodeInfo.BeamformingApplied=NaN;
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:TransmitterPrecoderMismatch');
    bad=tx; bad.PrecodeInfo.AppliedMatrixSHA256=repmat('a',1,64);
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:TransmitterPrecoderMismatch');
    bad=tx; bad.PrecodeInfo=rmfield(prec,'Source');
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:MissingTransmitterPrecoderEvidence');
    bad=rmfield(tx,'PrecodeInfo');
    bad.Grant=struct('AppliedPrecoderPMI',0,'BeamformingApplied',true, ...
        'AppliedPrecoderSHA256',good.AppliedMatrixSHA256);
    localThrows(@()sixgr.phy.ul.validatePUSCHPrecoderEvidence(bad),'sixgr:phy:ul:MissingTransmitterPrecoderEvidence');
end
ok=true;
end

function localThrows(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s',id,cause.identifier);
    return;
end
error('sixgr:test:MissingExpectedFailure','Expected %s',id);
end
