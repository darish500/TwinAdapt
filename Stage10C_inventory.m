function Stage10C_inventory()
% Stage 10 closure, step 0: inventory of the authoritative project files.
% Records size, modification time and SHA-256 hash of every script, model, dataset and result file,
% plus the column names / variables of the saved datasets, so later steps refer to exact files.
% Writes Stage10C_Inventory.csv, Stage10C_Schema.txt and Stage10C_Inventory_Log.txt in this folder.
% Nothing is modified or deleted.
here = fileparts(which('Stage10C_inventory'));
if isempty(here), error('Keep Stage10C_inventory.m in the Reformable_AI folder (it must be on the MATLAB path).'); end
cd(here);
diary('Stage10C_Inventory_Log.txt');  diary on
c = onCleanup(@() diary('off'));
fprintf('Inventory %s | MATLAB %s | %s\n', datestr(now), version('-release'), here);

% ---- software versions that matter for reproducibility ----
v = ver;
for k = 1:numel(v)
    if ~isempty(regexp(v(k).Name, 'MATLAB|Simulink|Simscape|Statistics|Optimization|Signal|Curve', 'once'))
        fprintf('  %-45s %s\n', v(k).Name, v(k).Version);
    end
end

% ---- every file, except caches and the repro snapshot ----
L = dir(fullfile(here, '**', '*'));
L = L(~[L.isdir]);
skip = contains({L.folder}, {'slprj', [filesep '.git'], 'Stage10_repro_snapshot'});
L = L(~skip);
inRuns = endsWith({L.folder}, '_runs');
fprintf('\nFiles found: %d (%d inside *_runs folders, summarised below)\n', numel(L), nnz(inRuns));

hashExt = {'.m','.slx','.csv','.mat','.png','.txt','.md','.tex','.pdf','.docx'};
rows = {};
for k = 1:numel(L)
    if inRuns(k), continue, end
    f = fullfile(L(k).folder, L(k).name);
    [~, ~, e] = fileparts(L(k).name);
    h = '';
    if ismember(lower(e), hashExt) && L(k).bytes < 3e8, h = sha256(f); end
    rows(end+1,:) = {strrep(f, [here filesep], ''), role(L(k).name, e), L(k).bytes, datestr(L(k).datenum, 'yyyy-mm-dd HH:MM:SS'), h}; %#ok<AGROW>
end
T = cell2table(rows, 'VariableNames', {'File','Role','Bytes','Modified','SHA256'});
T = sortrows(T, {'Role','File'});
writetable(T, 'Stage10C_Inventory.csv');
fprintf('Saved Stage10C_Inventory.csv (%d files hashed or listed)\n', height(T));

% ---- run folders: count, size, date range ----
fprintf('\n=== Simulation run folders ===\n');
fl = unique({L(inRuns).folder});
for k = 1:numel(fl)
    q = L(strcmp({L.folder}, fl{k}));
    fprintf('  %-60s %4d files  %8.1f MB   %s to %s\n', strrep(fl{k}, [here filesep], ''), numel(q), sum([q.bytes])/1e6, ...
        datestr(min([q.datenum]), 'yyyy-mm-dd HH:MM'), datestr(max([q.datenum]), 'yyyy-mm-dd HH:MM'));
end

% ---- what each Stage 10-13 script says it does (first comment lines) ----
fprintf('\n=== First comment lines of the Stage scripts ===\n');
S = dir(fullfile(here, 'Stage1*.m'));
for k = 1:numel(S)
    fid = fopen(fullfile(S(k).folder, S(k).name), 'r');
    ln = fgetl(fid);  ln2 = fgetl(fid);
    fclose(fid);
    if ~ischar(ln), ln = ''; end
    if ~ischar(ln2), ln2 = ''; end
    fprintf('  %-34s %s | %s\n', S(k).name, strtrim(ln(1:min(end,70))), strtrim(ln2(1:min(end,90))));
end

% ---- schema of saved datasets: variable names in .mat files, header line of .csv files ----
fid = fopen('Stage10C_Schema.txt', 'w');
fprintf(fid, 'Schema listing %s\n', datestr(now));
M = dir(fullfile(here, '*.mat'));
for k = 1:numel(M)
    fprintf(fid, '\n[MAT] %s (%.1f MB)\n', M(k).name, M(k).bytes/1e6);
    try
        w = whos('-file', fullfile(M(k).folder, M(k).name));
        for j = 1:numel(w)
            fprintf(fid, '   %-40s %-14s %s\n', w(j).name, w(j).class, mat2str(w(j).size));
        end
    catch ME
        fprintf(fid, '   (could not read: %s)\n', ME.message);
    end
end
C = dir(fullfile(here, '*.csv'));
for k = 1:numel(C)
    g = fopen(fullfile(C(k).folder, C(k).name), 'r');
    hdr = fgetl(g);  fclose(g);
    if ~ischar(hdr), hdr = '(empty)'; end
    fprintf(fid, '\n[CSV] %s (%.2f MB)\n   %s\n', C(k).name, C(k).bytes/1e6, hdr(1:min(end,1200)));
end
fclose(fid);
fprintf('\nSaved Stage10C_Schema.txt\nDone. Please send back: Stage10C_Inventory.csv, Stage10C_Schema.txt, Stage10C_Inventory_Log.txt\n');
end

function h = sha256(f)
fid = fopen(f, 'r');  b = fread(fid, inf, '*uint8');  fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(b);
u = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(double(u), 2).', 1, []));
end

function r = role(name, ext)
n = lower(name);
if strcmp(ext, '.slx'), r = '1 simulation model';
elseif strcmp(ext, '.m') && startsWith(n, 'reformable'), r = '2 model setup';
elseif strcmp(ext, '.m'), r = '3 script';
elseif strcmp(ext, '.mat') && contains(n, 'param'), r = '4 parameters';
elseif strcmp(ext, '.mat'), r = '5 data (mat)';
elseif strcmp(ext, '.csv') && (contains(n, 'eval') || contains(n, 'result') || contains(n, 'metrics') || contains(n, 'ablation') || contains(n, 'tinyml') || contains(n, 'table')), r = '6 result';
elseif strcmp(ext, '.csv'), r = '5 data (csv)';
elseif strcmp(ext, '.png'), r = '7 figure';
else, r = '8 document/other';
end
end