Promise = require 'bluebird'
events = require 'events'

settled = (promise) -> Promise.settle([promise])

class Board extends events.EventEmitter

  ready: no
  _awaitingAck: []

  constructor: (driverOptions, @protocol) ->
    # setup a new serialport driver
    SerialPortDriver = require './serialport'
    @driver = new SerialPortDriver(driverOptions)

    @_lastAction = Promise.resolve()
    @driver.on('ready', =>
      @_lastDataTime = new Date().getTime()
      @ready = yes
      @emit('ready')
    )
    @driver.on('error', (error) => @emit('error', error) )
    @driver.on('reconnect', (error) => @emit('reconnect', error) )
    @driver.on('close', =>
      @ready = no
      @emit('close')
    )
    @driver.on("data", (data) =>
      @emit "data", data
    )
    @driver.on("line", (line) =>
      @emit "line", line
      @_onLine(line)
    )
    @driver.on("send", (data) =>
      @emit "send", data
    )
    @on('ready', => @setupWatchdog())

  connect: (@timeout = 5*60*1000, @retries = 3) ->
# Stop watchdog if its running and close current connection
    return @pendingConnect = @driver.connect(timeout, retries)

  disconnect: ->
    @stopWatchdog()
    return @driver.disconnect()

  setupWatchdog: ->
    @stopWatchdog()
    @_watchdogTimeout = setTimeout( (=>
      now = new Date().getTime()
      # last received data is not very old, conncection looks ok:
      if now - @_lastDataTime < @timeout
        @setupWatchdog()
        return
      # Try to send ping, if it failes, there is something wrong...
      @_writeCommand("PING").then( =>
        @setupWatchdog()
      ).timeout(20*1000).catch( (err) =>
        @emit 'reconnect', err
        @connect(@timeout, @retries).catch( () =>
# Could not reconnect, so start watchdog again, to trigger next try
          @emit 'reconnect', err
          return
        )
        return
      )
    ), 20*1000)

  stopWatchdog: ->
    clearTimeout(@_watchdogTimeout)

  _onLine: (line) ->
    @_lastDataTime = new Date().getTime()

    event = @protocol.decodeLine line

    if event.debug? then @emit 'rfdebug', event.debug
    else if event.ackResponse? then @_handleAcknowledge event
    else @emit 'rf', event


  whenReady: ->
    unless @pendingConnect?
      return Promise.reject(new Error("First call connect!"))
    return @pendingConnect

  enableRfDebug: ->
    @_writeCommand("RFDEBUG=ON")

  enableRfuDebug: ->
    @_writeCommand("RFUDEBUG=ON")

  enableQrfDebug: ->
    @_writeCommand("QRFDEBUG=ON")

  encodeAndWriteEvent: (event) ->
    @_writeAndWait(@protocol.encodeLine(event))

  _writeCommand: (command) ->
    @encodeAndWriteEvent({action: command})

  _writeAndWait: (data) ->
    return @driver.write(data)
#    return @_lastAction = settled(@_lastAction).then( =>
#      return Promise.all([@driver.write(data), @_waitForAcknowledge()])
#      .then( ([_, result]) ->
#        console.log "_writeAndWait result: ", result
#        result ).timeout(5000, "operation timed out")
#    )

  _onAcknowledge: () =>
    return new Promise( (resolve) =>
      @_awaitingAck.push resolve
    )

  _waitForAcknowledge: () =>
    return @_onAcknowledge().then( ( event ) =>
      unless event.ackResponse then throw new Error("Failed to send: " + event.name)
      return event.name
    )

  _handleAcknowledge: (event) ->
    unless @_awaitingAck.length <= 0
      resolver = @_awaitingAck.splice(0, 1)[0]
      resolver(event)


module.exports = Board