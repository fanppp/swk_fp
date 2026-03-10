# HAP Agent（本地自动化脚本）

`scripts/hap-agent.ps1` 用于在本地 Windows 环境中执行 HarmonyOS 应用的自动化流程：

- HAP 编译（`build`）
- HAP 安装（`install`）
- Ability 启动（`launch`）
- 基于 `hdc` 的点击与截图 E2E（`e2e`）
- 一键全流程（`all`）

## 脚本路径

- `scripts/hap-agent.ps1`
- `scripts/e2e-scenario.json`

## 参数说明

```powershell
.
scripts/hap-agent.ps1 \
  [-Action build|install|launch|e2e|all] \
  [-ProjectRoot <path>] \
  [-HdcPath <path-to-hdc.exe>] \
  [-HapPath <path-to-hap>] \
  [-BundleName <bundle-name>] \
  [-AbilityName <ability-name>] \
  [-ScenarioPath <path-to-json>]
```

- `-Action`
  - 支持：`build` / `install` / `launch` / `e2e` / `all`
  - 默认：`all`
- `-ProjectRoot`
  - 工程根目录，默认自动指向脚本上级目录（即仓库根目录）。
- `-HdcPath`
  - 可选手工指定 `hdc.exe`。
  - 未指定时会自动探测：
    1. 系统 `PATH` 中的 `hdc`
    2. 常见 DevEco 安装位置（如 `D:\DevEco Studio\...`、`C:\Program Files\Huawei\DevEco Studio\...`、用户本地 Huawei SDK 目录）
- `-HapPath`
  - 默认：`entry/build/default/outputs/default/entry-default-unsigned.hap`
  - 实际安装时建议显式使用签名包：
    - `entry/build/default/outputs/default/entry-default-signed.hap`
- `-BundleName`
  - 默认：`com.example.ticketagent_fp`
- `-AbilityName`
  - 默认：`EntryAbility`
- `-ScenarioPath`
  - E2E 场景 JSON，默认：`scripts/e2e-scenario.json`

## 构建与执行细节

### Build

`build` 动作执行：

```powershell
hvigorw --mode module -p module=entry assembleHap
```

脚本会优先固定到本机 DevEco Studio 自带 JDK：

```text
D:\Huawei\DevEco Studio\jbr
```

这样可以避免命令行构建时因外部 JDK 不一致导致的签名失败。

### Install

`install` 动作执行：

```powershell
hdc install -r <hapPath>
```

### Launch

`launch` 动作执行：

```powershell
hdc shell "aa force-stop <bundle>"
hdc shell "aa start -a <ability> -b <bundle>"
```

### E2E

`e2e` 动作按场景文件依次执行：

- `tap`：`hdc shell "uitest uiInput click x y"`
- `sleep`：本地 `Start-Sleep`
- `screencap`：
  - 设备端截图：`hdc shell "uitest screenCap -p /data/local/tmp/<name>.png"`
  - 拉取到本地：`hdc file recv /data/local/tmp/<name>.png <artifact-path>`

默认截图输出目录由场景内 `artifactDir` 控制（默认示例为 `artifacts/e2e`）。

## 场景文件格式

`scripts/e2e-scenario.json` 示例：

```json
{
  "artifactDir": "artifacts/e2e",
  "steps": [
    { "type": "screencap", "name": "home_before" },
    { "type": "tap", "x": 640, "y": 1960, "delayMs": 900 },
    { "type": "sleep", "milliseconds": 500 }
  ]
}
```

- `type=tap`：需要 `x/y`，可选 `delayMs`
- `type=sleep`：需要 `milliseconds`（也支持 `delayMs`）
- `type=screencap`：可选 `name` 或 `fileName`

## 常用命令示例

```powershell
# 仅编译
powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action build

# 安装签名包
powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action install `
  -HapPath entry/build/default/outputs/default/entry-default-signed.hap

# 编译 + 安装 + 启动 + E2E
powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action all `
  -HapPath entry/build/default/outputs/default/entry-default-signed.hap

# 仅执行场景化 E2E
powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action e2e

# 指定 hdc 路径与自定义 bundle/ability
powershell -ExecutionPolicy Bypass -File .\scripts\hap-agent.ps1 -Action launch \
  -HdcPath "D:\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" \
  -BundleName "com.example.ticketagent_fp" \
  -AbilityName "EntryAbility"
```

## 错误处理

脚本在以下场景会抛出明确错误并停止执行：

- 找不到 `hdc.exe` 或 `hvigorw`
- 未检测到 `hdc target`
- HAP 文件不存在
- 场景 JSON 不存在/格式错误/steps 为空
- 场景步骤缺少必要字段（如 `tap` 缺少坐标）
- 任一外部命令返回非 0 退出码

