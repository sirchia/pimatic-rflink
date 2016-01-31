Promise = require 'bluebird'
events = require 'events'
SerialPortDriver = require './serialport'

settled = (promise) -> Promise.settle([promise])

class Board extends events.EventEmitter

  _awaitingAck: []
  _dynamicReconnectInterval: 0

  constructor: (driverOptions, @protocol, @connectionTimeout, @reconnectInterval, @pingInterval) ->
    # await the ready message to be received before writes are allowed
    @_blockWritesUntilready()

    # setup a new serialport driver
    @driver = new SerialPortDriver(driverOptions)

    @_lastAction = Promise.resolve()

    @driver.on('debug', (debug) =>
      @emit 'debug', debug
    )

    @driver.on('warning', (warning) =>
      @emit 'warning', warning
    )

    @driver.on('error', (error) =>
      @emit 'error', error
      @emit 'warning', 'Try to recover from the error by reconnecting to the RFLink device'
      @reconnect()
    )

    @driver.on('close', =>
      # serial port closed, await an acknowledge for the ready to be received
      @_blockWritesUntilready()
    )

    @driver.on("data", (data) =>
      @_lastDataTime = new Date().getTime()
      @emit "data", data
      @_processData(data)
    )

    @driver.on("send", (data) =>
      @emit "send", data
    )


  connect: =>
    return @driver.connect()
      .then( =>
        # driver connected, register timeout on acknowledge of ready message
        @connectionReady
          .timeout(@connectionTimeout)
          .catch( =>
            @emit 'warning', 'No ready message received within connection timeout, reboot device'
            @driver.write(@protocol.encodeLine({action: "REBOOT"}))
            @connectionReady.timeout(@connectionTimeout, 'No ready message received within connection timeout after reboot, reconnect')
        )
      ).timeout(@connectionTimeout, 'Connection not opened within connection timeout')
      .catch( (err) =>
        if @driver.isConnected()
          @disconnect()

        retryTime = @_determineReconnectInterval()
        @emit 'debug', "Connect failed (#{err.message}), retry in #{retryTime/1000} seconds"
        setTimeout(@reconnect, retryTime)
      )

  disconnect: ->
    @stopWatchdog()
    return @driver.disconnect().catch( (err) =>
      @emit 'error', err
      throw err
    )

  destroy: ->
    @disconnect()

  reconnect: =>
    @emit 'debug', 'Attempt to reconnect to device...'
    if @driver.isConnected()
      @disconnect().then(=>
        @connect()
      )
    else
      @connect()

  setupWatchdog: ->
    @stopWatchdog()
    @_watchdogTimeout = setTimeout( (=>
      now = new Date().getTime()
      # last received data is not very old, connection looks ok:
      if now - @_lastDataTime < @pingInterval
        @setupWatchdog()
        return

      # Try to send ping, if it fails, there is something wrong...
      @_writeCommand("PING").then( =>
        @setupWatchdog()
      ).timeout(@connectionTimeout).catch( (err) =>
        @emit 'warning', "Device ping failed (#{err.message})"
        @reconnect()
        return
      )
    ), Math.min(@pingInterval / 10, @connectionTimeout))

  stopWatchdog: ->
    clearTimeout(@_watchdogTimeout)
    @_watchdogTimeout = undefined

  _processData: (data) ->
    event = @protocol.decodeLine data

    # continue if we are already ready
    unless @connectionReady.isFulfilled()
      # continue if this line would make us ready and store state
      unless event.name.indexOf('RFLink Gateway') > -1
        # we receive a non-ready message before a ready message
        # reboot the RFLink to reset its state
        @emit 'warning', "Received data before the ready message from RFLink, discard and reboot..."
        @driver.write(@protocol.encodeLine({action: "REBOOT"}))
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
    @connectionReady = new Promise((resolve) =>
      @_markConnectionReady = resolve
    )

    @_lastDataTime = 0
    @_awaitingAck = [ =>
      @emit 'debug', 'Received welcome message from RFLink'
      @_markConnectionReady()
      # reset the _dynamicReconnectInterval to start at quick reconnect again
      @_dynamicReconnectInterval = 0
      # setup the watchdog to reconnect when connection appears lost
      @setupWatchdog()
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
        result ).timeout(@connectionTimeout, "write operation timed out")
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

  _determineReconnectInterval: ->
    if @reconnectInterval?
      return @reconnectInterval
    else
      # keep doubling the reconnect interval, minimum 1 second, maximum 1 minute 
      return @_dynamicReconnectInterval = Math.max(1000, Math.min(60000, @_dynamicReconnectInterval * 2))

module.exports = Board