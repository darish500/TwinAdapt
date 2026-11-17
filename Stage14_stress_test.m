function Stage14_stress_test()
% Stress tests on fresh data (Dataset F), robustness step: the FROZEN models are trained once on Dataset A and scored on
%   clean   Dataset F as it was evaluated in Stage10G_final_test (consistency check against Stage10G_Final_Results.csv)
%   E1a,E1b,E1,E2 : the Twin's parameters off by up to 1, 2, 5, 10 % (sensor data identical to clean F)
%   E3            : the Twin starts 3 SOC points away from the true battery SOC (sensor data identical to clean F)
%   D             : one silent sensor fault per sensor group (the Twin takes the faulted sensor values as its inputs)
% Only conditions whose Stage14_Features_<tag>_*.csv exist are evaluated; the list is printed and stored.
% Nothing is retuned: lambda, network size, iterations, seeds, bootstrap settings and feature sets come from Stage10G_Config.json, whose
% hash is checked together with the hashes of the library and of the Dataset A and clean Dataset F files.
% Question: does the Twin-residual advantage (C2 vs the strong sensor baseline S3) survive a wrong Twin, and a faulted sensor?
% Pre-specified outputs (all per run, run-level bootstrap, 2000 resamples, seed from the config):
%   (1) C1, C2, C2-mean minus S3 under the same condition (negative = Twin features better)
%   (2) damage = set under the condition minus the same set on clean F (positive = the condition hurts that set)
%   (3) advantage kept = (S3 - C2 under the condition) / (S3 - C2 on clean F), in percent, from the mean per-run MAE
% Writes once (stops if Stage14_Stress_Results.csv exists): Stage14_Stress_Results.csv, _Differences.csv, _Retention.csv, _PerRun.csv,
% _FaultBreakdown.csv (only if D was evaluated), _Inputs.csv.
here = fileparts(which('Stage14_stress_test'));
if isempty(here), error('Keep the Stage14_* files in the Reformable_AI folder (on the MATLAB path).'); end
cd(here);
if isfile('Stage14_Stress_Results.csv'), error('The stress test has already been evaluated (Stage14_Stress_Results.csv exists).'); end
if ~isfile('Stage10G_Config.json') || ~isfile('Stage10G_Config.sha256'), error('No frozen configuration.'); end
hCfg = strtrim(fileread('Stage10G_Config.sha256'));
assert(strcmp(Stage10G_lib('sha256','Stage10G_Config.json'), hCfg), 'Stage10G_Config.json changed after it was frozen.');
cfg = jsondecode(fileread('Stage10G_Config.json'));
chk = {'libSha256','Stage10G_lib.m'; 'featuresA_PV','Stage10_Features_PV.csv'; 'featuresA_Battery','Stage10_Features_Battery.csv'; ...
       'manifestF','Stage10F_Manifest.csv'; 'featuresF_PV','Stage10F_Features_PV.csv'; 'featuresF_Battery','Stage10F_Features_Battery.csv'};
for k = 1:size(chk,1)
    assert(strcmp(Stage10G_lib('sha256', chk{k,2}), cfg.hashes.(chk{k,1})), '%s changed after the freeze.', chk{k,2});
end
fprintf('Integrity checks passed: frozen config, library, Dataset A features, Dataset F manifest and clean features are unchanged.\n');

assets  = {'PV','Battery'};
fA = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
fF = {'Stage10F_Features_PV.csv','Stage10F_Features_Battery.csv'};
regimes = {'A','B'};  regName = {'A-F unseen health levels','B-F unseen profile family'};
want  = {'S3 sensor strong (baseline)','C1 strong + raw residuals','C2 strong + residual windows','C2-mean (window mean only)'};
short = {'S3','C1','C2','C2-mean'};
tagsAll = {'E1a','E1b','E1','E2','E3','D'};
tags = {'clean'};
for k = 1:numel(tagsAll)
    if isfile(['Stage14_Features_' tagsAll{k} '_PV.csv']) && isfile(['Stage14_Features_' tagsAll{k} '_Battery.csv']), tags{end+1} = tagsAll{k}; end %#ok<AGROW>
end
fprintf('Conditions evaluated: %s\n', strjoin(tags, ', '));
inp = {};
for c = 2:numel(tags)
    for a = 1:2
        f = ['Stage14_Features_' tags{c} '_' assets{a} '.csv'];
        inp(end+1,:) = {f, Stage10G_lib('sha256', f)}; %#ok<AGROW>
    end
end
if any(strcmp(tags,'D')), inp(end+1,:) = {'Stage14_Fault_Manifest.csv', Stage10G_lib('sha256','Stage14_Fault_Manifest.csv')}; end
seeds = cfg.nn.seedsFinal(:)';  K = numel(seeds);
rng(cfg.bootstrap.seed);
res = {};  per = {};  dif = {};  ret = {};

