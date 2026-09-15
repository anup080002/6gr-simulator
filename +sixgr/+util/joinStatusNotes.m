function notes=joinStatusNotes(varargin)
% Stable ordered note set, including text already joined by a prior pass.
% No status boolean, count or failure identifier is reduced here.
parts=strings(0,1);
for k=1:nargin
    values=string(varargin{k});
    for value=values(:).'
        if ismissing(value), continue; end
        atoms=strtrim(split(value," | "));
        parts=[parts;atoms(:)]; %#ok<AGROW>
    end
end
parts=parts(strlength(parts)>0);
notes=strjoin(unique(parts,"stable")," | ");
end
