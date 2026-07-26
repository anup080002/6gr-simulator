function out = executeSpatialComposite(tx, rx, cfg, varargin)
%EXECUTESPATIALCOMPOSITE Causal MU-MIMO / multi-TRP sample-domain composite.
%
% TX convention:
%   S: Nsample-by-Nlayer layer symbols
%   W: Nport-by-Nlayer precoder
%   X = S * W.' port samples
%
% RX convention:
%   H: Nrx-by-Nport effective channel for each transmitter-to-receiver link
%   Y = X * H.' contribution at the receiver antennas

if nargin < 3 || ~isstruct(cfg)
    cfg = struct();
end
opt = struct( ...
    "Mode", "auto", ...
    "CombiningMode", "coherent", ...
    "NoiseVariance", sixgr.util.structGet(cfg, "phy.noiseVariance", 0), ...
    "NoiseSamples", [], ...
    "Strict", logical(sixgr.util.structGet(cfg,"mimo.strict", ...
        sixgr.util.structGet(cfg,"phy.mimo.strict",false))), ...
    "TransmissionContext", []);
if ~isempty(varargin)
    if mod(numel(varargin), 2) ~= 0
        error("sixgr:mimo:executeSpatialComposite:BadNameValue", ...
            "Name-value arguments must come in pairs.");
    end
    for i = 1:2:numel(varargin)
        key = lower(strtrim(string(varargin{i})));
        switch key
            case "mode"
                opt.Mode = string(varargin{i + 1});
            case "combiningmode"
                opt.CombiningMode = string(varargin{i + 1});
            case "noisevariance"
                opt.NoiseVariance = double(varargin{i + 1});
            case "noisesamples"
                opt.NoiseSamples = varargin{i + 1};
            case "strict"
                opt.Strict = logical(varargin{i + 1});
            case "transmissioncontext"
                opt.TransmissionContext = varargin{i + 1};
            otherwise
                error("sixgr:mimo:executeSpatialComposite:UnknownOption", ...
                    "Unknown option '%s'.", key);
        end
    end
end

tx = localNormalizeTx(tx,opt.Strict);
rx = localNormalizeRx(rx);
if isempty(tx)
    error("sixgr:mimo:executeSpatialComposite:NoTransmitters", ...
        "At least one transmitter contribution is required.");
end
if isempty(rx)
    error("sixgr:mimo:executeSpatialComposite:NoReceivers", ...
        "At least one receiver context is required.");
end
localValidateStrictContext(tx,rx,opt);

