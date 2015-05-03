# prophunt
This prophunt gamemode was not created by me. All credit goes to Wolvindra-Vinzuerio and Kowalski. This propunt gamemode is just an edited version.

Below is the list of things To-Do the following may have or have not been fixed.

*Fixes*
-Wait for round to start till players spawns in on team props or hunters
-Score not being kept/transferred between teams
-Hunters score going into negatives
-Score not accurate
-prop_door_rotating has Door model (models/props_c17/door01_left.mdl) with no door_options! Verify that SKIN is valid, and has a corresponding options block in the model QC file
-round count not showing when dead/spectating
-When players enter server they are assigned to TEAM_UNASSIGNED instead of TEAM_SPECTATOR
-On some maps as a hunter while blinded, screen will spaaz out (http://reverselogicgaming.proboards.com/thread/72/008-hunter-blindlock-void-leak)
-mod_studio: MOVETYPE_FOLLOW with no model.
-When player tries to vote for map change the player sends to chat "rtv"
-Hunters win when last hunter on team kills self
-Very rearly a hunter will spawn not blinded and is able to move around and kill props
-player dies when switching to spectator
-does not swap score and when prop and hunter dies -1


*Enhancements*
-Better ULX support (Maybe add ranks to scoreboard)
-Add mute function to allow players to mute other players.
-Prop rotation by click of mouse and to lock prop orientation
-Allow to give props a weapon at a certain time limit or give a weapon to last prop left to kill hunters
-Allow to config jump hight for props
-Add unstuck function
-Add when 1 minute left in game props will taunt every few seconds