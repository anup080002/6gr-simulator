function [enc, info] = polarEncode(msg, E, direction, varargin)
%polarEncode  NR Polar coding wrapper for control channels (DCI/UCI) or raw polar.
%   [ENC,INFO] = polarEncode(MSG,E,DIRECTION,...) encodes the input bits MSG
%   and returns rate-matched coded bits ENC of length E.
%
%   This wrapper intentionally uses the 5G Toolbox high-level encoders when
%   available, because they include the required CRC attachment/masking and
%   rate matching steps for NR control channels:
%     - DIRECTION="DL": uses nrDCIEncode (PDCCH/DCI style)
%     - DIRECTION="UL": uses nrUCIEncode (PUCCH/PUSCH-UCI style)
%     - DIRECTION="RAW": uses nrPolarEncode (expects MSG already includes any CRC)
%
%   Optional arguments:
%     DIRECTION="DL" : polarEncode(MSG,E,"DL",RNTI)
%     DIRECTION="UL" : polarEncode(MSG,E,"UL",MODULATION)  % e.g. "QPSK"
%     DIRECTION="RAW": polarEncode(MSG,E,"RAW",NMAX,IIL)   % NMAX=9/10, IIL=true/false
%
%   Notes:
%     * If you pass only the DCI payload bits (e.g. 32 bits), do NOT call
%       nrPolarEncode directly; use nrDCIEncode so the 24-bit CRC is added.
%
%   See also: nrDCIEncode, nrUCIEncode, nrPolarEncode, nrRateMatchPolar

%#codegen

    arguments
        msg {mustBeVector}
        E (1,1) {mustBeInteger, mustBePositive}
        direction {mustBeTextScalar}
    end
    arguments (Repeating)
        varargin
    end

    % Force column vector
    msg = msg(:);

    dir = upper(string(direction));
    info = struct();
    info.Direction = char(dir);
    info.E = double(E);
    info.K = double(numel(msg));

    switch dir
        case "DL"
            % Downlink control: DCI -> CRC(24) -> polar -> rate match
            if exist("nrDCIEncode","file") ~= 2
                error("sixgr:polarEncode:MissingFunction", ...
                    "nrDCIEncode not found. Install/enable 5G Toolbox.");
            end
            if ~isempty(varargin)
                rnti = varargin{1};
            else
                rnti = 0; % default (caller should override for realistic runs)
            end
            % nrDCIEncode inherits output type from MSG
            [enc, maskedCRC] = nrDCIEncode(msg, rnti, E);
            info.Method = "nrDCIEncode";
            info.RNTI = double(rnti);
            info.MaskedCRC = maskedCRC;

        case "UL"
            % Uplink control: UCI -> (seg/CRC/coding/rate match internally)
            if exist("nrUCIEncode","file") ~= 2
                error("sixgr:polarEncode:MissingFunction", ...
                    "nrUCIEncode not found. Install/enable 5G Toolbox.");
            end
            if ~isempty(varargin)
                mod = varargin{1};
            else
                mod = "QPSK"; % default
            end
            enc = nrUCIEncode(msg, E, mod);
            info.Method = "nrUCIEncode";
            info.Modulation = char(string(mod));

        case "RAW"
            % Raw polar coding (expects MSG already includes CRC if required)
            if exist("nrPolarEncode","file") ~= 2
                error("sixgr:polarEncode:MissingFunction", ...
                    "nrPolarEncode not found. Install/enable 5G Toolbox.");
            end
            if numel(varargin) >= 1 && ~isempty(varargin{1})
                nmax = varargin{1};
            else
                nmax = 9; % downlink default
            end
            if numel(varargin) >= 2 && ~isempty(varargin{2})
                iil = varargin{2};
            else
                iil = true; % downlink default
            end
            enc = nrPolarEncode(msg, E, nmax, iil);
            info.Method = "nrPolarEncode";
            info.nMax = double(nmax);
            info.iIL = logical(iil);

        otherwise
            error("sixgr:polarEncode:BadDirection", ...
                "direction must be 'DL', 'UL', or 'RAW'.");
    end

    enc = enc(:);
end
