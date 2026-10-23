#!/bin/sh
# copy the add-on sources into the test dir (luau CLI require does not follow symlinks)
T=/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/test
rm -rf $T/sh $T/srv $T/cli; mkdir -p $T/sh $T/srv $T/cli
cp /home/user/-/src/ReplicatedStorage/GwangalliKaraokeShared/*.luau $T/sh/ 2>/dev/null
cp /home/user/-/src/ServerScriptService/GwangalliKaraokePlus/*.luau $T/srv/ 2>/dev/null
cp /home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus/*.luau $T/cli/ 2>/dev/null
true
