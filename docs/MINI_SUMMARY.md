# TicketAgent Mini 功能总结

## 文档信息
- 编译参考：`docs/HAP_AGENT.md`
- 当前重点：演唱会详情页任务识别、共享任务请求、手机端 GUI 抢票任务联动

## 已实现能力

### 1. 演唱会详情页抢票识别
- 页面文件：`entry/src/main/ets/pages/ConcertDetailPage.ets`
- 页面内容已对齐当前需求：
  - 顶部：`***演唱会`
  - 中部：`2026.05.23 19:00 周六`
  - 底部右侧：红色 `抢票` 按钮
  - 抢票按钮左侧：爱心 + `想看`
  - 抢票上方：`3月10日 15:00开抢，仅xx时xx分xx秒`
- `抢票` 按钮点击后通过 `context.openLink(applinkingUrl)` 跳转到元服务，不再使用 `Want/startAbility`
- 页面内输入 `等下帮我抢这张演唱会门票` 后，点击“智能识别抢票任务”会执行：
  1. 当前页全屏截图
  2. 获取当前页 UI 组件树
  3. 保存截图到图库，并额外落盘到应用目录 `files/screenshots/`
  4. 将截图、UI树、用户输入一起发给大模型
  5. 返回结构化任务结果：`taskType`、`title`、`timeText`、`confidence`、`extraInfo`
  6. 同时生成共享任务请求：
     - `requestId`
     - `requestType`
     - `requestDescription`
     - `taskTime`
     - `requestPageUri`

### 2. UI 组件树增强
- 组件树服务：`entry/src/main/ets/pages/mini/MiniUiTreeService.ets`
- 页面级 UI 树注册：`entry/src/main/ets/pages/mini/MiniUiAutomationRegistry.ets`
- 当前行为：
  - 若页面主动注册 UI 树，则优先使用页面真实语义树
  - 若未注册，再回退到窗口级通用树
- 演唱会详情页已注册专用 UI 树，便于识别：
  - 演唱会标题
  - 开抢时间
  - 抢票按钮
  - 输入框

### 3. 多模态任务识别增强
- 任务识别入口：`entry/src/main/ets/pages/mini/MiniLlm.ets`
- 大模型服务：`entry/src/main/ets/pages/mini/MiniLlmService.ets`
- 当前策略：
  - 请求中同时送入 `userText + screenshotBase64 + uiComponentTree`
  - 提示词显式约束识别 `concertTicket/trainTicket/redPacket/taxi/reminder/generic`
  - 对演唱会页面增加后处理归一化：
    - 如果模型误判成 `generic`，但页面/输入明显是抢票场景，会提升为 `concertTicket`
    - 如果标题过于泛化，会优先从 UI 树中提取 `***演唱会`
    - 如果模型漏掉时间，会从 UI 树中的开抢时间/演出时间补全
- 另外新增了抢票执行规划能力：
  - `planTicketTaskExecution(...)`
  - `planTicketTaskExecutionFromScreen(...)`
  - 用于在手机端执行任务时决定下一步是 `click` 还是 `scroll`

### 4. 截图保存增强
- 文件：`entry/src/main/ets/pages/mini/MiniVision.ets`
- 当前策略：
  - 继续使用全屏截图
  - 不再声明 `READ_IMAGEVIDEO` / `WRITE_IMAGEVIDEO`，避免安装时权限授权失败
  - 优先尝试系统相册创建流程
  - 若图库写入失败，会额外备份到应用目录：
    - `context.filesDir/screenshots/screenshot_<timestamp>.png`
- 页面日志会返回：
  - 图库 URI
  - 或 `backup-only=...` 备份路径

### 5. 手机端 GUI 测试页
- 页面文件：`entry/src/main/ets/pages/MobileGuiTestPage.ets`
- Stub 服务：`entry/src/main/ets/pages/mini/MobileGuiStubService.ets`
- 当前页面包含：
  - 点击测试：真实采集 `ClickEvent`，调用 `imitateClick(event)`
  - 长按测试：真实采集触摸参数，计算 `x/y/milliseconds`，调用 `imitateLongPress(...)`
  - 滚动测试：真实采集 `TouchEvent`，调用 `imitateScroll(event)`
  - 输入测试：调用 `imitateInput(text)`，内部先写剪切板，再记录“点击输入框区域 -> 长按 -> 粘贴”
