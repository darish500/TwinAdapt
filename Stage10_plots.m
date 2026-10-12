function Stage10_plots()
% The ten required Stage 10 figures. Needs Stage10_final_table first, plus the Stage 10-13 result CSV files.
load('Stage10_Predictions.mat', 'Pred');
Lt  = readtable('Stage10_Final_Metrics.csv');
out = 'Stage10_figures';
if ~exist(out,'dir'), mkdir(out); end
cS = [0.80 0.40 0.10];   cT = [0.00 0.45 0.70];   cB = [0.60 0.60 0.60];   % sensor-only, Twin-augmented, baseline
rng(1);
assets = {'PV','Battery'};
regT = struct('A','A: unseen levels','B','B: unseen profile');

% ---- Figures 1 and 2: predicted vs true ----
for a = 1:2
    f = figure('Visible','off','Position',[100 100 900 760]);
    tl = tiledlayout(2,2,'TileSpacing','compact');
    for rk = {'A','B'}
        for key = {'sensSel','full'}
            P = Pred.(assets{a}).(rk{1}).(key{1});
            nexttile;  hold on
            col = cS;  if strcmp(key{1},'full'), col = cT; end
            plot(P.y + 0.012*randn(size(P.y)), P.p, '.', 'Color', col, 'MarkerSize', 4);
            plot([0 1],[0 1],'k--');  xlim([-0.05 1.05]);  ylim([-0.05 1.05]);  grid on
            title(sprintf('%s, %s, MAE %.3f', regT.(rk{1}), ternary(strcmp(key{1},'full'),'Sensor + Twin','Sensor-only'), mean(abs(P.p-P.y))), 'FontSize', 9);
        end
    end
    xlabel(tl,'True health index D (small horizontal jitter added)');  ylabel(tl,'Predicted D');
    title(tl, sprintf('%s: predicted vs true health (test runs)', assets{a}));
    exportgraphics(f, fullfile(out, sprintf('Fig%02d_%s_pred_vs_true.png', a, assets{a})), 'Resolution', 200);  close(f);
end

% ---- Figures 3 and 4: error over time ----
for a = 1:2
    f = figure('Visible','off','Position',[100 100 900 380]);
    tl = tiledlayout(1,2,'TileSpacing','compact');
    for rk = {'A','B'}
        nexttile;  hold on
        for key = {'sensSel','full'}
            P = Pred.(assets{a}).(rk{1}).(key{1});
            [ut,~,ix] = unique(P.t);
            m = accumarray(ix, abs(P.p - P.y), [], @mean);
            col = cS;  if strcmp(key{1},'full'), col = cT; end
            plot(ut, m, 'Color', col, 'LineWidth', 1.6);
        end
        grid on;  title(regT.(rk{1}), 'FontSize', 9);  ylim([0 inf])
        if strcmp(rk{1},'A'), legend({'Sensor-only','Sensor + Twin'}, 'Location','best'); end
    end
    xlabel(tl,'Time within the run (s)');  ylabel(tl,'Mean absolute error of D');
    title(tl, sprintf('%s: prediction error over time (mean over test runs)', assets{a}));
    exportgraphics(f, fullfile(out, sprintf('Fig%02d_%s_error_over_time.png', a+2, assets{a})), 'Resolution', 200);  close(f);
end

% ---- Figure 5: sensor-only vs Twin-augmented, every ablation row ----
keys   = {'base','sensR','sensSel','twin','c1','c2','full'};
labels = {'Baseline','Sensor ridge','Sensor sel.','Twin only','S+raw res.','S+temporal','Full sel.'};
f = figure('Visible','off','Position',[100 100 1000 700]);
tl = tiledlayout(2,2,'TileSpacing','compact');
for a = 1:2
    for rk = {'A','B'}
        nexttile;
        v = zeros(1,numel(keys));
        for k = 1:numel(keys)
            v(k) = Lt.MAE(strcmp(Lt.Asset,assets{a}) & strcmp(Lt.Regime,rk{1}) & strcmp(Lt.RowKey,keys{k}));
        end
        b = bar(1:numel(keys), v, 'FaceColor','flat');
        for k = 1:numel(keys)
            if k == 1, b.CData(k,:) = cB; elseif ismember(k,[2 3]), b.CData(k,:) = cS; else, b.CData(k,:) = cT; end
        end
        xticks(1:numel(keys));  xticklabels(labels);  xtickangle(35);  grid on
        title(sprintf('%s, %s', assets{a}, regT.(rk{1})), 'FontSize', 9);
    end
