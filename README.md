# Shaarli MinIO Backup Docker

基于官方 `shaarli/shaarli` 镜像，注入 MinIO 持久化能力，适配 Render Free 休眠场景。

## Render 环境变量

### MinIO（必需的）

| 变量 | 说明 |
|------|------|
| `MINIO_ENDPOINT` | 你的 MinIO 地址 |
| `MINIO_ACCESS_KEY` | |
| `MINIO_SECRET_KEY` | |
| `MINIO_BACKUP_BUCKET` | 备份桶名（默认 `shaarli-backup`） |

### Shaarli

| 变量 | 值 |
|------|-----|
| `SHAARLI_VIRTUAL_HOST` | `https://你的render域名.onrender.com` |

## MinIO 桶

| 桶 | 用途 |
|----|------|
| `shaarli-backup` | SQLite 数据库备份 |

## 工作原理

```
启动 → entrypoint.sh
  ├─ mc 从 MinIO 拉取 datastore.sqlite（本地无数据库时）
  ├─ 后台 12 分钟定时备份
  ├─ 后台 60 秒监测触发文件
  ├─ SIGTERM 时强制备份一次
  └─ exec /init → s6 启动 Nginx + PHP-FPM

新增书签 → 触发文件 → 60 秒内自动备份到 MinIO
```
