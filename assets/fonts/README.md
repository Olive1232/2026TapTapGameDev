# 中文字体

`noto_sans_sc.ttf` 为 Noto Sans SC 可变字体，来自 [Google Fonts 官方仓库](https://github.com/google/fonts/tree/main/ofl/notosanssc)，按 SIL Open Font License 1.1 使用；许可原文见 `ofl_noto_sans_sc.txt`。

项目默认字体和菜单主题统一使用 `resources/ui/game_font.tres`，字重为 Regular（400）。字体随项目分发，关闭系统字体回退，避免中文显示依赖运行设备安装的字体。启用 MSDF 以兼顾 UI 与世界内标牌缩放。

## 底部像素文字

`fusion_pixel_12px_proportional_zh_hans.otf` 为缝合像素字体的 12px 比例宽度简体中文版本，来自 [TakWolf 官方发行 2026.09.25](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.09.25)，文件未修改。SHA-256：`e84b6d1ab8f2e25084761eb61c88b373bf1fa0b0c5e9b559d5b1d90e4d658c86`。

字体按 SIL Open Font License 1.1 分发，许可见 `ofl_fusion_pixel.txt`，发行包内的上游许可保存在 `licenses/fusion_pixel/`。字体配置为 `resources/ui/pixel_font.tres`，仅供底部文字组件使用；关闭抗锯齿、MSDF、亚像素定位、系统回退与自动过采样，按 24px（12px 的两倍）显示，使用最近邻纹理采样。菜单及世界标牌继续使用原字体。
