function Stage10G_final_test()
% Corrected Stage 10 evaluation, step 2 of 2: the single evaluation on the untouched final test, Dataset F.
% Refuses to run unless the frozen configuration and every input file are byte-identical to what was recorded at the freeze,
% and refuses to run a second time (Stage10G_Final_Results.csv must not exist).
%   Training : all 100 Dataset A runs (Stage10_Features_*.csv), scaling statistics from the training rows only.
%   Test     : Dataset F, regime A-F (unseen health levels, profiles 1-4) and regime B-F (unseen profile family 5).
%   Models   : ridge with the frozen lambda per (asset, feature set); 8-unit ReLU network with 10 seeds (mean and SD reported);
%              constant baseline (training mean). Metrics: MAE and R^2 (R^2 = 1 - SSE/SST over the test rows).
%   Uncertainty: run-level bootstrap (resample whole test runs) of the difference in per-run MAE, set minus S3 baseline.
%                Negative difference = the set is better than the sensor-only baseline.
% Writes Stage10G_Final_Results.csv, Stage10G_Final_Differences.csv, Stage10G_Final_PerRun.csv.
here = fileparts(which('Stage10G_final_test'));
if isempty(here), error('Keep the Stage10G_* files in the Reformable_AI folder (on the MATLAB path).'); end
cd(here);
if isfile('Stage10G_Final_Results.csv'), error('Dataset F has already been evaluated (Stage10G_Final_Results.csv exists). It is a one-shot test.'); end
if ~isfile('Stage10G_Config.json') || ~isfile('Stage10G_Config.sha256'), error('No frozen configuration. Run Stage10G_freeze_config first.'); end

% ---- integrity checks: nothing may have changed since the freeze ----
hCfg = strtrim(fileread('Stage10G_Config.sha256'));
assert(strcmp(Stage10G_lib('sha256','Stage10G_Config.json'), hCfg), 'Stage10G_Config.json changed after it was frozen.');
cfg = jsondecode(fileread('Stage10G_Config.json'));
chk = {'libSha256','Stage10G_lib.m'; 'featuresA_PV','Stage10_Features_PV.csv'; 'featuresA_Battery','Stage10_Features_Battery.csv'; ...
       'manifestF','Stage10F_Manifest.csv'; 'featuresF_PV','Stage10F_Features_PV.csv'; 'featuresF_Battery','Stage10F_Features_Battery.csv'};
for k = 1:size(chk,1)
    assert(strcmp(Stage10G_lib('sha256', chk{k,2}), cfg.hashes.(chk{k,1})), '%s changed after the freeze.', chk{k,2});
end
fprintf('Integrity checks passed: config, library, Dataset A features, Dataset F manifest and features are unchanged since the freeze.\n');

assets = {'PV','Battery'};
fA = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
fF = {'Stage10F_Features_PV.csv','Stage10F_Features_Battery.csv'};
regimes = {'A','B'};  regName = {'A-F unseen health levels','B-F unseen profile family'};
seeds = cfg.nn.seedsFinal(:)';
res = {};  per = {};  dif = {};
rng(cfg.bootstrap.seed);

