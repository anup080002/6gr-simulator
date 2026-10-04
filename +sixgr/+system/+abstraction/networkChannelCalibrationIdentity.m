function identity=networkChannelCalibrationIdentity(cfg,channel)
%NETWORKCHANNELCALIBRATIONIDENTITY Physical native settings, not caller labels.
% Realization seed/time and path-vs-OFDM output selection are not the channel
% distribution. Preserve all other public native properties, including
% correlation, polarization, array patterns, angles and sampling policy.
assert(isa(channel,'nrTDLChannel') || isa(channel,'nrCDLChannel'), ...
    'sixgr:abstraction:NetworkChannelIdentity','Require the actual native fading object.');
properties=get(channel);
excluded={'Seed','RandomStream','InitialTime','ChannelFiltering','NumTimeSamples', ...
    'ChannelResponseOutput','PathGainsOutputPort'};
properties=rmfield(properties,intersect(fieldnames(properties),excluded));
properties=orderfields(properties);
p=cfg.system.linkAbstraction.networkSpatial;
basis=string(sixgr.util.structGet(p,'dlAntennaBasis','direct_ports'));
beamBases=[];
if basis=="configured_csirs_elements", beamBases=cfg.phy.csirs.precoderMatrices; end
identity=struct('Schema',"sixgr.network_native_channel_calibration/v3", ...
    'ResponsePlane',"nominal_fft_filter_trim_cp_fraction_0p5", ...
    'ChannelEvolution',"persistent_link_absolute_slot", ...
    'ChannelClock',"actual_cp_ofdm_symbol_boundary", ...
    'NativeClass',string(class(channel)),'NativeProperties',properties, ...
    'BSPorts',p.bsPorts,'UEPorts',p.uePorts, ...
    'ResourcePopulation',string(p.sinrResourcePopulation),'PowerPolicy',string(p.powerPolicy), ...
    'InterferencePopulation',string(p.interferencePopulation),'DLAntennaBasis',basis, ...
    'CSIBasesSHA256',sixgr.phy.mimo.MatrixContract.digest(beamBases));
if any(string(p.interferencePopulation)==["scheduled_shared_data_and_srs", ...
        "scheduled_shared_data_and_srs_and_csirs","scheduled_shared_data_and_srs_and_csirs_and_pdcch"])
    identity.SRSPowerPolicy=string(p.srsPowerPolicy);
    identity.SRSPhaseAssumption=string(p.srsPhaseAssumption);
    identity.SRSConfigurationSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(cfg.phy.srs)),'UTF-8'))));
    identity.SRSScenarioUEBindingsSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(sixgr.util.structGet(cfg, ...
        'lls6g.reference_signals.srs.ue_resource_bindings',[]))),'UTF-8'))));
end
if any(string(p.interferencePopulation)==["scheduled_shared_data_and_srs_and_csirs", ...
        "scheduled_shared_data_and_srs_and_csirs_and_pdcch"])
    identity.CSIRSPowerPolicy=string(p.csirsPowerPolicy);
    identity.CSIRSPhaseAssumption=string(p.csirsPhaseAssumption);
    identity.CSIRSScramblingIDs=double(p.csirsScramblingIDs);
    identity.CSIRSConfigurationSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(cfg.phy.csirs)),'UTF-8'))));
end
if string(p.interferencePopulation)=="scheduled_shared_data_and_srs_and_csirs_and_pdcch"
    identity.PDCCHPowerPolicy=string(p.pdcchPowerPolicy);
    identity.PDCCHPhaseAssumption=string(p.pdcchPhaseAssumption);
    identity.PDCCHBeamPolicy=string(p.pdcchBeamPolicy);
    identity.PDCCHScramblingIDs=double(p.pdcchScramblingIDs);
    identity.PDCCHPrecoderSHA256=string(sixgr.phy.mimo.MatrixContract.digest(p.pdcchPrecoderMatrices));
    identity.PDCCHConfigurationSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(cfg.phy.pdcch)),'UTF-8'))));
end
if logical(sixgr.util.structGet(p,'ssbInterferenceEnabled',false))
    identity.SSBInterferenceEnabled=true;
    identity.SSBPowerPolicy=string(p.ssbPowerPolicy);
    identity.SSBPhaseAssumption=string(p.ssbPhaseAssumption);
    identity.SSBBeamPolicy=string(p.ssbBeamPolicy);
    identity.SSBCellIDs=double(p.ssbCellIDs);
    ssbConfiguration=struct('SSB',cfg.phy.ssb,'PBCH',cfg.phy.pbch,'MIB',cfg.phy.mib);
    identity.SSBConfigurationSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(ssbConfiguration)),'UTF-8'))));
end
if logical(sixgr.util.structGet(p,'pucchInterferenceEnabled',false))
    identity.PUCCHInterferenceEnabled=true;
    identity.PUCCHPowerPolicy=string(p.pucchPowerPolicy);
    identity.PUCCHPhaseAssumption=string(p.pucchPhaseAssumption);
    pucch=struct('PHY',cfg.phy.pucch,'Resources',cfg.validation.pucch_resources, ...
        'ControlAssumption',cfg.system.linkAbstraction.dynamicPUCCH);
    identity.PUCCHConfigurationSHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
        jsonencode(sixgr.util.jsonSafeValue(pucch)),'UTF-8'))));
end
identity.SHA256=string(sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(sixgr.util.jsonSafeValue(identity)),'UTF-8'))));
identity.ProfileID=string(channel.DelayProfile)+"_"+identity.SHA256;
end
