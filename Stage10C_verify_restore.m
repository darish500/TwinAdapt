function Stage10C_verify_restore(restoreDir)
% Compares every file in a restored copy of the project against the SHA-256 values recorded in the
% Stage10C inventory (Stage10C_Inventory.csv, found inside restoreDir). Read-only: nothing is changed.
% Usage (from anywhere):  Stage10C_verify_restore('/home/inspiredkhalid/workspace/Matlab_workspace/Reformable_AI_restore')
if nargin < 1, error('Give the restored folder, e.g. Stage10C_verify_restore(''../Reformable_AI_restore'')'); end
restoreDir = char(java.io.File(restoreDir).getCanonicalPath());
ref = fullfile(restoreDir, 'Stage10C_Inventory.csv');
if ~isfile(ref), error('No Stage10C_Inventory.csv in %s', restoreDir); end
fprintf('Reference inventory SHA-256: %s\n', sha256(ref));
T = readtable(ref, 'TextType', 'string');
T = T(strlength(T.SHA256) > 0, :);
nOK = 0; bad = strings(0,1); missing = strings(0,1);
for k = 1:height(T)
    f = fullfile(restoreDir, strrep(char(T.File(k)), '\', filesep));
    if ~isfile(f), missing(end+1,1) = T.File(k); continue; end %#ok<AGROW>
    if strcmpi(sha256(f), T.SHA256(k)), nOK = nOK + 1; else, bad(end+1,1) = T.File(k); end %#ok<AGROW>
end
fprintf('\nFiles with a recorded hash: %d\n  identical   : %d\n  DIFFERENT   : %d\n  not restored: %d\n', height(T), nOK, numel(bad), numel(missing));
if ~isempty(bad),     fprintf('\nDIFFERENT (hash does not match the inventory):\n');  fprintf('  %s\n', bad); end
if ~isempty(missing), fprintf('\nNOT PRESENT in the restore:\n');                     fprintf('  %s\n', missing); end

fprintf('\n=== run folders (the inventory does not hash these, so only counts are checked) ===\n');
for d = {'Stage10_runs','Stage11_D_runs','Stage11_E1_runs','Stage11_E1a_runs','Stage11_E1b_runs','Stage11_E3_runs'}
    L = dir(fullfile(restoreDir, d{1}, 'run_*.csv'));
    fprintf('  %-20s %3d run files%s\n', d{1}, numel(L), ternary(numel(L) == 100, '', '   <-- expected 100'));
end
end

function h = sha256(f)
fid = fopen(f, 'r');  b = fread(fid, inf, '*uint8');  fclose(fid);
md = java.security.MessageDigest.getInstance('SHA-256');
md.update(b);
u = typecast(md.digest(), 'uint8');
h = lower(reshape(dec2hex(double(u), 2).', 1, []));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end