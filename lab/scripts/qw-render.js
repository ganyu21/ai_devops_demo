/* qw-group.sh 的 JSON 解析助手。
 *
 * 为什么单独一个文件：qoderwake CLI 的 --json 输出前面会带一行 "[qoderwake] " 前缀，
 * 而且 messages list 返回的是**顶层数组**、group show 返回的是 {group,conversation,participants}，
 * 两者结构完全不同；这些解析逻辑塞进 shell 的内联 node -e 里既重复又难读，
 * 而且内联脚本里的 // 注释还会撞上 "UNC path" 命令守卫。
 *
 * 用法： <cli 的 --json 输出> | node qw-render.js <mode> [参与者映射文件]
 *   mode=maxseq    取消息里最大的 seq（messages list 是升序，所以不能靠 --limit 1 拿最新）
 *   mode=render    把消息渲染成一行一条
 *   mode=members   输出 participantId<TAB>显示名 的映射
 *   mode=sop       渲染群上已绑的 SOP：版本、releaseId、五个角色参数各自解析到了谁
 *
 *   mode=approvals 渲染 toolGuard 待审批队列。**输入不是 CLI 而是 qw-api.sh**：
 *                  qw-api.sh GET /api/permissions/approvals/pending | node qw-render.js approvals
 *   mode=pendcount 只输出待审批条数（给 watch 轮询用，队列空时输出 0 而不是空串）
 */
const fs = require("fs");

const mode = process.argv[2] || "render";
const mapFile = process.argv[3] || "";