for a = 1:2
    TA = readtable(fA{a});
    [TA, S] = Stage10G_lib('sets', TA, assets{a});
    idx = zeros(1,4);
    for q = 1:4, idx(q) = find(strcmp({S.name}, want{q})); end
    TT = cell(1, numel(tags));
    for c = 1:numel(tags)
        if c == 1, f = fF{a}; else, f = ['Stage14_Features_' tags{c} '_' assets{a} '.csv']; end
        X = readtable(f);
        [X, ~] = Stage10G_lib('sets', X, assets{a});
        TT{c} = X;
        assert(isequal(X.run, TT{1}.run) && max(abs(X.t - TT{1}.t)) < 1e-9, 'rows of %s do not line up with clean F', f);
        assert(max(abs(X.D - TT{1}.D)) < 1e-9, 'health labels of %s differ from clean F', f);
    end
    for r = 1:2
        te   = string(TT{1}.regime) == regimes{r};
        runs = TT{1}.run(te);  [uRuns, ~, g] = unique(runs);  nR = numel(uRuns);
        y = TT{1}.D(te);  nrow = nnz(te);
        bidx = randi(nR, nR, cfg.bootstrap.resamples);
        rm = struct();
        for q = 1:4
            s = idx(q);  cols = S(s).cols;
            li  = find(strcmp({cfg.lambda.set}, S(s).name) & strcmp({cfg.lambda.asset}, assets{a}));
            lam = cfg.lambda(li).lambda;
            Xtr = TA{:, cols};
            Xte = zeros(nrow*numel(tags), numel(cols));
            for c = 1:numel(tags), Xte((c-1)*nrow + (1:nrow), :) = TT{c}{te, cols}; end
            pr = Stage10G_lib('ridge', Xtr, TA.D, Xte, lam);
            pn = zeros(size(Xte,1), K);
            for k = 1:K, pn(:,k) = Stage10G_lib('nn', Xtr, TA.D, Xte, seeds(k), cfg.nn.hidden, cfg.nn.iterations); end
            for c = 1:numel(tags)
                rows = (c-1)*nrow + (1:nrow);
                [mae, r2] = Stage10G_lib('metrics', y, pr(rows));
                res(end+1,:) = {assets{a}, regName{r}, tags{c}, S(s).name, 'ridge', round(mae,4), round(r2,3), NaN}; %#ok<AGROW>
                rr = accumarray(g, abs(pr(rows) - y), [], @mean);
                m = zeros(1,K);  q2 = zeros(1,K);  rn = zeros(nR,K);
                for k = 1:K
                    [m(k), q2(k)] = Stage10G_lib('metrics', y, pn(rows,k));
                    rn(:,k) = accumarray(g, abs(pn(rows,k) - y), [], @mean);
                end
                res(end+1,:) = {assets{a}, regName{r}, tags{c}, S(s).name, 'network (10-seed mean)', round(mean(m),4), round(mean(q2),3), round(std(m),4)}; %#ok<AGROW>
                rm.(sprintf('q%d_ridge_c%d', q, c)) = rr;
                rm.(sprintf('q%d_nn_c%d', q, c))    = mean(rn, 2);
                for j = 1:nR
                    per(end+1,:) = {assets{a}, regName{r}, tags{c}, short{q}, uRuns(j), rr(j), mean(rn(j,:))}; %#ok<AGROW>
                end
            end
            fprintf('%-8s %-26s %-34s done\n', assets{a}, regName{r}, S(s).name);
        end
        % ---- differences, damage, retention ----
        for c = 1:numel(tags)
            for mdl = {'ridge','nn'}
                key = @(q, cc) sprintf('q%d_%s_c%d', q, mdl{1}, cc);
                s3 = rm.(key(1,c));
                for q = 2:4
                    d = rm.(key(q,c)) - s3;  ci = prctile(mean(d(bidx),1), [2.5 97.5]);
                    dif(end+1,:) = {assets{a}, regName{r}, tags{c}, [short{q} ' minus S3 (same condition)'], mdl{1}, round(mean(d),4), round(ci(1),4), round(ci(2),4), round(mean(d<0),3), nR}; %#ok<AGROW>
                end
                if c > 1
                    for q = [1 3]
                        d = rm.(key(q,c)) - rm.(key(q,1));  ci = prctile(mean(d(bidx),1), [2.5 97.5]);
                        dif(end+1,:) = {assets{a}, regName{r}, tags{c}, [short{q} ' damage (condition minus clean)'], mdl{1}, round(mean(d),4), round(ci(1),4), round(ci(2),4), round(mean(d<0),3), nR}; %#ok<AGROW>
                    end
                    advClean = mean(rm.(key(1,1))) - mean(rm.(key(3,1)));
                    advTag   = mean(rm.(key(1,c))) - mean(rm.(key(3,c)));
                    ret(end+1,:) = {assets{a}, regName{r}, tags{c}, mdl{1}, round(mean(rm.(key(1,c))),4), round(mean(rm.(key(3,c))),4), ...
                                    round(advClean,4), round(advTag,4), round(100*advTag/advClean,0)}; %#ok<AGROW>
                end
            end
        end
    end
