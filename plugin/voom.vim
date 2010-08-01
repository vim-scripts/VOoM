" voom.vim
" VOoM (Vim Outliner of Markers): two-pane outliner and related utilities
" plugin for Python-enabled Vim version 7.x
" Website: http://www.vim.org/scripts/script.php?script_id=2657
" Author:  Vlad Irnov (vlad DOT irnov AT gmail DOT com)
" License: This program is free software. It comes without any warranty,
"          to the extent permitted by applicable law. You can redistribute it
"          and/or modify it under the terms of the Do What The Fuck You Want To
"          Public License, Version 2, as published by Sam Hocevar.
"          See http://sam.zoy.org/wtfpl/COPYING for more details.
" Version: 3.0, 2010-08-01


"---Conventions-------------------------------{{{1
" Tree      --Tree buffer
" Body      --Body buffer
" tree      --Tree buffer number
" body      --Body buffer number
" headline  --Body line with a matching fold marker, also a Tree line
" node      --Body region between two headlines, usually also a fold.
"             A node is identified by Tree lnum (nodes) or Body lnum (bnodes).
" nodes     --list of Tree lnums
" bnodes    --list of Body lnums, line numbers of Body headlines
" bnr       --buffer number
" wnr, tnr  --window number, tab number
" lnum, ln, lnr      --line number, usually Tree
" blnum, bln, blnr   --Body line number
" tline(s)  --Tree line(s)
" bline(s)  --Body line(s)
" snLn      --selected node line number, a Tree line number
" var_      --previous value of var
" l:var     --this var is set by Python code (l:blnShow)
" z, Z      --list siZe, usually len(bnodes)


"---Quickload---------------------------------{{{1
if !exists('s:voom_did_load')
    let s:voom_did_load = 'v3.0'
    com! Voom  call Voom_Init()
    com! Voomlog  call Voom_LogInit()
    com! Voomhelp  call Voom_Help()
    com! -nargs=? Voomexec  call Voom_Exec(<q-args>)
    exe "au FuncUndefined Voom_* source " . expand("<sfile>:p")
    finish
endif


"---Initialize--------------------------------{{{1
if !exists('s:voom_did_init')
    let s:voom_path = expand("<sfile>:p")
    let s:voom_dir = expand("<sfile>:p:h")
    let s:voom_script_py = s:voom_dir.'/voomScript.py'

    " {tree : associated body,  ...}
    let s:voom_trees = {}
    " {body : {'tree' : associated tree,
    "          'blnr' : Body cursor lnum, set when selecting node from Body,
    "          'snLn' : selected node Tree lnum,
    "          'tick' : b:changedtick of Body on Body BufLeave,
    "          'tick_' : b:changedtick of Body on last Tree update}, {...}, ... }
    let s:voom_bodies = {}

python << EOF
import vim
import sys
voom_dir = vim.eval('s:voom_dir')
if not voom_dir in sys.path:
    sys.path.append(voom_dir)
import voom
VOOM = sys.modules['voom'].VOOM = voom.VoomData()
EOF
    au! FuncUndefined Voom_*
    let s:voom_did_init = 1
endif


"---User Options------------------------------{{{1
" These can be defined in .vimrc .

" Where Tree window is created: 'left', 'right', 'top', 'bottom'
" This is relative to the current window.
if !exists('g:voom_tree_placement')
    let g:voom_tree_placement = 'left'
endif
" Initial Tree window width.
if !exists('g:voom_tree_width')
    let g:voom_tree_width = 30
endif
" Initial Tree window height.
if !exists('g:voom_tree_height')
    let g:voom_tree_height = 12
endif

" Where Log window is created: 'left', 'right', 'top', 'bottom'
" This is far left/right/top/bottom.
if !exists('g:voom_log_placement')
    let g:voom_log_placement = 'bottom'
endif
" Initial Log window width.
if !exists('g:voom_log_width')
    let g:voom_log_width = 30
endif
" Initial Log window height.
if !exists('g:voom_log_height')
    let g:voom_log_height = 12
endif

" Verify outline after outline operations.
if !exists('g:voom_verify_oop')
    let g:voom_verify_oop = 0
endif

" Which key to map to Select-Node-and-Shuttle-between-Body/Tree
if !exists('g:voom_return_key')
    let g:voom_return_key = '<Return>'
endif

" Which key to map to Shuttle-between-Body/Tree
if !exists('g:voom_tab_key')
    let g:voom_tab_key = '<Tab>'
endif

" {filetype: chars to strip from right side of Tree headlines, ...}
" If defined, these will be used instead of 'commentstring' chars.
if !exists('g:voom_rstrip_chars')
    let g:voom_rstrip_chars = {"vim": "\"# \t", "text": " \t", "help": " \t" }
endif


"---Commands----------------------------------{{{1
" Main commands are defined in Quickload section.
" Naming convention: Voomdoit will not modify Body, VoomDoit can modify Body.

com! Voomunl call Voom_EchoUNL()
com! -nargs=? Voomgrep call Voom_Grep(<q-args>)

com! -nargs=? VoomSort call Voom_OopSort(<q-args>)

com! -range VoomFoldingSave    call Voom_OopFolding(<line1>,<line2>, 'save')
com! -range VoomFoldingRestore call Voom_OopFolding(<line1>,<line2>, 'restore')
com! -range VoomFoldingCleanup call Voom_OopFolding(<line1>,<line2>, 'cleanup')

""" development helpers
if exists('g:voom_create_devel_commands')
    " print Vim-side data
    com! VoomPrintData  call Voom_PrintData()
    " source voom.vim, reload voom.py
    com! VoomReload    exe 'so '.s:voom_path.' | python reload(voom)'
    " source voom.vim
    com! VoomReloadVim exe 'so '.s:voom_path
    " reload voom.py
    com! VoomReloadPy  python reload(voom)
    " complete reload: delete Trees and Voom data, source voom.vim, reload voom.py
    com! VoomReloadAll call Voom_ReloadAllPre() | exe 'so '.s:voom_path | call Voom_Init()
endif


"---Voom_Init(), various helpers--------------{{{1

func! Voom_Init() "{{{2
" The :Voom command.
    let bnr = bufnr('')
    " This is Tree. Go to Body, loading it if needed.
    if has_key(s:voom_trees, bnr)
        let body = s:voom_trees[bnr]
        if !hasmapto('Voom_ToTreeOrBodyWin','n')
            echoerr "VOoM: Tree lost mappings. Reconfiguring..."
            call Voom_TreeConfig()
        endif
        call Voom_ToBody(body, '')
        return
    " This is Body. Go to Tree.
    elseif has_key(s:voom_bodies, bnr)
        let tree = s:voom_bodies[bnr].tree
        if !hasmapto('Voom_ToTreeOrBodyWin','n')
            echoerr "VOoM: Body lost mappings. Reconfiguring..."
            call Voom_BodyConfig()
        endif
        if Voom_ToTree(tree) < 0 | return | endif
        return
    " This is not a VOoM buffer.
    " Create Tree for current buffer, which becomes a Body buffer.
    else
        let body = bnr
        let s:voom_bodies[body] = {}
        let s:voom_bodies[body].blnr = line('.')
        let b_name = expand('%:p:t')
        if b_name=='' | let b_name='No Name' | endif
        let b_dir = expand('%:p:h')
        let l:firstLine = ' '.b_name.' ['.b_dir.'], b'.body
        python voom.voom_Init(int(vim.eval('l:body')))
        call Voom_BodyConfig()
        call Voom_ToTreeWin()
        call Voom_TreeCreate(body)
    endif
endfunc


func! Voom_Help() "{{{2
" Open voom.txt as outline in a new tabpage.
    let bnr = bufnr('')
    " already in voom.txt
    if fnamemodify(bufname(bnr), ":t")==#'voom.txt'
        if !has_key(s:voom_bodies, bnr)
            setl fdm=marker fmr=[[[,]]]
        endif
        if &ft!=#'help'
            set ft=help
        endif
        call Voom_Init()
        return
    " in Tree for voom.txt
    elseif has_key(s:voom_trees, bnr) && fnamemodify(bufname(s:voom_trees[bnr]), ":t")==#'voom.txt'
        return
    endif

    """"" if voom.vim is in /a/b, voom.txt is expected in /a/doc
    let voom_help = fnamemodify(s:voom_dir, ":h") . '/doc/voom.txt'
    if !filereadable(voom_help)
        echoerr "VOoM: can't read help file:" voom_help
        return
    endif

    """"" try help command
    let voom_help_installed = 1
    let tnr_ = tabpagenr()
    try
        silent tab help voom.txt
    catch /^Vim\%((\a\+)\)\=:E149/ " no help for voom.txt
        let voom_help_installed = 0
    catch /^Vim\%((\a\+)\)\=:E429/ " help file not found--removed after installing
        let voom_help_installed = 0
    endtry
    if voom_help_installed==1
        if fnamemodify(bufname(""), ":t")!=#'voom.txt'
            echoerr "VOoM: internal error"
            return
        endif
        setl fdm=marker fmr=[[[,]]]
        call Voom_Init()
        return
    elseif tabpagenr()==tnr_+1 && bufname('')==''
        " 'tab help' failed, we are on new empty tabpage
        bwipeout
        exe 'tabnext '.tnr_
    endif

    """"" open voom.txt as regular file
    exe 'tabnew '.voom_help
    if fnamemodify(bufname(""), ":t")!=#'voom.txt'
        echoerr "VOoM: internal error"
        return
    endif
    if &ft!=#'help'
        set ft=help
    endif
    setl fdm=marker fmr=[[[,]]]
    call Voom_Init()
endfunc


func! Voom_FoldStatus(lnum) "{{{2
" Helper for dealing with folds. Determine if line lnum is:
"  not in a fold;
"  hidden in a closed fold;
"  not hidden and is a closed fold;
"  not hidden and is in an open fold.
    " there is no fold
    if foldlevel(a:lnum)==0
        return 'nofold'
    endif
    let fc = foldclosed(a:lnum)
    " line is hidden in fold, cannot determine it's status
    if fc < a:lnum && fc > 0
        return 'hidden'
    " line is first line of a closed fold
    elseif fc==a:lnum
        return 'folded'
    " line is in an opened fold
    else
        return 'notfolded'
    endif