let raw = "";
process.stdin.on("data", (d) => (raw += d));
process.stdin.on("end", () => {
  const i = Math.min(...[raw.indexOf("{"), raw.indexOf("[")].filter((x) => x >= 0));
  // approvals 模式下解析失败必须吵出来：静默无输出会被误读成「审批队列为空」，
  // 而真实原因可能是鉴权坏了（401）——那是整条流水线的问题，不是队列空。
  // pendcount 模式同理，但它是给 watch 轮询用的，不能打印整段排查文案（会刷屏），
  // 所以只输出一个非数字标记 ERR，由调用方决定怎么吵。
  // 其他模式保持静默：它们被 watch 轮询调用，刷屏比漏报更糟。
  const loud = (msg) => {
    if (mode === "pendcount") {
      process.stdout.write("ERR");
      return;
    }
    if (mode === "approvals") {
      process.stdout.write(`${msg}\n`);
      const t = raw.replace(/\s+/g, " ").trim();
      if (t) process.stdout.write(`   原始输出前 200 字: ${t.slice(0, 200)}\n`);
      process.stdout.write("   排查: 直接跑 lab/scripts/qw-api.sh GET /api/permissions/approvals/pending 看它返回什么\n");
    }
  };
  if (i < 0) { loud("(拿不到审批队列：输出里没有 JSON)"); return; }
  let d;
  try {
    d = JSON.parse(raw.slice(i));
  } catch (e) {
    loud(`(拿不到审批队列：JSON 解析失败 ${e.message})`);
    return;
  }

  if (mode === "members") {
    const ps = (d.data || d).participants || [];
    for (const p of ps) {
      const snap = p.wakerSnapshot || {};
      const isHuman = (snap.kind || "") === "core/human";
      const name = isHuman ? "我（Requirement Owner）" : snap.name || snap.id || p.id;
      process.stdout.write(`${p.id}\t${name}\n`);
    }
    return;
  }

  if (mode === "sop") {
    const skills = d.systemSkills || (d.data && d.data.systemSkills) || [];
    if (!Array.isArray(skills) || !skills.length) {
      process.stdout.write("  （未绑定任何 SOP）\n");
      return;
    }
    // 期望版本从环境来，不从 argv 来：这样 shell 侧不用为了传一个字符串再去拼参数。
    const want = process.env.LAB_SOP_VERSION || "";
    for (const k of skills) {
      const bad = want && k.version !== want;
      process.stdout.write(`  ${k.skillId}@${k.version}  release=${k.releaseId}  priority=${k.priority}`
        + (bad ? `   ⚠ 仓内期望 @${want}` : "") + "\n");
      // 未解析的 ${{...}} 字面量必须显式报出来。参数没解析时五个角色会照着 SOP 标题即兴发挥，
      // 而且看起来一切正常——那比报错危险得多，所以这里不给它安静的机会。
      const p = k.parameterValues || {};
      const keys = Object.keys(p);
      if (!keys.length) process.stdout.write("    ⚠ 一个角色参数都没解析出来\n");
      for (const key of keys) {
        const v = p[key] || {};
        const shown = v.display_name || v.id || JSON.stringify(v);
        const unresolved = /\$\{\{/.test(String(shown));
        process.stdout.write(`    ${key.padEnd(22)} → ${shown}${unresolved ? "   ⚠ 占位符未解析" : ""}\n`);
      }
    }
    return;
  }

  if (mode === "pendcount") {
    // 拿不到队列时必须输出一个**非数字**标记，不能输出空串或 0。
    // 调用方（qw-group.sh watch）会把空串经 ${N:-0} 兜成 0，然后打印「审批队列为空」——
    // 而真实原因可能是鉴权坏了。toolGuard 的审批窗口只有 5 分钟且只存内存、超时无法补批，
    // 把「守卫自身故障」显示成「没人需要批准」，后果是那一步静默超时。
    const items = (d.data && d.data.items) || d.items || [];
    process.stdout.write(Array.isArray(items) ? String(items.length) : "ERR");
    return;
  }

  if (mode === "approvals") {
    const items = (d.data && d.data.items) || d.items || [];
    if (!Array.isArray(items) || !items.length) {
      process.stdout.write("审批队列为空。\n");
      return;
    }
    const flat = (v) => String(v == null ? "" : v).replace(/\s+/g, " ");
    const now = Date.now();
    const KNOWN = ["requestId", "agentId", "toolName", "findings", "findingsSummary",
                   "expiresAt", "createdAt", "toolInputPreview", "toolInput"];
    for (const x of items) {
      process.stdout.write(`⚠ ${x.requestId}\n`);
      process.stdout.write(`   agent = ${x.agentId}   tool = ${x.toolName || "?"}\n`);

      // 命中的规则要逐条列：把数组整体 JSON.stringify 再截断，双命中时第二条的 ruleId
      // 与 guardianName 会被完全丢掉，而丢掉的往往正是 fileGuard 那条最该看见的。
      const fs2 = x.findingsSummary || x.findings || [];
      if (Array.isArray(fs2) && fs2.length) {
        process.stdout.write(`   命中规则（${fs2.length} 条）:\n`);
        fs2.forEach((f, i) => {
          process.stdout.write(`     [${i}] ${f.ruleId || f.rule || "?"}`
            + `  severity=${f.severity || "?"}  guardian=${f.guardianName || f.guardian || "?"}`
            + `  category=${f.category || "?"}\n`);
          if (f.description) process.stdout.write(`         ${flat(f.description).slice(0, 120)}\n`);
        });
      } else {
        process.stdout.write("   命中规则 = （响应里没有 findings / findingsSummary，看下面兜底字段）\n");
      }

      // expiresAt 是 epoch 毫秒。审批只存内存、5 分钟过期且超时无法补批，
      // 所以「还剩几秒」比原始毫秒有用得多。
      const exp = Number(x.expiresAt);
      if (Number.isFinite(exp) && exp > 1e12) {
        const left = Math.round((exp - now) / 1000);
        process.stdout.write(`   剩余 = ${left > 0 ? left + "s" : "已超时（无法补批）"}   expiresAt=${x.expiresAt}\n`);
      } else if (x.expiresAt) {
        process.stdout.write(`   到期 = ${flat(x.expiresAt)}\n`);
      }

      const cmd = flat(x.toolInputPreview || x.toolInput || "");
      if (cmd) process.stdout.write(`   命令 = ${cmd.slice(0, 300)}${cmd.length > 300 ? "…" : ""}\n`);

      // 兜底：schema 变了也至少能看到其余字段的原始值
      const rest = Object.keys(x).filter((k) => !KNOWN.includes(k));
      if (rest.length) {
        process.stdout.write("   其他 = " + rest.map((k) => {
          let v = x[k];
          if (v && typeof v === "object") v = JSON.stringify(v);
          return `${k}:${flat(v).slice(0, 80)}`;
        }).join("  ") + "\n");
      }

      process.stdout.write(`   批准: qw-api.sh POST /api/agents/${x.agentId}/permissions/approvals/${x.requestId}/resolve  载荷 {"decision":"allow","reason":"..."}\n\n`);
    }
    return;
  }

  const msgs = Array.isArray(d) ? d : (d.data && (d.data.messages || d.data)) || d.messages || [];
  const arr = Array.isArray(msgs) ? msgs : [];

  if (mode === "maxseq") {
    process.stdout.write(String(arr.reduce((m, x) => Math.max(m, Number(x.seq) || 0), 0)));
    return;
  }

  let names = {};
  if (mapFile && fs.existsSync(mapFile)) {
    for (const ln of fs.readFileSync(mapFile, "utf8").split("\n")) {
      const t = ln.split("\t");
      if (t.length >= 2) names[t[0]] = t[1];
    }
  }

  for (const x of arr) {
    const who = names[x.senderParticipantId] || x.senderParticipantId || "?";
    const body = x.body || {};
    let text = String(body.text || "").replace(/\s+/g, " ");
    // 用 --file 发的消息，正文进的是 attachments（kind=input_file），body.text 是空的。
    // 不显式标出来的话，这一行会退化成 body.type 也就是一个 "text"，
    // 读的人以为消息是空的——而它恰恰是最长最重要的那条。
    const atts = Array.isArray(x.attachments) ? x.attachments : [];
    if (atts.length) {
      const desc = atts.map((a) => {
        const f = (a && a.attachment) || {};
        return `${f.filename || "?"}(${f.sizeBytes != null ? f.sizeBytes + "B" : "?"})`;
      }).join(", ");
      text = (text ? text + " " : "") + `[附件 ${atts.length} 个: ${desc} —— 正文不在 body.text 里，用 qw-api.sh 取附件]`;
    }
    if (!text) text = String(body.type || "");
    const att = x.audience && x.audience.length ? ` →@${x.audience.map((a) => names[a.participantId] || a.participantId).join(",")}` : "";
    const t = String(x.createdAt || "").slice(11, 19);
    process.stdout.write(`[seq ${x.seq} ${t}] ${who}${att} (${x.intent || "?"}/${x.deliveryPolicy || "?"}): ${text}\n`);
  }
});
