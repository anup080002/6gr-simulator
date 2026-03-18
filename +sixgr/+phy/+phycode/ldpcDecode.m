function [decCB, actNumIter, finalParityChecks] = ldpcDecode(llr, bgn, maxNumIter, algorithm)
%ldpcDecode LDPC decode rate-recovered soft bits (5G Toolbox wrapper).
%
%   [decCB, actNumIter, finalParityChecks] = sixgr.phy.phycode.ldpcDecode(llr, bgn)
%   [decCB, actNumIter, finalParityChecks] = sixgr.phy.phycode.ldpcDecode(llr, bgn, maxNumIter)
%   [decCB, actNumIter, finalParityChecks] = sixgr.phy.phycode.ldpcDecode(llr, bgn, maxNumIter, algorithm)
%
%   This is a thin wrapper around nrLDPCDecode (5G Toolbox).
%
%   Inputs:
%     llr        : N-by-C soft bits (LLR). double/single recommended.
%     bgn        : Base graph number (1 or 2).
%     maxNumIter : Maximum decoder iterations (default 12).
%     algorithm  : Optional string/char forwarded as:
%                  nrLDPCDecode(...,'Algorithm',algorithm)
%                  Example: "Normalized min-sum" (default in 5G Toolbox).
%
%   Outputs:
%     decCB            : K-by-C decoded code blocks.
%     actNumIter       : Actual number of iterations for each code block.
%     finalParityChecks: Parity check results for each iteration.
%
%   See also nrLDPCDecode, sixgr.phy.phycode.rateRecoverLDPC

    if nargin < 2
        error('sixgr:phy:ldpcDecode:InvalidInput','llr and bgn are required.');
    end
    if nargin < 3 || isempty(maxNumIter)
        maxNumIter = 12;
    end
    if nargin < 4
        algorithm = '';
    end

    validateattributes(bgn, {'numeric'}, {'scalar','finite','integer'}, mfilename, 'bgn', 2);
    if ~(bgn==1 || bgn==2)
        error('sixgr:phy:ldpcDecode:InvalidBGN','bgn must be 1 or 2.');
    end
    validateattributes(maxNumIter, {'numeric'}, {'scalar','finite','integer','positive'}, mfilename, 'maxNumIter', 3);

    if exist('nrLDPCDecode','file') ~= 2
        error('sixgr:Missing5GToolbox', ...
            'nrLDPCDecode not found. Install/enable 5G Toolbox.');
    end

    % Normalize shape: allow vector input for single CB
    if isvector(llr)
        llr = llr(:);
    end

    % Normalize type
    if ~isa(llr,'double') && ~isa(llr,'single')
        llr = double(llr);
    end

    if ~isempty(algorithm)
        if isstring(algorithm), algorithm = char(algorithm); end
        [decCB, actNumIter, finalParityChecks] = nrLDPCDecode(llr, bgn, maxNumIter, 'Algorithm', algorithm);
    else
        [decCB, actNumIter, finalParityChecks] = nrLDPCDecode(llr, bgn, maxNumIter);
    end
end