endfunc


func! Voom_WarningMsg(...) "{{{2
    echohl WarningMsg
    for line in a:000
        echo line
    endfor
    echohl None
endfunc


func! Voom_ErrorMsg(...) "{{{2
    echohl Error
    for line in a:000
        echom line
    endfor
    echohl None
endfunc


func! Voom_BufLoaded(body) "{{{2
    if !bufloaded(a:body)
        if bufexists(a:body)
            let bname = fnamemodify(bufname(a:body),":t")
            call Voom_ErrorMsg('VOoM: Body buffer '.a:body.' ('.bname.') is not loaded')
        else
            call Voom_ErrorMsg('VOoM: Body buffer '.a:body.' does not exist')
        endif
        return -1
    endif
endfunc


func! Voom_BufEditable(body) "{{{2
" Check if Body is 'noma' or 'ro' before outline operation.
" Also catches if buffer doesn't exist.
    if getbufvar(a:body, "&ma")==0 || getbufvar(a:body, "&ro")==1
        let bname = fnamemodify(bufname(a:body),":t")
        call Voom_ErrorMsg("VOoM: Body buffer ".a:body." (".bname.") is 'nomodifiable' or 'readonly'")
        return -1
    endif
endfunc


func! Voom_DeleteOutline(ex_command) "{{{2
" Delete outline if current buffer is Tree or Body.
" Then execute ex_command if current buffer is not Tree.
    let bnr = bufnr('')
    " current buffer is Tree
    if has_key(s:voom_trees, bnr)
        let body = s:voom_trees[bnr]
        call Voom_UnVoom(body,bnr)
        return
    " current buffer is Body
    elseif has_key(s:voom_bodies, bnr)
        let tree = s:voom_bodies[bnr].tree
        call Voom_UnVoom(bnr,tree)
        execute a:ex_command
        return
    " not a VOoM buffer
    else
        execute a:ex_command
        return
    endif
endfunc


func! Voom_UnVoom(body,tree) "{{{2
" Remove VOoM data for Body body and its Tree tree.
" Wipeout Tree, delete Body au, etc.
" Can be called from any buffer.
" Note: when called from Tree BufUnload au, tree doesn't exist.
    if has_key(s:voom_trees, a:tree)
        unlet s:voom_trees[a:tree]
    endif
    if has_key(s:voom_bodies, a:body)
        unlet s:voom_bodies[a:body]
    endif
    python voom.voom_UnVoom()
    exe 'au! VoomBody * <buffer='.a:body.'>'
    if bufexists(a:tree)
        exe 'noautocmd bwipeout '.a:tree
    endif
    if bufnr('')==a:body
        call Voom_BodyUnMap()
    endif
endfunc


func! Voom_GetData() "{{{2
" Allow external scripts and add-ons to read Vim-side Voom data.
    return [s:voom_bodies, s:voom_trees]
endfunc


func! Voom_GetBufInfo() "{{{2
" Helper for external scripts and add-ons.
" Return ['Body' or 'Tree', body, tree] for current buffer.
" Return [None,0,0] if current buffer is neither Body nor Tree.
" Update outline if current buffer is Body.

    """ Determine Tree or Body buffer numbers.
    let bnr = bufnr('')
    " current buffer is Tree
    if has_key(s:voom_trees, bnr)
        let type = 'Tree'
        let tree = bnr
        let body = s:voom_trees[bnr]
        if Voom_BufLoaded(body) < 0 | return ['None',0,0] | endif
    " current buffer is Body
    elseif has_key(s:voom_bodies, bnr)
        let type = 'Body'
        let body = bnr
        let tree = s:voom_bodies[bnr].tree
        " update outline
        if Voom_BodyUpdateTree() < 0
            return ['None',0,0]
        endif
    else
        call Voom_ErrorMsg("VOoM: current buffer is not a VOoM buffer")
        return ['None',0,0]
    endif
    return [type, body, tree]
endfunc


func! Voom_SetSnLn(body, snLn) "{{{2
" Set snLn. Used by Python code.
    let s:voom_bodies[a:body].snLn= a:snLn
endfunc


func! Voom_PrintData() "{{{2
" Print Vim-side VOoM data.
    redir => voomData
    silent echo repeat('-', 60)
    if exists('s:voom_logbnr')
        silent echo 's:voom_logbnr --' s:voom_logbnr
    endif
    for v in ['s:voom_did_load', 's:voom_did_init', 's:voom_dir', 's:voom_path', 's:voom_script_py', 'g:voom_verify_oop', 's:voom_trees', 's:voom_bodies']
        silent echo v '--' {v}
    endfor
    redir END
    echo ' '
    python print vim.eval('l:voomData')
endfunc


func! Voom_ReloadAllPre() "{{{2
" Helper for reloading entire plugin.
    update
    " wipe out all Tree buffers
    for bnr in keys(s:voom_trees)
        if bufexists(str2nr(bnr))
            exe 'bwipeout '.bnr
        endif
    endfor
    python reload(voom)
    unlet s:voom_did_init
endfunc


"---Windows Navigation and Creation-----------{{{1
" These deal only with the current tab page.

func! Voom_ToTreeOrBodyWin() "{{{2
" If in Tree window, move to Body window.
" If in Body window, move to Tree window.
" If possible, use previous window.
    let bnr = bufnr('')
    " current buffer is Tree
    if has_key(s:voom_trees, bnr)
        let target = s:voom_trees[bnr]
    " current buffer is Body
    else
        " This happens after Tree is wiped out.
        if !has_key(s:voom_bodies, bnr)
            call Voom_BodyUnMap()
            return
        endif
        let target = s:voom_bodies[bnr].tree
    endif
    " Try previous window. It's the most common case.
    let wnr = winnr('#')
    if winbufnr(wnr)==target
        exe wnr.'wincmd w'
        return
    endif
    " Use any other window.
    if bufwinnr(target) > 0
        exe bufwinnr(target).'wincmd w'
        return
    endif
endfunc


func! Voom_ToTreeWin() "{{{2
" Move to window or create a new one where a Tree will be loaded.

    " Allready in a Tree buffer.
    if has_key(s:voom_trees, bufnr('')) | return | endif

    " Use previous window if it shows Tree.
    let wnr = winnr('#')
    if has_key(s:voom_trees, winbufnr(wnr))
        exe wnr.'wincmd w'
        return
    endif

    " Use any window with a Tree buffer.
    for bnr in tabpagebuflist()
        if has_key(s:voom_trees, bnr)
            exe bufwinnr(bnr).'wincmd w'
            return
        endif
    endfor

    " Create new window.
    if g:voom_tree_placement=='top'
        exe 'leftabove '.g:voom_tree_height.'split'
    elseif g:voom_tree_placement=='bottom'
        exe 'rightbelow '.g:voom_tree_height.'split'
    elseif g:voom_tree_placement=='left'
        exe 'leftabove '.g:voom_tree_width.'vsplit'
    elseif g:voom_tree_placement=='right'
        exe 'rightbelow '.g:voom_tree_width.'vsplit'
    endif
endfunc


func! Voom_ToTree(tree) abort "{{{2
" Move cursor to window with Tree buffer tree.
" If there is no such window, load buffer in a new window.
    " Already there.
    if bufnr('')==a:tree | return | endif

    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==a:tree
        exe wnr.'wincmd w'
        return
    endif

    " There is window with buffer a:tree.
    if bufwinnr(a:tree) > 0
        exe bufwinnr(a:tree).'wincmd w'
        return
    endif

    " Bail out if Tree is unloaded or doesn't exist.
    " Because of au, this should never happen.
    if !bufloaded(a:tree)
        let body = s:voom_trees[a:tree]
        call Voom_UnVoom(body,a:tree)
        echoerr "VOoM: Tree buffer" a:tree "is not loaded or does not exist. Cleanup has been performed."
        return -1
    endif

    " Create new window and load there.
    call Voom_ToTreeWin()
    silent exe 'b '.a:tree
    " window-local options will be set on BufEnter
endfunc


func! Voom_ToBodyWin() "{{{2
" Split current Tree window to create window where Body will be loaded
    if g:voom_tree_placement=='top'
        exe 'leftabove '.g:voom_tree_height.'split'
        wincmd p
    elseif g:voom_tree_placement=='bottom'
        exe 'rightbelow '.g:voom_tree_height.'split'
        wincmd p
    elseif g:voom_tree_placement=='left'
        exe 'leftabove '.g:voom_tree_width.'vsplit'
        wincmd p
    elseif g:voom_tree_placement=='right'
        exe 'rightbelow '.g:voom_tree_width.'vsplit'
        wincmd p
    endif
endfunc


func! Voom_ToBody(body, noa) abort "{{{2
" Move to window with Body a:body or load it in a new window.
" If a:noa is 'noa', use noautocmd with "wincmd w".
    " Allready there.
    if bufnr('')==a:body | return | endif

    let m = a:noa==#'noa' ? 'noautocmd ' : ''

    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==a:body
        exe m.wnr.'wincmd w'
        return
    endif

    " There is a window with buffer a:body .
    if bufwinnr(a:body) > 0
        exe m.bufwinnr(a:body).'wincmd w'
        return
    endif

    if !bufloaded(a:body)
        " Body is unloaded. Load it and force outline update.
        if bufexists(a:body)
            call Voom_ToBodyWin()
            exe 'b '.a:body
            call Voom_BodyUpdateTree()
            call Voom_WarningMsg('VOoM: loaded Body buffer and updated outline')
        " Body doesn't exist. Bail out.
        else
            let tree = s:voom_bodies[a:body].tree
            if !has_key(s:voom_trees, tree) || s:voom_trees[tree]!=a:body
                echoerr "VOoM: internal error"
                return -1
            endif
            call Voom_UnVoom(a:body,tree)
            call Voom_ErrorMsg("VOoM: Body ".a:body." does not exist. Cleanup has been performed.")
        endif
        return -1
    endif

    " Create new window and load there.
    call Voom_ToBodyWin()
    exe 'b '.a:body
endfunc


func! Voom_ToLogWin() "{{{2
" Create new window where PyLog will be loaded.
    if g:voom_log_placement=='top'
        exe 'topleft '.g:voom_log_height.'split'
    elseif g:voom_log_placement=='bottom'
        exe 'botright '.g:voom_log_height.'split'
    elseif g:voom_log_placement=='left'
        exe 'topleft '.g:voom_log_width.'vsplit'
    elseif g:voom_log_placement=='right'
        exe 'botright '.g:voom_log_width.'vsplit'
    endif
endfunc


"---TREE BUFFERS------------------------------{{{1

func! Voom_TreeCreate(body) "{{{2
" Create new Tree buffer for Body body in the current window.

    let b_name = fnamemodify(bufname(a:body),":t")
    if b_name=='' | let b_name='NoName' | endif
    silent exe 'edit '.b_name.'_VOOM'.a:body
    let tree = bufnr('')
    let blnr = s:voom_bodies[a:body].blnr

    """ Initialize VOoM data.
    let s:voom_bodies[a:body].tree = tree
    let s:voom_trees[tree] = a:body
    let s:voom_bodies[a:body].tick_ = 0
    python VOOM.buffers[int(vim.eval('l:tree'))] = vim.current.buffer

    call Voom_TreeConfig()

    """ Create outline and draw Tree lines.
    let lz_ = &lz | set lz
    setl ma
    let ul_=&ul | setl ul=-1
    try
        keepj python voom.updateTree(int(vim.eval('a:body')), int(vim.eval('l:tree')))
        " Draw = mark. Create folding from o marks.
        " This must be done afer creating outline.
        " this assigns s:voom_bodies[body].snLn
        python voom.voom_TreeCreate()
        let snLn = s:voom_bodies[a:body].snLn
        " Initial draw puts = on first line.
        if snLn!=1
            keepj call setline(snLn, '='.getline(snLn)[1:])
            keepj call setline(1, ' '.getline(1)[1:])
        endif
        let s:voom_bodies[a:body].tick_ = s:voom_bodies[a:body].tick
    finally
        let &ul=ul_
        setl noma
        let &lz=lz_
    endtry

    """ Show startup node.
    exe 'normal! gg' . snLn . 'G'
    call Voom_TreeZV()
    call Voom_TreePlaceCursor()
    if line('w0')!=1 && line('w$')!=line('$')
        normal! zz
    endif
    " blnShow is created by voom_TreeCreate() when there is Body headline marked with =
    if exists('l:blnShow')
        " go to Body
        let wnr_ = winnr()
        if Voom_ToBody(a:body,'noa') < 0 | return | endif
        " show fold at l:blnShow
        exe 'normal! '.l:blnShow.'G'
        if &fdm==#'marker'
            normal! zMzvzt
        else
            normal! zvzt
        endif
        " go back to Tree
        let wnr_ = winnr('#')
        if winbufnr(wnr_)==tree
            exe 'noautocmd '.wnr_.'wincmd w'
        else
            exe 'noautocmd '.bufwinnr(tree).'wincmd w'
        endif
    endif
