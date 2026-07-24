function [carrier, info] = makeCarrier(cfg, varargin)
%MAKECARRIER Create a 5G Toolbox nrCarrierConfig from SixGR config.
%
%   [carrier,info] = sixgr.phy.grid.makeCarrier(cfg) builds an nrCarrierConfig
%   using cfg.phy.carrier fields and returns derived OFDM information.
%
%   Name-Value overrides (all optional):
%     "Slot"               - override carrier.NSlot
%     "Frame"              - override carrier.NFrame
%     "NCellID"            - override NCellID
%     "SubcarrierSpacing"  - subcarrier spacing in kHz
%     "NSizeGrid"          - number of resource blocks
%     "NStartGrid"         - starting resource block
%     "CyclicPrefix"       - "normal" or "extended"
%
%   This wrapper is intentionally thin and uses 5G Toolbox functions.

opts = struct();
for i = 1:2:numel(varargin)
    if i+1 > numel(varargin)
        break;
    end
    k = varargin{i};
    v = varargin{i+1};
    if isstring(k) || ischar(k)
        opts.(char(k)) = v;
    end
end

% Accept either full cfg (with cfg.phy.carrier) or a carrier-substruct.
if isstruct(cfg) && isfield(cfg, "phy") && isfield(cfg.phy, "carrier")
    p = cfg.phy.carrier;
else
    p = cfg;
end

carrier = nrCarrierConfig;

carrier.NCellID = localGet(opts, "NCellID", localGetField(p, "NCellID", 1));
carrier.SubcarrierSpacing = localGet(opts, "SubcarrierSpacing", localGetField(p, "SubcarrierSpacing", 30));
carrier.NSizeGrid = localGet(opts, "NSizeGrid", localGetField(p, "NSizeGrid", 52));
carrier.NStartGrid = localGet(opts, "NStartGrid", localGetField(p, "NStartGrid", 0));

cp = localGet(opts, "CyclicPrefix", localGetField(p, "CyclicPrefix", "normal"));
carrier.CyclicPrefix = cp;

% Slot/frame are optional depending on use. Guard in case a release changes.
slot = localGet(opts, "Slot", localGetField(p, "NSlot", 0));
frm  = localGet(opts, "Frame", localGetField(p, "NFrame", 0));
try
    carrier.NSlot = slot;
catch
end
try
    carrier.NFrame = frm;
catch
end

info = struct();
info.NCellID = carrier.NCellID;
info.SubcarrierSpacing_kHz = carrier.SubcarrierSpacing;
info.NSizeGrid = carrier.NSizeGrid;
info.NStartGrid = carrier.NStartGrid;
info.CyclicPrefix = char(string(carrier.CyclicPrefix));

try
    info.NSlot = carrier.NSlot;
catch
    info.NSlot = slot;
end
try
    info.NFrame = carrier.NFrame;
catch
    info.NFrame = frm;
end

info.NSC = carrier.NSizeGrid * 12;

% Derived OFDM details use the same strict policy as every waveform path.
% Invalid carrier/sampling state is a configuration error and is not
% converted into an empty metadata struct.
sampling = sixgr.phy.frame.OFDMSamplingResolver.resolve(carrier);
info.OFDM = sampling.ToolboxOFDMInfo;
info.OFDMSamplingResolution = sampling;

end

function v = localGet(s, name, defaultVal)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = defaultVal;
end
end

function v = localGetField(s, name, defaultVal)
if isstruct(s) && isfield(s, name)
    v = s.(name);
else
    v = defaultVal;
end
end
