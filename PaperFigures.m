classdef PaperFigures < handle
% PaperFigures  All data-driven paper figures of the VERA-PHM / TwinAdapt-PHM Methodology and Results, in one file.
%
%   Put this file in the Reformable_AI folder (next to the Stage10*/Stage14* CSV files) and run
%       p = PaperFigures();   p.run();             % builds every figure
%       p.Fig03_parameter_mismatch();              % or just one
%   Output: Paper_Figures/ with a vector PDF and a 600 dpi PNG per figure, plus FigNN_..._data.csv with every plotted number.
%   Different folder or file names: change them in the constructor (or pass the data folder: PaperFigures('C:\path')).
%   Nothing in your data, models or results is modified. Needs R2020a or later (exportgraphics).
%
%   Fig01 primary contrast (F, F2)        Fig05 per-run MAE, S3 vs C2
%   Fig02 ablation heat maps              Fig06 residual vs time at D = 0..1
%   Fig03 Twin parameter-error curves     Fig07 operating profiles P1-P4, B1-B4
%   Fig04 start-SOC and sensor-fault damage   Fig08 plant model curves at D = 0, 0.5, 1
%   Fig08 reads PV_Params_Stage1, PV_Degradation_Params, Battery_Params_Stage3, Battery_Degradation_Params (.mat).
  properties
    cfg   % settings: folders, file names, colours, fonts, the eight comparison cells
  end
  methods
    function obj = PaperFigures(here)
      c = struct();
      % Settings. Edit here if a file name or folder differs on your machine.
    if nargin < 1 || isempty(here), here = fileparts(which('PaperFigures')); end
    c.dataDir = here;                                  % folder that holds the result CSVs and Dataset A CSVs
    c.outDir  = fullfile(here, 'Paper_Figures');       % figures are written here (created if missing)
    if ~exist(c.outDir, 'dir'), mkdir(c.outDir); end
    
    % result files (names exactly as produced by the Stage10G / Stage10G2 / Stage14 scripts)
    c.files.diffF      = 'Stage10G_Final_Differences.csv';
    c.files.diffF2     = 'Stage10G2_Final_Differences.csv';
    c.files.perrunF    = 'Stage10G_Final_PerRun.csv';
    c.files.perrunF2   = 'Stage10G2_Final_PerRun.csv';
    c.files.stressDiff = 'Stage14_Stress_Differences.csv';
    c.files.pvA        = 'Stage10_PV_Controlled.csv';        % Dataset A, PV runs
    c.files.batA       = 'Stage10_Battery_Controlled.csv';   % Dataset A, battery runs
    
    % row names used inside the CSV files
    c.fsS3 = 'S3 sensor strong (baseline)';
    c.fsC2 = 'C2 strong + residual windows';
    
    % look
    c.font = 'Arial';  c.fs = 9;
    c.blue   = [0.122 0.373 0.659];
    c.orange = [0.788 0.337 0.047];
    c.purple = [0.416 0.239 0.604];
    c.grey   = [0.55 0.55 0.55];
    c.ink    = [0.13 0.13 0.13];
    c.gridc  = [0.89 0.89 0.89];
    
    % the eight comparison cells, in the order used in every figure
    assets = {'PV', 'Battery'};  regs = {'A-', 'B-'};  regname = {'unseen levels', 'new profile'};
    models = {'ridge', 'nn'};    mname = {'ridge', 'network'};
    k = 0;
    for a = 1:2
      for r = 1:2
        for m = 1:2
          k = k + 1;
          c.cells(k).asset = assets{a};
          c.cells(k).reg   = regs{r};
          c.cells(k).model = models{m};
          c.cells(k).label = sprintf('%s, %s, %s', assets{a}, regname{r}, mname{m});
        end
      end
    end
          obj.cfg = c;
    end

    function run(obj)
      % Build every figure; one that fails (for example a missing file) is reported and the rest still run.
      list = {'Fig01_primary_contrast', 'Fig02_ablation_heatmap', 'Fig03_parameter_mismatch', 'Fig04_soc_and_faults', 'Fig05_per_run_scatter', 'Fig06_residual_vs_health', 'Fig07_operating_profiles', 'Fig08_model_curves'};
      ok = false(size(list));
      for i = 1:numel(list)
        fprintf('%s ...\n', list{i});
        try
          obj.(list{i})();  ok(i) = true;
        catch err
          fprintf(2, '  FAILED: %s\n', err.message);
          if ~isempty(err.stack), fprintf(2, '  at %s line %d\n', err.stack(1).name, err.stack(1).line); end
          close all force;
        end
      end
      fprintf('\n%d of %d figures written to %s\n', nnz(ok), numel(list), obj.cfg.outDir);
      if ~all(ok), fprintf('Not written: %s\n', strjoin(list(~ok), ', ')); end
    end

    function Fig01_primary_contrast(obj)
    % Figure: primary contrast C2 - S3 (change in mean per-run MAE; negative = residual features help).
    % Filled = Dataset F, hollow = replication F2. Bars = 95% bootstrap interval over runs.
    % Source: Stage10G_Final_Differences.csv and Stage10G2_Final_Differences.csv. Output: Fig01_primary_contrast.
    cfg = obj.cfg;
    TF  = figRead(cfg, cfg.files.diffF);
    TF2 = figRead(cfg, cfg.files.diffF2);
    f = figNew(17.5, 7.2);
    assets = {'PV', 'Battery'};  unit = {'A', 'V'};
    log = zeros(0, 8);  k = 0;
    for a = 1:2
      ax = figAxes(f, cfg, [0.15 + 0.46*(a-1), 0.17, 0.30, 0.70]);
      idx = find(strcmp({cfg.cells.asset}, assets{a}));
      for j = 1:numel(idx)
        c = cfg.cells(idx(j));  y = numel(idx) - j + 1;
        for s = 1:2
          if s == 1, T = TF; dy = 0.14; else, T = TF2; dy = -0.14; end
          i = figPick(T, c, cfg.fsC2);
          d = T.MeanDiffMAE_vs_S3(i);  lo = T.CI95_low(i);  hi = T.CI95_high(i);
          col = cfg.blue;  if strcmp(c.model, 'nn'), col = cfg.orange; end
          line(ax, [lo hi], [y+dy y+dy], 'Color', col, 'LineWidth', 1.2);
          if s == 1, fc = col; else, fc = 'w'; end
          plot(ax, d, y+dy, 'o', 'MarkerSize', 5.5, 'MarkerFaceColor', fc, 'MarkerEdgeColor', col, 'LineWidth', 1.1);
          k = k + 1;  log(k, :) = [a, idx(j), s, d, lo, hi, T.FractionRunsBetter(i), T.nTestRuns(i)];
        end
      end
      plot(ax, [0 0], [0.4 numel(idx)+0.6], '-', 'Color', cfg.grey, 'LineWidth', 0.8);
      set(ax, 'YLim', [0.4 numel(idx)+0.6], 'YTick', 1:numel(idx), 'YTickLabel', fliplr({cfg.cells(idx).label}), ...
          'TickLabelInterpreter', 'none', 'XGrid', 'on', 'GridColor', cfg.gridc, 'GridAlpha', 1);
      if a == 2, set(ax, 'YTickLabel', []); end
      xlabel(ax, sprintf('Change in mean per-run MAE, C2 minus S3 (%s)', unit{a}), 'FontName', cfg.font, 'FontSize', cfg.fs);
      title(ax, assets{a}, 'FontName', cfg.font, 'FontSize', cfg.fs+1, 'FontWeight', 'bold');
    end
    figLog(cfg, 'Fig01_primary_contrast', 'asset(1PV2Bat),cell,set(1F2F2),diff,ci_low,ci_high,fraction_runs_better,n_runs', log);
    figSave(f, cfg, 'Fig01_primary_contrast');
    end

    function Fig02_ablation_heatmap(obj)
    % Figure: feature-set ablation. Cell value = change in mean per-run MAE versus S3 (negative = better than baseline).
    % Rows = feature sets, columns = regime x model. * = 95% interval excludes zero.
    % Source: Stage10G_Final_Differences.csv (F) and Stage10G2_Final_Differences.csv (F2). Output: Fig02_ablation_heatmap.
    cfg = obj.cfg;
    src = {figRead(cfg, cfg.files.diffF), figRead(cfg, cfg.files.diffF2)};
    sets = {'C1 strong + raw residuals', 'C2 strong + residual windows', 'C2-mean (window mean only)', ...
            'C2-std (window std only)', 'C2-maxabs (window max-abs only)', 'C2-trend (window trend only)'};
    setlab = {'C1 raw residuals', 'C2 all windows', 'C2 mean only', 'C2 std only', 'C2 max-abs only', 'C2 trend only'};
    assets = {'PV', 'Battery'};  unit = {'A', 'V'};  dsn = {'Dataset F', 'Dataset F2'};
    f = figNew(17.5, 11.5);  cm = figDiverging(256);  log = zeros(0, 8);  k = 0;
    for a = 1:2
      idx = find(strcmp({cfg.cells.asset}, assets{a}));
      V = nan(6, 8);  SG = false(6, 8);
      for s = 1:2
        for r = 1:6
          for j = 1:4
            i = figPick(src{s}, cfg.cells(idx(j)), sets{r});
            V(r, (s-1)*4 + j) = src{s}.MeanDiffMAE_vs_S3(i);
            SG(r, (s-1)*4 + j) = src{s}.CI95_low(i) * src{s}.CI95_high(i) > 0;
            k = k + 1;  log(k, :) = [a, s, r, j, V(r, (s-1)*4+j), src{s}.CI95_low(i), src{s}.CI95_high(i), SG(r, (s-1)*4+j)];
          end
        end
      end
      m = max(abs(V(:)));
      ax = figAxes(f, cfg, [0.17, 0.57 - 0.48*(a-1), 0.70, 0.36]);
      imagesc(ax, V, [-m m]);  colormap(ax, cm);
      cb = colorbar(ax);  set(cb, 'FontName', cfg.font, 'FontSize', cfg.fs-1);
      ylabel(cb, sprintf('Change in MAE vs S3 (%s)', unit{a}), 'FontName', cfg.font, 'FontSize', cfg.fs-1);
      fmt = '%.3f';  if m < 0.01, fmt = '%.4f'; end
      for r = 1:6
        for q = 1:8
          t = sprintf(fmt, V(r, q));  if SG(r, q), t = [t '*']; end
          tc = cfg.ink;  if abs(V(r, q)) > 0.6*m, tc = 'w'; end
          text(ax, q, r, t, 'HorizontalAlignment', 'center', 'FontName', cfg.font, 'FontSize', cfg.fs-1.5, 'Color', tc);
        end
      end
      plot(ax, [4.5 4.5], [0.5 6.5], '-', 'Color', 'w', 'LineWidth', 3);
      xl = cell(1, 8);
      for q = 1:8, xl{q} = strrep(cfg.cells(idx(mod(q-1, 4)+1)).label(numel(assets{a})+3:end), ', ', newline); end
      set(ax, 'XTick', 1:8, 'XTickLabel', xl, 'YTick', 1:6, 'YTickLabel', setlab, 'TickLabelInterpreter', 'none', ...
          'YDir', 'reverse', 'XLim', [0.5 8.5], 'YLim', [0.5 6.5], 'Box', 'on');
      title(ax, sprintf('%s     (left: %s, right: %s)', assets{a}, dsn{1}, dsn{2}), 'FontName', cfg.font, 'FontSize', cfg.fs+1, 'FontWeight', 'bold');
    end
    figLog(cfg, 'Fig02_ablation_heatmap', 'asset(1PV2Bat),dataset(1F2F2),set,cell,diff,ci_low,ci_high,ci_excludes_zero', log);
    figSave(f, cfg, 'Fig02_ablation_heatmap');
    end

    function Fig03_parameter_mismatch(obj)
    % Figure: how the C2 - S3 contrast changes as the Twin's parameters become wrong (frozen models, re-simulated F).
    % x = random Twin parameter error (0 = clean, 2, 5, 10 %). Colour = model, line style = test regime. Bars = 95% interval.
    % Source: Stage14_Stress_Differences.csv, contrast 'C2 minus S3 (same condition)'. Output: Fig03_parameter_mismatch.
    cfg = obj.cfg;
    T = figRead(cfg, cfg.files.stressDiff);
    conds = {'clean', 'E1b', 'E1', 'E2'};  xv = [0 2 5 10];
    assets = {'PV', 'Battery'};  unit = {'A', 'V'};  log = zeros(0, 7);  k = 0;
    f = figNew(17.5, 7.4);
    for a = 1:2
      ax = figAxes(f, cfg, [0.09 + 0.47*(a-1), 0.19, 0.38, 0.69]);
      idx = find(strcmp({cfg.cells.asset}, assets{a}));
      for j = 1:numel(idx)
        c = cfg.cells(idx(j));
        col = cfg.blue;  if strcmp(c.model, 'nn'), col = cfg.orange; end
        ls = '-';  if strcmp(c.reg, 'B-'), ls = '--'; end
        d = nan(1, 4);  lo = d;  hi = d;
        for q = 1:4
          i = figPickStress(T, c, conds{q}, 'C2 minus S3 (same condition)');
          if ~isempty(i)
            d(q) = T.MeanDiffMAE(i);  lo(q) = T.CI95_low(i);  hi(q) = T.CI95_high(i);
            k = k + 1;  log(k, :) = [a, idx(j), xv(q), d(q), lo(q), hi(q), T.nTestRuns(i)];
          end
        end
        off = (j - 2.5) * 0.12;
        errorbar(ax, xv + off, d, d - lo, hi - d, ls, 'Color', col, 'LineWidth', 1.1, 'Marker', 'o', 'MarkerSize', 4, ...
                 'MarkerFaceColor', col, 'CapSize', 3);
      end
      plot(ax, [-0.6 10.6], [0 0], '-', 'Color', cfg.grey, 'LineWidth', 0.8);
      set(ax, 'XLim', [-0.6 10.6], 'XTick', xv, 'YGrid', 'on', 'GridColor', cfg.gridc, 'GridAlpha', 1);
      xlabel(ax, 'Random Twin parameter error (%)', 'FontName', cfg.font, 'FontSize', cfg.fs);
      ylabel(ax, sprintf('C2 minus S3 per-run MAE (%s)', unit{a}), 'FontName', cfg.font, 'FontSize', cfg.fs);
      title(ax, assets{a}, 'FontName', cfg.font, 'FontSize', cfg.fs+1, 'FontWeight', 'bold');
      if a == 1
        h1 = plot(ax, nan, nan, '-', 'Color', cfg.blue, 'LineWidth', 1.4);   h2 = plot(ax, nan, nan, '-', 'Color', cfg.orange, 'LineWidth', 1.4);
        h3 = plot(ax, nan, nan, '-', 'Color', cfg.ink, 'LineWidth', 1.1);    h4 = plot(ax, nan, nan, '--', 'Color', cfg.ink, 'LineWidth', 1.1);
        legend(ax, [h1 h2 h3 h4], {'ridge', 'network', 'unseen levels', 'new profile'}, 'Location', 'best', 'Box', 'off', ...
               'FontName', cfg.font, 'FontSize', cfg.fs-1);
      end
    end
    figLog(cfg, 'Fig03_parameter_mismatch', 'asset(1PV2Bat),cell,param_error_pct,diff,ci_low,ci_high,n_runs', log);
    figSave(f, cfg, 'Fig03_parameter_mismatch');
    end

    function Fig04_soc_and_faults(obj)
    % Figure: (a) battery C2 damage from a 3-point start-SOC offset (E3); (b,c) damage from a silent single-channel sensor fault (D)
    % for S3 and C2, PV and battery. Damage = MAE under the condition minus clean MAE (positive = worse). Bars = 95% interval.
    % Source: Stage14_Stress_Differences.csv, contrasts 'S3 damage (condition minus clean)' / 'C2 damage (condition minus clean)'.
    cfg = obj.cfg;
    T = figRead(cfg, cfg.files.stressDiff);
    dS = 'S3 damage (condition minus clean)';  dC = 'C2 damage (condition minus clean)';
    f = figNew(17.5, 7.0);  log = zeros(0, 8);  k = 0;
    panels = {{'Battery', 'E3', {dC}, 'V', '(a) Start-SOC offset, battery'}, ...
              {'PV', 'D', {dS, dC}, 'A', '(b) Silent sensor fault, PV'}, ...
              {'Battery', 'D', {dS, dC}, 'V', '(c) Silent sensor fault, battery'}};
    for p = 1:3
      P = panels{p};  ax = figAxes(f, cfg, [0.08 + 0.32*(p-1), 0.30, 0.25, 0.58]);
      idx = find(strcmp({cfg.cells.asset}, P{1}));
      for s = 1:numel(P{3})
        col = cfg.blue;  if strcmp(P{3}{s}, dC), col = cfg.orange; end
        for j = 1:numel(idx)
          i = figPickStress(T, cfg.cells(idx(j)), P{2}, P{3}{s});
          if isempty(i), continue; end
          if numel(P{3}) == 1, x = j; else, x = j + (s - 1.5) * 0.25; end
          d = T.MeanDiffMAE(i);  lo = T.CI95_low(i);  hi = T.CI95_high(i);
          line(ax, [x x], [lo hi], 'Color', col, 'LineWidth', 1.2);
          plot(ax, x, d, 'o', 'MarkerSize', 5, 'MarkerFaceColor', col, 'MarkerEdgeColor', col);
          k = k + 1;  log(k, :) = [p, s, idx(j), x, d, lo, hi, T.nTestRuns(i)];
        end
      end
      plot(ax, [0.4 4.6], [0 0], '-', 'Color', cfg.grey, 'LineWidth', 0.8);
      xl = cell(1, 4);
      for j = 1:4, xl{j} = strrep(cfg.cells(idx(j)).label(numel(P{1})+3:end), ', ', newline); end
      set(ax, 'XLim', [0.4 4.6], 'XTick', 1:4, 'XTickLabel', xl, 'TickLabelInterpreter', 'none', 'YGrid', 'on', ...
          'GridColor', cfg.gridc, 'GridAlpha', 1);
      ylabel(ax, sprintf('Damage in MAE (%s)', P{4}), 'FontName', cfg.font, 'FontSize', cfg.fs);
      title(ax, P{5}, 'FontName', cfg.font, 'FontSize', cfg.fs, 'FontWeight', 'bold');
      if p >= 2
        h1 = plot(ax, nan, nan, 'o', 'MarkerFaceColor', cfg.blue, 'MarkerEdgeColor', cfg.blue);
        h2 = plot(ax, nan, nan, 'o', 'MarkerFaceColor', cfg.orange, 'MarkerEdgeColor', cfg.orange);
        legend(ax, [h1 h2], {'S3', 'C2'}, 'Location', 'northwest', 'Box', 'off', 'FontName', cfg.font, 'FontSize', cfg.fs-1);
      end
    end
    figLog(cfg, 'Fig04_soc_and_faults', 'panel,series,cell,x,damage,ci_low,ci_high,n_runs', log);
    figSave(f, cfg, 'Fig04_soc_and_faults');
    end

    function Fig05_per_run_scatter(obj)
    % Figure: per-run test MAE, S3 (x) against C2 (y). Points below the diagonal are runs where residual features helped.
    % Filled = Dataset F, hollow = replication F2. Number = share of runs below the diagonal (F).
    % Source: Stage10G_Final_PerRun.csv and Stage10G2_Final_PerRun.csv. Output: Fig05_per_run_scatter.
    cfg = obj.cfg;
    src = {figRead(cfg, cfg.files.perrunF), figRead(cfg, cfg.files.perrunF2)};
    assets = {'PV', 'Battery'};  unit = {'A', 'V'};
    cols = {'RunMAE_ridge', 'RunMAE_network_seedmean'};  log = zeros(0, 8);  k = 0;
    f = figNew(17.5, 9.4);
    for a = 1:2
      idx = find(strcmp({cfg.cells.asset}, assets{a}));
      for j = 1:4
        c = cfg.cells(idx(j));  mc = cols{1 + strcmp(c.model, 'nn')};
        ax = figAxes(f, cfg, [0.075 + 0.235*(j-1), 0.58 - 0.45*(a-1), 0.19, 0.33]);
        col = cfg.blue;  if strcmp(c.model, 'nn'), col = cfg.orange; end
        hi = 0;  fr = nan;
        for s = 1:2
          T = src{s};
          mA = figAsset(T.Asset, c.asset) & figStarts(T.TestRegime, c.reg);
          m3 = mA & figEq(T.FeatureSet, cfg.fsS3);  m2 = mA & figEq(T.FeatureSet, cfg.fsC2);
          r3 = T.Run(m3);  r2 = T.Run(m2);  v3 = T.(mc)(m3);  v2 = T.(mc)(m2);
          [~, i3, i2] = intersect(r3, r2);
          x = v3(i3);  y = v2(i2);  hi = max([hi; x(:); y(:)]);
          if s == 1
            plot(ax, x, y, 'o', 'MarkerSize', 3.6, 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'LineWidth', 0.3);
            fr = mean(y < x);
          else
            plot(ax, x, y, 'o', 'MarkerSize', 3.6, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', col, 'LineWidth', 0.7);
          end
          for q = 1:numel(x), k = k + 1; log(k, :) = [a, idx(j), s, r3(i3(q)), x(q), y(q), numel(x), 0]; end
        end
        hi = hi * 1.05;
        plot(ax, [0 hi], [0 hi], '-', 'Color', cfg.grey, 'LineWidth', 0.8);
        set(ax, 'XLim', [0 hi], 'YLim', [0 hi]);  axis(ax, 'square');
        set(ax, 'XGrid', 'on', 'YGrid', 'on', 'GridColor', cfg.gridc, 'GridAlpha', 1);
        text(ax, 0.04*hi, 0.93*hi, sprintf('%.0f%% below', 100*fr), 'FontName', cfg.font, 'FontSize', cfg.fs-1, 'Color', cfg.ink);
        xlabel(ax, sprintf('S3 (%s)', unit{a}), 'FontName', cfg.font, 'FontSize', cfg.fs-1);
        if j == 1, ylabel(ax, sprintf('%s: C2 (%s)', assets{a}, unit{a}), 'FontName', cfg.font, 'FontSize', cfg.fs-1); end
        sub = strrep(c.label(numel(assets{a})+3:end), ', ', ', ');
        title(ax, sub, 'FontName', cfg.font, 'FontSize', cfg.fs-1, 'FontWeight', 'normal', 'Interpreter', 'none');
      end
    end
    figLog(cfg, 'Fig05_per_run_scatter', 'asset(1PV2Bat),cell,set(1F2F2),run,S3_MAE,C2_MAE,n_runs,unused', log);
    figSave(f, cfg, 'Fig05_per_run_scatter');
    end

    function Fig06_residual_vs_health(obj)
% Figure: Twin residual (measured minus Twin) against time for runs at increasing health index D, Dataset A, first operating
% profile of each asset, 1 s moving average. Shows the signal the C1/C2 features are built from.
% Source: Stage10_PV_Controlled.csv, Stage10_Battery_Controlled.csv. Output: Fig06_residual_vs_health.
cfg = obj.cfg;
spec = {{cfg.files.pvA,  {'PV_Residual_Current'},      'PV residual current (A)',      '(a) PV'}, ...
        {cfg.files.batA, {'Battery_Residual_Voltage'}, 'Battery residual voltage (V)', '(b) Battery'}};
want = [0 0.25 0.5 0.75 1];
cm = interp1([0 1], [cfg.blue; cfg.orange], linspace(0, 1, 5));
f = figNew(17.5, 6.8);  log = zeros(0, 4);  k = 0;
for p = 1:2
  S = spec{p};  T = figRead(cfg, S{1});
  yc = figCol(T, S{2}, S{1});  rc = figCol(T, {'Meta_Run_ID', 'run'}, S{1});  pc = figCol(T, {'Meta_Operating_Profile_ID', 'profile'}, S{1});
  H = figHealth(T, S{1});  t = figT(T);
  ax = figAxes(f, cfg, [0.08 + 0.50*(p-1), 0.17, 0.40, 0.70]);
  [up, ~, ip] = unique(string_(T.(pc)));  mp = ip == 1;
  lev = unique(H(mp));
  for q = 1:5
    [~, ii] = min(abs(lev - want(q)));  L = lev(ii);
    mm = mp & abs(H - L) < 1e-9;
    rs = string_(T.(rc));  rows = find(mm);  [~, ~, ir] = unique(rs(mm));  m = false(size(mm));  m(rows(ir == 1)) = true;
    y = T.(yc)(m);  tt = t(m);  tt = tt - tt(1);  ys = movmean(y, 10);
    plot(ax, tt, ys, '-', 'Color', cm(q, :), 'LineWidth', 1.1, 'DisplayName', sprintf('D = %.2f', L));
    k = k + 1;  log(k, :) = [p, L, mean(ys(tt >= 60)), numel(y)];
  end
  xlabel(ax, 'Time (s)', 'FontName', cfg.font, 'FontSize', cfg.fs);
  ylabel(ax, S{3}, 'FontName', cfg.font, 'FontSize', cfg.fs);
  title(ax, sprintf('%s, profile %s', S{4}, up{1}), 'FontName', cfg.font, 'FontSize', cfg.fs+1, 'FontWeight', 'bold', 'Interpreter', 'none');
  set(ax, 'XLim', [0 150], 'YGrid', 'on', 'GridColor', cfg.gridc, 'GridAlpha', 1);
  plot(ax, [60 60], get(ax, 'YLim'), ':', 'Color', cfg.grey, 'LineWidth', 0.8, 'HandleVisibility', 'off');
  legend(ax, 'Location', 'best', 'Box', 'off', 'FontName', cfg.font, 'FontSize', cfg.fs-1);
end
figLog(cfg, 'Fig06_residual_vs_health', 'panel,health_D,mean_residual_t_ge_60s,rows', log);
figSave(f, cfg, 'Fig06_residual_vs_health');
    end

    function Fig07_operating_profiles(obj)
% Figure: the operating profiles of Dataset A: PV irradiance and cell temperature (four profiles) and battery current (four
% profiles). One run per profile at the lowest health level. Uses the noise-free True_* columns when the file has them,
% otherwise the measured *_Final columns.  Source: Stage10_PV_Controlled.csv, Stage10_Battery_Controlled.csv.
cfg = obj.cfg;
cl = {cfg.blue, cfg.orange, cfg.purple, cfg.grey};
panels = {{cfg.files.pvA,  {'True_PV_Irradiance', 'PV_Irradiance_Final'},     'Irradiance (W/m^2)',       '(a) PV irradiance'}, ...
          {cfg.files.pvA,  {'True_PV_Temperature', 'PV_Temperature_Final'},   'Cell temperature (\circC)', '(b) PV temperature'}, ...
          {cfg.files.batA, {'True_Battery_Current', 'Battery_Current_Final'}, 'Battery current (A)',       '(c) Battery current'}};
f = figNew(17.5, 5.8);  log = zeros(0, 5);  k = 0;  cache = struct();
for p = 1:3
  S = panels{p};  T = figRead(cfg, S{1});
  yc = figCol(T, S{2}, S{1});  rc = figCol(T, {'Meta_Run_ID', 'run'}, S{1});  pc = figCol(T, {'Meta_Operating_Profile_ID', 'profile'}, S{1});
  H = figHealth(T, S{1});  t = figT(T);
  ax = figAxes(f, cfg, [0.075 + 0.325*(p-1), 0.20, 0.25, 0.68]);
  [up, ~, ip] = unique(string_(T.(pc)));
  for q = 1:min(4, numel(up))
    m = ip == q;  m = m & abs(H - min(H(m))) < 1e-9;
    rs = string_(T.(rc));  rows = find(m);  [~, ~, ir] = unique(rs(m));  m = false(size(m));  m(rows(ir == 1)) = true;
    y = T.(yc)(m);  tm = t(m);  tm = tm - tm(1);
    plot(ax, tm, y, '-', 'Color', cl{q}, 'LineWidth', 1.2, 'DisplayName', up{q});
    k = k + 1;  log(k, :) = [p, q, min(y), max(y), numel(y)];
  end
  xlabel(ax, 'Time (s)', 'FontName', cfg.font, 'FontSize', cfg.fs);
  ylabel(ax, S{3}, 'FontName', cfg.font, 'FontSize', cfg.fs);
  title(ax, S{4}, 'FontName', cfg.font, 'FontSize', cfg.fs+1, 'FontWeight', 'bold');
  set(ax, 'XLim', [0 150], 'YGrid', 'on', 'GridColor', cfg.gridc, 'GridAlpha', 1);
  legend(ax, 'Location', 'best', 'Box', 'off', 'FontName', cfg.font, 'FontSize', cfg.fs-1, 'Interpreter', 'none');
end
figLog(cfg, 'Fig07_operating_profiles', 'panel,profile,min,max,rows', log);
figSave(f, cfg, 'Fig07_operating_profiles');
    end

    function Fig08_model_curves(obj)
    % Figure: what the health index D does inside the plant models (no simulation data needed; equations and parameter files only).
    % (a,b) PV I-V and P-V at G = 1000 W/m^2, Tc = 25 C for D = 0, 0.5, 1 with Rs*(1+k_Rs*D), Rsh*(1-k_Rsh*D), Iph_ref*(1-k_Iph*D).
    % (c) Battery terminal voltage for a 2 A discharge step with R0*(1+k_R0*D), R1*(1+k_R1*D), V = OCV(SOC)+0.05*D - I*R0 - Vp.
    %     C1 is not aged. Capacity Q*(1-k_Q*D) changes only how fast SOC falls. Illustrative: SOC starts at 90 %.
    % Needs PV_Params_Stage1.mat, PV_Degradation_Params.mat, Battery_Params_Stage3.mat, Battery_Degradation_Params.mat in cfg.dataDir.
    cfg = obj.cfg;
    ld = @(n) load(fullfile(cfg.dataDir, n));
    P = ld('PV_Params_Stage1.mat');  K = ld('PV_Degradation_Params.mat');
    B = ld('Battery_Params_Stage3.mat');  KB = ld('Battery_Degradation_Params.mat');
    Ds = [0 0.5 1];  cm = interp1([0 1], [cfg.blue; cfg.orange], Ds);
    f = figNew(17.5, 6.0);  log = zeros(0, 4);  k = 0;
    axI = figAxes(f, cfg, [0.075 0.19 0.25 0.70]);
    axP = figAxes(f, cfg, [0.405 0.19 0.25 0.70]);
    axB = figAxes(f, cfg, [0.735 0.19 0.25 0.70]);
    for q = 1:3
      D = Ds(q);
      Rs = P.Rs*(1 + K.k_Rs*D);  Rsh = P.Rsh*(1 - K.k_Rsh*D);  Iph_ref = P.Iph_ref*(1 - K.k_Iph*D);
      V = linspace(0, 1.08*P.Voc_ref, 300)';  I = zeros(size(V));
      for i = 1:numel(V)
        I(i) = pvPlant(1000, 25, V(i), Rs, Rsh, Iph_ref, P.I0_ref, P.n, P.Ns, P.Ki, P.Eg, P.Gref, P.Tref);
      end
      keep = I > 0;  V = V(keep);  I = I(keep);
      plot(axI, V, I, '-', 'Color', cm(q, :), 'LineWidth', 1.3, 'DisplayName', sprintf('D = %.1f', D));
      plot(axP, V, V.*I, '-', 'Color', cm(q, :), 'LineWidth', 1.3, 'DisplayName', sprintf('D = %.1f', D));
      [pm, im] = max(V.*I);  plot(axP, V(im), pm, 'o', 'MarkerSize', 4, 'MarkerFaceColor', cm(q, :), 'MarkerEdgeColor', cm(q, :), 'HandleVisibility', 'off');
      k = k + 1;  log(k, :) = [1, D, pm, V(im)];
      % battery
      R0 = B.R0*(1 + KB.k_R0*D);  R1 = B.R1*(1 + KB.k_R1*D);  Qa = B.Q*(1 - KB.k_Q*D);  C1 = B.C1;
      dt = 0.1;  t = (0:dt:300)';  Iload = 2*(t >= 20);  soc = 90;  Vp = 0;  vb = zeros(size(t));
      for i = 1:numel(t)
        ocv = interp1(B.SOC_bp, B.OCV_tbl, min(max(soc, 0), 100)) + 0.05*D;
        vb(i) = ocv - Iload(i)*R0 - Vp;
        Vp = Vp + dt*(Iload(i)/C1 - Vp/(R1*C1));
        soc = soc - 100*Iload(i)*dt/(3600*Qa);
      end
      plot(axB, t, vb, '-', 'Color', cm(q, :), 'LineWidth', 1.3, 'DisplayName', sprintf('D = %.1f', D));
      k = k + 1;  log(k, :) = [2, D, vb(end), min(vb)];
    end
    labs = {axI, 'Voltage (V)', 'Current (A)', '(a) PV I-V';  axP, 'Voltage (V)', 'Power (W)', '(b) PV P-V';  axB, 'Time (s)', 'Terminal voltage (V)', '(c) Battery, 2 A step'};
    for p = 1:3
      a = labs{p, 1};
      xlabel(a, labs{p, 2}, 'FontName', cfg.font, 'FontSize', cfg.fs);  ylabel(a, labs{p, 3}, 'FontName', cfg.font, 'FontSize', cfg.fs);
      title(a, labs{p, 4}, 'FontName', cfg.font, 'FontSize', cfg.fs+1, 'FontWeight', 'bold');
      set(a, 'YGrid', 'on', 'GridColor', cfg.gridc, 'GridAlpha', 1);
      legend(a, 'Location', 'best', 'Box', 'off', 'FontName', cfg.font, 'FontSize', cfg.fs-1);
    end
    figLog(cfg, 'Fig08_model_curves', 'panel(1PV2Bat),health_D,max_power_W_or_final_V,Vmpp_or_min_V', log);
    figSave(f, cfg, 'Fig08_model_curves');
    end
  end
end

%% ---- local helper functions (used only inside this file) ----
function T = figRead(cfg, name)
% Read one CSV from cfg.dataDir with a clear error if it is missing.
p = fullfile(cfg.dataDir, name);
if ~isfile(p)
  error('figRead:missing', 'Cannot find %s. Keep PaperFigures.m in the Reformable_AI folder or pass the data folder: PaperFigures(''path'').', p);
end
T = readtable(p, 'TextType', 'string');
end

function c = figCol(T, cands, file)
% Name of the first candidate column that exists in T; error listing the real columns otherwise.
v = T.Properties.VariableNames;
for i = 1:numel(cands)
  if ismember(cands{i}, v), c = cands{i}; return; end
end
error('figCol:cols', '%s has none of the columns {%s}. Columns present: %s', file, strjoin(cands, ', '), strjoin(v, ', '));
end

function H = figHealth(T, file)
% Health index per row: Label_Health_Value, else 'level' if it lies in [0,1], else D_index (PV) or D_batt (battery).
v = T.Properties.VariableNames;
if ismember('Label_Health_Value', v)
  H = T.Label_Health_Value;
elseif ismember('level', v) && isnumeric(T.level) && all(T.level >= 0 & T.level <= 1)
  H = T.level;
elseif ismember('D_index', v)
  H = T.D_index;
elseif ismember('D_batt', v)
  H = T.D_batt;
else
  error('figHealth:cols', '%s: no health column (Label_Health_Value, level in [0,1], D_index or D_batt). Columns present: %s', file, strjoin(v, ', '));
end
H = double(H(:));
end

function t = figT(T)
% Time in seconds: t_grid or t when present, otherwise 0.1 s steps within each run (rows are in run order).
v = T.Properties.VariableNames;
if ismember('t_grid', v), t = T.t_grid; elseif ismember('t', v), t = T.t; else, t = mod((0:height(T)-1)', 1501) * 0.1; end
t = double(t(:));
end

function s = string_(x)
% Text version of an id column (numeric ids become text) without using the string class.
if isnumeric(x), s = cellstr(num2str(x(:))); else, s = cellstr(x); end
end

function m = figEq(col, val)
% Logical column vector: the text column equals val (works for string, char or cellstr columns).
m = strcmp(cellstr(col), val);
m = m(:);
end

function m = figStarts(col, pre)
% Logical column vector: the text column starts with pre.
m = strncmp(cellstr(col), pre, numel(pre));
m = m(:);
end

function m = figAsset(col, name)
% Logical column vector: rows belonging to the asset 'PV' or 'Battery' (case-insensitive, tolerant of wording).
s = lower(cellstr(col));
if strcmp(name, 'PV')
  m = ~cellfun('isempty', strfind(s, 'pv'));
else
  m = ~cellfun('isempty', strfind(s, 'batt'));
end
m = m(:);
end

function i = figPick(T, c, fs, strict)
% Row index of the differences table T for comparison cell c and feature set fs (exact name).
% c has fields asset ('PV'/'Battery'), reg ('A-'/'B-'), model ('ridge'/'nn').
m = figAsset(T.Asset, c.asset) & figStarts(T.TestRegime, c.reg) & figEq(T.Model, c.model) & figEq(T.FeatureSet, fs);
i = find(m);
if numel(i) ~= 1
  error('figPick:rows', 'Expected exactly one row for %s / %s / %s / "%s", found %d.', c.asset, c.reg, c.model, fs, numel(i));
end
end

function i = figPickStress(T, c, cond, contrast)
% Row index in Stage14_Stress_Differences.csv for cell c, condition and contrast text (exact). Returns [] if absent.
m = figAsset(T.Asset, c.asset) & figStarts(T.TestRegime, c.reg) & figEq(T.Model, c.model) & ...
    figEq(T.Condition, cond) & figEq(T.Contrast, contrast);
i = find(m);
if numel(i) > 1, error('figPickStress:rows', 'More than one row for %s / %s / %s / %s / %s.', c.asset, c.reg, c.model, cond, contrast); end
end

function ax = figAxes(f, cfg, pos)
% Create a clean axes at normalized position pos = [left bottom width height].
ax = axes('Parent', f, 'Units', 'normalized', 'Position', pos, 'Box', 'off', ...
          'FontName', cfg.font, 'FontSize', cfg.fs, 'LineWidth', 0.75, 'TickDir', 'out', ...
          'XColor', cfg.ink, 'YColor', cfg.ink, 'Color', 'w');
hold(ax, 'on');
end

function f = figNew(wcm, hcm)
% New white figure of the given size in centimetres (hidden while drawing).
f = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 wcm hcm], 'Visible', 'off', ...
           'PaperUnits', 'centimeters', 'PaperSize', [wcm hcm], 'PaperPosition', [0 0 wcm hcm]);