endfunc


func! Voom_TreeConfig() "{{{2
" Configure current buffer as a Tree buffer.
    augroup VoomTree
        au! * <buffer>
        au BufEnter   <buffer> call Voom_TreeBufEnter()
        "au BufUnload  <buffer> call Voom_TreeBufUnload()
        au BufUnload  <buffer> nested call Voom_TreeBufUnload()
    augroup END

    call Voom_TreeMap()

    " Options local to window.
    call Voom_TreeConfigWin()

    " local to buffer, may be changed by the user
    setl bufhidden=wipe

    " This should allow customizing via ftplugin. Removes syntax hi.
    setl ft=voomtree

    " Options local to buffer. Should not be changed.
    setl nobuflisted buftype=nofile noswapfile
    setl noro ma ff=unix noma

    call Voom_TreeSyntax()
endfunc


func! Voom_TreeConfigWin() "{{{2
" Set Tree window-local options.
    setl foldenable
    setl foldtext=getline(v:foldstart).'\ \ \ /'.(v:foldend-v:foldstart)
    setl foldmethod=expr
    setl foldexpr=Voom_TreeFoldexpr(v:lnum)
    setl cul nocuc nowrap nolist
    "setl winfixheight
    setl winfixwidth

    let w:voom_tree = 'VOoM'
endfunc


