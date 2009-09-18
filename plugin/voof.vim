" voof.vim
" VOOF (Vim Outliner Of Folds): two-pane outliner and related utilities
" plugin for Python-enabled Vim version 7.x
" Website: http://www.vim.org/scripts/script.php?script_id=2657
"  Author: Vlad Irnov  (vlad DOT irnov AT gmail DOT com)
" License: This program is free software. It comes without any warranty,
"          to the extent permitted by applicable law. You can redistribute it
"          and/or modify it under the terms of the Do What The Fuck You Want To
"          Public License, Version 2, as published by Sam Hocevar.
"          See http://sam.zoy.org/wtfpl/COPYING for more details.
" Version: 1.8, 2009-09-18


"---Conventions-----------------------{{{1
" Tree      --Tree buffer
" Body      --Body buffer
" tree      --Tree buffer number
" body      --Body buffer number
" headline  --Body line with a matching fold marker, also a Tree line
" node      --Body region between two headlines, usually also a fold
" nodes     --line numbers of headlines in a Body, list of node locations
" bnr       --buffer number
" wnr, tnr  --window number, tab number
" lnr(s), lnum(s), ln --line number(s), usually Tree
" blnr, bln --Body line number
" tline, tLine --Tree line
" bline, bLine --Body line
" snLn      --selected node line number, a Tree line number
" var_      --previous value of var


"---Quickload-------------------------{{{1
if !exists('s:voof_did_load')
    let s:voof_did_load = '1.7'
    com! Voof  call Voof_Init()
    com! Vooflog  call Voof_LogInit()
    com! Voofhelp  call Voof_Help()
    com! -nargs=? Voofrun  call Voof_Run(<q-args>)
    exe "au FuncUndefined Voof_* source " . expand("<sfile>:p")
    finish
endif


"---Initialize------------------------{{{1
if !exists('s:voof_did_init')
    let s:voof_path = expand("<sfile>:p")
    let s:voof_dir = expand("<sfile>:p:h")
    let s:voof_script_py = s:voof_dir.'/voofScript.py'
    let s:voof_TreeBufEnter = 1

    " {tree : associated body,  ...}
    let s:voof_trees = {}
    " {body : {'tree' : associated tree,
    "          'blnr' : Body line number,
    "          'snLn' : selected node line number,
    "          'tick' : b:changedtick of Body,
    "          'tick_' : b:changedtick of Body on last Tree update}, {...}, ... }
    let s:voof_bodies = {}

python << EOF
import vim
import sys
voof_dir = vim.eval('s:voof_dir')
if not voof_dir in sys.path:
    sys.path.append(voof_dir)
import voof
VOOF = sys.modules['voof'].VOOF = voof.VoofData()
VOOF.vim_stdout, VOOF.vim_stderr = sys.stdout, sys.stderr
EOF
    au! FuncUndefined Voof_*
    let s:voof_did_init = 1
endif


"---User Options----------------------{{{1
" These can be defined in .vimrc .

" Where Tree window is created: 'left', 'right', 'top', 'bottom'
" This is relative to the current window.
if !exists('g:voof_tree_placement')
    let g:voof_tree_placement = 'left'
endif
" Initial Tree window width.
if !exists('g:voof_tree_width')
    let g:voof_tree_width = 30
endif
" Initial Tree window hight.
if !exists('g:voof_tree_hight')
    let g:voof_tree_hight = 12
endif

" Where Log window is created: 'left', 'right', 'top', 'bottom'
" This is far left/right/top/bottom.
if !exists('g:voof_log_placement')
    let g:voof_log_placement = 'bottom'
endif
" Initial Log window width.
if !exists('g:voof_log_width')
    let g:voof_log_width = 30
endif
" Initial Log window hight.
if !exists('g:voof_log_hight')
    let g:voof_log_hight = 12
endif

" Verify outline after outline operations.
if !exists('g:voof_verify_oop')
    let g:voof_verify_oop = 0
endif

" Which key to map to Select-Node-and-Shuttle-between-Body/Tree
if !exists('g:voof_return_key')
    let g:voof_return_key = '<Return>'
endif

" Which key to map to Shuttle-between-Body/Tree
if !exists('g:voof_tab_key')
    let g:voof_tab_key = '<Tab>'
endif


"---Voof_Init(), various helpers------{{{1
"
func! Voof_Init() "{{{2
" Voof command.
" Create Tree for current buffer, which becomes a Body buffer.
    let body = bufnr('')
    " this is a Tree buffer
    if has_key(s:voof_trees, body) | return | endif

    if !has_key(s:voof_bodies, body)
    " There is no Tree for this Body. Create it.
        let s:voof_bodies[body] = {}
        let s:voof_bodies[body].blnr = line('.')
        let b_name = expand('%:p:t')
        if b_name=='' | let b_name='No Name' | endif
        let b_dir = expand('%:p:h')
        let l:firstLine = ' ' . b_name .' ['. b_dir . '], b' . body

        py voof.voof_Init(int(vim.eval('body')))

        "normal! zMzv
        call Voof_BodyConfigure()

        call Voof_ToTreeWin()
        call Voof_TreeCreate(body)

    else
    " There is already a Tree for this Body. Show it.
        let tree = s:voof_bodies[body].tree
        if !exists('b:voof_body')
            echoerr "VOOF: Body lost b:voof_tree. Reconfiguring..."
            call Voof_BodyConfigure()
        endif
        if Voof_ToTree(tree)==-1 | return | endif
        if !exists('b:voof_tree')
            echoerr "VOOF: Tree lost b:voof_tree. Reconfiguring..."
            call Voof_TreeConfigure()
        endif
    endif
endfunc


func! Voof_FoldStatus(lnum) "{{{2
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
    if fc < a:lnum && fc!=-1
        return 'hidden'
    " line is first line of a closed fold
    elseif fc==a:lnum
        return 'folded'
    " line is in an opened fold
    else
        return 'notfolded'
    endif
endfunc