end

function figSave(f, cfg, name)
% Save a figure as vector PDF and 600 dpi PNG in cfg.outDir, then close it.
exportgraphics(f, fullfile(cfg.outDir, [name '.pdf']), 'ContentType', 'vector');
exportgraphics(f, fullfile(cfg.outDir, [name '.png']), 'Resolution', 600);
close(f);
fprintf('  saved %s (.pdf and .png)\n', name);
end

function figLog(cfg, name, header, M)
% Write the numbers behind a figure to Paper_Figures/<name>_data.csv so every plotted value can be traced.
fid = fopen(fullfile(cfg.outDir, [name '_data.csv']), 'w');
fprintf(fid, '%s\n', header);
for i = 1:size(M, 1)
  fprintf(fid, '%.6g', M(i, 1));
  for j = 2:size(M, 2), fprintf(fid, ',%.6g', M(i, j)); end
  fprintf(fid, '\n');
end
fclose(fid);
end

function cm = figDiverging(n)
% Blue (negative = Twin features better) - light grey (zero) - orange (positive = worse) colormap.
c = [0.122 0.373 0.659; 0.62 0.76 0.90; 0.95 0.95 0.95; 0.94 0.70 0.48; 0.788 0.337 0.047];
cm = interp1([0 0.25 0.5 0.75 1], c, linspace(0, 1, n)');
end

function I = pvPlant(G, Tc_C, V, Rs, Rsh, Iph_ref, I0_ref, n, Ns, Ki, Eg, Gref, Tref)
% Single-diode plant, same Newton solver and additive-Ki photocurrent as the PV_model block (see Stage15 script).
k = 1.380649e-23;  q = 1.602176634e-19;  Tc = Tc_C + 273.15;  Vt = Ns*k*Tc/q;
Iph = (Iph_ref + Ki*(Tc - Tref)) * (G/Gref);
I0  = I0_ref * (Tc/Tref)^3 * exp((q*Eg/(n*k)) * (1/Tref - 1/Tc));
I = Iph;
for iter = 1:50
  e = exp(min((V + I*Rs)/(n*Vt), 700));
  fv = Iph - I0*(e - 1) - (V + I*Rs)/Rsh - I;
  df = -I0*(Rs/(n*Vt))*e - Rs/Rsh - 1;
  dI = fv/df;  I = I - dI;
  if abs(dI) < 1e-8, break; end
end
I = max(I, 0);
end