func! Voom_TreeBufEnter() "{{{2
" Tree's BufEnter au.
" Update outline if Body was changed since last update. Redraw Tree if needed.
    let tree = bufnr('')
    let body = s:voom_trees[tree]

    if !exists('w:voom_tree')
        call Voom_TreeConfigWin()
    endif

    """ update is not needed
    if s:voom_bodies[body].tick_==s:voom_bodies[body].tick
        return
    endif

    """ don't update if Body is not loaded
    if Voom_BufLoaded(body) < 0 | return | endif

    """ do update
    let snLn_ = s:voom_bodies[body].snLn
    setl ma
    let ul_=&ul | setl ul=-1
    try
        keepj python voom.updateTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
        let s:voom_bodies[body].tick_ = s:voom_bodies[body].tick
    finally
        let &ul=ul_
        setl noma
    endtry

    " The = mark is placed by updateTree()
    " When nodes are deleted by editing Body, snLn can get > last Tree lnum,
    " voom.updateTree() will change snLn to last line lnum
    if snLn_ != s:voom_bodies[body].snLn
        normal! Gzv
    endif
endfunc


func! Voom_TreeBufUnload() "{{{2
" Tree's BufUnload au. Wipe out Tree and cleanup.
    let tree = expand("<abuf>")
    if !exists("s:voom_trees") || !has_key(s:voom_trees, tree)
        echoerr "VOoM: internal error"
        return
    endif
    let body = s:voom_trees[tree]
    "echom bufexists(tree) --always 0
    exe 'noautocmd bwipeout '.tree
    call Voom_UnVoom(body,tree)
endfunc


func! Voom_TreeFoldexpr(lnum) "{{{2
    let ind = stridx(getline(a:lnum),'|') / 2
    let indn = stridx(getline(a:lnum+1),'|') / 2
    return indn>ind ? '>'.ind : ind-1
    "return indn>ind ? '>'.ind : indn<ind ? '<'.indn : ind-1
    "return indn==ind ? ind-1 : indn>ind ? '>'.ind : '<'.indn
endfunc


func! Voom_TreeSyntax() "{{{2
" Default Tree buffer syntax highlighting.
    " first line
    syn match Title /\%1l.*/
    " line comment chars: "  #  //  /*  %  <!--
    syn match Comment @|\zs\%("\|#\|//\|/\*\|%\|<!--\).*@ contains=Todo
    " keywords
    syn match Todo /\%(TODO\|Todo\)/
    " selected node
    "syn match Pmenu /^=.\{-}|\zs.*/
    "syn match Pmenu /^=/
endfunc


func! Voom_TreeMap() "{{{2
" Mappings and commands local to a Tree buffer.
    let cpo_ = &cpo | set cpo&vim
    " Use noremap to disable keys.
    " Use nnoremap and vnoremap to map keys to Voom functions, don't use noremap.
    " Disable common text change commands. {{{
    noremap <buffer><silent> i <Nop>
    noremap <buffer><silent> I <Nop>
    noremap <buffer><silent> a <Nop>
    noremap <buffer><silent> A <Nop>
    noremap <buffer><silent> o <Nop>
    noremap <buffer><silent> O <Nop>
    noremap <buffer><silent> s <Nop>
    noremap <buffer><silent> S <Nop>
    noremap <buffer><silent> r <Nop>
    noremap <buffer><silent> R <Nop>
    noremap <buffer><silent> x <Nop>
    noremap <buffer><silent> X <Nop>
    noremap <buffer><silent> d <Nop>
    noremap <buffer><silent> D <Nop>
    noremap <buffer><silent> J <Nop>
    noremap <buffer><silent> c <Nop>
    noremap <buffer><silent> p <Nop>
    noremap <buffer><silent> P <Nop>
    noremap <buffer><silent> . <Nop>
    " }}}

    " Disable undo (also case conversion). {{{
    noremap <buffer><silent> u <Nop>
    noremap <buffer><silent> U <Nop>
    " this is Move Right in Leo
    noremap <buffer><silent> <C-r> <Nop>
    " }}}

    " Disable creation/deletion of folds. {{{
    noremap <buffer><silent> zf <Nop>
    noremap <buffer><silent> zF <Nop>
    noremap <buffer><silent> zd <Nop>
    noremap <buffer><silent> zD <Nop>
    noremap <buffer><silent> zE <Nop>
    " }}}

    " Edit headline. {{{
    nnoremap <buffer><silent> i :<C-u>call Voom_OopEdit()<CR>
    nnoremap <buffer><silent> I :<C-u>call Voom_OopEdit()<CR>
    nnoremap <buffer><silent> a :<C-u>call Voom_OopEdit()<CR>
    nnoremap <buffer><silent> A :<C-u>call Voom_OopEdit()<CR>
    " }}}

    " Node selection and navigation. {{{

    exe "nnoremap <buffer><silent> ".g:voom_return_key.     " :<C-u>call Voom_TreeSelect(line('.'), '')<CR>"
    exe "vnoremap <buffer><silent> ".g:voom_return_key." <Esc>:<C-u>call Voom_TreeSelect(line('.'), '')<CR>"
    "exe "vnoremap <buffer><silent> ".g:voom_return_key." <Nop>"
    exe "nnoremap <buffer><silent> ".g:voom_tab_key.        " :<C-u>call Voom_ToTreeOrBodyWin()<CR>"
    exe "vnoremap <buffer><silent> ".g:voom_tab_key.   " <Esc>:<C-u>call Voom_ToTreeOrBodyWin()<CR>"
    "exe "vnoremap <buffer><silent> ".g:voom_tab_key.   " <Nop>"

    " Put cursor on currently selected node.
    nnoremap <buffer><silent> = :<C-u>call Voom_TreeToSelected()<CR>
    " Put cursor on node marked with '=', if any.
    nnoremap <buffer><silent> + :<C-u>call Voom_TreeToStartupNode()<CR>

    " Do not map <LeftMouse>. Not triggered on first click in the buffer.
    " Triggered on first click in another buffer. Vim doesn't know what buffer
    " it is until after the click.
    " Left mouse release. Also triggered when resizing window with the mouse.
    nnoremap <buffer><silent> <LeftRelease> <LeftRelease>:<C-u>call Voom_TreeMouseClick()<CR>
    inoremap <buffer><silent> <LeftRelease> <LeftRelease><Esc>
    " Disable Left mouse double click to avoid entering Visual mode.
    nnoremap <buffer><silent> <2-LeftMouse> <Nop>

    nnoremap <buffer><silent> <Space> :<C-u>call Voom_TreeToggleFold()<CR>
    "vnoremap <buffer><silent> <Space> :<C-u>call Voom_TreeToggleFold()<CR>

    nnoremap <buffer><silent> <Down> <Down>:<C-u>call Voom_TreeSelect(line('.'), 'tree')<CR>
    nnoremap <buffer><silent>   <Up>   <Up>:<C-u>call Voom_TreeSelect(line('.'), 'tree')<CR>

    nnoremap <buffer><silent> <Left>  :<C-u>call Voom_TreeLeft()<CR>
    nnoremap <buffer><silent> <Right> :<C-u>call Voom_TreeRight()<CR>

    nnoremap <buffer><silent> x :<C-u>call Voom_TreeNextMark(0)<CR>
    nnoremap <buffer><silent> X :<C-u>call Voom_TreeNextMark(1)<CR>
    " }}}

    " Outline operations. {{{
    " Can't use Ctrl as in Leo: <C-i> is Tab; <C-u>, <C-d> are page up/down.

    " insert new node
    nnoremap <buffer><silent> <LocalLeader>i  :<C-u>call Voom_OopInsert('')<CR>
    nnoremap <buffer><silent> <LocalLeader>I  :<C-u>call Voom_OopInsert('as_child')<CR>

    " move
    nnoremap <buffer><silent> <LocalLeader>u  :<C-u>call Voom_Oop('up', 'n')<CR>
    nnoremap <buffer><silent>         <C-Up>  :<C-u>call Voom_Oop('up', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>u  :<C-u>call Voom_Oop('up', 'v')<CR>
    vnoremap <buffer><silent>         <C-Up>  :<C-u>call Voom_Oop('up', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>d  :<C-u>call Voom_Oop('down', 'n')<CR>
    nnoremap <buffer><silent>       <C-Down>  :<C-u>call Voom_Oop('down', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>d  :<C-u>call Voom_Oop('down', 'v')<CR>
    vnoremap <buffer><silent>       <C-Down>  :<C-u>call Voom_Oop('down', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>l  :<C-u>call Voom_Oop('left', 'n')<CR>
    nnoremap <buffer><silent>       <C-Left>  :<C-u>call Voom_Oop('left', 'n')<CR>
    nnoremap <buffer><silent>             <<  :<C-u>call Voom_Oop('left', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>l  :<C-u>call Voom_Oop('left', 'v')<CR>
    vnoremap <buffer><silent>       <C-Left>  :<C-u>call Voom_Oop('left', 'v')<CR>
    vnoremap <buffer><silent>             <<  :<C-u>call Voom_Oop('left', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>r  :<C-u>call Voom_Oop('right', 'n')<CR>
    nnoremap <buffer><silent>      <C-Right>  :<C-u>call Voom_Oop('right', 'n')<CR>
    nnoremap <buffer><silent>             >>  :<C-u>call Voom_Oop('right', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>r  :<C-u>call Voom_Oop('right', 'v')<CR>
    vnoremap <buffer><silent>      <C-Right>  :<C-u>call Voom_Oop('right', 'v')<CR>
    vnoremap <buffer><silent>             >>  :<C-u>call Voom_Oop('right', 'v')<CR>

    " cut/copy/paste
    nnoremap <buffer><silent>  dd  :<C-u>call Voom_Oop('cut', 'n')<CR>
    vnoremap <buffer><silent>  dd  :<C-u>call Voom_Oop('cut', 'v')<CR>

    nnoremap <buffer><silent>  yy  :<C-u>call Voom_Oop('copy', 'n')<CR>
    vnoremap <buffer><silent>  yy  :<C-u>call Voom_Oop('copy', 'v')<CR>

    nnoremap <buffer><silent>  pp  :<C-u>call Voom_OopPaste()<CR>

    " mark/unmark
    nnoremap <buffer><silent> <LocalLeader>m   :<C-u>call Voom_OopMark('mark', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>m   :<C-u>call Voom_OopMark('mark', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>M   :<C-u>call Voom_OopMark('unmark', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>M   :<C-u>call Voom_OopMark('unmark', 'v')<CR>

    " mark node as selected node
    nnoremap <buffer><silent> <LocalLeader>=   :<C-u>call Voom_OopMarkSelected()<CR>
    " }}}

    " Save/Restore Tree folding. {{{
    nnoremap <buffer><silent> <LocalLeader>fs  :<C-u>call Voom_OopFolding(line('.'),line('.'), 'save')<CR>
    nnoremap <buffer><silent> <LocalLeader>fr  :<C-u>call Voom_OopFolding(line('.'),line('.'), 'restore')<CR>
    nnoremap <buffer><silent> <LocalLeader>fas :<C-u>call Voom_OopFolding(1,line('$'), 'save')<CR>
    nnoremap <buffer><silent> <LocalLeader>far :<C-u>call Voom_OopFolding(1,line('$'), 'restore')<CR>
    " }}}

    " Various commands. {{{
    "nnoremap <buffer><silent> <F1> :<C-u>call Voom_Help()<CR>
    nnoremap <buffer><silent> <LocalLeader>e :<C-u>call Voom_Exec('')<CR>
    " }}}

    let &cpo = cpo_
endfunc


"---Outline Navigation---{{{2
" To select node from Tree, call Voom_TreeSelect().
" Must return after calling Voom_TreeSelect() in case Body checks fail.

func! Voom_TreeSelect(lnum, focus) "{{{3
" Select node corresponding to Tree line lnum.
" Show correspoding node in Body.
" Leave cursor in Body if cursor is already in selected node and focus!='tree'.
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif

    let snLn = s:voom_bodies[body].snLn

    let lz_ = &lz | set lz
    call Voom_TreeZV()
    call Voom_TreePlaceCursor()

    " compute l:nodeStart and l:nodeEnd Body lnums
    " set VOOM.snLns before going to Body in case outline update is forced
    python voom.voom_TreeSelect()

    """" Mark new line with =. Remove old = mark.
    if a:lnum!=snLn
        setl ma | let ul_ = &ul | setl ul=-1
        keepj call setline(a:lnum, '='.getline(a:lnum)[1:])
        keepj call setline(snLn, ' '.getline(snLn)[1:])
        setl noma | let &ul = ul_
        let s:voom_bodies[body].snLn = a:lnum
    endif

    """" Go to Body, show current node, and either come back or stay in Body.
    if Voom_ToBody(body, 'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    " Show Body node corresponding to current line in Tree.
    let bodyLnr = line('.')
    let new_node_selected = (bodyLnr < l:nodeStart) || (bodyLnr > l:nodeEnd)
    if new_node_selected
        exe 'normal! '.nodeStart.'G'
        " zt is affected by 'scrolloff'.
        if &fdm ==# 'marker'
            normal! zMzvzt
        else
            normal! zvzt
        endif
    endif

    """" Go back to Tree after showing a different node in Body.
    """" Otherwise, that is if Body's node was same as Tree's, stay in Body.
    if (new_node_selected==1 || a:focus=='tree') && a:focus!='body'
        let wnr_ = winnr('#')
        if winbufnr(wnr_)==tree
            exe 'noautocmd '.wnr_.'wincmd w'
        else
            exe 'noautocmd '.bufwinnr(tree).'wincmd w'
        endif
    endif

    let &lz=lz_
endfunc


func! Voom_TreePlaceCursor() "{{{3
" Place cursor before the headline.
    let col = stridx(getline('.'),'|') + 1
    if col==0
        let col = 1
    endif
    call cursor('.', col)
endfunc


func! Voom_TreeZV() "{{{3
" Make current line visible.
" Like zv, but when current line starts a fold, do not automatically open that fold.
    let lnum = line('.')
    let fc = foldclosed(lnum)
    while fc < lnum && fc > 0
        normal! zo
        let fc = foldclosed(lnum)
    endwhile
endfunc


func! Voom_TreeToLine(lnum) "{{{3
" Put cursor on line lnum, e.g., snLn.
    if (line('w0') < a:lnum) && (a:lnum > 'w$')
        let offscreen = 0
    else
        let offscreen = 1
    endif
    exe 'normal! ' . a:lnum . 'G'
    call Voom_TreeZV()
    call Voom_TreePlaceCursor()
    if offscreen==1
        normal! zz
    endif
endfunc


func! Voom_TreeToSelected() "{{{3
" Put cursor on selected node, that is on SnLn line.
    let lnum = s:voom_bodies[s:voom_trees[bufnr('')]].snLn
    call Voom_TreeToLine(lnum)
endfunc


func! Voom_TreeToStartupNode() "{{{3
" Put cursor on startup node, if any: node marked with '=' in Body headline.
" Warn if there are several such nodes.
    let body = s:voom_trees[bufnr('')]
    " this creates l:lnums
    python voom.voom_TreeToStartupNode()
    if len(l:lnums)==0
        call Voom_WarningMsg("VOoM: no nodes marked with '='")
        return
    endif
    call Voom_TreeToLine(l:lnums[-1])
    if len(l:lnums)>1
        call Voom_WarningMsg("VOoM: multiple nodes marked with '=': ".join(l:lnums, ', '))
    endif
endfunc


func! Voom_TreeToggleFold() "{{{3
" Toggle fold at cursor: expand/contract node.
    let lnum=line('.')
    let ln_status = Voom_FoldStatus(lnum)

    if ln_status=='folded'
        normal! zo
    elseif ln_status=='notfolded'
        if stridx(getline(lnum),'|') < stridx(getline(lnum+1),'|')
            normal! zc
        endif
    elseif ln_status=='hidden'
        call Voom_TreeZV()
    endif
endfunc


func! Voom_TreeMouseClick() "{{{3
" Select node. Toggle fold if click is outside of headline text.
    if !has_key(s:voom_trees, bufnr(''))
        call Voom_ErrorMsg('VOoM: <LeftRelease> in wrong buffer')
        return
    endif
    if virtcol('.')+1 >= virtcol('$') || col('.')-1 < stridx(getline('.'),'|')
        call Voom_TreeToggleFold()
    endif
    call Voom_TreeSelect(line('.'), 'tree')
endfunc


func! Voom_TreeLeft() "{{{3
" Move to parent after first contracting node.
    let lnum = line('.')

    " line is hidden in a closed fold: make it visible
    let fc = foldclosed(lnum)
    if fc < lnum && fc > 0
        while fc < lnum && fc > 0
            normal! zo
            let fc = foldclosed(lnum)
        endwhile
        normal! zz
        call cursor('.', stridx(getline('.'),'|') + 1)
        call Voom_TreeSelect(line('.'), 'tree')
        return
    endif

    let ind = stridx(getline(lnum),'|')
    if ind < 0 | return | endif
    let indn = stridx(getline(lnum+1),'|')

    " line is in an opened fold and next line has bigger indent: close fold
    if fc < 0 && (ind < indn)
        normal! zc
        call Voom_TreeSelect(line('.'), 'tree')
        return
    endif

    " root node: do not move
    if ind==2
        call cursor('.', stridx(getline('.'),'|') + 1)
        call Voom_TreeSelect(line('.'), 'tree')
        return
    endif

    " move to parent
    let indp = ind
    while indp>=ind
        normal! k
        let indp = stridx(getline('.'),'|')
    endwhile
    "normal! zz
    call cursor('.', stridx(getline('.'),'|') + 1)
    call Voom_TreeSelect(line('.'), 'tree')
endfunc


func! Voom_TreeRight() "{{{3
" Move to first child.
    let lnum = line('.')
    " line is hidden in a closed fold: make it visible
    let fc = foldclosed(lnum)
    if fc < lnum && fc > 0
        while fc < lnum && fc > 0
            normal! zo
            let fc = foldclosed(lnum)
        endwhile
        normal! zz
        call cursor('.', stridx(getline('.'),'|') + 1)
        call Voom_TreeSelect(line('.'), 'tree')
        return
    endif

    " line is in a closed fold
    if fc==lnum
        normal! zoj
        call cursor('.', stridx(getline('.'),'|') + 1)
    " line is not in a closed fold and next line has bigger indent
    elseif stridx(getline(lnum),'|') < stridx(getline(lnum+1),'|')
        normal! j
        call cursor('.', stridx(getline('.'),'|') + 1)
    endif
    call Voom_TreeSelect(line('.'), 'tree')
endfunc


func! Voom_TreeNextMark(back) "{{{3
" Go to next or previous marked node.
    if a:back==1
        normal! 0
        let found = search('\C\v^.x', 'bw')
    else
        let found = search('\C\v^.x', 'w')
    endif

    if found==0
        call Voom_WarningMsg("VOoM: there are no marked nodes")
    else
        call Voom_TreeZV()
        call cursor('.', stridx(getline('.'),'|') + 1)
        call Voom_TreeSelect(line('.'), 'tree')
    endif
endfunc


"---Outline Operations---{{{2

func! Voom_OopEdit() "{{{3
" Edit headline text: move into Body, put cursor on headline.
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    let lnum = line('.')
    if lnum==1 | return | endif
    if Voom_BufEditable(body) < 0 | return | endif

    python vim.command("let l:bLnr=%s" %VOOM.bnodes[int(vim.eval('l:body'))][int(vim.eval('l:lnum'))-1])

    let lz_ = &lz | set lz
    if Voom_ToBody(body,'') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    exe 'normal! ' . l:bLnr.'G0'
    normal! zv
    " put cursor on the first word char before the foldmarker
    let foldmarker = split(&foldmarker, ',')[0]
    let markerIdx = match(getline('.'), '\V\C'.foldmarker)
    let wordCharIdx = match(getline('.'), '\<')
    if wordCharIdx < markerIdx
        call cursor(line('.'), wordCharIdx+1)
    endif
    let &lz=lz_
endfunc


func! Voom_OopInsert(as_child) "{{{3
" Insert new node.
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if Voom_BufEditable(body) < 0 | return | endif
    let ln = line('.')
    let ln_status = Voom_FoldStatus(ln)
    if ln_status=='hidden'
        call Voom_ErrorMsg("VOoM: current line is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
    call Voom_OopFromBody(body,tree,-1,'noa')

    setl ma
    if a:as_child=='as_child'
        keepj python voom.voom_OopInsert(as_child=True)
    else
        keepj python voom.voom_OopInsert(as_child=False)
    endif
    setl noma

    let snLn = s:voom_bodies[body].snLn
    exe "normal! ".snLn."G"
    call Voom_TreePlaceCursor()
    call Voom_TreeZV()

    if Voom_ToBody(body,'') < 0 | let &lz=lz_ | return | endif
    exe "normal! ".bLnum."G"
    normal! zvzz3l
    let &lz=lz_
endfunc


func! Voom_OopPaste() "{{{3
" Paste nodes in the clipboard.
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if Voom_BufEditable(body) < 0 | return | endif
    let ln = line('.')
    let ln_status = Voom_FoldStatus(ln)
    if ln_status=='hidden'
        call Voom_ErrorMsg("VOoM: current line is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    " default bnlShow -1 means pasting not possible
    let l:blnShow = -1

    call setbufvar(tree, '&ma', 1)
    keepj python voom.voom_OopPaste()
    call setbufvar(tree, '&ma', 0)

    " no pasting was done or Python code failed
    if l:blnShow < 0 | let &lz=lz_ | return | endif

    let s:voom_bodies[body].snLn = l:ln1
    if l:ln1==l:ln2
        call Voom_OopShowTree(l:ln1, l:ln2, 'n')
    else
        call Voom_OopShowTree(l:ln1, l:ln2, 'v')
    endif
    let &lz=lz_

    if g:voom_verify_oop==1
        python voom.verifyTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
    endif
endfunc


func! Voom_OopMark(op, mode) "{{{3
" Mark or unmark current node or all nodes in selection

    " Checks and init vars. {{{
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if Voom_BufEditable(body) < 0 | return | endif
    let ln = line('.')
    let ln_status = Voom_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        call Voom_ErrorMsg("VOoM: current line is hidden in fold")
        return
    endif
    " normal mode: use current line
    if a:mode=='n'
        let ln1 = ln
        let ln2 = ln
    " visual mode: use range
    elseif a:mode=='v'
        let ln1 = line("'<")
        let ln2 = line("'>")
    endif
    " don't touch first line
    if ln1==1 && ln2==ln1
        return
    elseif ln1==1 && ln2>1
        let ln1=2
    endif
    " }}}

    let lz_ = &lz | set lz
    let fdm_t = &fdm
    if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    let fdm_b=&fdm | setl fdm=manual
    call setbufvar(tree, '&fdm', 'manual')
    call setbufvar(tree, '&ma', 1)
    if a:op=='mark'
        keepj python voom.voom_OopMark()
    elseif a:op=='unmark'
        keepj python voom.voom_OopUnmark()
    endif
    call setbufvar(tree, '&ma', 0)
    let &fdm=fdm_b

    call Voom_OopFromBody(body,tree,0,'noa')
    let &fdm=fdm_t
    let &lz=lz_

    if g:voom_verify_oop==1
        python voom.verifyTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
    endif
endfunc


func! Voom_OopMarkSelected() "{{{3
" Mark or unmark current node or all nodes in selection
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if Voom_BufEditable(body) < 0 | return | endif
    let ln = line('.')
    let ln_status = Voom_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        call Voom_ErrorMsg("VOoM: current line is hidden in fold")
        return
    endif
    if ln==1
        return
    endif

    let lz_ = &lz | set lz
    if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    call setbufvar(tree, '&ma', 1)
    keepj python voom.voom_OopMarkSelected()
    call setbufvar(tree, '&ma', 0)

    call Voom_OopFromBody(body,tree,0,'noa')
    let &lz=lz_

    if g:voom_verify_oop==1
        python voom.verifyTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
    endif
endfunc


func! Voom_Oop(op, mode) "{{{3=
" Outline operations that can be perfomed on current node or on nodes in visual
" selection. All apply to branches, not to single nodes.

    " Checks and init vars. {{{
    let tree = bufnr('')
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if Voom_BufEditable(body) < 0 && a:op!='copy' | return | endif
    let ln = line('.')
    let ln_status = Voom_FoldStatus(ln)
    if ln_status=='hidden'
        call Voom_ErrorMsg("VOoM: current line is hidden in fold")
        return
    endif
    " normal mode: use current line
    if a:mode=='n'
        let [ln1,ln2] = [ln,ln]
    " visual mode: use range
    elseif a:mode=='v'
        let [ln1,ln2] = [line("'<"),line("'>")]
        " before op: move cursor to ln1 or ln2
    endif
    " don't touch first line
    if ln1==1 | return | endif
    " set ln2 to last node in the last sibling branch in selection
    " check validity of selection
    python vim.command('let ln2=%s' %voom.voom_OopSelEnd())
    if ln2==0
        call Voom_ErrorMsg("VOoM: invalid Tree selection")
        return
    endif
    " }}}

    " default bnlShow -1 means no changes were made
    let l:blnShow = -1
    let lz_ = &lz | set lz

    if     a:op=='up' " {{{
        if ln1<3 | let &lz=lz_ | return | endif
        if a:mode=='v'
            " must be on first line of selection
            exe "normal! ".ln1."G"
        endif
        " ln before which to insert, also, new snLn
        normal! k
        let lnUp1 = line('.')
        " top node of a tree after which to insert
        normal! k
        let lnUp2 = line('.')

        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj python voom.voom_OopUp()
        call setbufvar(tree, '&ma', 0)
        " Python code failed
        if l:blnShow < 0 | let &lz=lz_ | return | endif

        let s:voom_bodies[body].snLn = lnUp1
        let lnEnd = lnUp1+ln2-ln1
        call Voom_OopShowTree(lnUp1, lnEnd, a:mode)
        " }}}

    elseif a:op=='down' " {{{
        if ln2==line('$') | let &lz=lz_ | return | endif
        " must be on the last node of current tree or last tree in selection
        exe "normal! ".ln2."G"
        " line after which to insert
        normal! j
        let lnDn1 = line('.') " should be ln2+1
        let lnDn1_status = Voom_FoldStatus(lnDn1)

        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj python voom.voom_OopDown()
        call setbufvar(tree, '&ma', 0)
        " Python code failed
        if l:blnShow < 0 | let &lz=lz_ | return | endif

        let s:voom_bodies[body].snLn = l:snLn
        let lnEnd = snLn+ln2-ln1
        call Voom_OopShowTree(snLn, lnEnd, a:mode)
        " }}}

    elseif a:op=='right' " {{{
        if ln1==2 | let &lz=lz_ | return | endif

        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        let fdm_b=&fdm | setl fdm=manual
        call setbufvar(tree, '&ma', 1)
        keepj python voom.voom_OopRight()
        call setbufvar(tree, '&ma', 0)

        " can't move right or Python code failed
        if l:blnShow < 0
            call setbufvar(body, '&fdm', fdm_b)
            let &lz=lz_
            return
        endif

        let s:voom_bodies[body].snLn = ln1
        call Voom_OopShowTree(ln1, ln2, a:mode)
        " }}}

    elseif a:op=='left' " {{{
        if ln1==2 | let &lz=lz_ | return | endif

        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        let fdm_b=&fdm | setl fdm=manual
        call setbufvar(tree, '&ma', 1)
        keepj python voom.voom_OopLeft()
        call setbufvar(tree, '&ma', 0)

        " can't move right or Python code failed
        if l:blnShow < 0
            call setbufvar(body, '&fdm', fdm_b)
            let &lz=lz_
            return
        endif

        let s:voom_bodies[body].snLn = ln1
        call Voom_OopShowTree(ln1, ln2, a:mode)
        " }}}

    elseif a:op=='copy' " {{{
        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        keepj python voom.voom_OopCopy()

        call Voom_OopFromBody(body,tree,-1,'noa')
        "}}}

    elseif a:op=='cut' " {{{
        if a:mode=='v'
            " must be on first line of selection
            exe "normal! ".ln1."G"
        endif
        " new snLn
        normal! k
        let lnUp1 = line('.')

        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj python voom.voom_OopCut()
        call setbufvar(tree, '&ma', 0)

        let s:voom_bodies[body].snLn = lnUp1
        " }}}
    endif

    let &lz=lz_

    if g:voom_verify_oop==1 && a:op!='copy'
        python voom.verifyTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
    endif
endfunc


func! Voom_OopFolding(ln1, ln2, action) "{{{3
" Deal with Tree folding in range ln1-ln2 according to action:
" save, restore, cleanup. Range is ignored if 'cleanup'.
" Since potentially large lists are involved, folds are manipulated in Python.

    " must be in Tree buffer
    let tree = bufnr('')
    if !has_key(s:voom_trees, tree)
        call Voom_ErrorMsg("VOoM: this command must be executed in Tree buffer")
        return
    endif
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if a:action!=#'restore' && Voom_BufEditable(body) < 0
        return
    endif

    " can't deal with folds of node hidden in a fold
    if a:action!=#'cleanup' && Voom_FoldStatus(a:ln1)=='hidden'
        call Voom_ErrorMsg("VOoM: current line is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz

    " go to Body, check ticks, go back
    if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif
    call Voom_OopFromBody(body,tree,-1,'noa')
    " make sure we are back
    if bufnr('')!=tree
        echoerr "VOoM: internal error" | let &lz=lz_ | return
    endif

    """ diddle with folds
    let winsave_dict = winsaveview()
    python voom.voom_OopFolding(vim.eval('a:action'))
    call winrestview(winsave_dict)

    if a:action!=#'restore'
        " go to Body, set ticks, go back
        if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
        call Voom_OopFromBody(body,tree,0,'noa')
    endif

    let &lz=lz_
