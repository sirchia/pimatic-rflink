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

      @board = new Board(@config.driverOptions, @protocol)

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
        return
      )

      @board.on("warning", (warning) =>
        env.logger.warn warning
      )

      @board.on("error", (error) =>
        env.logger.error("Error with connection to rflink device: #{error.message}.")
        env.logger.error(error.stack)
      )

      @pendingConnect = new Promise( (resolve, reject) =>
        @framework.on "after init", ( =>
          @board.connect(@config.connectionTimeout).then( =>

          ).then(resolve).catch( (err) =>
            env.logger.error("Couldn't connect to rflink device: #{err.message}.")
            env.logger.error(err.stack)
            reject(err)
          )
        )
      )

      deviceConfigDef = require("./device-config-schema")

      deviceClasses = [
        RFLinkSwitch
        RFLinkDimmer
#        RFLinkTemperature
#        RFLinkWeatherStation
#        RFLinkPir
#        RFLinkContactSensor
#        RFLinkShutter
#        RFLinkGenericSensor
      ]

      for Cl in deviceClasses
        do (Cl) =>
          dcd = deviceConfigDef[Cl.name]
          @framework.deviceManager.registerDeviceClass(Cl.name, {
            prepareConfig: (config) =>
              if config['class'] is "RFLinkButtonsDevice"
                for b in config.buttons
                  if b.protocol? and b.protocolOptions
                    b.protocols = [
                      { name: b.protocol, options: b.protocolOptions}
                    ]
                    delete b.protocol
                    delete b.protocolOptions
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
          pending.push rflinkPlugin.pendingConnect.then( =>
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
          pending.push rflinkPlugin.pendingConnect.then( =>
            if @_pluginConfig.debug
              logDebug(@_pluginConfig, p, event)
            return @board.encodeAndWriteEvent(event)
          )
    return Promise.all(pending)


  class RFLinkSwitch extends env.devices.PowerSwitch

    constructor: (@config, lastState, @board, @_pluginConfig, @protocol) ->
      @id = config.id
      @name = config.name
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
      @id = config.id
      @name = config.name
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
      

#  class RFLinkContactSensor extends env.devices.ContactSensor
#
#    constructor: (@config, lastState, @board, @_pluginConfig) ->
#      @id = config.id
#      @name = config.name
#      @_contact = lastState?.contact?.value or false
#
#      for p in config.protocols
#        _protocol = Board.getRfProtocol(p.name)
#        unless _protocol?
#          throw new Error("Could not find a protocol with the name \"#{p.name}\".")
#
#      @board.on('rf', (event) =>
#        for p in @config.protocols
#          match = doesProtocolMatch(event, p)
#          if match
#            hasContact = (
#              if event.values.contact? then event.values.contact
#              else (not event.values.state)
#            )
#            @_setContact(hasContact)
#            if @config.autoReset is true
#              clearTimeout(@_resetContactTimeout)
#              @_resetContactTimeout = setTimeout(( =>
#                @_setContact(!hasContact)
#              ), @config.resetTime)
#      )
#      super()
#
#  class RFLinkShutter extends env.devices.ShutterController
#
#    constructor: (@config, lastState, @board, @_pluginConfig) ->
#      @id = config.id
#      @name = config.name
#      @_position = lastState?.position?.value or 'stopped'
#
#      for p in config.protocols
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
#  class RFLinkPir extends env.devices.PresenceSensor
#
#    constructor: (@config, lastState, @board, @_pluginConfig) ->
#      @id = config.id
#      @name = config.name
#      @_presence = lastState?.presence?.value or false
#
#      for p in config.protocols
#        _protocol = Board.getRfProtocol(p.name)
#        unless _protocol?
#          throw new Error("Could not find a protocol with the name \"#{p.name}\".")
#        unless _protocol.type is "pir"
#          throw new Error("\"#{p.name}\" is not a PIR protocol.")
#
#      resetPresence = ( =>
#        @_setPresence(no)
#      )
#
#      @board.on('rf', (event) =>
#        for p in @config.protocols
#          match = doesProtocolMatch(event, p)
#          if match
#            unless @_setPresence is event.values.presence
#              @_setPresence(event.values.presence)
#            clearTimeout(@_resetPresenceTimeout)
#            if @config.autoReset is true
#              @_resetPresenceTimeout = setTimeout(resetPresence, @config.resetTime)
#      )
#      super()
#
#    getPresence: -> Promise.resolve @_presence
#
#
#  class RFLinkTemperature extends env.devices.TemperatureSensor
#
#    constructor: (@config, lastState, @board) ->
#      @id = config.id
#      @name = config.name
#      @_temperatue = lastState?.temperature?.value
#      @_humidity = lastState?.humidity?.value
#      @_lowBattery = lastState?.lowBattery?.value
#      @_battery = lastState?.battery?.value
#
#      hasTemperature = false
#      hasHumidity = false
#      hasLowBattery = false # boolean battery indicator
#      hasBattery = false # numeric battery indicator
#      isFahrenheit = config.isFahrenheit
#      for p in config.protocols
#        _protocol = Board.getRfProtocol(p.name)
#        unless _protocol?
#          throw new Error("Could not find a protocol with the name \"#{p.name}\".")
#        unless _protocol.type is "weather"
#          throw new Error("\"#{p.name}\" is not a weather protocol.")
#        hasTemperature = true if _protocol.values.temperature?
#        hasHumidity = true if _protocol.values.humidity?
#        hasLowBattery = true if _protocol.values.lowBattery?
#        hasBattery = true if  _protocol.values.battery?
#      @attributes = {}
#
#      if hasTemperature
#        if isFahrenheit then tempUnit = '°F'
#        else tempUnit = '°C'
#        @attributes.temperature = {
#          description: "the measured temperature"
#          type: "number"
#          unit: tempUnit
#          acronym: 'T'
#        }
#
#      if hasHumidity
#        @attributes.humidity = {
#          description: "the measured humidity"
#          type: "number"
#          unit: '%'
#          acronym: 'RH'
#        }
#
#      if hasLowBattery
#        @attributes.lowBattery = {
#          description: "the battery status"
#          type: "boolean"
#          labels: ["low", 'ok']
#          icon:
#            noText: true
#            mapping: {
#              'icon-battery-filled': false
#              'icon-battery-empty': true
#            }
#        }
#      if hasBattery
#        @attributes.battery = {
#          description: "the battery status"
#          type: "number"
#          unit: '%'
#          displaySparkline: false
#          icon:
#            noText: true
#            mapping: {
#              'icon-battery-empty': 0
#              'icon-battery-fuel-1': [0, 20]
#              'icon-battery-fuel-2': [20, 40]
#              'icon-battery-fuel-3': [40, 60]
#              'icon-battery-fuel-4': [60, 80]
#              'icon-battery-fuel-5': [80, 100]
#              'icon-battery-filled': 100
#            }
#        }
#
#      @board.on('rf', (event) =>
#        for p in @config.protocols
#          match = doesProtocolMatch(event, p)
#          if match
#            now = (new Date()).getTime()
#            timeDelta = (
#              if @_lastReceiveTime? then (now - @_lastReceiveTime)
#              else 9999999
#            )
#            # discard value if it is the same and was received just under two second ago
#            if timeDelta < 2000
#              return
#
#            if event.values.temperature?
#              variableManager = rflinkPlugin.framework.variableManager
#              processing = @config.processingTemp or "$value"
#              info = variableManager.parseVariableExpression(
#                processing.replace(/\$value\b/g, event.values.temperature)
#              )
#              variableManager.evaluateNumericExpression(info.tokens).then( (value) =>
#                @_temperatue = value
#                @emit "temperature", @_temperatue
#              )
#            if event.values.humidity?
#              variableManager = rflinkPlugin.framework.variableManager
#              processing = @config.processingHum or "$value"
#              info = variableManager.parseVariableExpression(
#                processing.replace(/\$value\b/g, event.values.humidity)
#              )
#              variableManager.evaluateNumericExpression(info.tokens).then( (value) =>
#                @_humidity = value
#                @emit "humidity", @_humidity
#              )
#            if event.values.lowBattery?
#              @_lowBattery = event.values.lowBattery
#              @emit "lowBattery", @_lowBattery
#            if event.values.battery?
#              @_battery = event.values.battery
#              @emit "battery", @_battery
#            @_lastReceiveTime = now
#      )
#      super()
#
#    getTemperature: -> Promise.resolve @_temperatue
#    getHumidity: -> Promise.resolve @_humidity
#    getLowBattery: -> Promise.resolve @_lowBattery
#    getBattery: -> Promise.resolve @_battery
#
#  class RFLinkWeatherStation extends env.devices.Sensor
#
#    constructor: (@config, lastState, @board) ->
#      @id = config.id
#      @name = config.name
#      @_windGust = lastState?.windGust?.value or 0
#      @_avgAirspeed = lastState?.avgAirspeed?.value or 0
#      @_windDirection = lastState?.windDirection?.value or 0
#      @_temperatue = lastState?.temperature?.value or 0
#      @_humidity = lastState?.humidity?.value or 0
#      @_rain = lastState?.rain?.value or 0
#
#      hasWindGust = false
#      hasAvgAirspeed = false
#      hasWindDirection = false
#      hasTemperature = false
#      hasHumidity = false
#      hasRain = false
#      for p in config.protocols
#        _protocol = Board.getRfProtocol(p.name)
#        unless _protocol?
#          throw new Error("Could not find a protocol with the name \"#{p.name}\".")
#        unless _protocol.type is "weather"
#          throw new Error("\"#{p.name}\" is not a weather protocol.")
#        hasRain = true if _protocol.values.rain?
#        hasHumidity = true if _protocol.values.humidity?
#        hasTemperature = true if _protocol.values.temperature?
#        hasWindDirection = true if _protocol.values.windDirection?
#        hasAvgAirspeed = true if _protocol.values.avgAirspeed?
#        hasWindGust = true if _protocol.values.windGust?
#
#      hasNoAttributes = (
#        !hasRain and !hasHumidity and !hasTemperature and
#        !hasWindGust and !hasAvgAirspeed and !hasWindDirection
#      )
#      if hasNoAttributes
#        throw new Error(
#          "No values to show available. The config.protocols and the config.values doesn't match."
#        )
#
#      @attributes = {}
#
#      for s in config.values
#        switch s
#          when "rain"
#            if hasRain
#              if !@attributes.rain?
#                @attributes.rain = {
#                  description: "the measured fall of rain"
#                  type: "number"
#                  unit: 'mm'
#                  acronym: 'RAIN'
#                }
#            else
#              env.logger.warn(
#                "#{@id}: rain is defined but no protocol in config contains rain data!"
#              )
#          when "humidity"
#            if hasHumidity
#              if !@attributes.humidity?
#                @attributes.humidity = {
#                  description: "the measured humidity"
#                  type: "number"
#                  unit: '%'
#                  acronym: 'RH'
#                }
#            else
#              env.logger.warn(
#                "#{@id}: humidity is defined but no protocol in config contains humidity data!"
#              )
#          when "temperature"
#            if hasTemperature
#              if !@attributes.temperature?
#                @attributes.temperature = {
#                  description: "the measured temperature"
#                  type: "number"
#                  unit: '°C'
#                  acronym: 'T'
#                }
#            else
#              env.logger.warn(
#                "#{@id}: temperature is defined but no protocol in config contains " +
#                "temperature data!"
#              )
#          when "windDirection"
#            if hasWindDirection
#              if !@attributes.windDirection?
#                @attributes.windDirection = {
#                  description: "the measured wind direction"
#                  type: "string"
#                  acronym: 'WIND'
#                }
#            else
#              env.logger.warn(
#                "#{@id}: windDirection is defined but no protocol in config contains " +
#                "windDirection data!"
#              )
#          when "avgAirspeed"
#            if hasAvgAirspeed
#              if !@attributes.avgAirspeed?
#                @attributes.avgAirspeed = {
#                  description: "the measured average airspeed"
#                  type: "number"
#                  unit: 'm/s'
#                  acronym: 'SPEED'
#                }
#            else
#              env.logger.warn(
#                "#{@id}: avgAirspeed is defined but no protocol in config contains " +
#                "avgAirspeed data!"
#              )
#          when "windGust"
#            if hasWindGust
#              if !@attributes.windGust?
#                @attributes.windGust = {
#                  description: "the measured wind gust"
#                  type: "number"
#                  unit: 'm/s'
#                  acronym: 'GUST'
#                }
#            else
#              env.logger.warn(
#                "#{@id}: windGust is defined but no protocol in config contains windGust data!"
#              )
#          else
#            throw new Error(
#              "Values should be one of: " +
#              "rain, humidity, temperature, windDirection, avgAirspeed, windGust"
#            )
#
#      @board.on('rf', (event) =>
#        for p in @config.protocols
#          match = doesProtocolMatch(event, p)
#          if match
#            now = (new Date()).getTime()
#            timeDelta = (
#              if @_lastReceiveTime? then (now - @_lastReceiveTime)
#              else 9999999
#            )
#            if timeDelta < 2000
#              return
#            if event.values.windGust?
#              @_windGust = event.values.windGust
#              # discard value if it is the same and was received just under two second ago
#              @emit "windGust", @_windGust
#            if event.values.avgAirspeed?
#              @_avgAirspeed = event.values.avgAirspeed
#              # discard value if it is the same and was received just under two second ago
#              @emit "avgAirspeed", @_avgAirspeed
#            if event.values.windDirection?
#              @_windDirection = event.values.windDirection
#              # discard value if it is the same and was received just under two second ago
#              dir = @_directionToString(@_windDirection)
#              @emit "windDirection", "#{@_windDirection}°(#{dir})"
#            if event.values.temperature?
#              @_temperatue = event.values.temperature
#              # discard value if it is the same and was received just under two second ago
#              @emit "temperature", @_temperatue
#            if event.values.humidity?
#              @_humidity = event.values.humidity
#              # discard value if it is the same and was received just under two second ago
#              @emit "humidity", @_humidity
#            if event.values.rain?
#              @_rain = event.values.rain
#              # discard value if it is the same and was received just under two second ago
#              @emit "rain", @_rain
#            @_lastReceiveTime = now
#      )
#      super()
#
#    _directionToString: (direction)->
#      if direction<=360 and direction>=0
#        direction = Math.round(direction / 45)
#        labels = ["N","NE","E","SE","S","SW","W","NW","N"]
#      return labels[direction]
#
#    getWindDirection: -> Promise.resolve @_windDirection
#    getAvgAirspeed: -> Promise.resolve @_avgAirspeed
#    getWindGust: -> Promise.resolve @_windGust
#    getRain: -> Promise.resolve @_rain
#    getTemperature: -> Promise.resolve @_temperatue
#    getHumidity: -> Promise.resolve @_humidity
#
#
#  class RFLinkGenericSensor extends env.devices.Sensor
#
#    constructor: (@config, lastState, @board) ->
#      @id = config.id
#      @name = config.name
#
#      for p in config.protocols
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
