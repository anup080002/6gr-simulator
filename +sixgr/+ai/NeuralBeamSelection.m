classdef NeuralBeamSelection < handle
% sixgr.ai.NeuralBeamSelection
% Neural beam selection (classification) with an oracle label generator.
%
% Purpose
%   Provide a practical AI hook for beam management:
%     - Input features: CSI (raw or compressed) or handcrafted features
%     - Output: beam index (1..NumBeams) and soft scores
%
% Design
%   - Uses Deep Learning Toolbox trainNetwork for a simple MLP classifier.
%   - Includes a deterministic fallback (oracle) that chooses the best beam
%     for a given channel and codebook (max average beamforming gain).
%
% Typical usage
%   cfg = sixgr.config.defaultConfig();
%   bs  = sixgr.ai.NeuralBeamSelection(cfg, 'NumBeams', 64);
%
%   % Training with oracle labels:
%   %   H: channel samples (cell or 3D array)
%   %   W: codebook matrix Nt x NumBeams
%   [X, Y] = bs.makeDatasetFromChannel(H, W);
%   bs.train(X, Y);
%
%   % Inference:
%   [beamIdx, scores] = bs.predictBeam(X(1,:));
%
% File: +sixgr/+ai/NeuralBeamSelection.m
% This file is ASCII-only.

    properties
        Cfg (1,1) struct
        Logger = []

        NumBeams (1,1) double = 64
        HiddenSizes (1,:) double = [256 128]
        MaxEpochs (1,1) double = 20
        MiniBatchSize (1,1) double = 256
        LearnRate (1,1) double = 1e-3

        FeatureNormalization (1,:) char = 'zscore' % 'none'|'zscore'
    end

    properties(SetAccess=private)
        FeatureDim (1,1) double = 0
        Net = []                % DAGNetwork/SeriesNetwork
        ClassNames = categorical([])
        IsTrained (1,1) logical = false
        TrainingInfo = struct()
    end

    methods
        function obj = NeuralBeamSelection(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            % Defaults from cfg
            obj.NumBeams = double(sixgr.util.structGet(cfg,'ai.beamSelection.numBeams', obj.NumBeams));
            if isfield(cfg,'phy') && isfield(cfg.phy,'ssb')
                obj.NumBeams = double(sixgr.util.structGet(cfg,'phy.ssb.nBeams', obj.NumBeams));
            end
            obj.MaxEpochs = double(sixgr.util.structGet(cfg,'ai.beamSelection.maxEpochs', obj.MaxEpochs));
            obj.MiniBatchSize = double(sixgr.util.structGet(cfg,'ai.beamSelection.miniBatchSize', obj.MiniBatchSize));
            obj.LearnRate = double(sixgr.util.structGet(cfg,'ai.beamSelection.learnRate', obj.LearnRate));

            % Name-value
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralBeamSelection:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'numbeams'
                            obj.NumBeams = double(v);
                        case 'hiddensizes'
                            obj.HiddenSizes = double(v(:)).';
                        case 'maxepochs'
                            obj.MaxEpochs = double(v);
                        case 'minibatchsize'
                            obj.MiniBatchSize = double(v);
                        case 'learnrate'
                            obj.LearnRate = double(v);
                        case 'featurenormalization'
                            obj.FeatureNormalization = char(string(v));
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error('sixgr:NeuralBeamSelection:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            obj.ClassNames = categorical(1:obj.NumBeams);
        end

        function build(obj, featureDim)
            % build Build an untrained network for the given feature dimension.
            featureDim = double(featureDim);
            if featureDim <= 0
                error('sixgr:NeuralBeamSelection:BadFeatureDim','FeatureDim must be > 0.');
            end
            obj.FeatureDim = featureDim;

            layers = obj.makeLayers_(featureDim, obj.NumBeams);
            obj.Net = assembleNetwork(layerGraph(layers));
            obj.IsTrained = false;
        end

        function train(obj, X, Y, varargin)
            % train Train beam selection classifier.
            % X: nObs x featureDim (preferred) or featureDim x nObs.
            % Y: labels as numeric (1..NumBeams) or categorical.

            if nargin < 3
                error('sixgr:NeuralBeamSelection:NeedArgs','Provide X and Y.');
            end

            % Parse optional training options overrides
            maxEpochs = obj.MaxEpochs;
            miniBatch = obj.MiniBatchSize;
            learnRate = obj.LearnRate;
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralBeamSelection:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'maxepochs'
                            maxEpochs = double(v);
                        case 'minibatchsize'
                            miniBatch = double(v);
                        case 'learnrate'
                            learnRate = double(v);
                        otherwise
                            error('sixgr:NeuralBeamSelection:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            X = single(X);

            % Ensure X is nObs x featureDim
            if ismatrix(X)
                if size(X,2) ~= obj.FeatureDim && size(X,1) == obj.FeatureDim
                    X = X.';
                end
            end

            if obj.FeatureDim == 0
                obj.FeatureDim = size(X,2);
            end

            if size(X,2) ~= obj.FeatureDim
                error('sixgr:NeuralBeamSelection:BadDim','X must be nObs x featureDim.');
            end

            if iscategorical(Y)
                Yc = Y(:);
            else
                Yn = double(Y(:));
                if any(Yn < 1) || any(Yn > obj.NumBeams)
                    error('sixgr:NeuralBeamSelection:BadLabels','Labels must be within 1..NumBeams.');
                end
                Yc = categorical(Yn);
            end

            % Build layers
            layers = obj.makeLayers_(obj.FeatureDim, obj.NumBeams);

            % Training options
            opts = trainingOptions('adam', ...
                'MaxEpochs', maxEpochs, ...
                'MiniBatchSize', miniBatch, ...
                'InitialLearnRate', learnRate, ...
                'Shuffle', 'every-epoch', ...
                'Verbose', false);

            if ~isempty(obj.Logger) && isa(obj.Logger,'sixgr.core.Logger')
                obj.Logger.info(sprintf('BeamSel train: nObs=%d, featureDim=%d, numBeams=%d', size(X,1), size(X,2), obj.NumBeams));
            end

            [obj.Net, info] = trainNetwork(X, Yc, layers, opts);
            obj.IsTrained = true;
            obj.TrainingInfo = info;
        end

        function [beamIdx, scores] = predictBeam(obj, X)
            % predictBeam Predict beam index for one or more observations.
            % X: 1 x featureDim OR nObs x featureDim.

            if isempty(obj.Net)
                error('sixgr:NeuralBeamSelection:NotReady','Network is not built/trained. Call build() or train().');
            end

            X = single(X);
            if isvector(X)
                X = X(:).';
            end
            if size(X,2) ~= obj.FeatureDim
                % Try transpose if user provided featureDim x nObs
                if size(X,1) == obj.FeatureDim
                    X = X.';
                else
                    error('sixgr:NeuralBeamSelection:BadDim','X must have featureDim columns.');
                end
            end

            scores = predict(obj.Net, X);
            % scores is nObs x NumBeams
            [~, idx] = max(scores, [], 2);
            beamIdx = idx;
        end

        function [X, Y] = makeDatasetFromChannel(obj, H, W, varargin)
            % makeDatasetFromChannel Create (X,Y) from channel samples and codebook.
            %
            % H may be:
            %   - cell array of channels (each Hi complex vector/matrix)
            %   - numeric array where last dim indexes samples
            %
            % W: codebook matrix Nt x NumBeams OR cell array of beam vectors.
            %
            % Features:
            %   Default: vectorized [real; imag] of H (per sample).
            %   You can provide a custom feature function:
            %     makeDatasetFromChannel(...,'FeatureFcn',@(Hi) featureRow)

            featureFcn = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralBeamSelection:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'featurefcn'
                            featureFcn = v;
                        otherwise
                            error('sixgr:NeuralBeamSelection:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            if isempty(featureFcn)
                featureFcn = @(Hi) obj.defaultFeature_(Hi);
            end

            % Convert H to cell array
            Hcell = obj.toCellSamples_(H);
            nObs = numel(Hcell);

            X = [];
            Y = zeros(nObs,1);

            for i = 1:nObs
                Hi = Hcell{i};
                xi = featureFcn(Hi);
                xi = single(xi(:).');
                if isempty(X)
                    X = zeros(nObs, numel(xi), 'single');
                end
                X(i,:) = xi;
                Y(i) = obj.oracleBestBeam_(Hi, W);
            end

            % Ensure featureDim known
            if obj.FeatureDim == 0
                obj.FeatureDim = size(X,2);
            end
        end

        function y = oracleBestBeam(obj, H, W)
            % oracleBestBeam Public deterministic label generator.
            y = obj.oracleBestBeam_(H, W);
        end

        function saveModel(obj, filePath)
            if nargin < 2 || isempty(filePath)
                error('sixgr:NeuralBeamSelection:NeedFile','Provide a MAT file path.');
            end
            S = struct();
            S.NumBeams = obj.NumBeams;
            S.FeatureDim = obj.FeatureDim;
            S.HiddenSizes = obj.HiddenSizes;
            S.FeatureNormalization = obj.FeatureNormalization;
            S.Net = obj.Net;
            S.IsTrained = obj.IsTrained;
            S.TrainingInfo = obj.TrainingInfo;
            save(filePath,'-struct','S');
        end

        function loadModel(obj, filePath)
            if nargin < 2 || isempty(filePath)
                error('sixgr:NeuralBeamSelection:NeedFile','Provide a MAT file path.');
            end
            S = load(filePath);
            if isfield(S,'NumBeams'), obj.NumBeams = double(S.NumBeams); end
            if isfield(S,'FeatureDim'), obj.FeatureDim = double(S.FeatureDim); end
            if isfield(S,'HiddenSizes'), obj.HiddenSizes = double(S.HiddenSizes); end
            if isfield(S,'FeatureNormalization'), obj.FeatureNormalization = char(string(S.FeatureNormalization)); end
            if isfield(S,'Net'), obj.Net = S.Net; end
            if isfield(S,'IsTrained'), obj.IsTrained = logical(S.IsTrained); end
            if isfield(S,'TrainingInfo'), obj.TrainingInfo = S.TrainingInfo; end
            obj.ClassNames = categorical(1:obj.NumBeams);
        end
    end

    methods(Access=private)
        function layers = makeLayers_(obj, featureDim, numClasses)
            % Simple MLP classifier
            if featureDim <= 0
                error('sixgr:NeuralBeamSelection:BadFeatureDim','FeatureDim must be > 0.');
            end

            normMode = lower(strtrim(obj.FeatureNormalization));
            if strcmp(normMode,'zscore')
                normArg = 'zscore';
            else
                normArg = 'none';
            end

            layers = [
                featureInputLayer(featureDim, 'Normalization', normArg, 'Name','in')
                fullyConnectedLayer(obj.HiddenSizes(1), 'Name','fc1')
                reluLayer('Name','relu1')
                ];

            for i = 2:numel(obj.HiddenSizes)
                layers = [layers; fullyConnectedLayer(obj.HiddenSizes(i), 'Name',sprintf('fc%d',i)); reluLayer('Name',sprintf('relu%d',i))]; %#ok<AGROW>
            end

            layers = [layers;
                fullyConnectedLayer(numClasses, 'Name','fcOut')
                softmaxLayer('Name','sm')
                classificationLayer('Name','cls')
                ];
        end

        function x = defaultFeature_(obj, H) %#ok<INUSL>
            % Default feature: vectorize real/imag of H.
            if ~isnumeric(H)
                error('sixgr:NeuralBeamSelection:BadH','H must be numeric.');
            end
            if isreal(H)
                x = single(H(:));
            else
                x = single([real(H(:)); imag(H(:))]);
            end
            x = x(:);
        end

        function Hcell = toCellSamples_(obj, H) %#ok<INUSL>
            if iscell(H)
                Hcell = H;
                return;
            end
            if ~isnumeric(H)
                error('sixgr:NeuralBeamSelection:BadH','H must be numeric or cell.');
            end
            sz = size(H);
            if numel(sz) < 2
                Hcell = {H};
                return;
            end
            % Interpret last dimension as sample dimension
            nObs = sz(end);
            if nObs == 1
                Hcell = {H};
                return;
            end
            Hcell = cell(nObs,1);
            for i = 1:nObs
                idx = repmat({':'},1,ndims(H));
                idx{end} = i;
                Hcell{i} = H(idx{:});
            end
        end

        function bestIdx = oracleBestBeam_(obj, H, W)
            % Choose beam that maximizes average gain ||H*w||^2
            % H can be vector, matrix, or tensor. We flatten all dims except
            % the transmit dimension when possible.

            nb = obj.NumBeams;

            % Convert codebook to matrix Nt x nb
            Wm = obj.toCodebookMatrix_(W, nb);
            Nt = size(Wm,1);

            % Derive effective channel matrix Heff of size Nr x Nt
            Heff = obj.toHeff_(H, Nt);

            gains = zeros(nb,1);
            for b = 1:nb
                w = Wm(:,b);
                y = Heff * w;
                gains(b) = mean(abs(y(:)).^2);
            end

            [~, bestIdx] = max(gains);
            bestIdx = double(bestIdx);
        end

        function Wm = toCodebookMatrix_(obj, W, nb) %#ok<INUSL>
            if iscell(W)
                if numel(W) < nb
                    error('sixgr:NeuralBeamSelection:BadCodebook','Codebook cell must have NumBeams elements.');
                end
                Nt = numel(W{1});
                Wm = zeros(Nt, nb);
                for i = 1:nb
                    wi = W{i};
                    Wm(:,i) = wi(:);
                end
                return;
            end
            if ~isnumeric(W)
                error('sixgr:NeuralBeamSelection:BadCodebook','W must be numeric matrix or cell array.');
            end
            if size(W,2) ~= nb
                error('sixgr:NeuralBeamSelection:BadCodebook','W must be Nt x NumBeams.');
            end
            Wm = W;
        end

        function Heff = toHeff_(obj, H, Nt) %#ok<INUSL>
            % Attempt to interpret H so that transmit dimension is Nt.
            % If H has an Nt dimension, collapse all other dims into Nr.
            if ~isnumeric(H)
                error('sixgr:NeuralBeamSelection:BadH','H must be numeric.');
            end

            sz = size(H);
            % Find a dimension matching Nt
            dimTx = find(sz == Nt, 1, 'last');
            if isempty(dimTx)
                % If no matching dim, try if H is vector length Nt
                if numel(H) == Nt
                    Heff = reshape(H(:), 1, Nt);
                    return;
                end
                % Fallback: treat last dimension as Nt if compatible
                if sz(end) == Nt
                    dimTx = numel(sz);
                else
                    error('sixgr:NeuralBeamSelection:BadH','Cannot infer transmit dimension Nt=%d from H size.', Nt);
                end
            end

            % Permute so Tx dim is last
            perm = 1:numel(sz);
            perm([dimTx end]) = perm([end dimTx]);
            Hp = permute(H, perm);
            szp = size(Hp);

            % Now Hp is ... x Nt
            Nr = prod(szp(1:end-1));
            Heff = reshape(Hp, Nr, Nt);
        end
    end
end
