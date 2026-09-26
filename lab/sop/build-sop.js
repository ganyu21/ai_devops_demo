const fs = require("fs");
const path = require("path");
const HERE = __dirname;
const body = fs.readFileSync(path.join(HERE, "sop-body.md"), "utf8");
const params = [
  { key: "delivery_lead", type: "waker", label: "交付负责人", description: "群 Leader，路由工作与守护两道人工门禁，不写业务代码", required: true },
  { key: "product_manager", type: "waker", label: "需求分析 PM", description: "读 GitHub issue、只读勘察、产出六段式拆解与需求基线", required: true },
  { key: "engineering_executor", type: "waker", label: "工程执行 Dev", description: "隔离分支实现、热修、冲突仲裁、PR 自查、issue 回写与记忆沉淀", required: true },
  { key: "qa_reviewer", type: "waker", label: "独立验收 QA", description: "从基线与设计推导测试并给带证据结论，不得改实现代码", required: true },
  { key: "ci_gate_keeper", type: "waker", label: "CI 门禁与合并执行 DevOps", description: "跑 jenkins-lab.sh 门禁、核对 commit status 回写、逆向分诊、人工批准后执行合并，不得改业务代码", required: true }
];
const version = process.argv[2] || "1.0.0";
const doc = {
  skillId: "github-lab-group-delivery",
  version: version,
  displayName: "GitHub 靶仓群协作交付 SOP",
  template: {
    format: "qoder-sop-template/v1",
    description: "GitHub issue 在 ai_devops_demo 靶仓的群协作交付：需求拆解 → G1 人工门禁 → 实现 → 缺陷热修 → 冲突仲裁 → Jenkins 门禁自愈 → commit status 回写 → 独立验收 → G2 人工门禁 → 交付收尾与记忆治理。门禁结论以 jenkins-lab.sh 结构化输出为唯一事实源，合并资格以 github-lab.sh pr-status 为唯一事实源，交付状态以已提交的 state.json 为唯一事实源。",
    body: body,
    parameters: params
  }
};
const out = path.join(HERE, "github-lab-group-delivery.json");
fs.writeFileSync(out, JSON.stringify(doc, null, 1));
console.log("written " + out + "  version=" + version + "  body chars=" + body.length + "  params=" + params.length);

const ph = [...body.matchAll(/\$\{\{(\w+)\}\}/g)].map(m => m[1]);
const uniq = [...new Set(ph)];
console.log("正文占位符: " + uniq.join(", "));
console.log("参数键:     " + params.map(p => p.key).join(", "));
const missing = uniq.filter(x => !params.some(p => p.key === x));
const unused = params.map(p => p.key).filter(k => !uniq.includes(k));
console.log("缺失参数: " + (missing.length ? missing.join(",") : "无") + " | 未用参数: " + (unused.length ? unused.join(",") : "无"));

// 退役口径守卫：GitHub 版 SOP 正文里不该再出现上一代内部协作平台的口径。
// 用模式而不是字面量——这份脚本在公开仓里，把内部平台名与内部域名字面写进列表，
// 守卫自己就成了泄漏源（本轮就是这么发现的）。
const bannedPatterns = [
  { name: "内部 CLI 调用", re: /\ba1\s+(repo|project|ci|quality|workitem)\b/ },
  { name: "非 github.com 的 git 主机", re: /(?:git@|https?:\/\/)(?!github\.com)[\w.-]+\.[a-z]{2,}/ },
  { name: "MR 术语（应为 PR）", re: /\bMR\b/ },
  { name: "内部评审规则码", re: /approver_number/ },
  { name: "旧靶仓路径", re: /(?<![.\w])devflow\// },   // 前面不能是 . 或单词字符，否则误伤本仓的 .devflow/ 产物目录
  { name: "8 位以上裸单号", re: /(?<![\w./-])\d{8,}(?![\w./-])/ },
  { name: "机器用户名硬编码", re: /\/Users\/[\w-]+\// },
];
const hits = [];
for (const p of bannedPatterns) {
  const m = body.match(p.re);
  if (m) hits.push(p.name + " → " + JSON.stringify(m[0]));
}
console.log("退役口径残留: " + (hits.length ? hits.join(" | ") : "无"));
if (hits.length) process.exitCode = 1;
