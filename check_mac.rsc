### Script settings
##
#
# Expected MAC address
:local expectedMac "FF:FF:FF:FF:FF:FF";# <-- PASTE YOUR EXPECTED MAC ADDRESS HERE
# Interface name (ifName)
:local ifName "ether2";# <-- PASTE YOUR INTERFACE NAME HERE
# Name of task in scheduler.
:local scheduleName "checkMacSchedule";# <-- PASTE YOUR SCHEDULE NAME HERE
# Telegram settings
:global telegramNotificationsEnabled false;# <-- PASTE 'true' TO ENABLE TELEGRAM NOTIFICATIONS
# Bot token (e.g. 1234567890:ABCdefGHIjklMNOpqrSTUvwxYZ1234567890) [use https://t.me/botfather]
:global telegramBotToken "TELEGRAM_BOT_TOKEN";# <-- PASTE YOUR TELEGRAM BOT TOKEN HERE
# Chat id (e.g. -1008978939616) [use https://api.telegram.org/bot<your_bot_token>/getUpdates]
:global telegramChatId "TELEGRAM_CHAT_ID";# <-- PASTE YOUR TELEGRAM CHAT ID HERE
# Telegram header
:local hostname [/system identity get name];
:local model [/system routerboard get board-name];
:global telegramMessageHeader ("⚠️ WARNING! ⚠️ %0A%0AHost: ".$hostname." [MikroTik ".$model."]%0A%0A");
# File name to contain last http response
:global telegramFileName "telegramLastResponse.txt";
# Schedule interval (Used for logging only)
:local scheduleInterval "1 min";
# Script message prefix
:local msgPrefix "[MAC_CHECK]";
# Used to check for MAC presence on the port during the next iteration
:local noMacPresentText "NO_MAC_PRESENT";
#
##
### END script settings

# Function
:global sentOnTelegram do={

    :local messageText ($message);

    :global telegramNotificationsEnabled;

    :if ($telegramNotificationsEnabled = true) do={
        :global telegramBotToken;
        :global telegramChatId;
        :global telegramMessageHeader;
        :global telegramFileName;

        :local telegramMessage ($telegramMessageHeader."".$messageText);
        :local url ("https://api.telegram.org/bot".$telegramBotToken."/sendMessage\?chat_id=".$telegramChatId."&text=".$telegramMessage);
        /tool fetch url=$url dst-path=$telegramFileName;
        /log info ($msgPrefix." Notification sent on Telegram");
    }
}

# Function 
:local endScript do={

    :local message ($withMessage);
    /log info $message; # put message into log

    :local notification ($notifi);

    :if ([:len $notification] = 0) do={
        :set notification true; # notification enabled by default
    }
    
    :if ($notification = true) do={
        :global sentOnTelegram
        $sentOnTelegram message=$message
        # add more notification types here
    }

    :error $message;  # end of script
}

# Function
:local disableInterface do={
    /interface ethernet set $ifName disabled=yes;
    /log error ($msgPrefix." Interface ".$ifName." has been disabled! Check it manualy.");
}

####################
# Read current MAC addresses learned from ifName
:local currentMacAddresses [/interface bridge host find on-interface=$ifName local=no];

####################
# If link is down
# End Script
:if (![/interface ethernet get $ifName running]) do={
    $endScript withMessage=($msgPrefix." Interface ".$ifName." is DOWN. Aborting.") notifi=false;
}

:local macAddressCount [:tonum [:len $currentMacAddresses]];

####################
# If the MAC address matches the expected one:
#   stop the script
# If the MAC address does NOT match the expected one:
#   disable the interface
:if ($macAddressCount = 1) do={
    :local mac [/interface bridge host get [:pick $currentMacAddresses 0] mac-address];

    :if ($mac = $expectedMac) do={
        $endScript withMessage=($msgPrefix." Interface ".$ifName." done!") notifi=false;  # Successful check
    } else={
        /log error ($msgPrefix."Interface ".$ifName.": MAC address does not match the expected value. Disabling interface...")
        $disableInterface ifName=$ifName msgPrefix=$msgPrefix;
        $endScript withMessage=($msgPrefix." Interface ".$ifName.": disabled due to security policy violation. MAC address - ".$mac." (expected - ".$expectedMac.").");
    }
}

####################
# If more than one MAC address is present
# disable interface and end script
:if ($macAddressCount > 1) do={
    /log error ($msgPrefix." Interface ".$ifName.": more than one MAC address. Disabling interface...");
    $disableInterface ifName=$ifName msgPrefix=$msgPrefix;
    $endScript withMessage=($msgPrefix." Interface ".$ifName.": disabled due to security policy violation. MAC count: ".$macAddressCount);
}

# Redundant check for negative value
:if ($macAddressCount < 0) do={
    $endScript withMessage=($msgPrefix." Unexpected value macAddressCount variable: ".$macAddressCount);
}

####################
# If the link is UP but no MAC addresses are detected:
# If the flag already exists:
#   disable the interface.
# If no flag exists:
#   create one to check again on the next iteration.
:local currentFlag [/system scheduler get [find name=$scheduleName] comment];

:if ($currentFlag = $noMacPresentText) do={
    /system scheduler set [find name=$scheduleName] comment="";  # remove a flag
    /log error ($msgPrefix." Interface " . $ifName . ": no MAC address detected. Disabling interface...");
    $disableInterface ifName=$ifName msgPrefix=$msgPrefix;
    $endScript withMessage=($msgPrefix." Interface ".$ifName.": disabled due to security policy violation. No MAC address detected for more than ".$scheduleInterval);
}

# If the flag doesn’t match the $noMacPresentText, it means it doesn’t exist.
/log info ($msgPrefix." Interface ".$ifName." no MAC address detected. Adding a flag for verification in the next iteration.")
/system scheduler set [find name=$scheduleName] comment=$noMacPresentText;  # add a flag
# Acknowledge the created flag
:local createdFlag [/system scheduler get [find name=$scheduleName] comment];
/log info ($msgPrefix." Created flag: ".$createdFlag);