endfunc

func! Voom_OopSort(qargs) "{{{3
" Sort siblings of the currrent node according to options in qargs.
" If one of the options is 'deep' -- also sort siblings in all subnodes.
" Options are dealt with in the Python code.

    " must be in Tree buffer
    let tree = bufnr('')
    if !has_key(s:voom_trees, tree)
        call Voom_ErrorMsg("VOoM (VoomSort): this command must be executed in Tree buffer")
        return
    endif
    let body = s:voom_trees[tree]
    if Voom_BufLoaded(body) < 0 | return | endif
    if Voom_BufEditable(body) < 0 | return | endif
    let ln = line('.')
    let ln_status = Voom_FoldStatus(ln)
    if ln_status=='hidden'
        call Voom_ErrorMsg("VOoM (VoomSort): current line is hidden in fold")
        return
    endif

    let lz_ = &lz | set lz
    """ go to Body window
    if Voom_ToBody(body,'noa') < 0 | let &lz=lz_ | return | endif
    if Voom_BodyCheckTicks(body) < 0 | let &lz=lz_ | return | endif

    " default l:bnlShow -1 means no changes were made
    let l:blnShow = -1
    " Modify Body buffer. Tree buffer and outline data are not adjusted.
    keepj python voom.voom_OopSort()
    " IMPORTANT: we rely on BufEnter au to update outline
    call Voom_OopFromBody(body,tree,l:blnShow,'')
    if l:blnShow > 0
        call Voom_OopShowTree(l:ln1, l:ln2, 'n')
    endif
    let &lz=lz_
endfunc


func! Voom_OopFromBody(body, tree, blnShow, noa) "{{{3
" Move from Body to Tree after an outline operation.
" If a:noa=='noa':
" Set ticks. Show node (or just line) blnShow.
" Go back to Tree, do not execute autocommands.
" Special blnShow values:
"   -1 --don't set ticks and don't show node.
"    0 --set ticks, but don't show node.
"
" If a:noa!='noa': as above, but don't set ticks and don't disable
" autocommands. This assumes Tree BufEnter au will update outline.

    if bufnr('')!=a:body
        echoerr 'VOoM: internal error'
        return
    endif

    let body_tick = b:changedtick

    if a:blnShow >= 0 && a:noa==#'noa'
        " adjust changedtick to suppress TreeUpdate
        let s:voom_bodies[a:body].tick_ = b:changedtick
        let s:voom_bodies[a:body].tick  = b:changedtick
    endif

    if a:blnShow > 0
        " show fold at blnShow
        exe 'normal! '.a:blnShow.'G'
        if &fdm==#'marker'
            normal! zMzvzt
        else
            normal! zvzt
        endif
    endif

    " go back to Tree window, which should be previous window
    let m = a:noa==#'noa' ? 'noautocmd ' : ''
    let wnr_ = winnr('#')
    if winbufnr(wnr_)==a:tree
        exe m.wnr_.'wincmd w'
    else
        exe m.bufwinnr(a:tree).'wincmd w'
    endif
    if bufnr('')!=a:tree
        throw 'This is not Tree!'
    endif
    if s:voom_bodies[a:body].tick_ != body_tick
        echoerr 'VOoM: wrong ticks! Will force outline update.'
        let s:voom_bodies[a:body].tick = body_tick
        call Voom_TreeBufEnter()
    endif
endfunc


func! Voom_OopShowTree(ln1, ln2, mode) " {{{3
" Adjust Tree view after an outline operation.
" ln1 and ln2 are first and last line of the range.
"
" After outline operation Tree folds in the affected range are usually
" completely expanded. To be consistent: close all folds in the range
" (select range, zC, show first line).

    " zv ensures ln1 node is expanded before next GV
    exe 'normal! '.a:ln1.'Gzv'
    " select range and close all folds in range
    exe 'normal! '.a:ln2.'GV'.a:ln1.'G'
    try
        normal! zC
    " E490: No fold found
    catch /^Vim\%((\a\+)\)\=:E490/
    endtry

    " show first node
    call Voom_TreeZV()
    call Voom_TreePlaceCursor()

    " restore visual mode selection
    if a:mode=='v'
        normal! gv
    endif
endfunc


"---BODY BUFFERS------------------------------{{{1

func! Voom_BodyConfig() "{{{2
" Configure current buffer as a Body buffer.
    augroup VoomBody
        au! * <buffer>
        au BufLeave   <buffer> call Voom_BodyBufLeave()
        au BufEnter   <buffer> call Voom_BodyBufEnter()
    augroup END

    " redundant: will be set on BufLeave
    let s:voom_bodies[bufnr('')].tick = b:changedtick

    call Voom_BodyMap()
endfunc


func! Voom_BodyBufLeave() "{{{2
" Body BufLeave au.
" getbufvar() doesn't work with b:changedtick, thus the need for this au
    let s:voom_bodies[bufnr('')].tick = b:changedtick
endfunc


func! Voom_BodyBufEnter() "{{{2
" Body BufEnter au. Restore buffer-local mappings lost after :bd.
    if !hasmapto('Voom_ToTreeOrBodyWin','n')
        call Voom_BodyMap()
    endif
endfunc


func! Voom_BodyMap() "{{{2
" Create Body mappiings.
    let cpo_ = &cpo | set cpo&vim
    exe "nnoremap <buffer><silent> ".g:voom_return_key." :<C-u>call Voom_BodySelect()<CR>"
    exe "nnoremap <buffer><silent> ".g:voom_tab_key.   " :<C-u>call Voom_ToTreeOrBodyWin()<CR>"
    let &cpo = cpo_
endfunc


func! Voom_BodyUnMap() "{{{2
" Remove Body local mappings. Must be called from Body.
    let cpo_ = &cpo | set cpo&vim
    exe "nunmap <buffer> ".g:voom_return_key
    exe "nunmap <buffer> ".g:voom_tab_key
    let &cpo = cpo_
endfunc


func! Voom_BodySelect() "{{{2
" Select current Body node. Show corresponding line in the Tree.
" Stay in the Tree if the node is already selected.
    let body = bufnr('')
    " Tree has been wiped out.
    if !has_key(s:voom_bodies, body)
        call Voom_BodyUnMap()
        return
    endif

    let wnr_ = winnr()
    let tree = s:voom_bodies[body].tree
    let blnr = line('.')
    let s:voom_bodies[body].blnr = blnr

    let bchangedtick = b:changedtick
    " Go to Tree. Outline will be updated on BufEnter.
    if Voom_ToTree(tree) < 0 | return | endif
    " Check for ticks.
    if s:voom_bodies[body].tick_!=bchangedtick
        exe bufwinnr(body).'wincmd w'
        call Voom_BodyCheckTicks(body)
        return
    endif

    " updateTree() sets = mark and may change snLn to a wrong value if outline was modified from Body.
    let snLn_ = s:voom_bodies[body].snLn
    " Compute new and correct snLn with updated outline.
    python voom.computeSnLn(int(vim.eval('l:body')), int(vim.eval('l:blnr')))
    let snLn = s:voom_bodies[body].snLn

    call Voom_TreeToLine(snLn)
    " Node has not changed. Stay in Tree.
    if snLn==snLn_
        return
    endif

    " Node has changed. Draw marks. Go back to Body
    setl ma | let ul_ = &ul | setl ul=-1
    keepj call setline(snLn_, ' '.getline(snLn_)[1:])
    keepj call setline(snLn, '='.getline(snLn)[1:])
    setl noma | let &ul = ul_

    let wnr_ = winnr('#')
    if winbufnr(wnr_)==body
        exe 'noautocmd '.wnr_.'wincmd w'
    else
        exe 'noautocmd '.bufwinnr(body).'wincmd w'
    endif
endfunc


func! Voom_BodyCheckTicks(body) "{{{2
" Current buffer is Body body. Check ticks assuming that outline is up to date,
" as after going to Body from Tree.
" note: 'abort' argument is not needed and would be counterproductive
    if bufnr('')!=a:body
        echoerr 'VOoM: wrong buffer'
        return -1
    endif
    " Wrong ticks, probably after :bun or :bd. Force outline update.
    if s:voom_bodies[a:body].tick_!=b:changedtick
        let tree = s:voom_bodies[a:body].tree
        if !exists("s:voom_trees") || !has_key(s:voom_trees, tree)
            echoerr "VOoM: internal error"
            return -1
        endif
        call Voom_BodyUpdateTree()
        call Voom_ErrorMsg('VOoM: wrong ticks for Body buffer '.a:body.'. Updated outline...')
        return -1
    endif
endfunc


func! Voom_BodyUpdateTree() "{{{2
" Current buffer is Body. Update outline and Tree.
    let body = bufnr('')
    if !has_key(s:voom_bodies, body)
        call Voom_ErrorMsg('VOoM: current buffer is not Body')
        return -1
    endif

    let tree = s:voom_bodies[body].tree

    " paranoia
    if !bufloaded(tree)
        call Voom_UnVoom(body,tree)
        echoerr "VOoM: Tree buffer" tree "is not loaded or does not exist. Cleanup has been performed."
        return -1
    endif

    """" update is not needed
    if s:voom_bodies[body].tick_==b:changedtick
        return
    endif

    """" do update
    call setbufvar(tree, '&ma', 1)
    let ul_=&ul | setl ul=-1
    try
        keepj python voom.updateTree(int(vim.eval('l:body')), int(vim.eval('l:tree')))
        let s:voom_bodies[body].tick_ = b:changedtick
        let s:voom_bodies[body].tick  = b:changedtick
    finally
        " Why: &ul is global, but this causes 'undo list corrupt' error
        "let &ul=ul_
        call setbufvar(tree, '&ul', ul_)
        call setbufvar(tree, '&ma', 0)
    endtry
endfunc


"---Tree or Body------------------------------{{{1

func! Voom_EchoUNL() "{{{2
" Display UNL (Uniformed Node Locator) of current node.
" Copy UNL to register 'n'.
" This can be called from any buffer.
    let bnr = bufnr('')
    let lnum = line('.')

    if has_key(s:voom_trees, bnr)
        let body = s:voom_trees[bnr]
        if Voom_BufLoaded(body) < 0 | return | endif
        let tree = bnr
        let buftype = 'tree'
    elseif has_key(s:voom_bodies, bnr)
        let body = bnr
        let tree = s:voom_bodies[bnr].tree
        let buftype = 'body'
        " update outline
        if Voom_BodyUpdateTree() < 0 | return | endif
    else
        call Voom_ErrorMsg("VOoM (Voomunl): current buffer is not a VOoM buffer")
        return
    endif

    python voom.voom_EchoUNL()
endfunc


func! Voom_Grep(input) "{{{2
" Seach Body for pattern(s). Show list of UNLs of nodes with matches.
" Input can have several patterns separated by boolean 'AND' and 'NOT'.
" Stop each search after 10,000 matches.
" Set search register to the first AND pattern.

    """ Process input first in case we are in Tree and want word under cursor.
    if a:input==''
        let input = expand('<cword>')
        let input = substitute(input, '\s\+$', '', '')
        if input=='' | return | endif
        let [pattsAND, pattsNOT] = [['\<'.input.'\>'], []]
    else
        let input = substitute(a:input, '\s\+$', '', '')
        if input =='' | return | endif
        let [pattsAND, pattsNOT] = Voom_GrepParseInput(input)
    endif

    """ Search must be done in Body buffer. Move to Body if in Tree.
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let body = s:voom_trees[bnr]
        let tree = bnr
        if Voom_BufLoaded(body) < 0 | return | endif
        if Voom_ToBody(body,'') < 0 | return | endif
        if Voom_BodyCheckTicks(body) < 0 | return | endif
    elseif has_key(s:voom_bodies, bnr)
        let body = bnr
        let tree = s:voom_bodies[bnr].tree
        " update outline
        if Voom_BodyUpdateTree() < 0 | return | endif
    else
        call Voom_ErrorMsg("VOoM (Voomgrep): current buffer is not a VOoM buffer")
        return
    endif

    """ Search for each pattern with search().
    let lz_ = &lz | set lz
    let winsave_dict = winsaveview()
    let [matchesAND, matchesNOT] = [[], []]
    for patt in pattsAND
        let matches = Voom_GrepSearch(patt)
        if matches==[0]
            call Voom_WarningMsg('VOoM (Voomgrep): pattern not found: '.patt)
            call winrestview(winsave_dict)
            call winline()
            let &lz=lz_
            return
        endif
        call add(matchesAND, matches)
    endfor
    for patt in pattsNOT
        call add(matchesNOT, Voom_GrepSearch(patt))
    endfor
    call winrestview(winsave_dict)
    call winline()
    let &lz=lz_

    """ Highlight first AND pattern.
    " Problem: there is no search highlight after :noh
    " Consider: use matchadd() if several AND patterns
    if len(pattsAND)>0
        let @/ = pattsAND[0]
    endif

    """ Set and display quickfix list.
    " first line shows patterns and number of matches
    let line1 = ''
    for i in range(len(pattsAND))
        let L = matchesAND[i]
        let line1 = i==0 ? line1.pattsAND[i].' {' : line1.'AND '.pattsAND[i].' {'
        let line1 = L[-1]==0 ? line1. (len(L)-1) .' matches}  ' : line1.'>10,000 matches}  '
    endfor
    for i in range(len(pattsNOT))
        let L = matchesNOT[i]
        let line1 = line1.'NOT '.pattsNOT[i].' {'
        let line1 = L[-1]==0 ? line1. (len(L)-1) .' matches}  ' : line1.'>10,000 matches}  '
    endfor
    let line1 = 'Voomgrep '. substitute(line1,"'","''",'g')
    exe "call setqflist([{'text':'".line1."'}])"

    python voom.voom_Grep()
    botright copen
