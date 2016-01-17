module.exports = {
  title: "RFLink device config schemes"
  RFLinkSwitch: {
    title: "RFLinkSwitch config options"
    type: "object"
    extensions: ["xConfirm", "xLink", "xOnLabel", "xOffLabel"]
    properties:
      protocols:
        description: "The switch protocols to use."
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          properties:
            name:
              type: "string"
            options:
              description: "The protocol options"
              type: "object"
            send:
              type: "boolean"
              description: "Toggle send with this protocol"
              default: true
            receive:
              type: "boolean"
              description: "Toggle receive with this protocol"
              default: true
      forceSend: 
        type: "boolean"
        description: "Resend signal even if switch has the requested state already"
        default: true
    required: ["protocols"]
  },
  RFLinkDimmer: {
    title: "RFLinkDimmer config options"
    type: "object"
    extensions: ["xConfirm"]
    properties:
      protocols:
        description: "The dimmer protocols to use."
        type: "array"
        default: []
        format: "table"
        items:
          type: "object"
          properties:
            name:
              type: "string"
            options:
              description: "The protocol options"
              type: "object"
            send:
              type: "boolean"
              description: "Toggle send with this protocol"
              default: true
            receive:
              type: "boolean"
              description: "Toggle receive with this protocol"
              default: true
      forceSend: 
        type: "boolean"
        description: "Resend signal even if switch has the requested state already"
        default: true
    required: ["protocols"]
  },
#  RFLinkContactSensor: {
#    title: "RFLinkContactSensor config options"
#    type: "object"
#    extensions: ["xConfirm", "xLink", "xClosedLabel", "xOpenedLabel"]
#    properties:
#      protocols:
#        description: "The protocols to use."
#        type: "array"
#        default: []
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              type: "string"
#            options:
#              description: "The protocol options"
#              type: "object"
#      autoReset:
#        description: """Reset the state after resetTime. Useful for contact sensors,
#                      that only emit open or close events"""
#        type: "boolean"
#        default: false
#      resetTime:
#        description: """Time after that the contact state is reseted."""
#        type: "integer"
#        default: 10000
#    required: ["protocols"]
#  }
#  RFLinkShutter: {
#    title: "RFLinkShutter config options"
#    type: "object"
#    extensions: ["xConfirm", "xLink", "xOnLabel", "xOffLabel"]
#    properties:
#      protocols:
#        description: "The protocols to use."
#        type: "array"
#        default: []
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              type: "string"
#            options:
#              description: "The protocol options"
#              type: "object"
#      forceSend:
#        type: "boolean"
#        description: "Resend signal even if switch has the requested state already"
#        default: true
#    required: ["protocols"]
#  }
#  RFLinkTemperature: {
#    title: "RFLinkTemperature config options"
#    type: "object"
#    extensions: ["xLink", "xAttributeOptions"]
#    properties:
#      protocols:
#        description: "The protocols to use."
#        type: "array"
#        default: []
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              type: "string"
#            options:
#              description: "The protocol options"
#              type: "object"
#      processingTemp:
#        description: "
#          expression that can preprocess the value, $value is a placeholder for the temperature
#          value itself."
#        type: "string"
#        default: "$value"
#      processingHum:
#        description: "
#          expression that can preprocess the value, $value is a placeholder for the humidity
#          value itself."
#        type: "string"
#        default: "$value"
#      isFahrenheit:
#        description: "
#          boolean that sets the right units if the temperature is to be reported in
#           Fahrenheit"
#        type: "boolean"
#        default: false
#    required: ["protocols"]
#  }
#  RFLinkWeatherStation: {
#    title: "RFLinkWeatherStation config options"
#    type: "object"
#    extensions: ["xLink", "xAttributeOptions"]
#    properties:
#      values:
#        type: "array"
#        default: ["temperature", "humidity"]
#        format: "table"
#        items:
#          type: "string"
#      protocols:
#        description: "The protocols to use."
#        type: "array"
#        default: []
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              type: "string"
#            options:
#              description: "The protocol options"
#              type: "object"
#    required: ["protocols"]
#  }
#  RFLinkGenericSensor: {
#    title: "RFLinkGenericSensor config options"
#    type: "object"
#    extensions: ["xLink", "xAttributeOptions"]
#    properties:
#      protocols:
#        description: "The protocols to use."
#        type: "array"
#        default: []
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              type: "string"
#            options:
#              description: "The protocol options"
#              type: "object"
#      attributes:
#        description: "The attributes (sensor values) of the sensor"
#        type: "array"
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              description: "Name for the attribute."
#              type: "string"
#            type:
#              description: "The type of this attribute in the rf message."
#              type: "integer"
#            decimals:
#              description: "Decimals of the value in the rf message"
#              type: "number"
#              default: 0
#            baseValue:
#              description: "Offset that will be added to the value in the rf message"
#              type: "number"
#              default: 0
#            unit:
#              description: "The unit of the attribute"
#              type: "string"
#              default: ""
#              required: false
#            label:
#              description: "A custom label to use in the frontend."
#              type: "string"
#              default: ""
#              required: false
#            discrete:
#              description: "
#                Should be set to true if the value does not change continuously over time.
#              "
#              type: "boolean"
#              required: false
#            acronym:
#              description: "Acronym to show as value label in the frontend"
#              type: "string"
#              required: false
#  }
#  RFLinkPir: {
#    title: "RFLinkPir config options"
#    type: "object"
#    extensions: ["xLink", "xPresentLabel", "xAbsentLabel"]
#    properties:
#      protocols:
#        description: "The protocols to use."
#        type: "array"
#        default: []
#        format: "table"
#        items:
#          type: "object"
#          properties:
#            name:
#              type: "string"
#            options:
#              description: "The protocol options"
#              type: "object"
#      autoReset:
#        description: """Reset the state after resetTime. Useful for pir sensors,
#                      that emit present and absent events"""
#        type: "boolean"
#        default: true
#      resetTime:
#        description: "Time after that the presence value is reset to absent."
#        type: "integer"
#        default: 10000
#    required: ["protocols"]
#  }
}
