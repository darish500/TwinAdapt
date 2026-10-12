function Stage10_run_campaign(firstRun, lastRun)
% Runs the Dataset A manifest. Each run is saved to Stage10_runs/run_###.csv.
% Re-running skips runs that already exist, so it is safe to stop and resume.
if nargin < 1, firstRun = 1;   end
if nargin < 2, lastRun  = 100; end
M = readtable('Stage10_DatasetA_Manifest.csv');
if ~exist('Stage10_runs','dir'), mkdir('Stage10_runs'); end
flt = {'Fault_Active','PV_SensorFault_Active','Battery_SensorFault_Active','Battery_Fault_Active'};
failed = [];
for r = firstRun:lastRun
    f = fullfile('Stage10_runs', sprintf('run_%03d.csv', r));
    if isfile(f), continue; end
    m = M(M.run == r, :);
    tic;
    try
        T = Stage10_run_one(m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed);
        assert(abs(mean(T.D_index) - m.pvL/4) < 1e-6 && abs(mean(T.D_batt) - m.bL/4) < 1e-6, 'health level mismatch');
        assert(~any(any(T{:,flt} ~= 0)), 'a fault flag is on in Dataset A');
        writetable(T, f);
        fprintf('>>> run %3d of %d finished in %.1f s\n', r, lastRun, toc);
    catch err
        failed(end+1) = r; %#ok<AGROW>
        fprintf(2, '>>> run %d FAILED: %s\n', r, err.message);
    end
end
if isempty(failed), disp('campaign: no failures'); else, fprintf('failed runs: %s\n', mat2str(failed)); end
end