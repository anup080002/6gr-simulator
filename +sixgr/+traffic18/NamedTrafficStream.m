classdef NamedTrafficStream < handle
    %NAMEDTRAFFICSTREAM Per-flow deterministic RNG; never uses global RNG.

    properties (SetAccess = immutable)
        MasterSeed (1,1) double
        StreamIdentity (1,1) string
        DerivedSeed (1,1) double
    end

    properties (Access = private)
        Stream
    end

    methods
        function obj = NamedTrafficStream(masterSeed, identity)
            arguments
                masterSeed (1,1) double {mustBeInteger,mustBeNonnegative}
                identity (1,1) string
            end
            if strlength(identity) == 0
                error("sixgr:traffic:NonDeterministicStream", ...
                    "Traffic random-stream identity cannot be empty.");
            end
            obj.MasterSeed = masterSeed;
            obj.StreamIdentity = identity;
            digest = sixgr.protocol.ProtocolHash.bytes( ...
                string(masterSeed) + "|" + identity);
            derived = hex2dec(char(extractBetween(digest, 1, 8)));
            obj.DerivedSeed = mod(double(derived), 2^32-1);
            obj.Stream = RandStream("mt19937ar", "Seed", obj.DerivedSeed);
        end

        function value = uniform(obj, varargin)
            value = rand(obj.Stream, varargin{:});
        end

        function value = normal(obj, varargin)
            value = randn(obj.Stream, varargin{:});
        end

        function value = integer(obj, range, varargin)
            value = randi(obj.Stream, range, varargin{:});
        end
    end
end
