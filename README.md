# PiliPod

用 Swift 开发的 Bilibili 客户端

## 适配平台

iOS 26+ (测试平台为iOS27)

## 功能

- [x] 主页
    - [x] App版推荐视频
    - [x] 网页版推荐视频
    - [x] 直播推荐
    - [x] 热门
    - [ ] 分区
    - [ ] 动态
- [ ] 个人空间
    - [x] 投稿
    - [x] 动态
    - [ ] 主页
- [x] 视频播放
    - [x] 点赞/投币/收藏
    - [x] 添加稍后再看
    - [x] 全屏播放
    - [x] 评论
    - [x] 推荐视频
    - [x] 画质切换
    - [x] HDR/杜比视界视频播放
    - [x] CDN线路切换
        - [x] 自动测速并切换CDN
- [x] 直播播放
    - [x] 接收消息
    - [x] 画质切换
    - [ ] 线路切换
    - [ ] 发送信息
- [x] 视频缓存
    - [x] 断点续传
- [x] 弹幕
    - [x] 弹幕显示
    - [x] 等级屏蔽
    - [ ] 发送弹幕
- [x] 搜索
    - [x] 综合搜索
    - [x] 分类搜索
    - [x] 搜索历史
- [x] 设置
    - [x] 推荐流
    - [x] 播放器
    - [x] 音视频
    - [x] 弹幕
    - [x] 缓存管理

## 多账号与无痕模式

在“我的 → 账号”或“设置 → 账号与隐私”中添加账号，并为四类功能分别选择账号或 `0（匿名）`：

| 用途 | 对应功能 |
| --- | --- |
| 主账号 | 个人资料、动态、私信、关注、点赞、投币、收藏和评论 |
| 记录观看 | 观看记录上报、历史列表和自动恢复观看进度；匿名时不上报 |
| 推荐 | App/Web 推荐、相关视频、搜索推荐和直播推荐 |
| 视频取流 | 视频及直播播放认证、字幕、视频预览和缓存下载 |

“快速统一切换”可将四项设为同一个账号。新增账号会成为主账号，其余功能保留原分工。移除账号后，使用该账号的功能自动切换为匿名。

无痕模式不会上报观看记录（包括退出播放时），也不会新增本地搜索历史；关闭后按原账号分工继续记录。已保存的搜索历史不会被删除，主动点赞、收藏等操作仍会使用主账号。无痕模式不代表网络匿名，取流账号仍可用于获取其有权限访问的内容。

登录页支持密码、短信、扫码及 Cookie 四种方式。短信支持选择国际区号、极验验证和发送倒计时；扫码请使用哔哩哔哩客户端扫描并确认，过期后可刷新。Cookie 登录会校验是否有效及 UID 是否一致，但不包含 App 令牌，部分 App 接口可能不可用。

登录凭据、账号分工及无痕开关保存在本设备 Keychain；首次升级会自动迁移原单账号凭据，迁移成功后移除 UserDefaults 中的旧凭据。“账号与隐私”和“关于”页可导入或导出所有账号，兼容 PiliPlus 的 UID 字典 JSON，保留额外 Cookie、访问令牌、刷新令牌，以及 `type` 表示的功能分工（0 主账号、1 记录观看、2 推荐、3 视频取流）。`type: []` 的账号导入后不负责任何功能，可在账号与隐私中选择分工。登录导出文件包含凭据，请妥善保管。

开发分支的 `iOS Build and Tests` 工作流会编译未签名 iOS App、运行模拟器单元测试，并提供 `PiliPod-unsigned` IPA 和 `ios-validation` 诊断附件。安装 IPA 需要自行签名。

## 声明

此项目（PiliPod）是个人为了兴趣与swift学习而开发，仅用于学习和测试，请于下载后24小时内删除。所用API皆从官方网站收集，不提供任何破解内容。

## 致谢

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus/)
- [cilicili](https://github.com/Rone89/cilicili)
- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [MPVKit](https://github.com/mpvkit/MPVKit)

## Star History

<a href="https://www.star-history.com/?repos=BPTPW%2FPiliPod&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=BPTPW/PiliPod&type=date&theme=dark&legend=top-left&sealed_token=KTHjyBFwYKRQlWKuUlCHQ2hShaU-RKRBFdhlT3YsaB3B1X3zIwcxrHvvf5NZCeMIYOPhbGd6Ji6ieVNGAE3UUH3SPQw3ETQt7SJWTsK7BD5kam5WWbqpGPz8YxXUY2GK3VJQwXsft_NtaL-NlLOXKIB8xHyydugJSLhvAuHPod5_fuccXxE_HQL4XFMI" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=BPTPW/PiliPod&type=date&legend=top-left&sealed_token=KTHjyBFwYKRQlWKuUlCHQ2hShaU-RKRBFdhlT3YsaB3B1X3zIwcxrHvvf5NZCeMIYOPhbGd6Ji6ieVNGAE3UUH3SPQw3ETQt7SJWTsK7BD5kam5WWbqpGPz8YxXUY2GK3VJQwXsft_NtaL-NlLOXKIB8xHyydugJSLhvAuHPod5_fuccXxE_HQL4XFMI" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=BPTPW/PiliPod&type=date&legend=top-left&sealed_token=KTHjyBFwYKRQlWKuUlCHQ2hShaU-RKRBFdhlT3YsaB3B1X3zIwcxrHvvf5NZCeMIYOPhbGd6Ji6ieVNGAE3UUH3SPQw3ETQt7SJWTsK7BD5kam5WWbqpGPz8YxXUY2GK3VJQwXsft_NtaL-NlLOXKIB8xHyydugJSLhvAuHPod5_fuccXxE_HQL4XFMI" />
 </picture>
</a>
