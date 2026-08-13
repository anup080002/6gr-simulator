classdef TimeDomainProfile
    %TIMEDOMAINPROFILE Exact configured DM-RS group-start derivation.

    methods (Static)
        function profile = resolve(spec)
            arguments
                spec (1,1) struct
            end
            required = ["NSym","X","FirstOffsetSymbols"];
            for name = required
                if ~isfield(spec, name)
                    error("sixgr:ran1ai10522:MissingTimeDomainField", ...
                        "Time-domain profile field %s is required.", name);
                end
            end
            nSym = localPositiveInteger(spec.NSym, "NSym");
            X = localPositiveInteger(spec.X, "X");
            if ~ismember(X, [1 2 4])
                error("sixgr:ran1ai10522:UnsupportedX", "X must be one of [1 2 4].");
            end
            l0 = localNonnegativeInteger(spec.FirstOffsetSymbols, "FirstOffsetSymbols");
            lmax = nSym - X;
            if lmax < 0 || l0 > lmax
                error("sixgr:ran1ai10522:ProfileDoesNotFit", ...
                    "The configured X=%d and first offset=%d do not fit N_sym=%d.", X, l0, nSym);
            end
            supported = sixgr.studies.ran1ai10522.TimeDomainProfile.supportedL(X);
            explicit = isfield(spec, "L") && ~isempty(spec.L);
            if explicit
                L = localPositiveInteger(spec.L, "L");
                source = "explicit_L";
            else
                if ~isfield(spec, "MaxGroupStartSpacingG")
                    error("sixgr:ran1ai10522:MissingImplicitSpacing", ...
                        "MaxGroupStartSpacingG is required when L is implicit.");
                end
                G = localPositiveInteger(spec.MaxGroupStartSpacingG, "MaxGroupStartSpacingG");
                D = lmax - l0;
                if D == 0
                    requiredL = 1;
                else
                    requiredL = 1 + ceil(D / G);
                end
                candidates = supported(supported >= requiredL & (l0 + supported .* X <= nSym));
                if isempty(candidates)
                    error("sixgr:ran1ai10522:NoSupportedImplicitL", ...
                        "No supported L satisfies N_sym=%d, X=%d, l0=%d and G=%d.", ...
                        nSym, X, l0, G);
                end
                L = min(candidates);
                source = "implicit_G";
            end
            if ~ismember(L, supported)
                error("sixgr:ran1ai10522:UnsupportedL", ...
                    "L=%d is unsupported for X=%d; allowed values are %s.", ...
                    L, X, mat2str(supported));
            end
            if l0 + L * X > nSym
                error("sixgr:ran1ai10522:ProfileDoesNotFit", ...
                    "The no-shift fit condition l0 + L*X <= N_sym failed.");
            end
            positions = sixgr.studies.ran1ai10522.TimeDomainProfile.place(nSym, X, L, l0);
            if L > 1 && isfield(spec, "MaxGroupStartSpacingG") && ...
                    max(diff(positions)) > double(spec.MaxGroupStartSpacingG)
                error("sixgr:ran1ai10522:SpacingContractViolated", ...
                    "The derived maximum group-start spacing exceeds G.");
            end
            profile = struct("NSym", nSym, "X", X, "L", L, ...
                "FirstOffsetSymbols", l0, "LastGroupStart", lmax, ...
                "GroupStartSymbols", positions, "DerivationSource", source, ...
                "NoImplicitShift", true, "Fits", true);
        end

        function positions = place(nSym, X, L, l0)
            nSym = localPositiveInteger(nSym, "NSym");
            X = localPositiveInteger(X, "X");
            L = localPositiveInteger(L, "L");
            l0 = localNonnegativeInteger(l0, "FirstOffsetSymbols");
            if ~ismember(L, sixgr.studies.ran1ai10522.TimeDomainProfile.supportedL(X)) || ...
                    l0 + L * X > nSym
                error("sixgr:ran1ai10522:ProfileDoesNotFit", ...
                    "Configured L/X/l0 tuple is unsupported or does not fit the allocation.");
            end
            if L == 1
                positions = l0;
                return;
            end
            D = (nSym - X) - l0;
            q = floor(D / (L - 1));
            r = D - q * (L - 1);
            gaps = [repmat(q, 1, L - 1 - r), repmat(q + 1, 1, r)];
            if any(gaps < X)
                error("sixgr:ran1ai10522:OverlappingGroups", ...
                    "Derived DM-RS groups overlap; no implicit symbol shift is permitted.");
            end
            positions = l0 + [0 cumsum(gaps)];
            if positions(end) ~= nSym - X || max(gaps) - min(gaps) > 1
                error("sixgr:ran1ai10522:PlacementInvariant", ...
                    "Floor/remainder placement failed its exact end/gap invariant.");
            end
        end

        function values = supportedL(X)
            switch double(X)
                case 1, values = 1:6;
                case 2, values = 1:3;
                case 4, values = 1;
                otherwise
                    error("sixgr:ran1ai10522:UnsupportedX", "X must be one of [1 2 4].");
            end
        end

        function bits = normalizedPreEstimationBits(QIQ, nRx, nSC, nWait)
            values = double([QIQ nRx nSC nWait]);
            if any(~isfinite(values) | values <= 0 | values ~= fix(values))
                error("sixgr:ran1ai10522:InvalidBufferDimension", ...
                    "Q_IQ, N_rx, N_sc and N_wait must be positive integers.");
            end
            bits = 2 * prod(values);
        end

        function postVariance = despreadNoiseVariance(preVariance, X)
            if ~(isscalar(preVariance) && isnumeric(preVariance) && isfinite(preVariance) && preVariance >= 0)
                error("sixgr:ran1ai10522:InvalidNoiseVariance", ...
                    "Pre-despreading variance must be a finite nonnegative scalar.");
            end
            X = localPositiveInteger(X, "X");
            if ~ismember(X, [1 2 4])
                error("sixgr:ran1ai10522:UnsupportedX", "X must be one of [1 2 4].");
            end
            postVariance = double(preVariance) / X;
        end
    end
end

function value = localPositiveInteger(value, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 1 && value == fix(value))
    error("sixgr:ran1ai10522:InvalidInteger", "%s must be a positive integer.", name);
end
end

function value = localNonnegativeInteger(value, name)
value = double(value);
if ~(isscalar(value) && isfinite(value) && value >= 0 && value == fix(value))
    error("sixgr:ran1ai10522:InvalidInteger", "%s must be a nonnegative integer.", name);
end
end