endfunc


func! Voom_GrepParseInput(input) "{{{2
" Input string is patterns separated by AND or NOT.
" There can be a leading NOT, but not leading AND.
" Segregate patterns into AND and NOT lists.
    let [pattsAND, pattsNOT] = [[], []]
    " split at AND
    let andParts = split(a:input, '\v\c\s+and\s+')
    let i = 1
    for part in andParts
        " split at NOT
        let notParts = split(part, '\v\c\s+not\s+')
        " check for leading NOT
        if i==1
            let i+=1
            let parts1 = split(notParts[0], '\v\c^\s*not\s+', 1)
            if len(parts1)>1
                call add(pattsNOT, parts1[1])
            else
                call add(pattsAND, notParts[0])
            endif
        else
            call add(pattsAND, notParts[0])
        endif
        if len(notParts)>1
            let pattsNOT+=notParts[1:]
        endif
    endfor
    return [pattsAND, pattsNOT]
endfunc


func! Voom_GrepSearch(pattern) "{{{2
" Seach buffer for pattern. Return [lnums of matching lines].
" Stop search after first 10000 matches.
    let matches = []
    " always search from start
    keepj normal! gg0
    " special effort needed to detect match at cursor
    if searchpos(a:pattern, 'nc')==[1,1]
        call add(matches,1)
    endif
    " do search
    let found = 1
    while found>0 && len(matches)<10000
        let found = search(a:pattern, 'W')
        call add(matches, found)
    endwhile
    " search was terminated after 10000 matches were found
    if matches[-1]!=0
        call add(matches,-1)
    endif
    return matches
