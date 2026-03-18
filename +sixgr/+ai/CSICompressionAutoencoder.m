classdef CSICompressionAutoencoder < handle
% sixgr.ai.CSICompressionAutoencoder
% CSI compression via lightweight autoencoder.
%
% Purpose
%   Provides a practical CSI compression module for a unified 5G/6G
%   simulator. Intended integration points:
%     - UE: compress estimated DL CSI (e.g., from CSI-RS) into a compact
%           bitstream/latent vector for feedback.
%     - gNB: decompress feedback to reconstruct CSI for beamforming/MCS.
%
% Notes
%   - This implementation is simulation-friendly (JSON-free, fixed
%     interfaces) and uses Deep Learning Toolbox (dlnetwork).
%   - It is NOT a 3GPP-defined CSI reporting scheme. It is an ML module.
%   - By default it compresses an arbitrary complex CSI tensor H into a
%     latent vector z of length LatentDim, then (optionally) quantizes z to
%     QuantBits per latent element.
%
% Input / output
%   - CSI tensor H can be any numeric array (real/complex), any shape.
%   - It is packed as a feature vector:
%         x = [real(H(:)); imag(H(:))]   (complex)
%         x = H(:)                       (real)
%   - Decoder reconstructs Hhat with the same shape.
%
% Typical usage
%   cfg = sixgr.config.defaultConfig();
%   ae  = sixgr.ai.CSICompressionAutoencoder(cfg);
%
%   % Offline training (example):
%   X = randn(2*1000, 5000,'single');  % featureDim x nObs
%   ae.trainFromFeatures(X);
%
%   % Online compression:
%   comp = ae.compress(Hest);
%   Hrec = ae.decompress(comp);
%
% File: +sixgr/+ai/CSICompressionAutoencoder.m
% This file is ASCII-only.

    properties
        Cfg (1,1) struct
        Logger = []

        LatentDim (1,1) double = 64
        QuantBits (1,1) double = 6
        ClipLatent (1,1) double = 1.0

        UseZScore (1,1) logical = true
        MiniBatchSize (1,1) double = 256
        MaxEpochs (1,1) double = 20
        LearnRate (1,1) double = 1e-3

        HiddenMultiplier (1,1) double = 4  % hidden sizes: [4L, 2L]
        UseTanhLatent (1,1) logical = true
    end

    properties(SetAccess=private)
        FeatureDim (1,1) double = 0
        CSIShape (1,:) double = []
        IsComplexCSI (1,1) logical = true

        Mu single = single([])
        Sigma single = single([])

        EncoderNet = []   % dlnetwork
        DecoderNet = []   % dlnetwork
        IsTrained (1,1) logical = false

        TrainingHistory table = table()
    end

    methods
        function obj = CSICompressionAutoencoder(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            % Defaults from config
            obj.LatentDim = double(sixgr.util.structGet(cfg,'ai.csiCompression.latentDim', obj.LatentDim));
            obj.QuantBits = double(sixgr.util.structGet(cfg,'ai.csiCompression.quantBits', obj.QuantBits));
            obj.UseZScore = logical(sixgr.util.structGet(cfg,'ai.csiCompression.useZScore', obj.UseZScore));
            obj.MaxEpochs = double(sixgr.util.structGet(cfg,'ai.csiCompression.maxEpochs', obj.MaxEpochs));
            obj.MiniBatchSize = double(sixgr.util.structGet(cfg,'ai.csiCompression.miniBatchSize', obj.MiniBatchSize));
            obj.LearnRate = double(sixgr.util.structGet(cfg,'ai.csiCompression.learnRate', obj.LearnRate));

            % Name-value overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:CSICompressionAutoencoder:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'latentdim'
                            obj.LatentDim = double(v);
                        case 'quantbits'
                            obj.QuantBits = double(v);
                        case 'cliplatent'
                            obj.ClipLatent = double(v);
                        case 'usezscore'
                            obj.UseZScore = logical(v);
                        case 'minibatchsize'
                            obj.MiniBatchSize = double(v);
                        case 'maxepochs'
                            obj.MaxEpochs = double(v);
                        case 'learnrate'
                            obj.LearnRate = double(v);
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error('sixgr:CSICompressionAutoencoder:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end
        end

        function initFromCSI(obj, H)
            % Infer packing shape and build networks if needed.
            [x, shape, isCx] = obj.packCSI_(H);
            obj.CSIShape = shape;
            obj.IsComplexCSI = isCx;
            obj.FeatureDim = size(x,1);

            if isempty(obj.EncoderNet) || isempty(obj.DecoderNet) || obj.FeatureDim ~= obj.getFeatureDim_()
                obj.buildNetworks_(obj.FeatureDim);
                obj.IsTrained = false;
            end
        end

        function buildNetworks(obj, featureDim)
            % Explicitly build encoder/decoder networks for a given featureDim.
            obj.FeatureDim = double(featureDim);
            obj.buildNetworks_(obj.FeatureDim);
            obj.IsTrained = false;
        end

        function trainFromCSI(obj, Hcell)
            % trainFromCSI Train from a cell array of CSI tensors.
            % Hcell: {H1,H2,...} where each Hi is numeric array.
            if nargin < 2 || isempty(Hcell)
                error('sixgr:CSICompressionAutoencoder:NeedData','Provide CSI samples as a non-empty cell array.');
            end
            if ~iscell(Hcell)
                error('sixgr:CSICompressionAutoencoder:BadData','Hcell must be a cell array of CSI tensors.');
            end
            obj.initFromCSI(Hcell{1});

            X = zeros(obj.FeatureDim, numel(Hcell), 'single');
            for i = 1:numel(Hcell)
                xi = obj.packCSI_(Hcell{i});
                if size(xi,1) ~= obj.FeatureDim
                    error('sixgr:CSICompressionAutoencoder:ShapeMismatch','All CSI samples must have same packed feature dimension.');
                end
                X(:,i) = single(xi);
            end
            obj.trainFromFeatures(X);
        end

        function trainFromFeatures(obj, X)
            % trainFromFeatures Train encoder/decoder on feature vectors.
            % X: featureDim x nObs (preferred) or nObs x featureDim.
            if nargin < 2 || isempty(X)
                error('sixgr:CSICompressionAutoencoder:NeedData','Provide training features X.');
            end

            X = single(X);
            if ismatrix(X)
                if size(X,1) ~= obj.FeatureDim && size(X,2) == obj.FeatureDim
                    X = X.'; % transpose to featureDim x nObs
                end
            end

            if obj.FeatureDim == 0
                obj.FeatureDim = size(X,1);
                obj.buildNetworks_(obj.FeatureDim);
            end

            if size(X,1) ~= obj.FeatureDim
                error('sixgr:CSICompressionAutoencoder:BadDim','X must have size featureDim x nObs.');
            end

            % Compute normalization statistics
            if obj.UseZScore
                obj.Mu = mean(X,2);
                obj.Sigma = std(X,0,2);
                obj.Sigma(obj.Sigma < 1e-6) = 1e-6;
            else
                obj.Mu = zeros(obj.FeatureDim,1,'single');
                obj.Sigma = ones(obj.FeatureDim,1,'single');
            end

            Xn = (X - obj.Mu) ./ obj.Sigma;

            % Training loop
            nObs = size(Xn,2);
            mb = max(1, round(obj.MiniBatchSize));
            nIterPerEpoch = ceil(nObs/mb);

            if ~isempty(obj.Logger) && isa(obj.Logger,'sixgr.core.Logger')
                obj.Logger.info(sprintf('CSI AE train: featureDim=%d, nObs=%d, latentDim=%d', obj.FeatureDim, nObs, obj.LatentDim));
            end

            % Adam state
            trailingAvgE = [];
            trailingAvgSqE = [];
            trailingAvgD = [];
            trailingAvgSqD = [];

            iter = 0;
            histEpoch = zeros(obj.MaxEpochs,1);
            histLoss  = zeros(obj.MaxEpochs,1);

            for ep = 1:obj.MaxEpochs
                idx = randperm(nObs);
                epochLoss = 0;

                for it = 1:nIterPerEpoch
                    iter = iter + 1;
                    i1 = (it-1)*mb + 1;
                    i2 = min(it*mb, nObs);
                    batchIdx = idx(i1:i2);

                    Xb = Xn(:,batchIdx);
                    dlX = dlarray(Xb, 'CB');

                    [loss, gradE, gradD] = dlfeval(@obj.modelGradients_, dlX);
                    epochLoss = epochLoss + double(gather(extractdata(loss)));

                    % Update encoder
                    [obj.EncoderNet, trailingAvgE, trailingAvgSqE] = adamupdate(obj.EncoderNet, gradE, trailingAvgE, trailingAvgSqE, iter, obj.LearnRate);
                    % Update decoder
                    [obj.DecoderNet, trailingAvgD, trailingAvgSqD] = adamupdate(obj.DecoderNet, gradD, trailingAvgD, trailingAvgSqD, iter, obj.LearnRate);
                end

                epochLoss = epochLoss / nIterPerEpoch;
                histEpoch(ep) = ep;
                histLoss(ep) = epochLoss;

                if ~isempty(obj.Logger) && isa(obj.Logger,'sixgr.core.Logger')
                    obj.Logger.info(sprintf('CSI AE epoch %d/%d loss=%.4g', ep, obj.MaxEpochs, epochLoss));
                end
            end

            obj.TrainingHistory = table(histEpoch, histLoss, 'VariableNames', {'Epoch','Loss'});
            obj.IsTrained = true;
        end

        function z = encode(obj, H)
            % encode Return continuous latent vector z (single).
            obj.ensureReadyForCSI_(H);
            x = single(obj.packCSI_(H));
            xn = (x - obj.Mu) ./ obj.Sigma;
            dlX = dlarray(xn, 'CB');
            dlZ = forward(obj.EncoderNet, dlX);
            z = single(gather(extractdata(dlZ)));
            z = z(:);
        end

        function Hhat = decode(obj, z)
            % decode Reconstruct CSI tensor from continuous latent vector.
            if isempty(obj.DecoderNet)
                error('sixgr:CSICompressionAutoencoder:NotReady','Decoder network is not initialized.');
            end
            z = single(z(:));

            % Clip for numerical stability
            if isfinite(obj.ClipLatent) && obj.ClipLatent > 0
                z = max(-obj.ClipLatent, min(obj.ClipLatent, z));
            end

            dlZ = dlarray(z, 'CB');
            dlY = forward(obj.DecoderNet, dlZ);
            y = single(gather(extractdata(dlY)));
            y = y(:);

            xhat = y .* obj.Sigma + obj.Mu;
            Hhat = obj.unpackCSI_(xhat);
        end

        function comp = compress(obj, H, varargin)
            % compress Compress CSI to quantized latent + bits.
            %
            % Output comp struct:
            %   comp.Latent      : continuous latent (single)
            %   comp.Quantized   : quantized integers (uint16)
            %   comp.Bits        : bit vector (logical)
            %   comp.QuantBits   : bits per element
            %   comp.LatentDim   : latent dimension
            %   comp.CSIShape    : original CSI shape
            %   comp.IsComplex   : true if original CSI was complex

            qBits = obj.QuantBits;
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:CSICompressionAutoencoder:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'quantbits'
                            qBits = double(v);
                        otherwise
                            error('sixgr:CSICompressionAutoencoder:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            obj.ensureReadyForCSI_(H);

            z = obj.encode(H);
            [q, bits] = obj.quantizeLatent_(z, qBits);

            comp = struct();
            comp.Latent = z;
            comp.Quantized = q;
            comp.Bits = bits;
            comp.QuantBits = qBits;
            comp.LatentDim = obj.LatentDim;
            comp.CSIShape = obj.CSIShape;
            comp.IsComplex = obj.IsComplexCSI;
        end

        function Hhat = decompress(obj, comp)
            % decompress Reconstruct CSI from comp struct.
            if nargin < 2 || isempty(comp) || ~isstruct(comp)
                error('sixgr:CSICompressionAutoencoder:BadComp','comp must be a struct produced by compress().');
            end

            if isfield(comp,'CSIShape')
                obj.CSIShape = double(comp.CSIShape);
            end
            if isfield(comp,'IsComplex')
                obj.IsComplexCSI = logical(comp.IsComplex);
            end

            qBits = obj.QuantBits;
            if isfield(comp,'QuantBits')
                qBits = double(comp.QuantBits);
            end

            % Prefer Quantized; else derive from Bits
            if isfield(comp,'Quantized') && ~isempty(comp.Quantized)
                q = uint16(comp.Quantized(:));
            elseif isfield(comp,'Bits') && ~isempty(comp.Bits)
                q = obj.unpackBitsToIntegers_(logical(comp.Bits(:)), qBits);
            else
                error('sixgr:CSICompressionAutoencoder:BadComp','comp must contain Quantized or Bits.');
            end

            z = obj.dequantizeLatent_(q, qBits);
            Hhat = obj.decode(z);
        end

        function [nmseVal, mseVal] = nmse(obj, Htrue, Hhat)
            % nmse Normalized mean square error.
            if nargin < 3
                error('sixgr:CSICompressionAutoencoder:NeedArgs','Provide Htrue and Hhat.');
            end
            a = Htrue(:);
            b = Hhat(:);
            mseVal = mean(abs(a-b).^2);
            p = mean(abs(a).^2);
            nmseVal = mseVal / max(p, 1e-12);
        end

        function saveModel(obj, filePath)
            % saveModel Save networks and stats to a MAT file.
            if nargin < 2 || isempty(filePath)
                error('sixgr:CSICompressionAutoencoder:NeedFile','Provide a MAT file path.');
            end

            S = struct();
            S.LatentDim = obj.LatentDim;
            S.QuantBits = obj.QuantBits;
            S.ClipLatent = obj.ClipLatent;
            S.FeatureDim = obj.FeatureDim;
            S.CSIShape = obj.CSIShape;
            S.IsComplexCSI = obj.IsComplexCSI;
            S.UseZScore = obj.UseZScore;
            S.Mu = obj.Mu;
            S.Sigma = obj.Sigma;
            S.EncoderNet = obj.EncoderNet;
            S.DecoderNet = obj.DecoderNet;
            S.IsTrained = obj.IsTrained;
            S.TrainingHistory = obj.TrainingHistory;

            save(filePath, '-struct', 'S');
        end

        function loadModel(obj, filePath)
            % loadModel Load networks and stats from a MAT file.
            if nargin < 2 || isempty(filePath)
                error('sixgr:CSICompressionAutoencoder:NeedFile','Provide a MAT file path.');
            end
            S = load(filePath);

            if isfield(S,'LatentDim'), obj.LatentDim = double(S.LatentDim); end
            if isfield(S,'QuantBits'), obj.QuantBits = double(S.QuantBits); end
            if isfield(S,'ClipLatent'), obj.ClipLatent = double(S.ClipLatent); end
            if isfield(S,'FeatureDim'), obj.FeatureDim = double(S.FeatureDim); end
            if isfield(S,'CSIShape'), obj.CSIShape = double(S.CSIShape); end
            if isfield(S,'IsComplexCSI'), obj.IsComplexCSI = logical(S.IsComplexCSI); end
            if isfield(S,'UseZScore'), obj.UseZScore = logical(S.UseZScore); end
            if isfield(S,'Mu'), obj.Mu = single(S.Mu); end
            if isfield(S,'Sigma'), obj.Sigma = single(S.Sigma); end
            if isfield(S,'EncoderNet'), obj.EncoderNet = S.EncoderNet; end
            if isfield(S,'DecoderNet'), obj.DecoderNet = S.DecoderNet; end
            if isfield(S,'IsTrained'), obj.IsTrained = logical(S.IsTrained); end
            if isfield(S,'TrainingHistory'), obj.TrainingHistory = S.TrainingHistory; end
        end
    end

    methods(Access=private)
        function buildNetworks_(obj, featureDim)
            if nargin < 2
                featureDim = obj.FeatureDim;
            end
            featureDim = double(featureDim);
            if featureDim <= 0
                error('sixgr:CSICompressionAutoencoder:BadFeatureDim','FeatureDim must be > 0.');
            end

            L = max(1, round(obj.LatentDim));
            h1 = max(8, round(obj.HiddenMultiplier * L));
            h2 = max(8, round(0.5 * obj.HiddenMultiplier * L));

            if ~exist('dlnetwork','class')
                error('sixgr:CSICompressionAutoencoder:NeedDL','Deep Learning Toolbox is required (dlnetwork).');
            end

            % Encoder
            layersE = [
                featureInputLayer(featureDim, 'Normalization','none', 'Name','x')
                fullyConnectedLayer(h1, 'Name','enc_fc1')
                reluLayer('Name','enc_relu1')
                fullyConnectedLayer(h2, 'Name','enc_fc2')
                reluLayer('Name','enc_relu2')
                fullyConnectedLayer(L, 'Name','enc_fcZ')
                ];
            if obj.UseTanhLatent
                layersE = [layersE; tanhLayer('Name','enc_tanhZ')]; %#ok<AGROW>
            end

            % Decoder
            layersD = [
                featureInputLayer(L, 'Normalization','none', 'Name','z')
                fullyConnectedLayer(h2, 'Name','dec_fc1')
                reluLayer('Name','dec_relu1')
                fullyConnectedLayer(h1, 'Name','dec_fc2')
                reluLayer('Name','dec_relu2')
                fullyConnectedLayer(featureDim, 'Name','dec_fcY')
                ];

            obj.EncoderNet = dlnetwork(layerGraph(layersE));
            obj.DecoderNet = dlnetwork(layerGraph(layersD));

            % Safe defaults for normalization
            obj.Mu = zeros(featureDim,1,'single');
            obj.Sigma = ones(featureDim,1,'single');
        end

        function d = getFeatureDim_(obj)
            d = 0;
            if ~isempty(obj.EncoderNet)
                try
                    in = obj.EncoderNet.Layers(1);
                    if isprop(in,'InputSize')
                        d = double(in.InputSize);
                    end
                catch
                    d = 0;
                end
            end
        end

        function ensureReadyForCSI_(obj, H)
            if obj.FeatureDim == 0 || isempty(obj.EncoderNet) || isempty(obj.DecoderNet)
                obj.initFromCSI(H);
            else
                % Verify packed dimension matches
                x = obj.packCSI_(H);
                if size(x,1) ~= obj.FeatureDim
                    % Re-init to new shape
                    obj.initFromCSI(H);
                end
            end
        end

        function [loss, gradE, gradD] = modelGradients_(obj, dlX)
            dlZ = forward(obj.EncoderNet, dlX);
            dlY = forward(obj.DecoderNet, dlZ);
            loss = mean((dlY - dlX).^2, 'all');
            gradE = dlgradient(loss, obj.EncoderNet.Learnables);
            gradD = dlgradient(loss, obj.DecoderNet.Learnables);
        end

        function [x, shape, isCx] = packCSI_(obj, H) %#ok<INUSL>
            if nargin < 2
                error('sixgr:CSICompressionAutoencoder:NeedCSI','Provide CSI tensor H.');
            end
            if ~isnumeric(H)
                error('sixgr:CSICompressionAutoencoder:BadCSI','H must be numeric.');
            end
            shape = size(H);
            isCx = ~isreal(H);
            if isCx
                a = real(H(:));
                b = imag(H(:));
                x = [single(a); single(b)];
            else
                x = single(H(:));
            end
            x = x(:);
        end

        function H = unpackCSI_(obj, x)
            if isempty(obj.CSIShape)
                % If shape is unknown, return vector.
                H = x;
                return;
            end
            n = prod(obj.CSIShape);
            if obj.IsComplexCSI
                if numel(x) ~= 2*n
                    error('sixgr:CSICompressionAutoencoder:UnpackDim','Packed vector length mismatch for complex CSI.');
                end
                re = reshape(x(1:n), obj.CSIShape);
                im = reshape(x(n+1:end), obj.CSIShape);
                H = complex(re, im);
            else
                if numel(x) ~= n
                    error('sixgr:CSICompressionAutoencoder:UnpackDim','Packed vector length mismatch for real CSI.');
                end
                H = reshape(x, obj.CSIShape);
            end
        end

        function [q, bits] = quantizeLatent_(obj, z, qBits)
            qBits = max(1, round(qBits));
            L = 2^qBits;

            z = single(z(:));
            % Optional clip
            if isfinite(obj.ClipLatent) && obj.ClipLatent > 0
                z = max(-obj.ClipLatent, min(obj.ClipLatent, z));
            end

            % Map from [-Clip, Clip] -> [0, L-1]
            c = single(obj.ClipLatent);
            if ~(isfinite(c) && c > 0)
                c = single(1.0);
            end
            u = (z + c) ./ (2*c);
            u = max(0, min(1, u));

            q = uint16(round(u * single(L-1)));
            bits = obj.packIntegersToBits_(q, qBits);
        end

        function z = dequantizeLatent_(obj, q, qBits)
            qBits = max(1, round(qBits));
            L = 2^qBits;
            q = single(uint16(q(:)));
            c = single(obj.ClipLatent);
            if ~(isfinite(c) && c > 0)
                c = single(1.0);
            end

            u = q ./ single(L-1);
            z = (u * (2*c)) - c;
            z = z(:);
        end

        function bits = packIntegersToBits_(obj, q, qBits) %#ok<INUSL>
            q = uint16(q(:));
            qBits = max(1, round(qBits));
            n = numel(q);
            bits = false(n*qBits,1);
            % MSB-first packing
            for b = 1:qBits
                bits(b:qBits:end) = bitget(q, qBits - b + 1) ~= 0;
            end
        end

        function q = unpackBitsToIntegers_(obj, bits, qBits) %#ok<INUSL>
            bits = logical(bits(:));
            qBits = max(1, round(qBits));
            if mod(numel(bits), qBits) ~= 0
                error('sixgr:CSICompressionAutoencoder:BadBits','Bit length must be a multiple of QuantBits.');
            end
            n = numel(bits)/qBits;
            bits = reshape(bits, qBits, n);
            q = uint16(zeros(n,1));
            for b = 1:qBits
                q = bitor(q, uint16(bits(b,:)).' .* bitshift(uint16(1), qBits - b));
            end
        end
    end
end
