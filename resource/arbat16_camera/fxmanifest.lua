fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'Arbat16 Camera'
description 'Standalone Lua cinematic camera and keyframe editor for RedM'
version '1.7.1'
license 'ARBAT16 Source-Available License 1.0 (No Resale)'

shared_scripts { 'config.lua', 'shared/core.lua', 'shared/director.lua', 'shared/flight.lua' }
client_scripts { 'client/natives.lua', 'client/director.lua', 'client/main.lua' }
server_script 'server/main.lua'
ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/director.js', 'web/model.js', 'web/app.js', 'web/fonts/inter-latin.woff2', 'web/fonts/OFL-Inter.txt' }
