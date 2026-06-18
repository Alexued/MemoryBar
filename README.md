# 内存管家

一个原生 macOS 状态栏常驻系统资源管理工具。

## 功能

- 状态栏实时显示当前内存占用率。
- 状态栏实时显示当前启动磁盘占用率。
- 点击状态栏项目展开弹窗，显示当前内存占用榜，并支持上下滚动查看更多进程。
- 弹窗可在“内存 / 磁盘”之间切换，磁盘页展示启动磁盘用量和 App 磁盘占用榜。
- 弹窗和详情窗口支持左右滑动切换内存/磁盘，并带有缓入缓出的滑动动画。
- 点击弹窗以外的位置时，弹窗会自动收起。
- 每个进程名称前显示对应 App 或可执行文件图标。
- 每个 App 名称前显示对应应用图标。
- 弹窗内可刷新、退出，也可点击“进入应用查看”打开详细窗口。
- 详细窗口可查看内存进程榜，也可查看 App 名称、占用空间、占整盘比例、版本、Bundle ID 和路径，并支持搜索。

## 运行

```bash
cd "/Users/kaka/Documents/CodeX 2/MemoryBar"
chmod +x scripts/build_app.sh
./scripts/build_app.sh
open "dist/内存管家.app"
```

## 打包成 App

```bash
cd "/Users/kaka/Documents/CodeX 2/MemoryBar"
./scripts/build_app.sh
```

打包后的应用是状态栏应用，默认不显示在 Dock 中。

## 安装到应用程序

```bash
ditto "dist/内存管家.app" "/Applications/内存管家.app"
open "/Applications/内存管家.app"
```
