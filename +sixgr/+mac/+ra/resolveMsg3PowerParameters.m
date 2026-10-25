function p = resolveMsg3PowerParameters(cfg)
%RESOLVEMSG3POWERPARAMETERS RAR PUSCH j=0, not connected PUSCH policy.
% TS 38.213 V18.8.0 7.1.1: P0UE=0; absent Msg3 offset=0, alpha=1.
ra = sixgr.util.structGet(cfg,"random_access",struct());
target = sixgr.util.structGet(ra,"preamble_received_target_power_dbm",NaN);
validateattributes(target,{'numeric'},{'real','scalar','finite'});
common = sixgr.util.structGet(cfg,"UECommonCellConfiguration",struct());
if ~(isstruct(common)&&isscalar(common))
    error('sixgr:mac:ra:InvalidReceivedPowerConfiguration','Common configuration must be one installed structure.');
end
received=string(sixgr.util.structGet(ra,"binding_source",""))=="decoded_sib1_rach_config_common";
if received && ~isfield(common,'PUSCHConfigCommon')
    error('sixgr:mac:ra:MissingReceivedPowerConfiguration','Received SIB1 must retain PUSCH common presence/absence.');
end
if isfield(common,'PUSCHConfigCommon')
    % An installed received tree owns presence as well as value. Do not
    % resurrect a stale preconfigured offset when the received IE is absent.
    node=common.PUSCHConfigCommon;
    if ~(isstruct(node)&&isscalar(node))
        error('sixgr:mac:ra:InvalidReceivedPowerConfiguration','PUSCH common presence must be a scalar structure.');
    end
    raw=sixgr.util.structGet(node,"msg3_DeltaPreamble",0);
    validateattributes(raw,{'numeric'},{'real','scalar','finite','integer','>=',-1,'<=',6});
    delta=2*double(raw); % TS 38.331 PUSCH-ConfigCommon: two-dB ASN.1 step.
    source="received_common_configuration";
else
    delta=sixgr.util.structGet(ra,"pusch_common_msg3_delta_preamble",0);
    source="configured_common_parameters";
end
validateattributes(delta,{'numeric'},{'real','scalar','finite'});
if ~ismember(double(delta),-2:2:12)
    error('sixgr:mac:ra:InvalidMsg3DeltaPreamble','Physical Msg3 offset must represent an ASN.1 two-dB step [-2,12].');
end
alpha=sixgr.util.structGet(ra,"msg3_alpha",1);
validateattributes(alpha,{'numeric'},{'real','scalar','finite'});
if ~ismember(double(alpha),[0 .4 .5 .6 .7 .8 .9 1])
    error('sixgr:mac:ra:InvalidMsg3Alpha','Msg3 alpha must be a supported NR alpha value.');
end
p=struct('P0Nominal_dBm',double(target)+double(delta),'P0UE_dB',0, ...
    'PreambleReceivedTargetPower_dBm',double(target),'DeltaPreambleMsg3_dB',double(delta), ...
    'Alpha',double(alpha),'ParameterSetIndex',0,'Source',source, ...
    'AlphaSource',"normative_absent_msg3_alpha_one");
if isfield(ra,'msg3_alpha')
    p.AlphaSource="configured_msg3_alpha";
end
end
