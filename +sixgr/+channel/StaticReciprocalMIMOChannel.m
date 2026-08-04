classdef StaticReciprocalMIMOChannel < matlab.System
%STATICRECIPROCALMIMOCHANNEL Exact static reciprocal MIMO FIR endpoint.
% The impulse response is measured from the configured toolbox fading
% channel.  The reverse endpoint uses the nonconjugate spatial transpose,
% H_UL(tau)=H_DL(tau).', required by calibrated TDD reciprocity.

    properties (SetAccess=private)
        ImpulseResponse
        NumTransmitAntennas
        NumReceiveAntennas
        SampleRate
        PathDelays
        ChannelFilterDelay = 0
        SourceChannelClass
        SourceChannelSeed
        ReciprocityDirection
    end

    properties (Access=private)
        FilterState
    end

    methods
        function obj = StaticReciprocalMIMOChannel(impulseResponse, sampleRate, varargin)
            % MATLAB object deserialization first constructs an unlocked
            % shell and then calls loadObjectImpl.  The identity shell is
            % never an execution fallback: every persisted property is
            % overwritten from the serialized production object below.
            if nargin == 0
                impulseResponse = 1;
                sampleRate = 1;
            end
            p = inputParser;
            p.addParameter("SourceChannelClass", "", @(x)ischar(x)||isstring(x));
            p.addParameter("SourceChannelSeed", NaN, @(x)isnumeric(x)&&isscalar(x));
            p.addParameter("Direction", "DL", @(x)ischar(x)||isstring(x));
            p.parse(varargin{:});
            h = double(impulseResponse);
            % MATLAB removes trailing singleton dimensions, so an exact
            % L-by-NRx-by-1 impulse response reports ndims(h)==2. This is
            % the normal physical shape for PRACH and other single-port UL
            % signals; size(h,3) still returns one and must remain valid.
            if ~(isnumeric(h) && ndims(h) <= 3 && ~isempty(h) && ...
                    all(isfinite(real(h(:)))) && all(isfinite(imag(h(:)))) && ...
                    norm(h(:)) > 0)
                error("sixgr:channel:InvalidReciprocalImpulseResponse", ...
                    "Reciprocal runtime channel requires a finite nonzero L-by-NRx-by-NTx impulse response.");
            end
            fs = double(sampleRate);
            if ~(isscalar(fs) && isfinite(fs) && fs > 0)
                error("sixgr:channel:InvalidReciprocalSampleRate", ...
                    "Reciprocal runtime channel requires a finite positive sample rate.");
            end
            obj.ImpulseResponse = h;
            obj.NumReceiveAntennas = double(size(h,2));
            obj.NumTransmitAntennas = double(size(h,3));
            obj.SampleRate = fs;
            obj.PathDelays = (0:(size(h,1)-1)) ./ fs;
            obj.SourceChannelClass = char(string(p.Results.SourceChannelClass));
            obj.SourceChannelSeed = double(p.Results.SourceChannelSeed);
            obj.ReciprocityDirection = char(upper(strtrim(string(p.Results.Direction))));
        end

    end

    methods (Access=protected)
        function setupImpl(obj, ~)
            obj.FilterState = complex(zeros( ...
                max(0,size(obj.ImpulseResponse,1)-1), ...
                obj.NumReceiveAntennas,obj.NumTransmitAntennas));
        end

        function resetImpl(obj)
            obj.FilterState = complex(zeros( ...
                max(0,size(obj.ImpulseResponse,1)-1), ...
                obj.NumReceiveAntennas,obj.NumTransmitAntennas));
        end

        function [y, appliedImpulseResponse] = stepImpl(obj, x)
            if ~(isnumeric(x) && ismatrix(x) && size(x,2) == obj.NumTransmitAntennas)
                error("sixgr:channel:ReciprocalRuntimeDimensionMismatch", ...
                    "Reciprocal %s endpoint requires %d transmit columns; observed %d.", ...
                    obj.ReciprocityDirection, obj.NumTransmitAntennas, size(x,2));
            end
            y = complex(zeros(size(x,1),obj.NumReceiveAntennas,"like",x));
            for rx = 1:obj.NumReceiveAntennas
                for tx = 1:obj.NumTransmitAntennas
                    h = cast(obj.ImpulseResponse(:,rx,tx),"like",x);
                    if size(obj.ImpulseResponse,1) > 1
                        zi = cast(obj.FilterState(:,rx,tx),"like",x);
                        [part,zf] = filter(h,1,x(:,tx),zi);
                        obj.FilterState(:,rx,tx) = double(zf);
                    else
                        part = h .* x(:,tx);
                    end
                    y(:,rx) = y(:,rx) + part;
                end
            end
            appliedImpulseResponse = obj.ImpulseResponse;
        end

        function n = getNumOutputsImpl(~)
            n = 2;
        end

        function state = saveObjectImpl(obj)
            state = saveObjectImpl@matlab.System(obj);
            state.ImpulseResponse = obj.ImpulseResponse;
            state.NumTransmitAntennas = obj.NumTransmitAntennas;
            state.NumReceiveAntennas = obj.NumReceiveAntennas;
            state.SampleRate = obj.SampleRate;
            state.PathDelays = obj.PathDelays;
            state.ChannelFilterDelay = obj.ChannelFilterDelay;
            state.SourceChannelClass = obj.SourceChannelClass;
            state.SourceChannelSeed = obj.SourceChannelSeed;
            state.ReciprocityDirection = obj.ReciprocityDirection;
            state.FilterState = obj.FilterState;
        end

        function loadObjectImpl(obj, state, wasLocked)
            obj.ImpulseResponse = state.ImpulseResponse;
            obj.NumTransmitAntennas = state.NumTransmitAntennas;
            obj.NumReceiveAntennas = state.NumReceiveAntennas;
            obj.SampleRate = state.SampleRate;
            obj.PathDelays = state.PathDelays;
            obj.ChannelFilterDelay = state.ChannelFilterDelay;
            obj.SourceChannelClass = state.SourceChannelClass;
            obj.SourceChannelSeed = state.SourceChannelSeed;
            obj.ReciprocityDirection = state.ReciprocityDirection;
            if isfield(state, "FilterState")
                obj.FilterState = state.FilterState;
            else
                obj.FilterState = complex(zeros( ...
                    max(0,size(obj.ImpulseResponse,1)-1), ...
                    obj.NumReceiveAntennas,obj.NumTransmitAntennas));
            end
            loadObjectImpl@matlab.System(obj, state, wasLocked);
        end
    end
end
