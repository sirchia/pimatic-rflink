events = require 'events'

class Protocol extends events.EventEmitter

  @_ACK: [
    "PONG", # reply to PING
    "DEBUG", # covers reply of sent RFDEBUG, RFUDEBUG and QRFDEBUG en-/disable commands
    "RFLink Gateway", # covers reply of VERSION and welcome message
    "OK" # reply to all correctly processed RF commands
  ]

  @_NACK: [
    "CMD UNKNOWN" #received when command could not be processed
  ]

  @_DECODE: {
    id: (value) -> return parseInt(value, 16)
    switch: (value) -> return value
    cmd: (value) -> # ON/OFF/ALLON/ALLOFF
      result = {}
      if value.indexOf('SET_LEVEL') > -1
        result.level = @set_level(value.split('=')[1])
      else
        result.all = value.indexOf('ALL') > -1
        result.state = value.indexOf('ON') > -1
      return result
    set_level: (value) ->
      result = Math.round(parseInt(value) * 99 / 15) + 1 # 1-100 %
      result = Math.max(1, Math.min(100, result))
      result = parseFloat(result)
      if isNaN(result)
        result = 0
      return result
    temp: (value) -> # celcius
      result = parseInt(value, 16)
      if result >= 32768
        result = 32768 - result
      return result / 10.0
    hum: (value) -> return parseInt(value) # 0-100 %
    baro: (value) -> return parseInt(value, 16)
    hstatus: (value) -> return parseInt(value) # 0=Normal, 1=Comfortable, 2=Dry, 3=Wet
    bforecast: (value) -> return parseInt(value) # 0=No Info/Unknown, 1=Sunny, 2=Partly Cloudy, 3=Cloudy, 4=Rain
    uv: (value) -> return parseInt(value, 16)
    lux: (value) -> return parseInt(value, 16)
    bat: (value) -> return value # OK/LOW
    rain: (value) -> return parseInt(value, 16) / 10.0 # mm
    rainrate: (value) -> return parseInt(value, 16) / 10.0 # mm
    raintot: (value) -> return parseInt(value, 16) / 10.0 # mm
    winsp: (value) -> return parseInt(value, 16) / 10.0 # km. p/h
    awinsp: (value) -> return parseInt(value, 16) / 10.0 # km. p/h
    wings: (value) -> return parseInt(value, 16) # km. p/h
    windir: (value) -> return parseInt(value) * 360 / 15.0 # 0-360 degrees
    winchl: (value) -> return Protocol._DECODE[temp](value) # celcius
    wintmp: (value) -> return Protocol._DECODE[temp](value) # celcius
    chime: (value) -> return parseInt(value)
    smokealert: (value) -> return value # ON/OFF
    pir: (value) -> return value # ON/OFF
    co2: (value) -> return parseInt(value)
    sound: (value) -> return parseInt(value)
    kwatt: (value) -> return parseInt(value, 16)
    watt: (value) -> return parseInt(value, 16)
    current: (value) -> return parseInt(value)
    current2: (value) -> return parseInt(value)
    current3: (value) -> return parseInt(value)
    dist: (value) -> return parseInt(value)
    meter: (value) -> return parseInt(value)
    volt: (value) -> return parseInt(value)
    rgbw: (value) -> return parseInt(value)
  }

  @_ENCODE: {
    id: (value) ->
      stringVal = value.toString(16);
      if (stringVal.length < 6)
        return ('000000' + stringVal).slice(-6)
      else
        return stringVal
    switch: (value) -> return value
    cmd: (value) -> # ON/OFF/ALLON/ALLOFF
      result = null
      if value.state
        result = 'ON'
      else
        result = 'OFF'

      if value.all
        result = 'ALL'.concat(result)

      return result

    set_level: (value) -> return Math.round(value * 15 / 100).toString() # 0-100 % -> 0-15
    temp: (value) -> # celcius
      result = value * 10
      if result < 0
        result += 32768
      return result.toString(16)
    hum: (value) -> return value.toString() # 0-100 %
    baro: (value) -> return value.toString(16)
    hstatus: (value) -> return value.toString() # 0=Normal, 1=Comfortable, 2=Dry, 3=Wet
    bforecast: (value) -> return value.toString() # 0=No Info/Unknown, 1=Sunny, 2=Partly Cloudy, 3=Cloudy, 4=Rain
    uv: (value) -> return value.toString(16)
    lux: (value) -> return value.toString(16)
    bat: (value) -> return value # OK/LOW
    rain: (value) -> return parseInt(value * 10).toString(16) # mm
    rainrate: (value) -> return parseInt(value * 10).toString(16) # mm
    raintot: (value) -> return parseInt(value * 10).toString(16) # mm
    winsp: (value) -> return parseInt(value * 10).toString(16) # km. p/h
    awinsp: (value) -> return parseInt(value * 10).toString(16) # km. p/h
    wings: (value) -> return value.toString(16) # km. p/h
    windir: (value) -> return parseInt(value * 15 / 360).toString() # 0-360 degrees
    winchl: (value) -> return Protocol._ENCODE[temp](value)
    wintmp: (value) -> return Protocol._ENCODE[temp](value)
    chime: (value) -> return value.toString()
    smokealert: (value) -> return value # ON/OFF
    pir: (value) -> return value # ON/OFF
    co2: (value) -> return value.toString()
    sound: (value) -> return value.toString()
    kwatt: (value) -> return value.toString(16)
    watt: (value) -> return value.toString(16)
    current: (value) -> return value.toString()
    current2: (value) -> return value.toString()
    current3: (value) -> return value.toString()
    dist: (value) -> return value.toString()
    meter: (value) -> return value.toString()
    volt: (value) -> return value.toString()
    rgbw: (value) -> return value.toString()
  }



  decodeLine: (line) ->
    event = {}
    lineElements = line.slice(0, -1).split(";")

    event.node = lineElements[0]
    event.seq = lineElements[1]
    event.name = lineElements[2]

    labels = lineElements.slice(3)

    if event.name is 'DEBUG'
      event.debug = labels.concat(";")
      return event

    event.ackResponse = true for ack in Protocol._ACK when event.name and event.name.indexOf(ack) > -1
    event.ackResponse = false for nack in Protocol._NACK when event.name and event.name.indexOf(nack) > -1

    if not event.ackResponse?
      for label in labels
        labelElements = label.split("=")
        attributeName = labelElements[0].toLowerCase()
        try event[attributeName] = @decodeAttribute(attributeName, labelElements[1])
        catch e
          @emit 'warning', "Could not decode value #{labelElements[1]} for attribute #{attributeName} (#{e.message})"

    return event

  encodeLine: (event) ->
    line = '10;'

    if event.name?
      line = line.concat(event.name, ";")
    if event.id?
      line = line.concat(@encodeAttribute('id', event.id), ";")
    if event.switch?
      line = line.concat(@encodeAttribute('switch', event.switch), ";")

    return line.concat(event.action, ";\n")


  decodeAttribute: (name, value) ->
    return Protocol._DECODE[name]?(value);

  encodeAttribute: (name, value) ->
    if name of Protocol._ENCODE
      return Protocol._ENCODE[name] value;
    else
      return value


  switchEventMatches: (event, protocol) ->
    return @eventMatches(event, protocol) and
      (event.cmd?.all or event.switch is @decodeAttribute('switch', protocol.switch))

  eventMatches: (event, protocol) ->
    return event.name is  protocol.name and
      event.id is @decodeAttribute('id', protocol.id)


module.exports = Protocol
