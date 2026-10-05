function stage9_closure_passB_diagnostic4()
% stage9_closure_passB_diagnostic4  Mask theory and hardcoded-Constant
% theory are both now ruled out. The remaining live possibility: the
% signal actually logged to the workspace as "Rs_aged" is not sourced
% from the k_Rs-driven MATLAB Function output we inspected at all -- it
% could be tapped from a different block (a second/duplicate aging path,
% a Variant Subsystem, an Integrator that accumulates independently of
% k_Rs, etc). This traces the SIGNAL NAMED "Rs_aged" back to its actual
% source block, wherever that really is in the diagram, rather than
% assuming it's the PV_Degradation_Model MATLAB Function's output.
%
% Does the same for R0_aged for comparison, since that one behaves
% correctly.

mdl = 'Reformable_AI_2025';
load_system(mdl);

sigNames = {'Rs_aged','R0_aged'};

for i = 1:numel(sigNames)
    sigName = sigNames{i};
    fprintf('=== Tracing signal "%s" back to its real source block ===\n', sigName);

    lines = find_system(mdl, 'FindAll','on', 'type','line', 'Name', sigName);
    if isempty(lines)
        fprintf('  No line found with this exact signal name. Trying To Workspace / Outport blocks named %s instead...\n', sigName);
        cand = find_system(mdl,'FindAll','on','RegExp','on','Name',['^' sigName '$']);
        fprintf('  find_system by block name "%s" found %d block(s):\n', sigName, numel(cand));
        for k = 1:numel(cand)
            try
                fprintf('    %s  (BlockType=%s)\n', getfullname(cand(k)), get_param(cand(k),'BlockType'));
            catch
            end
        end
        fprintf('\n');
        continue;
    end

    for L = 1:numel(lines)
        lineH = lines(L);
        srcBlock = get_param(lineH,'SrcBlockHandle');
        srcPort  = get_param(lineH,'SrcPortHandle');
        if srcBlock == -1
            fprintf('  Line %d: no source block handle (likely a root-level signal label with no direct line here).\n', L);
            continue;
        end
        srcName  = getfullname(srcBlock);
        srcType  = get_param(srcBlock,'BlockType');
        fprintf('  Line %d source block: %s   (BlockType = %s)\n', L, srcName, srcType);

        % If the source is itself a Subsystem, that tells us immediately
        % whether it's PV_Degradation_Model or something else entirely.
        if strcmp(srcType,'SubSystem')
            fprintf('    -> sourced from inside/at the boundary of subsystem: %s\n', srcName);
        end

        % If it's a MATLAB Function, list its input argument names so we
        % can confirm k_Rs (or k_R0) is actually among them for THIS
        % specific block instance.
        if strcmp(srcType,'MATLABFunction') || strcmp(srcType,'SubSystem')
            try
                ports = get_param(srcBlock,'PortHandles');
                fprintf('    Inport count: %d\n', numel(ports.Inport));
            catch
            end
        end
    end
    fprintf('\n');
end

fprintf('If "%s"''s source block is NOT inside PV_Degradation_Model (or is a\n', sigNames{1});
fprintf('different block type than the MATLAB Function we read earlier --\n');
fprintf('e.g. an Integrator, a second subsystem, a Variant Subsystem, or a\n');
fprintf('Merge/Switch block picking between two sources), that is the\n');
fprintf('actual root cause: we''ve been correctly diagnosing a block that\n');
fprintf('is not the one actually driving the logged signal.\n');

end