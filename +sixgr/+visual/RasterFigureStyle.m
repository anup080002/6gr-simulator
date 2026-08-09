classdef RasterFigureStyle
    %RASTERFIGURESTYLE Deterministic light styling for exported PNG figures.
    %
    % MATLAB desktop themes can change the inherited axes, text, legend and
    % colorbar colors even when a producer explicitly creates a white
    % figure.  Artifact rasters must not depend on the operator's desktop
    % theme, so qualification runners install these defaults before figures
    % are created and runtime renderers normalize the completed figure.

    methods (Static)
        function prior = installDefaults()
            root = groot;
            properties = [ ...
                "DefaultFigureColor", "DefaultFigureInvertHardcopy", ...
                "DefaultAxesColor", "DefaultAxesXColor", ...
                "DefaultAxesYColor", "DefaultAxesZColor", ...
                "DefaultAxesGridColor", "DefaultAxesMinorGridColor", ...
                "DefaultAxesFontName", "DefaultTextColor", ...
                "DefaultLegendColor", "DefaultLegendTextColor", ...
                "DefaultLegendEdgeColor", "DefaultColorbarColor"];
            values = { ...
                [1 1 1], "off", ...
                [1 1 1], [0.12 0.16 0.22], ...
                [0.12 0.16 0.22], [0.12 0.16 0.22], ...
                [0.72 0.76 0.82], [0.82 0.85 0.89], ...
                "Arial", [0.12 0.16 0.22], ...
                [1 1 1], [0.12 0.16 0.22], ...
                [0.72 0.76 0.82], [0.12 0.16 0.22]};
            supported = false(size(properties));
            priorValues = cell(size(properties));
            for index = 1:numel(properties)
                name = properties(index);
                % Graphics-root default properties are dynamic HG defaults;
                % isprop(groot,"DefaultAxesColor") is false in R2026a even
                % though get/set accepts the property. Probe the graphics
                % API directly so qualification figures created later in a
                % phase runner actually inherit this style.
                try
                    priorValues{index} = get(root, char(name));
                    set(root, char(name), values{index});
                    supported(index) = true;
                catch
                    % Releases differ in optional legend/colorbar defaults.
                    % Unsupported defaults are simply omitted from restore.
                end
            end
            prior = struct( ...
                "Properties", properties(supported), ...
                "Values", {priorValues(supported)});
        end

        function restoreDefaults(prior)
            if ~(isstruct(prior) && isscalar(prior) && ...
                    isfield(prior, "Properties") && isfield(prior, "Values"))
                return;
            end
            root = groot;
            properties = string(prior.Properties);
            values = prior.Values;
            for index = 1:numel(properties)
                name = properties(index);
                try
                    set(root, char(name), values{index});
                catch
                    % Ignore a default removed by a release change between
                    % installation and cleanup.
                end
            end
        end

        function apply(figureHandle)
            if ~(isscalar(figureHandle) && isgraphics(figureHandle, "figure"))
                error("sixgr:visual:RasterFigureRequired", ...
                    "Raster styling requires one MATLAB figure handle.");
            end
            dark = [0.12 0.16 0.22];
            gridColor = [0.72 0.76 0.82];
            set(figureHandle, "Color", "white", "InvertHardcopy", "off");

            axesHandles = findall(figureHandle, "Type", "axes");
            for index = 1:numel(axesHandles)
                ax = axesHandles(index);
                set(ax, "Color", "white", "XColor", dark, ...
                    "YColor", dark, "ZColor", dark, ...
                    "GridColor", gridColor, ...
                    "MinorGridColor", gridColor, "FontName", "Arial");
                localStyleText(ax.Title, dark);
                localStyleText(ax.Subtitle, dark);
                localStyleText(ax.XLabel, dark);
                localStyleText(ax.YLabel, dark);
                localStyleText(ax.ZLabel, dark);
            end

            legends = findall(figureHandle, "Type", "legend");
            for index = 1:numel(legends)
                set(legends(index), "Color", "white", ...
                    "TextColor", dark, "EdgeColor", gridColor);
            end
            colorbars = findall(figureHandle, "Type", "colorbar");
            for index = 1:numel(colorbars)
                set(colorbars(index), "Color", dark);
            end
            textHandles = findall(figureHandle, "Type", "text");
            for index = 1:numel(textHandles)
                localStyleText(textHandles(index), dark);
            end
            drawnow;
        end
    end
end

function localStyleText(handle, color)
if ~isempty(handle) && isgraphics(handle) && isprop(handle, "Color")
    handle.Color = color;
end
end
