Promise = require 'bluebird'
events = require 'events'

class Board extends events.EventEmitter

  ready: no

  constructor: (driverOptions, @protocol) ->
    # setup a new serialport driver
    SerialPortDriver = require './serialport'
    @driver = new SerialPortDriver(driverOptions, @protocol)

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
      @driver.writeCommand("PING").then( =>
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

    if event.debug?
      @emit 'rfdebug', event.debug
    else if event.ack? then
      #nop
    else
      @emit 'rf', event


  whenReady: ->
    unless @pendingConnect?
      return Promise.reject(new Error("First call connect!"))
    return @pendingConnect

  enableRfDebug: ->
    @driver.writeCommand("RFDEBUG=ON")

  enableRfuDebug: ->
    @driver.writeCommand("RFUDEBUG=ON")

  enableQrfDebug: ->
    @driver.writeCommand("QRFDEBUG=ON")

  encodeAndWriteEvent: (event) ->
    @driver.encodeAndWriteEvent(event)

#  writeAndWait: (data) ->
#    return @_lastAction = settled(@_lastAction).then( =>
#      return Promise.all([@driver.write(data), @_waitForAcknowledge()])
#      .then( ([_, result]) ->
##console.log "writeAndWait result: ", result
#        result )
#    )

module.exports = Board