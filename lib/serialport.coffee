events = require 'events'

serialport = require("serialport")
SerialPort = serialport.SerialPort

Promise = require 'bluebird'
Promise.promisifyAll(SerialPort.prototype)


class SerialPortDriver extends events.EventEmitter

  constructor: (protocolOptions)->
    @connected = false

    @serialPort = new SerialPort(protocolOptions.serialDevice, {
      baudrate: protocolOptions.baudrate,
      parser: serialport.parsers.readline("\r\n")
    }, false)

    @serialPort.on('error', (error) =>
      @emit('error', error)
    )

    @serialPort.on('close', =>
      @connected = false
      @emit 'close'
    )

    @serialPort.on('open', =>
      @connected = true
      @emit 'open'
    )

    # setup data listner
    @serialPort.on('data', (data) =>
# Sanitize data
      line = data.replace(/\0/g, '').trim()
      @emit('data', line)
      @emit('line', line)
    )


  connect: (timeout, retries) ->
    if @connected
      @emit 'warning', 'connect called while already connected'
      return Promise.resolve(false)

    return @serialPort.openAsync().then( =>

      return new Promise((resolve) =>
        if (@connected)
          resolve()
        else
          @once("open", resolve)

      ).timeout(timeout).catch( (err) =>
        if err.name is "TimeoutError" and retries > 0
          # try to reconnect
          return @connect(timeout, retries-1)
        else
          throw err
      )
    )

  disconnect: ->
    unless @connected
      @emit 'warning', 'disconnect called while not connected'
      return Promise.resolve(false)

    return @serialPort.closeAsync()

  write: (data) ->
    unless @connected
      throw new Error "Tried to send data '#{data}' while we were not connected"
    @emit 'send', data
    @serialPort.writeAsync(data)

module.exports = SerialPortDriver
