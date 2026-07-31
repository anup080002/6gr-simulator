function wrote = safeFprintf(varargin)
%SAFEFPRINTF Best-effort diagnostic output that never stops simulation.
%
% Use this only for optional console/log diagnostics. File and artifact
% writes that carry simulation evidence must continue to fail loudly.

wrote = false;
try
    fprintf(varargin{:});
    wrote = true;
catch
    % A detached or closed WebGUI stdout stream must not abort PHY work.
end
end
