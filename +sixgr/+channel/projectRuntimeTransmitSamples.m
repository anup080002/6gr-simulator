function [samples,evidence]=projectRuntimeTransmitSamples(state,x)
%PROJECTRUNTIMETRANSMITSAMPLES Apply the materialized TX map before summation.
% This does not invoke, advance, reset or clone the physical channel.
arguments
    state (1,1) struct
    x {mustBeFloat,mustBeFinite}
end
if ~isfield(state,"ContractVersion") || ...
        ~logical(sixgr.util.structGet(state,"Initialized",false)) || ...
        ~logical(sixgr.util.structGet(state,"Materialized",false))
    error("ChannelFactory:UninitializedTransmitProjection", ...
        "Transmit projection requires the materialized runtime antenna authority.");
end
if ~ismatrix(x) || isempty(x)
    error("ChannelFactory:InvalidTransmitProjectionSamples","Provide a nonempty sample matrix.");
end
physical=double(sixgr.util.structGet(state,"NumTxAnt",NaN));
expanded=logical(sixgr.util.structGet(state,"ElementExpansionApplied",false));
expected=physical;
if expanded
    expected=double(sixgr.util.structGet(state,"ExternalLogicalTxPorts",NaN));
end
if ~isscalar(expected) || ~isfinite(expected) || expected<1 || ...
        expected~=fix(expected) || size(x,2)>expected
    error("ChannelFactory:RuntimeChannelDimensionChange", ...
        "Logical samples exceed the materialized antenna port capacity.");
end
padded=expected-size(x,2);
samples=[x zeros(size(x,1),padded,'like',x)];
matrixHash="";
if expanded
    matrix=sixgr.util.structGet(state,"PortToElementMatrix",[]);
    if ~isnumeric(matrix) || ~ismatrix(matrix) || ...
            ~isequal(size(matrix),[physical expected]) || any(~isfinite(matrix(:)))
        error("ChannelFactory:ElementExpansionDimensionMismatch", ...
            "The actual port-to-element matrix must match the materialized channel.");
    end
    if norm(matrix'*matrix-eye(expected),'fro')>1e-9*max(1,expected)
        error("ChannelFactory:NonPowerPreservingPortToElementMatrix", ...
            "The materialized port-to-element projection must preserve logical-port power.");
    end
    samples=samples*cast(matrix,'like',x).';
    matrixHash=string(sixgr.phy.mimo.MatrixContract.digest(matrix));
end
evidence=struct("Source","materialized_runtime_transmit_antenna_projection", ...
    "InputSampleDomain","logical_ports", ...
    "OutputSampleDomain","materialized_channel_ports", ...
    "ElementExpansionApplied",expanded,"LogicalInputColumns",size(x,2), ...
    "SilentLogicalPaddingColumns",padded,"ChannelInputColumns",size(samples,2), ...
    "ProjectionMatrixSHA256",matrixHash, ...
    "InputWaveformSHA256",string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(x)), ...
    "OutputWaveformSHA256",string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(samples)));
end
