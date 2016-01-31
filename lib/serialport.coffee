events = require 'events'

serialport = require("serialport")
SerialPort = serialport.SerialPort

Promise = require 'bluebird'
Promise.promisifyAll(SerialPort.prototype)

class SerialPortDriver extends events.EventEmitter

  constructor: (@protocolOptions) ->

  _createSerialPort: ->
    @serialPort = new SerialPort(@protocolOptions.serialDevice, {
      baudrate: @protocolOptions.baudrate,
      parser: serialport.parsers.readline("\r\n")
    }, false)

    @serialPort.on('open', =>
      @emit 'debug', 'Connection to RFLink device opened'
      @emit 'open'
    )

    @serialPort.on('error', (error) =>
      @emit('error', error)
    )

    @serialPort.on('close', =>
      @emit 'debug', 'Close event from serial device'
      @emit 'close'
    )

    # setup data listner
    @serialPort.on('data', (data) =>
      # Sanitize data
      line = data.replace(/\0/g, '').trim()
      @emit('data', line)
    )


  connect: =>
    if @serialPort?.isOpen()
      console.trace 'connect'
      @emit 'warning', 'Connect called while already connected'
      return Promise.resolve(false)

    @emit 'debug', 'Opening connection to RFLink device...'

    # we recreate the serial port as subsequent open/close/open does not seem to work
    @_createSerialPort()

    return @serialPort.openAsync().then( =>

      return new Promise((resolve) =>
        if (@serialPort.isOpen())
          resolve()
        else
          @emit 'debug', 'Not yet connected after serial port was opened, schedule open event callback'
          @serialPort.once("open", resolve)

      )
    )

  disconnect: =>
    unless @serialPort?.isOpen()
      @emit 'warning', 'Disconnect called while not connected'
      return Promise.resolve(false)

    return @serialPort.closeAsync().then(@serialPort = undefined)

  write: (data) =>
    unless @serialPort?.isOpen()
      throw new Error "Tried to send data '#{data.trim()}' while we were not connected"

    @emit 'send', data
    @serialPort.writeAsync(data)

  isConnected: ->
    return @serialPort?.isOpen()

module.exports = SerialPortDriver
