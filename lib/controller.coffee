Document = require("tree-sitter").Document
TextBufferInput = require("./text-buffer-input")
{Range, TextBuffer} = require("atom")

unless TextBuffer::onDidTransact?
  originalTransact = TextBuffer::transact
  TextBuffer::transact = ->
    originalTransact.apply(this, arguments)
    this.emitter.emit('did-transact')

  originalUndo = TextBuffer::undo
  TextBuffer::undo = ->
    originalUndo.apply(this, arguments)
    this.emitter.emit('did-transact')

  originalRedo = TextBuffer::redo
  TextBuffer::redo = ->
    originalRedo.apply(this, arguments)
    this.emitter.emit('did-transact')

  TextBuffer::onDidTransact = (callback) ->
    this.emitter.on('did-transact', callback)

LANGUAGE_SCOPE_REGEX = /source.(\w+)/

LANGUAGES_MODULES =
  "js": "tree-sitter-javascript"
  "go": "tree-sitter-golang"
  "c": "tree-sitter-c"

class SyntaxState
  constructor: (editor) ->
    @nodeStacks = []
    @document = new Document()
      .setInput(new TextBufferInput(editor.buffer))
      .setLanguage(getEditorLanguage(editor))
      .parse()

    editor.buffer.onDidTransact =>
      @nodeStacks.length = 0
      @document.parse()
    editor.buffer.onDidChange ({oldRange, newRange, newText, oldText}) =>
      @document.edit(
        position: editor.buffer.characterIndexForPosition(oldRange.start)
        charsInserted: newText.length
        charsRemoved: oldText.length
      )

module.exports =
class Controller
  constructor: (@workspace, @workspaceElement) ->
    @syntaxStates = new WeakMap

  start: ->
    atom.commands.add(@workspaceElement, "syntax-tree:select-up", @selectUp.bind(this))
    atom.commands.add(@workspaceElement, "syntax-tree:select-down", @selectDown.bind(this))
    atom.commands.add(@workspaceElement, "syntax-tree:select-left", @selectLeft.bind(this))
    atom.commands.add(@workspaceElement, "syntax-tree:select-right", @selectRight.bind(this))
    atom.commands.add(@workspaceElement, "syntax-tree:print-tree", @printTree.bind(this))
    atom.commands.add(@workspaceElement, "syntax-tree:toggle-debug", @toggleDebug.bind(this))
    atom.commands.add(@workspaceElement, "syntax-tree:select-next-error", @selectNextError.bind(this))

  stop: ->

  selectNextError: ->
    findFirstError = (node) ->
      if node.type is 'ERROR' and node.children.length is 0
        return node
      for child in node.children
        if error = findFirstError(child)
          return error
      null

    editor = @currentEditor()
    if node = findFirstError(@stateForEditor(editor).document.rootNode)
      editor.setSelectedBufferRange(
        new Range(
          editor.buffer.positionForCharacterIndex(node.position),
          editor.buffer.positionForCharacterIndex(node.position + node.size),
        )
      )

  selectUp: ->
    @updatedSelectedNodes (node, nodeStack, size) ->
      newNode = node
      while newNode and newNode.size is size
        newNode = newNode.parent
      if newNode
        nodeStack.push(node)
        newNode

  selectDown: ->
    @updatedSelectedNodes (node, nodeStack, currentStart, currentEnd) ->
      if nodeStack.length > 0
        nodeStack.pop()
      else if node.children.length > 0
        node.children[0]
      else
        null

  selectLeft: ->
    @updatedSelectedNodes (node, nodeStack) ->
      nodeStack.length = 0
      depth = 0
      while node.parent and !node.previousSibling
        depth++
        node = node.parent
      node = node.previousSibling
      if node
        while depth > 0 and node.children.length > 0
          depth--
          node = node.children[node.children.length - 1]
      node

  selectRight: ->
    @updatedSelectedNodes (node, nodeStack) ->
      nodeStack.length = 0
      depth = 0
      while node.parent and !node.nextSibling
        depth++
        node = node.parent
      node = node.nextSibling
      if node
        while depth > 0 and node.children.length > 0
          depth--
          node = node.children[0]
      node

  printTree: ->
    editor = @currentEditor()
    {document} = @stateForEditor(editor)
    if editor.getSelectedText() is ''
      console.log(document.rootNode.toString())
    else
      buffer = editor.buffer
      for range in editor.getSelectedBufferRanges()
        currentStart = buffer.characterIndexForPosition(range.start)
        currentEnd = buffer.characterIndexForPosition(range.end)
        node = document.rootNode.descendantForRange(currentStart, currentEnd - 1)
        console.log(node.toString())
    return

  toggleDebug: ->
    {document} = @stateForEditor(@currentEditor())
    document.setDebugger (msg, params, type) ->
      switch type
        when 'parse'
          console.log(msg, params)
        when 'lex'
          console.log("  ", msg, params)

  updatedSelectedNodes: (fn) ->
    editor = @currentEditor()
    buffer = editor.buffer
    syntaxState = @stateForEditor(editor)
    selectedRanges = editor.getSelectedBufferRanges()

    if syntaxState.nodeStacks.length isnt selectedRanges.length
      syntaxState.nodeStacks = selectedRanges.map -> []

    newRanges = for range, i in selectedRanges
      currentStart = buffer.characterIndexForPosition(range.start)
      currentEnd = buffer.characterIndexForPosition(range.end)
      size = currentEnd - currentStart
      node = syntaxState.document.rootNode.descendantForRange(currentStart, currentEnd - 1)
      nodeStack = syntaxState.nodeStacks[i]
      if node.position < currentStart or node.position + node.size > currentEnd
        nodeStack.length = 0
      if size > 0
        node = fn(node, nodeStack, size)
      if node
        new Range(
          buffer.positionForCharacterIndex(node.position),
          buffer.positionForCharacterIndex(node.position + node.size),
        )
      else
        new Range(range.start, range.end)

    editor.setSelectedBufferRanges(newRanges)
    editor.scrollToScreenRange(editor.screenRangeForBufferRange(newRanges[0]))

  stateForEditor: (editor) ->
    unless syntaxState = @syntaxStates.get(editor)
      syntaxState = new SyntaxState(editor)
      @syntaxStates.set(editor, syntaxState)
    syntaxState

  currentEditor: ->
    @workspace.getActiveTextEditor()

getEditorLanguage = (editor) ->
  for scope in editor.getLastCursor().getScopeDescriptor().getScopesArray()
    if match = scope.match(LANGUAGE_SCOPE_REGEX)
      languageName = match[1]
      if languageModule = LANGUAGES_MODULES[languageName]
        return require(languageModule)
      else
        throw new Error("Unsupported language '#{languageName}'")
  throw new Error("Couldn't determine language for buffer.")
