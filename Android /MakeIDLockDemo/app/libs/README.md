# 供应方 AAR 放置目录

当前目录**尚无最终 AAR**。本次禁止编译/打包，因此未从SDK中间产物拼造交付包。

需由供应方提供同批次、配套版本并按以下名称放入：

| 文件名 | 源码参考版本 |
| --- | --- |
| MkdLockLib.aar | 1.7.19 |
| MkdElectronicKeyLib.aar | 1.0.2 |
| makeid_bleconnectlib_1.1.aar | 1.1 |

`preBuild` 会检查缺失文件并给出明确说明。这不检查二进制的真实版本或兼容性；供应方必须确认：

- 三个AAR真实匹配上述公开接口，完整包含arm64-v8a的JNI依赖与consumer rules。
- 两个业务AAR中的同ABI OpenSSL副本内容一致后，才使用项目的限定文件pickFirsts。
- 修正/关闭SDK实际敏感日志后再外发。旧MkdLockLib日志开关不能完整禁止明文，电子钥匙授权解析也可能输出password/lockSmSecret；App日志脱敏不解决SDK logcat。
- 修正USB绑定未完成时的取消/解绑，以及NFC公开release对Tag/监控线程的释放，见 `docs/SDK交付阻断.md`。
- 记录每份文件SHA-256和实际版本；先在受控设备完成编译/真机验收后再对外提供APK。

不要放入中间`classes.jar`、旧SDK、额外仪表库或同一库多个版本。使用真正合并AAR时需另行调整重复依赖，不能直接混入现有三个文件。
