function Stage10_master(rerunSimulations)
% Stage 10 master workflow and reproducibility check (spec Test 16),
% plus a listing of every normalisation line for the scaling audit (spec Test 6).
%
% Use from a freshly started MATLAB session, inside the Reformable_AI folder:
%       clear all; close all; clc
%       Stage10_master            % re-runs the whole ML chain from the saved datasets
%       Stage10_master(true)      % ALSO re-runs reformable_AI and the simulation campaigns (slow)
%
% The first call stores a snapshot of the current result files in Stage10_repro_snapshot.
% Every later call re-creates the results and compares them with that snapshot.
if nargin < 1, rerunSimulations = false; end
% always work in the folder that holds this script and the Stage 10 files, whatever the current folder is
here = fileparts(which('Stage10_master'));
if isempty(here), error('Stage10_master.m must be on the MATLAB path (keep it in the Reformable_AI folder).'); end
cd(here);
if ~isfile('Stage10_final_table.m'), error('Stage10_final_table.m is not in %s. Put Stage10_master.m in the folder with the Stage 10 scripts.', here); end
diary('Stage10_Reproducibility_Log.txt');  diary on
c = onCleanup(@() diary('off'));
t0 = tic;
fprintf('Stage 10 master started %s, MATLAB %s, folder %s\n', datestr(now), version('-release'), pwd);

watch = {'Stage10_Final_Metrics.csv','Stage10_Ablation_Table_A.csv','Stage10_Ablation_Table_B.csv', ...
         'Stage10_Ablation_Results.csv','Stage10_Ablation_ByWear.csv','Stage10_Redundancy.csv', ...
         'Stage10_FeatureAudit.csv','Stage10_TinyML_Estimates.csv','Stage13_Eval_D1.csv'};
snap = 'Stage10_repro_snapshot';

% ---- 1. snapshot of the reference results (taken once) ----
have = watch(cellfun(@isfile, watch));
if ~exist(snap,'dir') || isempty(dir(fullfile(snap,'*.csv')))
    if isempty(have), error('No Stage 10 result CSV files found in %s. Run the ML chain once before using the master script.', pwd); end
    if ~exist(snap,'dir'), mkdir(snap); end
    for k = 1:numel(have), copyfile(have{k}, fullfile(snap, have{k})); end
    fprintf('Reference snapshot stored in %s (%d files).\n', snap, numel(have));
else
    fprintf('Using the existing reference snapshot in %s.\n', snap);
end

% ---- 2. optional: rebuild the simulated data ----
if rerunSimulations
    fprintf('\n--- Re-running reformable_AI and the simulation campaigns (this is slow) ---\n');
    evalin('base','reformable_AI');
    camp = dir('Stage*campaign*.m');
    names = sort({camp.name});
    for k = 1:numel(names)
        n = erase(names{k},'.m');
        if strcmp(n,'Stage13_run_campaign')
            if ~runStep('Stage13_fault_plan'), return; end
        end
        if ~runStep(n), return; end
    end
    if ~runStep2('Stage11_build_features','D'), return; end
end

% ---- 3. the machine-learning chain ----
steps = {'Stage10_ml_compare','Stage10_cv_compare','Stage10_ablation','Stage10_tinyml', ...
         'Stage10_final_table','Stage13_eval_faults','Stage10_plots'};
for k = 1:numel(steps)
    if ~runStep(steps{k}), return; end
end

% ---- 4. compare with the snapshot ----
fprintf('\n=== Reproducibility comparison against %s ===\n', snap);
tol = 1e-6;   allOk = true;
for k = 1:numel(watch)
    ref = fullfile(snap, watch{k});
    if ~isfile(ref) || ~isfile(watch{k})
        fprintf('  %-34s  SKIPPED (file missing: %s)\n', watch{k}, ternary(~isfile(ref),'snapshot','new result'));
        continue
    end
    [ok, d, msg] = compareCsv(watch{k}, ref, tol);
    allOk = allOk && ok;
    fprintf('  %-34s  %s   max |difference| = %.3g  %s\n', watch{k}, ternary(ok,'MATCH   ','DIFFERS '), d, msg);
end

% ---- 5. normalisation audit (Test 6): every line that computes a mean or std ----
fprintf('\n=== Normalisation audit: lines that compute mean/std/zscore/normalize or set Standardize ===\n');
fprintf('Check each line: it must be computed from TRAINING rows only.\n');
fl = [dir('Stage10_*.m'); dir('Stage11_build_features.m')];
for k = 1:numel(fl)
    L = splitlines(fileread(fl(k).name));
    for j = 1:numel(L)
        s = strtrim(L{j});
        if isempty(s) || s(1) == '%', continue, end
        hit = ~isempty(regexp(s, '(zscore|normalize\s*\(|Standardize)', 'once')) || ...
              (~isempty(regexp(s, '\<(mean|std)\s*\(', 'once')) && isempty(regexp(s, 'abs\(|MAE|RMSE|bias', 'once')));
        if hit, fprintf('  %s:%d:  %s\n', fl(k).name, j, s(1:min(end,150))); end
    end
end

fprintf('\n=== RESULT: %s ===\n', ternary(allOk, 'every compared result file reproduced within tolerance', 'at least one result file differs: see the table above'));
fprintf('Elapsed %.1f minutes. Log saved in Stage10_Reproducibility_Log.txt\n', toc(t0)/60);
end

function ok = runStep(name)
fprintf('\n=== %s ===\n', name);  t = tic;
ok = true;
try
    if exist(name,'file') ~= 2, error('%s.m not found in %s', name, pwd); end
    feval(name);
catch ME
    ok = false;  fprintf(2, 'STEP FAILED: %s\n   %s\n', name, ME.message);
    return
end
fprintf('--- %s finished in %.1f s ---\n', name, toc(t));
end

function ok = runStep2(name, arg)
fprintf('\n=== %s(''%s'') ===\n', name, arg);  ok = true;
try
    feval(name, arg);
catch ME
    ok = false;  fprintf(2, 'STEP FAILED: %s\n   %s\n', name, ME.message);
end
end

function [ok, dmax, msg] = compareCsv(newF, oldF, tol)
A = readtable(newF);  B = readtable(oldF);
ok = true;  dmax = 0;  msg = '';
if ~isequal(A.Properties.VariableNames, B.Properties.VariableNames) || height(A) ~= height(B)
    ok = false;  msg = '(different columns or number of rows)';  return
end
for v = 1:width(A)
    a = A.(v);  b = B.(v);
    if isnumeric(a) && isnumeric(b)
        if ~isequal(isnan(a), isnan(b)), ok = false;  msg = ['(NaN pattern differs in ' A.Properties.VariableNames{v} ')'];  return, end
        d = max(abs(a(:) - b(:)), [], 'omitnan');
        if ~isempty(d) && ~isnan(d), dmax = max(dmax, d); end
    else
        if ~isequal(string(a), string(b)), ok = false;  msg = ['(text differs in ' A.Properties.VariableNames{v} ')'];  return, end
    end
end
if dmax > tol, ok = false; end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end