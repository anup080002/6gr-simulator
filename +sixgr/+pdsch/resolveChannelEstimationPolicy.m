function [method,window] = resolveChannelEstimationPolicy(method,window)
% Validate receiver-owned policy; never substitute LS for another request.
method=lower(strtrim(string(method)));
if ~isscalar(method) || ismissing(method) || strlength(method)==0
    error('sixgr:pdsch:PDSCHReceiver:InvalidChannelEstimationMethod', ...
        'ChannelEstimationMethod must be one nonempty method name.');
end
switch method
    case {"ls","least_squares","least-squares"}
        method="LS";
    case {"wiener","wiener_interpolation","wiener_interpolated"}
        method="wiener";
    case {"lmmse","full_covariance_lmmse","wiener_lmmse","wiener-full-covariance"}
        method="lmmse";
    otherwise
        error('sixgr:pdsch:PDSCHReceiver:InvalidChannelEstimationMethod', ...
            ['Unsupported PDSCH channel-estimation method %s. Use LS, wiener ' ...
             'or lmmse. Ideal channels require the separate explicit oracle-test interface.'],method);
end
if ~isnumeric(window) || ~isreal(window) || ~isvector(window) ...
        || numel(window)~=2 || any(~isfinite(window)) ...
        || any(window<0 | (window~=0 & mod(window,2)~=1))
    error('sixgr:pdsch:PDSCHReceiver:InvalidChannelEstimationAveragingWindow', ...
        ['PDSCH channel-estimation averaging window must contain [frequency,time] ' ...
         'nonnegative integers, each zero (automatic) or odd.']);
end
window=double(window(:).');
if method~="LS" && any(window~=0)
    error('sixgr:pdsch:PDSCHReceiver:ConflictingChannelEstimationWindow', ...
        'Explicit averaging windows require Method=LS; other methods own their filtering.');
end
end