endfunc


"---LOG BUFFER (Voomlog)----------------------{{{1

func! Voom_LogInit() "{{{2
" Redirect Python stdout and stderr to Log buffer.
    let bnr_ = bufnr('')
    """" Log buffer exists, show it.
    if exists('s:voom_logbnr')
        if !bufloaded(s:voom_logbnr)
            python sys.stdout, sys.stderr = _voom_py_sys_stdout, _voom_py_sys_stderr
            python if 'pydoc' in sys.modules: del sys.modules['pydoc']
            if bufexists(s:voom_logbnr)
                exe 'noautocmd bwipeout '.s:voom_logbnr
            endif
            let bnr = s:voom_logbnr
            unlet s:voom_logbnr
            echoerr "VOoM: PyLog buffer" bnr "was not shut down properly. Cleanup has been performed. Execute the command :Voomlog again."
            return
        endif
        if bufwinnr(s:voom_logbnr) < 0
            call Voom_ToLogWin()
            silent exe 'b '.s:voom_logbnr
            normal! G
            exe bufwinnr(bnr_).'wincmd w'
        endif
        return
    endif

    """" Create Log buffer.
    call Voom_ToLogWin()
    silent edit __PyLog__
    let s:voom_logbnr=bufnr('')
    " Configure Log buffer
    au BufUnload <buffer> call Voom_LogBufUnload()
    setl cul nocuc list wrap
    setl bufhidden=wipe
    setl ft=voomlog
    setl noro ma ff=unix
    setl nobuflisted buftype=nofile noswapfile
    call Voom_LogSyntax()
