{Workspace, TextEditor, Point} = require 'atom'
Controller = require '../lib/controller'

describe "SyntaxTree", ->
  [workspace, workspaceElement, controller, editor] = []

  beforeEach ->
    workspace = new Workspace
    workspaceElement = atom.views.getView(workspace)
    controller = new Controller(workspace, workspaceElement)
    controller.start()

    editor = setUpActiveEditor(workspace)
    editor.setText(trim("""
      var x = { theKey: "the-value" };
      console.log(x);
    """))

    waitsForPromise ->
      atom.packages.activatePackage("language-javascript").then ->
        editor.setGrammar(atom.grammars.grammarForScopeName("source.js"))

  describe "when a syntax-tree:select-up event is triggered", ->
    beforeEach ->
      editor.setCursorBufferPosition(new Point(0, "var x = { the".length))
      atom.commands.dispatch(workspaceElement, 'syntax-tree:select-up')

    it "parses the document", ->
      programNode = editor.syntaxTreeDocument.children[0]
      expect(programNode.toString()).toEqual(trim("""
        (program
          (var_declaration (var_assignment
            (identifier)
            (object (pair (identifier) (string)))))
          (expression_statement (function_call
            (member_access (identifier) (identifier))
            (identifier))))
      """))

    it "highlights the syntax node under the cursor", ->
      expect(editor.getSelectedText()).toEqual("theKey")

    describe "when select-up is triggered again", ->
      it "highlights the parent of the previously highlighted node", ->
        atom.commands.dispatch(workspaceElement, 'syntax-tree:select-up')
        expect(editor.getSelectedText()).toEqual('theKey: "the-value"')

    describe "when select-down is triggered", ->
      it "highlights the first child of the previously highlighted node", ->
        atom.commands.dispatch(workspaceElement, 'syntax-tree:select-up')
        atom.commands.dispatch(workspaceElement, 'syntax-tree:select-down')
        expect(editor.getSelectedText()).toEqual('theKey')

    describe "when select-left is triggered", ->
      it "highlights the left sibling of the previously highlighted node", ->
        atom.commands.dispatch(workspaceElement, 'syntax-tree:select-left')
        expect(editor.getSelectedText()).toEqual("x")

    describe "when select-right is triggered", ->
      it "highlights the left sibling of the previously highlighted node", ->
        atom.commands.dispatch(workspaceElement, 'syntax-tree:select-right')
        expect(editor.getSelectedText()).toEqual('"the-value"')

    describe "when the document is edited", ->
      beforeEach ->
        editor.buffer.insert(
          new Point(0, 'var x = { theKey: "the-value"'.length),
          ', otherKey: "other-value" '
        )

      it "updates the parse tree", ->
        programNode = editor.syntaxTreeDocument.children[0]
        expect(programNode.toString()).toEqual(trim("""
          (program
            (var_declaration (var_assignment
              (identifier)
              (object (pair (identifier) (string)) (pair (identifier) (string)))))
            (expression_statement (function_call
              (member_access (identifier) (identifier))
              (identifier))))
        """))

# Helpers

setUpActiveEditor = (workspace) ->
  editor = new TextEditor({})
  spyOn(workspace, 'getActiveTextEditor').andReturn(editor)
  editor

trim = (string) ->
  string
    .replace(/\n/g, '')
    .replace(/\s+/g, " ")
    .trim()
