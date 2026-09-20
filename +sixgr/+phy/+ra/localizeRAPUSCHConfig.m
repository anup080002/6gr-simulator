function cfgOut=localizeRAPUSCHConfig(cfg,raCfg,grant,absoluteSlot,stage)
% Keep initial-access PUSCH coding separate from connected-data MCS policy.
if nargin<5, stage="Msg3"; end
switch string(stage)
    case "Msg3"
        validateattributes(grant.MCS,{'numeric'},{'real','scalar','finite','integer','>=',0,'<=',15});
        installed=raCfg.Msg3PUSCH;
        mismatch='sixgr:phy:ra:Msg3MCSContextMismatch';
        rankMatches=isequal(double(grant.NLayers),1);
    case "RRCSetupComplete"
        installed=raCfg.SetupCompletePUSCH;
        mismatch='sixgr:phy:ra:RRCSetupMCSContextMismatch';
        rankMatches=isequal(double(grant.NLayers),double(installed.NLayers)) && ...
            isequal(double(grant.MCS),double(installed.MCS)) && ...
            isequal(logical(grant.TransformPrecoding),logical(installed.TransformPrecoding));
    otherwise
        error('sixgr:phy:ra:InvalidPUSCHStage','Use Msg3 or RRCSetupComplete.');
end
profile=sixgr.phy.ul.pusch.PUSCHMCSResolver.resolve( ...
    installed.MCSTable,grant.MCS,grant.TransformPrecoding);
assert(string(grant.MCSTable)==profile.MCSTable && ...
    string(grant.Modulation)==profile.Modulation && ...
    isequal(double(grant.TargetCodeRate),profile.TargetCodeRate) && ...
    rankMatches, mismatch, ...
    'Initial-access PUSCH table, modulation, rate and rank must retain their stage context.');
cfgOut=sixgr.phy.ra.localizeCarrierConfig(cfg,raCfg,absoluteSlot);
cfgOut.phy.pusch.mcsTable=char(profile.MCSTable);
cfgOut.phy.pusch.mcsIndex=double(grant.MCS);
cfgOut.phy.pusch.modulation=char(profile.Modulation);
cfgOut.phy.pusch.targetCodeRate=profile.TargetCodeRate;
cfgOut.phy.pusch.numLayers=double(grant.NLayers);
cfgOut.phy.pusch.transformPrecoding=logical(grant.TransformPrecoding);
end
