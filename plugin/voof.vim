" voof.vim
" VOOF (Vim Outliner Of Folds): two-pane outliner and related utilities
" plugin for Python-enabled Vim version 7.x
" Home: http://www.vim.org/scripts/script.php?script_id=2657
" Author: Vlad Irnov  (vlad DOT irnov AT gmail DOT com)
" License: this software is in the public domain
" Version: 1.4, 2009-07-13

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
" snLn      --selected node line number, a Tree line number
" var_      --previous value of var

"---Quickload-------------------------{{{1
if !exists('g:voof_did_load')
    let g:voof_did_load = 1
    com! Voof call Voof_Init()
    com! Vooflog call Voof_LogInit()
    com! Voofhelp call Voof_Help()
    com! -nargs=? Voofrun call Voof_Run(<f-args>)
    exe "au FuncUndefined Voof_* source " . expand("<sfile>:p")
    finish
endif

"---Initialize------------------------{{{1
if !exists('g:voof_did_init')
    let g:voof_did_init = 1
    au! FuncUndefined Voof_*
    let g:voof_path = expand("<sfile>:p")
    let g:voof_dir = expand("<sfile>:p:h")
    let g:voof_script_py = g:voof_dir.'/voofScript.py'
python << EOF
import vim
import sys
voof_dir = vim.eval('g:voof_dir')
if not voof_dir in sys.path:
    sys.path.append(voof_dir)
import voof
VOOF = sys.modules['voof'].VOOF = voof.VoofData()
EOF
    " {tree : associated body,  ...}
    let g:voof_trees = {}
    " {body : {'tree' : associated tree,
    "          'blnr' : Body line number,
    "          'snLn' : selected node line number,
    "          'tick' : b:changedtick of Body,
    "          'tick_' : b:changedtick of Body on last Tree update}, {...}, ... }
    let g:voof_bodies = {}
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
    if has_key(g:voof_trees, body) | return | endif

    if !has_key(g:voof_bodies, body)
    " There is no Tree for this Body. Create it.
        let g:voof_bodies[body] = {}
        let g:voof_bodies[body].blnr = line('.')
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
        let tree = g:voof_bodies[body].tree
        call Voof_ToTree(tree)
    endif
endfunc

func! Voof_UnVoof(body, tree) "{{{2
" Remove VOOF data for Body body and its Tree tree.
    unlet g:voof_trees[a:tree]
    unlet g:voof_bodies[a:body]
    py voof.voof_UnVoof()
endfunc

func! Voof_BufEditable(bnr) "{{{2
" Check if buffer bnr is noma or ro.
    let ma_opt = getbufvar(a:bnr, "&ma")
    let ro_opt = getbufvar(a:bnr, "&ro")
    if ma_opt==0 || ro_opt==1
        py print "VOOF: Body buffer is 'nomodifiable' and/or 'readonly'"
        return 0
    else
        return 1
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

func! Voof_Help() "{{{2
" Display voof.txt as outline in new tabpage.
    let bnr = bufnr('')
    " already in voof.txt
    "if expand("%:t")=='voof.txt'
    if fnamemodify(bufname(bnr), ":t")=='voof.txt'
        return
    " in Tree for voof.txt
    elseif has_key(g:voof_trees, bnr) && fnamemodify(bufname(g:voof_trees[bnr]), ":t")=='voof.txt'
        return
    endif

    " look for voof.txt in script dir first
    let voof_help = g:voof_dir.'/voof.txt'
    if !filereadable(voof_help)
        " voof.vim should be in /plugin; look for voof.txt in /doc
        let tail = fnamemodify(g:voof_dir, ":t")
        if tail=='plugin'
            let voof_help = fnamemodify(g:voof_dir, ":h") . '/doc/voof.txt'
            if !filereadable(voof_help)
                let voof_help = 'None'
            endif
        else
            let voof_help = 'None'
        endif
    endif

    if voof_help=='None'
        echo 'VOOF: cannot find "voof.txt"'
        return
    endif

    exe 'tabnew '.voof_help
    Voof
    normal! zR
endfunc

func! Voof_ReloadAllPre() "{{{2
" Helper for reloading entire plugin.
    update
    " wipe out all Tree buffers
    for bnr in keys(g:voof_trees)
        if bufexists(str2nr(bnr))
            exe 'bw '.bnr
        endif
    endfor
    py reload(voof)
    unlet g:voof_did_init
endfunc

"---Windows Navigation and Creation---{{{1
" These deal only with the current tab page.
"
func! Voof_ToTreeOrBodyWin() "{{{2
" Current buffer is Body or Tree. Go to next window with corresponding Tree or
" Body or with the same buffer.
    let bnr = bufnr('')
    if has_key(g:voof_trees, bnr)
        let tree = bnr
        let body = g:voof_trees[tree]
    else
        let body = bnr
        " Tree doesn't exist. Should never happen.
        if !has_key(g:voof_bodies, body)
            call Voof_BodyUnVoof()
            return
        endif
        let tree = g:voof_bodies[body].tree
    endif

    let wnr_ = winnr()
    while 1
        wincmd w
        if bufnr('')==body || bufnr('')==tree || winnr()==wnr_
            break
        endif
    endwhile
endfunc