func! Voof_Help() "{{{2=
" Display voof.txt as outline in new tabpage.
    let bnr = bufnr('')
    " already in voof.txt
    if fnamemodify(bufname(bnr), ":t")==#'voof.txt'
        return
    " in Tree for voof.txt
    elseif has_key(s:voof_trees, bnr) && fnamemodify(bufname(s:voof_trees[bnr]), ":t")==#'voof.txt'
        return
    endif

    """"" if voof.vim is in /a/b, voof.txt is expected in /a/doc
    let voof_help = fnamemodify(s:voof_dir, ":h") . '/doc/voof.txt'
    if !filereadable(voof_help)
        echoerr "VOOF: can't read help file:" voof_help
        return
    endif

    """"" try help command
    let voof_help_installed = 1
    let tnr_ = tabpagenr()
    try
        silent tab help voof.txt
    catch /^Vim\%((\a\+)\)\=:E149/ " no help for voof.txt
        let voof_help_installed = 0
    catch /^Vim\%((\a\+)\)\=:E429/ " help file not found--removed after installing
        let voof_help_installed = 0
    endtry
    if voof_help_installed==1
        Voof
        normal! zR
        return
    elseif tabpagenr()==tnr_+1 && bufname('')==''
        " 'tab help' failed, we are on new empty tabpage
        bwipeout
        exe 'tabnext '.tnr_
    endif

    """"" open voof.txt as regular file
    exe 'tabnew '.voof_help
    if &ft!=#'help'
        set ft=help
    endif
    Voof
    normal! zR
endfunc


func! Voof_WarningMsg(...) "{{{2
    echohl WarningMsg
    for line in a:000
        echo line
    endfor
    echohl None
endfunc


func! Voof_ErrorMsg(...) "{{{2
    echohl Error
    for line in a:000
        echom line
    endfor
    echohl None
endfunc


func! Voof_ReloadAllPre() "{{{2
" Helper for reloading entire plugin.
    update
    " wipe out all Tree buffers
    for bnr in keys(s:voof_trees)
        if bufexists(str2nr(bnr))
            exe 'bwipeout '.bnr
        endif
    endfor
    py reload(voof)
    unlet s:voof_did_init
endfunc


func! Voof_PrintData() "{{{2
" Print Voof data.
    redir => voofData
    silent echo repeat('-', 60)
    if exists('s:voof_logbnr')
        silent echo 's:voof_logbnr --' s:voof_logbnr
    endif
    for v in ['s:voof_did_load', 's:voof_did_init', 's:voof_dir', 's:voof_path', 's:voof_script_py', 's:voof_TreeBufEnter', 'g:voof_verify_oop', 's:voof_trees', 's:voof_bodies']
        silent echo v '--' {v}
    endfor
    redir END
    echo ' '
    py print vim.eval('voofData')
endfunc


"---Windows Navigation and Creation---{{{1
" These deal only with the current tab page.
"
func! Voof_ToTreeOrBodyWin() "{{{2
" If in Tree window, move to Body window.
" If in Body window, move to Tree window.
" If possible, use previous window.

    let bnr = bufnr('')
    " current buffer is  Tree
    if has_key(s:voof_trees, bnr)
        let target_bnr = s:voof_trees[bnr]
    " current buffer is Body
    else
        " This happens after Tree is wiped out.
        if !has_key(s:voof_bodies, bnr)
            call Voof_BodyUnMap()
            return
        endif
        let target_bnr = s:voof_bodies[bnr].tree
    endif

    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==target_bnr
        exe wnr.'wincmd w'
        return
    endif
    " Search among all windows.
    let wnr_ = winnr()
    while 1
        wincmd w
        if winnr()==wnr_ || bufnr('')==target_bnr
            break
        endif
    endwhile
endfunc


func! Voof_ToTreeWin() "{{{2
" Move to window or open a new one where a Tree will be loaded.

    " Allready in a Tree buffer.
    if has_key(s:voof_trees, bufnr('')) | return | endif

    " Use previous window if it shows Tree.
    let wnr = winnr('#')
    if has_key(s:voof_trees, winbufnr(wnr))
        exe wnr.'wincmd w'
        return
    endif

    " Use any window with a Tree buffer.
    for bnr in tabpagebuflist()
        if has_key(s:voof_trees, bnr)
            exe bufwinnr(bnr).'wincmd w'
            return
        endif
    endfor

    " Create new window.
    if g:voof_tree_placement=='top'
        exe 'leftabove '.g:voof_tree_hight.'split'
    elseif g:voof_tree_placement=='bottom'
        exe 'rightbelow '.g:voof_tree_hight.'split'
    elseif g:voof_tree_placement=='left'
        exe 'leftabove '.g:voof_tree_width.'vsplit'
    elseif g:voof_tree_placement=='right'
        exe 'rightbelow '.g:voof_tree_width.'vsplit'
    endif
endfunc


func! Voof_ToTree(tree) abort "{{{2
" Move cursor to window with Tree buffer a:tree or load it in a new window.
    " Already there.
    if bufnr('')==a:tree | return | endif

    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==a:tree
        exe wnr.'wincmd w'
        return
    endif

    " There is window with buffer a:tree .
    if bufwinnr(a:tree)!=-1
        exe bufwinnr(a:tree).'wincmd w'
        return
    endif

    " Bail out if Tree is unloaded or doesn't exist.
    " Because of au, this should never happen.
    if !bufloaded(a:tree)
        let body = s:voof_trees[a:tree]
        call Voof_UnVoof(body,a:tree)
        echoerr "VOOF: Tree buffer" a:tree "was not loaded or didn't exist. Cleanup has been performed."
        return -1
    endif

    " Create new window and load there.
    call Voof_ToTreeWin()
    silent exe 'b'.a:tree
    " Must set options local to window.
    setl foldenable
    setl foldtext=getline(v:foldstart).'\ \ \ /'.(v:foldend-v:foldstart)
    setl foldmethod=expr
    setl foldexpr=Voof_TreeFoldexpr(v:lnum)
    setl cul nocuc nowrap nolist
    "setl winfixheight
    setl winfixwidth
endfunc


func! Voof_ToBodyWin() "{{{2
" Split current Tree window to create window where Body will be loaded
    if g:voof_tree_placement=='top'
        exe 'leftabove '.g:voof_tree_hight.'split'
        wincmd p
    elseif g:voof_tree_placement=='bottom'
        exe 'rightbelow '.g:voof_tree_hight.'split'
        wincmd p
    elseif g:voof_tree_placement=='left'
        exe 'leftabove '.g:voof_tree_width.'vsplit'
        wincmd p
    elseif g:voof_tree_placement=='right'
        exe 'rightbelow '.g:voof_tree_width.'vsplit'
        wincmd p
    endif
endfunc


func! Voof_ToBody(body, noa) abort "{{{2
" Move to window with Body a:body or load it in a new window.
" If a:noa is '', don't use noautocmd with "wincmd w".
    " Allready there.
    if bufnr('')==a:body | return | endif

    let m = 'noautocmd '
    if a:noa==''
        let m = ''
    endif

    " Try previous window.
    let wnr = winnr('#')
    if winbufnr(wnr)==a:body
        exe m.wnr.'wincmd w'
        return
    endif

    " There is a window with buffer a:body .
    if bufwinnr(a:body)!=-1
        exe m.bufwinnr(a:body).'wincmd w'
        return
    endif

    " Bail out if Body is unloaded or doesn't exist.
    " Because of au, this should never happen.
    if !bufloaded(a:body)
        let tree = s:voof_bodies[a:body].tree
        if !exists("s:voof_trees") || !has_key(s:voof_trees, tree) || (a:body!=s:voof_trees[tree])
            echoerr "VOOF: internal error"
            return -1
        endif
        call Voof_UnVoof(a:body,tree)
        echoerr "VOOF: Body" a:body "was not loaded or didn't exist. Cleanup has been performed."
        return -1
    endif

    " Create new window and load there.
    call Voof_ToBodyWin()
    exe 'b'.a:body
endfunc


func! Voof_ToLogWin() "{{{2
" Create new window where PyLog will be loaded.
    if g:voof_log_placement=='top'
        exe 'topleft '.g:voof_log_hight.'split'
    elseif g:voof_log_placement=='bottom'
        exe 'botright '.g:voof_log_hight.'split'
    elseif g:voof_log_placement=='left'
        exe 'topleft '.g:voof_log_width.'vsplit'
    elseif g:voof_log_placement=='right'
        exe 'botright '.g:voof_log_width.'vsplit'
    endif
endfunc


"---TREE BUFFERS----------------------{{{1
"
"---Tree augroup---{{{2
augroup VoofTree
    au!
    au BufEnter   *_VOOF\d\+   call Voof_TreeBufEnter()
    au BufUnload  *_VOOF\d\+   nested call Voof_TreeBufUnload()
augroup END


func! Voof_TreeBufEnter() "{{{2
" Tree's BufEnter au.
" Update outline if Body was changed since last update. Redraw Tree if needed.
    "py print 'BufEnter'
    "let start = reltime()
    if s:voof_TreeBufEnter==0
        let s:voof_TreeBufEnter = 1
        return
    endif

    let tree = bufnr('')
    let body = s:voof_trees[tree]

    """ update is not needed
    if s:voof_bodies[body].tick_==s:voof_bodies[body].tick
        return
    endif

    """ do update
    let snLn_ = s:voof_bodies[body].snLn
    setl ma
    let ul_=&ul | setl ul=-1
    try
        keepj py voof.voofUpdate(int(vim.eval('body')))
        let s:voof_bodies[body].tick_ = s:voof_bodies[body].tick
    finally
        let &ul=ul_
        setl noma
    endtry

    " The = mark is placed by voofUpdate()
    " When nodes are deleted by editing Body, snLn can get > last Tree lnum,
    " voof.voofUpdate() will change snLn to last line lnum
    let snLn = s:voof_bodies[body].snLn
    if snLn_ != snLn
        normal! Gzv
    endif
    "echom reltimestr(reltime(start))
endfunc


func! Voof_TreeBufUnload() "{{{2
" Tree's BufUnload au. Wipe out Tree and cleanup.
    let tree = expand("<abuf>")
    "py print vim.eval('l:tree')
    if !exists("s:voof_trees") || !has_key(s:voof_trees, tree)
        echoerr "VOOF: internal error"
        return
    endif
    let body = s:voof_trees[tree]
    "echom bufexists(tree) " this is always 0
    exe 'noautocmd bwipeout '.tree
    call Voof_UnVoof(body,tree)
endfunc


func! Voof_TreeFoldexpr(lnum) "{{{2
" 'foldexpr' function for emulating tree widget.
    " match() is affected by encoding, but probably not in this case.
    let indent  = match(getline(a:lnum)  , '|') / 2
    let indentn = match(getline(a:lnum+1), '|') / 2

    " Start new fold if next line has bigger indent:
    " tree starts, node has children.
    if indentn > indent
        return '>' . indent
    " End all higher level folds if next line has smaller indent:
    " tree ends, node is childless and is the last sibling.
    elseif indentn < indent
        return '<' . indentn
    " Next line has the same indent.
    else
        return (indent-1)
    endif
endfunc


func! Voof_TreeCreate(body) "{{{2
" Create new Tree buffer for Body body in the current window.

    " Suppress Tree BufEnter autocommand once.
    let s:voof_TreeBufEnter = 0

    let b_name = fnamemodify(bufname(a:body),":t")
    if b_name=='' | let b_name='NoName' | endif
    silent exe 'edit '.b_name.'_VOOF'.a:body
    let tree = bufnr('')

    """ Initialize VOOF data.
    let s:voof_bodies[a:body].tree = tree
    let s:voof_trees[tree] = a:body
    let s:voof_bodies[a:body].tick_ = 0
    py VOOF.buffers[int(vim.eval('tree'))] = vim.current.buffer

    call Voof_TreeConfigure()

    """ Create outline and draw Tree lines.
    setl ma
    let ul_=&ul | setl ul=-1
    try
        keepj py voof.voofUpdate(int(vim.eval('a:body')))
        " Draw = mark. This must be done afer creating outline.
        " this assigns s:voof_bodies[body].snLn
        " calendar_outline.txt: 0.002 sec
        py voof.voof_TreeCreate()
        let snLn = s:voof_bodies[a:body].snLn
        " Initial draw puts = on first line.
        if snLn!=1
            keepj call setline(snLn, '='.getline(snLn)[1:])
            keepj call setline(1, ' '.getline(1)[1:])
        endif
        let s:voof_bodies[a:body].tick_ = s:voof_bodies[a:body].tick
    finally
        let &ul=ul_
        setl noma
    endtry

    """ Show current position.
    exe 'normal! ' . snLn . 'G'
    call Voof_TreeZV()
    call Voof_TreePlaceCursor()
    " blnShow is created by voof_TreeCreate() when there is Body headline marked with =
    if exists('l:blnShow')
        " go to Body
        let wnr_ = winnr()
        if Voof_ToBody(a:body,'noa')==-1 | return | endif

        " show fold at l:blnShow
        exe 'normal '.l:blnShow.'G'
        if &fdm==#'marker'
            normal! zMzvzt
        else
            normal! zt
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


