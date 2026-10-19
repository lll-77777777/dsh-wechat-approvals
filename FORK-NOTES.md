# dsh-wechat-approvals — 微信审批双端 + 完成通知补丁

这是 `dsh-wechat-plugin` 的修改版（fork），不是独立插件。
它让 **DSH 桌面会话**也走微信审批/通知，而不是只有绑定微信的会话才走。

## 装在哪

- 源（这份）：`E:\大肥鱼人设\dsh-wechat-approvals`
- 生效位置：`C:\Users\ireina\.dsh\profiles\desktop\node_modules\dsh-wechat-plugin`
- 官方原版备份：同目录下 `dsh-wechat-plugin.stock-backup-0.43.1`

## 改了什么

| 文件 | 改动 |
| --- | --- |
| `lib/host.js` | 未绑定会话的审批转发、任务完成通知、双端审批（10 秒窗口）、通知去噪、工作区防改名 |
| `package.json` | 版本改成 `0.43.1-desknotify.1` |
| `cordis.patch.yml` | 默认配置加上这几个开关 |

另有 DSH 自带包的补丁（不是微信插件）：
`profiles\desktop\node_modules\dsh-ops\lib\workspace-preparation.js` 的 spawn 参数加 `-ExecutionPolicy Bypass`，修 PowerShell 执行策略导致的 shell 工具全挂。

## 配额优化（2026-10-19 加）

起因：微信一个回复窗口只允许连发 10 条，攒满后剩下的消息只能排队等你回话；一屏冒出好几条零碎消息时容易漏看，漏了就等于转发失败。
原则：**只减条数，不动通道**——配额是腾讯侧的，改协议没有意义。

| 位置 | 改动 | 效果 |
| --- | --- | --- |
| `lib/host.js` `#sendWithinLimit` | 长回复不再先发一句「回复较长（N 字），已作为文件发送」，直接发文件；字数挪进文件名 `回复-<字数>字-<时间>.md` | 长回复固定吃 2 条 → 1 条 |
| `dist/core/lib/quota.js` `QUOTA_WARN_AT` | `QUOTA_PER_TOKEN - 2` → `QUOTA_PER_TOKEN - 4`（第 8 条提醒 → 第 6 条） | 提醒本身也占一条，留 4 条余量，回一句之后还能真的接上内容 |
| `lib/host.js` `#flushPending` | 补发积压时在**第一条正文前**加「（补发积压 N 条）」，不单独发提示 | 积压不再静默消失，一眼知道一口气来了几条 |

备份：`_fork-backup/host.js.20261019-before-quota-tune`、`_fork-backup/quota.js.20261019-before-quota-tune`（只留在生效目录，源仓库不备份）。

## 开关（profile 的 cordis.yml，插件 config 段）

```yaml
- id: dsh-wechat-plugin
  name: dsh-wechat-plugin
  config:
    autoStart: true
    relayUnboundApprovals: true   # 桌面会话的审批也推微信（关掉 = 官方行为）
    notifyTurnEnd: true           # 桌面会话完成时推微信（关掉 = 只推审批）
    relayDelayMs: 10000           # 等桌面多少毫秒没回应才推微信
    notifyTurnEndMinMs: 60000     # 完成通知门槛：跑满这么久算工作
    notifyTurnEndMinTools: 5      # 或者工具调用达到这么多次也算工作
```

完成通知的规则：**跑满 60 秒** 或 **工具调用 ≥ 5 次**，满足一条才推。
短问答（几十秒、一两次工具）不会打扰手机。嫌吵就调高这两个数，嫌漏就调低。

## 升级后怎么恢复

DSH 或微信插件升级会把 `node_modules\dsh-wechat-plugin` 覆盖回官方版，改动丢失。
升级完跑一次：

```
pwsh -ExecutionPolicy Bypass -File "E:\大肥鱼人设\dsh-wechat-approvals\restore.ps1"
```

脚本会：
1. 检查已装的插件版本，不是这份就备份旧的、复制 fork 覆盖
2. 检查 cordis.yml 的开关，缺了补上（阈值两个键有代码默认值，可省）
3. 检查 dsh-ops 的 `-ExecutionPolicy Bypass` 补丁，缺了补上

幂等：已经装好时只报告状态，什么都不改。跑完重启 DSH。

## 验证装好了

- 桌面会话里触发一次审批（需要权限的操作），10 秒不点，微信应该收到「🔐 需要你确认」
- 桌面会话跑一个**长任务**（或工具调用 ≥ 5 次），微信应该收到「✅ 任务完成」；随便问个问题则不会收到
- `C:\Users\ireina\.dsh\wechat\boot.log` 里有 `desktop approval answered from WeChat` / `desktop turn finished: notified WeChat`

