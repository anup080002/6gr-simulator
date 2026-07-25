function text = pdschVectorEncodeIntegers(values)
%PDSCHVECTORENCODEINTEGERS Encode an expanded integer vector with pipes.

values = double(values(:).');
if isempty(values)
    text = "";
else
    text = strjoin(string(values), "|");
end
end
