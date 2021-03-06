Controller = require './controller'

module.exports =
  syntaxTreeView: null

  activate: (state) ->
    @controller = new Controller(atom.workspace, atom.views.getView(atom.workspace))
    @controller.start()

  deactivate: ->
    @syntaxTreeView.stop()

  serialize: ->
    {}

  getCurrentDocument: ->
    if editor = atom.workspace.getActiveTextEditor()
      @controller?.stateForEditor(editor)?.document
