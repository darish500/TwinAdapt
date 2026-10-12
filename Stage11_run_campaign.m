function Stage11_run_campaign(tag, firstRun, lastRun)
% tag: 'E1' (+-5% params), 'E2' (+-10% params), 'E3' (+-3 pts starting SOC)
if nargin < 2, firstRun = 1;   end
if nargin < 3, lastRun  = 100; end
switch tag
    case 'E1', level = 0.05;  socPts = 0;
    case 'E2', level = 0.10;  socPts = 0;
    case 'E3', level = 0;     socPts = 3;
    case 'E1a', level = 0.01;  socPts = 0;
    case 'E1b', level = 0.02;  socPts = 0;
    otherwise, error('unknown tag %s', tag);
end
M = readtable('Stage10_DatasetA_Manifest.csv');
folder = ['Stage11_' tag '_runs'];
if ~exist(folder,'dir'), mkdir(folder); end
flt = {'Fault_Active','PV_SensorFault_Active','Battery_SensorFault_Active','Battery_Fault_Active'};
failed = [];
for r = firstRun:lastRun
    f = fullfile(folder, sprintf('run_%03d.csv', r));
    if isfile(f), continue; end
    m = M(M.run == r, :);
    tic;
    try
        mm = Stage11_mismatch(level, socPts, 300000 + r);          % same draw for every tag, scaled by level
        T  = Stage11_run_one(m.pvL/4, m.bL/4, m.noiseSeed, m.pvProf, m.bProf, m.pvProfSeed, m.bProfSeed, mm);
        assert(abs(mean(T.D_index) - m.pvL/4) < 1e-6 && abs(mean(T.D_batt) - m.bL/4) < 1e-6, 'health level mismatch');
        assert(~any(any(T{:,flt} ~= 0)), 'a fault flag is on');
        writetable(T, f);
        fprintf('>>> %s run %3d of %d finished in %.1f s\n', tag, r, lastRun, toc);
    catch err
        failed(end+1) = r; %#ok<AGROW>
        fprintf(2, '>>> %s run %d FAILED: %s\n', tag, r, err.message);
    end
end
if isempty(failed), fprintf('%s campaign: no failures\n', tag); else, fprintf('failed runs: %s\n', mat2str(failed)); end
end