p='crew.js'
s=open(p).read()
s=s.replace('''hrp.Anchored = false ch:PivotTo(CFrame.lookAt(Vector3.new(${pos[0]}, ${pos[1]}, ${pos[2]}), Vector3.new(${look[0]}, ${pos[1]}, ${look[2]}))) hrp.AssemblyLinearVelocity = Vector3.zero out = "tp " .. tostring(hrp.Position)`);''','''ch:PivotTo(CFrame.lookAt(Vector3.new(${pos[0]}, ${pos[1]}, ${pos[2]}), Vector3.new(${look[0]}, ${pos[1]}, ${look[2]}))) hrp.Anchored = true hrp.AssemblyLinearVelocity = Vector3.zero out = "tp " .. tostring(hrp.Position)`);''')
# status: add the server-side player position + session
s=s.replace('''      out = "crews=" .. #st.crews''','''      local hp = S.player.Character and S.player.Character:FindFirstChild("HumanoidRootPart")
      out = "pos=" .. (hp and V(hp.Position) or "-") .. " sess=" .. HOOK:Invoke("session") .. " crews=" .. #st.crews''')
# talk test: run inside a spawned client thread, read back from an attribute
a=s.index("  log('talk', await cli(")
b=s.index("out = table.concat(bits, \" | \")`));", a)+len("out = table.concat(bits, \" | \")`));")
talk=s[a:b]
talk=talk.replace("log('talk', await cli(`local RS","await cli(`task.spawn(function() local ok, err = pcall(function() local RS")
talk=talk.replace('''    out = table.concat(bits, " | ")`));''','''    S.game:GetService("Players").LocalPlayer:SetAttribute("CrewTalkTest", table.concat(bits, " | "))
    end) if not ok then S.game:GetService("Players").LocalPlayer:SetAttribute("CrewTalkTest", "ERR " .. tostring(err)) end end) out = "spawned"`);
  for (let i = 0; i < 20; i++) { await p.waitForTimeout(1500); const t = await cli(`out = tostring(S.game:GetService("Players").LocalPlayer:GetAttribute("CrewTalkTest"))`); if (t !== 'nil') { log('talk', t); break; } }''')
s=s[:a]+talk+s[b:]
# fewer screenshots: drop 05_dialog, 06_receipt, 07_clear
s=s.replace("  await shot('05_dialog', null, null, null, false);\n","")
s=s.replace("  await shot('06_receipt', null, null, null, false);\n","")
s=s.replace("  await shot('07_clear', eye, at, 70);\n","")
open(p,'w').write(s)
