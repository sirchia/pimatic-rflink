module.exports = (env) ->

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'

  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  M = env.matcher

  Board = require './lib/board'

  Protocol = require './lib/protocol'

  class RFLinkPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      #disable logginf og rfdebug info when generic debug is on to prevent redundant debug logging
      @rfdebug = !@config.debug && (@config.rfdebug || @config.rfudebug || @config.qrfdebug)

      @protocol = new Protocol

      @protocol.on("warning", (warning) =>
        env.logger.warn warning
      )

      @board = new Board(@config.driverOptions, @protocol, @config.connectionTimeout, @config.reconnectInterval, @config.pingInterval)

      @board.on("data", (data) =>
        if @config.debug
          env.logger.debug "data: \"#{data}\""
      )

      @board.on("send", (data) =>
        if @config.debug
          env.logger.debug "send: \"#{data.trim()}\""
      )

      @board.on("rfdebug", (data) =>
        if @rfdebug
          env.logger.debug "rfdebug: \" #{data}\""
      )

      @board.on("connected", () =>
        env.logger.info("Connected to rflink device.")
        if @config.rfdebug
          env.logger.info("Enabling RFDEBUG...")
          @board.enableRfDebug()
        if @config.rfudebug
          env.logger.info("Enabling RFUDEBUG...")
          @board.enableRfuDebug()
        if @config.qrfdebug
          env.logger.info("Enabling QRFDEBUG...")
          @board.enableQrfDebug()
      )

      @board.on("debug", (message) =>
        if @config.debug
          env.logger.debug message
      )

      @board.on("warning", (warning) =>
        env.logger.warn warning
      )

      @board.on("error", (error) =>
        env.logger.error("Error with connection to RFLink device: #{error.message}.")
        env.logger.error(error.stack)
      )

      @framework.on "after init", ( =>
        @board.connect(@config.connectionTimeout)
      )

      @framework.on "destroy", ( =>
        @board.destroy()
      )

      deviceConfigDef = require("./device-config-schema")

      deviceClasses = [
        RFLinkSwitch
        RFLinkDimmer
        RFLinkData
        RFLinkPir
        RFLinkContactSensor
#        RFLinkShutter
#        RFLinkGenericSensor
      ]

      for Cl in deviceClasses
        do (Cl) =>
          dcd = deviceConfigDef[Cl.name]
          @framework.deviceManager.registerDeviceClass(Cl.name, {
            configDef: dcd
            createCallback: (deviceConfig, lastState) => 
              device = new Cl(deviceConfig, lastState, @board, @config, @protocol)
              return device
          })

      @framework.ruleManager.addPredicateProvider(new RFEventPredicateProvider(@framework))

