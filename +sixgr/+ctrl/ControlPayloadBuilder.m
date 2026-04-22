function payload = ControlPayloadBuilder(ctrlCfg, varargin)
%ControlPayloadBuilder Build deterministic or random control payload bits.

opts = struct("Seed", ctrlCfg.Seed, "PayloadBits", [], "GrantPlaceholders", false);
for i = 1:2:numel(varargin)
    if i + 1 <= numel(varargin)
        opts.(char(string(varargin{i}))) = varargin{i + 1};
    end
end

if isempty(opts.PayloadBits)
    s = rng;
    cleanup = onCleanup(@() rng(s)); %#ok<NASGU>
    rng(double(opts.Seed), "twister");
    bits = int8(randi([0 1], ctrlCfg.PayloadLengthBits, 1));
else
    bits = int8(opts.PayloadBits(:) ~= 0);
end

payload = struct();
payload.InformationBits = bits(:);
payload.PayloadLengthBits = numel(payload.InformationBits);
payload.PayloadMode = ternary(isempty(opts.PayloadBits), "random_reproducible", "deterministic_vector");
payload.GrantPlaceholderBits = logical(opts.GrantPlaceholders);
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
