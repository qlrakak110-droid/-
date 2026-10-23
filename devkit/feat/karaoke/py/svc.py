exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/py/kdump.py').read().split("mode=sys.argv[1]")[0])
for i in G.inst[1:]:
    if i['parent']==1 or i['cls'] in ('VoiceChatService','SoundService','TextChatService','Chat','AudioDeviceInput','AudioEmitter','AudioListener','AudioEcho','AudioReverb','SoundGroup','ReverbSoundEffect','EchoSoundEffect','ChorusSoundEffect','PitchShiftSoundEffect','EqualizerSoundEffect'):
        if i['cls'] in ('VoiceChatService','SoundService','TextChatService','Chat') or i['parent']!=1:
            print(path(i['id']), i['cls'])
            for k in i['props']:
                print('   ', k, G.prop(i,k))
            for k,v in i['attrs'].items(): print('   @',k,G.val(v))