end

Rt = cell2table(res, 'VariableNames', {'Asset','TestRegime','Condition','FeatureSet','Model','MAE','R2','SD_over_seeds'});
Dt = cell2table(dif, 'VariableNames', {'Asset','TestRegime','Condition','Contrast','Model','MeanDiffMAE','CI95_low','CI95_high','FractionRunsBetter','nTestRuns'});
Kt = cell2table(ret, 'VariableNames', {'Asset','TestRegime','Condition','Model','MAE_S3','MAE_C2','Advantage_clean','Advantage_condition','Pct_advantage_kept'});
Pt = cell2table(per, 'VariableNames', {'Asset','TestRegime','Condition','FeatureSet','Run','RunMAE_ridge','RunMAE_network_seedmean'});
Pt.Condition = string(Pt.Condition);  Pt.FeatureSet = string(Pt.FeatureSet);  Pt.Asset = string(Pt.Asset);

% ---- consistency check: the clean rows must reproduce Stage10G_Final_Results.csv ----
if isfile('Stage10G_Final_Results.csv')
    FR = readtable('Stage10G_Final_Results.csv');
    worst = 0;  nCmp = 0;
    for i = find(strcmp(Rt.Condition,'clean'))'
        j = find(strcmp(FR.Asset, Rt.Asset{i}) & strcmp(FR.TestRegime, Rt.TestRegime{i}) & strcmp(FR.FeatureSet, Rt.FeatureSet{i}) & strcmp(FR.Model, Rt.Model{i}));
        if numel(j) == 1, worst = max(worst, abs(FR.MAE(j) - Rt.MAE(i))); nCmp = nCmp + 1; end
    end
    fprintf('Consistency with Stage10G_Final_Results.csv: %d clean cells compared, largest MAE difference %.4g (%s)\n', nCmp, worst, ...
            ternary(worst < 2e-4 && nCmp == 4*2*2*2));
else
    warning('Stage10G_Final_Results.csv not found: consistency check skipped.');
end

writetable(Rt, 'Stage14_Stress_Results.csv');
writetable(Dt, 'Stage14_Stress_Differences.csv');
writetable(Kt, 'Stage14_Stress_Retention.csv');
writetable(Pt, 'Stage14_Stress_PerRun.csv');
writetable(cell2table(inp, 'VariableNames', {'File','SHA256'}), 'Stage14_Stress_Inputs.csv');

% ---- fault breakdown (pooled over A-F and B-F runs, exploratory) ----
if any(strcmp(tags,'D'))
    Pm = sortrows(readtable('Stage14_Fault_Manifest.csv'), 'run');
    fb = {};
    for a = 1:2
        if a == 1, typ = string(Pm.pvType); chn = string(Pm.pvChannel); else, typ = string(Pm.bType); chn = string(Pm.bChannel); end
        for by = {'fault type','channel'}
            if strcmp(by{1}, 'fault type'), lab = typ; else, lab = chn; end
            for v = unique(lab)'
                runsV = Pm.run(lab == v);
                for col = {'RunMAE_ridge','RunMAE_network_seedmean'}
                    m  = Pt.Asset == assets{a} & Pt.Condition == "D" & ismember(Pt.Run, runsV);
                    s3 = mean(Pt.(col{1})(m & Pt.FeatureSet == "S3"));
                    c2 = mean(Pt.(col{1})(m & Pt.FeatureSet == "C2"));
                    fb(end+1,:) = {assets{a}, by{1}, char(v), col{1}, numel(unique(Pt.Run(m))), round(s3,4), round(c2,4), round(c2 - s3,4)}; %#ok<AGROW>
                end
            end
        end
    end
    Ft = cell2table(fb, 'VariableNames', {'Asset','GroupBy','Group','Model','nRuns','MeanRunMAE_S3','MeanRunMAE_C2','C2_minus_S3'});
    writetable(Ft, 'Stage14_Stress_FaultBreakdown.csv');
end

fprintf('\n=== C2 minus S3 under each condition (negative = Twin features better; same condition for both) ===\n');
disp(Dt(startsWith(Dt.Contrast, 'C2 minus S3'), {'Asset','TestRegime','Condition','Model','MeanDiffMAE','CI95_low','CI95_high'}));
fprintf('\n=== Advantage kept under each condition (percent of the clean-F advantage of C2 over S3) ===\n');
disp(Kt);
fprintf('Saved Stage14_Stress_Results/Differences/Retention/PerRun/Inputs (and FaultBreakdown if D was evaluated).csv\n');
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'CHECK'; end
end