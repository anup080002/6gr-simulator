function tf=isAppliedChannelReference(r)
% Accept only explicitly identified executed-channel scoring representations.
source=string(sixgr.util.structGet(r,'Source',''));
tf=isscalar(source) && source=="same_executed_NR_channel_path_gains_and_filters";
if isscalar(source) && source=="executed_fixed_matrix_AWGN_operator"
    H=sixgr.util.structGet(r,'SpatialMatrix',[]);
    n=sixgr.util.structGet(r,'NumTransmitAntennas',NaN);
    nr=sixgr.util.structGet(r,'NumReceiveAntennas',NaN);
    gains=sixgr.util.structGet(r,'PathGains',[]);
    tf=isnumeric(H) && isequal(size(H),[nr n]) && all(isfinite(H),'all') && ...
        isequal(sixgr.util.structGet(r,'PathFilters',[]),1) && ...
        isequal(sixgr.util.structGet(r,'NormalizeChannelOutputs',true),false) && ...
        isequal(sixgr.util.structGet(r,'NormalizePathGains',true),false) && ...
        isequal(sixgr.util.structGet(r,'ReceiverEstimatorInput',true),false) && ...
        isequal(sixgr.util.structGet(r,'AdditionalChannelExecutions',NaN),0) && ...
        ~isempty(gains) && size(gains,2)==1 && size(gains,3)==n && size(gains,4)==nr;
    if tf
        tf=all(gains==reshape(H.',[1 1 n nr]),'all');
    end
    return;
end
if tf || ~isscalar(source) || source~="executed_identity_AWGN_operator", return; end
required={'NumTransmitAntennas','NumReceiveAntennas','PathGains','PathFilters', ...
    'NormalizeChannelOutputs','NormalizePathGains','ReceiverEstimatorInput', ...
    'AdditionalChannelExecutions'};
if ~all(isfield(r,required)), return; end
n=r.NumTransmitAntennas;
tf=isnumeric(n) && isscalar(n) && isfinite(n) && n>=1 && n==fix(n) && ...
    isequal(n,r.NumReceiveAntennas) && isequal(r.PathFilters,1) && ...
    ~r.NormalizeChannelOutputs && ~r.NormalizePathGains && ...
    ~r.ReceiverEstimatorInput && r.AdditionalChannelExecutions==0 && ...
    size(r.PathGains,2)==1 && size(r.PathGains,3)==n && size(r.PathGains,4)==n;
if ~tf, return; end
for tx=1:n
    for rx=1:n
        if ~all(r.PathGains(:,1,tx,rx)==double(tx==rx),'all')
            tf=false; return;
        end
    end
end
end
