function y = applyFractionalSampleDelay(x, delaySamples)
%APPLYFRACTIONALSAMPLEDELAY Apply a zero-padded fractional sample delay.
% Positive delaySamples delays the waveform: y[n] = x[n-delaySamples].

delaySamples = double(delaySamples);
if isempty(x) || ~(isscalar(delaySamples) && isfinite(delaySamples)) || abs(delaySamples) < 1e-12
    y = x;
    return;
end

intPart = fix(delaySamples);
fracPart = delaySamples - intPart;
y = localApplyIntegerDelay(x, intPart);
if abs(fracPart) > 1e-12
    y = localApplyWindowedSincFractionalDelay(y, fracPart);
end
end

function y = localApplyIntegerDelay(x, intDelay)
intDelay = round(double(intDelay));
y = x;
if intDelay > 0
    if intDelay >= size(x, 1)
        y = zeros(size(x), "like", x);
    else
        y = [zeros(intDelay, size(x, 2), "like", x); x(1:end-intDelay, :)];
    end
elseif intDelay < 0
    adv = abs(intDelay);
    if adv >= size(x, 1)
        y = zeros(size(x), "like", x);
    else
        y = [x(adv+1:end, :); zeros(adv, size(x, 2), "like", x)];
    end
end
end

function y = localApplyWindowedSincFractionalDelay(x, fracDelay)
N = size(x, 1);
if N <= 1
    y = x;
    return;
end

span = min(16, max(1, N - 1));
n = (1:N).';
yWork = complex(zeros(size(x)));
xWork = double(x);
for tap = -span:span
    src = n - tap;
    valid = src >= 1 & src <= N;
    if ~any(valid)
        continue;
    end
    win = 0.54 + 0.46 * cos(pi * double(tap) / double(span));
    coeff = localSinc(double(tap) - double(fracDelay)) * win;
    if coeff ~= 0
        yWork(valid, :) = yWork(valid, :) + coeff .* xWork(src(valid), :);
    end
end

if isreal(x)
    yWork = real(yWork);
end
y = zeros(size(x), "like", x);
y(:,:) = yWork;
end

function y = localSinc(x)
if abs(x) < 1e-12
    y = 1;
else
    y = sin(pi * x) ./ (pi * x);
end
end
