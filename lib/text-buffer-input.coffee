{Point} = require("atom")

module.exports =
class TextBufferInput
  constructor: (@textBuffer) ->
    @seek(0)

  seek: (offset) ->
    @point = @textBuffer.positionForCharacterIndex(offset)

  read: ->
    line =
      @textBuffer.lines[@point.row]?.slice(@point.column) +
      @textBuffer.lineEndings[@point.row]
    @point = @point.traverse([1, 0])
    line