nTx = numel(tx);
portWaveforms = cell(nTx, 1);
matrixDigests = strings(nTx,1);
measuredTxPower = zeros(nTx,1);
for k = 1:nTx
    S = tx(k).Symbols;
    W = tx(k).Precoder;
    if size(W, 2) ~= size(S, 2)
        error("sixgr:mimo:executeSpatialComposite:LayerPrecoderMismatch", ...
            "Transmitter %d has %d layer columns but a %d-column precoder.", ...
            k, size(S, 2), size(W, 2));
    end
    scale = double(tx(k).PowerScale) .* exp(1i .* double(tx(k).PhaseRad));
    if logical(tx(k).Muted)
        scale = 0;
    end
    portWaveforms{k} = scale .* (S * W.');
    matrixDigests(k) = sixgr.phy.mimo.MatrixContract.digest(W);
    measuredTxPower(k) = localMeanPower(portWaveforms{k});
end

out = struct();
out.Source = "sixgr.mimo.executeSpatialComposite";
out.Mode = char(string(opt.Mode));
out.CombiningMode = char(string(opt.CombiningMode));
out.GroupSize = double(numel(unique(string({tx.UserId}))));
out.TransmitterCount = double(nTx);
out.ReceiverCount = double(numel(rx));
out.SimultaneousSharedPRB = logical(localHasSharedPRB(tx));
out.Equation = "y_u=sum_j H_{u<-j} x_j+n_u, x_j=S_j W_j^T";
out.TxPortWaveforms = portWaveforms;
out.PrecoderSHA256 = matrixDigests;
out.MeasuredTxPower = measuredTxPower;
out.FallbackUsed = false;
out.Strict = logical(opt.Strict);
out.ContextClass = string(class(opt.TransmissionContext));

rxOut = repmat(localEmptyRxOut(), numel(rx), 1);
for r = 1:numel(rx)
    if numel(rx(r).Channel) == 1 && nTx > 1
        rx(r).Channel = repmat(rx(r).Channel, nTx, 1);
    elseif numel(rx(r).Channel) ~= nTx
        error("sixgr:mimo:executeSpatialComposite:ChannelCountMismatch", ...
            "Receiver %d supplies %d channel entries for %d transmitters.", ...
            r, numel(rx(r).Channel), nTx);
    end
    nSamples = size(portWaveforms{1}, 1);
    nRxAnt = size(rx(r).Channel{1}, 1);
    contribution = complex(zeros(nSamples, nRxAnt, nTx));
    desiredMask = false(1, nTx);
    for k = 1:nTx
        if size(portWaveforms{k}, 1) ~= nSamples
            error("sixgr:mimo:executeSpatialComposite:SampleLengthMismatch", ...
                "All transmitter waveforms must have the same sample length.");
        end
        H = rx(r).Channel{k};
        if size(H, 2) ~= size(portWaveforms{k}, 2)
            error("sixgr:mimo:executeSpatialComposite:ChannelPortMismatch", ...
                "Receiver %d channel from transmitter %d has %d ports but waveform has %d port columns.", ...
                r, k, size(H, 2), size(portWaveforms{k}, 2));
        end
        if size(H, 1) ~= nRxAnt
            error("sixgr:mimo:executeSpatialComposite:ReceiverAntennaMismatch", ...
                "Receiver %d channel antenna dimensions are inconsistent.", r);
        end
        contribution(:, :, k) = localApplyChannel(portWaveforms{k}, H);
        desiredMask(k) = strcmp(string(tx(k).UserId), string(rx(r).UserId));
    end
    desired = sum(contribution(:, :, desiredMask), 3);
    interference = sum(contribution(:, :, ~desiredMask), 3);
    noise = localNoiseSamples(opt, nSamples, nRxAnt);
    composite = desired + interference + noise;
    desiredPower = localMeanPower(desired);
    interferencePower = localMeanPower(interference);
    noisePower = localMeanPower(noise);
    if noisePower == 0
        noisePower = max(0, double(opt.NoiseVariance));
    end
    denom = max(interferencePower + noisePower, realmin);
    sinr = desiredPower ./ denom;

    rxOut(r).UserId = char(string(rx(r).UserId));
    rxOut(r).DesiredWaveform = desired;
    rxOut(r).InterferenceWaveform = interference;
    rxOut(r).NoiseWaveform = noise;
    rxOut(r).CompositeWaveform = composite;
    rxOut(r).ContributionTensor = contribution;
    rxOut(r).DesiredMask = desiredMask;
    rxOut(r).DesiredPower = double(desiredPower);
    rxOut(r).InterferencePower = double(interferencePower);
    rxOut(r).NoisePower = double(noisePower);
    rxOut(r).SINRLinear = double(sinr);
    rxOut(r).SINR_dB = double(10 .* log10(max(sinr, realmin)));
    rxOut(r).Rate_bpsHz = double(log2(1 + max(sinr, 0)));
    rxOut(r).ContributorIds = string({tx.SourceId});
    rxOut(r).DesiredContributorIds = string({tx(desiredMask).SourceId});
    rxOut(r).InterferenceContributorIds = string({tx(~desiredMask).SourceId});
end
out.Rx = rxOut;
out.SumRate_bpsHz = sum([rxOut.Rate_bpsHz]);
out.DimensionContract = "S[Nsample,Nlayer], W[Nport,Nlayer], X=S*W.', H[Nrx,Nport], Y=X*H.'";
end

function tx = localNormalizeTx(txIn,strict)
if isempty(txIn)
    tx = repmat(localEmptyTx(), 0, 1);
    return;
end
tx = txIn(:);
for k = 1:numel(tx)
    if ~isfield(tx(k), "Symbols") || isempty(tx(k).Symbols)
        error("sixgr:mimo:executeSpatialComposite:MissingSymbols", ...
            "Transmitter %d is missing layer-domain Symbols.", k);
    end
    S = tx(k).Symbols;
    if ~isnumeric(S) || ~ismatrix(S)
        error("sixgr:mimo:executeSpatialComposite:BadSymbols", ...
            "Transmitter Symbols must be an Nsample-by-Nlayer numeric matrix.");
    end
    if isvector(S)
        S = S(:);
    end
    tx(k).Symbols = double(S);
    if ~isfield(tx(k), "Precoder") || isempty(tx(k).Precoder)
        if strict
            error("sixgr:mimo:MissingAppliedPrecoder", ...
                "Strict spatial composition requires the scheduler-selected immutable precoder.");
        end
        tx(k).Precoder = eye(size(S, 2));
    end
    if ~isnumeric(tx(k).Precoder) || ~ismatrix(tx(k).Precoder)
        error("sixgr:mimo:executeSpatialComposite:BadPrecoder", ...
            "Transmitter Precoder must be an Nport-by-Nlayer numeric matrix.");
    end
    tx(k).Precoder = double(tx(k).Precoder);
    if strict
        sixgr.phy.mimo.MatrixContract.validate( ...
            tx(k).Precoder,size(tx(k).Precoder,1),size(S,2));
    end
    if ~isfield(tx(k), "UserId") || strlength(string(tx(k).UserId)) == 0
        tx(k).UserId = "tx" + k;
    end
    if ~isfield(tx(k), "SourceId") || strlength(string(tx(k).SourceId)) == 0
        tx(k).SourceId = "tx" + k;
    end
    if ~isfield(tx(k), "TRPId") || strlength(string(tx(k).TRPId)) == 0
        tx(k).TRPId = "";
    end
    if ~isfield(tx(k), "Muted") || isempty(tx(k).Muted)
        tx(k).Muted = false;
    end
    if ~isfield(tx(k), "PowerScale") || isempty(tx(k).PowerScale)
        tx(k).PowerScale = 1;
    end
    if ~isfield(tx(k), "PhaseRad") || isempty(tx(k).PhaseRad)
        tx(k).PhaseRad = 0;
    end
    if ~isfield(tx(k), "PRBSet")
        tx(k).PRBSet = [];
    end
    if ~isfield(tx(k), "SymbolSet")
        tx(k).SymbolSet = [];
    end
    if ~isfield(tx(k), "DMRSIdentity")
        tx(k).DMRSIdentity = NaN;
    end
end
end

function localValidateStrictContext(tx,rx,opt)
if ~logical(opt.Strict)
    return;
end
if isempty(opt.TransmissionContext)
    error("sixgr:mimo:MissingTransmissionContext", ...
        "Strict MU-MIMO or multi-TRP composition requires a typed transmission context.");
end
ctx = opt.TransmissionContext;
if isa(ctx,"sixgr.phy.mimo.MUMIMOTransmissionContext")
    if numel(tx) ~= numel(ctx.UEIDs) || ...
            ~isequal(sort(string({tx.UserId})),sort(ctx.UEIDs))
        error("sixgr:mimo:MUIdentityCollision", ...
            "Waveform UE identities do not match the immutable MU context.");
    end
    dmrs = double([tx.DMRSIdentity]);
    if any(~isfinite(dmrs)) || ...
            ~isequal(sort(dmrs),sort(double(ctx.DMRSIdentities)))
        error("sixgr:mimo:MUIdentityCollision", ...
            "Waveform DM-RS identities do not match the immutable MU context.");
    end
    for index = 1:numel(tx)
        if isempty(tx(index).PRBSet) || isempty(tx(index).SymbolSet)
            error("sixgr:mimo:InvalidMUResourceSharing", ...
                "Strict MU transmitters require explicit PRB and symbol sets.");
        end
        if ~isequal(sort(double(tx(index).PRBSet(:))),sort(double(ctx.SharedPRBs(:)))) || ...
                ~isequal(sort(double(tx(index).SymbolSet(:))),sort(double(ctx.SharedSymbols(:))))
            error("sixgr:mimo:InvalidMUResourceSharing", ...
                "Waveform resources differ from the immutable MU context.");
        end
    end
elseif isa(ctx,"sixgr.phy.mimo.MultiTRPTransmissionContext")
    if numel(tx) ~= 2 || ...
            ~isequal(sort(string({tx.TRPId})),sort(ctx.TRPIDs))
        error("sixgr:mimo:MissingTRPState", ...
            "Waveform TRP identities do not match the immutable multi-TRP context.");
    end
else
    error("sixgr:mimo:MissingTransmissionContext", ...
        "Unsupported strict transmission-context class %s.",class(ctx));
end
if isempty(rx)
    error("sixgr:mimo:MissingMeasurementState", ...
        "Strict composition requires at least one receiver context.");
end
end

function rx = localNormalizeRx(rxIn)
rx = rxIn(:);
for r = 1:numel(rx)
    if ~isfield(rx(r), "UserId") || strlength(string(rx(r).UserId)) == 0
        rx(r).UserId = "rx" + r;
    end
    if ~isfield(rx(r), "Channel") || isempty(rx(r).Channel)
        error("sixgr:mimo:executeSpatialComposite:MissingChannel", ...
            "Receiver %d is missing Channel.", r);
    end
    if iscell(rx(r).Channel)
        channels = rx(r).Channel(:);
    else
        channels = {rx(r).Channel};
    end
    for k = 1:numel(channels)
        H = channels{k};
        if ~isnumeric(H) || ~(ismatrix(H) || ndims(H) == 3)
            error("sixgr:mimo:executeSpatialComposite:BadChannel", ...
                "Receiver Channel entries must be Nrx-by-Nport or Nrx-by-Nport-by-Nsample numeric arrays.");
        end
        channels{k} = double(H);
    end
    rx(r).Channel = channels;
end
end

function y = localApplyChannel(x, H)
if ismatrix(H)
    y = x * H.';
    return;
end
nSamples = size(x, 1);
if size(H, 3) ~= nSamples
    error("sixgr:mimo:executeSpatialComposite:TimeVaryingChannelLengthMismatch", ...
        "Time-varying channel third dimension must match waveform sample count.");
end
y = complex(zeros(nSamples, size(H, 1)));
for n = 1:nSamples
    y(n, :) = x(n, :) * H(:, :, n).';
end
end

function noise = localNoiseSamples(opt, nSamples, nRxAnt)
if ~isempty(opt.NoiseSamples)
    noise = opt.NoiseSamples;
    if ~isequal(size(noise), [nSamples, nRxAnt])
        error("sixgr:mimo:executeSpatialComposite:NoiseSizeMismatch", ...
            "NoiseSamples must be Nsample-by-Nrx.");
    end
    noise = double(noise);
else
    noise = complex(zeros(nSamples, nRxAnt));
end
end

function p = localMeanPower(x)
if isempty(x)
    p = 0;
else
    p = mean(abs(x(:)).^2, "omitnan");
end
if ~isfinite(p)
    p = NaN;
end
end

function tf = localHasSharedPRB(tx)
tf = false;
for i = 1:numel(tx)
    ai = tx(i).PRBSet;
    if isempty(ai)
        continue;
    end
    for j = i+1:numel(tx)
        if strcmp(string(tx(i).UserId), string(tx(j).UserId))
            continue;
        end
        aj = tx(j).PRBSet;
        if ~isempty(aj) && ~isempty(intersect(double(ai(:)), double(aj(:))))
            tf = true;
            return;
        end
    end
end
end

function s = localEmptyTx()
s = struct("Symbols", [], "Precoder", [], "UserId", "", "SourceId", "", ...
    "TRPId", "", "Muted", false, "PowerScale", 1, "PhaseRad", 0, ...
    "PRBSet", [], "SymbolSet", [], "DMRSIdentity", NaN);
end

function s = localEmptyRxOut()
s = struct("UserId", "", "DesiredWaveform", [], "InterferenceWaveform", [], ...
    "NoiseWaveform", [], "CompositeWaveform", [], "ContributionTensor", [], ...
    "DesiredMask", [], "DesiredPower", NaN, "InterferencePower", NaN, ...
    "NoisePower", NaN, "SINRLinear", NaN, "SINR_dB", NaN, "Rate_bpsHz", NaN, ...
    "ContributorIds", strings(0, 1), ...
    "DesiredContributorIds", strings(0,1), ...
    "InterferenceContributorIds", strings(0,1));
end
