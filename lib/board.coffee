Promise = require 'bluebird'
events = require 'events'
SerialPortDriver = require './serialport'

settled = (promise) -> Promise.settle([promise])

class Board extends events.EventEmitter

  ready: no
  _awaitingAck: []

  constructor: (driverOptions, @protocol) ->
    # await the ready message to be received before writes are allowed
    @_blockWritesUntilready()

    # setup a new serialport driver
    @driver = new SerialPortDriver(driverOptions)

    @_lastAction = Promise.resolve()

    @driver.on('open', =>
      # setup the watchdog to reconnect when connection appears lost
      @setupWatchdog()
    )
    @driver.on('error', (error) =>
      @emit('error', error)
    )
    @driver.on('close', =>
      @ready = no
      # serial port opened, await an acknowledge for the ready to be received
      @_blockWritesUntilready()
      @reconnect()
      @emit('close')
    )
    @driver.on("data", (data) =>
      @emit "data", data
    )
    @driver.on("line", (line) =>
      @_onLine(line)
    )
    @driver.on("send", (data) =>
      @emit "send", data
    )


  connect: (@timeout = 5*60*1000, @retries = 3) =>
    return @driver.connect(timeout, retries).catch( (err) =>
      @emit 'error', err
      throw err
    )

  disconnect: ->
    @stopWatchdog()
    return @driver.disconnect().catch( (err) =>
      @emit 'error', err
      throw err
    )

  reconnect: ->
    @disconnect().then(=>
      @connect()
    )

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
        @emit 'error', "Couldn't connect (#{err.message}), retrying..."
        @reconnect()
        return
      )
    ), 20*1000)

  stopWatchdog: ->
    clearTimeout(@_watchdogTimeout)

  _onLine: (line) ->
    @_lastDataTime = new Date().getTime()

    event = @protocol.decodeLine line

    # continue if we are already ready
    unless @ready
      # continue if this line would make us ready and store state
      unless @ready = (event.name.indexOf('RFLink Gateway') > -1)
        # we receive a non-ready message before a ready message
        # reboot the RFLink to reset its state
        @emit 'warning', "Received data before the ready message from RFLink, discard and reboot..."
        driver.write(@protocol.encodeLine({action: "REBOOT"}))
        return

    if event.debug? then @emit 'rfdebug', event.debug
    else if event.ackResponse? then @_handleAcknowledge event
    else @emit 'rf', event


  enableRfDebug: ->
    @_writeCommand("RFDEBUG=ON")

  enableRfuDebug: ->
    @_writeCommand("RFUDEBUG=ON")

  enableQrfDebug: ->
    @_writeCommand("QRFDEBUG=ON")

  _blockWritesUntilready: ->
    @_awaitingAck = [ =>
      @emit 'debug', 'Received welcome message from RFLink'
      @_lastDataTime = new Date().getTime()
      @ready = yes
      @emit 'connected'
    ]

  encodeAndWriteEvent: (event) ->
    @_writeAndWait(@protocol.encodeLine(event))

  _writeCommand: (command) ->
    @encodeAndWriteEvent({action: command})

  _writeAndWait: (data) ->
    return @_lastAction = settled(@_lastAction).then( =>
      return Promise.all([@driver.write(data), @_waitForAcknowledge()])
      .then( ([_, result]) ->
        result ).timeout(5000, "operation timed out")
    )

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
    resolver = @_awaitingAck.splice(0, 1)[0]
    resolver(event)


module.exports = Board