# esp_rgbww_fhemmodule
an experimental module for FHEM to drive the esp_rgbww_controllers

### Installation
use update all <url to blame file controls_ledcontroller.txt>

### Contributions

Please refer to [CONTRIBUTING.md](https://github.com/patrickjahns/esp_rgbww_fhemmodule/blob/master/CONTRIBUTING.md) for participating in the project.

### Branches
* Master: stable and functional (releases)
* Develop: working branch with latest features


### ToDo:
* [x] setting to "on" currently sets the *value* (=brightness) to 100 and keeps the current hue and and saturation. I suggest adding an *attr* to define hsv for "on"
* [x] provide a default transition setting (attr)
* [ ] enable updating of attributes (I can't find how that's supposed to be done)
* [ ] I have enabled defaultColor and colorTemp attributes but not yet put them into use
* [ ] check if setExtensions are applicable
* [ ] check if "color" is applicable
* [ ] add a "raw r10 g10 b10 ww10 cw10" setting
* [ ] implement get for r8g8b8, hsl, r10g10b10ww10cw10 - may be dependent on the MQTT interface as I would rather see this as a subscribe than as a REST query
* [ ] add bounds checking - the code currently doesn't do any checking on the parameters supplied but relies on the underlying code to deal with it. Mixig up text / numerical characters can break things badly
* [ ] make sure the set commands / readings / internals follow the general convention for capitalization / wording (I've just noticed that, instead of *val*, WifiLight uses *brightness* but doesn't offer it as a separate setting
* [ ] do we need to do anything for autoconfig? Could we automatically detect Controllers as they join the net? 

### Links

* [esp rgbww pcb](https://github.com/patrickjahns/esp_rgbww_controller)
* [esp rgbww firmware](https://github.com/patrickjahns/esp_rgbww_firmware)
* [Discussion at FHEM (german)](https://forum.fhem.de/index.php?topic=48918)

