Promise = require 'bluebird'
assert = require 'assert'
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

#  writeAndWait: (data) ->
#    return @_lastAction = settled(@_lastAction).then( =>
#      return Promise.all([@driver.write(data), @_waitForAcknowledge()])
#      .then( ([_, result]) ->
##console.log "writeAndWait result: ", result
#        result )
#    )

#  rfControlSendMessage: (pin, repeats, protocolName, message) ->
#    result = rfcontrol.encodeMessage(protocolName, message)
#    return @rfControlSendPulses(pin, repeats, result.pulseLengths, result.pulses)

#  rfControlSendPulses: (pin, repeats, pulseLengths, pulses) ->
#    assert typeof pin is "number", "pin should be a number"
#    assert Array.isArray(pulseLengths), "pulseLengths should be an array"
#    assert pulseLengths.length <= 8, "pulseLengths.length should be <= 8"
#    assert typeof pulses is "string", "pulses should be a string"
#    pulseLengthsArgs = ""
#    i = 0
#    for pl in pulseLengths
#      pulseLengthsArgs += " #{pl}"
#      i++
#    while i < 8
#      pulseLengthsArgs += " 0"
#      i++
#    return @writeAndWait("RF send #{pin} #{repeats} #{pulseLengthsArgs} #{pulses}\n")


#  _handleRFControl: (cmd, args) ->
#    unless args.length is 10 and args[0] is 'receive'
#      console.log "Unknown RF response \"#{args.join(" ")}\""
#      return
#
#    strSeq = args[1]
#    for a in args[2..9]
#      strSeq += " #{a}"
#
#    info = rfcontrol.prepareCompressedPulses(strSeq)
#    @_emitReceive(info)
#    return
#
#  provessExternalReceive: (pulseLengths, pulses) ->
#    info = rfcontrol.sortCompressedPulses(pulseLengths, pulses)
#    @_emitReceive(info)
#    return
#
#  _emitReceive: (info) ->
#    @emit 'rfReceive', info
#    results = rfcontrol.decodePulses(info.pulseLengths, info.pulses)
#    for r in results
#      @emit 'rf', r
#    return

#  @getRfProtocol: (protocolName) -> rfcontrol.getProtocol(protocolName)
#
#  @getAllRfProtocols: () -> rfcontrol.getAllProtocols()

module.exports = Board