{TextBuffer} = require 'atom'

unless TextBuffer::onDidTransact?
  originalTransact = TextBuffer::transact
  TextBuffer::transact = ->
    result = originalTransact.apply(this, arguments)
    this.emitter.emit('did-transact')
    result

  originalUndo = TextBuffer::undo
  TextBuffer::undo = ->
    result = originalUndo.apply(this, arguments)
    this.emitter.emit('did-transact')
    result

  originalRedo = TextBuffer::redo
  TextBuffer::redo = ->
    result = originalRedo.apply(this, arguments)
    this.emitter.emit('did-transact')
    result

  TextBuffer::onDidTransact = (callback) ->
    this.emitter.on('did-transact', callback)
