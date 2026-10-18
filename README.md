# dsh-wechat-approvals

**给 [DeepSeek Harness](https://github.com/deepseek-ai) 桌面版用的微信插件补丁版（fork）。**

基于官方 `dsh-wechat-plugin@0.43.1` 修改，不是独立插件——它整包替换官方插件，只多做了三件事：

| 能力 | 官方版 | 这个版本 |
| --- | --- | --- |
| 桌面会话要审批时**通知到微信** | 只通知「绑定微信的那个会话」 | 任何桌面会话都推 |
| 微信上**直接批准/拒绝** | 只有绑定会话能 | 桌面会话的审批也能，微信回「允许」就生效 |
| 任务**完成时通知微信** | 没有 | 有（只报干了活的轮次，不刷屏） |
| 双端批准 | — | 桌面卡片照常显示；**10 秒内没人点**才推微信；两边都能批，谁先批算谁 |

手机在兜里、人已经离开电脑时，桌面那边卡在审批上——这个补丁就是为这个场景写的。

---

## 安装

> **前提**：DSH 桌面版（`desktop` profile）、官方微信插件 `0.43.1`、**并且已经绑定了至少一个微信会话**。
> 没绑定会话时，审批和通知找不到推送目标，功能等于不生效（最容易漏的一步）。

```bash
# 1. 先装官方插件（提供登录、扫码、消息通道）
dsh plugin --profile desktop add dsh-wechat-plugin

# 2. 再用本仓库覆盖同名包
dsh plugin --profile desktop add github:lll-77777777/dsh-wechat-approvals

# 3. 重启 DSH
```

也可以直接在 DSH 的「插件 → 添加插件」里粘贴仓库地址。

**顺序不能反**：先官方、后本仓库。反过来的话官方版会把本仓库覆盖掉。

**不用改配置**：三个开关默认就是开的。

---

## 配置（可选）

profile 的 `cordis.yml` 里，`dsh-wechat-plugin` 的 `config` 段：

```yaml
- id: dsh-wechat-plugin
  name: dsh-wechat-plugin
  config:
    autoStart: true
    relayUnboundApprovals: true   # 桌面会话的审批也推微信（关掉 = 官方行为）
    relayDelayMs: 10000           # 等桌面多少毫秒没人回应才推微信
    notifyTurnEnd: true           # 桌面会话完成时推微信（关掉 = 只推审批）
    notifyTurnEndMinMs: 60000     # 完成通知门槛：这一轮跑满这么久算「干活」
    notifyTurnEndMinTools: 5      # 或者工具调用达到这么多次也算「干活」
```

**完成通知的规则**：一轮跑满 **60 秒** 或 工具调用 **≥ 5 次**，满足一条才推。短问答（几秒、一两次工具）不打扰手机。嫌吵调高，嫌漏调低。

---

## ⚠️ 注意事项 / 已知问题

### 1. 「串会话」——微信消息跑到别的 DSH 工作区去了

**现象**：你在 A 工作区干活，手机微信发消息，回复却出现在 B 工作区（通常是 `E:\微信` 这种插件默认工作区）的会话里。

**原因**：一个微信对话同一时间只绑定**一个** DSH 会话。插件的默认工作区来自设置项 `workspacePath`；微信里 `/new`、或已绑定的会话被删除/归档后自动重建时，新会话就落在**默认工作区**。默认工作区不是你现在用的那个，看起来就是「串」了。

**避免办法**：
- 把插件默认工作区（设置页 → 微信 → 工作区路径）改成你常用的那个
- 别在 GUI 里删除/归档已经绑定的会话（删了就会重建到默认工作区）
- 微信里用 `/list` 看会话，`/switch <短id>` 切回来
- 记住：切换会话 = 换工作上下文，不是换一个「频道」

**自检**：微信里发 `/current`，看当前绑定的是哪个会话。

### 2. 微信批完，桌面审批卡片不会自动消失

桌面那张「需要通过」卡片是 DSH 前端画的，插件在后端批完之后**没有 API 能让它收回去**（前端只监听「新请求」，没有「已被别处答完」的事件）。

所以：微信批完 → 工具已经继续执行了 → 桌面上那张卡片还挂着。**回电脑点一下「允许」或按 Esc 收掉即可**，这一点是空操作，不会重复执行、不会重复授权。

### 3. 微信回复窗口有额度：一条入站消息最多回 10 条

微信 ClawBot 的协议规定：**你发一条消息，bot 最多能回 10 条**（审批提示、完成通知都占额度）。额度用完后的通知会**静默失败**。

如果你发现「审批没推过来 / 完成没通知」，先看微信里是不是很久没说过话了——**随便发一条消息**就能刷新窗口，之前积压的通知不会补发。

### 4. Windows 上可能遇到 PowerShell 执行策略问题（与本插件无关）

如果装完后 DSH 里所有 shell 工具都报：

```
无法加载文件 …\dsh-ops\bin\prepare-workspace.ps1，因为在此系统上禁止运行脚本
```

这是 DSH 自带的 `dsh-ops` 包调 PowerShell 时没带 `-ExecutionPolicy Bypass`。修法是给
`profiles\desktop\node_modules\dsh-ops\lib\workspace-preparation.js` 里的 spawn 参数加上：

```js
'-ExecutionPolicy', 'Bypass'
```

仓库里的 `restore.ps1` 包含这段检查与修复（Windows 专用）。

### 5. 升级会覆盖本插件

DSH 或官方微信插件升级时，`node_modules\dsh-wechat-plugin` 会被重新安装成官方版，本插件的改动丢失。

升级后跑一次（Windows）：

```powershell
pwsh -ExecutionPolicy Bypass -File .\restore.ps1
```

脚本是幂等的：检查版本 → 不是本 fork 就备份并覆盖 → 检查 `cordis.yml` 开关 → 检查 `dsh-ops` 补丁。跑完重启 DSH。

### 6. 版本绑定

本 fork 直接用 `dsh-wechat-plugin@0.43.1` 的内部接口（会话绑定、消息路由、审批交互）。官方版本改动大时可能对不上，届时需要跟进适配。

---

## 验证装好了

1. 桌面会话里触发一次需要权限的操作 → 桌面弹审批卡片 → **10 秒不点** → 微信收到「🔐 需要你确认：<工具名>」
2. 微信回「允许」→ 工具继续执行（桌面卡片需手动点掉，见注意事项 2）
3. 桌面跑一个**长任务**（≥60 秒，或 ≥5 次工具调用）→ 微信收到「✅ 任务完成 + 摘要」；随便问个短问题则不会收到
4. 日志核对：`C:\Users\<你>\.dsh\wechat\boot.log` 里有
   `desktop approval answered from WeChat` / `desktop turn finished: notified WeChat`

---

## 改了什么（技术说明）

| 文件 | 改动 |
| --- | --- |
| `lib/host.js` | 未绑定会话的审批转发、双端审批（10 秒窗口 + 撤回）、完成通知（按 agent 空闲判定轮次）、通知去噪、工作区防改名 |
| `lib/services.js` | 读取流帧时识别 `start` 帧（轮次计时锚点） |
| `package.json` | 版本号 `0.43.1-desknotify.1` |
| `cordis.patch.yml` | 默认配置带上全部开关 |

`dist/` 与 `client.js` 是官方包的构建产物原样保留——本仓库是**整包替换**，不是打小补丁，所以推仓必须带上它们。

更细的实现笔记见 [FORK-NOTES.md](FORK-NOTES.md)。

---

## 许可

MIT，继承自上游 [xcisxc29/dsh-wechat](https://github.com/xcisxc29/dsh-wechat)。见 [LICENSE](LICENSE)。
