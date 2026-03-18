classdef NeuralChannelEstimator < handle
% sixgr.ai.NeuralChannelEstimator
% Neural channel estimator / denoiser for NR OFDM channel estimates.
%
% Purpose
%   Provide an AI hook that can refine classical pilot-based channel
%   estimates (LS/MMSE/linear interpolation) using a learned denoiser.
%
% Integration intent
%   - Use your existing PHY estimator (DMRS/SRS) to produce an initial
%     estimate Hls (complex CSI grid).
%   - Call this module to refine:
%         Hhat = nn.estimate(Hls, 'NoiseVar', noiseVar);
%   - Then feed Hhat to equalizer/MIMO detector.
%
% Training
%   - Supervised regression. Provide pairs (Hls, Htrue) generated from your
%     channel model.
%   - Default training target is residual: (Htrue - Hls).
%
% Notes
%   - Uses Deep Learning Toolbox trainNetwork.
%   - Not 3GPP standardized; it is a research hook.
%   - For multi-antenna CSI, this class flattens all dims beyond the first
%     two (freq x time) into a channel dimension, and uses 2x channels for
%     real/imag.
%
% File: +sixgr/+ai/NeuralChannelEstimator.m
% This file is ASCII-only.

    properties
        Cfg (1,1) struct
        Logger = []

        Depth (1,1) double = 8           % number of conv blocks (>=1)
        NumFilters (1,1) double = 64
        ResidualLearning (1,1) logical = true
        UseNoiseVarChannel (1,1) logical = false

        MaxEpochs (1,1) double = 15
        MiniBatchSize (1,1) double = 64
        LearnRate (1,1) double = 1e-3
        L2Regularization (1,1) double = 1e-5
    end

    properties(SetAccess=private)
        InputSize (1,3) double = [0 0 0]   % [F T Cin]
        OutputChannels (1,1) double = 0
        Net = []
        IsTrained (1,1) logical = false
        TrainingInfo = struct()
    end

    methods
        function obj = NeuralChannelEstimator(cfg, varargin)
            if nargin < 1 || isempty(cfg)
                cfg = struct();
            end
            obj.Cfg = cfg;

            % Defaults from cfg (best-effort)
            obj.Depth = double(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.depth', obj.Depth));
            obj.NumFilters = double(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.numFilters', obj.NumFilters));
            obj.ResidualLearning = logical(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.residualLearning', obj.ResidualLearning));
            obj.UseNoiseVarChannel = logical(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.useNoiseVarChannel', obj.UseNoiseVarChannel));
            obj.MaxEpochs = double(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.maxEpochs', obj.MaxEpochs));
            obj.MiniBatchSize = double(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.miniBatchSize', obj.MiniBatchSize));
            obj.LearnRate = double(sixgr.util.structGet(cfg,'ai.neuralChannelEstimator.learnRate', obj.LearnRate));

            % Name-value overrides
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralChannelEstimator:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'depth'
                            obj.Depth = double(v);
                        case 'numfilters'
                            obj.NumFilters = double(v);
                        case 'residuallearning'
                            obj.ResidualLearning = logical(v);
                        case 'usenoisevarchannel'
                            obj.UseNoiseVarChannel = logical(v);
                        case 'maxepochs'
                            obj.MaxEpochs = double(v);
                        case 'minibatchsize'
                            obj.MiniBatchSize = double(v);
                        case 'learnrate'
                            obj.LearnRate = double(v);
                        case 'l2regularization'
                            obj.L2Regularization = double(v);
                        case 'logger'
                            obj.Logger = v;
                        otherwise
                            error('sixgr:NeuralChannelEstimator:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            obj.Depth = max(1, round(obj.Depth));
            obj.NumFilters = max(8, round(obj.NumFilters));
        end

        function initFromEstimate(obj, Hls, varargin)
            % initFromEstimate Infer input size from an LS estimate tensor.
            noiseVar = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralChannelEstimator:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'noisevar'
                            noiseVar = v; %#ok<NASGU>
                        otherwise
                            error('sixgr:NeuralChannelEstimator:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            [X, Cout] = obj.packForNet_(Hls, 'NoiseVar', []);
            % X is [F T Cin 1]
            obj.InputSize = [size(X,1) size(X,2) size(X,3)];
            obj.OutputChannels = Cout;

            obj.build_();
        end

        function build(obj, inputSize, outChannels)
            % build Build an untrained network for a specified size.
            if nargin < 3
                error('sixgr:NeuralChannelEstimator:NeedArgs','Provide inputSize and outChannels.');
            end
            inputSize = double(inputSize);
            if numel(inputSize) ~= 3
                error('sixgr:NeuralChannelEstimator:BadInputSize','inputSize must be [F T Cin].');
            end
            obj.InputSize = reshape(inputSize,1,3);
            obj.OutputChannels = double(outChannels);
            obj.build_();
        end

        function train(obj, HlsSamples, HtrueSamples, varargin)
            % train Supervised training.
            %
            % Prefer cell arrays for clarity:
            %   HlsSamples   = {Hls1,Hls2,...}
            %   HtrueSamples = {H1,H2,...}
            %
            % Alternatively, numeric arrays where the last dim indexes
            % samples may work, but cell is recommended.

            if nargin < 3
                error('sixgr:NeuralChannelEstimator:NeedArgs','Provide HlsSamples and HtrueSamples.');
            end

            maxEpochs = obj.MaxEpochs;
            miniBatch = obj.MiniBatchSize;
            learnRate = obj.LearnRate;

            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralChannelEstimator:BadNV','Name-value inputs must come in pairs.');
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
                            error('sixgr:NeuralChannelEstimator:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            HlsCell = obj.toCellSamples_(HlsSamples);
            HtCell  = obj.toCellSamples_(HtrueSamples);
            if numel(HlsCell) ~= numel(HtCell)
                error('sixgr:NeuralChannelEstimator:BadData','HlsSamples and HtrueSamples must have same number of samples.');
            end

            nObs = numel(HlsCell);
            if nObs == 0
                error('sixgr:NeuralChannelEstimator:BadData','No training samples provided.');
            end

            % Initialize network size from first sample
            if isempty(obj.Net) || any(obj.InputSize == 0)
                obj.initFromEstimate(HlsCell{1});
            end

            % Build training arrays
            XTrain = [];
            YTrain = [];

            for i = 1:nObs
                Hls = HlsCell{i};
                Ht  = HtCell{i};

                [Xi, Cout] = obj.packForNet_(Hls, 'NoiseVar', []);
                Yi = obj.packTarget_(Hls, Ht, Cout);

                if isempty(XTrain)
                    XTrain = zeros([size(Xi,1) size(Xi,2) size(Xi,3) nObs], 'single');
                    YTrain = zeros([size(Yi,1) size(Yi,2) size(Yi,3) nObs], 'single');
                end

                if ~isequal(size(Xi,1), obj.InputSize(1)) || ~isequal(size(Xi,2), obj.InputSize(2)) || ~isequal(size(Xi,3), obj.InputSize(3))
                    error('sixgr:NeuralChannelEstimator:ShapeMismatch','All samples must pack to the same input size.');
                end

                XTrain(:,:,:,i) = Xi;
                YTrain(:,:,:,i) = Yi;
            end

            layers = obj.makeLayers_();

            opts = trainingOptions('adam', ...
                'MaxEpochs', maxEpochs, ...
                'MiniBatchSize', miniBatch, ...
                'InitialLearnRate', learnRate, ...
                'L2Regularization', obj.L2Regularization, ...
                'Shuffle', 'every-epoch', ...
                'Verbose', false, ...
                'ExecutionEnvironment', 'auto');

            if ~isempty(obj.Logger) && isa(obj.Logger,'sixgr.core.Logger')
                obj.Logger.info(sprintf('NeuralChEst train: nObs=%d input=[%d %d %d] outCh=%d', nObs, obj.InputSize(1), obj.InputSize(2), obj.InputSize(3), obj.OutputChannels));
            end

            [obj.Net, info] = trainNetwork(XTrain, YTrain, layers, opts);
            obj.IsTrained = true;
            obj.TrainingInfo = info;
        end

        function Hhat = estimate(obj, Hls, varargin)
            % estimate Refine channel estimate.
            % Hls: complex CSI tensor (any shape).
            % Optional:
            %   'NoiseVar', noiseVar

            noiseVar = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralChannelEstimator:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'noisevar'
                            noiseVar = v;
                        otherwise
                            error('sixgr:NeuralChannelEstimator:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            if isempty(obj.Net)
                obj.initFromEstimate(Hls);
            end

            [X, Cout] = obj.packForNet_(Hls, 'NoiseVar', noiseVar);
            if Cout ~= obj.OutputChannels
                % If antenna dimensions changed, rebuild
                obj.initFromEstimate(Hls);
                [X, Cout] = obj.packForNet_(Hls, 'NoiseVar', noiseVar);
            end

            if ~isequal(size(X,1), obj.InputSize(1)) || ~isequal(size(X,2), obj.InputSize(2)) || ~isequal(size(X,3), obj.InputSize(3))
                error('sixgr:NeuralChannelEstimator:InputSizeMismatch','Packed input size mismatch. Rebuild or retrain for this configuration.');
            end

            Y = predict(obj.Net, X);
            % Y is [F T Cout 1]

            Hcorr = obj.unpackFromNet_(Y, Hls, Cout);

            if obj.ResidualLearning
                Hhat = Hls + Hcorr;
            else
                Hhat = Hcorr;
            end
        end

        function [nmseVal, mseVal] = nmse(obj, Htrue, Hhat)
            a = Htrue(:);
            b = Hhat(:);
            mseVal = mean(abs(a-b).^2);
            p = mean(abs(a).^2);
            nmseVal = mseVal / max(p, 1e-12);
        end

        function saveModel(obj, filePath)
            if nargin < 2 || isempty(filePath)
                error('sixgr:NeuralChannelEstimator:NeedFile','Provide a MAT file path.');
            end
            S = struct();
            S.Depth = obj.Depth;
            S.NumFilters = obj.NumFilters;
            S.ResidualLearning = obj.ResidualLearning;
            S.UseNoiseVarChannel = obj.UseNoiseVarChannel;
            S.InputSize = obj.InputSize;
            S.OutputChannels = obj.OutputChannels;
            S.Net = obj.Net;
            S.IsTrained = obj.IsTrained;
            S.TrainingInfo = obj.TrainingInfo;
            save(filePath,'-struct','S');
        end

        function loadModel(obj, filePath)
            if nargin < 2 || isempty(filePath)
                error('sixgr:NeuralChannelEstimator:NeedFile','Provide a MAT file path.');
            end
            S = load(filePath);
            if isfield(S,'Depth'), obj.Depth = double(S.Depth); end
            if isfield(S,'NumFilters'), obj.NumFilters = double(S.NumFilters); end
            if isfield(S,'ResidualLearning'), obj.ResidualLearning = logical(S.ResidualLearning); end
            if isfield(S,'UseNoiseVarChannel'), obj.UseNoiseVarChannel = logical(S.UseNoiseVarChannel); end
            if isfield(S,'InputSize'), obj.InputSize = double(S.InputSize); end
            if isfield(S,'OutputChannels'), obj.OutputChannels = double(S.OutputChannels); end
            if isfield(S,'Net'), obj.Net = S.Net; end
            if isfield(S,'IsTrained'), obj.IsTrained = logical(S.IsTrained); end
            if isfield(S,'TrainingInfo'), obj.TrainingInfo = S.TrainingInfo; end
        end
    end

    methods(Access=private)
        function build_(obj)
            % Build an untrained network with current InputSize/OutputChannels.
            if any(obj.InputSize == 0) || obj.OutputChannels == 0
                error('sixgr:NeuralChannelEstimator:NotReady','Set InputSize and OutputChannels before build.');
            end
            layers = obj.makeLayers_();
            obj.Net = assembleNetwork(layerGraph(layers));
            obj.IsTrained = false;
        end

        function layers = makeLayers_(obj)
            F = obj.InputSize(1);
            T = obj.InputSize(2);
            Cin = obj.InputSize(3);
            Cout = obj.OutputChannels;

            layers = [
                imageInputLayer([F T Cin], 'Normalization','none', 'Name','in')
                convolution2dLayer(3, obj.NumFilters, 'Padding','same', 'Name','conv1')
                reluLayer('Name','relu1')
                ];

            for k = 2:obj.Depth
                layers = [layers;
                    convolution2dLayer(3, obj.NumFilters, 'Padding','same', 'Name',sprintf('conv%d',k))
                    reluLayer('Name',sprintf('relu%d',k))
                    ]; %#ok<AGROW>
            end

            layers = [layers;
                convolution2dLayer(3, Cout, 'Padding','same', 'Name','convOut')
                regressionLayer('Name','loss')
                ];
        end

        function [X, Cout] = packForNet_(obj, H, varargin)
            % Pack complex CSI tensor to 4D array [F T Cin 1].
            % Cin = 2*Nlink (+1 if UseNoiseVarChannel).

            noiseVar = [];
            if ~isempty(varargin)
                if mod(numel(varargin),2) ~= 0
                    error('sixgr:NeuralChannelEstimator:BadNV','Name-value inputs must come in pairs.');
                end
                for i = 1:2:numel(varargin)
                    k = varargin{i}; v = varargin{i+1};
                    if isstring(k), k = char(k); end
                    switch lower(char(k))
                        case 'noisevar'
                            noiseVar = v;
                        otherwise
                            error('sixgr:NeuralChannelEstimator:BadOpt','Unknown option: %s', string(k));
                    end
                end
            end

            if ~isnumeric(H)
                error('sixgr:NeuralChannelEstimator:BadH','H must be numeric.');
            end

            % Require at least 2 dims for F x T. If 1D, treat T=1.
            sz = size(H);
            if numel(sz) == 2
                F = sz(1); T = sz(2);
                rest = 1;
            elseif numel(sz) == 1
                F = sz(1); T = 1;
                rest = 1;
            else
                F = sz(1); T = sz(2);
                rest = prod(sz(3:end));
            end

            H2 = reshape(H, [F T rest]);
            % Pack real/imag into channels
            if isreal(H2)
                % Treat as real-only with 1*rest channels
                Re = single(H2);
                CinBase = rest;
                Xc = Re;
                % Expand to 4D: [F T Cin 1]
                Xc = reshape(Xc, [F T CinBase 1]);
                Cout = CinBase;
            else
                Re = single(real(H2));
                Im = single(imag(H2));
                CinBase = 2*rest;
                Xc = cat(3, Re, Im);  % [F T 2*rest]
                Xc = reshape(Xc, [F T CinBase 1]);
                Cout = CinBase;
            end

            if obj.UseNoiseVarChannel
                nv = single(0);
                if ~isempty(noiseVar)
                    nv = single(log10(max(double(noiseVar), 1e-12)));
                end
                nvPlane = nv * ones(F, T, 1, 1, 'single');
                X = cat(3, Xc, nvPlane);
            else
                X = Xc;
            end
        end

        function Y = packTarget_(obj, Hls, Htrue, Cout)
            % Pack training target.
            if obj.ResidualLearning
                Ht = Htrue - Hls;
            else
                Ht = Htrue;
            end
            % Pack Ht to [F T Cout 1]
            Y = obj.packForNet_(Ht, 'NoiseVar', []);
            % packForNet_ returns Cout based on tensor. Ensure match.
            if obj.UseNoiseVarChannel
                % Target must be Cout channels (no noise plane)
                if size(Y,3) == Cout+1
                    Y = Y(:,:,1:Cout,:);
                end
            end
            if size(Y,3) ~= Cout
                error('sixgr:NeuralChannelEstimator:TargetDim','Target channel count mismatch. Expected %d, got %d.', Cout, size(Y,3));
            end
        end

        function H = unpackFromNet_(obj, Y, Href, Cout)
            % Convert network output [F T Cout 1] to complex tensor of same
            % shape as Href.
            F = size(Y,1);
            T = size(Y,2);
            Y = squeeze(Y);
            if ndims(Y) == 2
                Y = reshape(Y, [F T 1]);
            end

            % Determine rest dims from Href
            sz = size(Href);
            if numel(sz) <= 2
                rest = 1;
                outShape = [F T];
            else
                rest = prod(sz(3:end));
                outShape = sz;
            end

            if isreal(Href)
                % Real-only
                if Cout ~= rest
                    error('sixgr:NeuralChannelEstimator:UnpackDim','Output channel mismatch for real Href.');
                end
                Hr = reshape(single(Y), [F T rest]);
                H = reshape(Hr, outShape);
            else
                if Cout ~= 2*rest
                    error('sixgr:NeuralChannelEstimator:UnpackDim','Output channel mismatch for complex Href.');
                end
                Yr = reshape(single(Y), [F T 2*rest]);
                Re = Yr(:,:,1:rest);
                Im = Yr(:,:,rest+1:end);
                Hc = complex(Re, Im);
                H = reshape(Hc, outShape);
            end
        end

        function C = toCellSamples_(obj, X) %#ok<INUSL>
            if iscell(X)
                C = X(:);
                return;
            end
            if ~isnumeric(X)
                error('sixgr:NeuralChannelEstimator:BadData','Samples must be cell or numeric.');
            end

            % Interpret last dimension as sample index if > 1 and ndims >= 3
            sz = size(X);
            if ndims(X) < 3 || sz(end) == 1
                C = {X};
                return;
            end

            nObs = sz(end);
            C = cell(nObs,1);
            for i = 1:nObs
                idx = repmat({':'},1,ndims(X));
                idx{end} = i;
                C{i} = X(idx{:});
            end
        end
    end
end
