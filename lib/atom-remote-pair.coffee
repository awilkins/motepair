{Emitter}    = require 'event-kit'
{TextEditor} = require('atom')
WsEmitClient = require('./ws/ws-emit-client.js')
Fsm          = require('./fsm.js')

module.exports =

  config:
    serverAddress:
      title: 'Server address'
      type: 'string'
      default: 'localhost'
    serverPort:
      title: 'Server port number'
      type: 'integer'
      default: 3000

  activate: ->
    address = atom.config.get('atom-remote-pair.serverAddress')
    portNumber = atom.config.get('atom-remote-pair.serverPort')

    remoteClient = new WsEmitClient("ws://#{ address }:#{ portNumber }")
    fsm =  new Fsm({ws: remoteClient})

    atom.workspaceView.command "remote-pair:action", => @action()
    @project = atom.project

    remoteClient.on 'open', ->
      console.log('Connected!')

    remoteClient.on 'save-file', (event) =>
      fsm.transition("remoteFileChanging")
      fsm.handle("saveFile", event, atom)

    remoteClient.on 'close-file', (event) =>
      fsm.transition("remoteFileChanging")
      fsm.handle("closeFile", event, atom)

    remoteClient.on 'change-file', (event) =>
      fsm.transition("remoteFileChanging")
      fsm.handle("changeFile", event, atom)

    remoteClient.on 'open-file', (event) =>
      fsm.transition("remoteFileChanging")
      fsm.handle("changeFile", event, atom)

    remoteClient.on 'change', (event) =>
      for editor in atom.workspace.getPaneItems() when editor.getPath().indexOf(event.file) >= 0
        fsm.transition("remoteChanging")
        fsm.handle("remoteChange", editor, event.change)

    remoteClient.on 'selection', (event) =>
      for editor in atom.workspace.getPaneItems() when editor.getPath().indexOf(event.file) >= 0
        fsm.transition("remoteSelecting")
        fsm.handle("remoteSelection", editor, event)
        setTimeout ->
          fsm.transition("localSelecting")
        , 300

    atom.workspace.observeTextEditors (editor) =>

      editor.backspace = (args) ->
        this.emit('will-backspace', args)
        TextEditor.prototype.backspace.call(this, args)

      editor.on 'will-backspace', (event)->
        fsm.transition("localChanging")

      editor.onDidSave (event) =>
        fsm.handle("fileAction", "save-file", @project.relativize(event.path))
        fsm.transition("localChanging")

      editor.onDidChangeCursorPosition (event) =>
        if event.textChanged
          fsm.transition("localChanging")
        else
          setTimeout ->
            fsm.transition("localSelecting")
          , 300

      editor.onDidChangeSelectionRange (event) =>
        fsm.handle("localSelection", atom, editor, event)

      editor.onWillInsertText (event) =>
        fsm.transition("localChanging")

      buffer = editor.getBuffer()

      buffer.onDidChange (event) =>
        fsm.handle('localChange', atom, editor, event)

    atom.workspace.onDidOpen (event) =>
      fsm.handle 'fileAction', 'change-file', @project.relativize(event.uri)
      fsm.transition("localChanging")

    atom.workspace.onWillDestroyPaneItem (event) =>
      fsm.handle 'fileAction', 'close-file', @project.relativize(event.item.getPath())
      fsm.transition("localChanging")

    atom.workspace.onDidChangeActivePaneItem (event) =>
      fsm.handle 'fileAction', 'change-file', @project.relativize(event.getPath())
      fsm.transition("localChanging")
