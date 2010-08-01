" This is a sample VOoM add-on.
" It creates global command :VoomInfo which prints various outline information
" about the current buffer if it's a VOoM buffer (Tree or Body)

com! VoomInfo call Voom_Info()

func! Voom_Info()
    """"""" standard code for every VOoM add-on command
    " Determine if current buffer is a Tree or Body buffer.
    " Exit if neither. An info message will be printed by Voom_GetBufInfo.
    " bufType is also 'None' when Body is not loaded or doesn't exist.
    " Get Tree and Body buffer numbers.
    " If current buffer is a Body, outline is updated if needed.
    let [bufType,body,tree] = Voom_GetBufInfo()
    if bufType=='None' | return | endif
    " Get voom.vim data.
    let [voom_bodies, voom_trees] = Voom_GetData()


    """"""" script-specific code
    " Get Python-side data. This creates local vars.
    py voom_Info()

    " print information
    echo 'VOoM outline for:' getbufline(tree,1)[0][1:]
    echo 'Current buffer is:' bufType
    echo 'Body buffer number:' body
    echo 'Tree buffer number:' tree
    echo 'number of nodes:' l:nodesNumber
    echo 'nodes with/without children:' l:nodesWithChildren '/' l:nodesWithoutChildren
    echo 'max level:' l:maxLevel
    echo 'selected node number:' voom_bodies[body].snLn
    echo 'selected node headline text:' l:selectedHeadline
    echo 'selected node level:' l:selectedNodeLevel
endfunc

python << EOF
def voom_Info():
    body, tree = int(vim.eval('l:body')), int(vim.eval('l:tree'))
    bnodes, levels = VOOM.bnodes[body], VOOM.levels[body]
    vim.command("let l:maxLevel=%s" %(max(levels)))
    vim.command("let l:nodesNumber=%s" %(len(bnodes)))
    nodesWithChildren = len([i for i in xrange(1,len(bnodes)+1) if voom.nodeHasChildren(body,i)])
    vim.command("let l:nodesWithChildren=%s" %nodesWithChildren)
    nodesWithoutChildren = len([i for i in xrange(1,len(bnodes)+1) if not voom.nodeHasChildren(body,i)])
    vim.command("let l:nodesWithoutChildren=%s" %nodesWithoutChildren)
    snLn = VOOM.snLns[body]
    treeline = VOOM.buffers[tree][snLn-1]
    if snLn>1:
        selectedHeadline = treeline[treeline.find('|')+1:]
    else:
        selectedHeadline = "top-of-file"
    vim.command("let [l:selectedNode,l:selectedHeadline]=[%s,'%s']" %(snLn, selectedHeadline.replace("'","''")))
    vim.command("let l:selectedNodeLevel=%s" %VOOM.levels[body][snLn-1])
EOF