func! Voof_ToTreeWin() "{{{2
" Move to window or open a new one where a Tree will be loaded.

    " Allready in a Tree buffer.
    if has_key(g:voof_trees, bufnr('')) | return | endif

    " Look for any window with a Tree buffer.
    for bnr in tabpagebuflist()
        if has_key(g:voof_trees, bnr)
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

func! Voof_ToTree(tree) "{{{2
" Move cursor to window with Tree buffer a:tree or load it in a new window.

    " Already there.
    if bufnr('')==a:tree | return 1 | endif

    " Try previous window.
    let wnr = winnr('#')
    if wnr<=winnr('$') && winbufnr(wnr)==a:tree
        exe wnr.'wincmd w'
        return 1
    endif

    " There is window with buffer a:tree .
    if bufwinnr(a:tree)!=-1
        exe bufwinnr(a:tree).'wincmd w'
        return 1
    endif

    " Make sure buffer exists before loading it.
    if !bufexists(a:tree)
        " because of au, this should never happen
        echoerr "VOOF: Tree buffer doesn't exist: " . a:tree
        return 2
    endif

    " Create new window and load there.
    call Voof_ToTreeWin()
    silent exe 'b'.a:tree
    " Must set options local to window.
    setl foldenable
    setl foldtext=getline(v:foldstart).'\ \ \ /'.(v:foldend-v:foldstart)
    setl foldmethod=expr
    setl foldexpr=Voof_TreeFoldexpr(v:lnum)
    setl cul nocuc nowrap list
    "setl winfixheight
    setl winfixwidth
    return 0
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

func! Voof_ToBody(body) "{{{2
" Move to window with Body a:body or load it in a new window.

    " Allready there.
    if bufnr('')==a:body | return 1 | endif

    " Try previous window.
    let wnr = winnr('#')
    if wnr<=winnr('$') && winbufnr(wnr)==a:body
        exe wnr.'wincmd w'
        return 1
    endif

    " There is a window with buffer a:body .
    if bufwinnr(a:body)!=-1
        exe bufwinnr(a:body).'wincmd w'
        return 1
    endif

    " Make sure buffer exists before loading it.
    if !bufexists(a:body)
        " because of au, this should never happen
        echoerr "VOOF: Body buffer doesn't exist: " . a:body
        return 2
    endif

"    " Load in the first window with a non-Tree buffer.
"    for bnr in tabpagebuflist()
"         if !has_key(g:voof_trees, bnr)
"            exe bufwinnr(bnr).'wincmd w'
"            exe 'b'.a:body
"            return 1
"        endif
"    endfor

    " Create new window and load there.
    call Voof_ToBodyWin()
    exe 'b'.a:body
    return 0
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
func! Voof_TreeFoldexpr(lnum) "{{{2
" 'foldexpr' function for emulating tree widget.
    " match() is affected by encoding, but probably not in this case.
    let indent   = (match(getline(a:lnum)  , '|')) / 2
    let indentn  = (match(getline(a:lnum+1), '|')) / 2

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

    " Suppress Tree update function that runs of BufEnter.
    let g:voof_TreeUpdate = 0

    let b_name = fnamemodify(bufname(a:body),":t")
    if b_name=='' | let b_name='NoName' | endif
    silent exe 'edit '.b_name.'_VOOF'.a:body
    let tree = bufnr('')

    " Initialize VOOF data.
    let g:voof_bodies[a:body].tree = tree
    let g:voof_trees[tree] = a:body
    let g:voof_bodies[a:body].tick_ = g:voof_bodies[a:body].tick

    call Voof_TreeConfigure()

    " Draw lines.
    setl ma
    let ul_=&ul | setl ul=-1

    keepj py voof.treeUpdate(int(vim.eval('a:body')))

    " Draw = mark. This must be done afer creating outline.
    " this assigns g:voof_bodies[body].snLn
    py voof.voof_TreeCreate()
    let snLn = g:voof_bodies[a:body].snLn
    " Initial draw puts = on first line.
    if snLn!=1
        keepj call setline(snLn, '='.getline(snLn)[1:])
        keepj call setline(1, ' '.getline(1)[1:])
    endif

    let &ul=ul_
    setl noma

    " Show current position.
    exe 'normal! ' . snLn . 'G'
    call Voof_TreeZV()
    call Voof_TreePlaceCursor()
    if exists('l:blnShow')
        call Voof_OopShowBody(a:body, blnShow)
    endif
endfunc