#      if @config.apikey? and @config.apikey.length > 0
#        @framework.userManager.addAllowPublicAccessCallback( (req) =>
#          return req.url.match(/^\/rflink\/received.*$/)?
#        )
#        app.get('/rflink/received', (req, res) =>
#          if req.query.apikey isnt @config.apikey
#            res.end('Invalid apikey')
#            return
#          buckets = JSON.parse(req.query.buckets)
#          pulses = req.query.pulses
#          @board.provessExternalReceive(buckets, pulses)
#          res.end('ACK')
#        )

  rflinkPlugin = new RFLinkPlugin()

  logDebug = (config, protocol, options) ->
    message = "Sending Protocol: #{protocol.name}"
    for field, content of options
      message += " #{field}: #{content}"
    env.logger.debug(message)

  sendToSwitchesMixin = (protocols, state = false) ->
    pending = []
    for p in protocols
      do (p) =>
        unless p.send is false
          event = _.clone(p)
          event.id = @protocol.decodeAttribute('id',event.id)
          delete event.send
          delete event.receive
          event.action= @protocol.encodeAttribute('cmd', {'state': state})
          pending.push @board.connectionReady.then( =>
            if @_pluginConfig.debug
              logDebug(@_pluginConfig, p, event)
            return @board.encodeAndWriteEvent(event)
          )
    return Promise.all(pending)

  sendToDimmersMixin = (protocols, level = 0) ->
    pending = []
    for p in protocols
      do (p) =>
        unless p.send is false
          event = _.clone(p)
          event.id = @protocol.decodeAttribute('id',event.id)
          delete event.send
          delete event.receive
          if level is 0
            event.action= @protocol.encodeAttribute('cmd', {'state': false})
          else
            event.action= @protocol.encodeAttribute('set_level', level)
          pending.push @board.connectionReady.then( =>
            if @_pluginConfig.debug
              logDebug(@_pluginConfig, p, event)
            return @board.encodeAndWriteEvent(event)
          )
    return Promise.all(pending)


  class RFLinkSwitch extends env.devices.PowerSwitch

    constructor: (@config, lastState, @board, @_pluginConfig, @protocol) ->
      @id = @config.id
      @name = @config.name
      @_state = lastState?.state?.value

      @board.on('rf', (event) =>
        for p in @config.protocols
          unless p.receive is false
            if @protocol.switchEventMatches(event, p)
              @emit('rf', event.cmd.state) # used by the RFEventPredicateHandler
              @_setState(event.cmd.state)
        )
      super()

    _sendStateToSwitches: sendToSwitchesMixin

    changeStateTo: (state) ->
      unless @config.forceSend
        if @_state is state then return Promise.resolve true
      @_sendStateToSwitches(@config.protocols, state).then( =>
        @_setState(state)
      )


  class RFLinkDimmer extends env.devices.DimmerActuator
    _lastdimlevel: null

    constructor: (@config, lastState, @board, @_pluginConfig, @protocol) ->
      @id = @config.id
      @name = @config.name
      @_dimlevel = lastState?.dimlevel?.value or 0
      @_lastdimlevel = lastState?.lastdimlevel?.value or 100
      @_state = lastState?.state?.value or off

      @board.on('rf', (event) =>
        for p in @config.protocols
          unless p.receive is false
            if @protocol.switchEventMatches(event, p)
              if event.cmd.level?
                @_setDimlevel(event.cmd.level)
              else
                if event.cmd.state is false
                  unless @_dimlevel is 0
                    @_lastdimlevel = @_dimlevel
                  @_setDimlevel(0)
                else
                  @_setDimlevel(@_lastdimlevel)
        )
      super()

    _sendLevelToDimmers: sendToDimmersMixin

    turnOn: -> @changeDimlevelTo(@_lastdimlevel)

    changeDimlevelTo: (level) ->
      unless @config.forceSend
        if @_dimlevel is level then return Promise.resolve true

      unless @_dimlevel is 0
        @_lastdimlevel = @_dimlevel

      @_sendLevelToDimmers(@config.protocols, level).then( =>
        @_setDimlevel(level)
      )
      

  class RFLinkContactSensor extends env.devices.ContactSensor

    constructor: (@config, lastState, @board, @_pluginConfig, @protocol) ->
      @id = @config.id
      @name = @config.name
      @_contact = lastState?.contact?.value or false

      @board.on('rf', (event) =>
        for p in @config.protocols
          if @protocol.switchEventMatches(event, p)
            if @config.invert is false
              @_setContact(event.cmd.state)
            else
              @_setContact(!event.cmd.state)
            if @config.autoReset is true
              clearTimeout(@_resetContactTimeout)
              @_resetContactTimeout = setTimeout(( =>
                @_setContact(!event.cmd.state)
              ), @config.resetTime)
      )  
      super()

