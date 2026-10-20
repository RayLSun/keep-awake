# keep-awake

让 AI Agent 长时间工作时不被系统打断：阻止休眠/睡眠、硬盘空闲关闭，可选保持屏幕常亮。
双平台、零依赖、退出自动恢复原状。v1.0

## 原理

| 平台 | 机制 | 需要管理员? |
|---|---|---|
| Windows | `SetThreadExecutionState(ES_CONTINUOUS \| ES_SYSTEM_REQUIRED)`（Win32 官方 API）+ 临时关闭硬盘空闲超时 | 否 |
| macOS | 系统自带 `caffeinate`（-i 防空闲睡眠 -s 防系统睡眠 -m 防硬盘休眠 -d 防息屏） | 否 |

- 不修改电源计划本身，Ctrl+C 或进程退出后自动解除
- 心跳日志：Windows 在 `%LOCALAPPDATA%\keep-awake\keep-awake.log`

## 用法

### Windows 托盘应用（推荐）

双击 `app\dist\keep-awake-tray.exe`（绿色单文件，无需安装）：
- 托盘图标：绿色=保持唤醒中，灰色=已停止
- 右键菜单：开始/停止、屏幕常亮 ✓、防止硬盘休眠 ✓、退出
- 无需管理员权限

重新打包（可选，改代码后）：
```
cd app
python -m PyInstaller --onefile --noconsole --name keep-awake-tray keep_awake_tray.py
```

### Windows 脚本版

双击 `windows\start.bat`（或命令行）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File keep-awake.ps1 [选项]
```

| 选项 | 作用 |
|---|---|
| （无参数） | 交互询问是否保持屏幕常亮 |
| `-KeepDisplay` | 同时保持屏幕常亮（UI 自动化类 Agent 建议） |
| `-NoDisplay` | 不保持屏幕（跳过询问） |
| `-NoDisk` | 不动硬盘空闲超时 |
| `-Minutes N` | N 分钟后自动停止（默认一直运行到 Ctrl+C） |

停止：Ctrl+C，自动恢复一切。

### macOS

```bash
./mac/keep-awake.sh          # 交互询问屏幕
./mac/keep-awake.sh -d       # 保持屏幕常亮
./mac/keep-awake.sh --minutes 60   # 60 分钟后自动停
```

或双击 `mac/KeepAwake.app`（在 Terminal 窗口里运行，Ctrl+C 停止）。
clone 后需要先赋权：`chmod +x mac/keep-awake.sh mac/KeepAwake.app/Contents/MacOS/KeepAwake`

## 验证是否生效

```powershell
# Windows（需要管理员控制台）
powercfg /requests          # SYSTEM: 一行显示 PowerShell 即生效
```

```bash
# macOS
pmset -g assertions | grep -i caffeinate
```

## 已知限制

- Windows：`powercfg /requests` 查看注册状态需要管理员控制台（脚本本身不需要管理员）
- Windows：托盘应用被 taskkill 强杀时硬盘超时不会自动恢复（正常菜单退出/重启后正常退出会恢复）；被强杀后重开应用再正常退出，或手动 `powercfg /change disk-timeout-ac 20` 即可。睡眠阻止本身随进程死亡自动解除
- macOS：`caffeinate -s` 只在接通电源时阻止系统睡眠；电池下由 `-i` 覆盖空闲睡眠
- Windows 休眠（Hibernate）快捷键/合盖动作不受影响，只挡"空闲超时"

## License

MIT