for a = 1:2
    TA = readtable(fA{a});  TF = readtable(fF{a});
    [TA, S] = Stage10G_lib('sets', TA, assets{a});
    [TF, ~] = Stage10G_lib('sets', TF, assets{a});
    for r = 1:2
        te = string(TF.regime) == regimes{r};
        runs = TF.run(te);  [uRuns, ~, g] = unique(runs);  nR = numel(uRuns);
        y = TF.D(te);
        perMAE = struct();                                   % per-run MAE, one column per (set, model)
        base = mean(TA.D);
        res(end+1,:) = {assets{a}, regName{r}, 'constant (training mean)', 'constant', 0, round(mean(abs(base - y)),4), ...
                        round(1 - sum((y-base).^2)/sum((y-mean(y)).^2),3), NaN, nR, nnz(te)}; %#ok<AGROW>
        for s = 1:numel(S)
            Xtr = TA{:, S(s).cols};  Xte = TF{te, S(s).cols};
            li = find(strcmp({cfg.lambda.set}, S(s).name) & strcmp({cfg.lambda.asset}, assets{a}));
            lam = cfg.lambda(li).lambda;
            % ridge
            p = Stage10G_lib('ridge', Xtr, TA.D, Xte, lam);
            [mae, r2] = Stage10G_lib('metrics', y, p);
            res(end+1,:) = {assets{a}, regName{r}, S(s).name, 'ridge', numel(S(s).cols), round(mae,4), round(r2,3), NaN, nR, nnz(te)}; %#ok<AGROW>
            runMAE_ridge = accumarray(g, abs(p - y), [], @mean);
            % network, 10 seeds
            m = zeros(1, numel(seeds));  q = zeros(1, numel(seeds));  runMAE_nn = zeros(nR, numel(seeds));
            for k = 1:numel(seeds)
                pn = Stage10G_lib('nn', Xtr, TA.D, Xte, seeds(k), cfg.nn.hidden, cfg.nn.iterations);
                [m(k), q(k)] = Stage10G_lib('metrics', y, pn);
                runMAE_nn(:,k) = accumarray(g, abs(pn - y), [], @mean);
            end
            res(end+1,:) = {assets{a}, regName{r}, S(s).name, 'network (10-seed mean)', numel(S(s).cols), round(mean(m),4), round(mean(q),3), round(std(m),4), nR, nnz(te)}; %#ok<AGROW>
            fprintf('%-8s %-26s %-34s ridge %.4f | network %.4f (SD %.4f)\n', assets{a}, regName{r}, S(s).name, mae, mean(m), std(m));
            perMAE.(sprintf('s%d_ridge', s)) = runMAE_ridge;
            perMAE.(sprintf('s%d_nn', s))    = mean(runMAE_nn, 2);
            for j = 1:nR
                per(end+1,:) = {assets{a}, regName{r}, S(s).name, uRuns(j), runMAE_ridge(j), mean(runMAE_nn(j,:))}; %#ok<AGROW>
            end
        end
        % ---- run-level bootstrap of (set - S3 baseline) ----
        B = cfg.bootstrap.resamples;  idx = randi(nR, nR, B);
        for s = 2:numel(S)
            for mdl = {'ridge','nn'}
                d  = perMAE.(sprintf('s%d_%s', s, mdl{1})) - perMAE.(sprintf('s1_%s', mdl{1}));
                bm = mean(d(idx), 1);
                ci = prctile(bm, [2.5 97.5]);
                dif(end+1,:) = {assets{a}, regName{r}, S(s).name, mdl{1}, round(mean(d),4), round(ci(1),4), round(ci(2),4), round(mean(d < 0),3), nR}; %#ok<AGROW>
            end
        end
    end
end

R = cell2table(res, 'VariableNames', {'Asset','TestRegime','FeatureSet','Model','nFeatures','MAE','R2','SD_over_seeds','nTestRuns','nTestRows'});
D = cell2table(dif, 'VariableNames', {'Asset','TestRegime','FeatureSet','Model','MeanDiffMAE_vs_S3','CI95_low','CI95_high','FractionRunsBetter','nTestRuns'});
P = cell2table(per, 'VariableNames', {'Asset','TestRegime','FeatureSet','Run','RunMAE_ridge','RunMAE_network_seedmean'});
writetable(R, 'Stage10G_Final_Results.csv');
writetable(D, 'Stage10G_Final_Differences.csv');
writetable(P, 'Stage10G_Final_PerRun.csv');
fprintf('\n=== PRIMARY CONTRAST: C2 strong + residual windows minus S3 sensor strong (negative = Twin better) ===\n');
disp(D(startsWith(D.FeatureSet, 'C2 strong'), :));
fprintf('Saved Stage10G_Final_Results.csv, Stage10G_Final_Differences.csv, Stage10G_Final_PerRun.csv\n');
end