function cfgOut = attachFixedLinkRuntimeAntennaContext(cfgIn, userIndex, numUsers)
%ATTACHFIXEDLINKRUNTIMEANTENNACONTEXT Build same-flow fixed-link antenna objects.
%
% Fixed-SNR/SINR execution has no geometry/drop runtime, but its PHY and RF
% paths still require concrete BS/UE antenna objects.  Reuse the canonical
% CoupledTruthRuntime antenna factory with deliberately undefined positions;
% do not create a second antenna model and do not imply geometry evidence.

arguments
    cfgIn (1,1) struct
    userIndex (1,1) double {mustBeInteger,mustBePositive} = 1
    numUsers (1,1) double {mustBeInteger,mustBePositive} = 1
end

if userIndex > numUsers
    error("sixgr:truth:FixedLinkRuntimeAntennaUserIndexOutOfRange", ...
        "Fixed-link antenna user index %d exceeds the configured user count %d.", ...
        userIndex, numUsers);
end

layout = struct();
layout.bs = struct( ...
    "pos_m", nan(1, 3), ...
    "azim_deg", NaN);
ue = struct( ...
    "pos_m", nan(numUsers, 3), ...
    "heading_deg", nan(numUsers, 1));

[bsRuntime, ueRuntime] = ...
    sixgr.truth.CoupledTruthRuntime.buildRuntimeAntennaStateForFixedLink( ...
    cfgIn, layout, ue);
if isempty(bsRuntime) || numel(ueRuntime) < userIndex
    error("sixgr:truth:FixedLinkRuntimeAntennaInitializationFailed", ...
        "The canonical antenna factory did not return the required BS/UE runtime objects.");
end

bsEntry = bsRuntime(1);
ueEntry = ueRuntime(userIndex);
bsMeta = sixgr.util.structGet(bsEntry, "Metadata", struct());
ueMeta = sixgr.util.structGet(ueEntry, "Metadata", struct());
configSource = "master_yaml_to_buildInternalConfig_to_fixed_link_runtime";
objectSource = "attachFixedLinkRuntimeAntennaContext:AntennaArrayFactory.build";
bsMeta.AntennaConfigSource = configSource;
ueMeta.AntennaConfigSource = configSource;
bsMeta.RuntimeObjectSource = objectSource;
ueMeta.RuntimeObjectSource = objectSource;

cfgOut = cfgIn;
userMeta = sixgr.util.structGet(cfgOut, "lls6g.userContext", struct());
if ~(isstruct(userMeta) && isscalar(userMeta))
    userMeta = struct();
end
userMeta.RuntimeServingCell = 1;
userMeta.RuntimeServingCellID = 1;
userMeta.RuntimeUEIndex = double(userIndex);
userMeta.RuntimeServingBSAntenna = sixgr.util.structGet(bsEntry, "Antenna", struct());
userMeta.RuntimeServingBSAntennaMeta = bsMeta;
userMeta.RuntimeUEAntenna = sixgr.util.structGet(ueEntry, "Antenna", struct());
userMeta.RuntimeUEAntennaMeta = ueMeta;
userMeta.RuntimeAntennaConfigSource = configSource;
userMeta.RuntimeAntennaObjectSource = objectSource;
userMeta.RuntimeAntennaGeometrySource = ...
    "fixed_link_no_geometry:attachFixedLinkRuntimeAntennaContext";
userMeta.RuntimeSameFlowEvidenceSource = ...
    "attachFixedLinkRuntimeAntennaContext->active_link_waveform";
userMeta.RuntimeChannelArrayModel = char( ...
    sixgr.truth.CoupledTruthRuntime.resolveChannelArrayModelRuntime(cfgOut));
cfgOut = sixgr.util.structSet(cfgOut, "lls6g.userContext", userMeta);
end
