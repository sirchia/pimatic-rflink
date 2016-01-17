# #rflink configuration options
module.exports = {
  title: "RFLink config"
  type: "object"
  properties:
    driverOptions:
      title: "serialport driver options"
      type: "object"
      properties:
       serialDevice:
         description: "The name of the serial device to use"
         type: "string"
         default: "/dev/ttyUSB0"
       baudrate:
         description: "The baudrate to use for serial communication"
         type: "integer"
         default: 57600
    connectionTimeout:
      description: "Time to wait for ready package on connection"
      type: "integer"
      default: 5*60*1000 # 5min
    debug:
      description: "Log information for debugging, including received messages"
      type: "boolean"
      default: true
    rfdebug:
      description: "Log raw RF packets"
      type: "boolean"
      default: false
    rfudebug:
      description: "Log raw undecoded RF packets"
      type: "boolean"
      default: false
    qrfdebug:
      description: "Log raw undecoded RF packets"
      type: "boolean"
      default: false
}
