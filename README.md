pimatic-rflink
=======================

Plugin for using various 433 Mhz devices and sensors with a connected
[RFLink Gateway](http://www.nemcon.nl/blog2/).

This device supports [many 433 MHz devices](http://www.nemcon.nl/blog2/2015/07/devlist)
but this plugin is currently limited to only supports the following devices:
- Switches
- Dimmers
- PIR sensors
- Contact sensors 
- Generic data sensors for temperature, wind, barometric pressure and many more

Support for other devices may be added in the future.


Plugin configuration
------

You can load the plugin by editing your `config.json` to include:

```json
{
  "plugin": "rflink",
  "driverOptions": {
    "serialDevice": "/dev/tty.usbmodem641"
  }
}
```

in the `plugins` section. For all configuration options see [rflink-config-schema](rflink-config-schema.coffee)


Devices
------

Devices must be added manually to the device section of your pimatic config. 

A list with all supported protocol names can be found [here](https://github.com/ThibG/RFLink/blob/master/Doc/RFLink%20Protocol%20Reference.txt).
For all configuration options see [device-config-schema](device-config-schema.coffee).
To determine the device name, id and switch configuration, make sure the debug option on the driver is on (this is the 
default) and press the remote control button that controls the device. The debug logging will then show a line conting 
for example:
```
20;01;NewKaku;ID=005ef68a;SWITCH=1;CMD=ON;
```
The contents of this line should then be interpreted in protocol configuration options as follows 
```
20;01;<name>;ID=<id>;SWITCH=<switch>;CMD=ON;
```
See below for complete device configuration examples 
 
### Switch example:

```json
{
  "id": "rfswitch",
  "name": "RFSwitch",
  "class": "RFLinkSwitch",
  "protocols": [{
    "name": "NewKaku",
    "id": "005ef68a",
    "switch": "1"
  }]
}
```

A switch (and other devices) can be controlled or send to outlets with multiple protocols. Just
add more protocols to the `protocols` array. You can also set if a protocol
is used for sending or receiving. Default is `true` for both.

### Multi protocol switch example:

```json
{
  "id": "rfswitch",
  "name": "RFSwitch",
  "class": "RFLinkSwitch",
  "protocols": [
    {
      "name": "NewKaku",
      "id": "005ef68a",
      "switch": "1"
    },
    {
      "name": "Kaku",
      "id": "4b",
      "switch": "1",
      "send": false
    }
  ]
}
```

### Dimmer device example:
```json
{
  "id": "kitchenspots",
  "name": "Kitchen spots",
  "class": "RFLinkDimmer",
  "protocols": [{
    "name": "NewKaku",
    "id": "005ef68a",
    "switch": "1"
  }]
}
```

### ContactSensor example:
```json
{
  "id": "window",
  "name": "Window",
  "class": "RFLinkContactSensor",
  "autoReset": false,
  "invert": false,
  "protocols": [
    {
      "name": "NewKaku",
      "id": "00d199ee",
      "switch": "1"
    }
  ]
},
```

### PIR sensor example:
```json
{
  "id": "movement",
  "name": "Movement",
  "class": "RFLinkPir",
  "autoReset": false,
  "invert": false,
  "protocols": [
    {
      "name": "NewKaku",
      "id": "00d189ee",
      "switch": "1"
    }
  ]
},
```


### Generic data sensor example:
Values represent the (lowercase) attributes as sent by the RFLink device.
Currently, the following values are supported:
- temp
- hum
- baro
- hstatus
- bforecast
- uv
- lux
- bat
- rain
- rainrate
- raintot
- winsp
- awinsp
- wings
- windir
- winchil
- wintmp
- co2
- sound
- kwatt
- watt
- current
- current2
- current3
- dist
- meter
- volt
```json
{ 
  "id": "TemperatuurWoonkamer",
  "name": "Temperatuur Woonkamer", 
  "class": "RFLinkData", 
  "protocols": [
    {
      "name": "Xiron",
      "id": "C901" 
    }
  ],
  "values": [
    "temp",
    "hum"
  ]
},
```

