function out = BLER_DB(varargin)
%BLER_DB Build, normalize, or query context-aware BLER calibration database.
%
% Usage:
%   db = sixgr.system.BLER_DB("BLER", tensor, ...);
%   db = sixgr.system.BLER_DB("AllowSynthetic", true, ...); % explicit opt-in
%   db = sixgr.system.BLER_DB(existingStruct);
%   bler = sixgr.system.BLER_DB("query", db, ctx);

if nargin >= 1 && (ischar(varargin{1}) || isstring(varargin{1})) ...
        && strcmpi(string(varargin{1}), "query")
    if nargin < 3
        error("sixgr:system:BLER_DB:NeedArgs", "Query requires db and ctx.");
    end
    db = localNormalize(varargin{2});
    ctx = varargin{3};
    strictMode = false;
    if nargin >= 4
        strictMode = logical(varargin{4});
    end
    out = localQuery(db, ctx, strictMode);
    return;
end

if nargin == 1 && isstruct(varargin{1})
    out = localNormalize(varargin{1});
    return;
end

p = inputParser;
p.addParameter("SNR_dB", (-10:2:30).', @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
p.addParameter("Direction", ["DL","UL"], @(x)isstring(x)||ischar(x)||iscellstr(x));
p.addParameter("MCS", 0:27, @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
p.addParameter("PRB", [10 20 50 100], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
p.addParameter("Layers", [1 2 4], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
p.addParameter("SCS", [15 30 60 120], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
p.addParameter("DopplerHz", [0 30 70 300], @(x)isnumeric(x)&&isvector(x)&&~isempty(x));
p.addParameter("ChannelModel", ["AWGN","TDL-C","CDL-D"], @(x)isstring(x)||ischar(x)||iscellstr(x));
p.addParameter("BLER", [], @(x)isempty(x) || isnumeric(x));
p.addParameter("Source", "calibrated_db", @(x)ischar(x)||isstring(x));
p.addParameter("StrictMode", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
p.addParameter("AllowSynthetic", false, @(x)islogical(x)||(isnumeric(x)&&isscalar(x)));
p.parse(varargin{:});
R = p.Results;
strictBuild = logical(R.StrictMode);
allowSynthetic = logical(R.AllowSynthetic);

ax = struct();
ax.Direction = string(R.Direction(:).');
ax.MCS = double(R.MCS(:).');
ax.PRB = double(R.PRB(:).');
ax.Layers = double(R.Layers(:).');
ax.SCS = double(R.SCS(:).');
ax.DopplerHz = double(R.DopplerHz(:).');
ax.ChannelModel = upper(string(R.ChannelModel(:).'));
ax.SNR_dB = double(R.SNR_dB(:));

sz = [numel(ax.Direction), numel(ax.MCS), numel(ax.PRB), numel(ax.Layers), ...
      numel(ax.SCS), numel(ax.DopplerHz), numel(ax.ChannelModel), numel(ax.SNR_dB)];

if isempty(R.BLER)
    if strictBuild || ~allowSynthetic
        error("sixgr:system:BLER_DB:SyntheticDisabled", ...
            "Synthetic BLER_DB generation is disabled. Provide calibrated BLER tensor or set AllowSynthetic=true.");
    end
    B = zeros(sz);
    for iDir = 1:numel(ax.Direction)
        for iM = 1:numel(ax.MCS)
            for iP = 1:numel(ax.PRB)
                for iL = 1:numel(ax.Layers)
                    for iS = 1:numel(ax.SCS)
                        for iD = 1:numel(ax.DopplerHz)
                            for iC = 1:numel(ax.ChannelModel)
                                thr = -4 + 0.45*double(ax.MCS(iM)) + 0.08*double(ax.PRB(iP)) ...
                                    + 0.45*(double(ax.Layers(iL))-1) + 0.01*double(ax.DopplerHz(iD)) ...
                                    + 0.03*(double(ax.SCS(iS))-15);
                                if ax.Direction(iDir) == "UL"
                                    thr = thr - 0.35;
                                end
                                if ax.ChannelModel(iC) == "AWGN"
                                    thr = thr - 1.0;
                                elseif ax.ChannelModel(iC) == "CDL-D"
                                    thr = thr + 1.2;
                                end
                                bl = 1.0 ./ (1.0 + exp((ax.SNR_dB(:) - thr)/1.9));
                                bl = min(max(bl, 1e-4), 0.9999);
                                B(iDir,iM,iP,iL,iS,iD,iC,:) = reshape(bl, 1,1,1,1,1,1,1,[]);
                            end
                        end
                    end
                end
            end
        end
    end
else
    B = double(R.BLER);
    if ~isequal(size(B), sz)
        error("sixgr:system:BLER_DB:ShapeMismatch", "BLER tensor size mismatch with axes.");
    end
    B = min(max(B, 1e-4), 0.9999);
end

db = struct();
db.Axes = ax;
db.BLER = B;
if isempty(R.BLER)
    db.Source = "synthetic_db";
else
    db.Source = string(R.Source);
end
out = localNormalize(db);
end

function db = localNormalize(dbIn)
db = dbIn;
if ~isfield(db, "Axes") || ~isfield(db, "BLER")
    error("sixgr:system:BLER_DB:MissingFields", "DB requires Axes and BLER.");
end
a = db.Axes;
req = ["Direction","MCS","PRB","Layers","SCS","DopplerHz","ChannelModel","SNR_dB"];
for i = 1:numel(req)
    if ~isfield(a, req(i))
        error("sixgr:system:BLER_DB:MissingAxis", "Missing axis: %s", req(i));
    end
end
a.Direction = upper(string(a.Direction(:).'));
a.MCS = double(a.MCS(:).');
a.PRB = double(a.PRB(:).');
a.Layers = double(a.Layers(:).');
a.SCS = double(a.SCS(:).');
a.DopplerHz = double(a.DopplerHz(:).');
a.ChannelModel = upper(string(a.ChannelModel(:).'));
a.SNR_dB = double(a.SNR_dB(:));

sz = [numel(a.Direction), numel(a.MCS), numel(a.PRB), numel(a.Layers), ...
      numel(a.SCS), numel(a.DopplerHz), numel(a.ChannelModel), numel(a.SNR_dB)];
B = double(db.BLER);
if ~isequal(size(B), sz)
    error("sixgr:system:BLER_DB:ShapeMismatch", "BLER tensor size does not match normalized axes.");
end
db.Axes = a;
db.BLER = min(max(B, 1e-4), 0.9999);
if ~isfield(db, "Source")
    db.Source = "custom_db";
end
end

function bler = localQuery(db, ctx, strictMode)
if nargin < 3
    strictMode = false;
end
if ~isstruct(ctx)
    ctx = struct("SINR_dB", double(ctx), "Direction", "DL");
end

if strictMode
    src = lower(string(sixgr.util.structGet(db, "Source", "")));
    if contains(src, "default") || contains(src, "synthetic")
        error("sixgr:system:BLER_DB:StrictSyntheticSource", ...
            "Strict mode forbids querying synthetic/default BLER DB source: %s", src);
    end
end

a = db.Axes;
snr = double(sixgr.util.structGet(ctx, "SINR_dB", NaN));
if ~isfinite(snr)
    if strictMode
        error("sixgr:system:BLER_DB:InvalidSINR", "Query requires finite SINR_dB in strict mode.");
    end
    snr = 0;
end

dir = upper(string(sixgr.util.structGet(ctx, "Direction", "DL")));
mcs = double(sixgr.util.structGet(ctx, "MCSIndex", sixgr.util.structGet(ctx, "CQI", 10)));
prb = double(sixgr.util.structGet(ctx, "PRBCount", 50));
layers = double(sixgr.util.structGet(ctx, "NumLayers", 1));
scs = double(sixgr.util.structGet(ctx, "SCS_kHz", 30));
dop = double(sixgr.util.structGet(ctx, "DopplerHz", 0));
chn = upper(string(sixgr.util.structGet(ctx, "ChannelModel", "AWGN")));

iDir = localNearestString(a.Direction, dir);
iM = localNearestNumeric(a.MCS, mcs);
iP = localNearestNumeric(a.PRB, prb);
iL = localNearestNumeric(a.Layers, layers);
iS = localNearestNumeric(a.SCS, scs);
iD = localNearestNumeric(a.DopplerHz, dop);
iC = localNearestString(a.ChannelModel, chn);

curve = squeeze(db.BLER(iDir, iM, iP, iL, iS, iD, iC, :));
bler = interp1(a.SNR_dB(:), curve(:), snr, "linear", "extrap");
bler = min(max(double(bler), 1e-4), 0.9999);
end

function i = localNearestNumeric(v, x)
[~, i] = min(abs(double(v(:)) - double(x)));
end

function i = localNearestString(v, x)
sv = upper(string(v(:)));
x = upper(string(x));
i = find(sv == x, 1, "first");
if isempty(i)
    i = 1;
end
end