- 额外提供：
  - `requestFocus(targetWindowId: number): boolean`
  - `imitateScrollFromParams(...)`
    - 这是任务执行器内部使用的参数版滚动 helper
    - 原始 `imitateScroll(event: TouchEvent)` 仍然保留给手动测试页使用

### 6. 手机端 GUI 抢票任务联动
- 执行器：`entry/src/main/ets/pages/mini/MobileTicketTaskExecutor.ets`
- 请求存储：`entry/src/main/ets/pages/mini/MiniTaskRequestStore.ets`
- 当前联动链路：
  1. 用户在演唱会详情页点击“智能识别抢票任务”
  2. 页面生成并保存共享任务请求
  3. 用户进入“手机端GUI测试”
  4. 点击“执行抢票任务”
  5. 执行器先跳转回请求页面 URI
  6. 然后按策略进行抢票按钮定位和后续操作

### 7. 抢票定位策略可配置
- `executeRequest(...)` 现已支持策略参数：
  - `uiTreeFirst`
  - `llmFirst`
- 手机端 GUI 测试页上也提供了策略选择器

#### 7.1 `uiTreeFirst`
- 优先本地分析 `uiTree`
- 如果本地已找到按钮并且在屏幕范围内，直接点击
- 如果本地找到按钮但不在当前屏幕内，则上下滑动
- 如果本地仍找不到，再截图并交给大模型做屏幕理解

#### 7.2 `llmFirst`
- 优先把截图 + `uiTree` 一起送给大模型做屏幕理解
- 按大模型建议决定点击还是滑动
- 每轮动作后，再回到本地 `uiTree` 做补充判断

### 8. 抢票按钮定位规则
- 当前不再依赖固定 `targetId`
- 也不再只匹配固定文案 `抢票`
- 本地优先尝试这些文本：
  - `抢票`
  - `立即抢票`
  - `马上抢票`
  - `抢这张票`
  - `立即抢这张票`
- 若本地 `uiTree` 找不到，则再走“截图 + UI树”的大模型屏幕理解回退
- 每轮滑动查找最多 3 次：
  - 若 3 轮后仍未找到，则明确返回“查找失败”

## 当前可直接测试的路径

### 路径 1：演唱会详情页生成请求
1. 打开首页 `演唱会详情页面`
2. 滑到页面底部
3. 在输入框保留或输入：`等下帮我抢这张演唱会门票`
4. 点击 `智能识别抢票任务`
5. 观察日志：
   - 是否完成全屏截图
   - 是否获取到 UI 树
   - 是否完成大模型识别
   - 是否生成 `requestId/requestType/requestDescription/taskTime/requestPageUri`

### 路径 2：手机端 GUI 抢票联动测试
1. 返回首页，打开 `手机端GUI测试`
2. 查看“待执行抢票请求”区域是否已读到上一页生成的请求
3. 选择定位策略：
   - `uiTree优先`
   - `LLM优先`
4. 点击 `执行抢票任务`
5. 观察日志：
   - 是否跳转回请求页面 URI
   - 是否优先命中本地 UI 树
   - 若本地未命中，是否进入截图理解
   - 是否执行 `imitateScroll` 或 `imitateClick`
   - 若连续 3 次仍未找到，是否明确输出“查找失败”

## 编译与运行
- 构建、安装、启动、E2E 统一参考：`docs/HAP_AGENT.md`
- 常用命令：
  - `powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action build`
  - `powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action install -HapPath entry/build/default/outputs/default/entry-default-signed.hap`
  - `powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action launch`
  - `powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action e2e`

## 当前边界
- 当前手机端 GUI 抢票执行仍然是 stub 执行层：
  - `imitateClick(event)`
  - `imitateLongPress(x, y, milliseconds)`
  - `imitateScroll(event)`
  - `imitateInput(text)`
- 但抢票点击位置已经不再固定打桩，而是优先由当前 `uiTree` 解析 `bounds(...)` 后计算中心点。
- 当本地 `uiTree` 无法直接定位时，会再走“截图 + UI树”的大模型屏幕理解回退。
- 图库保存仍受设备系统图库行为影响，但现在即使图库不可见，也会保留应用内备份文件，便于排查。
- 本地命令行构建、签名、安装、启动已跑通；`scripts/hap-agent.ps1` 已固定优先使用 DevEco Studio 自带 JDK。