#  class RFLinkShutter extends env.devices.ShutterController
#
#    constructor: (@config, lastState, @board, @_pluginConfig) ->
#      @id = @config.id
#      @name = @config.name
#      @_position = lastState?.position?.value or 'stopped'
#
#      for p in @config.protocols
#        _protocol = Board.getRfProtocol(p.name)
#        unless _protocol?
#          throw new Error("Could not find a protocol with the name \"#{p.name}\".")
#
#      @board.on('rf', (event) =>
#        for p in @config.protocols
#          match = doesProtocolMatch(event, p)
#          unless match
#            return
#          now = new Date().getTime()
#          # ignore own send messages
#          if (now - @_lastSendTime) < 3000
#            return
#          if @_position is 'stopped'
#            @_setPosition(if event.values.state then 'up' else 'down')
#          else
#            @_setPosition('stopped')
#      )
#      super()
#
#    _sendStateToSwitches: sendToSwitchesMixin
#
#    stop: ->
#      unless @config.forceSend
#        if @_position is 'stopped' then return Promise.resolve()
#      @_sendStateToSwitches(@config.protocols, @_position is 'up').then( =>
#        @_setPosition('stopped')
#      )
#
#      return Promise.resolve()
#
#    # Returns a promise that is fulfilled when done.
#    moveToPosition: (position) ->
#      unless @config.forceSend
#        if position is @_position then return Promise.resolve()
#      if position is 'stopped' then return @stop()
#      else return @_sendStateToSwitches(@config.protocols, position is 'up').then( =>
#        @_lastSendTime = new Date().getTime()
#        @_setPosition(position)
#      )
#
#
  class RFLinkPir extends env.devices.PresenceSensor

    constructor: (@config, lastState, @board, @_pluginConfig, @protocol) ->
      @id = @config.id
      @name = @config.name
      @_presence = lastState?.presence?.value or false
      
      resetPresence = ( =>
        @_setPresence(no)
      )
      
      @board.on('rf', (event) =>
        for p in @config.protocols
          if @protocol.switchEventMatches(event, p)
            if @config.invert is false
              @_setPresence(event.cmd.state)
            else
              @_setPresence(!event.cmd.state)
            if @config.autoReset is true
              @_resetPresenceTimeout = setTimeout(resetPresence, @config.resetTime)
      )  
      super()

    getPresence: -> Promise.resolve @_presence

  class RFLinkData extends env.devices.Sensor

    constructor: (@config, lastState, @board, @_pluginConfig, @protocol) ->
      @id = @config.id
      @name = @config.name
      @_temp = lastState?.temp?.value or 0
      @_hum = lastState?.hum?.value or 0
      @_baro = lastState?.baro?.value or 0
      @_hstatus = lastState?.hstatus?.value or 0
      @_bforecast = lastState?.bforecast?.value or 0
      @_uv = lastState?.uv?.value or 0
      @_lux = lastState?.lux?.value or 0
      @_bat = lastState?.bat?.value or ""
      @_rain = lastState?.rain?.value or 0
      @_rainrate = lastState?.rainrate?.value or 0
      @_raintot = lastState?.raintot?.value or 0
      @_winsp = lastState?.winsp?.value or 0
      @_awinsp = lastState?.awinsp?.value or 0
      @_wings = lastState?.wings?.value or 0
      @_windir = lastState?.windir?.value or 0
      @_winchl = lastState?.winchl?.value or 0
      @_wintmp = lastState?.wintmp?.value or 0
      @_co2 = lastState?.co2?.value or 0
      @_sound = lastState?.sound?.value or 0
      @_kwatt = lastState?.kwatt?.value or 0
      @_watt = lastState?.watt?.value or 0
      @_current = lastState?.current?.value or 0
      @_current2 = lastState?.current2?.value or 0
      @_current3 = lastState?.current3?.value or 0
      @_dist = lastState?.dist?.value or 0
      @_meter = lastState?.meter?.value or 0
      @_volt = lastState?.volt?.value or 0

      @attributes = {}

      for s in @config.values
        switch s
          when "temp"
            if !@attributes.temp?
              @attributes.temp = {
                description: "the measured temperature"
                type: "number"
                unit: '°C'
                acronym: 'T'
              }
          when "hum"
            if !@attributes.hum?
              @attributes.hum = {
                description: "the measured humidity"
                type: "number"
                unit: '%'
                acronym: 'RH'
              }
          when "baro"
            if !@attributes.baro?
              @attributes.baro = {
                description: "the measured barometric pressure"
                type: "number"
                unit: 'mbar'
                acronym: 'PB'
              }
          when "hstatus"
            if !@attributes.hstatus?
              @attributes.hstatus = {
                description: "indication of the weather 0=Normal, 1=Comfortable, 2=Dry, 3=Wet"
                type: "number"
                unit: ''
                acronym: 'ACTUAL'
              }
          when "bforecast"
            if !@attributes.bforecast?
              @attributes.bforecast = {
                description: "prediction of the weather 0=No Info/Unknown, 1=Sunny, 2=Partly Cloudy, 3=Cloudy, 4=Rain"
                type: "number"
                unit: ''
                acronym: 'FORECAST'
              }
          when "uv"
            if !@attributes.uv?
              @attributes.uv = {
                description: "the measured UV intensity"
                type: "number"
                unit: ''
                acronym: 'UV'
              }
          when "lux"
            if !@attributes.lux?
              @attributes.lux = {
                description: "the measured light intensity"
                type: "number"
                unit: 'lx'
                acronym: 'LUM'
              }
          when "bat"
            if !@attributes.bat?
              @attributes.bat = {
                description: "the battery status"
                type: "string"
                unit: ''
                acronym: 'BAT'
              }
          when "rain"
            if !@attributes.rain?
              @attributes.rain = {
                description: "the measured rain rate"
                type: "number"
                unit: 'mm'
                acronym: 'RAIN'
              }
          when "rainrate"
            if !@attributes.rainrate?
              @attributes.rainrate = {
                description: "the measured rain rate"
                type: "number"
                unit: 'mm'
                acronym: 'RAINR'
              }
          when "raintot"
            if !@attributes.raintot?
              @attributes.raintot = {
                description: "the measured total rain per 24 hours"
                type: "number"
                unit: 'mm'
                acronym: 'RAINT'
              }
          when "winsp"
            if !@attributes.winsp?
              @attributes.winsp = {
                description: "the measured wind speed"
                type: "number"
                unit: 'km/h'
                acronym: 'WIND'
              }
          when "awinsp"
            if !@attributes.winsp?
              @attributes.winsp = {
                description: "the measured average wind speed"
                type: "number"
                unit: 'km/h'
                acronym: 'MWIND'
              }
          when "wings"
            if !@attributes.wings?
              @attributes.wings = {
                description: "the measured wind gust"
                type: "number"
                unit: 'km/h'
                acronym: 'GUST'
              }
          when "windir"
            if !@attributes.windir?
              @attributes.windir = {
                description: "the measured wind direction 0-360"
                type: "number"
                unit: ''
                acronym: 'WDIR'
              }
          when "winchil"
            if !@attributes.winchil?
              @attributes.winchil = {
                description: "the measured wind chill"
                type: "number"
                unit: '°C'
                acronym: 'CHILL'
              }
          when "wintmp"
            if !@attributes.wintmp?
              @attributes.wintmp = {
                description: "the measured wind temperature"
                type: "number"
                unit: '°C'
                acronym: 'WTEMP'
              }
          when "co2"
            if !@attributes.co2?
              @attributes.co2 = {
                description: "the measured CO2 air quality"
                type: "number"
                unit: ''
                acronym: 'CO2'
              }
          when "sound"
            if !@attributes.sound?
              @attributes.sound = {
                description: "the measured noise level"
                type: "number"
                unit: ''
                acronym: 'SOUND'
              }
          when "kwatt"
            if !@attributes.kwatt?
              @attributes.kwatt = {
                description: "the measured power value"
                type: "number"
                unit: 'kW'
                acronym: 'POWER'
              }
          when "watt"
            if !@attributes.watt?
              @attributes.watt = {
                description: "the measured power value"
                type: "number"
                unit: 'W'
                acronym: 'POWER'
              }
          when "current"
            if !@attributes.current?
              @attributes.current = {
                description: "Current phase 1"
                type: "number"
                unit: 'A'
                acronym: 'I'
              }
          when "current2"
            if !@attributes.current2?
              @attributes.current2 = {
                description: "Current phase 2"
                type: "number"
                unit: 'A'
                acronym: 'I2'
              }
          when "current3"
            if !@attributes.current3?
              @attributes.current3 = {
                description: "Current phase 3"
                type: "number"
                unit: 'A'
                acronym: 'I3'
              }
          when "dist"
            if !@attributes.dist?
              @attributes.dist = {
                description: "the measured distance value"
                type: "number"
                unit: 'mm'
                acronym: 'DISTANCE'
              }
          when "meter"
            if !@attributes.meter?
              @attributes.meter = {
                description: "the measured meter value"
                type: "number"
                unit: ''
                acronym: 'METER'
              }
          when "volt"
            if !@attributes.volt?
              @attributes.volt = {
                description: "the measured voltage value"
                type: "number"
                unit: 'V'
                acronym: 'U'
              }
          else
            throw new Error(
              "Values should be one of: temp, hum, baro, hstatus, bforecast, uv, lux, bat, rain, raintot, winsp, awinsp, wings, windir, winchil, wintmp, co2, sound, kwatt, watt, dist, meter, volt, current"
            )


      @board.on('rf', (event) =>
        for p in @config.protocols
          if @protocol.eventMatches(event, p)
            if event.temp?
              @_temp = event.temp
              @emit "temp", @_temp
            if event.hum?
              @_hum = event.hum
              @emit "hum", @_hum
            if event.baro?
              @_baro = event.baro
              @emit "baro", @_baro
            if event.hstatus?
              @_hstatus = event.hstatus
              @emit "hstatus", @_hstatus
            if event.bforecast?
              @_bforecast = event.bforecast
              @emit "bforecast", @_bforecast
            if event.uv?
              @_uv = event.uv
              @emit "uv", @_uv
            if event.lux?
              @_lux = event.lux
              @emit "lux", @_lux
            if event.bat?
              @_bat = event.bat
              @emit "bat", @_bat
            if event.rain?
              @_rain = event.rain
              @emit "rain", @_rain
            if event.rainrate?
              @_rain = event.rainrate
              @emit "rainrate", @_rainrate
            if event.raintot?
              @_raintot = event.raintot
              @emit "raintot", @_raintot
            if event.winsp?
              @_winsp = event.winsp
              @emit "winsp", @_winsp
            if event.awinsp?
              @_awinsp = event.awinsp
              @emit "awinsp", @_awinsp
            if event.wings?
              @_wings = event.wings
              @emit "wings", @_wings
            if event.windir?
              @_windir = event.windir
              @emit "windir", @_windir
            if event.winchl?
              @_winchl = event.winchl
              @emit "winchl", @_winchl
            if event.wintmp?
              @_wintmp = event.wintmp
              @emit "wintmp", @_wintmp
            if event.co2?
              @_co2 = event.co2
              @emit "co2", @_co2
            if event.sound?
              @_sound = event.sound
              @emit "sound", @_sound
            if event.kwatt?
              @_kwatt = event.kwatt
              @emit "kwatt", @_kwatt
            if event.watt?
              @_watt = event.watt
              @emit "watt", @_watt
            if event.current?
              @_current = event.current
              @emit "current", @_current
            if event.current2?
              @_current2 = event.current2
              @emit "current2", @_current2
            if event.current3?
              @_current3 = event.current3
              @emit "current3", @_current3
            if event.dist?
              @_dist = event.dist
              @emit "dist", @_dist
            if event.meter?
              @_meter = event.meter
              @emit "meter", @_meter
            if event.volt?
              @_volt = event.volt
              @emit "volt", @_volt
      )
      super()

    getTemp: -> Promise.resolve @_temp
    getHum: -> Promise.resolve @_hum
    getBaro: -> Promise.resolve @_baro
    getHstatus: -> Promise.resolve @_hstatus
    getBforecast: -> Promise.resolve @_bforecast
    getUv: -> Promise.resolve @_uv
    getLux: -> Promise.resolve @_lux
    getBat: -> Promise.resolve @_bat
    getRain: -> Promise.resolve @_rain
    getRainrate: -> Promise.resolve @_rainrate
    getRaintot: -> Promise.resolve @_raintot
    getWinsp: -> Promise.resolve @_winsp
    getAwinsp: -> Promise.resolve @_awinsp
    getWings: -> Promise.resolve @_wings
    getWindir: -> Promise.resolve @_windir
    getWinchl: -> Promise.resolve @_winchl
    getWintmp: -> Promise.resolve @_wintmp
    getCo2: -> Promise.resolve @_co2
    getSound: -> Promise.resolve @_sound
    getKwatt: -> Promise.resolve @_kwatt
    getWatt: -> Promise.resolve @_watt
    getCurrent: -> Promise.resolve @_current
    getCurrent2: -> Promise.resolve @_current2
    getCurrent3: -> Promise.resolve @_current3
    getDist: -> Promise.resolve @_dist
    getMeter: -> Promise.resolve @_meter
    getVolt: -> Promise.resolve @_volt


