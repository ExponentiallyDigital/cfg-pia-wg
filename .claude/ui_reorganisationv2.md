### Fixes and changes to be made for new UI

#### Manage router PIA WireGuard configuration

- disallow concurrency: only one interface should ever be active at a time, ENABLE button must disable any currently enabled interface
- disabling/deleting an interface must also disable any active watchdog on that interface
- deleting an interface must display the description of that interface in the confirmation popup
- when a slot is active (enabled), grey out the ENABLE button
- when creating an interface set the kill switch to disabled (wgcN_enforce=0)
- when editing an interface alter the UI text display: currently shows "Enable (enable) 0" , change to "Enabled YES" or "Enabled NO"
- when displaying the "WIREGUARD SLOTS" modal, the HOME button at thje bottom of that modal should take you to the home menu instead of the router login window
- when ENABLE is selected and ping tests are conducted, log this to the router log (currently only logging to the app log)
- CREATE, ENABLE, DISABLE and DELETE must log these activities to the router log

#### Watchdog WireGuard management

- ENABLE and DELETE buttons must be greyed out if an empty slot is selected
- after creating a watchdog on an empty slot, open a popup to remind the user to ENABLE the watchdog (this functionality will then match "Manage router PIA WireGuard configuration")
- modify `deployWatchdogScripts` to include the region (description) eg from "Deployed watchdog script for wgc5" to "Deployed watchdog script for wgc5, aus_melbourne"
- disallow concurrency: only one watchdog should ever be active at a time, ENABLE button must disable any currently enabled watchdog
- when the DELETE button is pressed, add a confirmation popup with this text "This will also delete and disable the underlying region."
- when EDIT button is pressed for a disabled slot, put the PIA username and password in the mopdal that open up

#### UI

- remove the 10 minute timer and all it's associated logic and code
- set defaults for router ip = "192.168.0.254" and router username = "admin"
- warn the user when pressing the back key IFF it will exit the application
- on the main menu screen, show text below "\* requires SSH connectivity to an Asus router". This additional text will use the house green style with vertical padding from the existiong text, it will say "Select from the above and/or use the top left <\insert reduced image of hambuger menu> menu."
- in the hamburger menu, there is text marked "HOME" in green, make this grey and make it navigate to the main menu screen when pressed
- in the hamburger menu, make the currently active menu item appear in house GREEN. eg if the user is currently in the "Watchdog WireGuard management" menu item it's modal, display that in house GREE on the manhurger meny. The "Close app" colour does not change and remains red.
- if there is an existing SSH connection to the router, display the "connect to router" screen in the background but skip to the modal window which is displayed in the "Manage router PIA WireGuard Configuration" and "Watchdog WireGuard management" menu options.
