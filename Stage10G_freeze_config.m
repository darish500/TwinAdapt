function Stage10G_freeze_config()
% Corrected Stage 10 evaluation, step 1 of 2: validation on DATASET A ONLY, then freeze every choice before Dataset F is evaluated.
%
% Design
%   Development data  : all 100 runs of Dataset A (Stage10_Features_PV/Battery.csv). Nothing from Dataset F is read here
%                       (the F files are only hashed, byte for byte, so the final test can prove they did not change).
%   Validation        : leave-one-group-out inside Dataset A, whole runs held out together.
%       scheme 'level'   : hold out every run of one health level (5 folds)       -> mirrors Regime A (unseen health levels)
%       scheme 'profile' : hold out every run of one operating profile (4 folds)   -> mirrors Regime B (unseen operating profile)
%   Chosen here       : the ridge penalty lambda for each (asset, feature set), as the lowest mean of
%                       [mean validation MAE over level folds, mean validation MAE over profile folds].
%   Not tuned         : the feature sets (fixed in Stage10G_lib), the network (8 ReLU units, 300 iterations, as in Stage 10), seeds.
%   Frozen to         : Stage10G_Config.json + Stage10G_Config.sha256. Stage10G_final_test.m refuses to run if either changed.
% Writes: Stage10G_Validation_Folds.csv, Stage10G_Validation_Summary.csv, Stage10G_Config.json, Stage10G_Config.sha256.
here = fileparts(which('Stage10G_freeze_config'));
if isempty(here), error('Keep the Stage10G_* files in the Reformable_AI folder (on the MATLAB path).'); end
cd(here);
if isfile('Stage10G_Config.json')
    error('Stage10G_Config.json already exists: the configuration is frozen. Delete it only on purpose, and say why in the report.');
end
need = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv','Stage10F_Manifest.csv','Stage10F_Features_PV.csv','Stage10F_Features_Battery.csv','Stage10G_lib.m'};
for k = 1:numel(need), if ~isfile(need{k}), error('Missing %s', need{k}); end, end

cfg = struct();
cfg.created       = datestr(now, 'yyyy-mm-dd HH:MM:SS');
cfg.matlab        = version;
cfg.lambdaGrid    = [0.01 0.1 1 10 100 1000];
cfg.nn            = struct('hidden', 8, 'iterations', 300, 'standardize', true, 'activation', 'relu', 'seedsFinal', 1:10);
cfg.bootstrap     = struct('resamples', 2000, 'seed', 20261015, 'level', 0.95, 'unit', 'run');
cfg.primaryContrast = 'C2 strong + residual windows minus S3 sensor strong (baseline), per-run MAE, ridge and network';
cfg.validation    = 'leave-one-group-out inside Dataset A (level folds and profile folds), whole runs held out';
cfg.final         = 'train on all 100 Dataset A runs; test once on Dataset F (A-F: unseen health levels, B-F: unseen profile family)';
cfg.trees         = 'not evaluated: bagged trees cannot extrapolate to unseen health levels (Regime A), documented in the Stage 10 report';
cfg.rowUnit       = 'one row per second from t >= 60 s (91 rows per run)';
cfg.hashes        = struct('libSha256', Stage10G_lib('sha256','Stage10G_lib.m'), ...
                           'featuresA_PV',      Stage10G_lib('sha256','Stage10_Features_PV.csv'), ...
                           'featuresA_Battery', Stage10G_lib('sha256','Stage10_Features_Battery.csv'), ...
                           'manifestF',         Stage10G_lib('sha256','Stage10F_Manifest.csv'), ...
                           'featuresF_PV',      Stage10G_lib('sha256','Stage10F_Features_PV.csv'), ...
                           'featuresF_Battery', Stage10G_lib('sha256','Stage10F_Features_Battery.csv'));

assets = {'PV','Battery'};
files  = {'Stage10_Features_PV.csv','Stage10_Features_Battery.csv'};
lamSel = struct('asset', {}, 'set', {}, 'lambda', {}, 'valScore', {});
foldRows = {};  sumRows = {};
for a = 1:2
    F = readtable(files{a});
    [F, S] = Stage10G_lib('sets', F, assets{a});
    y = F.D;
    levels = unique(F.level);  profs = unique(F.profile);
    for s = 1:numel(S)
        X = F{:, S(s).cols};
        nL = numel(cfg.lambdaGrid);
        mL = zeros(nL, numel(levels));  mP = zeros(nL, numel(profs));
        for li = 1:nL
            for f = 1:numel(levels)
                te = F.level == levels(f);
                p = Stage10G_lib('ridge', X(~te,:), y(~te), X(te,:), cfg.lambdaGrid(li));
                mL(li,f) = mean(abs(p - y(te)));
                foldRows(end+1,:) = {assets{a}, S(s).name, 'level', levels(f), cfg.lambdaGrid(li), mL(li,f)}; %#ok<AGROW>
            end
            for f = 1:numel(profs)
                te = F.profile == profs(f);
                p = Stage10G_lib('ridge', X(~te,:), y(~te), X(te,:), cfg.lambdaGrid(li));
                mP(li,f) = mean(abs(p - y(te)));
                foldRows(end+1,:) = {assets{a}, S(s).name, 'profile', profs(f), cfg.lambdaGrid(li), mP(li,f)}; %#ok<AGROW>
            end
        end
        score = (mean(mL,2) + mean(mP,2)) / 2;            % equal weight to the two validation schemes
        [best, ib] = min(score);
        lamSel(end+1) = struct('asset', assets{a}, 'set', S(s).name, 'lambda', cfg.lambdaGrid(ib), 'valScore', best); %#ok<AGROW>
        sumRows(end+1,:) = {assets{a}, S(s).name, numel(S(s).cols), cfg.lambdaGrid(ib), round(mean(mL(ib,:)),4), round(mean(mP(ib,:)),4), round(best,4)}; %#ok<AGROW>
        fprintf('%-8s %-34s lambda %-6g validation MAE: levels %.4f | profiles %.4f\n', assets{a}, S(s).name, cfg.lambdaGrid(ib), mean(mL(ib,:)), mean(mP(ib,:)));
    end
end
cfg.lambda = lamSel;
cfg.sets   = {S.name};

writetable(cell2table(foldRows, 'VariableNames', {'Asset','FeatureSet','Scheme','HeldOutGroup','Lambda','MAE'}), 'Stage10G_Validation_Folds.csv');
writetable(cell2table(sumRows,  'VariableNames', {'Asset','FeatureSet','nFeatures','ChosenLambda','ValMAE_levels','ValMAE_profiles','ValScore'}), 'Stage10G_Validation_Summary.csv');

fid = fopen('Stage10G_Config.json', 'w');  fwrite(fid, jsonencode(cfg, 'PrettyPrint', true));  fclose(fid);
h = Stage10G_lib('sha256', 'Stage10G_Config.json');
fid = fopen('Stage10G_Config.sha256', 'w');  fprintf(fid, '%s\n', h);  fclose(fid);
fprintf('\nConfiguration frozen.\nStage10G_Config.json SHA-256: %s\n', h);
fprintf('Write this hash into the report. Nothing from Dataset F has been read, trained on or evaluated.\n');
end