## 别人怎么装（GitHub 分发）

前提：DSH 桌面版（desktop profile）。

**版本要求**：基于 `dsh-wechat-plugin 0.43.1`。
本 fork 直接用它的内部接口（会话绑定、消息路由、`#ask`），版本差太多可能对不上。

**必须已经有一个微信会话绑定**：
装官方插件 → 扫码登录 → 发一次 `/new 微信`（或 `/switch` 绑定已有会话）。
没有绑定会话的话，审批和通知找不到推送目标，`#boundConversation()` 直接返回失败，
本插件的功能等于不生效——这是最容易漏的一步。

```bash
# 1. 先装官方微信插件（提供登录、二维码、依赖 qrcode 那一套）
#    官方仓库：https://github.com/xcisxc29/dsh-wechat   包名：dsh-wechat-plugin
#    建议锁版本 0.43.1（本 fork 的基线）
dsh plugin --profile desktop add dsh-wechat-plugin@0.43.1

# 2. 再用这个仓库覆盖同名包
dsh plugin --profile desktop add github:lll-77777777/dsh-wechat-approvals
```

然后重启 DSH。

**不用改 cordis.yml**：三个开关在代码里默认就是开的
（`relayUnboundApprovals` / `notifyTurnEnd` 不传 = `true`，`relayDelayMs` 默认 `10000`）。

**顺序不能反**：先官方、后本仓库。反过来的话官方会把本仓库覆盖掉。

**仓库必须是完整包**：`dist/`、`client.js`、`cordis.patch.yml` 都要一起推，这是整包替换，不是打小补丁。

**本仓库不带 dsh-ops 补丁**：那个补丁修的是 PowerShell 执行策略，属于 DSH 自带的另一个包。
如果对方装完 shell 工具报「无法加载文件 …prepare-workspace.ps1，因为在此系统上禁止运行脚本」，
要给 `profiles\desktop\node_modules\dsh-ops\lib\workspace-preparation.js` 里 spawn 的参数加上
`'-ExecutionPolicy', 'Bypass'`（`restore.ps1` 里有现成写法）。

装完验证：桌面会话触发一次需要权限的操作 → 桌面弹卡片 → 10 秒不点 → 微信收到「🔐 需要你确认」。

---

## 官方插件升级后自动恢复（2026-10-18 加）

官方升级会把 `node_modules\dsh-wechat-plugin` 整个换成官方版，fork 就没了。
现在的做法是两层：

**1. 自动（启动文件夹）**

```powershell
powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1
```

往 `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\` 放一个
`DSH-WeChat-Approvals-Restore.vbs`，每次登录后台跑一次 `check-and-restore.ps1`。

- 补丁还在 → 什么都不做，写一行日志
- 被覆盖 → 先做**接口自检**（`lib/interactions.js` 要找得到 `presentApproval`/`parseApprovalReply`，
  `dist/core/lib/state.js` 要找得到 `bindings`，`lib/services.js` 要找得到 `readStreamFrame`）：
  - 通过 → 备份官方版为 `dsh-wechat-plugin.backup-<时间戳>`，再整包复制回来，补 `cordis.yml` 开关和 dsh-ops 补丁
  - 不通过（官方把内部结构改了）→ **拒绝覆盖**（退出码 2），只写日志，等人工适配 fork
- 日志：`restore.log`（在脚本目录，不是 `.dsh` 下——那里会被 ACL 挡住写不进去）
- 卸载：`install-autostart.ps1 -Remove`；想用计划任务：`-Task`（本机 DSH 会话里注册任务被 job object 拒，得在普通窗口跑）

**2. 手动**

`check-and-restore.ps1`（带自检、可换 profile：`-ProfileDir`）或老的 `restore.ps1`。

### 踩过的坑（改脚本别踩回去）

- **vbs 必须是纯 ASCII**：WScript 按系统 ANSI（GBK）读 `.vbs`，文件里直接写中文路径会乱码 → 脚本根本不跑。
  路径用 `ChrW(22823) & ChrW(32933) & ...` 拼；`install-autostart.ps1` 里的 `ToVbsString` 就是干这个的。
- **ps1 必须存成 UTF-8 带 BOM**：Windows PowerShell 5.1 读无 BOM 的 UTF-8 会按 GBK 解中文 → 大面积语法错误。
  `[System.IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding($true)))`。
- **写文件用 .NET 不用 `Set-Content -Encoding utf8`**：5.1 会加 BOM，YAML/JS 解析器可能因此报错。

