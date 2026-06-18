# 内存管家

一个原生 macOS 状态栏常驻内存管理工具。

## 功能

- 状态栏实时显示当前内存占用率。
- 点击状态栏项目展开弹窗，显示当前内存占用榜，并支持上下滚动查看更多进程。
- 点击弹窗以外的位置时，弹窗会自动收起。
- 每个进程名称前显示对应 App 或可执行文件图标。
- 弹窗内可刷新、退出，也可点击“进入应用查看”打开详细窗口。
- 详细窗口展示排名、进程名称、PID、内存、占比、CPU 和可执行路径，并支持搜索。

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