end
ylabel(tl,'Test MAE (lower is better)');  title(tl,'Sensor-only vs Twin-augmented models');
exportgraphics(f, fullfile(out,'Fig05_sensor_vs_twin.png'), 'Resolution', 200);  close(f);

% ---- Figure 6: performance vs degradation level ----
f = figure('Visible','off','Position',[100 100 900 380]);
tl = tiledlayout(1,2,'TileSpacing','compact');
for a = 1:2
    nexttile;  hold on
    for rk = {'B','A'}
        for key = {'sensSel','full'}
            P = Pred.(assets{a}).(rk{1}).(key{1});
            lv = unique(round(P.y,2));
            m = arrayfun(@(l) mean(abs(P.p(round(P.y,2)==l) - P.y(round(P.y,2)==l))), lv);
            col = cS;  if strcmp(key{1},'full'), col = cT; end
            ls = '-o';  if strcmp(rk{1},'A'), ls = '--s'; end
            plot(lv, m, ls, 'Color', col, 'LineWidth', 1.4);
        end
    end
    grid on;  xlabel('True health level D');  title(assets{a});  ylim([0 inf])
    if a == 1, legend({'Sensor B','Sensor+Twin B','Sensor A','Sensor+Twin A'}, 'Location','best'); end
end
ylabel(tl,'MAE');  title(tl,'Performance vs degradation level (B: all levels, A: levels 0.25 and 0.75)');
exportgraphics(f, fullfile(out,'Fig06_performance_vs_degradation.png'), 'Resolution', 200);  close(f);

% ---- Figure 7: environmental variation (per held-out profile) ----
Pp = readtable('Stage12_PerProfile.csv');
Pp = Pp(strcmp(Pp.Model,'ridge'), :);
f = figure('Visible','off','Position',[100 100 900 380]);
tl = tiledlayout(1,2,'TileSpacing','compact');
for a = 1:2
    nexttile;
    q = Pp(strcmp(Pp.Asset,assets{a}), :);  q = sortrows(q,'HeldOutProfile');
    bb = bar(q.HeldOutProfile, [q.MAE_sensor q.MAE_twin]);
    bb(1).FaceColor = cS;  bb(2).FaceColor = cT;  grid on;  title(assets{a});  xlabel('Held-out profile');
    for k = 1:height(q)
        text(q.HeldOutProfile(k), max(q.MAE_sensor(k), q.MAE_twin(k)) + 0.01, sprintf('-%d%%', round(q.Pct_error_reduction(k))), 'HorizontalAlignment','center', 'FontSize', 8);
    end
    if a == 1, legend({'Sensor-only','Sensor + Twin'}, 'Location','best'); end
end
ylabel(tl,'Ridge MAE');  title(tl,'Environment and load variation (train on 3 profiles, test on the 4th)');
exportgraphics(f, fullfile(out,'Fig07_environment_variation.png'), 'Resolution', 200);  close(f);

