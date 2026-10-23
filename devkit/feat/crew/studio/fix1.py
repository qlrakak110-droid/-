p='crew.js'
s=open(p).read()
old='''  log('tp', await srv(`local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart") hrp.Anchored = false ch:PivotTo(CFrame.lookAt(Vector3.new(${inside[0]}, ${inside[1]}, ${inside[2]}), Vector3.new(${c[0]}, ${inside[1]}, ${c[2]}))) out = "tp " .. tostring(hrp.Position)`));'''
new='''  const tp = async (pos, look) => {
    const js = await p.evaluate((q) => { try { if (window.Character && Character.teleport) { Character.teleport(q); return 'js'; } } catch (e) { return 'jsERR ' + e; } return 'nojs'; }, pos);
    const r = await srv(`local ch = S.player.Character local hrp = ch and ch:FindFirstChild("HumanoidRootPart") hrp.Anchored = false ch:PivotTo(CFrame.lookAt(Vector3.new(${pos[0]}, ${pos[1]}, ${pos[2]}), Vector3.new(${look[0]}, ${pos[1]}, ${look[2]}))) hrp.AssemblyLinearVelocity = Vector3.zero out = "tp " .. tostring(hrp.Position)`);
    return js + ' ' + r;
  };
  log('tp', await tp(inside, c));
  await p.waitForTimeout(4000);
  log('where', await srv(`${SVC} out = HOOK:Invoke("session") .. " pos=" .. tostring(S.player.Character.HumanoidRootPart.Position)`));'''
assert old in s; s=s.replace(old,new)
a=s.index("  // bus logger")
b=s.index("\n", s.index("log('logger'"))
s=s[:a]+s[b+1:]
s=s.replace('''    const lg = await srv(`out = table.concat(_G.__crewLog, " | ")`);
    log('bus', lg.slice(-400));''','''    const lg = await srv(`${SVC} out = HOOK:Invoke("session")`);
    log('sess', lg);''')
s=s.replace('''    if (/ served /.test(lg) && i > 2) { await p.waitForTimeout(3000); break; }''','''    if (shotTray && /waiter:(idle|-)/.test(s) && i > 4) { await p.waitForTimeout(3000); break; }''')
open(p,'w').write(s)
