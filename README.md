# RGBWW_fhem_module
an experimental module to drive the RGBWW controllers developed by Patrick Jahns

This modul is very experimental. I mean *very*.


ToDo:

* Reading Values are set in different places, I'm sure they can be moved to a single, more convenient place (like the actual set HSV sub).
* setting to "on" should fetch the last HSV values and set them rather than setting 60,0,100 (or should id? maybe a default?)
* provide a default transition setting (attr)

