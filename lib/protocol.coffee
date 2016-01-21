events = require 'events'

class Protocol extends events.EventEmitter

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
    set_level: (value) -> return Math.round(parseInt(value) * 99 / 15) + 1 # 1-100 %
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
    rain: (value) -> return parseInt(value, 16) # mm
    raintot: (value) -> return parseInt(value, 16) # mm
    winsp: (value) -> return parseInt(value, 16) / 10.0 # km. p/h
    awinsp: (value) -> return parseInt(value, 16) / 10.0 # km. p/h
    wings: (value) -> return parseInt(value, 16) # km. p/h
    windir: (value) -> return parseInt(value) * 100 / 15 # 0-360 degrees
    winchl: (value) -> return parseInt(value, 16)
    wintmp: (value) -> return parseInt(value, 16)
    chime: (value) -> return parseInt(value)
    smokealaert: (value) -> return value # ON/OFF
    pir: (value) -> return value # ON/OFF
    co2: (value) -> return parseInt(value)
    sound: (value) -> return parseInt(value)
    kwatt: (value) -> return parseInt(value)
    watt: (value) -> return parseInt(value)
    dist: (value) -> return parseInt(value)
    meter: (value) -> return parseInt(value)
    volt: (value) -> return parseInt(value)
    current: (value) -> return parseInt(value)
  }

  @_ENCODE: {
    id: (value) ->
      stringVal = value.toString(16);
      return stringVal.length >= 6 ? stringVal : ('000000' + stringVal).slice(-6)
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
      result = value.toString(16)
      if result >= 32768
        result = 32768 - result
      return result / 10.0
    hum: (value) -> return value.toString() # 0-100 %
    baro: (value) -> return value.toString(16)
    hstatus: (value) -> return value.toString() # 0=Normal, 1=Comfortable, 2=Dry, 3=Wet
    bforecast: (value) -> return value.toString() # 0=No Info/Unknown, 1=Sunny, 2=Partly Cloudy, 3=Cloudy, 4=Rain
    uv: (value) -> return value.toString(16)
    lux: (value) -> return value.toString(16)
    bat: (value) -> return value # OK/LOW
    rain: (value) -> return value.toString(16) # mm
    raintot: (value) -> return value.toString(16) # mm
    winsp: (value) -> return parseInt(value * 10).toString(16) # km. p/h
    awinsp: (value) -> return parseInt(value * 10).toString(16) # km. p/h
    wings: (value) -> return value.toString(16) # km. p/h
    windir: (value) -> return parseInt(value * 15 / 100).toString() # 0-360 degrees
    winchl: (value) -> return value.toString(16)
    wintmp: (value) -> return value.toString(16)
    chime: (value) -> return value.toString()
    smokealaert: (value) -> return value # ON/OFF
    pir: (value) -> return value # ON/OFF
    co2: (value) -> return value.toString()
    sound: (value) -> return value.toString()
    kwatt: (value) -> return value.toString()
    watt: (value) -> return value.toString()
    dist: (value) -> return value.toString()
    meter: (value) -> return value.toString()
    volt: (value) -> return value.toString()
    current: (value) -> return value.toString()
  }



  decodeLine: (line) ->
    event = {}
    lineElements = line.slice(0, -1).split(";")

    event.node = lineElements[0]
    event.seq = lineElements[1]

    if lineElements[2] is 'DEBUG'
      event.debug = lineElements.slice(3).concat(";")
    else if lineElements[2] is 'PONG' or lineElements[2].indexOf("DEBUG") > -1 or lineElements[2].indexOf("RFLink Gateway") > -1
      event.ack = lineElements[2]
    else
      event.name = lineElements[2]

    labels = lineElements.slice(3)

    for label in labels
      labelElements = label.split("=")
      attributeName = labelElements[0].toLowerCase()
      event[attributeName] = @decodeAttribute(attributeName, labelElements[1])

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

    @emit 'warning', ' could not decode attribute ' + name + ' with value ' + value
    return value

  encodeAttribute: (name, value) ->
    if name of Protocol._ENCODE
      return Protocol._ENCODE[name] value;
    else
      @emit 'warning', ' could not encode attribute ' + name + ' with value ' + value
      return value


  switchEventMatches: (event, protocol) ->
    return @eventMatches(event, protocol) and
      (event.cmd?.all or event.switch is @decodeAttribute('switch', protocol.switch))

  eventMatches: (event, protocol) ->
    return event.name is  protocol.name and
      event.id is @decodeAttribute('id', protocol.id)


module.exports = Protocol