func! Voof_TreeConfigure() "{{{2
" Configure current buffer as a Tree buffer.

    " Options local to window.
    setl foldenable
    setl foldtext=getline(v:foldstart).'\ \ \ /'.(v:foldend-v:foldstart)
    setl foldmethod=expr
    setl foldexpr=Voof_TreeFoldexpr(v:lnum)
    setl cul nocuc nowrap list
    "setl winfixheight
    setl winfixwidth

    " This should allow customizing via ftplugin. Removes syntax hi.
    setl ft=vooftree

    " Options local to buffer.
    setl buftype=nofile noswapfile bufhidden=hide
    setl noro ma ff=unix noma

    " Syntax.
    " first line
    syn match Title /\%1l.*/
    " line comment chars: "  #  //  /*  %  <!--
    syn match Comment @|\zs\%("\|#\|//\|/\*\|%\|<!--\).*@ contains=Todo
    " keywords
    syn match Todo /\%(TODO\|Todo\)/

    "augroup VoofTree
        ""au!
        "au BufEnter   <buffer> call Voof_TreeBufEnter()
        "au BufUnload  <buffer> call Voof_TreeBufUnload()
    "augroup END

    call Voof_TreeMap()
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
    nnoremap <buffer><silent> i :call Voof_OopEdit()<CR>
    nnoremap <buffer><silent> I :call Voof_OopEdit()<CR>
    nnoremap <buffer><silent> a :call Voof_OopEdit()<CR>
    nnoremap <buffer><silent> A :call Voof_OopEdit()<CR>
    " }}}

    " Node selection and navigation. {{{

    exe "nnoremap <buffer><silent> ".g:voof_return_key." :call Voof_TreeSelect(line('.'), '')<CR>"
    exe "vnoremap <buffer><silent> ".g:voof_return_key." <Nop>"
    exe "nnoremap <buffer><silent> ".g:voof_tab_key.   " :call Voof_ToTreeOrBodyWin()<CR>"
    exe "vnoremap <buffer><silent> ".g:voof_tab_key.   " <Nop>"

    " Put cursor on the current position.
    nnoremap <buffer><silent> = :call Voof_TreeToLine(g:voof_bodies[g:voof_trees[bufnr('')]].snLn)<CR>

    " Do not map <LeftMouse> . Not triggered on the first click in the buffer.
    " Triggered on the first click in another buffer. Vim doesn't know what
    " buffer it is until after the left mouse click.
    "nnoremap <buffer><silent> <LeftMouse> <LeftMouse>:call Voof_TreeSelect(line('.'),'tree')<CR>

    " Left mouse release. Also triggered when resizing windows with the mouse.
    nnoremap <buffer><silent> <LeftRelease> <LeftRelease>:call Voof_TreeOnLeftClick()<CR>

    " Disable Left mouse double click to avoid entering Visual mode.
    nnoremap <buffer><silent> <2-LeftMouse> <Nop>

    nnoremap <buffer><silent> <Space> :call Voof_TreeToggleFold()<CR>

    nnoremap <buffer><silent> <Down> <Down>:call Voof_TreeSelect(line('.'), 'tree')<CR>
    nnoremap <buffer><silent>   <Up>   <Up>:call Voof_TreeSelect(line('.'), 'tree')<CR>

    nnoremap <buffer><silent> <Left>  :call Voof_TreeLeft()<CR>
    nnoremap <buffer><silent> <Right> :call Voof_TreeRight()<CR>

    nnoremap <buffer><silent> x :call Voof_TreeNextMark(0)<CR>
    nnoremap <buffer><silent> X :call Voof_TreeNextMark(1)<CR>
    " }}}

    " Outline operations. {{{
    " Can't use Ctrl as in Leo: <C-i> is Tab; <C-u>, <C-d> are page up/down.

    " insert new node
    nnoremap <buffer><silent> <LocalLeader>i  :call Voof_OopInsert('')<CR>
    nnoremap <buffer><silent> <LocalLeader>I  :call Voof_OopInsert('as_child')<CR>

    " move
    nnoremap <buffer><silent> <LocalLeader>u       :call Voof_Oop('up', 'n')<CR>
    nnoremap <buffer><silent>         <C-Up>       :call Voof_Oop('up', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>u  :<C-u>call Voof_Oop('up', 'v')<CR>
    vnoremap <buffer><silent>         <C-Up>  :<C-u>call Voof_Oop('up', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>d       :call Voof_Oop('down', 'n')<CR>
    nnoremap <buffer><silent>       <C-Down>       :call Voof_Oop('down', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>d  :<C-u>call Voof_Oop('down', 'v')<CR>
    vnoremap <buffer><silent>       <C-Down>  :<C-u>call Voof_Oop('down', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>l       :call Voof_Oop('left', 'n')<CR>
    nnoremap <buffer><silent>       <C-Left>       :call Voof_Oop('left', 'n')<CR>
    nnoremap <buffer><silent>             <<       :call Voof_Oop('left', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>l  :<C-u>call Voof_Oop('left', 'v')<CR>
    vnoremap <buffer><silent>       <C-Left>  :<C-u>call Voof_Oop('left', 'v')<CR>
    vnoremap <buffer><silent>             <<  :<C-u>call Voof_Oop('left', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>r       :call Voof_Oop('right', 'n')<CR>
    nnoremap <buffer><silent>      <C-Right>       :call Voof_Oop('right', 'n')<CR>
    nnoremap <buffer><silent>             >>       :call Voof_Oop('right', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>r  :<C-u>call Voof_Oop('right', 'v')<CR>
    vnoremap <buffer><silent>      <C-Right>  :<C-u>call Voof_Oop('right', 'v')<CR>
    vnoremap <buffer><silent>             >>  :<C-u>call Voof_Oop('right', 'v')<CR>

    " cut/copy/paste
    nnoremap <buffer><silent>             dd       :call Voof_Oop('cut', 'n')<CR>
    vnoremap <buffer><silent>             dd  :<C-u>call Voof_Oop('cut', 'v')<CR>

    nnoremap <buffer><silent>             yy       :call Voof_Oop('copy', 'n')<CR>
    vnoremap <buffer><silent>             yy  :<C-u>call Voof_Oop('copy', 'v')<CR>

    nnoremap <buffer><silent>             pp       :call Voof_OopPaste()<CR>

    " mark/unmark
    nnoremap <buffer><silent> <LocalLeader>m        :call Voof_OopMark('mark', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>m   :<C-u>call Voof_OopMark('mark', 'v')<CR>

    nnoremap <buffer><silent> <LocalLeader>M        :call Voof_OopMark('unmark', 'n')<CR>
    vnoremap <buffer><silent> <LocalLeader>M   :<C-u>call Voof_OopMark('unmark', 'v')<CR>

    " mark node as selected node
    nnoremap <buffer><silent> <LocalLeader>=        :call Voof_OopMarkSelected()<CR>
    " }}}

    " Various commands. {{{
    nnoremap <buffer><silent> <F1> :call Voof_Help()<CR>
    nnoremap <buffer><silent> <LocalLeader>r :call Voof_Run()<CR>

    " update Tree, not needed
    "nnoremap <buffer><silent> u :call Voof_TreeUpdate(g:voof_trees[bufnr('')])<CR>
    " }}}

    let &cpo = cpo_
endfunc


func! Voof_TreeUpdate(body) "{{{2
" Draw Tree buffer (current buffer) for Body body. Will not work for first draw.
    setl ma
    let ul_=&ul | setl ul=-1
    let snLn_ = g:voof_bodies[a:body].snLn
    "let start = reltime()
    keepj py voof.treeUpdate(int(vim.eval('a:body')))
    "let update_time = reltimestr(reltime(start))
    "echom update_time
    let &ul=ul_
    setl noma

    " The = mark is placed by treeUpdate()
    " When nodes are deleted by editing Body, snLn can get > last Tree lnum or become 0.
    " treeUpdate() will change snLn to last line lnum
    let snLn = g:voof_bodies[a:body].snLn
    if snLn_ != snLn 
        normal! Gzv
    endif
endfunc

"---Tree autocommands---{{{2
"
augroup VoofTree
    au!
    au BufEnter   *_VOOF\d\+   call Voof_TreeBufEnter()
    au BufUnload  *_VOOF\d\+   nested call Voof_TreeBufUnload()
augroup END

func! Voof_TreeBufEnter() "{{{3
" Update outline if Body was changed since last update. Redraw Tree if needed.
    "py print 'BufEnter'
    if g:voof_TreeUpdate==0
        let g:voof_TreeUpdate = 1
        return
    endif

    let tree = bufnr('')
    let body = g:voof_trees[tree]
    if g:voof_bodies[body].tick_ != g:voof_bodies[body].tick
        call Voof_TreeUpdate(body)
        let g:voof_bodies[body].tick_ = g:voof_bodies[body].tick
    endif
endfunc

func! Voof_TreeBufUnload() "{{{3
" Wipe out Tree buffer and delete Voof data when the Tree is unloaded.
" This is also triggered when deleting and wiping out a Tree.
    let tree = expand("<abuf>")
    "py print vim.eval('tree')
    if !exists("g:voof_trees") || !has_key(g:voof_trees, tree)
        echoerr "VOOF: Error in BufUnload autocommand"
        return
    endif

    let body = g:voof_trees[tree]
    exe 'au! VoofBody * <buffer='.body.'>'
    call Voof_UnVoof(body, tree)
    exe 'noautocmd bwipeout! '.tree
endfunc


"---Outline Navigation---{{{2
"
func! Voof_TreeSelect(lnum, focus) "{{{3=
" Select node corresponding to line lnum in the Tree.
" Show correspoding fold in the Body.
" Leave cursor in the Body if it already shows the selected fold and focus!='tree'.

    let tree = bufnr('')
    let body = g:voof_trees[tree]
    let snLn = g:voof_bodies[body].snLn
    let wnr_ = winnr()

    let lz_ = &lz | set lz
    call Voof_TreeZV()
    call Voof_TreePlaceCursor()

    " Mark selected line with =. Remove old = mark.
    if a:lnum!=snLn
        setl ma | let ul_ = &ul | setl ul=-1
        keepj call setline(a:lnum, '='.getline(a:lnum)[1:])
        keepj call setline(snLn, ' '.getline(snLn)[1:])
        setl noma | let &ul = ul_
        let g:voof_bodies[body].snLn = a:lnum
    endif

    " this computes and assigns nodeStart and nodeEnd:
    " first and last lnums of Body node for Tree line lnum.
    py voof.voof_TreeSelect()

    " Go to Body, show current node, and either come back or stay in Body.
    let ei_=&eventignore
    set eventignore=BufEnter,BufLeave,WinEnter,WinLeave
    "let scrolloff_ = &scrolloff | set scrolloff=0
    let toBody = Voof_ToBody(body)

    " Body buffer no longer exists (wiped out). This should never happen because of au.
    if toBody==2
        let &eventignore=ei_
        let &lz=lz_
        "let &scrolloff=scrolloff_
        return
    endif

    " Show Body node corresponding to current line in the Tree.
    let bodyLnr = line('.')
    "let bodyLnr = line('w0') " ugly hack for 'scrolloff' problems
    "let &scrolloff=scrolloff_
    if nodeEnd==-1 | let nodeEnd=line('$')+1 | endif
    let new_node_selected = 0
    if ((bodyLnr < nodeStart) || (bodyLnr > nodeEnd))
        let new_node_selected = 1
        exe 'normal ' . nodeStart . 'G'
        normal! zMzv
        " Scroll to position headline at top of window. Affected by 'scrolloff'.
        normal! zt
        "" We want headline to be the fist window line. The following code
        "" scrolls down to make headline the first window line even when
        "" scrolloff>0. Alas, this causes problems, e.g., when selecting node
        "" that consits only of the headline, the cursor ends up below the
        "" node. And a very large scrolloff will likely put cursor outside of
        "" node. So the best is just set scrolloff to 0 or 1.
        "if winline()>1 && &scrolloff<4
            "exe "normal! ".(winline()-1)."\<c-e>"
        "endif
    endif

    " Go back to Tree after showing a different node in the Body.
    " Otherwise, that is if Body's node was same as Tree's, stay in the Body.
    if (new_node_selected==1 || a:focus=='tree') && a:focus!='body'
        if toBody==1 " Body window was found, no windows were created.
            exe wnr_.'wincmd w'
        else " A new window was created, wnr_ could be invalid.
            exe bufwinnr(tree).'wincmd w'
        endif
    endif

    let &eventignore=ei_
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
    if virtcol('.')+1==virtcol('$') || col('.')-1<=match(getline('.'), '|')
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
        let found = search('^.x\C\V', 'bw')
    else
        let found = search('^.x\C\V', 'w')
    endif

    if found==0
        py print "VOOF: there are no marked nodes"
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
    let lnum = line('.')
    if lnum==1 | return | endif
    let tree = bufnr('')
    let body = g:voof_trees[tree]
    if Voof_BufEditable(body)==0 | return | endif
    " find first word char
    let firstCharIdx = match(getline('.')[3:], '\w')
    if firstCharIdx!=-1
        let firstChar = getline('.')[3:][firstCharIdx]
    endif
    py vim.command("let bLnr=%s" %VOOF.nodes[int(vim.eval('body'))][int(vim.eval('lnum'))-1])
    call Voof_ToBody(body)
    exe 'normal! ' . bLnr.'G0'
    normal! zv
    " put cursor on first word char
    if firstCharIdx!=-1 && getline('.')[0]!=firstChar
        exe 'normal! f'.firstChar
    endif
endfunc

func! Voof_OopInsert(as_child) "{{{3
" Insert new node.
    let tree = bufnr('')
    " current buffer must be a Tree
    if !has_key(g:voof_trees, tree)
        py print "VOOF: CAN'T DO COMMAND (current buffer is not Tree)"
        return
    endif
    let body = g:voof_trees[tree]
    if Voof_BufEditable(body)==0 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        py print "VOOF: CAN'T DO COMMAND (cursor hidden in fold)"
        return
    endif

    setl ma
    if a:as_child=='as_child'
        keepj py voof.oopInsert(as_child=True)
    else
        keepj py voof.oopInsert(as_child=False)
    endif
    setl noma

    let snLn = g:voof_bodies[body].snLn
    exe "normal! ".snLn."G"
    call Voof_TreePlaceCursor()
    call Voof_TreeZV()
    call Voof_ToBody(body)
    exe "normal! ".bLnum."G"
    normal! zvzz3l

    "let g:voof_bodies[body].tick_ = b:changedtick
    "if g:voof_verify_oop==1
        "py voof.voofVerify(int(vim.eval('body')))
    "endif
endfunc

func! Voof_OopPaste() "{{{3
" Paste nodes in the clipboard.
    let tree = bufnr('')
    " current buffer must be a Tree
    if !has_key(g:voof_trees, tree)
        py print "VOOF: CAN'T DO COMMAND (current buffer is not Tree)"
        return
    endif
    let body = g:voof_trees[tree]
    if Voof_BufEditable(body)==0 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        py print "VOOF: CAN'T DO COMMAND (cursor hidden in fold)"
        return
    endif

    setl ma
    keepj py voof.oopPaste()
    setl noma
    if exists('l:invalid_clipboard')
        return
    endif
    let g:voof_bodies[body].snLn = l:ln1
    call Voof_OopShowBody(body, l:blnShow)
    if l:ln1==l:ln2
        call Voof_OopShowTree(l:ln1, l:ln2, 'n')
    else
        call Voof_OopShowTree(l:ln1, l:ln2, 'v')
    endif

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif
endfunc

func! Voof_OopMark(op, mode) "{{{3x
" Mark or unmark current node or all nodes in selection

    " Checks and init vars. {{{
    let tree = bufnr('')
    " current buffer must be a Tree
    if !has_key(g:voof_trees, tree)
        py print "VOOF: CAN'T DO COMMAND (current buffer is not Tree)"
        return
    endif
    let body = g:voof_trees[tree]
    if Voof_BufEditable(body)==0 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        py print "VOOF: CAN'T DO COMMAND (cursor hidden in fold)"
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

    if a:op=='mark'
        setl ma
        keepj py voof.oopMark()
        setl noma
        call Voof_OopShowBody(body, 0)

    elseif a:op=='unmark'
        setl ma
        keepj py voof.oopUnmark()
        setl noma
        call Voof_OopShowBody(body, 0)

    endif

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif

endfunc

func! Voof_OopMarkSelected() "{{{3x
" Mark or unmark current node or all nodes in selection

    " Checks and init vars.
    let tree = bufnr('')
    " current buffer must be a Tree
    if !has_key(g:voof_trees, tree)
        py print "VOOF: CAN'T DO COMMAND (current buffer is not Tree)"
        return
    endif
    let body = g:voof_trees[tree]
    if Voof_BufEditable(body)==0 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        py print "VOOF: CAN'T DO COMMAND (cursor hidden in fold)"
        return
    endif
    if ln==1
        return
    endif

    setl ma
    keepj py voof.oopMarkSelected()
    setl noma
    call Voof_OopShowBody(body, 0)

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif

endfunc

func! Voof_Oop(op, mode) "{{{3
" Outline operations that can be perfomed on current node or on nodes in visual
" selection. All apply to trees, not to single nodes.

    " Checks and init vars. {{{
    let tree = bufnr('')
    " current buffer must be a Tree
    if !has_key(g:voof_trees, tree)
        py print "VOOF: CAN'T DO COMMAND (current buffer is not Tree)"
        return
    endif
    let body = g:voof_trees[tree]
    if a:op!='copy' && Voof_BufEditable(body)==0 | return | endif
    let ln = line('.')
    let ln_status = Voof_FoldStatus(ln)
    " current line must not be hidden in a fold
    if ln_status=='hidden'
        py print "VOOF: CAN'T DO COMMAND (cursor hidden in fold)"
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
        py print "VOOF: INVALID SELECTION"
        return
    endif
    " }}}

    if     a:op=='up' " {{{
        if ln1<3 | return | endif
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
        setl ma
        keepj py voof.oopUp()
        setl noma
        let g:voof_bodies[body].snLn = lnUp1
        call Voof_OopShowBody(body, l:blnShow)
        let lnEnd = lnUp1+ln2-ln1
        call Voof_OopShowTree(lnUp1, lnEnd, a:mode)
        " }}}

    elseif a:op=='down' " {{{
        if ln2==line('$') | return | endif
        if a:mode=='v'
            " must be on last line of selection
            exe "normal! ".ln2."G"
        endif
        " line after which to insert
        normal! j
        let lnDn1 = line('.') " should be ln2+1
        let lnDn1_status = Voof_FoldStatus(lnDn1)
        setl ma
        keepj py voof.oopDown()
        setl noma
        let g:voof_bodies[body].snLn = l:snLn
        call Voof_OopShowBody(body, l:blnShow)
        let lnEnd = snLn+ln2-ln1
        call Voof_OopShowTree(snLn, lnEnd, a:mode)
        " }}}

    elseif a:op=='right' " {{{
        if ln1==2 | return | endif
        setl ma
        keepj py voof.oopRight()
        setl noma
        if exists('l:cannot_move_right') | return | endif
        let g:voof_bodies[body].snLn = ln1
        call Voof_OopShowBody(body, l:blnShow)
        call Voof_OopShowTree(ln1, ln2, a:mode)
        " }}}

    elseif a:op=='left' " {{{
        if ln1==2 | return | endif
        setl ma
        keepj py voof.oopLeft()
        setl noma
        if exists('l:cannot_move_left') | return | endif
        let g:voof_bodies[body].snLn = ln1
        call Voof_OopShowBody(body, l:blnShow)
        call Voof_OopShowTree(ln1, ln2, a:mode)
        " }}}

    elseif a:op=='copy' " {{{
        keepj py voof.oopCopy()
        "}}}

    elseif a:op=='cut' " {{{
        if a:mode=='v'
            " must be on first line of selection
            exe "normal! ".ln1."G"
        endif
        " new snLn
        normal! k
        let lnUp1 = line('.')
        setl ma
        keepj py voof.oopCut()
        setl noma
        let g:voof_bodies[body].snLn = lnUp1
        call Voof_OopShowBody(body, l:blnShow)
        " }}}

    endif

    if g:voof_verify_oop==1
        py voof.voofVerify(int(vim.eval('body')))
    endif
endfunc

func! Voof_OopShowBody(body, blnr) "{{{3
" Called from Tree after outline operation:
" go to Body, set changedtick, show node at blnr, go back.
"
    let tree = bufnr('')
    let wnr_ = winnr()
    " Go to Body, show current node, and either come back or stay in Body.
    let ei_=&eventignore
    set eventignore=BufEnter,BufLeave,WinEnter,WinLeave
    let toBody = Voof_ToBody(a:body)
    " Body buffer no longer exists (wiped out). This should never happen because of au.
    if toBody==2
        let &eventignore=ei_
        return
    endif

    " adjust changedtick to suppress TreeUpdate
    let g:voof_bodies[a:body].tick_ = b:changedtick
    let g:voof_bodies[a:body].tick  = b:changedtick

    " show fold at blnr
    if a:blnr > 0
        exe 'normal ' . a:blnr . 'G'
        normal! zMzvzt
    endif

    " go back
    if toBody==1 " Body window was found, no windows were created.
        exe wnr_.'wincmd w'
    else " A new window was created, wnr_ could be invalid.
        exe bufwinnr(tree).'wincmd w'
    endif
    let &eventignore=ei_
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
func! Voof_BodyConfigure() "{{{2
" Configure current buffer as a Body buffer.
    augroup VoofBody
        "au!
        au BufLeave  <buffer> call Voof_BodyBufLeave()
        au BufUnload <buffer> nested call Voof_BodyBufUnload()
    augroup END

    let cpo_ = &cpo | set cpo&vim
    exe "nnoremap <buffer><silent> ".g:voof_return_key." :call Voof_BodySelect()<CR>"
    exe "nnoremap <buffer><silent> ".g:voof_tab_key.   " :call Voof_ToTreeOrBodyWin()<CR>"
    let &cpo = cpo_
endfunc

func! Voof_BodySelect() "{{{2
" Select current Body node. Show corresponding line in the Tree.
" Stay in the Tree if the node is already selected.
    let body = bufnr('')

    " Tree has been wiped out.
    if !has_key(g:voof_bodies, body)
        call Voof_BodyUnVoof()
        return
    endif

    let wnr_ = winnr()
    let tree = g:voof_bodies[body].tree
    let blnr = line('.')
    let blnr_ = g:voof_bodies[body].blnr
    let g:voof_bodies[body].blnr = blnr

    " Go to Tree. Outline is updated automatically.
    let toTree = Voof_ToTree(tree)
    " Tree buffer no longer exists. This should never happen.
    if toTree==2 | return | endif
    " treeUpdate() sets = mark and may change snLn to a wrong value if outline was modified from Body.
    let snLn_ = g:voof_bodies[body].snLn
    " Compute new and correct snLn with updated outline.
    py voof.computeSnLn(int(vim.eval('body')), int(vim.eval('g:voof_bodies[body].blnr')))
    let snLn = g:voof_bodies[body].snLn

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

    if toTree==1 " Tree window was found, no windows were created.
        exe wnr_.'wincmd w'
    else " A new window was created, wnr_ could be invalid.
        exe bufwinnr(tree).'wincmd w'
    endif
endfunc

func! Voof_BodyBufLeave() "{{{2
" getbufvar() doesn't work with b:changedtick (why?), thus the need for this au
    let body = bufnr('')
    let g:voof_bodies[body].tick = b:changedtick
endfunc

func! Voof_BodyBufUnload() "{{{2
" This is BufUnload au for Body. Called on unloading, deleting, and wiping out
" Body. Delete VOOF data and wipe out the corresponding Tree.
    let body = expand("<abuf>")
    if !exists("g:voof_bodies") || !has_key(g:voof_bodies, body)
        echoerr "VOOF: Error in BufUnload autocommand"
        return
    endif
    let tree = g:voof_bodies[body].tree
    if !exists("g:voof_trees") || !has_key(g:voof_trees, tree)
        echoerr "VOOF: Error in BufUnload autocommand"
        return
    endif

    exe 'au! VoofBody * <buffer='.body.'>'
    call Voof_UnVoof(body, tree)
    exe 'noautocmd bwipeout! '.tree

    try
        exe 'noautocmd bunload! '.body
    " E90: Cannot unload last buffer
    catch /^Vim\%((\a\+)\)\=:E90/
    endtry
endfunc

func! Voof_BodyUnVoof() "{{{2
" Remove Body mappings.
    let cpo_ = &cpo | set cpo&vim
    exe "nunmap <buffer> ".g:voof_return_key 
    exe "nunmap <buffer> ".g:voof_tab_key
    let &cpo = cpo_
endfunc


"---LOG BUFFER (Vooflog)--------------{{{1
"
func! Voof_LogInit() "{{{2
" Redirect Python stdout and stderr to Log buffer.
    let bnr_ = bufnr('')
    """" Log buffer exists, show it.
    if exists('g:voof_logbnr')
        if bufwinnr(g:voof_logbnr)==-1
            call Voof_ToLogWin()
            silent exe 'b'.g:voof_logbnr
            normal! G
            exe bufwinnr(bnr_).'wincmd w'
        endif
        return
    endif

    """" Create Log buffer.
    "wincmd t | 10wincmd l | vsplit | wincmd l
    call Voof_ToLogWin()
    silent edit __PyLog__
    let g:voof_logbnr=bufnr('')
    " Configure Log buffer
    setl cul cuc nowrap list
    setl ft=log
    setl noro ma ff=unix
    setl buftype=nofile noswapfile bufhidden=hide
    call Voof_LogSyntax()
    au BufUnload <buffer> call Voof_LogBufUnload()
python << EOF
VOOF.vim_stdout, VOOF.vim_stderr = sys.stdout, sys.stderr
sys.stdout = sys.stderr = voof.LogBufferClass()
EOF
    " Go back.
    exe bufwinnr(bnr_).'wincmd w'
endfunc

func! Voof_LogBufUnload() "{{{2
    py sys.stdout, sys.stderr = VOOF.vim_stdout, VOOF.vim_stderr
    exe 'bwipeout '.g:voof_logbnr
    unlet g:voof_logbnr
endfunc

func! Voof_LogSyntax() "{{{2
" Syntax highlighting for common messages in the Log.

    syn match PreProc /^---end of Python script---/
    syn match PreProc /^---end of Vim script---/

    syn match WarningMsg /^Traceback (most recent call last):/
    syn match Type /^\u\h*Error/

    syn match Type /^vim\.error/

    syn match WarningMsg /^ERROR:/
    syn match WarningMsg /^WARNING:/
    syn match WarningMsg /.*exception executing script.*/

    syn match WarningMsg /^Vim EXCEPTION:/
    syn match WarningMsg /^Vim.*:E\d\+:.*/
endfunc

func! Voof_LogScroll() "{{{2
" Scroll windows with the __PyLog__ buffer.
" All tabs are searched, but only the first found Log window in a tab is scrolled.
    " can't go to other windows when in Ex mode (after 'Q' or 'gQ')
    if mode()=='c' | return | endif

    " This should never happen.
    if !exists('g:voof_logbnr')
        echoerr "VOOF: g:voof_logbnr doesn't exist"
        return
    else
        if !bufexists(g:voof_logbnr)
            echoerr "VOOF: Log buffer ".g:voof_logbnr." doesn't exist"
            return
        endif
    endif

    " disable autocommands since we will be entering tabs and windows
    let ei_=&eventignore
    set eventignore=BufEnter,BufLeave,WinEnter,WinLeave,TabEnter,TabLeave

    let log_found=0
    let tnr_=tabpagenr()
    let wnr_=winnr()
    let bnr_=bufnr('')
    " search among visible buffers in all tabs
    for tnr in range(1, tabpagenr('$'))
        for bnr in tabpagebuflist(tnr)
            if bnr==g:voof_logbnr
                let log_found=1
                exe 'tabnext '.tnr
                " save this tab's current window number
                let wnr__=winnr()
                " move to window with buffer bnr
                exe bufwinnr(bnr).'wincmd w'
                normal G
                " move back to previous window, otherwise Log becomes last visited window
                exe wnr__.'wincmd w'
            endif
        endfor
    endfor

    " At least one Log window was found and scrolled. Return to original tab and window.
    if log_found==1
        exe 'tabn '.tnr_
        exe wnr_.'wincmd w'
    " Log window was not found. Create it.
    elseif log_found==0
        " Create new window.
        "wincmd t | 10wincmd l | vsplit | wincmd l
        call Voof_ToLogWin()
        exe 'b '.g:voof_logbnr
        normal G
        " Return to original tab and buffer.
        exe 'tabn '.tnr_
        exe bufwinnr(bnr_).'wincmd w'
    endif

    let &eventignore=ei_
endfunc


"---RUN SCRIPT (Voofrun)--------------{{{1
"
func! Voof_GetLines(lnum) "{{{2
" Return list of lines.
" Tree buffer: lines from Body node (including subnodes) corresponding to Tree
" line lnum.
" Any other buffer: lines from fold at line lnum (including subfolds).
" Returns [] if checks fail.

    """"" Tree buffer: get lines from corresponding node.
    if has_key(g:voof_trees, bufnr(''))
        let status = Voof_FoldStatus(a:lnum)
        if status=='hidden'
            echo 'VOOF: current line hidden in fold'
            return []
        endif
        let body = g:voof_trees[bufnr('')]

        " this computes and assigns nodeStart and nodeEnd
        py voof.voof_GetLines()
        "echo [nodeStart, nodeEnd]
        return getbufline(body, nodeStart, nodeEnd)
    endif

    """"" Regular buffer: get lines from current fold.
    let status = Voof_FoldStatus(a:lnum)
    if status=='nofold'
        echo 'VOOF: no fold'
        return []
    elseif status=='hidden'
        echo 'VOOF: current line hidden in fold'
        return []
    elseif status=='folded'
        return getline(foldclosed(a:lnum), foldclosedend(a:lnum))
    elseif status=='notfolded'
        normal! zc
        let foldStart = foldclosed(a:lnum)
        let foldEnd   = foldclosedend(a:lnum)
        normal! zo
        return getline(foldStart, foldEnd)
    endif
endfunc

func! Voof_Run(...) "{{{2
" Execute lines from the current fold (non-Tree buffer, include subfolds) or
" node (Tree buffer, include subnodes) as a script.
" First argument is 'vim' or 'py': execute as Vim or Python script respectively.
" Otherwise execute according to filetype.

    let lines = Voof_GetLines(line('.'))
    if lines==[] | return | endif

    " Determine type of script: Vim or Python.
    let scriptType = ''

    " this is a Tree
    if has_key(g:voof_trees, bufnr(''))
        let ft = getbufvar(g:voof_trees[bufnr('')], '&ft')
    " this is not a Tree
    else
        let ft = &ft
    endif

    if     a:0>0 && a:1=='vim'
        let scriptType = 'vim'
    elseif a:0>0 && a:1=='py'
        let scriptType = 'python'
    elseif ft=='vim'
        let scriptType = 'vim'
    elseif ft=='python'
        let scriptType = 'python'
    else
        echo "VOOF: can't determine script type"
        return
    endif
 
    " Run Vim script: Copy list of lines to register and execute it.
    " Problem: Python errors do not terminate script and Python tracebacks are
    " not printed. They are printed to the PyLog if it's enabled.
    if scriptType=='vim'
        let z_=@z
        let script = join(lines, "\n") . "\n"
        call setreg('z', script, "l")
        try
            @z
            echo '---end of Vim script---'
        catch /.*/
            echo v:exception
        endtry
        let @z=z_
    " Run Python script: write lines to a .py file and do execfile().
    elseif scriptType=='python'
        call writefile(lines, g:voof_script_py)
        py voof.runScript()
    endif
endfunc

"---Commands--------------------------{{{1
" Main Voof commands should be defined in Quickload section.

" Source voof.vim, reload voof.py
com! VoofReload exe 'so '.g:voof_path.' | py reload(voof)'
" Source voof.vim .
com! VoofReloadVim exe 'so '.g:voof_path
" Reload voof.py .
com! VoofReloadPy py reload(voof)
" Complete reload: delete Trees and Voof data, source voof.vim, reload voof.py .
com! VoofReloadAll call Voof_ReloadAllPre() | exe 'so '.g:voof_path | call Voof_Init()

" modelines {{{1
" vim:fdm=marker:fdl=0
" vim:foldtext=getline(v\:foldstart).'...'.(v\:foldend-v\:foldstart)