func! Voof_TreeConfigure() "{{{2
" Configure current buffer as a Tree buffer--options, syntax, mappings.

    """" Options local to window.
    setl foldenable
    setl foldtext=getline(v:foldstart).'\ \ \ /'.(v:foldend-v:foldstart)
    setl foldmethod=expr
    setl foldexpr=Voof_TreeFoldexpr(v:lnum)
    setl cul nocuc nowrap nolist
    "setl winfixheight
    setl winfixwidth

    """" This should allow customizing via ftplugin. Removes syntax hi.
    setl ft=vooftree

    """" Options local to buffer.
    setl nobuflisted buftype=nofile noswapfile bufhidden=hide
    setl noro ma ff=unix noma

    """" Syntax.
    " first line
    syn match Title /\%1l.*/
    " line comment chars: "  #  //  /*  %  <!--
    syn match Comment @|\zs\%("\|#\|//\|/\*\|%\|<!--\).*@ contains=Todo
    " keywords
    syn match Todo /\%(TODO\|Todo\)/
    " selected node
    "syn match Pmenu /^=.\{-}|\zs.*/
    "syn match Pmenu /^=/

    call Voof_TreeMap()
    let b:voof_tree = 1

    "augroup VoofTree
        "au! * <buffer>
        "au BufEnter   <buffer> call Voof_TreeBufEnter()
        "au BufUnload  <buffer> nested call Voof_TreeBufUnload()
    "augroup END
endfunc


func! Voof_TreeMap() "{{{2
" Mappings and commands local to a Tree buffer.
    let cpo_ = &cpo | set cpo&vim
    " Use noremap to disable keys.
    " Use nnoremap and vnoremap to map keys to Voof functions, don't use noremap.
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
    nnoremap <buffer><silent> i :<C-u>call Voof_OopEdit()<CR>
    nnoremap <buffer><silent> I :<C-u>call Voof_OopEdit()<CR>
    nnoremap <buffer><silent> a :<C-u>call Voof_OopEdit()<CR>
    nnoremap <buffer><silent> A :<C-u>call Voof_OopEdit()<CR>
    " }}}

    " Node selection and navigation. {{{

    exe "nnoremap <buffer><silent> ".g:voof_return_key.     " :<C-u>call Voof_TreeSelect(line('.'), '')<CR>"
    exe "vnoremap <buffer><silent> ".g:voof_return_key." <Esc>:<C-u>call Voof_TreeSelect(line('.'), '')<CR>"
    "exe "vnoremap <buffer><silent> ".g:voof_return_key." <Nop>"
    exe "nnoremap <buffer><silent> ".g:voof_tab_key.        " :<C-u>call Voof_ToTreeOrBodyWin()<CR>"
    exe "vnoremap <buffer><silent> ".g:voof_tab_key.   " <Esc>:<C-u>call Voof_ToTreeOrBodyWin()<CR>"
    "exe "vnoremap <buffer><silent> ".g:voof_tab_key.   " <Nop>"

    " Put cursor on the current position.
    nnoremap <buffer><silent> = :<C-u>call Voof_TreeToSnLn()<CR>

    " Do not map <LeftMouse>. Not triggered on first click in the buffer.
    " Triggered on first click in another buffer. Vim doesn't know what buffer
    " it is until after the click.
    " Left mouse release. Also triggered when resizing window with the mouse.
    nnoremap <buffer><silent> <LeftRelease> <LeftRelease>:<C-u>call Voof_TreeOnLeftClick()<CR>
    inoremap <buffer><silent> <LeftRelease> <LeftRelease><Esc>
    " Disable Left mouse double click to avoid entering Visual mode.
    nnoremap <buffer><silent> <2-LeftMouse> <Nop>

    nnoremap <buffer><silent> <Space> :<C-u>call Voof_TreeToggleFold()<CR>
    "vnoremap <buffer><silent> <Space> :<C-u>call Voof_TreeToggleFold()<CR>

    nnoremap <buffer><silent> <Down> <Down>:<C-u>call Voof_TreeSelect(line('.'), 'tree')<CR>
    nnoremap <buffer><silent>   <Up>   <Up>:<C-u>call Voof_TreeSelect(line('.'), 'tree')<CR>

    nnoremap <buffer><silent> <Left>  :<C-u>call Voof_TreeLeft()<CR>
    nnoremap <buffer><silent> <Right> :<C-u>call Voof_TreeRight()<CR>

    nnoremap <buffer><silent> x :<C-u>call Voof_TreeNextMark(0)<CR>
    nnoremap <buffer><silent> X :<C-u>call Voof_TreeNextMark(1)<CR>
    " }}}

    " Outline operations. {{{
    " Can't use Ctrl as in Leo: <C-i> is Tab; <C-u>, <C-d> are page up/down.

    " insert new node
    nnoremap <buffer><silent> <LocalLeader>i  :<C-u>call Voof_OopInsert('')<CR>
    nnoremap <buffer><silent> <LocalLeader>I  :<C-u>call Voof_OopInsert('as_child')<CR>

    " move
    nnoremap <buffer><silent> <LocalLeader>u  :<C-u>call Voof_Oop('up', 'n')<CR>
    nnoremap <buffer><silent>         <C-Up>  :<C-u>call Voof_Oop('up', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>u  :<C-u>call Voof_Oop('up', 'v')<CR>
    vnoremap <buffer><silent>         <C-Up>  :<C-u>call Voof_Oop('up', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>d  :<C-u>call Voof_Oop('down', 'n')<CR>
    nnoremap <buffer><silent>       <C-Down>  :<C-u>call Voof_Oop('down', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>d  :<C-u>call Voof_Oop('down', 'v')<CR>
    vnoremap <buffer><silent>       <C-Down>  :<C-u>call Voof_Oop('down', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>l  :<C-u>call Voof_Oop('left', 'n')<CR>
    nnoremap <buffer><silent>       <C-Left>  :<C-u>call Voof_Oop('left', 'n')<CR>
    nnoremap <buffer><silent>             <<  :<C-u>call Voof_Oop('left', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>l  :<C-u>call Voof_Oop('left', 'v')<CR>
    vnoremap <buffer><silent>       <C-Left>  :<C-u>call Voof_Oop('left', 'v')<CR>
    vnoremap <buffer><silent>             <<  :<C-u>call Voof_Oop('left', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>r  :<C-u>call Voof_Oop('right', 'n')<CR>
    nnoremap <buffer><silent>      <C-Right>  :<C-u>call Voof_Oop('right', 'n')<CR>
    nnoremap <buffer><silent>             >>  :<C-u>call Voof_Oop('right', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>r  :<C-u>call Voof_Oop('right', 'v')<CR>
    vnoremap <buffer><silent>      <C-Right>  :<C-u>call Voof_Oop('right', 'v')<CR>
    vnoremap <buffer><silent>             >>  :<C-u>call Voof_Oop('right', 'v')<CR>

    " cut/copy/paste
    nnoremap <buffer><silent>  dd  :<C-u>call Voof_Oop('cut', 'n')<CR>
    vnoremap <buffer><silent>  dd  :<C-u>call Voof_Oop('cut', 'v')<CR>

    nnoremap <buffer><silent>  yy  :<C-u>call Voof_Oop('copy', 'n')<CR>
    vnoremap <buffer><silent>  yy  :<C-u>call Voof_Oop('copy', 'v')<CR>

    nnoremap <buffer><silent>  pp  :<C-u>call Voof_OopPaste()<CR>

    " mark/unmark
    nnoremap <buffer><silent> <LocalLeader>m   :<C-u>call Voof_OopMark('mark', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>m   :<C-u>call Voof_OopMark('mark', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>M   :<C-u>call Voof_OopMark('unmark', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>M   :<C-u>call Voof_OopMark('unmark', 'v')<CR>

    " mark node as selected node
    nnoremap <buffer><silent> <LocalLeader>=   :<C-u>call Voof_OopMarkSelected()<CR>
    " }}}

    " Various commands. {{{
    nnoremap <buffer><silent> <F1> :<C-u>call Voof_Help()<CR>
    nnoremap <buffer><silent> <LocalLeader>r :<C-u>call Voof_Run('')<CR>
    " }}}

    let &cpo = cpo_
endfunc


"---Outline Navigation---{{{2
"
func! Voof_TreeSelect(lnum, focus) "{{{3
" Select node corresponding to Tree line lnum.
" Show correspoding node in Body.
" Leave cursor in Body if cursor is already in the selected node and focus!='tree'.

    let tree = bufnr('')
    let body = s:voof_trees[tree]
    let snLn = s:voof_bodies[body].snLn

    let lz_ = &lz | set lz
    call Voof_TreeZV()
    call Voof_TreePlaceCursor()

    """" Mark new line with =. Remove old = mark.
    if a:lnum!=snLn
        setl ma | let ul_ = &ul | setl ul=-1
        keepj call setline(a:lnum, '='.getline(a:lnum)[1:])
        keepj call setline(snLn, ' '.getline(snLn)[1:])
        setl noma | let &ul = ul_
        let s:voof_bodies[body].snLn = a:lnum
        "py VOOF.snLns[int(vim.eval('body'))] = int(vim.eval('a:lnum'))
    endif

    """" Go to Body, show current node, and either come back or stay in Body.
    if Voof_ToBody(body, 'noa')==-1 | let &lz=lz_ | return | endif
    if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

    " Show Body node corresponding to current line in the Tree.
    let bodyLnr = line('.')
    let new_node_selected = 0
    " This assigns l:nodeStart and l:nodeEnd: Body lnums
    py voof.voof_TreeSelect()
    if ((bodyLnr < l:nodeStart) || (bodyLnr > l:nodeEnd))
        let new_node_selected = 1
        exe 'normal '.nodeStart.'G'
        if &fdm ==# 'marker'
            normal! zMzv
        endif
        " Position headline near window top. Affected by 'scrolloff'.
        normal! zt
    endif

    """" Go back to Tree after showing a different node in the Body.
    """" Otherwise, that is if Body's node was same as Tree's, stay in the Body.
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


func! Voof_TreePlaceCursor() "{{{3
" Place cursor before the headline.
    "let lz_ = &lz | set lz
    let col = match(getline('.'), '|') + 1
    if col==0
        let col = 1
    endif
    call cursor('.', col)
    "let &lz=lz_
endfunc


func! Voof_TreeZV() "{{{3
" Make current line visible.
" Like zv, but when current line starts a fold, do not automatically open that fold.
    let lnum = line('.')
    let fc = foldclosed(lnum)
    while fc < lnum && fc!=-1
        normal zo
        let fc = foldclosed(lnum)
    endwhile
endfunc


func! Voof_TreeToLine(lnum) "{{{3
" Put cursor on line lnum, usually snLn.
    if (line('w0') < a:lnum) && (a:lnum > 'w$')
        let offscreen = 0
    else
        let offscreen = 1
    endif
    exe 'normal! ' . a:lnum . 'G'
    call Voof_TreeZV()
    call Voof_TreePlaceCursor()
    if offscreen==1
        normal zz
    endif
endfunc


func! Voof_TreeToSnLn() "{{{3
" Put cursor on SnLn line.
    let lnum = s:voof_bodies[s:voof_trees[bufnr('')]].snLn
    call Voof_TreeToLine(lnum)
endfunc


func! Voof_TreeToggleFold() "{{{3
" Toggle fold at cursor: expand/contract node.
    let lnum=line('.')
    let ln_status = Voof_FoldStatus(lnum)

    if ln_status=='folded'
        normal zo
    elseif ln_status=='notfolded'
        if match(getline(lnum), '|') < match(getline(lnum+1), '|')
            normal zc
        endif
    elseif ln_status=='hidden'
        call Voof_TreeZV()
    endif
endfunc


func! Voof_TreeOnLeftClick() "{{{3
" Toggle fold on mouse click after or before headline text.
    if virtcol('.')+1 >= virtcol('$') || col('.')-1 < match(getline('.'), '|')
        call Voof_TreeToggleFold()
    endif
    call Voof_TreeSelect(line('.'), 'tree')
endfunc


func! Voof_TreeLeft() "{{{3
" Move to parent after first contracting node.
    let lnum = line('.')

    " line is hidden in a closed fold: make it visible
    let fc = foldclosed(lnum)
    if fc < lnum && fc!=-1
        while fc < lnum && fc!=-1
            normal zo
            let fc = foldclosed(lnum)
        endwhile
        normal zz
        call cursor('.', match(getline('.'), '|') + 1)
        call Voof_TreeSelect(line('.'), 'tree')
        return
    endif

    let ind = match(getline(lnum), '|')
    if ind==-1 | return | endif
    let indn = match(getline(lnum+1), '|')

    " line is in an opened fold and next line has bigger indent: close fold
    if fc==-1 && (ind < indn)
        normal zc
        call Voof_TreeSelect(line('.'), 'tree')
        return
    endif

    " root node: do not move
    if ind==2
        call cursor('.', match(getline('.'), '|') + 1)
        call Voof_TreeSelect(line('.'), 'tree')
        return
    endif

    " move to parent
    let indp = ind
    while indp>=ind
        normal k
        let indp = match(getline('.'), '|')
    endwhile
    "normal zz
    call cursor('.', match(getline('.'), '|') + 1)
    call Voof_TreeSelect(line('.'), 'tree')
endfunc


func! Voof_TreeRight() "{{{3
" Move to first child.
    let lnum = line('.')
    " line is hidden in a closed fold: make it visible
    let fc = foldclosed(lnum)
    if fc < lnum && fc!=-1
        while fc < lnum && fc!=-1
            normal zo
            let fc = foldclosed(lnum)
        endwhile
        normal zz
        call cursor('.', match(getline('.'), '|') + 1)
        call Voof_TreeSelect(line('.'), 'tree')
        return
    endif

    " line is in a closed fold
    if fc==lnum
        normal zoj
        call cursor('.', match(getline('.'), '|') + 1)
    " line is not in a closed fold and next line has bigger indent
    elseif match(getline(lnum), '|') < match(getline(lnum+1), '|')
        normal j
        call cursor('.', match(getline('.'), '|') + 1)
    endif
    call Voof_TreeSelect(line('.'), 'tree')
endfunc


func! Voof_TreeNextMark(back) "{{{3
" Go to next or previous marked node.
    if a:back==1
        normal! 0
        let found = search('\C\v^.x', 'bw')
    else
        let found = search('\C\v^.x', 'w')
    endif

    if found==0
        call Voof_WarningMsg("VOOF: there are no marked nodes")
    else
        call Voof_TreeZV()
        call cursor('.', match(getline('.'), '|') + 1)
        call Voof_TreeSelect(line('.'), 'tree')
    endif
endfunc


"---Outline Operations---{{{2
"
func! Voof_OopEdit() "{{{3
" Edit headline text: move into Body, put cursor on headline.
    let tree = bufnr('')
    let body = s:voof_trees[tree]
    let lnum = line('.')
    if lnum==1 | return | endif
    if Voof_OopBodyEditable(body)==-1 | return | endif
    " find first word char
    let firstCharIdx = match(getline('.')[3:], '\w')
    if firstCharIdx!=-1
        let firstChar = getline('.')[3:][firstCharIdx]
    endif
    py vim.command("let bLnr=%s" %VOOF.nodes[int(vim.eval('body'))][int(vim.eval('lnum'))-1])

    let lz_ = &lz | set lz
    if Voof_ToBody(body,'')==-1 | let &lz=lz_ | return | endif
    if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif
    exe 'normal! ' . bLnr.'G0'
    normal! zv
    " put cursor on first word char
    if firstCharIdx!=-1 && getline('.')[0]!=firstChar
        exe 'normal! f'.firstChar
    endif
    let &lz=lz_
endfunc


func! Voof_OopInsert(as_child) "{{{3
" Insert new node.
    let tree = bufnr('')
    let body = s:voof_trees[tree]
    if Voof_OopBodyEditable(body)==-1 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    if ln_status=='hidden'
        call Voof_WarningMsg("VOOF: CAN'T RUN COMMAND (cursor hidden in fold)")
        return
    endif

    let lz_ = &lz | set lz
    if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
    if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif
    call Voof_OopFromBody(body,tree, -1)

    setl ma
    if a:as_child=='as_child'
        keepj py voof.oopInsert(as_child=True)
    else
        keepj py voof.oopInsert(as_child=False)
    endif
    setl noma

    let snLn = s:voof_bodies[body].snLn
    exe "normal! ".snLn."G"
    call Voof_TreePlaceCursor()
    call Voof_TreeZV()

    if Voof_ToBody(body,'')==-1 | let &lz=lz_ | return | endif
    exe "normal! ".bLnum."G"
    normal! zvzz3l
    let &lz=lz_
    "let s:voof_bodies[body].tick_ = b:changedtick
    "if g:voof_verify_oop==1
        "py voof.voofVerify(int(vim.eval('body')))
    "endif
endfunc


func! Voof_OopPaste() "{{{3
" Paste nodes in the clipboard.
    let tree = bufnr('')
    let body = s:voof_trees[tree]
    if Voof_OopBodyEditable(body)==-1 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    if ln_status=='hidden'
        call Voof_WarningMsg("VOOF: CAN'T RUN COMMAND (cursor hidden in fold)")
        return
    endif

    let lz_ = &lz | set lz
    if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
    if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

    call setbufvar(tree, '&ma', 1)
    keepj py voof.oopPaste()
    call setbufvar(tree, '&ma', 0)

    call Voof_OopFromBody(body,tree, l:blnShow)
    " no pasting was done
    if l:blnShow==-1
        let &lz=lz_
        return
    endif

    let s:voof_bodies[body].snLn = l:ln1
    if l:ln1==l:ln2
        call Voof_OopShowTree(l:ln1, l:ln2, 'n')
    else
        call Voof_OopShowTree(l:ln1, l:ln2, 'v')
    endif
    let &lz=lz_

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif
endfunc


func! Voof_OopMark(op, mode) "{{{3
" Mark or unmark current node or all nodes in selection

    " Checks and init vars. {{{
    let tree = bufnr('')
    let body = s:voof_trees[tree]
    if Voof_OopBodyEditable(body)==-1 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        call Voof_WarningMsg("VOOF: CAN'T RUN COMMAND (cursor hidden in fold)")
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
    if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
    if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

    call setbufvar(tree, '&ma', 1)
    if a:op=='mark'
        keepj py voof.oopMark()
    elseif a:op=='unmark'
        keepj py voof.oopUnmark()
    endif
    call setbufvar(tree, '&ma', 0)

    call Voof_OopFromBody(body,tree, 0)
    let &lz=lz_

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif
endfunc


func! Voof_OopMarkSelected() "{{{3
" Mark or unmark current node or all nodes in selection
    let tree = bufnr('')
    let body = s:voof_trees[tree]
    if Voof_OopBodyEditable(body)==-1 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        call Voof_WarningMsg("VOOF: CAN'T RUN COMMAND (cursor hidden in fold)")
        return
    endif
    if ln==1
        return
    endif

    let lz_ = &lz | set lz
    if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
    if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

    call setbufvar(tree, '&ma', 1)
    keepj py voof.oopMarkSelected()
    call setbufvar(tree, '&ma', 0)

    call Voof_OopFromBody(body,tree, 0)
    let &lz=lz_

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif
endfunc


func! Voof_Oop(op, mode) "{{{3
" Outline operations that can be perfomed on current node or on nodes in visual
" selection. All apply to trees, not to single nodes.

    " Checks and init vars. {{{
    let tree = bufnr('')
    let body = s:voof_trees[tree]
    if a:op!='copy' && Voof_OopBodyEditable(body)==-1 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    if ln_status=='hidden'
        call Voof_WarningMsg("VOOF: CAN'T RUN COMMAND (cursor hidden in fold)")
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
        " before op: move cursor to ln1 or ln2
    endif
    " don't touch first line
    if ln1==1 | return | endif
    " set ln2 to last node in current tree of last tree in selection
    " check validity of selection
    py vim.command('let ln2=%s' %voof.oopSelEnd())
    if ln2==0
        call Voof_WarningMsg("VOOF: INVALID TREE SELECTION")
        return
    endif
    " }}}

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

        if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
        if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj py voof.oopUp()
        call setbufvar(tree, '&ma', 0)

        call Voof_OopFromBody(body,tree, l:blnShow)

        let s:voof_bodies[body].snLn = lnUp1
        let lnEnd = lnUp1+ln2-ln1
        call Voof_OopShowTree(lnUp1, lnEnd, a:mode)
        " }}}

    elseif a:op=='down' " {{{
        if ln2==line('$') | let &lz=lz_ | return | endif
        " must be on the last node of current tree or last tree in selection
        exe "normal! ".ln2."G"
        " line after which to insert
        normal! j
        let lnDn1 = line('.') " should be ln2+1
        let lnDn1_status = Voof_FoldStatus(lnDn1)

        if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
        if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj py voof.oopDown()
        call setbufvar(tree, '&ma', 0)

        call Voof_OopFromBody(body,tree, l:blnShow)

        let s:voof_bodies[body].snLn = l:snLn
        let lnEnd = snLn+ln2-ln1
        call Voof_OopShowTree(snLn, lnEnd, a:mode)
        " }}}

    elseif a:op=='right' " {{{
        if ln1==2 | let &lz=lz_ | return | endif

        if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
        if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj py voof.oopRight()
        call setbufvar(tree, '&ma', 0)

        call Voof_OopFromBody(body,tree, l:blnShow)
        " can't move right
        if l:blnShow==-1
            let &lz=lz_
            return
        endif

        let s:voof_bodies[body].snLn = ln1
        call Voof_OopShowTree(ln1, ln2, a:mode)
        " }}}

    elseif a:op=='left' " {{{
        if ln1==2 | let &lz=lz_ | return | endif

        if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
        if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj py voof.oopLeft()
        call setbufvar(tree, '&ma', 0)

        call Voof_OopFromBody(body,tree, l:blnShow)
        " can't move left
        if l:blnShow==-1
            let &lz=lz_
            return
        endif

        let s:voof_bodies[body].snLn = ln1
        call Voof_OopShowTree(ln1, ln2, a:mode)
        " }}}

    elseif a:op=='copy' " {{{
        if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
        if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

        keepj py voof.oopCopy()

        call Voof_OopFromBody(body,tree, -1)
        "}}}

    elseif a:op=='cut' " {{{
        if a:mode=='v'
            " must be on first line of selection
            exe "normal! ".ln1."G"
        endif
        " new snLn
        normal! k
        let lnUp1 = line('.')

        if Voof_ToBody(body,'noa')==-1 | let &lz=lz_ | return | endif
        if Voof_BodyCheckTicks(body)==-1 | let &lz=lz_ | return | endif

        call setbufvar(tree, '&ma', 1)
        keepj py voof.oopCut()
        call setbufvar(tree, '&ma', 0)

        call Voof_OopFromBody(body,tree, l:blnShow)
        let s:voof_bodies[body].snLn = lnUp1
        " }}}
    endif
    let &lz=lz_

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif
endfunc


func! Voof_OopBodyEditable(body) "{{{3
" Check if Body is noma or ro before outline operation.
" This also catches if Body doesn't exist.
    if getbufvar(a:body, "&ma")==0 || getbufvar(a:body, "&ro")==1
        let bname = fnamemodify(bufname(a:body), ":t")
        call Voof_ErrorMsg("VOOF: Body buffer ".a:body." (".bname.") is not editable")
        return -1
    endif
endfunc


func! Voof_OopFromBody(body, tree, blnr) "{{{3
" Called from Body after outline operations.
" Set ticks, Show node (or just line) blnr. Go back to tree.
" Special blnr values:
"   -1 --don't set ticks and don't show node.
"    0 --set ticks, but don't show node.
"
    if a:blnr >= 0
        " adjust changedtick to suppress TreeUpdate
        let s:voof_bodies[a:body].tick_ = b:changedtick
        let s:voof_bodies[a:body].tick  = b:changedtick
    endif
    if a:blnr>0
        " show fold at blnr
        exe 'normal '.a:blnr.'G'
        if &fdm==#'marker'
            normal! zMzvzt
        else
            normal! zt
        endif
    endif

    " go back to Tree window, which should be previous window
    let wnr_ = winnr('#')
    if winbufnr(wnr_)==a:tree
        exe 'noautocmd '.wnr_.'wincmd w'
    else
        exe 'noautocmd '.bufwinnr(a:tree).'wincmd w'
    endif
    if bufnr('')!=a:tree
        throw 'This is not Tree!'
    endif
endfunc


func! Voof_OopShowTree(ln1, ln2, mode) " {{{3
" Adjust Tree view after an outline operation.
" ln1 and ln2 are first and last line of the range.
"
" After outline operation Tree folds in the affected range are usually
" completely expanded. To be consistent: close all folds in the range
" (select range, zC, show first line).
"
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
    call Voof_TreeZV()
    call Voof_TreePlaceCursor()

    " restore visual mode selection
    if a:mode=='v'
        normal! gv
    endif
endfunc


"---BODY BUFFERS----------------------{{{1
"
"---Body augroup---{{{2
augroup VoofBody
    " Body autocommands are buffer-local
augroup END


func! Voof_BodyConfigure() "{{{2
" Configure current buffer as a Body buffer.
    augroup VoofBody
        au! * <buffer>
        au BufLeave  <buffer> call Voof_BodyBufLeave()
        au BufUnload <buffer> nested call Voof_BodyBufUnload()
    augroup END

    " redundant: will be set on BufLeave
    let s:voof_bodies[bufnr('')].tick = b:changedtick

    let cpo_ = &cpo | set cpo&vim
    exe "nnoremap <buffer><silent> ".g:voof_return_key." :<C-u>call Voof_BodySelect()<CR>"
    exe "nnoremap <buffer><silent> ".g:voof_tab_key.   " :<C-u>call Voof_ToTreeOrBodyWin()<CR>"
    let &cpo = cpo_
    let b:voof_body = 1
endfunc


func! Voof_BodyBufLeave() "{{{2
" Body's BufLeave au.
" getbufvar() doesn't work with b:changedtick (why?), thus the need for this au
    let body = bufnr('')
    let s:voof_bodies[body].tick = b:changedtick
endfunc


func! Voof_BodyBufUnload() "{{{2
" Body's BufUnload au. Wipe out Tree and clean up.
    let body = expand("<abuf>")
    if !exists("s:voof_bodies") || !has_key(s:voof_bodies, body)
        echoerr "VOOF: internal error"
        return
    endif
    let tree = s:voof_bodies[body].tree
    if !exists("s:voof_trees") || !has_key(s:voof_trees, tree)
        echoerr "VOOF: internal error"
        return
    endif
    call Voof_UnVoof(body,tree)
endfunc


func! Voof_BodySelect() "{{{2
" Select current Body node. Show corresponding line in the Tree.
" Stay in the Tree if the node is already selected.
    let body = bufnr('')
    " Tree has been wiped out.
    if !has_key(s:voof_bodies, body)
        call Voof_BodyUnMap()
        return
    endif

    let wnr_ = winnr()
    let tree = s:voof_bodies[body].tree
    let blnr = line('.')
    let blnr_ = s:voof_bodies[body].blnr
    let s:voof_bodies[body].blnr = blnr

    let bchangedtick = b:changedtick
    " Go to Tree. Outline will be updated on BufEnter.
    if Voof_ToTree(tree)==-1 | return | endif
    " Check for ticks.
    if s:voof_bodies[body].tick_!=bchangedtick
        exe bufwinnr(body).'wincmd w'
        call Voof_BodyCheckTicks(body)
        return
    endif

    " voofUpdate() sets = mark and may change snLn to a wrong value if outline was modified from Body.
    let snLn_ = s:voof_bodies[body].snLn
    " Compute new and correct snLn with updated outline.
    py voof.computeSnLn(int(vim.eval('body')), int(vim.eval('s:voof_bodies[body].blnr')))
    let snLn = s:voof_bodies[body].snLn

    call Voof_TreeToLine(snLn)
    " Node has not changed. Stay in Tree.
    if snLn==snLn_
        return
    endif

    " Node has changed. Draw marks. Go back.
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


func! Voof_BodyUpdateTree() "{{{2
" Current buffer is a Body. Update outline and Tree.
    "let start = reltime()
    let body = bufnr('')
    if !has_key(s:voof_bodies, body)
        call Voof_WarningMsg('VOOF: current buffer is not Body')
        return -1
    endif

    let tree = s:voof_bodies[body].tree

    " paranoia
    if !bufloaded(tree)
        call Voof_UnVoof(body,tree)
        echoerr "VOOF: Tree buffer" tree "was not loaded or didn't exist. Cleanup has been performed."
        return -1
    endif

    """" update is not needed
    if s:voof_bodies[body].tick_==b:changedtick
        return
    endif

    """" do update
    call setbufvar(tree, '&ma', 1)
    let ul_=&ul | setl ul=-1
    try
        keepj py voof.voofUpdate(int(vim.eval('body')))
        let s:voof_bodies[body].tick_ = b:changedtick
        let s:voof_bodies[body].tick  = b:changedtick
    finally
        " Why: &ul is global, but this causes 'undo list corrupt' error
        "let &ul=ul_
        call setbufvar(tree, '&ul', ul_)
        call setbufvar(tree, '&ma', 0)
    endtry
    "echom reltimestr(reltime(start))
endfunc


func! Voof_BodyUnMap() "{{{2
" Remove Body local mappings. Must be called from Body.
    unlet! b:voof_body
    let cpo_ = &cpo | set cpo&vim
    exe "nunmap <buffer> ".g:voof_return_key
    exe "nunmap <buffer> ".g:voof_tab_key
    let &cpo = cpo_
endfunc


func! Voof_BodyCheckTicks(body) "{{{2
" Current buffer is Body body. Check ticks assuming that outline is up to date,
" as after going to Body from Tree.
" note: 'abort' argument is not needed and would be counterproductive

    " paranoia
    if bufnr('')!=a:body
        echoerr 'VOOF: WRONG BUFFER!'
        return -1
    endif

    " Outline is invalid. Bail out.
    if s:voof_bodies[a:body].tick_!=b:changedtick
        let tree = s:voof_bodies[a:body].tree
        if !exists("s:voof_trees") || !has_key(s:voof_trees, tree)
            echoerr "VOOF: internal error"
            return -1
        endif
        call Voof_UnVoof(a:body,tree)
        echoerr 'VOOF: WRONG TICKS IN BODY BUFFER '.a:body.'! CLEANUP HAS BEEN PERFORMED.'
        return -1
    endif
endfunc


"---Tree or Body----------------------{{{1
"
func! Voof_UnVoof(body,tree) "{{{2
" Delete Voof data, wipeout Tree, etc.
" Can be called from any buffer.
" Note: when called from Tree BufUnload au, tree doesn't exist.
    " Remove VOOF data for Body body and its Tree tree.
    if has_key(s:voof_trees, a:tree)
        unlet s:voof_trees[a:tree]
    endif
    if has_key(s:voof_bodies, a:body)
        unlet s:voof_bodies[a:body]
    endif
    py voof.voof_UnVoof()

    exe 'au! VoofBody * <buffer='.a:body.'>'
    if bufexists(a:tree)
        exe 'noautocmd bwipeout '.a:tree
    endif
    if bufnr('')==a:body
        call Voof_BodyUnMap()
    endif
endfunc


func! Voof_GetUNL() "{{{2
" Display UNL (Uniformed Node Locator) of current node.
" Copy UNL to register 'n'.
" This can be called from any buffer.
"
    let bnr = bufnr('')
    let lnum = line('.')

    if has_key(s:voof_trees, bnr)
        let buftype = 'tree'
        let body = s:voof_trees[bnr]
    elseif has_key(s:voof_bodies, bnr)
        let buftype = 'body'
        let body = bnr
        " update outline
        if Voof_BodyUpdateTree()==-1 | return | endif
    else
        call Voof_WarningMsg("VOOF (Voofunl): current buffer is neither Tree nor Body")
        return
    endif

    py voof.voof_GetUNL()
endfunc


func! Voof_Grep(pattern) "{{{2
" Seach Body for pattern and show list of nodes with matches.
" Number of matches is limited to first 1000.
" Search register is set to pattern.
"
    "let start = reltime()
    if a:pattern==''
        let pattern = expand('<cword>')
        let pattern = substitute(pattern, '\s\+$', '', '')
        if pattern=='' | return | endif
        let pattern = '\<'.pattern.'\>'
    else
        let pattern = substitute(a:pattern, '\s\+$', '', '')
        if pattern=='' | return | endif
    endif
    "echo '"'.pattern.'"'

    """ Search must be done in Body buffer. Move to Body if in Tree.
    let bnr = bufnr('')
    if has_key(s:voof_trees, bnr)
        let body = s:voof_trees[bnr]
        if Voof_ToBody(body,'')==-1 | return | endif
        if Voof_BodyCheckTicks(body)==-1 | return | endif
    elseif has_key(s:voof_bodies, bnr)
        let body = bnr
        " update outline
        if Voof_BodyUpdateTree()==-1 | return | endif
    else
        call Voof_WarningMsg("VOOF (Voofgrep): current buffer is neither Tree nor Body")
        return
    endif

    " Problem: there is no search highlight after :noh
    let @/ = pattern

    """ Search current buffer for pattern. Limit to first 1000 matches.
    let lz_ = &lz | set lz
    let winsave_dict = winsaveview()
    " search from start
    keepj normal! gg0
    let matches = []
    " special effort needed to detect match at cursor
    if searchpos(pattern, 'nc')==[1,1]
        call add(matches,1)
    endif
    " do search
    let found = 1
    while found>0 && len(matches)<1000
        let found = search(pattern, 'W')
        call add(matches, found)
    endwhile
    call winrestview(winsave_dict)
    " without this, current line jumps to top after :copen
    call winline()
    let &lz=lz_

    " this signals that search was terminated after 1000 matches were found
    if matches[-1]!=0
        call add(matches,-1)
    endif

    if matches==[0]
        call Voof_WarningMsg('VOOF (Voofgrep): pattern not found: '.pattern)
        "py print 'VOOF (Voofgrep): pattern not found: '+vim.eval('pattern')
        return
    endif

    """ set and display quickfix list
    exe "call setqflist([{'text':'Voofgrep ". substitute(pattern,"'","''",'g') ."'}])"
    if matches[-1]==-1
        call setqflist([{'text':'seach stopped after 1000 matches'}], 'a')
    else
        exe "call setqflist([{'text':'". (len(matches)-1) ." matches'}], 'a')"
    endif

    py voof.voof_Grep()
    botright copen
    "echo reltimestr(reltime(start))
endfunc


"---LOG BUFFER (Vooflog)--------------{{{1
"
func! Voof_LogInit() "{{{2
" Redirect Python stdout and stderr to Log buffer.
    let bnr_ = bufnr('')
    """" Log buffer exists, show it.
    if exists('s:voof_logbnr')
        if !bufloaded(s:voof_logbnr)
            py sys.stdout, sys.stderr = VOOF.vim_stdout, VOOF.vim_stderr
            py if 'pydoc' in sys.modules: del sys.modules['pydoc']
            if bufexists(s:voof_logbnr)
                exe 'noautocmd bwipeout '.s:voof_logbnr
            endif
            let bnr = s:voof_logbnr
            unlet s:voof_logbnr
            echoerr "VOOF: PyLog buffer" bnr "was not shut down properly. Cleanup has been performed. Run Vooflog command again."
            return
        endif
        if bufwinnr(s:voof_logbnr)==-1
            call Voof_ToLogWin()
            silent exe 'b'.s:voof_logbnr
            normal! G
            exe bufwinnr(bnr_).'wincmd w'
        endif
        return
    endif

    """" Create Log buffer.
    call Voof_ToLogWin()
    silent edit __PyLog__
    let s:voof_logbnr=bufnr('')
    " Configure Log buffer
    setl cul nocuc list wrap
    setl ft=log
    setl noro ma ff=unix
    setl nobuflisted buftype=nofile noswapfile bufhidden=hide
    call Voof_LogSyntax()
    au BufUnload <buffer> call Voof_LogBufUnload()
python << EOF
# this is done once in Initialize
#VOOF.vim_stdout, VOOF.vim_stderr = sys.stdout, sys.stderr
sys.stdout = sys.stderr = voof.LogBufferClass()
if 'pydoc' in sys.modules: del sys.modules['pydoc']
EOF
    " Go back.
    exe bufwinnr(bnr_).'wincmd w'
endfunc


func! Voof_LogBufUnload() "{{{2
    if !exists('s:voof_logbnr') || expand("<abuf>")!=s:voof_logbnr
        echoerr 'VOOF: internal error'
        return
    endif
    py sys.stdout, sys.stderr = VOOF.vim_stdout, VOOF.vim_stderr
    py if 'pydoc' in sys.modules: del sys.modules['pydoc']
    exe 'bwipeout '.s:voof_logbnr
    unlet! s:voof_logbnr
endfunc


func! Voof_LogSyntax() "{{{2
" Syntax highlighting for common messages in the Log.

    " Python tracebacks
    syn match WarningMsg /^Traceback (most recent call last):/
    syn match Type /^\u\h*Error/

    " VOOF messages
    syn match WarningMsg /^VOOF.*/

    syn match PreProc /^---end of Python script---/
    syn match PreProc /^---end of Vim script---/

    " -> UNL separator
    syn match Title / -> /

    syn match Type /^vim\.error/
    syn match WarningMsg /^Vim.*:E\d\+:.*/
endfunc


func! Voof_LogScroll() "{{{2
" Scroll windows with the __PyLog__ buffer.
" All tabs are searched, but only the first found Log window in a tab is scrolled.
" Uses noautocmd when entering tabs and windows.
" Note: careful with Python here: an error can cause recursive call.

    " can't go to other windows when in Ex mode (after 'Q' or 'gQ')
    if mode()=='c' | return | endif

    " This should never happen.
    if !exists('s:voof_logbnr') || !bufloaded(s:voof_logbnr)
        echoerr "VOOF: internal error"
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
            if bnr==s:voof_logbnr
                let log_found=1
                exe 'noautocmd tabnext '.tnr
                " save tab's current window and previous window numbers
                let wnr__ = winnr()
                let wnr__p = winnr('#')
                " move to window with buffer bnr
                exe 'noautocmd '. bufwinnr(bnr).'wincmd w'
                normal G
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
        call Voof_ToLogWin()
        exe 'b '.s:voof_logbnr
        normal G
        " Return to original tab and buffer.
        exe 'tabn '.tnr_
        exe bufwinnr(bnr_).'wincmd w'
    endif
    let &lz=lz_
endfunc


"---RUN SCRIPT (Voofrun)--------------{{{1
"
func! Voof_GetLines(lnum) "{{{2
" Return list of lines.
" Tree buffer: lines from Body node (including subnodes) corresponding to Tree
" line lnum.
" Any other buffer: lines from fold at line lnum (including subfolds).
" Return [] if checks fail.

    """"" Tree buffer: get lines from corresponding node.
    if has_key(s:voof_trees, bufnr(''))
        let status = Voof_FoldStatus(a:lnum)
        if status=='hidden'
            call Voof_WarningMsg('VOOF: current line hidden in fold')
            return []
        endif
        let body = s:voof_trees[bufnr('')]

        " this computes and assigns nodeStart and nodeEnd
        py voof.voof_GetLines()
        "echo [nodeStart, nodeEnd]
        return getbufline(body, nodeStart, nodeEnd)
    endif

    """"" Regular buffer: get lines from current fold.
    if &fdm !=# 'marker'
        call Voof_WarningMsg('VOOF: ''foldmethod'' must be "marker"')
        return []
    endif
    let status = Voof_FoldStatus(a:lnum)
    if status=='nofold'
        call Voof_WarningMsg('VOOF: no fold')
        return []
    elseif status=='hidden'
        call Voof_WarningMsg('VOOF: current line hidden in fold')
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


func! Voof_GetLines1() "{{{2
" Return list of lines from current node.
" This is for use by external scripts. Can be called from any buffer.
" Return [-1] if current buffer is neither Tree nor Body.
    let lnum = line('.')
    let bnr = bufnr('')
    if has_key(s:voof_trees, bnr)
        let buftype = 'tree'
        let body = s:voof_trees[bnr]
    elseif has_key(s:voof_bodies, bnr)
        let buftype = 'body'
        let body = bnr
        let tree = s:voof_bodies[body].tree
        if Voof_BodyUpdateTree()==-1
            return [-1]
        endif
    else
        "echo "VOOF: current buffer is neither Tree nor Body"
        return [-1]
    endif

    py voof.voof_GetLines1()
    return getbufline(body, l:bln1, l:bln2)
endfunc


func! Voof_Run(qargs) "{{{2
" Execute lines from the current fold (non-Tree buffer, include subfolds) or
" node (Tree buffer, include subnodes) as a script.
" First argument is 'vim' or 'py': execute as Vim or Python script respectively.
" Otherwise execute according to filetype.

    let lines = Voof_GetLines(line('.'))
    if lines==[] | return | endif

    " Determine type of script: Vim or Python.
    let scriptType = ''

    " this is a Tree
    if has_key(s:voof_trees, bufnr(''))
        let ft = getbufvar(s:voof_trees[bufnr('')], '&ft')
    " this is not a Tree
    else
        let ft = &ft
    endif

    if     a:qargs==#'vim'
        let scriptType = 'vim'
    elseif a:qargs==#'py' || a:qargs==#'python'
        let scriptType = 'python'
    elseif ft==#'vim'
        let scriptType = 'vim'
    elseif ft==#'python'
        let scriptType = 'python'
    else
        call Voof_WarningMsg("VOOF: can't determine script type")
        return
    endif

    " Run Vim script: Copy list of lines to register and execute it.
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
            call Voof_ErrorMsg(v:exception)
        endtry
        call setreg('z', reg_z, reg_z_mode)
    " Run Python script: write lines to a .py file and do execfile().
    elseif scriptType==#'python'
        call writefile(lines, s:voof_script_py)
        py voof.runScript()
    endif
endfunc


"---Commands--------------------------{{{1
" Main Voof commands should be defined in Quickload section.
com! Voofunl  call Voof_GetUNL()
com! -nargs=? Voofgrep  call Voof_Grep(<q-args>)

"com! VoofPrintData  call Voof_PrintData()
"
"" source voof.vim, reload voof.py
"com! VoofReload    exe 'so '.s:voof_path.' | py reload(voof)'
"
"" source voof.vim
"com! VoofReloadVim exe 'so '.s:voof_path
"
"" reload voof.py
"com! VoofReloadPy  py reload(voof)
"
"" complete reload: delete Trees and Voof data, source voof.vim, reload voof.py
"com! VoofReloadAll call Voof_ReloadAllPre() | exe 'so '.s:voof_path | call Voof_Init()

" modelines {{{1
" vim:fdm=marker:fdl=0
" vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart)
