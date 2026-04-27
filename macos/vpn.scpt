set pass to do shell script "security find-generic-password -a $(whoami) -s mac_login_pass -w"

activate application "Cisco AnyConnect Secure Mobility Client"
tell application "System Events"
	delay 1
	tell process "Cisco AnyConnect Secure Mobility Client"
		tell window 2
			click button "Connect"
		end tell
	end tell
end tell
delay 1
tell application "System Events"
	tell process "Cisco AnyConnect Secure Mobility Client"
		tell window 2
			set value of text field 2 to pass
			click button "OK"
		end tell
	end tell
end tell