% ---- Figure 8: sensor faults ----
D1 = readtable('Stage13_Eval_D1.csv');  D1 = D1(strcmp(D1.Model,'ridge'), :);
cats = cell(height(D1),1);
for k = 1:height(D1), cats{k} = sprintf('%s %s', D1.Asset{k}, D1.Regime{k}(1)); end
f = figure('Visible','off','Position',[100 100 800 420]);
bb = bar(1:height(D1), [D1.MAE_sensor_clean D1.MAE_sensor_fault D1.MAE_twin_clean D1.MAE_twin_fault]);
bb(1).FaceColor = cS;  bb(2).FaceColor = cS*0.55;  bb(3).FaceColor = cT;  bb(4).FaceColor = cT*0.55;
xticks(1:height(D1));  xticklabels(cats);  grid on;  ylabel('Ridge MAE')
legend({'Sensor clean','Sensor faulty','Twin clean','Twin faulty'}, 'Location','northwest');
title('Silent sensor faults: models trained on clean data, scored on faulty data');
exportgraphics(f, fullfile(out,'Fig08_sensor_faults.png'), 'Resolution', 200);  close(f);

% ---- Figure 9: Twin mismatch ----
tags = {'E1b','E1','E3'};  tagLab = {'params +/-2%','params +/-5%','start SOC +/-3'};
M = nan(4, 5);  cats = cell(4,1);  row = 0;
for a = 1:2
    for rk = {'A','B'}
        row = row + 1;  cats{row} = sprintf('%s %s', assets{a}, rk{1});
        for t = 1:3
            fn = sprintf('Stage11_Eval_%s.csv', tags{t});
            if ~isfile(fn), continue; end
            Ev = readtable(fn);
            q = Ev(strcmp(Ev.Asset,assets{a}) & strcmp(Ev.Model,'ridge') & startsWith(Ev.Regime, [rk{1} ':']), :);
            M(row,1) = q.MAE_sensor;  M(row,2) = q.MAE_twin_exact;  M(row,2+t) = q.MAE_twin_mismatch;
        end
    end
end
f = figure('Visible','off','Position',[100 100 900 430]);
bb = bar(1:4, M);
bb(1).FaceColor = cS;  bb(2).FaceColor = cT;
for t = 1:3, bb(2+t).FaceColor = cT*(0.75 - 0.2*(t-1)) + [0.25 0.25 0.25]*(0.2*(t-1)); end
xticks(1:4);  xticklabels(cats);  grid on;  ylabel('Ridge MAE')
legend([{'Sensor-only','Twin exact'} tagLab], 'Location','northwest');
title('Twin mismatch: model trained on an exact Twin, scored on a mismatched Twin');
exportgraphics(f, fullfile(out,'Fig09_twin_mismatch.png'), 'Resolution', 200);  close(f);

% ---- Figure 10: model complexity vs performance ----
Tm = readtable('Stage10_TinyML_Estimates.csv');
f = figure('Visible','off','Position',[100 100 1000 430]);
tl = tiledlayout(1,2,'TileSpacing','compact');
mk = struct('ridge','o', 'nn','s', 'trees','^');
for a = 1:2
    nexttile;  hold on
    q = Tm(strcmp(Tm.Asset,assets{a}), :);
    for k = 1:height(q)
        col = cS;  if strcmp(q.Group{k},'Twin-using'), col = cT; end
        lw = 0.8;  if strcmp(q.Selected{k},'SELECTED'), lw = 2.5; end
        scatter(q.Flash_B(k), q.MeanMAE(k), 60, col, mk.(q.Model{k}), 'LineWidth', lw);
        tok = strsplit(q.Candidate{k}, ' ');
        text(q.Flash_B(k)*1.1, q.MeanMAE(k), tok{1}, 'FontSize', 7);
    end
    set(gca,'XScale','log');  grid on;  title(assets{a});  xlabel('Model size (bytes, float32)')
end
ylabel(tl,'Mean test MAE (regimes A and B)');
title(tl,'Complexity vs performance (orange: sensor-only, blue: Twin-using; o ridge, square network, triangle trees; bold edge: selected)');
exportgraphics(f, fullfile(out,'Fig10_complexity_vs_performance.png'), 'Resolution', 200);  close(f);

fprintf('Ten figures saved in %s\n', out);
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end