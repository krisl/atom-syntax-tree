Document = require("tree-sitter").Document
TextBufferInput = require("./text-buffer-input")
{Range} = require("atom")

LANGUAGE_SCOPE_REGEX = /source.(\w+)/

LANGUAGES_MODULES =
  "js": "tree-sitter-javascript"
  "go": "tree-sitter-golang"
  "c": "tree-sitter-c"

class SyntaxState
  constructor: (editor) ->
    buffer = editor.buffer

    @nodeStacks = []
    @document = new Document()
      .setInput(new TextBufferInput(buffer))
      .setLanguage(getEditorLanguage(editor))
    
    @document.parse()

    buffer.onDidChangeText =>
      @nodeStacks.length = 0
      @document.parse()

    buffer.onDidChange ({oldRange, newText, oldText}) =>
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
    atom.commands.add(@workspaceElement, "syntax-tree:reparse", @reparse.bind(this))

  stop: ->

  selectNextError: ->
    findFirstError = (node) ->
      if node.type is 'ERROR'
        return node
      for child in node.children
        if error = findFirstError(child)
          return error
      null

    editor = @currentEditor()
    if node = findFirstError(@stateForEditor(editor).document.rootNode)
      editor.setSelectedBufferRange(Range(node.startPosition, node.endPosition))

  reparse: ->
    @stateForEditor(@currentEditor()).document.invalidate().parse()

  selectUp: ->
    @updatedSelectedNodes (node, nodeStack, currentStartIndex, currentEndIndex) ->
      newNode = node
      while newNode and newNode.startIndex is currentStartIndex and newNode.endIndex is currentEndIndex
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
        node = document.rootNode.descendantForIndex(currentStart, currentEnd - 1)
        console.log(node.toString())
    return

  toggleDebug: ->
    state = @stateForEditor(@currentEditor())
    if state.document.getDebugger()
      state.document.setDebugger(null)
    else
      state.document.setDebugger (msg, params, type) ->
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
      node = syntaxState.document.rootNode.descendantForIndex(currentStart, currentEnd - 1)
      nodeStack = syntaxState.nodeStacks[i]
      if node.startIndex < currentStart or node.endIndex > currentEnd
        nodeStack.length = 0
      if currentEnd > currentStart
        node = fn(node, nodeStack, currentStart, currentEnd)
      if node
        Range(node.startPosition, node.endPosition)
      else
        Range(range.start, range.end)

    editor.setSelectedBufferRanges(newRanges)

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