#  class RFLinkGenericSensor extends env.devices.Sensor
#
#    constructor: (@config, lastState, @board) ->
#      @id = @config.id
#      @name = @config.name
#
#      for p in @config.protocols
#        _protocol = Board.getRfProtocol(p.name)
#        unless _protocol?
#          throw new Error("Could not find a protocol with the name \"#{p.name}\".")
#        unless _protocol.type is "generic"
#          throw new Error("\"#{p.name}\" is not a generic protocol.")
#
#      @attributes = {}
#      for attributeConfig in @config.attributes
#        @_createAttribute(attributeConfig)
#
#      @_lastReceiveTimes = {}
#      @board.on('rf', (event) =>
#        for p in @config.protocols
#          match = doesProtocolMatch(event, p)
#          if match
#            for attributeConfig in @config.attributes
#              @_updateAttribute(attributeConfig, event)
#      )
#      super()
#
#    _createAttribute: (attributeConfig) ->
#      name = attributeConfig.name
#      if @attributes[name]?
#        throw new Error(
#          "Two attributes with the same name in RFLinkGenericSensor config \"#{name}\""
#        )
#      # Set description and label
#      @attributes[name] = {
#        description: name
#        label: (
#          if attributeConfig.label? and attributeConfig.label.length > 0 then attributeConfig.label
#          else name
#        )
#        type: "number"
#      }
#      # Set unit
#      if attributeConfig.unit? and attributeConfig.unit.length > 0
#        @attributes[name].unit = attributeConfig.unit
#
#      if attributeConfig.discrete?
#        @attributes[name].discrete = attributeConfig.discrete
#
#      if attributeConfig.acronym?
#        @attributes[name].acronym = attributeConfig.acronym
#
#      # generate getter:
#      @_createGetter(name, => Promise.resolve(@_attributesMeta[name].value))
#
#    _updateAttribute: (attributeConfig, event) ->
#      name = attributeConfig.name
#      now = (new Date()).getTime()
#      timeDelta = (
#        if @_lastReceiveTimes[name]? then (now - @_lastReceiveTimes[name])
#        else 9999999
#      )
#      if timeDelta < 2000
#        return
#
#      unless event.values.value?
#        return
#
#      unless event.values.type is attributeConfig.type
#        return
#
#      baseValue = attributeConfig.baseValue
#      decimalsDivider = Math.pow(10, attributeConfig.decimals)
#      value = event.values.value / decimalsDivider
#      value = -value if event.values.positive is false
#      value += baseValue
#      @emit name, value
#      @_lastReceiveTimes[name] = now

  ###
  The RF-Event Predicate Provider
  ----------------
  Provides predicates for the state of switch devices like:

  * _device_ receives on|off

  ####
  class RFEventPredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework) ->

    # ### parsePredicate()
    parsePredicate: (input, context) ->  

      rfSwitchDevices = _(@framework.deviceManager.devices)
        .filter( (device) => device instanceof RFLinkSwitch ).value()

      device = null
      state = null
      match = null

      M(input, context)
        .matchDevice(rfSwitchDevices, (next, d) =>
          next.match([' receives'])
            .match([' on', ' off'], (next, s) =>
              # Already had a match with another device?
              if device? and device.id isnt d.id
                context?.addError(""""#{input.trim()}" is ambiguous.""")
                return
              assert d?
              assert s in [' on', ' off']
              device = d
              state = s.trim() is 'on'
              match = next.getFullMatch()
          )
        )
 
      # If we have a match
      if match?
        assert device?
        assert state?
        assert typeof match is "string"
        # and state as boolean.
        return {
          token: match
          nextInput: input.substring(match.length)
          predicateHandler: new RFEventPredicateHandler(device, state)
        }
      else
        return null

  class RFEventPredicateHandler extends env.predicates.PredicateHandler

    constructor: (@device, @state) ->
    setup: ->
      lastTime = 0
      @rfListener = (newState) =>
        if @state is newState
          now = new Date().getTime()
          # suppress same values within 200ms
          if now - lastTime <= 200
            return
          lastTime = now
          @emit 'change', 'event' 
      @device.on 'rf', @rfListener
      super()
    getValue: -> Promise.resolve(false)
    destroy: -> 
      @device.removeListener "rf", @rfListener
      super()
    getType: -> 'event'

  return rflinkPlugin