python << EOF
_voom_py_sys_stdout, _voom_py_sys_stderr = sys.stdout, sys.stderr
sys.stdout = sys.stderr = voom.LogBufferClass()
if 'pydoc' in sys.modules: del sys.modules['pydoc']
EOF
    " Go back.
    exe bufwinnr(bnr_).'wincmd w'
endfunc


func! Voom_LogBufUnload() "{{{2
    if !exists('s:voom_logbnr') || expand("<abuf>")!=s:voom_logbnr
        echoerr 'VOoM: internal error'
        return
    endif
    python sys.stdout, sys.stderr = _voom_py_sys_stdout, _voom_py_sys_stderr
    python if 'pydoc' in sys.modules: del sys.modules['pydoc']
    exe 'bwipeout '.s:voom_logbnr
    unlet! s:voom_logbnr
endfunc


func! Voom_LogSyntax() "{{{2
" Log buffer syntax highlighting.

    " Python tracebacks
    syn match Title /^Traceback (most recent call last)/
    syn match Title /^\u\h*Error/
    syn region WarningMsg start="^Traceback (most recent call last)" end="^\u\h*Error.*" contains=Title keepend

    " VOoM messages
    syn match WarningMsg /^VOoM.*/

    syn match PreProc /^---end of Python script---/
    syn match PreProc /^---end of Vim script---/

    " -> UNL separator
    syn match Title / -> /

    syn match Type /^vim\.error/
    syn match WarningMsg /^Vim.*:E\d\+:.*/
endfunc


func! Voom_LogScroll() "{{{2
" Scroll windows with the __PyLog__ buffer.
" All tabs are searched, but only the first found Log window in a tab is scrolled.
" Uses noautocmd when entering tabs and windows.
" Note: careful with Python here: an error can cause recursive call.

    " can't go to other windows when in Ex mode (after 'Q' or 'gQ')
    if mode()=='c' | return | endif

    " This should never happen.
    if !exists('s:voom_logbnr') || !bufloaded(s:voom_logbnr)
        echoerr "VOoM: internal error"
        return
    endif

    let lz_=&lz | set lz
    let log_found=0
    let tnr_=tabpagenr()
    let wnr_=winnr()
    let bnr_=bufnr('')
    " search among visible buffers in all tabs
    for tnr in range(1, tabpagenr('$'))
        for bnr in tabpagebuflist(tnr)
            if bnr==s:voom_logbnr
                let log_found=1
                exe 'noautocmd tabnext '.tnr
                " save tab's current window and previous window numbers
                let wnr__ = winnr()
                let wnr__p = winnr('#')
                " move to window with buffer bnr
                exe 'noautocmd '. bufwinnr(bnr).'wincmd w'
                normal! G
                " restore tab's current and previous window numbers
                exe 'noautocmd '.wnr__p.'wincmd w'
                exe 'noautocmd '.wnr__.'wincmd w'
            endif
        endfor
    endfor

    " At least one Log window was found and scrolled. Return to original tab and window.
    if log_found==1
        exe 'noautocmd tabn '.tnr_
        exe 'noautocmd '.wnr_.'wincmd w'
    " Log window was not found. Create it.
    elseif log_found==0
        " Create new window.
        "wincmd t | 10wincmd l | vsplit | wincmd l
        call Voom_ToLogWin()
        exe 'b '.s:voom_logbnr
        normal! G
        " Return to original tab and buffer.
        exe 'tabn '.tnr_
        exe bufwinnr(bnr_).'wincmd w'
    endif
    let &lz=lz_
endfunc


"---EXECUTE SCRIPT (Voomexec)-----------------{{{1

func! Voom_GetBodyLines(lnum) "{{{2
" Return list of Body lines.
" Tree buffer: Body lines from branch at Tree line lnum (node lnum and all its
" subnodes).
" Any other buffer: lines from fold at line lnum, including subfolds.
" Return [] if checks fail.

    """"" Tree buffer: get lines from corresponding node.
    if has_key(s:voom_trees, bufnr(''))
        let body = s:voom_trees[bufnr('')]
        if Voom_BufLoaded(body) < 0 | return [] | endif
        let status = Voom_FoldStatus(a:lnum)
        if status=='hidden'
            call Voom_ErrorMsg('VOoM: current line is hidden in fold')
            return []
        endif

        " this computes and assigns nodeStart and nodeEnd
        python voom.voom_GetBodyLines()
        "echo [nodeStart, nodeEnd]
        return getbufline(body, nodeStart, nodeEnd)
    endif

    """"" Regular buffer: get lines from current fold.
    if &fdm !=# 'marker'
        call Voom_ErrorMsg('VOoM: ''foldmethod'' must be "marker"')
        return []
    endif
    let status = Voom_FoldStatus(a:lnum)
    if status=='nofold'
        call Voom_ErrorMsg('VOoM: no fold at cursor')
        return []
    elseif status=='hidden'
        call Voom_ErrorMsg('VOoM: current line is hidden in fold')
        return []
    elseif status=='folded'
        return getline(foldclosed(a:lnum), foldclosedend(a:lnum))
    elseif status=='notfolded'
        let lz_ = &lz | set lz
        let winsave_dict = winsaveview()
        normal! zc
        let foldStart = foldclosed(a:lnum)
        let foldEnd   = foldclosedend(a:lnum)
        normal! zo
        call winrestview(winsave_dict)
        let &lz=lz_
        return getline(foldStart, foldEnd)
    endif
endfunc


func! Voom_GetBodyLines1() "{{{2
" Return list of Body lines of node under the cursor.
" This is for use by external scripts. Can be called from any buffer.
" Return [-1] if lines cannot be obtained.
    let lnum = line('.')
    let bnr = bufnr('')
    if has_key(s:voom_trees, bnr)
        let buftype = 'tree'
        let body = s:voom_trees[bnr]
        if Voom_BufLoaded(body) < 0 | return [-1] | endif
    elseif has_key(s:voom_bodies, bnr)
        let buftype = 'body'
        let body = bnr
        let tree = s:voom_bodies[body].tree
        if Voom_BodyUpdateTree() < 0 | return [-1] | endif
    else
        "echo "VOoM: current buffer is not a VOoM buffer"
        return []
    endif

    python voom.voom_GetBodyLines1()
    return getbufline(body, l:bln1, l:bln2)
endfunc


func! Voom_Exec(qargs) "{{{2
" Execute text from the current fold (non-Tree buffer, include subfolds) or
" node (Tree buffer, include subnodes) as a script.
" If argument is 'vim' or 'py'/'python': execute as Vim or Python script.
" Otherwise execute according to filetype.

    " Determine type of script.
    " this is a Tree, use Body filetype
    if has_key(s:voom_trees, bufnr(''))
        let ft = getbufvar(s:voom_trees[bufnr('')], '&ft')
    " this is not a Tree, use current buffer filetype
    else
        let ft = &ft
    endif
    if     a:qargs==#'vim'
        let scriptType = 'vim'
    elseif a:qargs==#'py' || a:qargs==#'python'
        let scriptType = 'python'
    elseif a:qargs!=''
        call Voom_ErrorMsg('VOoM: unsupported script type: "'.a:qargs.'"')
        return
    elseif ft==#'vim'
        let scriptType = 'vim'
    elseif ft==#'python'
        let scriptType = 'python'
    else
        call Voom_ErrorMsg('VOoM: unsupported script type: "'.ft.'"')
        return
    endif

    " Get script lines.
    let lines = Voom_GetBodyLines(line('.'))
    if lines==[] | return | endif

    " Execute Vim script: Copy list of lines to register and execute it.
    " Problem: Python errors do not terminate script and Python tracebacks are
    " not printed. They are printed to the PyLog if it's enabled.
    if scriptType==#'vim'
        let reg_z = getreg('z')
        let reg_z_mode = getregtype('z')
        let script = join(lines, "\n") . "\n"
        call setreg('z', script, "l")
        try
            @z
            echo '---end of Vim script---'
        catch /.*/
            call Voom_ErrorMsg(v:exception)
        endtry
        call setreg('z', reg_z, reg_z_mode)
    " Execute Python script: write lines to a .py file and do execfile().
    elseif scriptType==#'python'
        " specifiy script encoding on first line
        let fenc = &fenc!='' ? &fenc : &enc
        call insert(lines, '# -*- coding: '.fenc.' -*-')
        if writefile(lines, s:voom_script_py)==0
            python voom.execScript()
        endif
    endif
endfunc


"---execute user command----------------------{{{1
if exists('g:voom_user_command')
    execute g:voom_user_command
endif


" modelines {{{1
" vim:fdm=marker:fdl=0:
" vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart):
